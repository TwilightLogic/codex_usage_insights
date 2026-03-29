import Foundation
import Testing
@testable import CodexUsageInsightsApp

struct PrimaryFilterStoreTests {
    @Test
    func primaryFilterStorePersistsAndRestoresState() throws {
        let suiteName = "PrimaryFilterStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PrimaryFilterStore(defaults: defaults, storageKey: "filters")
        let savedState = AnalysisFilterState(
            rangePreset: .custom,
            customStartDate: Date(timeIntervalSince1970: 1_710_000_500),
            customEndDate: Date(timeIntervalSince1970: 1_710_100_500),
            workspacePath: "/tmp/workspace",
            modelID: "gpt-5.4",
            warningsOnly: true
        )

        store.save(savedState)
        let restoredState = store.load(now: Date(timeIntervalSince1970: 1_710_200_000))

        #expect(restoredState == savedState)
    }

    @Test
    func normalizedFiltersClearInvalidSelectionsAndNormalizeCustomDates() {
        let start = Date(timeIntervalSince1970: 1_710_200_000)
        let end = Date(timeIntervalSince1970: 1_710_100_000)

        let state = AnalysisFilterState(
            rangePreset: .custom,
            customStartDate: start,
            customEndDate: end,
            workspacePath: "/tmp/unknown",
            modelID: "unknown-model-id",
            warningsOnly: false
        )

        let normalizedState = state.normalized(
            availableWorkspacePaths: ["/tmp/known-workspace"],
            availableModelIDs: ["gpt-5.4"]
        )

        #expect(normalizedState.workspacePath == nil)
        #expect(normalizedState.modelID == nil)
        #expect(normalizedState.customStartDate == end)
        #expect(normalizedState.customEndDate == start)
    }
}
