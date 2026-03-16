import json
from decimal import Decimal
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .models import BILLABLE_TOKEN_FIELDS, PricingProfile, ScanWarning, TokenUsage

BUILTIN_PROFILES_PATH = Path(__file__).with_name("pricing_profiles.json")


def parse_decimal(value: object) -> Decimal:
    return Decimal(str(value))


def load_pricing_profiles(config_path: Optional[Path] = None) -> Tuple[Dict[str, PricingProfile], List[ScanWarning]]:
    profiles: Dict[str, PricingProfile] = {}
    warnings: List[ScanWarning] = []

    for source_path in [BUILTIN_PROFILES_PATH, config_path]:
        if source_path is None:
            continue
        source_path = source_path.expanduser()
        if not source_path.exists():
            warnings.append(
                ScanWarning(
                    code="pricing_config_missing",
                    message="Pricing config file does not exist.",
                    path=str(source_path),
                )
            )
            continue

        try:
            with source_path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except (OSError, json.JSONDecodeError) as exc:
            warnings.append(
                ScanWarning(
                    code="pricing_config_invalid",
                    message="Failed to load pricing config: {message}".format(message=str(exc)),
                    path=str(source_path),
                )
            )
            continue

        raw_profiles = payload.get("profiles", [])
        if not isinstance(raw_profiles, list):
            warnings.append(
                ScanWarning(
                    code="pricing_config_invalid",
                    message="Pricing config must contain a 'profiles' list.",
                    path=str(source_path),
                )
            )
            continue

        for raw_profile in raw_profiles:
            if not isinstance(raw_profile, dict) or "name" not in raw_profile:
                continue

            raw_rates = raw_profile.get("rates_per_million", {})
            if not isinstance(raw_rates, dict):
                continue

            rates = {}
            for field_name in BILLABLE_TOKEN_FIELDS:
                rates[field_name] = parse_decimal(raw_rates.get(field_name, 0))

            profile = PricingProfile(
                name=str(raw_profile["name"]),
                description=str(raw_profile.get("description", "")),
                reviewed_on=str(raw_profile.get("reviewed_on")) if raw_profile.get("reviewed_on") else None,
                source=str(source_path),
                rates_per_million=rates,
            )
            profiles[profile.name] = profile

    return profiles, warnings


def select_pricing_profile(
    profiles: Dict[str, PricingProfile],
    profile_name: Optional[str],
) -> Tuple[Optional[PricingProfile], Optional[ScanWarning]]:
    if not profile_name:
        return None, None
    profile = profiles.get(profile_name)
    if profile is not None:
        return profile, None
    return (
        None,
        ScanWarning(
            code="pricing_profile_missing",
            message="Pricing profile '{name}' was not found. Cost estimate is unavailable.".format(
                name=profile_name
            ),
            path=profile_name,
        ),
    )


def derive_billable_token_counts(usage: TokenUsage) -> Dict[str, int]:
    # Cached input is reported as a subset of total input, so we split input
    # into uncached and cached portions instead of charging both in full.
    total_input_tokens = max(usage.input_tokens, 0)
    cached_input_tokens = min(max(usage.cached_input_tokens, 0), total_input_tokens)
    uncached_input_tokens = max(total_input_tokens - cached_input_tokens, 0)

    return {
        "input_tokens": uncached_input_tokens,
        "cached_input_tokens": cached_input_tokens,
        "output_tokens": max(usage.output_tokens, 0),
    }


def estimate_usage_cost(usage: TokenUsage, profile: PricingProfile) -> Decimal:
    total = Decimal("0")
    for field_name, token_count in derive_billable_token_counts(usage).items():
        rate = profile.rate_for(field_name)
        total += (Decimal(token_count) / Decimal("1000000")) * rate
    return total
