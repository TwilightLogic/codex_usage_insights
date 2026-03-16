from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal
from typing import Dict, List, Optional

TOKEN_FIELDS = (
    "input_tokens",
    "cached_input_tokens",
    "output_tokens",
    "reasoning_output_tokens",
    "total_tokens",
)

BILLABLE_TOKEN_FIELDS = (
    "input_tokens",
    "cached_input_tokens",
    "output_tokens",
)


@dataclass(frozen=True)
class TokenUsage:
    input_tokens: int = 0
    cached_input_tokens: int = 0
    output_tokens: int = 0
    reasoning_output_tokens: int = 0
    total_tokens: int = 0

    @classmethod
    def from_mapping(cls, payload: Dict[str, object]) -> "TokenUsage":
        values = {}
        for field_name in TOKEN_FIELDS:
            value = payload.get(field_name, 0)
            values[field_name] = int(value or 0)
        return cls(**values)

    def is_nonzero(self) -> bool:
        return any(getattr(self, field_name) > 0 for field_name in TOKEN_FIELDS)

    def add(self, other: "TokenUsage") -> "TokenUsage":
        values = {}
        for field_name in TOKEN_FIELDS:
            values[field_name] = getattr(self, field_name) + getattr(other, field_name)
        return TokenUsage(**values)

    def to_dict(self) -> Dict[str, int]:
        return {field_name: getattr(self, field_name) for field_name in TOKEN_FIELDS}


@dataclass(frozen=True)
class ScanWarning:
    code: str
    message: str
    path: str
    line: Optional[int] = None

    def to_dict(self) -> Dict[str, object]:
        data = {"code": self.code, "message": self.message, "path": self.path}
        if self.line is not None:
            data["line"] = self.line
        return data


@dataclass(frozen=True)
class SessionRecord:
    session_id: str
    source_path: str
    timestamp_utc: datetime
    usage: TokenUsage


@dataclass(frozen=True)
class ScanResult:
    records: List[SessionRecord]
    warnings: List[ScanWarning]
    scanned_files: int
    excluded_files: int


@dataclass(frozen=True)
class PricingProfile:
    name: str
    description: str
    source: str
    rates_per_million: Dict[str, Decimal]
    reviewed_on: Optional[str] = None

    def rate_for(self, token_field: str) -> Decimal:
        return self.rates_per_million.get(token_field, Decimal("0"))

    def formula(self) -> str:
        return (
            "uncached_input=${input}/1M, cached_input=${cached}/1M, "
            "output=${output}/1M"
        ).format(
            input=self.rate_for("input_tokens"),
            cached=self.rate_for("cached_input_tokens"),
            output=self.rate_for("output_tokens"),
        )


@dataclass(frozen=True)
class CostEstimate:
    status: str
    amount_usd: Optional[Decimal]
    profile_name: Optional[str]
    formula: Optional[str]
    reason: Optional[str] = None


@dataclass
class PeriodBucket:
    key: str
    label: str
    period_start: str
    session_count: int = 0
    usage: TokenUsage = field(default_factory=TokenUsage)
    estimated_cost_usd: Optional[Decimal] = None


@dataclass(frozen=True)
class Report:
    period: str
    timezone: str
    input_path: str
    scanned_files: int
    counted_sessions: int
    excluded_files: int
    summary_usage: TokenUsage
    buckets: List[PeriodBucket]
    warnings: List[ScanWarning]
    cost_estimate: CostEstimate
    caveat: str
