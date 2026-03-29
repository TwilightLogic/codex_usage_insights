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
            VStack(spacing: 0) {
                if let recoverableError = model.recoverableError {
                    RecoverableErrorBanner(
                        errorState: recoverableError,
                        onRetry: model.importLogs,
                        onChooseFolder: model.chooseDirectory,
                        onReset: model.resetImportedData,
                        onDismiss: model.clearRecoverableError
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                Group {
                    switch model.selectedDestination ?? .dashboard {
                    case .dashboard:
                        OverviewView(model: model)
                    case .sessions:
                        SessionsView(model: model)
                    case .models:
                        ModelsView(model: model)
                    case .cost:
                        CostView(model: model)
                    case .settings:
                        PlaceholderDestinationView(destination: model.selectedDestination ?? .dashboard)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                GlobalFilterToolbarView(model: model)
            }

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

private struct RecoverableErrorBanner: View {
    let errorState: RecoverableErrorState
    let onRetry: () -> Void
    let onChooseFolder: () -> Void
    let onReset: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(errorState.title)
                            .font(.headline)
                        Text(errorState.message)
                        Text(errorState.resetSuggestion)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                }

                HStack(spacing: 12) {
                    Button("Retry", action: onRetry)
                    Button("Choose Folder", action: onChooseFolder)
                    Button("Reset Imported Data", action: onReset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Recoverable Error", systemImage: "exclamationmark.triangle.fill")
        }
    }
}
