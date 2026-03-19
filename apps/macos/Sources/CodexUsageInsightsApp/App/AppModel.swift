import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let foregroundRefreshStalenessInterval: TimeInterval = 60

    var selectedDestination: SidebarDestination? = .dashboard
    var selectedDirectoryURL: URL?
    var importProgress: ImportProgress?
    var selectedTrendGranularity: TrendGranularity = .day
    var summary: UsageOverviewSummary?
    var trendBuckets: [UsageTrendBucket] = []
    var topSessions: [UsageSession] = []
    var importedSessions: [UsageSession] = []
    var sessionRows: [UsageSession] = []
    var recentWarnings: [ImportWarning] = []
    var errorMessage: String?

    @ObservationIgnored
    private let directoryPicker: DirectoryPicking

    @ObservationIgnored
    private let importService: LogImporting

    @ObservationIgnored
    private let repository: InMemoryAnalyticsRepository

    @ObservationIgnored
    private let launchConfiguration: LaunchConfiguration

    @ObservationIgnored
    private var automaticImportDidRun = false

    @ObservationIgnored
    private var latestImportResult: ImportResult?

    init(
        directoryPicker: DirectoryPicking = AppKitDirectoryPicker(),
        importService: LogImporting = LogImportService(),
        repository: InMemoryAnalyticsRepository = InMemoryAnalyticsRepository(),
        launchConfiguration: LaunchConfiguration = .fromEnvironment()
    ) {
        self.directoryPicker = directoryPicker
        self.importService = importService
        self.repository = repository
        self.launchConfiguration = launchConfiguration

        if let autoImportPath = launchConfiguration.autoImportPath {
            selectedDirectoryURL = URL(fileURLWithPath: autoImportPath, isDirectory: true)
        }
    }

    var isImporting: Bool {
        importProgress != nil
    }

    var canImport: Bool {
        selectedDirectoryURL != nil && !isImporting
    }

    var canRefresh: Bool {
        selectedDirectoryURL != nil && summary != nil && !isImporting
    }

    func chooseDirectory() {
        if let directoryURL = directoryPicker.pickDirectory() {
            selectedDirectoryURL = directoryURL
            errorMessage = nil
        }
    }

    func performAutomaticImportIfNeeded() {
        guard !automaticImportDidRun else {
            return
        }
        guard launchConfiguration.autoImportPath != nil else {
            return
        }

        automaticImportDidRun = true
        importLogs()
    }

    func importLogs() {
        guard !isImporting, let directoryURL = selectedDirectoryURL else {
            return
        }

        errorMessage = nil
        importProgress = ImportProgress(
            totalFiles: 0,
            processedFiles: 0,
            countedSessions: 0,
            warningCount: 0
        )

        let progressHandler: @Sendable (ImportProgress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.importProgress = progress
            }
        }

        let importService = self.importService
        let repository = self.repository
        let previousResult = latestImportResult?.summary.inputPath == directoryURL.path
            ? latestImportResult
            : nil

        Task {
            do {
                let result = try await importService.importLogs(
                    from: directoryURL,
                    previousResult: previousResult,
                    progress: progressHandler
                )
                await repository.replace(with: result)

                latestImportResult = result
                summary = await repository.currentSummary()
                trendBuckets = await repository.trendBuckets(
                    matching: TrendQuery(
                        granularity: selectedTrendGranularity,
                        dateInterval: nil
                    ),
                    calendar: .autoupdatingCurrent
                )
                topSessions = Array(
                    await repository.sessions(
                        matching: SessionListQuery(
                            searchText: "",
                            sort: .totalTokensDescending
                        )
                    ).prefix(5)
                )
                importedSessions = await repository.allSessions()
                sessionRows = await repository.sessions(matching: .default)
                recentWarnings = Array(result.warnings.prefix(5))
                importProgress = nil
                emitAutomationOutputIfNeeded(for: result.summary)
            } catch {
                importProgress = nil
                errorMessage = error.localizedDescription
                emitAutomationFailureIfNeeded(error)
            }
        }
    }

    func refreshIfNeededOnForeground() {
        guard canRefresh, let summary else {
            return
        }

        let secondsSinceLastImport = Date().timeIntervalSince(summary.importedAt)
        guard secondsSinceLastImport >= foregroundRefreshStalenessInterval else {
            return
        }

        importLogs()
    }

    func sessionDetail(for sessionID: String?) async -> SessionDetailPayload? {
        guard let sessionID else {
            return nil
        }

        return await repository.sessionDetail(withID: sessionID)
    }

    func refreshSessionRows(
        searchText: String,
        sort: SessionListSort
    ) {
        let repository = self.repository
        let query = SessionListQuery(searchText: searchText, sort: sort)

        Task {
            sessionRows = await repository.sessions(matching: query)
        }
    }

    func refreshDashboardData() {
        let repository = self.repository
        let selectedTrendGranularity = self.selectedTrendGranularity

        Task {
            trendBuckets = await repository.trendBuckets(
                matching: TrendQuery(
                    granularity: selectedTrendGranularity,
                    dateInterval: nil
                ),
                calendar: .autoupdatingCurrent
            )
            topSessions = Array(
                await repository.sessions(
                    matching: SessionListQuery(
                        searchText: "",
                        sort: .totalTokensDescending
                    )
                ).prefix(5)
            )
        }
    }

    func openSessionsWorkspace() {
        selectedDestination = .sessions
    }

    private func emitAutomationOutputIfNeeded(for summary: UsageOverviewSummary) {
        guard launchConfiguration.shouldPrintImportSummary || launchConfiguration.shouldExitAfterImport else {
            return
        }

        let output = [
            "AUTO_IMPORT_SUMMARY",
            "path=\(summary.inputPath)",
            "scanned=\(summary.scannedFiles)",
            "counted=\(summary.countedSessions)",
            "excluded=\(summary.excludedFiles)",
            "warnings=\(summary.warningCount)",
            "total_tokens=\(summary.usage.totalTokens)"
        ].joined(separator: " ")

        if launchConfiguration.shouldPrintImportSummary {
            FileHandle.standardOutput.write(Data((output + "\n").utf8))
        }

        if launchConfiguration.shouldExitAfterImport {
            NSApplication.shared.terminate(nil)
        }
    }

    private func emitAutomationFailureIfNeeded(_ error: Error) {
        guard launchConfiguration.shouldPrintImportSummary || launchConfiguration.shouldExitAfterImport else {
            return
        }

        let output = "AUTO_IMPORT_ERROR message=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))"
        FileHandle.standardError.write(Data((output + "\n").utf8))

        if launchConfiguration.shouldExitAfterImport {
            NSApplication.shared.terminate(nil)
        }
    }
}

struct LaunchConfiguration: Sendable {
    let autoImportPath: String?
    let shouldPrintImportSummary: Bool
    let shouldExitAfterImport: Bool

    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchConfiguration {
        LaunchConfiguration(
            autoImportPath: environment["CODEX_USAGE_AUTO_IMPORT_PATH"],
            shouldPrintImportSummary: environment["CODEX_USAGE_PRINT_IMPORT_SUMMARY"] == "1",
            shouldExitAfterImport: environment["CODEX_USAGE_EXIT_AFTER_IMPORT"] == "1"
        )
    }
}
