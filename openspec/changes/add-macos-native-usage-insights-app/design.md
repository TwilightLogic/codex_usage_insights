## Context

The repository currently proves the core local-reporting idea through a Python CLI that reconstructs token usage from `~/.codex/sessions/**/*.jsonl`. That foundation is useful, but it is not yet a product: there is no native macOS information architecture, no persistent analytics store, no exploratory workflow for drilling from trends into sessions, and no clear product boundary for dimensions that are only partially available in the raw logs.

Observed Codex log structure creates both opportunity and constraint:

- `session_meta` provides a stable session identifier, workspace path, source, and provider metadata.
- `turn_context` provides the active `model`, which makes model attribution possible.
- `token_count` provides cumulative token snapshots, including `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, and `total_tokens`.
- `rate_limits` sometimes exposes window and plan metadata, but not a stable official billing unit.
- Current logs expose `cached_input_tokens`, but do not expose a stable `cache create` field that can be shown as a trustworthy first-class metric.

The product therefore needs to be intentionally opinionated: it should ship a real local analytics workflow for dimensions the logs can support, and explicitly defer or label dimensions that would otherwise be guesswork.

## Goals / Non-Goals

**Goals:**

- Ship a real macOS-native MVP for individual Codex users who want to analyze local usage without a terminal-only workflow.
- Let users answer four practical questions quickly: how much usage happened, when it happened, which sessions caused it, and which models it is associated with.
- Preserve trust by separating official log-derived values from estimates and unsupported fields.
- Keep the first implementation small enough to ship in roughly two weeks while leaving a clean path for future expansion.
- Reuse the semantics already established in this repository for token buckets and estimated cost, while redesigning the presentation and storage layers for desktop use.

**Non-Goals:**

- Team analytics, cloud sync, account sharing, or multi-device merge in v1.
- Official invoice-grade billing or provider-native `billing block` reporting in v1.
- Real-time menu bar monitoring, notifications, or long-running background daemons in v1.
- Cross-tool ingestion for Claude Code, Cursor, or generic OpenAI logs in v1.
- A speculative `cache create` metric synthesized from incomplete signals.

## Decisions

### Position the product as a single-user local analytics workbench

The MVP should target three user groups:

- Heavy Codex users who want to understand day-to-day token and cost behavior.
- Freelancers or consultants who need rough usage and cost visibility for their own work.
- Tool builders who want to inspect session quality, model mix, and log completeness while staying local-first.

The core value is not “pretty charts.” The core value is an explainable path from summary to cause:

- Start from a time-bounded overview.
- Identify a spike, skew, or cost jump.
- Drill into the sessions and models behind it.
- See caveats when the underlying data is incomplete.

The MVP scope should include:

- Local log import from a user-selected Codex sessions folder.
- Dashboard summary with KPI cards and daily/weekly/monthly trends.
- Session explorer with search, sort, filters, and a right-side detail panel.
- Model breakdown using attributed usage segments.
- Cost analysis using named pricing profiles and visible estimation caveats.
- Settings for data path, timezone, pricing profile, and refresh behavior.

The MVP should explicitly exclude:

- Provider-native `billing block` analytics.
- `cache create` analytics.
- Collaboration and cloud-backed account views.
- Alerting, automation, and export-heavy reporting surfaces.

Alternative considered:

- Position the app as a broad LLM observability product from day one. Rejected because the source of truth is currently local Codex logs, the strongest use case is individual analysis, and broadening the promise this early would create unsupported UX and architectural debt.

### Use a macOS-first three-column workspace instead of a single dashboard page

The app should use `NavigationSplitView` with three functional layers:

- Sidebar: top-level destinations `Dashboard`, `Sessions`, `Models`, `Cost`, and `Settings`.
- Content column: the main chart, table, or grouped list for the selected destination.
- Detail / inspector column: contextual drill-down for the selected session, model, or warning cluster.

This structure fits macOS analytics behavior better than a mobile-style tab layout because users often compare a list against detail while keeping filters visible and stable.

Recommended page hierarchy:

- `Dashboard`
  - KPI strip: total tokens, uncached input, cached input, output, estimated cost, counted sessions.
  - Primary trend chart with `Daily / Weekly / Monthly` granularity switch.
  - Secondary breakdown cards for models, cache ratio, and warning count.
  - “Top sessions in range” table for fast drill-down.
- `Sessions`
  - Search + filter toolbar.
  - Sortable table in the content column.
  - Detail inspector with session metadata, token totals, segment timeline, and parser warnings.
- `Models`
  - Breakdown table by model.
  - Model trend chart across the selected range.
  - Contribution list showing top sessions for the selected model.
- `Cost`
  - Estimated cost summary, pricing profile picker, formula disclosure, and cost trend chart.
  - Table that pairs token buckets with derived billable counts.
- `Settings`
  - Data source path.
  - Timezone and calendar settings.
  - Pricing profile selection and custom profile import.
  - Refresh behavior and data reset controls.

Global interaction rules:

- Keep a shared filter bar in the window toolbar for time range, project path, model filter, and “warnings only.”
- Use `7D`, `30D`, `90D`, `This Month`, and `Custom` for quick ranges.
- Let each page own its local sort order, but keep filters global so drill-down feels consistent.
- Persist the last selected range and filters between launches.

Search, sort, and filter behavior:

- Search should work primarily in `Sessions` and match session id, workspace path, and source metadata.
- Sorting should default to “latest usage first” in `Sessions` and “highest tokens first” in `Models`.
- Time-range changes should update all dashboard summaries, charts, and detail counts from the same query state.
- When filters reduce the result set to zero, show an explicit zero-results state instead of a blank table.

State design:

- Empty state: guide the user to choose a session folder and explain what data the app reads locally.
- Initial loading state: full-screen import progress with counts for scanned files and imported sessions.
- Incremental refresh state: non-blocking toolbar progress while keeping previous data visible.
- Error state: actionable message for missing paths, permission issues, or store corruption with retry and reset options.
- Partial data state: warning banner when some sessions were skipped or some model attribution is incomplete.

Alternative considered:

- Build the first version as one large dashboard with modal drill-downs. Rejected because it hides context, creates extra navigation friction on desktop, and makes session analysis feel secondary when it is actually one of the primary jobs to be done.

### Standardize the data model around Session totals and Usage Segments

The product should define and consistently use these terms:

- `Session`: one logical Codex conversation log, backed by one source JSONL file and a stable session id when available.
- `Usage Snapshot`: one cumulative `token_count` payload from the log.
- `Usage Segment`: the non-negative delta between two consecutive usable cumulative snapshots in the same session.
- `Token Usage`: the tuple of `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, and `total_tokens`.
- `Cache Read`: the reported `cached_input_tokens` portion of input.
- `Cache Create`: unsupported in current logs and therefore unavailable in MVP.
- `Cost Estimate`: a transparent, API-equivalent estimate derived from token buckets and a chosen pricing profile.
- `Billing Block`: reserved for future use only. The MVP should not show a `billing block` page or metric because current logs do not expose a stable provider-native billing unit.

