import SwiftUI
import ICCeryCore

/// `#savePresetDialog` — save the live Stage 1/2 form as a custom
/// preset (issue #11). Names/descriptions render via `Text` only (#114).
struct SavePresetDialog: View {
    @ObservedObject var workflow: TargetWorkflowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Preset").font(.title3).foregroundStyle(Theme.text)
            TextField("Name", text: $workflow.savePresetName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("savePresetName")
            TextField("Description (optional)", text: $workflow.savePresetDesc)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("savePresetDesc")
            HStack {
                Spacer()
                Button("Cancel") { workflow.showingSavePreset = false }
                    .accessibilityIdentifier("btnCloseSavePresetDialog")
                Button("Save") { workflow.saveCurrentAsPreset() }
                    .accessibilityIdentifier("btnConfirmSavePreset")
                    .disabled(workflow.savePresetName
                        .trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("savePresetDialog")
    }
}

/// `#managePresetsDialog` — list, delete (custom only), import, export.
struct ManagePresetsDialog: View {
    @ObservedObject var workflow: TargetWorkflowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Presets").font(.title3).foregroundStyle(Theme.text)
            List {
                ForEach(workflow.presets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name).foregroundStyle(Theme.text)
                            if !preset.description.isEmpty {
                                Text(preset.description)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if PresetCatalog.isBuiltIn(preset.id) {
                            Text("Built-in")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Export") { workflow.exportPreset(preset) }
                                .accessibilityIdentifier(
                                    "btnExportPreset-\(preset.id)")
                            Button("Delete", role: .destructive) {
                                workflow.deletePreset(preset)
                            }
                            .accessibilityIdentifier("btnDeletePreset-\(preset.id)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("presetRow-\(preset.id)")
                }
            }
            .accessibilityIdentifier("managePresetsList")
            .frame(minHeight: 240)
            HStack {
                Button("Import…") { workflow.importPreset() }
                    .accessibilityIdentifier("btnImportPreset")
                if let selected = workflow.selectedPreset,
                   !PresetCatalog.isBuiltIn(selected.id) {
                    Button("Export Active") { workflow.exportPreset(selected) }
                        .accessibilityIdentifier("btnExportActivePreset")
                }
                Spacer()
                Button("Close") { workflow.showingManagePresets = false }
                    .accessibilityIdentifier("btnCloseManagePresetsDialog")
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("managePresetsDialog")
    }
}
