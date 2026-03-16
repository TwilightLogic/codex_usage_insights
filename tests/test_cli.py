import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


class CliTests(unittest.TestCase):
    def test_table_output_includes_caveat_and_summary(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "codex_usage_analytics",
                "--input-path",
                "tests/fixtures/sessions",
                "--period",
                "day",
            ],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertIn("📊 Local Codex Usage Report", result.stdout)
        self.assertIn("🗂 Report Scope", result.stdout)
        self.assertIn("💵 Cost Estimate", result.stdout)
        self.assertIn("🧮 Token Totals", result.stdout)
        self.assertIn("• Uncached input:", result.stdout)
        self.assertIn("📅 Period Buckets", result.stdout)
        self.assertIn("⚠ Warnings", result.stdout)

    def test_json_output_contains_machine_readable_fields(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "codex_usage_analytics",
                "--input-path",
                "tests/fixtures/sessions",
                "--period",
                "month",
                "--format",
                "json",
                "--pricing-profile",
                "gpt-5.4",
            ],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

        payload = json.loads(result.stdout)
        self.assertEqual(payload["period"], "month")
        self.assertIn("buckets", payload)
        self.assertIn("warnings", payload)
        self.assertEqual(payload["pricing"]["profile_name"], "gpt-5.4")
        self.assertIn("uncached_input=", payload["pricing"]["formula"])


if __name__ == "__main__":
    unittest.main()
