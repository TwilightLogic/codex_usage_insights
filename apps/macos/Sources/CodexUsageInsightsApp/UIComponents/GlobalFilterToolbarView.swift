import SwiftUI

struct GlobalFilterToolbarView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Picker("Range", selection: rangePresetBinding) {
                ForEach(AnalysisRangePreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            if model.primaryFilters.rangePreset == .custom {
                DatePicker(
                    "Start",
                    selection: customStartDateBinding,
                    displayedComponents: .date
                )
                .labelsHidden()
                .frame(width: 130)

                DatePicker(
                    "End",
                    selection: customEndDateBinding,
                    displayedComponents: .date
                )
                .labelsHidden()
                .frame(width: 130)
            }

            Picker("Workspace", selection: workspaceBinding) {
                Text("All Workspaces")
                    .tag(String?.none)

                ForEach(model.availableWorkspacePaths, id: \.self) { workspacePath in
                    Text(workspaceLabel(for: workspacePath))
                        .tag(Optional(workspacePath))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)

            Picker("Model", selection: modelBinding) {
                Text("All Models")
                    .tag(String?.none)

                ForEach(model.availableModelFilters, id: \.id) { aggregate in
                    Text(aggregate.displayName)
                        .tag(Optional(aggregate.id))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Toggle("Warnings Only", isOn: warningsOnlyBinding)
                .toggleStyle(.button)
        }
        .disabled(model.summary == nil || model.isImporting)
    }

    private var rangePresetBinding: Binding<AnalysisRangePreset> {
        Binding(
            get: { model.primaryFilters.rangePreset },
            set: { model.selectRangePreset($0) }
        )
    }

    private var customStartDateBinding: Binding<Date> {
        Binding(
            get: { model.primaryFilters.customStartDate },
            set: { model.updateCustomStartDate($0) }
        )
    }

    private var customEndDateBinding: Binding<Date> {
        Binding(
            get: { model.primaryFilters.customEndDate },
            set: { model.updateCustomEndDate($0) }
        )
    }

    private var workspaceBinding: Binding<String?> {
        Binding(
            get: { model.primaryFilters.workspacePath },
            set: { model.selectWorkspaceFilter(path: $0) }
        )
    }

    private var modelBinding: Binding<String?> {
        Binding(
            get: { model.primaryFilters.modelID },
            set: { model.selectModelFilter(id: $0) }
        )
    }

    private var warningsOnlyBinding: Binding<Bool> {
        Binding(
            get: { model.primaryFilters.warningsOnly },
            set: { model.setWarningsOnly($0) }
        )
    }

    private func workspaceLabel(for workspacePath: String) -> String {
        let name = URL(fileURLWithPath: workspacePath).lastPathComponent
        return name.isEmpty ? workspacePath : name
    }
}
