import SwiftUI

struct SessionsView: View {
    @Bindable var model: AppModel

    @State private var searchText = ""
    @State private var selectedSessionID: UsageSession.ID?
    @State private var selectedSessionDetail: SessionDetailPayload?
    @State private var sortOrder = [
        KeyPathComparator(\UsageSession.observedAt, order: .reverse)
    ]

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search sessions", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                if model.importedSessions.isEmpty {
                    ContentUnavailableView(
                        "No imported sessions yet",
                        systemImage: "tray",
                        description: Text("Run an import from Dashboard first, then come back here to inspect sessions.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.sessionRows.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(model.sessionRows, selection: $selectedSessionID, sortOrder: $sortOrder) {
                        TableColumn("Session", value: \.id)
                        TableColumn("Workspace", value: \.workspaceName)
                        TableColumn("Observed", value: \.observedAt) { session in
                            Text(session.observedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        TableColumn("Total Tokens", value: \.totalTokens) { session in
                            Text(session.totalTokens.formatted())
                        }
                    }
                }
            }
            .frame(minWidth: 460, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)

            SessionDetailView(detail: selectedSessionDetail)
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 380, maxHeight: .infinity)
                .padding(20)
        }
        .navigationTitle("Sessions")
        .onAppear {
            refreshSessionRows()
            normalizeSelection()
            loadSelectedSessionDetail()
        }
        .onChange(of: model.importedSessions.count) {
            refreshSessionRows()
            normalizeSelection()
            loadSelectedSessionDetail()
        }
        .onChange(of: model.sessionRows.map(\.id)) {
            normalizeSelection()
        }
        .onChange(of: searchText) {
            refreshSessionRows()
        }
        .onChange(of: sortOrder) {
            refreshSessionRows()
        }
        .onChange(of: selectedSessionID) {
            loadSelectedSessionDetail()
        }
    }

    private func normalizeSelection() {
        guard !model.sessionRows.isEmpty else {
            selectedSessionID = nil
            selectedSessionDetail = nil
            return
        }

        if let selectedSessionID, model.sessionRows.contains(where: { $0.id == selectedSessionID }) {
            return
        }

        selectedSessionID = model.sessionRows.first?.id
    }

    private func loadSelectedSessionDetail() {
        let selectedSessionID = selectedSessionID
        Task {
            selectedSessionDetail = await model.sessionDetail(for: selectedSessionID)
        }
    }

    private func refreshSessionRows() {
        model.refreshSessionRows(
            searchText: searchText,
            sort: mappedSortOrder
        )
    }

    private var mappedSortOrder: SessionListSort {
        guard let primaryComparator = sortOrder.first else {
            return .observedAtDescending
        }

        if primaryComparator.keyPath == \UsageSession.totalTokens {
            return primaryComparator.order == .forward ? .totalTokensAscending : .totalTokensDescending
        }

        if primaryComparator.keyPath == \UsageSession.id {
            return primaryComparator.order == .forward ? .sessionIDAscending : .sessionIDDescending
        }

        if primaryComparator.keyPath == \UsageSession.workspaceName {
            return primaryComparator.order == .forward ? .workspaceAscending : .workspaceDescending
        }

        return primaryComparator.order == .forward ? .observedAtAscending : .observedAtDescending
    }
}

private struct SessionDetailView: View {
    let detail: SessionDetailPayload?

    var body: some View {
        if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Session Detail")
                        .font(.title3.weight(.semibold))

                    GroupBox {
                        detailRow(title: "Session ID", value: detail.session.id)
                        Divider()
                        detailRow(title: "Workspace", value: detail.session.workspaceName)
                        Divider()
                        detailRow(title: "Source File", value: detail.session.sourceFilename)
                        Divider()
                        detailRow(
                            title: "Observed At",
                            value: detail.session.observedAt.formatted(date: .abbreviated, time: .standard)
                        )
                    } label: {
                        Label("Metadata", systemImage: "info.circle")
                    }

                    GroupBox {
                        detailRow(title: "Total Tokens", value: detail.session.totalTokens.formatted())
                        Divider()
                        detailRow(title: "Input Tokens", value: detail.session.usage.inputTokens.formatted())
                        Divider()
                        detailRow(title: "Uncached Input", value: detail.session.usage.uncachedInputTokens.formatted())
                        Divider()
                        detailRow(title: "Cached Input", value: detail.session.usage.cachedInputTokens.formatted())
                        Divider()
                        detailRow(title: "Output Tokens", value: detail.session.usage.outputTokens.formatted())
                        Divider()
                        detailRow(title: "Reasoning Output", value: detail.session.usage.reasoningOutputTokens.formatted())
                    } label: {
                        Label("Usage", systemImage: "chart.bar")
                    }

                    GroupBox {
                        if detail.warnings.isEmpty {
                            Text("No parser warnings for this imported session.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(detail.warnings) { warning in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(warning.code)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(warning.message)
                                        .font(.body)
                                    if let line = warning.line {
                                        Text("Line \(line)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if warning.id != detail.warnings.last?.id {
                                    Divider()
                                }
                            }
                        }
                    } label: {
                        Label("Warnings", systemImage: "exclamationmark.triangle")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Select a session",
                systemImage: "rectangle.and.text.magnifyingglass",
                description: Text("Pick a row on the left to inspect the imported session summary.")
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
}
