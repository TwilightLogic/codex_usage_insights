import SwiftUI

struct OverviewView: View {
    @Bindable var model: AppModel

    private let metrics = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Import local Codex logs and verify the first end-to-end slice before we build deeper analytics.")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                sourceControls

                if let importProgress = model.importProgress {
                    progressPanel(importProgress)
                }

                if let errorMessage = model.errorMessage {
                    GroupBox {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Import Failed", systemImage: "exclamationmark.triangle")
                    }
                }

                if let summary = model.summary {
                    summaryPanel(summary)
                } else if !model.isImporting {
                    emptyState
                }

                if !model.recentWarnings.isEmpty {
                    warningsPanel
                }
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
    }

    private var sourceControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.selectedDirectoryURL?.path ?? "No log folder selected yet.")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(model.selectedDirectoryURL == nil ? .secondary : .primary)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    Button("Choose Log Folder") {
                        model.chooseDirectory()
                    }

                    Button("Import Logs") {
                        model.importLogs()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canImport)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Log Source", systemImage: "folder")
        }
    }

    private func progressPanel(_ progress: ImportProgress) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: progress.fractionCompleted)

                Text("Processed \(progress.processedFiles) of \(progress.totalFiles) files")
                    .font(.headline)

                HStack(spacing: 20) {
                    Text("Counted sessions: \(progress.countedSessions)")
                    Text("Warnings: \(progress.warningCount)")
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Import In Progress", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private func summaryPanel(_ summary: UsageOverviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Import Summary")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(summary.importedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: metrics, spacing: 16) {
                MetricTileView(title: "Scanned Files", value: "\(summary.scannedFiles)")
                MetricTileView(title: "Counted Sessions", value: "\(summary.countedSessions)")
                MetricTileView(title: "Excluded Files", value: "\(summary.excludedFiles)")
                MetricTileView(title: "Warnings", value: "\(summary.warningCount)")
                MetricTileView(title: "Total Tokens", value: summary.usage.totalTokens.formatted())
                MetricTileView(title: "Input Tokens", value: summary.usage.inputTokens.formatted())
                MetricTileView(title: "Uncached Input", value: summary.usage.uncachedInputTokens.formatted())
                MetricTileView(title: "Cached Input", value: summary.usage.cachedInputTokens.formatted())
                MetricTileView(title: "Output Tokens", value: summary.usage.outputTokens.formatted())
                MetricTileView(title: "Reasoning Output", value: summary.usage.reasoningOutputTokens.formatted())
                MetricTileView(title: "Estimated Cost", value: "Unavailable", emphasis: false)
            }
        }
    }

    private var warningsPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.recentWarnings) { warning in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(warning.message)
                            .font(.headline)
                        Text(URL(fileURLWithPath: warning.path).lastPathComponent)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(warning.code)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if warning.id != model.recentWarnings.last?.id {
                        Divider()
                    }
                }
            }
        } label: {
            Label("Recent Warnings", systemImage: "exclamationmark.circle")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Choose a local Codex sessions folder",
            systemImage: "tray",
            description: Text("This first slice only validates the import path: pick a folder, run one import, and inspect the base summary.")
        )
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}
