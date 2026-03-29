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
    func scopedUsageSummary(matching scope: AnalysisScope) async -> ScopedUsageSummary
    func warnings(matching scope: AnalysisScope, limit: Int?) async -> [ImportWarning]
    func trendBuckets(
        matching query: TrendQuery,
        calendar: Calendar
    ) async -> [UsageTrendBucket]
    func modelAggregates(matching query: ModelAggregateQuery) async -> [ModelAggregate]
    func modelTrendBuckets(
        matching query: ModelTrendQuery,
        calendar: Calendar
    ) async -> [UsageTrendBucket]
    func modelSessionContributions(
        matching query: ModelSessionContributionQuery
    ) async -> [ModelSessionContribution]
}

protocol SessionLookupProviding: Sendable {
    func allSessions() async -> [UsageSession]
    func sessions(matching query: SessionListQuery) async -> [UsageSession]
    func session(withID id: String) async -> UsageSession?
    func sessionDetail(withID id: String) async -> SessionDetailPayload?
}

protocol PricingProfileProviding: Sendable {
    func availablePricingProfiles() async -> [PricingProfile]
    func costEstimate(matching query: CostEstimateQuery) async -> CostEstimate?
    func costTrendBuckets(
        matching query: CostTrendQuery,
        calendar: Calendar
    ) async -> [CostTrendBucket]
}

protocol AnalyticsRepository: UsageSummaryQuerying, SessionLookupProviding, PricingProfileProviding {
    func replace(with result: ImportResult) async
    func clear() async
}

