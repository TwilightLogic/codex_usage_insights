import argparse
from pathlib import Path
from typing import Optional

from .aggregation import resolve_timezone
from .parser import default_input_path, scan_sessions
from .pricing import load_pricing_profiles, select_pricing_profile
from .reporting import build_report, render_json_report, render_text_report


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Reconstruct local Codex usage from session logs.",
    )
    parser.add_argument(
        "--input-path",
        default=str(default_input_path()),
        help="Path to the root Codex session directory (default: ~/.codex/sessions).",
    )
    parser.add_argument(
        "--period",
        choices=["day", "month", "year"],
        default="day",
        help="Calendar period to group by.",
    )
    parser.add_argument(
        "--timezone",
        help="IANA timezone name used for grouping. Defaults to the host system timezone.",
    )
    parser.add_argument(
        "--pricing-profile",
        help="Name of a built-in or custom pricing profile.",
    )
    parser.add_argument(
        "--pricing-config",
        help="Path to a JSON file that adds or overrides pricing profiles.",
    )
    parser.add_argument(
        "--format",
        choices=["table", "json"],
        default="table",
        help="Output format.",
    )
    return parser


def main(argv: Optional[list] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        tzinfo, timezone_label = resolve_timezone(args.timezone)
    except ValueError as exc:
        parser.error(str(exc))

    input_path = Path(args.input_path).expanduser()
    scan_result = scan_sessions(input_path)

    pricing_profiles, pricing_warnings = load_pricing_profiles(
        Path(args.pricing_config).expanduser() if args.pricing_config else None
    )
    selected_profile, selection_warning = select_pricing_profile(pricing_profiles, args.pricing_profile)

    extra_warnings = list(pricing_warnings)
    if selection_warning is not None:
        extra_warnings.append(selection_warning)

    report = build_report(
        scan_result=scan_result,
        input_path=str(input_path),
        period=args.period,
        timezone_label=timezone_label,
        tzinfo=tzinfo,
        profile=selected_profile,
        extra_warnings=extra_warnings,
    )

    if args.format == "json":
        print(render_json_report(report))
    else:
        print(render_text_report(report))

    return 0
