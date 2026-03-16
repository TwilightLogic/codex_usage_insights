## 1. Establish the reporting core

- [ ] 1.1 Create the project or module skeleton for a local Codex usage reporting tool with separate parser, aggregator, pricing, and presentation layers.
- [ ] 1.2 Add fixture session files and test helpers that cover usable `token_count` events, rate-limit-only events, and missing-usage files.

## 2. Implement local session parsing

- [ ] 2.1 Implement JSONL scanning for `~/.codex/sessions/**/*.jsonl` with configurable input path and timezone-aware timestamp handling.
- [ ] 2.2 Convert each usable session file into one canonical usage record while skipping unusable files and collecting parser warnings.
- [ ] 2.3 Add tests that verify repeated `token_count` snapshots do not double-count a single session and that skipped files are reported correctly.

## 3. Build aggregation and pricing

- [ ] 3.1 Implement day, month, and year grouping over canonical session usage records with per-bucket totals and session counts.
- [ ] 3.2 Implement pricing profile loading and API-equivalent cost estimation for input, cached input, and output-style token buckets.
- [ ] 3.3 Add tests for timezone boundaries, missing pricing profiles, and cost-estimate disclaimers.

## 4. Expose report outputs

- [ ] 4.1 Implement a default human-readable CLI report that shows reporting periods, timezone, token totals, warnings, and estimated cost status.
- [ ] 4.2 Implement machine-readable JSON output that includes bucket totals, session counts, warnings, pricing metadata, and estimated cost fields.

## 5. Harden UX and documentation

- [ ] 5.1 Add clear user-facing caveats that local ChatGPT-authenticated Codex reports are reconstructed from local logs and are not official billing statements.
- [ ] 5.2 Document pricing profile configuration, supported report periods, and known limitations compared with tools such as `ccusage`, `codex-ratelimit`, and SessionWatcher.
