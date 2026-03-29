import Foundation

enum SidebarDestination: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case sessions
    case models
    case cost
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .sessions:
            return "Sessions"
        case .models:
            return "Models"
        case .cost:
            return "Cost"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "chart.bar.xaxis"
        case .sessions:
            return "list.bullet.rectangle"
        case .models:
            return "square.stack.3d.up"
        case .cost:
            return "dollarsign.circle"
        case .settings:
            return "gearshape"
        }
    }
}

enum AnalysisRangePreset: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case allTime
    case last7Days
    case last30Days
    case last90Days
    case thisMonth
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .allTime:
            return "All Time"
        case .last7Days:
            return "7D"
        case .last30Days:
            return "30D"
        case .last90Days:
            return "90D"
        case .thisMonth:
            return "This Month"
        case .custom:
            return "Custom"
        }
    }
}

struct AnalysisFilterState: Codable, Hashable, Sendable {
    var rangePreset: AnalysisRangePreset
    var customStartDate: Date
    var customEndDate: Date
    var workspacePath: String?
    var modelID: String?
    var warningsOnly: Bool

    static func `default`(now: Date = Date()) -> AnalysisFilterState {
        AnalysisFilterState(
            rangePreset: .allTime,
            customStartDate: now.addingTimeInterval(-6 * 86_400),
            customEndDate: now,
            workspacePath: nil,
            modelID: nil,
            warningsOnly: false
        )
    }

    func resolvedScope(
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) -> AnalysisScope {
        AnalysisScope(
            dateInterval: resolvedDateInterval(calendar: calendar, now: now),
            workspacePath: workspacePath,
            modelID: modelID,
            warningsOnly: warningsOnly
        )
    }

    func normalized(
        availableWorkspacePaths: Set<String>,
        availableModelIDs: Set<String>
    ) -> AnalysisFilterState {
        let normalizedWorkspace = workspacePath.flatMap { availableWorkspacePaths.contains($0) ? $0 : nil }
        let normalizedModel = modelID.flatMap { availableModelIDs.contains($0) ? $0 : nil }
        let normalizedStart = min(customStartDate, customEndDate)
        let normalizedEnd = max(customStartDate, customEndDate)

        return AnalysisFilterState(
            rangePreset: rangePreset,
            customStartDate: normalizedStart,
            customEndDate: normalizedEnd,
            workspacePath: normalizedWorkspace,
            modelID: normalizedModel,
            warningsOnly: warningsOnly
        )
    }

    private func resolvedDateInterval(
        calendar: Calendar,
        now: Date
    ) -> DateInterval? {
        switch rangePreset {
        case .allTime:
            return nil
        case .last7Days:
            return recentDateInterval(days: 7, calendar: calendar, now: now)
        case .last30Days:
            return recentDateInterval(days: 30, calendar: calendar, now: now)
        case .last90Days:
            return recentDateInterval(days: 90, calendar: calendar, now: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .custom:
            let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
            let endDay = calendar.startOfDay(for: max(customStartDate, customEndDate))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateInterval(start: start, end: max(start, end))
        }
    }

    private func recentDateInterval(
        days: Int,
        calendar: Calendar,
        now: Date
    ) -> DateInterval? {
        let end = now
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }
}

struct AnalysisScope: Hashable, Sendable {
    let dateInterval: DateInterval?
    let workspacePath: String?
    let modelID: String?
    let warningsOnly: Bool

    static let all = AnalysisScope(
        dateInterval: nil,
        workspacePath: nil,
        modelID: nil,
        warningsOnly: false
    )
}

struct ScopedUsageSummary: Hashable, Sendable {
    let countedSessions: Int
    let warningCount: Int
    let usage: TokenUsage
}

struct TokenUsage: Codable, Hashable, Sendable {
    var inputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var outputTokens: Int = 0
    var reasoningOutputTokens: Int = 0
    var totalTokens: Int = 0

    static let zero = TokenUsage()

    var uncachedInputTokens: Int {
        max(inputTokens - cachedInputTokens, 0)
    }

    var isNonZero: Bool {
        inputTokens > 0
            || cachedInputTokens > 0
            || outputTokens > 0
            || reasoningOutputTokens > 0
            || totalTokens > 0
    }

    func adding(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: inputTokens + other.inputTokens,
            cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
            outputTokens: outputTokens + other.outputTokens,
            reasoningOutputTokens: reasoningOutputTokens + other.reasoningOutputTokens,
            totalTokens: totalTokens + other.totalTokens
        )
    }

    func subtractingClamped(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: max(inputTokens - other.inputTokens, 0),
            cachedInputTokens: max(cachedInputTokens - other.cachedInputTokens, 0),
            outputTokens: max(outputTokens - other.outputTokens, 0),
            reasoningOutputTokens: max(reasoningOutputTokens - other.reasoningOutputTokens, 0),
            totalTokens: max(totalTokens - other.totalTokens, 0)
        )
    }

    func componentwiseMax(with other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: max(inputTokens, other.inputTokens),
            cachedInputTokens: max(cachedInputTokens, other.cachedInputTokens),
            outputTokens: max(outputTokens, other.outputTokens),
            reasoningOutputTokens: max(reasoningOutputTokens, other.reasoningOutputTokens),
            totalTokens: max(totalTokens, other.totalTokens)
        )
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }
}

struct UsageSession: Identifiable, Hashable, Sendable {
    let id: String
    let sourcePath: String
    let workspacePath: String?
    let observedAt: Date
    let usage: TokenUsage

    var workspaceName: String {
        workspacePath ?? "Unknown Workspace"
    }

    var sourceFilename: String {
        URL(fileURLWithPath: sourcePath).lastPathComponent
    }

    var totalTokens: Int {
        usage.totalTokens
    }
}

