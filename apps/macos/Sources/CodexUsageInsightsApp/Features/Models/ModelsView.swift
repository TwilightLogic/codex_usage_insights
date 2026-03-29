import SwiftUI

struct ModelsView: View {
    @Bindable var model: AppModel

    @State private var selectedModelID: ModelAggregate.ID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                if let importProgress = model.importProgress {
                    ImportActivityBanner(
                        progress: importProgress,
                        hasPriorData: !model.importedSessions.isEmpty
                    )
                }

                if model.importedSessions.isEmpty, model.importProgress == nil {
                    ContentUnavailableView(
                        "No imported usage yet",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Import logs from Dashboard first, then come back here to inspect attributed model usage.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.modelRows.isEmpty, model.importProgress == nil {
                    ContentUnavailableView(
                        "No model usage matches the current filters",
                        systemImage: "questionmark.square.dashed",
                        description: Text("Imported sessions exist, but the active analysis scope does not currently include attributed segments for model analysis.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if model.modelRows.contains(where: \.isUnknownModel) {
                        partialAttributionBanner
                    }

                    Table(model.modelRows, selection: $selectedModelID) {
                        TableColumn("Model") { aggregate in
                            HStack(spacing: 8) {
                                Text(aggregate.displayName)
                                    .fontWeight(aggregate.isUnknownModel ? .semibold : .regular)
                                if aggregate.isUnknownModel {
                                    Text("Partial")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.orange.opacity(0.16), in: Capsule())
                                }
                            }
                        }

                        TableColumn("Attributed Tokens") { aggregate in
                            Text(aggregate.usage.totalTokens.formatted())
                        }

                        TableColumn("Sessions") { aggregate in
                            Text(aggregate.sessionCount.formatted())
                        }
                    }
                }
            }
            .frame(minWidth: 420, idealWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)

            ModelDetailView(
                aggregate: selectedAggregate,
                trendBuckets: model.modelTrendBuckets,
                granularity: $model.selectedModelTrendGranularity,
                contributions: model.modelContributionRows,
                onOpenSessions: model.openSessionsWorkspace
            )
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 440, maxHeight: .infinity)
            .padding(20)
        }
        .navigationTitle("Models")
        .onAppear {
            if model.summary != nil && model.modelRows.isEmpty {
                model.refreshModelsData()
            }
            normalizeSelection()
            loadSelectedModelDetail()
        }
        .onChange(of: model.modelRows.map(\.id)) {
            normalizeSelection()
            loadSelectedModelDetail()
        }
        .onChange(of: selectedModelID) {
            loadSelectedModelDetail()
        }
        .onChange(of: model.selectedModelTrendGranularity) {
            loadSelectedModelDetail()
        }
    }

    private var selectedAggregate: ModelAggregate? {
        guard let selectedModelID else {
            return nil
        }
        return model.modelRows.first(where: { $0.id == selectedModelID })
    }

    private var partialAttributionBanner: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Some usage could not be tied to a specific model")
                    .font(.headline)
                Text("Those segments stay visible under Unknown Model instead of being guessed. Treat per-model totals as partial attribution when this banner appears.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Partial Attribution", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func normalizeSelection() {
        guard !model.modelRows.isEmpty else {
            selectedModelID = nil
            return
        }

        if let selectedModelID, model.modelRows.contains(where: { $0.id == selectedModelID }) {
            return
        }

        selectedModelID = model.modelRows.first?.id
    }

    private func loadSelectedModelDetail() {
        model.refreshModelDetail(for: selectedModelID)
    }
}

private struct ModelDetailView: View {
    let aggregate: ModelAggregate?
    let trendBuckets: [UsageTrendBucket]
    @Binding var granularity: TrendGranularity
    let contributions: [ModelSessionContribution]
    let onOpenSessions: () -> Void

    var body: some View {
        if let aggregate {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Model Detail")
                        .font(.title3.weight(.semibold))

                    if aggregate.isUnknownModel {
                        GroupBox {
                            Text("Unknown Model groups segments that had usable token deltas but no nearby turn_context model to attribute them to.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Attribution Caveat", systemImage: "questionmark.circle")
                        }
                    }

                    GroupBox {
                        detailRow(title: "Model", value: aggregate.displayName)
                        Divider()
                        detailRow(title: "Attributed Tokens", value: aggregate.usage.totalTokens.formatted())
                        Divider()
                        detailRow(title: "Sessions With Attribution", value: aggregate.sessionCount.formatted())
                        Divider()
                        detailRow(title: "Uncached Input", value: aggregate.usage.uncachedInputTokens.formatted())
                        Divider()
                        detailRow(title: "Output Tokens", value: aggregate.usage.outputTokens.formatted())
                    } label: {
                        Label("Attributed Usage", systemImage: "chart.bar")
                    }

                    GroupBox {
                        HStack {
                            Text("Model Trend")
                                .font(.title3.weight(.semibold))
                            Spacer()
                            Picker("Granularity", selection: $granularity) {
                                ForEach(TrendGranularity.allCases) { option in
                                    Text(option.title)
                                        .tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 280)
                        }

                        UsageTrendChartView(
                            buckets: trendBuckets,
                            granularity: granularity
                        )
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Top Session Contributions")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Button("Open Sessions", action: onOpenSessions)
                            }

                            if contributions.isEmpty {
                                Text("No session contributions match this model in the current imported range.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(contributions) { contribution in
                                    Button(action: onOpenSessions) {
                                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(contribution.session.id)
                                                    .font(.headline)
                                                    .lineLimit(1)
                                                Text(contribution.session.workspaceName)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                Text(contribution.session.observedAt.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text(contribution.attributedUsage.totalTokens.formatted())
                                                    .font(.body.weight(.semibold))
                                                Text(attributionShareText(contribution: contribution, totalTokens: aggregate.usage.totalTokens))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if contribution.id != contributions.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Select a model",
                systemImage: "square.stack.3d.up",
                description: Text("Pick a model on the left to inspect its attributed usage trend and session contributions.")
            )
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attributionShareText(
        contribution: ModelSessionContribution,
        totalTokens: Int
    ) -> String {
        guard totalTokens > 0 else {
            return "0% of model total"
        }

        let percent = Double(contribution.attributedUsage.totalTokens) / Double(totalTokens)
        return percent.formatted(.percent.precision(.fractionLength(0))) + " of model total"
    }
}
