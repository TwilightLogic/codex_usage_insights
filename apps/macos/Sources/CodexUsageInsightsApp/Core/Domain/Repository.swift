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
    func session(withID id: String) async -> UsageSession?
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

    func session(withID id: String) async -> UsageSession? {
        latestResult?.sessions.first(where: { $0.id == id })
    }

    func availablePricingProfiles() async -> [PricingProfile] {
        []
    }
}
