import SwiftUI

struct OverviewView: View {
    @Bindable var model: AppModel

    private let metrics = [
        GridItem(.adaptive(minimum: 180), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Import local Codex logs once, then use the dashboard to spot usage spikes and jump into the sessions behind them.")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                sourceControls

                if let importProgress = model.importProgress {
                    progressPanel(importProgress)
                }

                if let errorMessage = model.errorMessage {
                    errorPanel(errorMessage)
                }

                if let summary = model.summary {
                    if summary.warningCount > 0 {
                        warningBanner(summary)
                    }

                    usageBar(summary)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) {
                            trendPanel
                            topSessionsPanel
                                .frame(width: 340)
                        }

                        VStack(alignment: .leading, spacing: 24) {
                            trendPanel
                            topSessionsPanel
                        }
                    }

                    importHealthPanel(summary)
                } else if !model.isImporting {
                    emptyState
                }
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .onAppear {
            if model.summary != nil && (model.trendBuckets.isEmpty || model.topSessions.isEmpty) {
                model.refreshDashboardData()
            }
        }
        .onChange(of: model.selectedTrendGranularity) {
            model.refreshDashboardData()
        }
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

                    Button(model.summary == nil ? "Import Logs" : "Refresh Logs") {
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

    private func errorPanel(_ errorMessage: String) -> some View {
        GroupBox {
            Text(errorMessage)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Import Failed", systemImage: "exclamationmark.triangle")
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

    private func usageBar(_ summary: UsageOverviewSummary) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Usage Overview")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(summary.importedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: metrics, spacing: 16) {
                    MetricTileView(title: "Counted Sessions", value: "\(summary.countedSessions)")
                    MetricTileView(title: "Total Tokens", value: summary.usage.totalTokens.formatted())
                    MetricTileView(title: "Uncached Input", value: summary.usage.uncachedInputTokens.formatted())
                    MetricTileView(title: "Cached Input", value: summary.usage.cachedInputTokens.formatted())
                    MetricTileView(title: "Output Tokens", value: summary.usage.outputTokens.formatted())
                    MetricTileView(title: "Estimated Cost", value: "Unavailable", emphasis: false)
                }
            }
        }
    }

    private var trendPanel: some View {
        GroupBox {
            HStack {
                Text("Usage Trend")
                    .font(.title3.weight(.semibold))
                Spacer()
                Picker("Granularity", selection: $model.selectedTrendGranularity) {
                    ForEach(TrendGranularity.allCases) { granularity in
                        Text(granularity.title)
                            .tag(granularity)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }

            UsageTrendChartView(
                buckets: model.trendBuckets,
                granularity: model.selectedTrendGranularity
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var topSessionsPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Top Sessions")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Open Sessions") {
                        model.openSessionsWorkspace()
                    }
                }

                if model.topSessions.isEmpty {
                    Text("Import logs to see the sessions driving the most usage.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.topSessions) { session in
                        Button {
                            model.openSessionsWorkspace()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.id)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(session.workspaceName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(session.observedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(session.totalTokens.formatted())
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if session.id != model.topSessions.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func importHealthPanel(_ summary: UsageOverviewSummary) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Import Health")
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: metrics, spacing: 16) {
                    MetricTileView(title: "Scanned Files", value: "\(summary.scannedFiles)")
                    MetricTileView(title: "Excluded Files", value: "\(summary.excludedFiles)")
                    MetricTileView(title: "Warnings", value: "\(summary.warningCount)")
                    MetricTileView(title: "Reasoning Output", value: summary.usage.reasoningOutputTokens.formatted())
                }
            }
        }
    }

    private func warningBanner(_ summary: UsageOverviewSummary) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(summary.warningCount) import warning\(summary.warningCount == 1 ? "" : "s") need review")
                            .font(.headline)
                        Text("Some logs were skipped, partial, or malformed. The dashboard totals remain measured, but you should review the warning list before trusting edge cases.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Sessions") {
                        model.openSessionsWorkspace()
                    }
                }

                ForEach(model.recentWarnings.prefix(3)) { warning in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(warning.message)
                            .font(.subheadline.weight(.medium))
                        Text(URL(fileURLWithPath: warning.path).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            Label("Warnings", systemImage: "exclamationmark.triangle.fill")
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
