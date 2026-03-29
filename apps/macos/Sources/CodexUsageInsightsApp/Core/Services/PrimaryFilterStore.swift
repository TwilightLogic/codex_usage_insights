import Foundation

struct PrimaryFilterStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "codex_usage_insights.primary_filters.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load(now: Date = Date()) -> AnalysisFilterState {
        guard
            let data = defaults.data(forKey: storageKey),
            let state = try? JSONDecoder().decode(AnalysisFilterState.self, from: data)
        else {
            return .default(now: now)
        }

        return state
    }

    func save(_ state: AnalysisFilterState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
