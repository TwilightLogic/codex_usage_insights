import Foundation

protocol LogImporting: Sendable {
    func importLogs(
        from directoryURL: URL,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> ImportResult
}

protocol UsageSummaryQuerying: Sendable {
    func currentSummary() async -> UsageOverviewSummary?
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

        let warnings = latestResult.warnings.filter { warning in
            warning.path == session.sourcePath
        }

        return SessionDetailPayload(session: session, warnings: warnings)
    }

    func availablePricingProfiles() async -> [PricingProfile] {
        []
    }
}
