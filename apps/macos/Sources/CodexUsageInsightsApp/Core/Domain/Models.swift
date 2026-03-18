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
}

struct UsageSegment: Identifiable, Hashable, Sendable {
    let id: String
    let sessionID: String
    let sequence: Int
    let timestamp: Date
    let model: String?
    let usage: TokenUsage
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
    let name: String
    let description: String
    let inputRatePerMillion: Double
    let cachedInputRatePerMillion: Double
    let outputRatePerMillion: Double
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
    let warnings: [ImportWarning]
}
