import SwiftUI

struct WorkspaceRootView: View {
    @Bindable var model: AppModel

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
        .task {
            model.performAutomaticImportIfNeeded()
        }
    }
}