struct SessionDetailPayload: Hashable, Sendable {
    let session: UsageSession
    let segments: [UsageSegment]
    let warnings: [ImportWarning]
}

enum SessionListSort: String, Hashable, Sendable {
    case observedAtDescending
    case observedAtAscending
    case totalTokensDescending
    case totalTokensAscending
    case sessionIDAscending
    case sessionIDDescending
    case workspaceAscending
    case workspaceDescending
}

struct SessionListQuery: Hashable, Sendable {
    let searchText: String
    let sort: SessionListSort
    let scope: AnalysisScope

    static let `default` = SessionListQuery(
        searchText: "",
        sort: .observedAtDescending,
        scope: .all
    )
}

enum TrendGranularity: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    var id: Self { self }

    var title: String {
        switch self {
        case .day:
            return "Daily"
        case .week:
            return "Weekly"
        case .month:
            return "Monthly"
        }
    }
}

struct TrendQuery: Hashable, Sendable {
    let granularity: TrendGranularity
    let scope: AnalysisScope

    static let `default` = TrendQuery(
        granularity: .day,
        scope: .all
    )
}

struct UsageTrendBucket: Identifiable, Hashable, Sendable {
    let startDate: Date
    let usage: TokenUsage

    var id: Date {
        startDate
    }
}

struct UsageSegment: Identifiable, Hashable, Sendable {
    let id: String
    let sessionID: String
    let sourcePath: String
    let sequence: Int
    let timestamp: Date
    let model: String?
    let usage: TokenUsage

    var modelDisplayName: String {
        model ?? ModelAggregate.unknownModelDisplayName
    }

    var modelIdentifier: String {
        model ?? ModelAggregate.unknownModelID
    }
}

struct ModelAggregateQuery: Hashable, Sendable {
    let scope: AnalysisScope

    static let `default` = ModelAggregateQuery(scope: .all)
}

struct ModelAggregate: Identifiable, Hashable, Sendable {
    static let unknownModelID = "unknown-model"
    static let unknownModelDisplayName = "Unknown Model"

    let model: String?
    let usage: TokenUsage
    let sessionCount: Int

    var id: String {
        model ?? Self.unknownModelID
    }

    var displayName: String {
        model ?? Self.unknownModelDisplayName
    }

    var isUnknownModel: Bool {
        model == nil
    }
}

struct ModelTrendQuery: Hashable, Sendable {
    let modelID: String
    let granularity: TrendGranularity
    let scope: AnalysisScope
}

struct ModelSessionContributionQuery: Hashable, Sendable {
    let modelID: String
    let scope: AnalysisScope
    let limit: Int?
}

struct ModelSessionContribution: Identifiable, Hashable, Sendable {
    let session: UsageSession
    let attributedUsage: TokenUsage

    var id: String {
        session.id
    }
}

enum ImportedFileStatus: String, Codable, Hashable, Sendable {
    case imported
    case excluded
    case failed
}

struct ImportedFile: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let fileSize: Int64?
    let modifiedAt: Date?
    let importStatus: ImportedFileStatus
}

struct ImportWarning: Identifiable, Hashable, Sendable {
    let id: String
    let code: String
    let message: String
    let path: String
    let line: Int?
}

struct PricingProfile: Hashable, Sendable {
    let reviewedOn: String?
    let name: String
    let description: String
    let inputRatePerMillion: Decimal
    let cachedInputRatePerMillion: Decimal
    let outputRatePerMillion: Decimal

    var id: String {
        name
    }

    var formulaText: String {
        "Estimated cost = uncached input × \(inputRatePerMillion.decimalDisplayString)/M + cached input × \(cachedInputRatePerMillion.decimalDisplayString)/M + output × \(outputRatePerMillion.decimalDisplayString)/M"
    }
}

struct BillableTokenBreakdown: Hashable, Sendable {
    let uncachedInputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
}

struct CostEstimateQuery: Hashable, Sendable {
    let pricingProfileName: String?
    let scope: AnalysisScope

    static let `default` = CostEstimateQuery(
        pricingProfileName: nil,
        scope: .all
    )
}

struct CostTrendQuery: Hashable, Sendable {
    let pricingProfileName: String
    let granularity: TrendGranularity
    let scope: AnalysisScope
}

struct CostEstimate: Hashable, Sendable {
    let profile: PricingProfile
    let usage: TokenUsage
    let billableTokens: BillableTokenBreakdown
    let estimatedCost: Decimal
}

struct CostTrendBucket: Identifiable, Hashable, Sendable {
    let startDate: Date
    let estimatedCost: Decimal
    let usage: TokenUsage

    var id: Date {
        startDate
    }
}

enum CostEstimateStatus: String, Hashable, Sendable {
    case unavailable
}

struct UsageOverviewSummary: Hashable, Sendable {
    let inputPath: String
    let scannedFiles: Int
    let countedSessions: Int
    let excludedFiles: Int
    let warningCount: Int
    let usage: TokenUsage
    let estimatedCostStatus: CostEstimateStatus
    let importedAt: Date
}

struct ImportProgress: Hashable, Sendable {
    let totalFiles: Int
    let processedFiles: Int
    let countedSessions: Int
    let warningCount: Int

    var fractionCompleted: Double {
        guard totalFiles > 0 else {
            return 0
        }
        return Double(processedFiles) / Double(totalFiles)
    }
}

struct ImportResult: Sendable {
    let summary: UsageOverviewSummary
    let importedFiles: [ImportedFile]
    let sessions: [UsageSession]
    let segments: [UsageSegment]
    let warnings: [ImportWarning]
}

extension Decimal {
    var decimalDisplayString: String {
        NSDecimalNumber(decimal: self).stringValue
    }
}
