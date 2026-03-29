import Foundation
import Testing
@testable import CodexUsageInsightsApp

struct InMemoryAnalyticsRepositoryTests {
    @Test
    func sessionDetailIncludesWarningsForTheSameSourceFile() async {
        let session = makeSession(
            id: "session-1",
            sourcePath: "/tmp/session-1.jsonl",
            workspacePath: "/tmp/workspace",
            observedAt: Date(timeIntervalSince1970: 1_710_000_000),
            totalTokens: 160
        )

        let matchingWarning = ImportWarning(
            id: "warning-1",
            code: "invalid_json_line",
            message: "Invalid JSON line",
            path: session.sourcePath,
            line: 7
        )
        let unrelatedWarning = ImportWarning(
            id: "warning-2",
            code: "missing_usage_snapshot",
            message: "No usable token_count snapshot found",
            path: "/tmp/other-session.jsonl",
            line: nil
        )

        let result = ImportResult(
            summary: UsageOverviewSummary(
                inputPath: "/tmp",
                scannedFiles: 2,
                countedSessions: 1,
                excludedFiles: 1,
                warningCount: 2,
                usage: session.usage,
                estimatedCostStatus: .unavailable,
                importedAt: Date(timeIntervalSince1970: 1_710_000_100)
            ),
            importedFiles: [],
            sessions: [session],
            segments: [
                UsageSegment(
                    id: "segment-1",
                    sessionID: session.id,
                    sourcePath: session.sourcePath,
                    sequence: 0,
                    timestamp: session.observedAt.addingTimeInterval(-60),
                    model: "gpt-5.4",
                    usage: TokenUsage(
                        inputTokens: 80,
                        cachedInputTokens: 20,
                        outputTokens: 20,
                        reasoningOutputTokens: 5,
                        totalTokens: 100
                    )
                )
            ],
            warnings: [matchingWarning, unrelatedWarning]
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(with: result)

        let detail = await repository.sessionDetail(withID: session.id)

        #expect(detail?.session.id == session.id)
        #expect(detail?.warnings.count == 1)
        #expect(detail?.warnings.first?.id == matchingWarning.id)
        #expect(detail?.segments.count == 1)
        #expect(detail?.segments.first?.model == "gpt-5.4")
    }

    @Test
    func sessionQueriesFilterAndSortRows() async {
        let alpha = makeSession(
            id: "session-alpha",
            sourcePath: "/tmp/session-alpha.jsonl",
            workspacePath: "/tmp/alpha",
            observedAt: Date(timeIntervalSince1970: 1_710_000_100),
            totalTokens: 120
        )
        let beta = makeSession(
            id: "session-beta",
            sourcePath: "/tmp/session-beta.jsonl",
            workspacePath: "/tmp/beta",
            observedAt: Date(timeIntervalSince1970: 1_710_000_200),
            totalTokens: 450
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(
            with: ImportResult(
                summary: UsageOverviewSummary(
                    inputPath: "/tmp",
                    scannedFiles: 2,
                    countedSessions: 2,
                    excludedFiles: 0,
                    warningCount: 0,
                    usage: alpha.usage.adding(beta.usage),
                    estimatedCostStatus: .unavailable,
                    importedAt: Date(timeIntervalSince1970: 1_710_000_300)
                ),
                importedFiles: [],
                sessions: [alpha, beta],
                segments: [],
                warnings: []
            )
        )

        let searchResults = await repository.sessions(
            matching: SessionListQuery(
                searchText: "beta",
                sort: .observedAtDescending,
                scope: .all
            )
        )
        let sortedResults = await repository.sessions(
            matching: SessionListQuery(
                searchText: "",
                sort: .totalTokensDescending,
                scope: .all
            )
        )

        #expect(searchResults.map(\.id) == [beta.id])
        #expect(sortedResults.map(\.id) == [beta.id, alpha.id])
    }

    @Test
    func scopedQueriesRespectWorkspaceModelAndWarningsOnlyFilters() async {
        let alpha = makeSession(
            id: "session-alpha",
            sourcePath: "/tmp/session-alpha.jsonl",
            workspacePath: "/tmp/alpha",
            observedAt: Date(timeIntervalSince1970: 1_710_000_100),
            totalTokens: 120
        )
        let beta = makeSession(
            id: "session-beta",
            sourcePath: "/tmp/session-beta.jsonl",
            workspacePath: "/tmp/beta",
            observedAt: Date(timeIntervalSince1970: 1_710_000_200),
            totalTokens: 450
        )

        let alphaWarning = ImportWarning(
            id: "warning-alpha",
            code: "malformed_json_tail",
            message: "Trailing invalid JSON ignored",
            path: alpha.sourcePath,
            line: 24
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(
            with: ImportResult(
                summary: UsageOverviewSummary(
                    inputPath: "/tmp",
                    scannedFiles: 2,
                    countedSessions: 2,
                    excludedFiles: 0,
                    warningCount: 1,
                    usage: alpha.usage.adding(beta.usage),
                    estimatedCostStatus: .unavailable,
                    importedAt: Date(timeIntervalSince1970: 1_710_000_300)
                ),
                importedFiles: [],
                sessions: [alpha, beta],
                segments: [
                    UsageSegment(
                        id: "alpha-segment",
                        sessionID: alpha.id,
                        sourcePath: alpha.sourcePath,
                        sequence: 0,
                        timestamp: alpha.observedAt,
                        model: "gpt-5.4",
                        usage: alpha.usage
                    ),
                    UsageSegment(
                        id: "beta-segment",
                        sessionID: beta.id,
                        sourcePath: beta.sourcePath,
                        sequence: 0,
                        timestamp: beta.observedAt,
                        model: "gpt-5-mini",
                        usage: beta.usage
                    )
                ],
                warnings: [alphaWarning]
            )
        )

        let scope = AnalysisScope(
            dateInterval: nil,
            workspacePath: "/tmp/alpha",
            modelID: "gpt-5.4",
            warningsOnly: true
        )

        let scopedSummary = await repository.scopedUsageSummary(matching: scope)
        let scopedSessions = await repository.sessions(
            matching: SessionListQuery(
                searchText: "",
                sort: .observedAtDescending,
                scope: scope
            )
        )
        let scopedWarnings = await repository.warnings(matching: scope, limit: nil)
        let scopedModels = await repository.modelAggregates(
            matching: ModelAggregateQuery(scope: scope)
        )

        #expect(scopedSummary.countedSessions == 1)
        #expect(scopedSummary.warningCount == 1)
        #expect(scopedSummary.usage.totalTokens == alpha.totalTokens)
        #expect(scopedSessions.map(\.id) == [alpha.id])
        #expect(scopedWarnings.map(\.id) == [alphaWarning.id])
        #expect(scopedModels.map(\.displayName) == ["gpt-5.4"])
        #expect(scopedModels.first?.usage.totalTokens == alpha.totalTokens)
    }

    @Test
    func trendBucketsGroupSessionsByGranularityAndDateInterval() async throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let alpha = makeSession(
            id: "session-alpha",
            sourcePath: "/tmp/session-alpha.jsonl",
            workspacePath: "/tmp/alpha",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 17,
                hour: 10,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 120
        )
        let beta = makeSession(
            id: "session-beta",
            sourcePath: "/tmp/session-beta.jsonl",
            workspacePath: "/tmp/beta",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 18,
                hour: 11,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 200
        )
        let gamma = makeSession(
            id: "session-gamma",
            sourcePath: "/tmp/session-gamma.jsonl",
            workspacePath: "/tmp/gamma",
            observedAt: makeDate(
                year: 2026,
                month: 4,
                day: 2,
                hour: 9,
                minute: 30,
                calendar: calendar
            ),
            totalTokens: 300
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(
            with: ImportResult(
                summary: UsageOverviewSummary(
                    inputPath: "/tmp",
                    scannedFiles: 3,
                    countedSessions: 3,
                    excludedFiles: 0,
                    warningCount: 0,
                    usage: alpha.usage.adding(beta.usage).adding(gamma.usage),
                    estimatedCostStatus: .unavailable,
                    importedAt: Date(timeIntervalSince1970: 1_710_000_300)
                ),
                importedFiles: [],
                sessions: [alpha, beta, gamma],
                segments: [
                    UsageSegment(
                        id: "alpha-segment",
                        sessionID: alpha.id,
                        sourcePath: alpha.sourcePath,
                        sequence: 0,
                        timestamp: alpha.observedAt,
                        model: "gpt-5.4",
                        usage: alpha.usage
                    ),
                    UsageSegment(
                        id: "beta-segment",
                        sessionID: beta.id,
                        sourcePath: beta.sourcePath,
                        sequence: 0,
                        timestamp: beta.observedAt,
                        model: "gpt-5-mini",
                        usage: beta.usage
                    ),
                    UsageSegment(
                        id: "gamma-segment",
                        sessionID: gamma.id,
                        sourcePath: gamma.sourcePath,
                        sequence: 0,
                        timestamp: gamma.observedAt,
                        model: nil,
                        usage: gamma.usage
                    )
                ],
                warnings: []
            )
        )

        let daily = await repository.trendBuckets(
            matching: TrendQuery(granularity: .day, scope: .all),
            calendar: calendar
        )
        let weekly = await repository.trendBuckets(
            matching: TrendQuery(granularity: .week, scope: .all),
            calendar: calendar
        )
        let filteredMonthly = await repository.trendBuckets(
            matching: TrendQuery(
                granularity: .month,
                scope: AnalysisScope(
                    dateInterval: DateInterval(
                        start: makeDate(
                            year: 2026,
                            month: 3,
                            day: 1,
                            hour: 0,
                            minute: 0,
                            calendar: calendar
                        ),
                        end: makeDate(
                            year: 2026,
                            month: 4,
                            day: 1,
                            hour: 0,
                            minute: 0,
                            calendar: calendar
                        )
                    ),
                    workspacePath: nil,
                    modelID: nil,
                    warningsOnly: false
                )
            ),
            calendar: calendar
        )

        #expect(daily.map(\.usage.totalTokens) == [120, 200, 300])
        #expect(weekly.map(\.usage.totalTokens) == [320, 300])
        #expect(filteredMonthly.map(\.usage.totalTokens) == [320])
    }

    @Test
    func modelAggregatesGroupAttributedAndUnknownSegments() async throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let alpha = makeSession(
            id: "session-alpha",
            sourcePath: "/tmp/session-alpha.jsonl",
            workspacePath: "/tmp/alpha",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 17,
                hour: 10,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 120
        )
        let beta = makeSession(
            id: "session-beta",
            sourcePath: "/tmp/session-beta.jsonl",
            workspacePath: "/tmp/beta",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 18,
                hour: 11,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 200
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(
            with: ImportResult(
                summary: UsageOverviewSummary(
                    inputPath: "/tmp",
                    scannedFiles: 2,
                    countedSessions: 2,
                    excludedFiles: 0,
                    warningCount: 0,
                    usage: alpha.usage.adding(beta.usage),
                    estimatedCostStatus: .unavailable,
                    importedAt: Date(timeIntervalSince1970: 1_710_000_300)
                ),
                importedFiles: [],
                sessions: [alpha, beta],
                segments: [
                    UsageSegment(
                        id: "alpha-known",
                        sessionID: alpha.id,
                        sourcePath: alpha.sourcePath,
                        sequence: 0,
                        timestamp: alpha.observedAt,
                        model: "gpt-5.4",
                        usage: alpha.usage
                    ),
                    UsageSegment(
                        id: "beta-unknown",
                        sessionID: beta.id,
                        sourcePath: beta.sourcePath,
                        sequence: 0,
                        timestamp: beta.observedAt,
                        model: nil,
                        usage: beta.usage
                    )
                ],
                warnings: []
            )
        )

        let aggregates = await repository.modelAggregates(matching: .default)

        #expect(aggregates.count == 2)
        #expect(aggregates.map(\.displayName) == [ModelAggregate.unknownModelDisplayName, "gpt-5.4"])
        #expect(aggregates.map(\.usage.totalTokens) == [200, 120])
        #expect(aggregates.first?.isUnknownModel == true)
    }

    @Test
    func modelTrendBucketsScopeToSelectedModelIdentifier() async throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let alpha = makeSession(
            id: "session-alpha",
            sourcePath: "/tmp/session-alpha.jsonl",
            workspacePath: "/tmp/alpha",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 17,
                hour: 10,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 120
        )
        let beta = makeSession(
            id: "session-beta",
            sourcePath: "/tmp/session-beta.jsonl",
            workspacePath: "/tmp/beta",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 18,
                hour: 11,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 200
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(
            with: ImportResult(
                summary: UsageOverviewSummary(
                    inputPath: "/tmp",
                    scannedFiles: 2,
                    countedSessions: 2,
                    excludedFiles: 0,
                    warningCount: 0,
                    usage: alpha.usage.adding(beta.usage),
                    estimatedCostStatus: .unavailable,
                    importedAt: Date(timeIntervalSince1970: 1_710_000_300)
                ),
                importedFiles: [],
                sessions: [alpha, beta],
                segments: [
                    UsageSegment(
                        id: "alpha-known",
                        sessionID: alpha.id,
                        sourcePath: alpha.sourcePath,
                        sequence: 0,
                        timestamp: alpha.observedAt,
                        model: "gpt-5.4",
                        usage: alpha.usage
                    ),
                    UsageSegment(
                        id: "beta-unknown",
                        sessionID: beta.id,
                        sourcePath: beta.sourcePath,
                        sequence: 0,
                        timestamp: beta.observedAt,
                        model: nil,
                        usage: beta.usage
                    )
                ],
                warnings: []
            )
        )

        let knownTrend = await repository.modelTrendBuckets(
            matching: ModelTrendQuery(
                modelID: "gpt-5.4",
                granularity: .day,
                scope: .all
            ),
            calendar: calendar
        )
        let unknownTrend = await repository.modelTrendBuckets(
            matching: ModelTrendQuery(
                modelID: ModelAggregate.unknownModelID,
                granularity: .day,
                scope: .all
            ),
            calendar: calendar
        )

        #expect(knownTrend.map(\.usage.totalTokens) == [120])
        #expect(unknownTrend.map(\.usage.totalTokens) == [200])
    }

    @Test
    func modelSessionContributionsGroupSegmentsPerSessionAndSortDescending() async throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let alpha = makeSession(
            id: "session-alpha",
            sourcePath: "/tmp/session-alpha.jsonl",
            workspacePath: "/tmp/alpha",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 17,
                hour: 10,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 120
        )
        let beta = makeSession(
            id: "session-beta",
            sourcePath: "/tmp/session-beta.jsonl",
            workspacePath: "/tmp/beta",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 18,
                hour: 11,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 200
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(
            with: ImportResult(
                summary: UsageOverviewSummary(
                    inputPath: "/tmp",
                    scannedFiles: 2,
                    countedSessions: 2,
                    excludedFiles: 0,
                    warningCount: 0,
                    usage: alpha.usage.adding(beta.usage),
                    estimatedCostStatus: .unavailable,
                    importedAt: Date(timeIntervalSince1970: 1_710_000_300)
                ),
                importedFiles: [],
                sessions: [alpha, beta],
                segments: [
                    UsageSegment(
                        id: "alpha-first",
                        sessionID: alpha.id,
                        sourcePath: alpha.sourcePath,
                        sequence: 0,
                        timestamp: alpha.observedAt,
                        model: "gpt-5.4",
                        usage: TokenUsage(
                            inputTokens: 50,
                            cachedInputTokens: 10,
                            outputTokens: 10,
                            reasoningOutputTokens: 5,
                            totalTokens: 60
                        )
                    ),
                    UsageSegment(
                        id: "alpha-second",
                        sessionID: alpha.id,
                        sourcePath: alpha.sourcePath,
                        sequence: 1,
                        timestamp: alpha.observedAt.addingTimeInterval(60),
                        model: "gpt-5.4",
                        usage: TokenUsage(
                            inputTokens: 20,
                            cachedInputTokens: 5,
                            outputTokens: 10,
                            reasoningOutputTokens: 5,
                            totalTokens: 30
                        )
                    ),
                    UsageSegment(
                        id: "beta-first",
                        sessionID: beta.id,
                        sourcePath: beta.sourcePath,
                        sequence: 0,
                        timestamp: beta.observedAt,
                        model: "gpt-5.4",
                        usage: TokenUsage(
                            inputTokens: 80,
                            cachedInputTokens: 20,
                            outputTokens: 20,
                            reasoningOutputTokens: 5,
                            totalTokens: 100
                        )
                    )
                ],
                warnings: []
            )
        )

        let contributions = await repository.modelSessionContributions(
            matching: ModelSessionContributionQuery(
                modelID: "gpt-5.4",
                scope: .all,
                limit: nil
            )
        )

        #expect(contributions.map(\.session.id) == [beta.id, alpha.id])
        #expect(contributions.map(\.attributedUsage.totalTokens) == [100, 90])
    }

    @Test
    func pricingProfilesAndCostEstimateUseSubsetAwareBillingSemantics() async throws {
        let session = makeSession(
            id: "session-cost",
            sourcePath: "/tmp/session-cost.jsonl",
            workspacePath: "/tmp/workspace",
            observedAt: Date(timeIntervalSince1970: 1_710_000_000),
            totalTokens: 140
        )
        let usage = TokenUsage(
            inputTokens: 120,
            cachedInputTokens: 80,
            outputTokens: 20,
            reasoningOutputTokens: 10,
            totalTokens: 140
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(
            with: ImportResult(
                summary: UsageOverviewSummary(
                    inputPath: "/tmp",
                    scannedFiles: 1,
                    countedSessions: 1,
                    excludedFiles: 0,
                    warningCount: 0,
                    usage: usage,
                    estimatedCostStatus: .unavailable,
                    importedAt: Date(timeIntervalSince1970: 1_710_000_100)
                ),
                importedFiles: [],
                sessions: [
                    UsageSession(
                        id: session.id,
                        sourcePath: session.sourcePath,
                        workspacePath: session.workspacePath,
                        observedAt: session.observedAt,
                        usage: usage
                    )
                ],
                segments: [
                    UsageSegment(
                        id: "cost-segment",
                        sessionID: session.id,
                        sourcePath: session.sourcePath,
                        sequence: 0,
                        timestamp: session.observedAt,
                        model: "gpt-5.4",
                        usage: usage
                    )
                ],
                warnings: []
            )
        )

        let profiles = await repository.availablePricingProfiles()
        let estimate = await repository.costEstimate(
            matching: CostEstimateQuery(
                pricingProfileName: "gpt-5.4",
                scope: .all
            )
        )

        #expect(profiles.map(\.name) == ["gpt-5.4", "gpt-5-mini"])
        #expect(estimate?.billableTokens.uncachedInputTokens == 40)
        #expect(estimate?.billableTokens.cachedInputTokens == 80)
        #expect(estimate?.billableTokens.outputTokens == 20)
        #expect(estimate?.estimatedCost.decimalDisplayString == "0.00042")
    }

    @Test
    func costTrendBucketsFollowUsageBucketsForSelectedPricingProfile() async throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let alpha = makeSession(
            id: "session-alpha",
            sourcePath: "/tmp/session-alpha.jsonl",
            workspacePath: "/tmp/alpha",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 17,
                hour: 10,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 120
        )
        let beta = makeSession(
            id: "session-beta",
            sourcePath: "/tmp/session-beta.jsonl",
            workspacePath: "/tmp/beta",
            observedAt: makeDate(
                year: 2026,
                month: 3,
                day: 18,
                hour: 11,
                minute: 0,
                calendar: calendar
            ),
            totalTokens: 200
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(
            with: ImportResult(
                summary: UsageOverviewSummary(
                    inputPath: "/tmp",
                    scannedFiles: 2,
                    countedSessions: 2,
                    excludedFiles: 0,
                    warningCount: 0,
                    usage: alpha.usage.adding(beta.usage),
                    estimatedCostStatus: .unavailable,
                    importedAt: Date(timeIntervalSince1970: 1_710_000_300)
                ),
                importedFiles: [],
                sessions: [alpha, beta],
                segments: [
                    UsageSegment(
                        id: "alpha",
                        sessionID: alpha.id,
                        sourcePath: alpha.sourcePath,
                        sequence: 0,
                        timestamp: alpha.observedAt,
                        model: "gpt-5.4",
                        usage: alpha.usage
                    ),
                    UsageSegment(
                        id: "beta",
                        sessionID: beta.id,
                        sourcePath: beta.sourcePath,
                        sequence: 0,
                        timestamp: beta.observedAt,
                        model: "gpt-5.4",
                        usage: beta.usage
                    )
                ],
                warnings: []
            )
        )

        let costTrend = await repository.costTrendBuckets(
            matching: CostTrendQuery(
                pricingProfileName: "gpt-5.4",
                granularity: .day,
                scope: .all
            ),
            calendar: calendar
        )

        #expect(costTrend.count == 2)
        #expect(costTrend.map(\.usage.totalTokens) == [120, 200])
        #expect(costTrend.map { $0.estimatedCost.decimalDisplayString } == ["0.000605", "0.000805"])
    }

    private func makeSession(
        id: String,
        sourcePath: String,
        workspacePath: String,
        observedAt: Date,
        totalTokens: Int
    ) -> UsageSession {
        UsageSession(
            id: id,
            sourcePath: sourcePath,
            workspacePath: workspacePath,
            observedAt: observedAt,
            usage: TokenUsage(
                inputTokens: max(totalTokens - 40, 0),
                cachedInputTokens: 20,
                outputTokens: 30,
                reasoningOutputTokens: 10,
                totalTokens: totalTokens
            )
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
