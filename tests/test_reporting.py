import json
import unittest

from codex_usage_analytics.aggregation import resolve_timezone
from codex_usage_analytics.parser import scan_sessions
from codex_usage_analytics.pricing import load_pricing_profiles, select_pricing_profile
from codex_usage_analytics.reporting import build_report, render_text_report, report_to_dict

from tests.helpers import make_fixture_directory


class ReportingTests(unittest.TestCase):
    def test_timezone_boundary_groups_into_local_calendar_bucket(self) -> None:
        temp_dir, temp_path = make_fixture_directory(["session_timezone_boundary.jsonl"])
        self.addCleanup(temp_dir.cleanup)

        scan_result = scan_sessions(temp_path)
        tzinfo, timezone_label = resolve_timezone("Asia/Shanghai")
        report = build_report(
            scan_result=scan_result,
            input_path=str(temp_path),
            period="day",
            timezone_label=timezone_label,
            tzinfo=tzinfo,
        )

        self.assertEqual(len(report.buckets), 1)
        self.assertEqual(report.buckets[0].label, "2026-01-01")

    def test_best_usage_snapshot_controls_local_day_bucket(self) -> None:
        temp_dir, temp_path = make_fixture_directory(["session_usage_after_midnight_local.jsonl"])
        self.addCleanup(temp_dir.cleanup)

        scan_result = scan_sessions(temp_path)
        tzinfo, timezone_label = resolve_timezone("Asia/Shanghai")
        report = build_report(
            scan_result=scan_result,
            input_path=str(temp_path),
            period="day",
            timezone_label=timezone_label,
            tzinfo=tzinfo,
        )

        self.assertEqual(len(report.buckets), 1)
        self.assertEqual(report.buckets[0].label, "2026-03-16")
        self.assertEqual(report.buckets[0].usage.total_tokens, 140)

    def test_missing_pricing_profile_keeps_tokens_and_marks_cost_unavailable(self) -> None:
        temp_dir, temp_path = make_fixture_directory(["session_with_growth.jsonl"])
        self.addCleanup(temp_dir.cleanup)

        scan_result = scan_sessions(temp_path)
        tzinfo, timezone_label = resolve_timezone("UTC")
        profiles, warnings = load_pricing_profiles()
        _, selection_warning = select_pricing_profile(profiles, "missing-profile")
        if selection_warning is not None:
            warnings.append(selection_warning)

        report = build_report(
            scan_result=scan_result,
            input_path=str(temp_path),
            period="day",
            timezone_label=timezone_label,
            tzinfo=tzinfo,
            extra_warnings=warnings,
        )

        self.assertEqual(report.summary_usage.total_tokens, 140)
        self.assertEqual(report.cost_estimate.status, "unavailable")
        rendered = render_text_report(report)
        self.assertIn("💵 Cost Estimate", rendered)
        self.assertIn("• Status: unavailable", rendered)
        self.assertIn("• Reason: Pricing profile 'missing-profile' was not found. Cost estimate is unavailable.", rendered)
        self.assertIn("⚠ Warnings", rendered)
        self.assertIn("not an official ChatGPT invoice", rendered)

    def test_text_report_uses_sections_and_explicit_uncached_input(self) -> None:
        temp_dir, temp_path = make_fixture_directory(["session_with_growth.jsonl", "session_missing_usage.jsonl"])
        self.addCleanup(temp_dir.cleanup)

        scan_result = scan_sessions(temp_path)
        tzinfo, timezone_label = resolve_timezone("UTC")
        profiles, warnings = load_pricing_profiles()
        profile, selection_warning = select_pricing_profile(profiles, "gpt-5.4")
        if selection_warning is not None:
            warnings.append(selection_warning)

        report = build_report(
            scan_result=scan_result,
            input_path=str(temp_path),
            period="day",
            timezone_label=timezone_label,
            tzinfo=tzinfo,
            profile=profile,
            extra_warnings=warnings,
        )

        rendered = render_text_report(report)
        self.assertIn("📊 Local Codex Usage Report", rendered)
        self.assertIn("🗂 Report Scope", rendered)
        self.assertIn("📁 Scan Summary", rendered)
        self.assertIn("💵 Cost Estimate", rendered)
        self.assertIn("🧮 Token Totals", rendered)
        self.assertIn("📅 Period Buckets", rendered)
        self.assertIn("⚠ Warnings", rendered)
        self.assertIn("• Uncached input: 40", rendered)
        self.assertIn("• Cached input: 80", rendered)
        self.assertIn("• Formula: uncached_input=$2.5/1M, cached_input=$0.25/1M, output=$15.0/1M", rendered)
        self.assertIn("• [missing_usage_snapshot]", rendered)

    def test_json_report_includes_pricing_metadata_and_bucket_costs(self) -> None:
        temp_dir, temp_path = make_fixture_directory(["session_with_growth.jsonl"])
        self.addCleanup(temp_dir.cleanup)

        scan_result = scan_sessions(temp_path)
        tzinfo, timezone_label = resolve_timezone("UTC")
        profiles, warnings = load_pricing_profiles()
        profile, selection_warning = select_pricing_profile(profiles, "gpt-5.4")
        if selection_warning is not None:
            warnings.append(selection_warning)

        report = build_report(
            scan_result=scan_result,
            input_path=str(temp_path),
            period="day",
            timezone_label=timezone_label,
            tzinfo=tzinfo,
            profile=profile,
            extra_warnings=warnings,
        )

        payload = report_to_dict(report)
        self.assertEqual(payload["pricing"]["status"], "estimated")
        self.assertEqual(payload["pricing"]["profile_name"], "gpt-5.4")
        self.assertEqual(payload["pricing"]["formula"], "uncached_input=$2.5/1M, cached_input=$0.25/1M, output=$15.0/1M")
        self.assertEqual(len(payload["buckets"]), 1)
        self.assertIsNotNone(payload["buckets"][0]["estimated_cost_usd"])
        self.assertAlmostEqual(payload["buckets"][0]["estimated_cost_usd"], 0.00042)
        json.dumps(payload)


if __name__ == "__main__":
    unittest.main()