The app should store two complementary analytical facts:

- `Session` facts for stable totals, list views, and coarse reporting.
- `Usage Segment` facts for model attribution and time-based charts.

This is the key architectural decision for the desktop product. Session-only storage is enough for a CLI summary, but it is too lossy for a desktop explorer. If we only keep the final max snapshot per session, model breakdowns either become wrong or vague. By storing segment deltas and attributing each segment to the latest known `turn_context.model`, the app can answer “which model drove this usage?” in a defensible way.

Recommended persisted entities:

- `ImportedFile`
  - `path`
  - `fileSize`
  - `modifiedAt`
  - `contentHash` or fast fingerprint
  - `lastImportedAt`
  - `importStatus`
- `UsageSession`
  - `sessionID`
  - `sourceFilePath`
  - `startedAt`
  - `lastUsageAt`
  - `workspacePath`
  - `sourceKind`
  - `modelProvider`
  - `primaryModel`
  - `planType`
  - `totals` for all token buckets
  - `warningCount`
- `UsageSegment`
  - `sessionID`
  - `sequence`
  - `timestamp`
  - `model`
  - `workspacePath`
  - delta token buckets
  - optional rate-limit window metadata when present
- `ImportWarning`
  - `sessionID` or `sourceFilePath`
  - `code`
  - `message`
  - `severity`
- `PricingProfile`
  - `name`
  - `description`
  - rates for uncached input, cached input, and output

Semantics the store must preserve:

- `cached_input_tokens` are a subset of `input_tokens` for cost estimation.
- `reasoning_output_tokens` are a reported subset of `output_tokens`, not a second billable output bucket.
- `cache create` must be represented as unavailable rather than `0`.
- If model attribution is missing for some segments, the UI should group those tokens under `Unknown Model` and show a partial-data indicator.

Alternative considered:

