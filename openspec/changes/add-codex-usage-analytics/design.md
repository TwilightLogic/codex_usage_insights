## Context

This change plans a standalone Codex usage reporting project rather than a feature inside the current repository runtime. The core problem is that local Codex Desktop sessions already persist token usage snapshots in `~/.codex/sessions/**/*.jsonl`, but ChatGPT-authenticated local usage does not expose an official daily, monthly, or yearly history or a corresponding dollar-cost view. Existing tools validate parts of the workflow but do not cleanly define the narrow product we want:

- `ccusage` proves local AI coding logs can be parsed into aggregate usage and cost reports.
- `codex-ratelimit` focuses on rate-limit windows, not calendar-based historical reporting.
- SessionWatcher covers broader real-time monitoring across coding agents, which is larger in scope than the CLI-first reporting flow we want to establish first.

The design therefore focuses on a trustworthy core: derive one canonical usage record per local session file, aggregate records by calendar period, and optionally estimate API-equivalent cost with explicit caveats.

## Goals / Non-Goals

**Goals:**
- Produce accurate daily, monthly, and yearly token totals from local Codex session files.
- Preserve token-bucket detail for `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, and `total_tokens`.
- Estimate API-equivalent dollar cost through named pricing profiles and show exactly which profile generated the estimate.
- Surface warnings when reports are incomplete because of missing usage snapshots, partial files, or missing pricing configuration.
- Keep the first implementation CLI-friendly while making parsing and aggregation reusable for future UI surfaces.

**Non-Goals:**
- Reproduce an official ChatGPT or OpenAI invoice for ChatGPT-authenticated Codex usage.
- Depend on undocumented backend endpoints as the primary reporting path.
- Build a menu bar monitor, always-on daemon, or cloud sync service in the first version.
- Support non-Codex log formats in the initial release.

## Decisions

### Use local session files as the source of truth

The system will read `~/.codex/sessions/**/*.jsonl` directly and treat `token_count` events as the primary usage source. This keeps the tool offline-friendly and avoids reliance on unstable or hidden APIs.

Alternative considered:
- Use undocumented backend usage endpoints. Rejected because they are brittle, unofficial, and not useful for local-only or archived session analysis.

### Derive one canonical usage snapshot per session file

Multiple `token_count` events may appear in the same session file as the conversation progresses. The parser will use the highest observed `total_token_usage` snapshot for a file as the session total, because summing repeated snapshots would double-count the same session growth.

For calendar grouping, the canonical session timestamp will come from the winning `token_count` event itself when available, not just from the initial `session_meta` event. This keeps long-running sessions that cross midnight from assigning their full token total to the day the session started.

Alternative considered:
- Sum every `last_token_usage` payload. Rejected for the initial version because not every event guarantees a clean incremental delta and missing events would lead to inconsistent totals.

### Separate parsing, aggregation, and pricing into distinct layers

The implementation will define:
- A parser that extracts canonical session usage records and parser warnings.
- An aggregator that groups records by local calendar day, month, or year.
- A pricing engine that applies a selected profile to the aggregated token buckets.

This split keeps the reporting core testable and reusable for CLI output, JSON export, and any later UI.

Alternative considered:
- Build report generation inside one monolithic command. Rejected because it couples file parsing, grouping rules, and pricing assumptions too tightly.

### Make pricing profile-driven instead of hard-coding one formula

The project will use named pricing profiles with configurable rates for uncached input, cached input, and output tokens. Cost estimation will interpret `cached_input_tokens` as a priced subset of `input_tokens`, so the estimated billable input will be:

- `uncached_input_tokens = input_tokens - cached_input_tokens`
- `cached_input_tokens = cached_input_tokens`
- `output_tokens = output_tokens`

The implementation will also treat `reasoning_output_tokens` as a reported subset of `output_tokens`, not as an additional billable bucket. Reports will show the profile name, the effective formula, and clearly label the resulting dollar value as an estimate. When no pricing profile is available, the tool will still emit token totals and mark cost as unavailable.

Alternative considered:
- Bill `input_tokens`, `cached_input_tokens`, `output_tokens`, and `reasoning_output_tokens` as four independent buckets. Rejected because observed Codex logs indicate `cached_input_tokens` is a subset of `input_tokens` and `reasoning_output_tokens` is a subset of `output_tokens`, which would double-count costs.

### Start with CLI and JSON outputs

The first implementation will provide a human-readable terminal report and a machine-readable JSON report. This keeps scope aligned with the research goal and helps validate correctness before spending effort on a richer UI.

The terminal report will use labeled sections and lightweight visual markers so the user can quickly separate report scope, scan status, token totals, pricing status, period buckets, and warnings. This improves usability without changing the underlying JSON contract.

Alternative considered:
- Build a local dashboard first. Rejected because it increases scope before the reporting model is stable and existing tools already cover some monitoring-oriented UI use cases.

### Aggregate by configurable local timezone

Daily, monthly, and yearly rollups will use a configured timezone, defaulting to the host system timezone, so sessions near midnight land in the bucket users expect rather than silently grouping by UTC.

Alternative considered:
- Always aggregate in UTC. Rejected because these reports are primarily human-facing and local calendar expectations matter more than transport neutrality.

## Risks / Trade-offs

- [Risk] Users may mistake estimated dollar values for official billing. -> Mitigation: label all cost figures as estimates, require a named pricing profile, and include a report-level disclaimer.
- [Risk] Codex log schema may change across app versions. -> Mitigation: make the parser version-tolerant, record unknown shapes as warnings, and add fixture coverage for multiple observed formats.
- [Risk] Using the maximum session snapshot could undercount if a file is truncated before the final event is persisted. -> Mitigation: surface warnings for incomplete-looking files and preserve excluded-file counts in report output.
- [Risk] Calendar aggregation can surprise users around timezone boundaries. -> Mitigation: show the active timezone in every report and make it configurable.
- [Risk] Pricing presets can become stale as public API pricing changes. -> Mitigation: store presets in separate configuration and support user overrides without code changes.

## Migration Plan

This change only creates planning artifacts in the current repository, so there is no runtime migration or rollback step here. For the future standalone project, the expected implementation path is:

1. Build a parser with fixture-backed tests.
2. Add aggregation and pricing layers on top of canonical session records.
3. Expose the results through CLI table output and JSON export.
4. Add a richer UI only after the reporting contract is stable.

## Open Questions

- Should the yearly view mean calendar year only, or should we also support rolling 12-month summaries?
- Should the tool auto-select a pricing profile from model hints in session logs when the user does not pass `--pricing-profile`?
- Is JSON enough for the first machine-readable format, or do we also want CSV export in the first release?
