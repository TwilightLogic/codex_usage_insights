## Why

Codex Desktop with ChatGPT OAuth currently does not provide an official daily, monthly, or yearly token usage history or a dollar-cost view for local sessions, even though local session files already contain enough token data to reconstruct these summaries. We need a small standalone project that turns those local records into trustworthy usage reports so users can understand their usage without hidden APIs or manual log parsing.

## What Changes

- Define a standalone usage analytics workflow that reads local Codex session JSONL files and produces daily, monthly, and yearly token summaries.
- Add a reporting model that preserves `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, and `total_tokens` instead of only one rolled-up usage number.
- Add API-equivalent dollar estimation using configurable pricing profiles and clear disclaimers that estimated cost is not an official ChatGPT bill.
- Add spec guidance that explicitly positions the project relative to tools such as `ccusage`, `codex-ratelimit`, and SessionWatcher so the first version stays focused on the uncovered gap.
- Keep the scope outside the current repository runtime: this change creates planning artifacts for a future standalone project and does not modify application behavior in this workspace.

## Capabilities

### New Capabilities
- `codex-usage-analytics`: Import local Codex session usage data, aggregate it by reporting period, and estimate API-equivalent dollar cost with transparent assumptions and reporting caveats.

### Modified Capabilities

## Impact

Affected areas are the OpenSpec planning artifacts for a future standalone project, the parsing rules for `~/.codex/sessions/**/*.jsonl`, and any future CLI or local dashboard that renders the reports. There are no runtime changes in the current repository, no required backend API integrations for the first version, and no new dependency requirements here beyond these planning files.