- Keep only one canonical max snapshot per session in the app database. Rejected because it makes model-level views and fine-grained trend attribution too inaccurate for a serious desktop analytics tool.

### Build the app with SwiftUI, selective AppKit bridges, GRDB, and a Swift-native parser

Recommended stack:

- `SwiftUI` for the app shell, navigation, inspector, toolbar, and reusable view composition.
- `Observation` (`@Observable`) plus Swift concurrency for state management.
- `Charts` for line, bar, and stacked-area visualizations.
- `GRDB` on top of SQLite for the local store and query layer.
- `Foundation` streaming JSON decoding for parser and import services.
- Small `AppKit` bridges only where macOS-native affordances are materially better, such as `NSOpenPanel`, window commands, and possibly table behavior fallback if SwiftUI `Table` proves insufficient.

Why this stack:

- `SwiftUI` is the fastest way to ship a native macOS interface with multi-column navigation, inspector flows, settings scenes, and chart integration.
- `Charts` is “good enough” for the MVP and avoids integrating a heavier third-party charting library before we know which visualizations actually stick.
- `GRDB` offers explicit schema control, migrations, fast queries, testability, and predictable bulk insert behavior, all of which matter more here than persistence convenience.
- A Swift-native parser avoids embedding Python in the app, removes runtime packaging risk, and keeps import behavior testable inside Xcode.

Why not the main alternatives:

- `AppKit-first`: rejected for MVP because it would slow delivery without giving us proportionate value for the initial scope.
- `SwiftData`: rejected because import-heavy analytics apps benefit from explicit migrations, indexed SQL queries, and more predictable performance than SwiftData currently offers.
- `Electron`, `Tauri`, or a local web app shell: rejected because the product is explicitly macOS-native and benefits from native windowing, settings, tables, keyboard commands, and file access flows.
- Embedding the existing Python parser: rejected because app distribution, dependency management, and debugging would all get harder for little product benefit.

Recommended code organization for the first implementation:

```text
apps/macos/
  CodexUsageInsights.xcodeproj
  CodexUsageInsights/
    App/
    Core/
      Domain/
      Parser/
      Store/
      Analytics/
      Services/
      UIComponents/
    Features/
      Dashboard/
      Sessions/
      Models/
      Cost/
      Settings/
    Resources/
  CodexUsageInsightsTests/
  CodexUsageInsightsUITests/
```

The MVP should keep one app target with clear folder boundaries instead of prematurely splitting everything into separate Swift packages. If the parser and analytics layers prove stable, they can be extracted later.

Alternative considered:

- Start with many packages and a deep modular architecture. Rejected because it increases setup and coordination cost before we have validated the app’s core workflow.

### Keep state management lightweight and query-driven

The app should use a small number of observable stores instead of a large architecture framework:

- `AppState` for window-level routing, onboarding completion, and settings.
- `FilterState` for global time range, workspace filter, model filter, and warning toggles.
- One feature store per page for query execution and selection state.
- Repository-style services for imports, analytics queries, and pricing calculations.

View rendering should be query-driven:

- `DashboardStore` asks the analytics repository for summary KPIs, trend buckets, top sessions, and warnings based on the active filter.
- `SessionsStore` asks for paged rows plus the currently selected session detail payload.
- `ModelsStore` asks for model aggregates and per-model contribution details.
- `CostStore` asks for token totals plus derived billable counts and estimated cost output.

Why this over a heavier state framework:

- The MVP does not yet need the ceremony of TCA or Redux-style action graphs.
- Most complexity lives in parsing and query semantics, not in UI event choreography.
- `Observation` with repositories is easier to onboard into and fast enough for a two-week delivery.

Alternative considered:

- Introduce TCA at the start for future-proofing. Rejected because it would add conceptual overhead before the core product contract is validated.

### Use a staged import and refresh model instead of live file watching in v1

The import flow should be:

1. On first launch, show onboarding and ask the user to pick a Codex session root.
2. Run an initial scan in the background and persist imported files, sessions, segments, and warnings.
3. On later launches, rescan the root and only re-import files whose fingerprint changed.
4. Provide a visible `Refresh` action in the toolbar.
5. Optionally auto-refresh when the app becomes active again if the last scan is stale.

This is the right MVP trade-off because it gives users real data freshness without forcing the team to solve continuous file watching, debouncing, and partial-write edge cases immediately.

Data freshness rules:

- Never block the UI on refresh once there is already imported data.
- Show the last refresh timestamp in the toolbar or dashboard.
- If a refresh fails, keep the previous good dataset and show a warning.

What should be real first:

