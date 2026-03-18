## ADDED Requirements

### Requirement: Import local Codex session logs into an on-device analytics store
The system SHALL let the user choose a local Codex session root and import supported JSONL logs into a persistent on-device store without requiring a network service or bundled Python runtime.

#### Scenario: Initial import from a selected session folder
- **WHEN** the user selects a valid Codex session root in the app
- **THEN** the system MUST scan supported session files, parse usable records, persist imported analytics data locally, and expose import progress to the UI

#### Scenario: Refresh reuses previously imported files
- **WHEN** the user runs refresh after a prior import
- **THEN** the system MUST avoid duplicating unchanged source files and MUST update only files whose import fingerprint or metadata changed

### Requirement: Preserve both session totals and attributed usage segments
The system SHALL persist one stable session-level usage record per imported session and SHALL also persist usage segments derived from cumulative token snapshots so time-based and model-based analysis can be computed accurately.

#### Scenario: Session file contains cumulative token snapshots
- **WHEN** the system imports a session file with one or more usable `token_count` snapshots
- **THEN** it MUST produce a session-level total for the imported session
- **THEN** it MUST derive non-negative usage segments from successive cumulative snapshots in timestamp order

#### Scenario: Model attribution is available for imported snapshots
- **WHEN** a usable token snapshot can be associated with a preceding `turn_context.model`
- **THEN** the derived usage segment MUST be attributed to that model for analytics queries

#### Scenario: Model attribution is incomplete
- **WHEN** a usable token snapshot cannot be associated with a model
- **THEN** the derived usage segment MUST still be persisted
- **THEN** the system MUST mark the segment as `Unknown Model` or equivalent partial attribution state

### Requirement: Surface incomplete and unsupported source data explicitly
The system SHALL preserve trust by recording import warnings for incomplete files and by marking unsupported dimensions as unavailable rather than fabricating values.

#### Scenario: Session file has no usable token usage snapshot
- **WHEN** the system imports a session file that lacks a usable `total_token_usage` payload
- **THEN** the system MUST exclude that file from numeric analytics totals
- **THEN** the system MUST persist an import warning that can be surfaced in the UI

#### Scenario: Source logs do not provide a stable cache-create metric
- **WHEN** the system renders analytics for imported data
- **THEN** it MUST treat `cache create` as unavailable in the MVP instead of showing `0` or an inferred approximation

#### Scenario: Source logs do not provide a stable billing block field
- **WHEN** the system computes imported analytics for the MVP
- **THEN** it MUST NOT fabricate a provider-native `billing block` dimension from partial rate-limit metadata alone
