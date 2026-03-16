import unittest

from codex_usage_analytics.parser import parse_session_file, scan_sessions

from tests.helpers import make_fixture_directory


class ParserTests(unittest.TestCase):
    def test_repeated_snapshots_use_highest_total_once(self) -> None:
        temp_dir, temp_path = make_fixture_directory(["session_with_growth.jsonl"])
        self.addCleanup(temp_dir.cleanup)

        result = scan_sessions(temp_path)

        self.assertEqual(result.scanned_files, 1)
        self.assertEqual(result.excluded_files, 0)
        self.assertEqual(len(result.records), 1)
        record = result.records[0]
        self.assertEqual(record.usage.input_tokens, 120)
        self.assertEqual(record.usage.cached_input_tokens, 80)
        self.assertEqual(record.usage.output_tokens, 20)
        self.assertEqual(record.usage.reasoning_output_tokens, 10)
        self.assertEqual(record.usage.total_tokens, 140)

    def test_skips_files_without_usable_snapshots(self) -> None:
        temp_dir, temp_path = make_fixture_directory(
            [
                "session_with_growth.jsonl",
                "session_rate_limit_only.jsonl",
                "session_missing_usage.jsonl",
            ]
        )
        self.addCleanup(temp_dir.cleanup)

        result = scan_sessions(temp_path)

        self.assertEqual(result.scanned_files, 3)
        self.assertEqual(result.excluded_files, 2)
        self.assertEqual(len(result.records), 1)
        warning_codes = sorted(warning.code for warning in result.warnings)
        self.assertEqual(warning_codes.count("missing_usage_snapshot"), 2)

    def test_invalid_json_line_is_reported_but_file_can_still_count(self) -> None:
        temp_dir, temp_path = make_fixture_directory(["session_with_invalid_tail.jsonl"])
        self.addCleanup(temp_dir.cleanup)

        record, warnings = parse_session_file(temp_path / "session_with_invalid_tail.jsonl")
        self.assertIsNotNone(record)
        self.assertTrue(any(warning.code == "invalid_json_line" for warning in warnings))

    def test_canonical_timestamp_prefers_selected_usage_snapshot_time(self) -> None:
        temp_dir, temp_path = make_fixture_directory(["session_usage_after_midnight_local.jsonl"])
        self.addCleanup(temp_dir.cleanup)

        record, warnings = parse_session_file(temp_path / "session_usage_after_midnight_local.jsonl")

        self.assertIsNotNone(record)
        assert record is not None
        self.assertEqual(record.timestamp_utc.isoformat(), "2026-03-15T16:05:00+00:00")
        self.assertEqual(warnings, [])


if __name__ == "__main__":
    unittest.main()
