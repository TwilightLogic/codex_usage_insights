## 1. Establish the reporting core

- [x] 1.1 Create the project or module skeleton for a local Codex usage reporting tool with separate parser, aggregator, pricing, and presentation layers.
- [x] 1.2 Add fixture session files and test helpers that cover usable `token_count` events, rate-limit-only events, and missing-usage files.

## 2. Implement local session parsing

- [x] 2.1 Implement JSONL scanning for `~/.codex/sessions/**/*.jsonl` with configurable input path and timezone-aware timestamp handling.
- [x] 2.2 Convert each usable session file into one canonical usage record while skipping unusable files and collecting parser warnings.
- [x] 2.3 Add tests that verify repeated `token_count` snapshots do not double-count a single session and that skipped files are reported correctly.

## 3. Build aggregation and pricing

- [x] 3.1 Implement day, month, and year grouping over canonical session usage records with per-bucket totals and session counts.
- [x] 3.2 Implement pricing profile loading and API-equivalent cost estimation for input, cached input, and output-style token buckets.
- [x] 3.3 Add tests for timezone boundaries, missing pricing profiles, and cost-estimate disclaimers.

## 4. Expose report outputs

- [x] 4.1 Implement a default human-readable CLI report that shows reporting periods, timezone, token totals, warnings, and estimated cost status.
- [x] 4.2 Implement machine-readable JSON output that includes bucket totals, session counts, warnings, pricing metadata, and estimated cost fields.

## 5. Harden UX and documentation

- [x] 5.1 Add clear user-facing caveats that local ChatGPT-authenticated Codex reports are reconstructed from local logs and are not official billing statements.
- [x] 5.2 Document pricing profile configuration, supported report periods, and known limitations compared with tools such as `ccusage`, `codex-ratelimit`, and SessionWatcher.

## 6. Refine cost estimation semantics

- [x] 6.1 Update pricing calculation so cached input is billed as a subset of input and reasoning output is not billed separately from output.
- [x] 6.2 Update report formula text and pricing configuration examples to describe uncached input, cached input, and output billing clearly.
- [x] 6.3 Add regression tests that lock in subset-aware billing semantics and non-negative derived uncached input behavior.

## 7. Improve human-readable output formatting

- [x] 7.1 Rework the default text report into clearly labeled sections with lightweight symbols for scope, scan summary, pricing, token totals, buckets, and warnings.
- [x] 7.2 Add a clearer token summary that explicitly shows uncached input alongside input, cached input, output, reasoning, and total tokens.
- [x] 7.3 Add regression tests that lock in the new sectioned output format and warning presentation.

## 8. Align bucket attribution with usage snapshot timing

- [x] 8.1 Use the selected `token_count` snapshot timestamp as the canonical session timestamp for aggregation, falling back to session metadata only when needed.
- [x] 8.2 Add regression coverage for sessions whose best usage snapshot lands on a later local calendar day than the session start time.
