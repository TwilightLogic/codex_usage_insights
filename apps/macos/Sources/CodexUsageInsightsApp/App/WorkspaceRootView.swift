import SwiftUI

struct WorkspaceRootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $model.selectedDestination) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationTitle("Codex Usage Insights")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch model.selectedDestination ?? .dashboard {
                case .dashboard:
                    OverviewView(model: model)
                case .sessions:
                    SessionsView(model: model)
                case .models, .cost, .settings:
                    PlaceholderDestinationView(destination: model.selectedDestination ?? .dashboard)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.importLogs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!model.canRefresh)
                .help("Refresh imported logs")
            }

            ToolbarItem(placement: .status) {
                if model.isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task {
            model.performAutomaticImportIfNeeded()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                model.refreshIfNeededOnForeground()
            }
        }
    }
}
