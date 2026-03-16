from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .models import PeriodBucket, SessionRecord, TokenUsage


def resolve_timezone(timezone_name: Optional[str]) -> Tuple[timezone, str]:
    if timezone_name:
        try:
            zone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Unknown timezone: {name}".format(name=timezone_name)) from exc
        return zone, timezone_name

    local_now = datetime.now().astimezone()
    local_zone = local_now.tzinfo or timezone.utc
    label = getattr(local_zone, "key", None) or local_now.tzname() or "local"
    return local_zone, label


def bucket_parts(local_timestamp: datetime, period: str) -> Tuple[str, str, str]:
    if period == "day":
        key = local_timestamp.strftime("%Y-%m-%d")
        return key, key, key
    if period == "month":
        key = local_timestamp.strftime("%Y-%m")
        return key, key, "{year:04d}-{month:02d}-01".format(
            year=local_timestamp.year,
            month=local_timestamp.month,
        )
    if period == "year":
        key = local_timestamp.strftime("%Y")
        return key, key, "{year:04d}-01-01".format(year=local_timestamp.year)
    raise ValueError("Unsupported period: {period}".format(period=period))


def aggregate_records(records: List[SessionRecord], period: str, tzinfo: timezone) -> List[PeriodBucket]:
    buckets: Dict[str, PeriodBucket] = {}

    for record in sorted(records, key=lambda item: item.timestamp_utc):
        local_timestamp = record.timestamp_utc.astimezone(tzinfo)
        key, label, period_start = bucket_parts(local_timestamp, period)
        bucket = buckets.get(key)
        if bucket is None:
            bucket = PeriodBucket(key=key, label=label, period_start=period_start)
            buckets[key] = bucket

        bucket.session_count += 1
        bucket.usage = bucket.usage.add(record.usage)

    return [buckets[key] for key in sorted(buckets.keys())]


def summarize_buckets(buckets: List[PeriodBucket]) -> TokenUsage:
    summary = TokenUsage()
    for bucket in buckets:
        summary = summary.add(bucket.usage)
    return summary
