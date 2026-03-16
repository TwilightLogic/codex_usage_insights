## ADDED Requirements

### Requirement: Import local Codex session usage records
The system SHALL scan local Codex session files and derive a canonical usage record for each session from `token_count` events stored in JSONL logs.

#### Scenario: Session file contains token usage snapshots
- **WHEN** the system reads a Codex session file that contains one or more `token_count` events with `total_token_usage`
- **THEN** it MUST produce one canonical session usage record for that file
- **THEN** the record MUST preserve `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, and `total_tokens`
- **THEN** the record MUST retain the timestamp of the selected usage snapshot for calendar grouping when that event timestamp is available

#### Scenario: Session file has no usable token snapshot
- **WHEN** the system reads a session file that has no usable `token_count` usage payload
- **THEN** it MUST skip that file from numeric totals
- **THEN** it MUST emit a warning that the session could not be counted

### Requirement: Aggregate usage by calendar period
The system SHALL aggregate canonical session usage records into daily, monthly, and yearly reports using a configurable timezone.

#### Scenario: User requests a daily report
- **WHEN** the user requests a report with period `day`
- **THEN** the system MUST group usage records by local calendar day in the active timezone
- **THEN** the output MUST include per-day totals for each supported token bucket and the number of counted sessions

#### Scenario: User requests a monthly report
- **WHEN** the user requests a report with period `month`
- **THEN** the system MUST group usage records by local calendar month in the active timezone
- **THEN** the output MUST include per-month totals for each supported token bucket and the number of counted sessions

#### Scenario: User requests a yearly report
- **WHEN** the user requests a report with period `year`
- **THEN** the system MUST group usage records by local calendar year in the active timezone
- **THEN** the output MUST include per-year totals for each supported token bucket and the number of counted sessions

### Requirement: Estimate cost from transparent pricing profiles
The system SHALL compute an API-equivalent estimated dollar cost when a pricing profile is selected or matched for the report.

#### Scenario: Pricing profile is available
- **WHEN** the user runs a report with a valid pricing profile
- **THEN** the system MUST calculate an estimated cost from the aggregated token buckets using that profile's rates
- **THEN** the system MUST treat `cached_input_tokens` as a priced subset of `input_tokens` rather than billing both full input and cached input for the same tokens
- **THEN** the system MUST treat `reasoning_output_tokens` as a reported subset of `output_tokens` and MUST NOT bill them separately
- **THEN** the report MUST identify the pricing profile used
- **THEN** the report MUST label the resulting dollar value as an estimate rather than an official bill

#### Scenario: Pricing profile is unavailable
- **WHEN** the user runs a report without a pricing profile
- **THEN** the system MUST still return token totals for the requested period
- **THEN** the system MUST mark estimated cost as unavailable instead of fabricating a dollar value

### Requirement: Surface completeness and billing caveats
The system SHALL communicate the limits of locally reconstructed usage so users can judge how much trust to place in a report.

#### Scenario: Report is based on local ChatGPT-authenticated Codex logs
- **WHEN** the report is generated from local Codex session files
- **THEN** the system MUST include a caveat that the report is reconstructed from local logs
- **THEN** the system MUST state that any dollar total is an API-equivalent estimate and not an official ChatGPT invoice

#### Scenario: Report contains skipped or partial data
- **WHEN** one or more session files are skipped, incomplete, or otherwise suspicious
- **THEN** the system MUST surface warning details alongside the report summary
- **THEN** the system MUST identify how many files were excluded from totals

### Requirement: Provide human-readable and machine-readable reports
The system SHALL make aggregated usage reports available in both a human-readable summary view and a machine-readable structured format.

#### Scenario: User requests the default local report
- **WHEN** the user runs the reporting command without a machine-readable output flag
- **THEN** the system MUST render a human-readable summary that shows the reporting period, timezone, token totals, and estimated cost or cost status
- **THEN** the human-readable summary MUST group report scope, scan summary, token totals, pricing details, and warnings into clearly labeled sections

#### Scenario: User requests structured output
- **WHEN** the user requests structured output
- **THEN** the system MUST return a machine-readable report containing the period buckets, token totals, session counts, warnings, pricing profile metadata, and estimated cost fields
