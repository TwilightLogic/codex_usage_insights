## ADDED Requirements

### Requirement: Estimate cost from transparent pricing profiles
The system SHALL estimate cost from imported token buckets only when a named pricing profile is available and selected.

#### Scenario: Valid pricing profile is selected
- **WHEN** the user selects a valid pricing profile for the active dataset
- **THEN** the system MUST calculate estimated cost using uncached input, cached input, and output buckets without double-counting overlapping token fields
- **THEN** the system MUST expose the profile name used for the calculation

#### Scenario: No pricing profile is selected
- **WHEN** the user has not selected a valid pricing profile
- **THEN** the system MUST continue showing token analytics
- **THEN** the system MUST mark cost as unavailable instead of fabricating a dollar value

### Requirement: Show cost analysis with formula and caveats
The system SHALL make the estimation logic inspectable so users can judge how much trust to place in the output.

#### Scenario: Cost view renders estimated values
- **WHEN** the app shows estimated cost output
- **THEN** the UI MUST identify the pricing profile, the effective billing formula, and that the dollar figure is an estimate rather than an official provider bill

#### Scenario: User inspects cost inputs
- **WHEN** the user drills into cost analysis for the active range
- **THEN** the system MUST show the relationship between reported token buckets and derived billable token counts

### Requirement: Cost queries honor the active analysis scope
The system SHALL apply the same active filters and time scope to cost analysis as it does to token analysis.

#### Scenario: User changes time range or filters
- **WHEN** the user changes the active global analysis scope
- **THEN** the system MUST recompute cost summaries, trends, and related token totals from the same filtered dataset

### Requirement: Avoid unsupported billing-block claims in MVP cost reporting
The system SHALL keep cost reporting honest by limiting the MVP to time-range-based estimates instead of unsupported provider-native billing units.

#### Scenario: User views cost reporting in the MVP
- **WHEN** the app renders estimated cost analysis
- **THEN** the system MUST present the results as time-range-based estimates and MUST NOT claim a provider-native `billing block` total unless that field becomes explicitly supported by the source data
