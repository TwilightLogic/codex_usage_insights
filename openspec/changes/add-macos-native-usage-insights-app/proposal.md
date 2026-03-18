## Why

`codex-usage-analytics` already proves that local Codex logs can be reconstructed into trustworthy token totals, but individual macOS users still lack a native workflow for turning those logs into explainable usage analysis. The first macOS app should let users import local logs, inspect time-bounded usage changes, trace those changes back to sessions and supported model attribution, and understand rough cost without overstating what the source data can actually prove.

## Primary User

The primary user is a heavy individual Codex user on macOS who wants to understand personal usage over time, identify which sessions drove spikes or changes, see model mix where attribution is supported, and get a rough local cost estimate without uploading logs or working in the terminal.

## MVP User Loop

- Select a local Codex sessions folder and import logs into the app.
- Choose a time range and inspect usage and estimated cost changes.
- Drill into the sessions that contributed most to the selected range or spike.
- Inspect model-associated usage where attribution is supported.
- See explicit warnings when data is partial, skipped, estimated, or unavailable.

## Trust Boundary / Support Matrix

### Measured From Local Logs

- Session-level usage reconstructed from usable `token_count` snapshots.
- Token buckets: `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, and `total_tokens`.
- Time-bounded aggregates and trend buckets computed directly from imported usage records.
- Import completeness signals such as skipped files and warnings.

### Derived Inside The App

- Cost estimates computed from measured token buckets plus a selected pricing profile.
- Model attribution for usage when token activity can be associated with model context in the logs.
- Rankings, summaries, and breakdowns built from measured records.

### Unavailable In V1

- `cache create` as a first-class metric.
- Provider-native `billing block` analytics.
- Official invoice or billing reconciliation.

## What Changes

- Add a single-user macOS-native workflow that imports local Codex session logs and refreshes them incrementally while preserving warnings for incomplete or unusable data.
- Add a time-bounded analysis workflow that helps users understand how usage and estimated cost change over time without leaving the app.
- Add drill-down workflows that let users move from summaries into the sessions most responsible for a change in usage.
- Add model-associated analysis only where attribution is supported, and surface unattributed usage explicitly instead of hiding it.
- Make trust boundaries visible in product behavior and terminology so users can distinguish measured values, derived estimates, and unavailable metrics.

## Non-Goals

- Cloud sync, collaboration, team analytics, or multi-device merge in v1.
- Cross-tool ingestion beyond local Codex session logs in v1.
- Provider-native `billing block` reporting or official billing reconciliation in v1.
- `cache create` as a supported v1 metric.
- Menu bar monitoring, notifications, or background-daemon behavior in v1.

## Capabilities

### New Capabilities
- `local-usage-ingestion`: Import local Codex session logs into a normalized on-device analytics store with refresh, deduplication, and completeness signaling.
- `desktop-usage-workspace`: Provide a macOS-native analysis workspace for time-bounded overview, session drill-down, supported model analysis, and shared filter state optimized for keyboard-and-pointer desktop usage.
- `cost-analysis`: Apply transparent pricing profiles to supported token buckets and expose cost summaries, trends, and estimate caveats inside the app.

### Modified Capabilities

## MVP Release Gate

The MVP is complete when a user can import local Codex session logs, inspect usage trends for a chosen time range, drill into contributing sessions, view supported model attribution, and see estimated cost plus explicit partial-data and unavailable-metric caveats entirely inside the macOS app.

## Impact

Affected areas include a new macOS app surface, the product contract for local Codex usage analysis, and repository-level terminology that must stay aligned with existing token and pricing semantics. This proposal intentionally does not lock in parser implementation details, storage technology, or UI framework choices; those belong in design.
