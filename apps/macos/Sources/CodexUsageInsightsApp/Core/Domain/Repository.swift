import Foundation

protocol LogImporting: Sendable {
    func importLogs(
        from directoryURL: URL,
        previousResult: ImportResult?,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> ImportResult
}

protocol UsageSummaryQuerying: Sendable {
    func currentSummary() async -> UsageOverviewSummary?
    func trendBuckets(
        matching query: TrendQuery,
        calendar: Calendar
    ) async -> [UsageTrendBucket]
    func modelAggregates(matching query: ModelAggregateQuery) async -> [ModelAggregate]
}

protocol SessionLookupProviding: Sendable {
    func allSessions() async -> [UsageSession]
    func sessions(matching query: SessionListQuery) async -> [UsageSession]
    func session(withID id: String) async -> UsageSession?
    func sessionDetail(withID id: String) async -> SessionDetailPayload?
}

protocol PricingProfileProviding: Sendable {
    func availablePricingProfiles() async -> [PricingProfile]
}

protocol AnalyticsRepository: UsageSummaryQuerying, SessionLookupProviding, PricingProfileProviding {
    func replace(with result: ImportResult) async
}

actor InMemoryAnalyticsRepository: AnalyticsRepository {
    private var latestResult: ImportResult?

    func replace(with result: ImportResult) async {
        latestResult = result
    }

    func currentSummary() async -> UsageOverviewSummary? {
        latestResult?.summary
    }

    func trendBuckets(
        matching query: TrendQuery,
        calendar: Calendar
    ) async -> [UsageTrendBucket] {
        var groupedUsage: [Date: TokenUsage] = [:]
        let segments = latestResult?.segments ?? []

        if segments.isEmpty {
            let sessions = (latestResult?.sessions ?? []).filter { session in
                guard let dateInterval = query.dateInterval else {
                    return true
                }
                return dateInterval.contains(session.observedAt)
            }

            for session in sessions {
                let bucketStart = bucketStartDate(
                    for: session.observedAt,
                    granularity: query.granularity,
                    calendar: calendar
                )
                groupedUsage[bucketStart, default: .zero] = groupedUsage[bucketStart, default: .zero]
                    .adding(session.usage)
            }
        } else {
            for segment in segments where query.dateInterval?.contains(segment.timestamp) ?? true {
                let bucketStart = bucketStartDate(
                    for: segment.timestamp,
                    granularity: query.granularity,
                    calendar: calendar
                )
                groupedUsage[bucketStart, default: .zero] = groupedUsage[bucketStart, default: .zero]
                    .adding(segment.usage)
            }
        }

        return groupedUsage.keys.sorted().map { startDate in
            UsageTrendBucket(
                startDate: startDate,
                usage: groupedUsage[startDate] ?? .zero
            )
        }
    }

    func allSessions() async -> [UsageSession] {
        latestResult?.sessions ?? []
    }

    func sessions(matching query: SessionListQuery) async -> [UsageSession] {
        let sessions = latestResult?.sessions ?? []
        let filteredSessions: [UsageSession]

        if query.searchText.isEmpty {
            filteredSessions = sessions
        } else {
            let normalizedQuery = query.searchText.localizedLowercase
            filteredSessions = sessions.filter { session in
                session.id.localizedLowercase.contains(normalizedQuery)
                    || session.workspaceName.localizedLowercase.contains(normalizedQuery)
                    || session.sourceFilename.localizedLowercase.contains(normalizedQuery)
            }
        }

        switch query.sort {
        case .observedAtDescending:
            return filteredSessions.sorted { $0.observedAt > $1.observedAt }
        case .observedAtAscending:
            return filteredSessions.sorted { $0.observedAt < $1.observedAt }
        case .totalTokensDescending:
            return filteredSessions.sorted { $0.totalTokens > $1.totalTokens }
        case .totalTokensAscending:
            return filteredSessions.sorted { $0.totalTokens < $1.totalTokens }
        case .sessionIDAscending:
            return filteredSessions.sorted {
                $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
        case .sessionIDDescending:
            return filteredSessions.sorted {
                $0.id.localizedStandardCompare($1.id) == .orderedDescending
            }
        case .workspaceAscending:
            return filteredSessions.sorted {
                $0.workspaceName.localizedStandardCompare($1.workspaceName) == .orderedAscending
            }
        case .workspaceDescending:
            return filteredSessions.sorted {
                $0.workspaceName.localizedStandardCompare($1.workspaceName) == .orderedDescending
            }
        }
    }

    func session(withID id: String) async -> UsageSession? {
        latestResult?.sessions.first(where: { $0.id == id })
    }

    func sessionDetail(withID id: String) async -> SessionDetailPayload? {
        guard
            let latestResult,
            let session = latestResult.sessions.first(where: { $0.id == id })
        else {
            return nil
        }

        let segments = latestResult.segments
            .filter { $0.sessionID == session.id }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.sequence < rhs.sequence
                }
                return lhs.timestamp < rhs.timestamp
            }
        let warnings = latestResult.warnings.filter { warning in
            warning.path == session.sourcePath
        }

        return SessionDetailPayload(session: session, segments: segments, warnings: warnings)
    }

    func modelAggregates(matching query: ModelAggregateQuery) async -> [ModelAggregate] {
        let segments = (latestResult?.segments ?? []).filter { segment in
            guard let dateInterval = query.dateInterval else {
                return true
            }
            return dateInterval.contains(segment.timestamp)
        }

        let groupedSegments = Dictionary(grouping: segments, by: \.model)
        return groupedSegments.map { model, groupedSegments in
            ModelAggregate(
                model: model,
                usage: groupedSegments.reduce(.zero) { partialResult, segment in
                    partialResult.adding(segment.usage)
                },
                sessionCount: Set(groupedSegments.map(\.sessionID)).count
            )
        }
        .sorted { lhs, rhs in
            if lhs.usage.totalTokens == rhs.usage.totalTokens {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.usage.totalTokens > rhs.usage.totalTokens
        }
    }

    func availablePricingProfiles() async -> [PricingProfile] {
        []
    }

    private func bucketStartDate(
        for date: Date,
        granularity: TrendGranularity,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
                ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start
                ?? calendar.startOfDay(for: date)
        }
    }
}
