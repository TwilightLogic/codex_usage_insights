## ADDED Requirements

### Requirement: Provide a macOS-native analytics workspace
The system SHALL provide a desktop workspace optimized for macOS pointer-and-keyboard usage with persistent navigation and contextual drill-down.

#### Scenario: User opens the main app workspace
- **WHEN** the user opens the app after completing onboarding
- **THEN** the system MUST present top-level navigation for `Dashboard`, `Sessions`, `Models`, `Cost`, and `Settings`
- **THEN** the system MUST support contextual detail inspection without forcing the user into a separate modal-only flow

### Requirement: Apply shared filters across analysis views
The system SHALL provide a shared query state for time range and other primary filters so all analytics views stay aligned while the user drills down.

#### Scenario: User changes the global time range
- **WHEN** the user selects a different time range or trend granularity
- **THEN** the system MUST refresh dashboard summaries, charts, and downstream analysis views from the same active filter state

#### Scenario: Filters produce no rows
- **WHEN** the active filters produce no matching results
- **THEN** the system MUST show a zero-results empty state that distinguishes filtered emptiness from import failure

### Requirement: Show a dashboard that explains summary usage at a glance
The system SHALL provide a dashboard that summarizes the selected range before the user drills into sessions or models.

#### Scenario: Dashboard has imported data
- **WHEN** imported analytics data exists for the active filter range
- **THEN** the dashboard MUST show summary totals for key token buckets, counted session count, and estimated cost status
- **THEN** the dashboard MUST provide at least one time-series visualization at daily, weekly, or monthly granularity
- **THEN** the dashboard MUST provide a fast path into high-impact sessions or warning states

### Requirement: Provide a searchable and sortable session explorer
The system SHALL let the user inspect sessions as a first-class analysis surface.

#### Scenario: User explores sessions
- **WHEN** the user opens the `Sessions` view
- **THEN** the system MUST provide search over session-identifying metadata and sortable columns for core usage values
- **THEN** the system MUST show detail for the selected session, including metadata, token totals, and relevant warnings

### Requirement: Provide a model analysis view
The system SHALL let the user inspect model usage based on attributed usage segments rather than only per-session labels.

#### Scenario: User opens the model analysis view
- **WHEN** the user opens the `Models` view for a range with attributed usage
- **THEN** the system MUST show aggregate usage broken down by model
- **THEN** the system MUST let the user inspect the sessions or contributions behind a selected model

#### Scenario: Some usage cannot be attributed to a model
- **WHEN** the model analysis includes unattributed segments
- **THEN** the system MUST show an explicit unknown or partial-attribution bucket rather than silently dropping that usage

### Requirement: Communicate empty, loading, error, and partial-data states clearly
The system SHALL differentiate app states so users can tell the difference between no data, filtered data, in-progress refresh, and failed import.

#### Scenario: App has not imported any data yet
- **WHEN** the user opens the app before selecting a session folder
- **THEN** the system MUST show an onboarding empty state that explains what local data will be read and how to begin

#### Scenario: Refresh is in progress with prior data available
- **WHEN** the app is refreshing after a successful prior import
- **THEN** the system MUST keep prior results visible and MUST show non-blocking refresh progress

#### Scenario: Import or query fails
- **WHEN** the app cannot access the selected path or encounters a recoverable data-store failure
- **THEN** the system MUST present an actionable error state with retry or reset guidance
