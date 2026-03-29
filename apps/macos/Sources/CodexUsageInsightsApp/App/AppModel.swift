import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let foregroundRefreshStalenessInterval: TimeInterval = 60
    private let recentWarningLimit = 5

    var selectedDestination: SidebarDestination? = .dashboard
    var selectedDirectoryURL: URL?
    var importProgress: ImportProgress?
    var primaryFilters: AnalysisFilterState
    var selectedTrendGranularity: TrendGranularity = .day
    var summary: UsageOverviewSummary?
    var scopedSummary: ScopedUsageSummary?
    var trendBuckets: [UsageTrendBucket] = []
    var topSessions: [UsageSession] = []
    var importedSessions: [UsageSession] = []
    var availableWorkspacePaths: [String] = []
    var sessionRows: [UsageSession] = []
    var sessionSearchText = ""
    var sessionSort: SessionListSort = .observedAtDescending
    var availableModelFilters: [ModelAggregate] = []
    var modelRows: [ModelAggregate] = []
    var selectedModelTrendGranularity: TrendGranularity = .day
    var modelTrendBuckets: [UsageTrendBucket] = []
    var modelContributionRows: [ModelSessionContribution] = []
    var availablePricingProfiles: [PricingProfile] = []
    var selectedPricingProfileName: String?
    var costEstimate: CostEstimate?
    var costTrendBuckets: [CostTrendBucket] = []
    var recentWarnings: [ImportWarning] = []
    var recoverableError: RecoverableErrorState?

    @ObservationIgnored
    private let directoryPicker: DirectoryPicking

    @ObservationIgnored
    private let importService: LogImporting

    @ObservationIgnored
    private let repository: InMemoryAnalyticsRepository

    @ObservationIgnored
    private let primaryFilterStore: PrimaryFilterStore

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
        primaryFilterStore: PrimaryFilterStore = PrimaryFilterStore(),
        launchConfiguration: LaunchConfiguration = .fromEnvironment()
    ) {
        let restoredPrimaryFilters = primaryFilterStore.load()

        self.directoryPicker = directoryPicker
        self.importService = importService
        self.repository = repository
        self.primaryFilterStore = primaryFilterStore
        self.launchConfiguration = launchConfiguration
        self.primaryFilters = restoredPrimaryFilters

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
            recoverableError = nil
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

        recoverableError = nil
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
                await refreshAllAnalysisState(using: repository)
                modelTrendBuckets = []
                modelContributionRows = []
                importProgress = nil
                emitAutomationOutputIfNeeded(for: result.summary)
            } catch {
                importProgress = nil
                recoverableError = RecoverableErrorState(error: error)
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
        sessionSearchText = searchText
        sessionSort = sort
        let repository = self.repository
        let query = SessionListQuery(
            searchText: searchText,
            sort: sort,
            scope: currentScope()
        )

        Task {
            sessionRows = await repository.sessions(matching: query)
        }
    }

    func refreshDashboardData() {
        let repository = self.repository
        let selectedTrendGranularity = self.selectedTrendGranularity
        let scope = currentScope()

        Task {
            scopedSummary = await repository.scopedUsageSummary(matching: scope)
            trendBuckets = await repository.trendBuckets(
                matching: TrendQuery(
                    granularity: selectedTrendGranularity,
                    scope: scope
                ),
                calendar: .autoupdatingCurrent
            )
            topSessions = Array(
                await repository.sessions(
                    matching: SessionListQuery(
                        searchText: "",
                        sort: .totalTokensDescending,
                        scope: scope
                    )
                ).prefix(5)
            )
            recentWarnings = await repository.warnings(matching: scope, limit: recentWarningLimit)
            await refreshCostState(using: repository, scope: scope)
        }
    }

    func refreshModelsData() {
        let repository = self.repository
        let scope = currentScope()

        Task {
            modelRows = await repository.modelAggregates(
                matching: ModelAggregateQuery(scope: scope)
            )
        }
    }

    func refreshModelDetail(for modelID: String?) {
        guard let modelID else {
            modelTrendBuckets = []
            modelContributionRows = []
            return
        }

        let repository = self.repository
        let selectedModelTrendGranularity = self.selectedModelTrendGranularity
        let scope = currentScope()

        Task {
            modelTrendBuckets = await repository.modelTrendBuckets(
                matching: ModelTrendQuery(
                    modelID: modelID,
                    granularity: selectedModelTrendGranularity,
                    scope: scope
                ),
                calendar: .autoupdatingCurrent
            )
            modelContributionRows = await repository.modelSessionContributions(
                matching: ModelSessionContributionQuery(
                    modelID: modelID,
                    scope: scope,
                    limit: 8
                )
            )
        }
    }

    func refreshPricingProfiles() {
        let repository = self.repository

        Task {
            availablePricingProfiles = await repository.availablePricingProfiles()
            await refreshCostState(using: repository, scope: currentScope())
        }
    }

    func refreshCostData() {
        let repository = self.repository
        let scope = currentScope()

        Task {
            await refreshCostState(using: repository, scope: scope)
        }
    }

    func selectPricingProfile(named profileName: String?) {
        selectedPricingProfileName = profileName
        refreshCostData()
    }

    func selectRangePreset(_ preset: AnalysisRangePreset) {
        primaryFilters.rangePreset = preset
        persistAndRefreshPrimaryFilters()
    }

    func updateCustomStartDate(_ date: Date) {
        primaryFilters.customStartDate = date
        if primaryFilters.rangePreset != .custom {
            primaryFilters.rangePreset = .custom
        }
        persistAndRefreshPrimaryFilters()
    }

    func updateCustomEndDate(_ date: Date) {
        primaryFilters.customEndDate = date
        if primaryFilters.rangePreset != .custom {
            primaryFilters.rangePreset = .custom
        }
        persistAndRefreshPrimaryFilters()
    }

    func selectWorkspaceFilter(path: String?) {
        primaryFilters.workspacePath = path
        persistAndRefreshPrimaryFilters()
    }

    func selectModelFilter(id: String?) {
        primaryFilters.modelID = id
        persistAndRefreshPrimaryFilters()
    }

    func setWarningsOnly(_ warningsOnly: Bool) {
        primaryFilters.warningsOnly = warningsOnly
        persistAndRefreshPrimaryFilters()
    }

    func openSessionsWorkspace() {
        selectedDestination = .sessions
    }

    func clearRecoverableError() {
        recoverableError = nil
    }

    func resetImportedData() {
        let repository = self.repository

        Task {
            await repository.clear()
            summary = nil
            scopedSummary = nil
            trendBuckets = []
            topSessions = []
            importedSessions = []
            availableWorkspacePaths = []
            sessionRows = []
            availableModelFilters = []
            modelRows = []
            modelTrendBuckets = []
            modelContributionRows = []
            costEstimate = nil
            costTrendBuckets = []
            recentWarnings = []
            latestImportResult = nil
            recoverableError = nil
        }
    }

    private func refreshCostState(
        using repository: InMemoryAnalyticsRepository,
        scope: AnalysisScope
    ) async {
        costEstimate = await repository.costEstimate(
            matching: CostEstimateQuery(
                pricingProfileName: selectedPricingProfileName,
                scope: scope
            )
        )

        if let selectedPricingProfileName {
            costTrendBuckets = await repository.costTrendBuckets(
                matching: CostTrendQuery(
                    pricingProfileName: selectedPricingProfileName,
                    granularity: selectedTrendGranularity,
                    scope: scope
                ),
                calendar: .autoupdatingCurrent
            )
        } else {
            costTrendBuckets = []
        }
    }

    private func refreshAllAnalysisState(using repository: InMemoryAnalyticsRepository) async {
        importedSessions = await repository.allSessions()
        availableWorkspacePaths = Array(Set(importedSessions.compactMap(\.workspacePath))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

        let normalizedForWorkspaces = primaryFilters.normalized(
            availableWorkspacePaths: Set(availableWorkspacePaths),
            availableModelIDs: primaryFilters.modelID.map { [$0] } ?? []
        )

        availableModelFilters = await repository.modelAggregates(
            matching: ModelAggregateQuery(scope: scopeWithoutModelFilter(from: normalizedForWorkspaces))
        )

        let fullyNormalizedFilters = normalizedForWorkspaces.normalized(
            availableWorkspacePaths: Set(availableWorkspacePaths),
            availableModelIDs: Set(availableModelFilters.map(\.id))
        )

        if fullyNormalizedFilters != primaryFilters {
            primaryFilters = fullyNormalizedFilters
            primaryFilterStore.save(fullyNormalizedFilters)
        }

        let scope = currentScope()
        scopedSummary = await repository.scopedUsageSummary(matching: scope)
        trendBuckets = await repository.trendBuckets(
            matching: TrendQuery(
                granularity: selectedTrendGranularity,
                scope: scope
            ),
            calendar: .autoupdatingCurrent
        )
        topSessions = Array(
            await repository.sessions(
                matching: SessionListQuery(
                    searchText: "",
                    sort: .totalTokensDescending,
                    scope: scope
                )
            ).prefix(5)
        )
        sessionRows = await repository.sessions(
            matching: SessionListQuery(
                searchText: sessionSearchText,
                sort: sessionSort,
                scope: scope
            )
        )
        modelRows = await repository.modelAggregates(
            matching: ModelAggregateQuery(scope: scope)
        )
        recentWarnings = await repository.warnings(matching: scope, limit: recentWarningLimit)
        availablePricingProfiles = await repository.availablePricingProfiles()
        await refreshCostState(using: repository, scope: scope)
    }

    private func persistAndRefreshPrimaryFilters() {
        primaryFilters = primaryFilters.normalized(
            availableWorkspacePaths: Set(availableWorkspacePaths),
            availableModelIDs: Set(availableModelFilters.map(\.id))
        )
        primaryFilterStore.save(primaryFilters)

        let repository = self.repository
        Task {
            await refreshAllAnalysisState(using: repository)
        }
    }

    private func currentScope() -> AnalysisScope {
        primaryFilters.resolvedScope(calendar: .autoupdatingCurrent)
    }

    private func scopeWithoutModelFilter(from filters: AnalysisFilterState) -> AnalysisScope {
        AnalysisScope(
            dateInterval: filters.resolvedScope(calendar: .autoupdatingCurrent).dateInterval,
            workspacePath: filters.workspacePath,
            modelID: nil,
            warningsOnly: filters.warningsOnly
        )
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

struct RecoverableErrorState: Hashable {
    let title: String
    let message: String
    let resetSuggestion: String

    init(error: Error) {
        if let logImportError = error as? LogImportError {
            switch logImportError {
            case .invalidDirectory(let path):
                title = "Selected Folder Is Missing"
                message = "The app can no longer find a readable log folder at \(path). Choose a different folder or retry after restoring it."
                resetSuggestion = "You can also reset imported data if you want to clear the current workspace and start over."
            case .permissionDenied(let path):
                title = "Folder Access Was Denied"
                message = "The app does not currently have permission to read \(path). Retry after fixing permissions or choose another folder."
                resetSuggestion = "If the workspace is now out of sync, reset imported data and import again."
            }
        } else {
            title = "Import Failed"
            message = error.localizedDescription
            resetSuggestion = "Retry the import, choose a different folder, or reset imported data if the app state looks stale."
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