- Folder selection and initial import.
- Parser correctness for sessions and segments.
- Local persistence.
- Dashboard summary and session explorer backed by the real store.
- Pricing profile application and cost estimates.

What can be mocked first:

- Empty-state illustration and visual polish.
- Preview data for chart layout work.
- Some advanced settings controls.

Alternative considered:

- Build the UI entirely on mock data and integrate the parser later. Rejected because the biggest product risk is semantic correctness, not visual assembly.

### Treat unsupported metrics and ambiguous billing data as unavailable, not approximate

Two tempting features are risky in v1:

- `cache create`
- `billing block`

The current logs support `cached_input_tokens`, but not a trustworthy `cache create` counter. They also expose some rate-limit window and `plan_type` data, but not a stable official billing unit. The app should therefore do two things:

- Keep those concepts visible in the product language only when necessary for future planning.
- Mark them as unavailable or defer them entirely in the shipped UI.

If a future version introduces a user-defined `billing window`, it should be presented as a derived grouping rule, not a provider-native billing truth.

Alternative considered:

- Infer `cache create` and `billing block` from partial signals. Rejected because it would make the product feel richer while actually reducing trust.

### Deliver the MVP in two weeks by sequencing core correctness before breadth

Recommended two-week plan:

- Days 1-2
  - Create the macOS app shell, navigation, fixtures, and design tokens.
  - Port the existing parser semantics into Swift tests.
- Days 3-4
  - Add SQLite schema, import pipeline, deduplication, and warning persistence.
  - Build onboarding and manual refresh.
- Days 5-6
  - Implement dashboard KPIs, daily/weekly/monthly aggregation, and warning banner.
  - Build the session table and detail inspector from real data.
- Days 7-8
  - Add usage segment attribution and the models page.
  - Add pricing profile loading and the cost page.
- Days 9-10
  - Polish states, keyboard behavior, settings, and error handling.
  - Run performance checks on larger local logs and close MVP gaps.

MVP acceptance criteria:

- A user can choose a local Codex session folder and import data successfully.
- Dashboard totals and trends update when the global time range changes.
- Sessions can be searched, sorted, and inspected.
- Models view shows attributed usage or clearly labels unknown attribution.
- Cost view applies a chosen pricing profile and labels all dollars as estimates.
- The app surfaces skipped files, unsupported metrics, and partial data without silently hiding them.

Alternative considered:

- Spend week one polishing a visually rich dashboard before the store and parser are stable. Rejected because a usage analytics product fails on trust long before it fails on aesthetics.

## Risks / Trade-offs

- [Risk] Model attribution may be incomplete when logs lack nearby `turn_context` entries. -> Mitigation: attribute by nearest prior model context, group failures under `Unknown Model`, and show a partial-data banner.
- [Risk] SwiftUI `Table` performance may degrade with large datasets. -> Mitigation: start with indexed SQLite queries and paging-friendly table models; keep an AppKit table bridge as an escape hatch if profiling proves it necessary.
- [Risk] Codex log schema may change across versions. -> Mitigation: make the parser tolerant, version test fixtures, and surface unknown payloads as warnings instead of failing imports.
- [Risk] Users may interpret cost estimates or plan metadata as official billing. -> Mitigation: repeat estimate labeling in dashboard and cost views, and do not expose unsupported `billing block` analytics.
- [Risk] Maintaining both the Python CLI and the Swift app can create semantic drift. -> Mitigation: share fixture cases and keep terminology and pricing semantics aligned in tests and specs.

## Migration Plan

This change only adds planning artifacts in the current repository, so there is no production migration yet. The implementation path should be:

1. Add the macOS project under `apps/macos` without disturbing the current Python CLI.
2. Port parser semantics and fixture tests into Swift before building most UI features.
3. Add the SQLite schema at version `1` with explicit migration support from the start.
4. Build dashboard and sessions against real imported data.
5. Add model attribution and cost analysis after the core store is stable.

Rollback strategy for the future implementation:

- Keep the CLI working as an independent verification path while the macOS app matures.
- If segment attribution proves too unstable for launch, ship session-level views first and mark model analysis as beta rather than blocking the entire app.

## Open Questions

- Should the initial deployment target be macOS 14 for broader reach, or macOS 15 if newer SwiftUI table and inspector behavior materially improves the implementation?
- Do we want a user-defined `billing window` in v1.1, or should all cost analysis remain purely time-range based until the rest of the app is stable?
- Is CSV export important enough for the first public build, or should it wait until query contracts are proven through the UI?
