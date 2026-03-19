import SwiftUI

@main
struct CodexUsageInsightsApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self)
    private var appActivationDelegate

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("Codex Usage Insights") {
            WorkspaceRootView(model: appModel)
                .frame(minWidth: 960, minHeight: 620)
        }
    }
}
