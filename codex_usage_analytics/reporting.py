import json
from decimal import Decimal
from typing import List, Optional

from .aggregation import aggregate_records, summarize_buckets
from .models import CostEstimate, PeriodBucket, PricingProfile, Report, ScanResult, ScanWarning
from .pricing import derive_billable_token_counts, estimate_usage_cost

CAVEAT = (
    "This report is reconstructed from local Codex logs. Any dollar amount is an "
    "API-equivalent estimate, not an official ChatGPT invoice."
)


def build_report(
    scan_result: ScanResult,
    input_path: str,
    period: str,
    timezone_label: str,
    tzinfo,
    profile: Optional[PricingProfile] = None,
    extra_warnings: Optional[List[ScanWarning]] = None,
) -> Report:
    buckets = aggregate_records(scan_result.records, period, tzinfo)

    total_cost: Optional[Decimal] = None
    if profile is not None:
        running_cost = Decimal("0")
        for bucket in buckets:
            bucket.estimated_cost_usd = estimate_usage_cost(bucket.usage, profile)
            running_cost += bucket.estimated_cost_usd
        total_cost = running_cost

    warnings = list(scan_result.warnings)
    if extra_warnings:
        warnings.extend(extra_warnings)

    if profile is not None:
        cost_estimate = CostEstimate(
            status="estimated",
            amount_usd=total_cost,
            profile_name=profile.name,
            formula=profile.formula(),
        )
    else:
        reason = "No pricing profile selected."
        if extra_warnings:
            reason = extra_warnings[-1].message
        cost_estimate = CostEstimate(
            status="unavailable",
            amount_usd=None,
            profile_name=None,
            formula=None,
            reason=reason,
        )

    return Report(
        period=period,
        timezone=timezone_label,
        input_path=input_path,
        scanned_files=scan_result.scanned_files,
        counted_sessions=len(scan_result.records),
        excluded_files=scan_result.excluded_files,
        summary_usage=summarize_buckets(buckets),
        buckets=buckets,
        warnings=warnings,
        cost_estimate=cost_estimate,
        caveat=CAVEAT,
    )


def format_number(value: int) -> str:
    return "{value:,}".format(value=value)


def format_money(value: Optional[Decimal]) -> str:
    if value is None:
        return "n/a"
    return "${amount:.6f}".format(amount=float(value))


def render_section(title: str, lines: List[str]) -> List[str]:
    rendered = [title]
    rendered.extend(lines)
    rendered.append("")
    return rendered


def render_table(buckets: List[PeriodBucket]) -> str:
    headers = [
        "Bucket",
        "Sessions",
        "Input",
        "Cached In",
        "Output",
        "Reasoning",
        "Total",
        "Est. USD",
    ]
    rows = []
    for bucket in buckets:
        rows.append(
            [
                bucket.label,
                str(bucket.session_count),
                format_number(bucket.usage.input_tokens),
                format_number(bucket.usage.cached_input_tokens),
                format_number(bucket.usage.output_tokens),
                format_number(bucket.usage.reasoning_output_tokens),
                format_number(bucket.usage.total_tokens),
                format_money(bucket.estimated_cost_usd),
            ]
        )

    if not rows:
        rows.append(["(no data)", "0", "0", "0", "0", "0", "0", "n/a"])

    widths = [len(header) for header in headers]
    for row in rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(value))

    rendered = ["  ".join(header.ljust(widths[index]) for index, header in enumerate(headers))]
    rendered.append("  ".join("-" * width for width in widths))
    for row in rows:
        rendered.append("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)))
    return "\n".join(rendered)


def render_text_report(report: Report) -> str:
    summary_billable_tokens = derive_billable_token_counts(report.summary_usage)
    pricing_status = (
        "estimated via {name} ({amount})".format(
            name=report.cost_estimate.profile_name,
            amount=format_money(report.cost_estimate.amount_usd),
        )
        if report.cost_estimate.status == "estimated"
        else "unavailable"
    )

    lines = ["📊 Local Codex Usage Report", ""]
    lines.extend(
        render_section(
            "🗂 Report Scope",
            [
                "• Period: {period}".format(period=report.period),
                "• Timezone: {timezone}".format(timezone=report.timezone),
                "• Input path: {path}".format(path=report.input_path),
            ],
        )
    )
    lines.extend(
        render_section(
            "📁 Scan Summary",
            [
                "• Scanned files: {count}".format(count=report.scanned_files),
                "• Counted sessions: {count}".format(count=report.counted_sessions),
                "• Excluded files: {count}".format(count=report.excluded_files),
            ],
        )
    )

    pricing_lines = [
        "• Status: {status}".format(status=pricing_status),
        "• Caveat: {caveat}".format(caveat=report.caveat),
    ]
    if report.cost_estimate.formula:
        pricing_lines.insert(
            1,
            "• Formula: {formula}".format(formula=report.cost_estimate.formula),
        )
    elif report.cost_estimate.reason:
        pricing_lines.insert(
            1,
            "• Reason: {reason}".format(reason=report.cost_estimate.reason),
        )
    lines.extend(render_section("💵 Cost Estimate", pricing_lines))

    lines.extend(
        render_section(
            "🧮 Token Totals",
            [
                "• Input: {input}".format(input=format_number(report.summary_usage.input_tokens)),
                "• Uncached input: {input}".format(
                    input=format_number(summary_billable_tokens["input_tokens"])
                ),
                "• Cached input: {cached}".format(
                    cached=format_number(report.summary_usage.cached_input_tokens)
                ),
                "• Output: {output}".format(output=format_number(report.summary_usage.output_tokens)),
                "• Reasoning: {reasoning}".format(
                    reasoning=format_number(report.summary_usage.reasoning_output_tokens)
                ),
                "• Total: {total}".format(total=format_number(report.summary_usage.total_tokens)),
            ],
        )
    )

    lines.extend(render_section("📅 Period Buckets", [render_table(report.buckets)]))

    if report.warnings:
        warning_lines = []
        for warning in report.warnings:
            location = warning.path
            if warning.line is not None:
                location = "{path}:{line}".format(path=warning.path, line=warning.line)
            warning_lines.append(
                "• [{code}] {location}: {message}".format(
                    code=warning.code,
                    location=location,
                    message=warning.message,
                )
            )
        lines.extend(render_section("⚠ Warnings", warning_lines))

    if lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def report_to_dict(report: Report) -> dict:
    return {
        "period": report.period,
        "timezone": report.timezone,
        "input_path": report.input_path,
        "scanned_files": report.scanned_files,
        "counted_sessions": report.counted_sessions,
        "excluded_files": report.excluded_files,
        "caveat": report.caveat,
        "summary_usage": report.summary_usage.to_dict(),
        "pricing": {
            "status": report.cost_estimate.status,
            "profile_name": report.cost_estimate.profile_name,
            "formula": report.cost_estimate.formula,
            "amount_usd": float(report.cost_estimate.amount_usd)
            if report.cost_estimate.amount_usd is not None
            else None,
            "reason": report.cost_estimate.reason,
        },
        "warnings": [warning.to_dict() for warning in report.warnings],
        "buckets": [
            {
                "key": bucket.key,
                "label": bucket.label,
                "period_start": bucket.period_start,
                "session_count": bucket.session_count,
                "usage": bucket.usage.to_dict(),
                "estimated_cost_usd": float(bucket.estimated_cost_usd)
                if bucket.estimated_cost_usd is not None
                else None,
            }
            for bucket in report.buckets
        ],
    }


def render_json_report(report: Report) -> str:
    return json.dumps(report_to_dict(report), indent=2, sort_keys=False)
