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
            warnings: [matchingWarning, unrelatedWarning]
        )

        let repository = InMemoryAnalyticsRepository()
        await repository.replace(with: result)

        let detail = await repository.sessionDetail(withID: session.id)

        #expect(detail?.session.id == session.id)
        #expect(detail?.warnings.count == 1)
        #expect(detail?.warnings.first?.id == matchingWarning.id)
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
                warnings: []
            )
        )

        let searchResults = await repository.sessions(
            matching: SessionListQuery(
                searchText: "beta",
                sort: .observedAtDescending
            )
        )
        let sortedResults = await repository.sessions(
            matching: SessionListQuery(
                searchText: "",
                sort: .totalTokensDescending
            )
        )

        #expect(searchResults.map(\.id) == [beta.id])
        #expect(sortedResults.map(\.id) == [beta.id, alpha.id])
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
                warnings: []
            )
        )

        let daily = await repository.trendBuckets(
            matching: TrendQuery(granularity: .day, dateInterval: nil),
            calendar: calendar
        )
        let weekly = await repository.trendBuckets(
            matching: TrendQuery(granularity: .week, dateInterval: nil),
            calendar: calendar
        )
        let filteredMonthly = await repository.trendBuckets(
            matching: TrendQuery(
                granularity: .month,
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
                )
            ),
            calendar: calendar
        )

        #expect(daily.map(\.usage.totalTokens) == [120, 200, 300])
        #expect(weekly.map(\.usage.totalTokens) == [320, 300])
        #expect(filteredMonthly.map(\.usage.totalTokens) == [320])
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
