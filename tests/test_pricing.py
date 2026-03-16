from decimal import Decimal
import unittest

from codex_usage_analytics.models import PricingProfile, TokenUsage
from codex_usage_analytics.pricing import derive_billable_token_counts, estimate_usage_cost


class PricingTests(unittest.TestCase):
    def make_profile(self) -> PricingProfile:
        return PricingProfile(
            name="test-profile",
            description="Test profile",
            source="tests",
            rates_per_million={
                "input_tokens": Decimal("2.5"),
                "cached_input_tokens": Decimal("0.25"),
                "output_tokens": Decimal("15.0"),
            },
        )

    def test_subset_billing_uses_uncached_input_and_output_once(self) -> None:
        usage = TokenUsage(
            input_tokens=120,
            cached_input_tokens=80,
            output_tokens=20,
            reasoning_output_tokens=10,
            total_tokens=140,
        )

        self.assertEqual(
            derive_billable_token_counts(usage),
            {
                "input_tokens": 40,
                "cached_input_tokens": 80,
                "output_tokens": 20,
            },
        )
        self.assertEqual(estimate_usage_cost(usage, self.make_profile()), Decimal("0.000420"))

    def test_cached_input_is_clamped_to_total_input(self) -> None:
        usage = TokenUsage(
            input_tokens=50,
            cached_input_tokens=80,
            output_tokens=20,
            reasoning_output_tokens=5,
            total_tokens=70,
        )

        self.assertEqual(
            derive_billable_token_counts(usage),
            {
                "input_tokens": 0,
                "cached_input_tokens": 50,
                "output_tokens": 20,
            },
        )


if __name__ == "__main__":
    unittest.main()