actor InMemoryAnalyticsRepository: AnalyticsRepository {
    private let builtInPricingProfiles: [PricingProfile] = [
        PricingProfile(
            reviewedOn: "2026-03-16",
            name: "gpt-5.4",
            description: "Public OpenAI API pricing proxy for GPT-5.4 usage.",
            inputRatePerMillion: Decimal(string: "2.5") ?? 2.5,
            cachedInputRatePerMillion: Decimal(string: "0.25") ?? 0.25,
            outputRatePerMillion: Decimal(string: "15.0") ?? 15.0
        ),
        PricingProfile(
            reviewedOn: "2026-03-16",
            name: "gpt-5-mini",
            description: "Public OpenAI API pricing proxy for GPT-5 mini usage.",
            inputRatePerMillion: Decimal(string: "0.25") ?? 0.25,
            cachedInputRatePerMillion: Decimal(string: "0.025") ?? 0.025,
            outputRatePerMillion: Decimal(string: "2.0") ?? 2.0
        )
    ]

    private var latestResult: ImportResult?

    func replace(with result: ImportResult) async {
        latestResult = result
    }

    func clear() async {
        latestResult = nil
    }

    func currentSummary() async -> UsageOverviewSummary? {
        latestResult?.summary
    }

    func scopedUsageSummary(matching scope: AnalysisScope) async -> ScopedUsageSummary {
        let sessions = filteredSessions(matching: scope)
        return ScopedUsageSummary(
            countedSessions: sessions.count,
            warningCount: filteredWarnings(matching: scope).count,
            usage: aggregatedUsage(matching: scope)
        )
    }

    func warnings(matching scope: AnalysisScope, limit: Int?) async -> [ImportWarning] {
        let filtered = filteredWarnings(matching: scope)
        guard let limit else {
            return filtered
        }
        return Array(filtered.prefix(limit))
    }

    func trendBuckets(
        matching query: TrendQuery,
        calendar: Calendar
    ) async -> [UsageTrendBucket] {
        var groupedUsage: [Date: TokenUsage] = [:]
        let segments = filteredSegments(matching: query.scope)

        if segments.isEmpty {
            for session in filteredSessions(matching: query.scope) {
                let bucketStart = bucketStartDate(
                    for: session.observedAt,
                    granularity: query.granularity,
                    calendar: calendar
                )
                groupedUsage[bucketStart, default: .zero] = groupedUsage[bucketStart, default: .zero]
                    .adding(session.usage)
            }
        } else {
            for segment in segments {
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
        let sessions = filteredSessions(matching: query.scope)
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
        let segments = filteredSegments(matching: query.scope)

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

    func modelTrendBuckets(
        matching query: ModelTrendQuery,
        calendar: Calendar
    ) async -> [UsageTrendBucket] {
        let segments = filteredSegments(matching: query.scope)
            .filter { $0.modelIdentifier == query.modelID }

        var groupedUsage: [Date: TokenUsage] = [:]
        for segment in segments {
            let bucketStart = bucketStartDate(
                for: segment.timestamp,
                granularity: query.granularity,
                calendar: calendar
            )
            groupedUsage[bucketStart, default: .zero] = groupedUsage[bucketStart, default: .zero]
                .adding(segment.usage)
        }

        return groupedUsage.keys.sorted().map { startDate in
            UsageTrendBucket(
                startDate: startDate,
                usage: groupedUsage[startDate] ?? .zero
            )
        }
    }

    func modelSessionContributions(
        matching query: ModelSessionContributionQuery
    ) async -> [ModelSessionContribution] {
        guard let latestResult else {
            return []
        }

        let sessionsByID = Dictionary(uniqueKeysWithValues: latestResult.sessions.map { ($0.id, $0) })
        let groupedSegments = Dictionary(
            grouping: filteredSegments(matching: query.scope).filter { $0.modelIdentifier == query.modelID },
            by: \.sessionID
        )

        let contributions = groupedSegments.compactMap { sessionID, segments -> ModelSessionContribution? in
            guard let session = sessionsByID[sessionID] else {
                return nil
            }

            let attributedUsage = segments.reduce(TokenUsage.zero) { partialResult, segment in
                partialResult.adding(segment.usage)
            }

            return ModelSessionContribution(
                session: session,
                attributedUsage: attributedUsage
            )
        }
        .sorted { lhs, rhs in
            if lhs.attributedUsage.totalTokens == rhs.attributedUsage.totalTokens {
                return lhs.session.observedAt > rhs.session.observedAt
            }
            return lhs.attributedUsage.totalTokens > rhs.attributedUsage.totalTokens
        }

        if let limit = query.limit {
            return Array(contributions.prefix(limit))
        }

        return contributions
    }

    func availablePricingProfiles() async -> [PricingProfile] {
        builtInPricingProfiles
    }

    func costEstimate(matching query: CostEstimateQuery) async -> CostEstimate? {
        guard let profile = pricingProfile(named: query.pricingProfileName) else {
            return nil
        }

        return makeCostEstimate(
            usage: aggregatedUsage(matching: query.scope),
            profile: profile
        )
    }

    func costTrendBuckets(
        matching query: CostTrendQuery,
        calendar: Calendar
    ) async -> [CostTrendBucket] {
        guard let profile = pricingProfile(named: query.pricingProfileName) else {
            return []
        }

        let usageBuckets = await trendBuckets(
            matching: TrendQuery(
                granularity: query.granularity,
                scope: query.scope
            ),
            calendar: calendar
        )

        return usageBuckets.map { bucket in
            CostTrendBucket(
                startDate: bucket.startDate,
                estimatedCost: estimateUsageCost(
                    usage: bucket.usage,
                    profile: profile
                ),
                usage: bucket.usage
            )
        }
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

    private func filteredSegments(matching scope: AnalysisScope) -> [UsageSegment] {
        guard let latestResult else {
            return []
        }

        let sessionsByID = Dictionary(uniqueKeysWithValues: latestResult.sessions.map { ($0.id, $0) })
        let warningSessionIDs = warningSessionIDs(from: latestResult)

        return latestResult.segments.filter { segment in
            guard scope.dateInterval?.contains(segment.timestamp) ?? true else {
                return false
            }
            guard let session = sessionsByID[segment.sessionID] else {
                return false
            }
            guard sessionMatchesNonDateFilters(
                session,
                workspacePath: scope.workspacePath,
                warningsOnly: scope.warningsOnly,
                warningSessionIDs: warningSessionIDs
            ) else {
                return false
            }
            guard let modelID = scope.modelID else {
                return true
            }
            return segment.modelIdentifier == modelID
        }
    }

    private func filteredSessions(matching scope: AnalysisScope) -> [UsageSession] {
        guard let latestResult else {
            return []
        }

        let warningSessionIDs = warningSessionIDs(from: latestResult)
        let baseSessions = latestResult.sessions.filter { session in
            guard scope.dateInterval?.contains(session.observedAt) ?? true else {
                return false
            }
            return sessionMatchesNonDateFilters(
                session,
                workspacePath: scope.workspacePath,
                warningsOnly: scope.warningsOnly,
                warningSessionIDs: warningSessionIDs
            )
        }

        guard let modelID = scope.modelID else {
            return baseSessions
        }

        let matchingSessionIDs = Set(
            latestResult.segments.filter { segment in
                guard segment.modelIdentifier == modelID else {
                    return false
                }
                guard scope.dateInterval?.contains(segment.timestamp) ?? true else {
                    return false
                }
                guard let session = latestResult.sessions.first(where: { $0.id == segment.sessionID }) else {
                    return false
                }
                return sessionMatchesNonDateFilters(
                    session,
                    workspacePath: scope.workspacePath,
                    warningsOnly: scope.warningsOnly,
                    warningSessionIDs: warningSessionIDs
                )
            }
            .map(\.sessionID)
        )

        return baseSessions.filter { matchingSessionIDs.contains($0.id) }
    }

    private func filteredWarnings(matching scope: AnalysisScope) -> [ImportWarning] {
        guard let latestResult else {
            return []
        }

        let matchingPaths = Set(filteredSessions(matching: scope).map(\.sourcePath))
        return latestResult.warnings.filter { matchingPaths.contains($0.path) }
    }

    private func aggregatedUsage(matching scope: AnalysisScope) -> TokenUsage {
        let segments = filteredSegments(matching: scope)
        if !segments.isEmpty {
            return segments.reduce(.zero) { partialResult, segment in
                partialResult.adding(segment.usage)
            }
        }

        guard scope.modelID == nil else {
            return .zero
        }

        return filteredSessions(matching: scope).reduce(.zero) { partialResult, session in
            partialResult.adding(session.usage)
        }
    }

    private func warningSessionIDs(from result: ImportResult) -> Set<String> {
        let sessionsByPath = Dictionary(grouping: result.sessions, by: \.sourcePath)
        return Set(
            result.warnings.flatMap { warning in
                sessionsByPath[warning.path]?.map(\.id) ?? []
            }
        )
    }

    private func sessionMatchesNonDateFilters(
        _ session: UsageSession,
        workspacePath: String?,
        warningsOnly: Bool,
        warningSessionIDs: Set<String>
    ) -> Bool {
        if let workspacePath, session.workspacePath != workspacePath {
            return false
        }

        if warningsOnly && !warningSessionIDs.contains(session.id) {
            return false
        }

        return true
    }

    private func pricingProfile(named profileName: String?) -> PricingProfile? {
        guard let profileName else {
            return nil
        }
        return builtInPricingProfiles.first(where: { $0.name == profileName })
    }

    private func deriveBillableTokenBreakdown(from usage: TokenUsage) -> BillableTokenBreakdown {
        let totalInputTokens = max(usage.inputTokens, 0)
        let cachedInputTokens = min(max(usage.cachedInputTokens, 0), totalInputTokens)
        let uncachedInputTokens = max(totalInputTokens - cachedInputTokens, 0)

        return BillableTokenBreakdown(
            uncachedInputTokens: uncachedInputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: max(usage.outputTokens, 0)
        )
    }

    private func makeCostEstimate(
        usage: TokenUsage,
        profile: PricingProfile
    ) -> CostEstimate {
        let billableTokens = deriveBillableTokenBreakdown(from: usage)
        return CostEstimate(
            profile: profile,
            usage: usage,
            billableTokens: billableTokens,
            estimatedCost: estimateUsageCost(usage: usage, profile: profile)
        )
    }

    private func estimateUsageCost(
        usage: TokenUsage,
        profile: PricingProfile
    ) -> Decimal {
        let billableTokens = deriveBillableTokenBreakdown(from: usage)
        let million = Decimal(1_000_000)

        let uncachedInputCost = Decimal(billableTokens.uncachedInputTokens) / million * profile.inputRatePerMillion
        let cachedInputCost = Decimal(billableTokens.cachedInputTokens) / million * profile.cachedInputRatePerMillion
        let outputCost = Decimal(billableTokens.outputTokens) / million * profile.outputRatePerMillion

        return uncachedInputCost + cachedInputCost + outputCost
    }
}
