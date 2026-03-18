## 1. Bootstrap the macOS app foundation

- [ ] 1.1 Create the macOS project under `apps/macos` with app, unit-test, and UI-test targets
- [x] 1.2 Add the initial folder structure for `App`, `Core`, `Features`, and shared UI components
- [ ] 1.3 Add dependencies and project wiring for `GRDB`, `Charts`, and fixture-based test resources
- [x] 1.4 Implement the initial `NavigationSplitView` shell with destinations for `Dashboard`, `Sessions`, `Models`, `Cost`, and `Settings`

## 2. Define the domain and persistence model

- [x] 2.1 Implement Swift domain models for `UsageSession`, `UsageSegment`, `ImportWarning`, `ImportedFile`, and `PricingProfile`
- [ ] 2.2 Create the SQLite schema and migration `v1` for imported files, sessions, segments, warnings, and pricing profiles
- [x] 2.3 Add repository interfaces for import, analytics queries, session detail lookup, and pricing-profile access

## 3. Port parsing and import semantics from local logs

- [ ] 3.1 Implement a streaming JSONL parser for `session_meta`, `turn_context`, and `token_count` events
- [x] 3.2 Derive stable session totals from cumulative usage snapshots without double-counting repeated totals
- [ ] 3.3 Derive timestamp-ordered usage segments from cumulative snapshots and attribute them to the latest known model context
- [ ] 3.4 Persist import warnings for skipped files, malformed payloads, missing usage snapshots, and unsupported metrics
- [ ] 3.5 Add parser and importer tests using the existing repository fixtures plus new cases for model attribution and unknown-model segments

## 4. Implement import, onboarding, and refresh flows

- [x] 4.1 Build first-launch onboarding that lets the user choose a Codex session root with `NSOpenPanel`
- [x] 4.2 Implement initial import progress reporting with scanned-file, imported-session, and warning counts
- [ ] 4.3 Implement refresh with file fingerprint deduplication so unchanged logs are not re-imported
- [ ] 4.4 Add stale-on-foreground auto-refresh and a manual toolbar refresh action
- [ ] 4.5 Add recoverable error handling for missing paths, permission failures, and local store reset

## 5. Build the analytics query layer

- [x] 5.1 Implement summary queries for total tokens, uncached input, cached input, output, estimated cost status, and counted sessions
- [ ] 5.2 Implement day, week, and month bucket queries for trend charts from the active global filter state
- [x] 5.3 Implement searchable and sortable session list queries plus session-detail payload assembly
- [ ] 5.4 Implement model aggregate queries that group attributed segments and preserve an `Unknown Model` bucket

## 6. Build the dashboard and session explorer

- [ ] 6.1 Implement the global filter bar with time range, custom range, workspace filter, model filter, and warnings-only toggle
- [ ] 6.2 Build the dashboard KPI strip, primary trend chart, warning banner, and top-sessions table from real query data
- [x] 6.3 Build the `Sessions` view with search, sortable columns, selection state, and a detail inspector
- [ ] 6.4 Persist the user’s last selected range and primary filters across launches

## 7. Build models and cost analysis

- [ ] 7.1 Build the `Models` view with aggregate rows, trend visualization, and per-model session contribution drill-down
- [ ] 7.2 Implement pricing-profile loading, selection, and estimated-cost calculation using subset-aware billing semantics
- [ ] 7.3 Build the `Cost` view with profile disclosure, formula text, billable-token breakdown, and estimate caveats
- [ ] 7.4 Ensure unsupported metrics such as `cache create` and provider-native `billing block` are clearly unavailable rather than synthesized

## 8. Polish MVP states, performance, and validation

- [ ] 8.1 Add empty, loading, zero-results, partial-data, and recoverable-error states across all primary views
- [ ] 8.2 Profile import and query performance against a larger real local session dataset and add the missing database indexes
- [ ] 8.3 Add UI and integration tests for onboarding, import, dashboard refresh, session drill-down, model breakdown, and cost estimation
- [ ] 8.4 Write MVP usage documentation and a release checklist that maps directly to the acceptance criteria in the design
