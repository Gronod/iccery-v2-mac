import SwiftUI
import ICCeryCore

/// `#saveMediaRecipeDialog` — capture the current printer + paper +
/// ink + `.cal` bound to the selected preset (issue #146). Clones
/// `SavePresetDialog` chrome; names render via `Text` only (#114).
struct SaveMediaRecipeDialog: View {
    @ObservedObject var workflow: TargetWorkflowViewModel
    /// Observed directly: nested ObservableObjects are not tracked
    /// through the parent's `objectWillChange`.
    @ObservedObject private var media: MediaLibraryViewModel
    @ObservedObject private var printSession: PrintSessionViewModel

    init(workflow: TargetWorkflowViewModel) {
        self.workflow = workflow
        self._media = ObservedObject(wrappedValue: workflow.media)
        self._printSession = ObservedObject(wrappedValue: workflow.print)
    }

    private var printerCaption: String {
        let queue = printSession.selectedPrinter
        guard !queue.isEmpty else { return "None" }
        let display = printSession.printers
            .first { $0.name == queue }?.displayName ?? queue
        return "\(display) (\(queue))"
    }

    private func captureRow(
        _ label: String, value: String, identifier: String
    ) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier(identifier)
        }
    }

    private var saveDisabled: Bool {
        media.saveMediaName.trimmingCharacters(in: .whitespaces).isEmpty
            || media.saveMediaPaper.trimmingCharacters(in: .whitespaces).isEmpty
            || media.saveMediaInk.trimmingCharacters(in: .whitespaces).isEmpty
            || media.captureColourSpaceMismatch
    }

    // Swift 5.7 (Xcode 14.2 CI runner) caps a ViewBuilder body at 10
    // children (#146); Group blocks are layout-transparent, so field
    // order and every docs/21 id are unchanged.
    private var fields: some View {
        Group {
            TextField("Name", text: $media.saveMediaName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("saveMediaName")
            TextField("Notes (optional)", text: $media.saveMediaNotes)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("saveMediaNotes")
            TextField("Paper", text: $media.saveMediaPaper)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("saveMediaPaper")
            TextField("Ink set", text: $media.saveMediaInk)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("saveMediaInk")
        }
    }

    private var readOnlyRows: some View {
        Group {
            captureRow("Printer", value: printerCaption,
                       identifier: "saveMediaPrinter")
            captureRow("Preset",
                       value: workflow.selectedPreset?.name ?? "No preset",
                       identifier: "saveMediaPreset")
            captureRow("Colour space",
                       value: workflow.colourSpace.rawValue.uppercased(),
                       identifier: "saveMediaColourSpace")
            captureRow("Calibration",
                       value: workflow.profile.calibrationFile.isEmpty
                           ? "None" : workflow.profile.calibrationFile,
                       identifier: "saveMediaCal")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Media Recipe").font(.title3).foregroundStyle(Theme.text)
            fields
            readOnlyRows
            Toggle("Apply calibration to profile",
                   isOn: $media.saveMediaApplyCal)
                .disabled(!media.calApplyable)
                .accessibilityIdentifier("saveMediaApplyCal")

            if media.captureColourSpaceMismatch {
                Text("Colour space does not match the selected preset.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let error = media.saveMediaError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { workflow.showingSaveMedia = false }
                    .accessibilityIdentifier("btnCloseSaveMediaDialog")
                Button("Save") {
                    Task {
                        if await media.captureFromSession() {
                            workflow.showingSaveMedia = false
                        }
                    }
                }
                .disabled(saveDisabled)
                .accessibilityIdentifier("btnConfirmSaveMedia")
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveMediaRecipeDialog")
    }
}

/// `#manageMediaDialog` — list, apply, delete, capture (issue #146).
/// `List`, not `Table` — macOS 12 target. Clones `ManagePresetsDialog`.
struct ManageMediaDialog: View {
    @ObservedObject var workflow: TargetWorkflowViewModel
    /// Observed directly: nested ObservableObjects are not tracked
    /// through the parent's `objectWillChange`.
    @ObservedObject private var media: MediaLibraryViewModel
    @State private var selection: String?
    @State private var pendingDelete: MediaRecipe?

    init(workflow: TargetWorkflowViewModel) {
        self.workflow = workflow
        self._media = ObservedObject(wrappedValue: workflow.media)
    }

    private func presetCaption(for recipe: MediaRecipe) -> String {
        workflow.presets.first { $0.id == recipe.presetID }?.name
            ?? "Missing preset"
    }

    private func calCaption(for recipe: MediaRecipe) -> String {
        if media.staleReasons[recipe.id]?.contains(.calibration) == true {
            return "Stale"
        }
        if let days = media.calAgeDays[recipe.id] {
            return "Cal \(days)d"
        }
        return "No cal"
    }

    private func applyAndDismiss(_ recipe: MediaRecipe) {
        Task {
            if await media.apply(recipe) {
                workflow.showingManageMedia = false
            }
        }
    }

    private func presetMissing(_ recipe: MediaRecipe) -> Bool {
        !workflow.presets.contains { $0.id == recipe.presetID }
    }

    private func calStale(_ recipe: MediaRecipe) -> Bool {
        media.staleReasons[recipe.id]?.contains(.calibration) == true
    }

    @ViewBuilder
    private func row(_ recipe: MediaRecipe) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name).foregroundStyle(Theme.text)
                Text("\(recipe.printerDisplayName) · \(recipe.paperName) · \(recipe.inkSet)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(presetCaption(for: recipe))
                        .font(.caption)
                        .foregroundStyle(presetMissing(recipe) ? .orange : .secondary)
                    Text(calCaption(for: recipe))
                        .font(.caption)
                        .foregroundStyle(calStale(recipe) ? .orange : .secondary)
                }
            }
            Spacer()
            Button("Apply") { applyAndDismiss(recipe) }
                .accessibilityIdentifier("btnMediaLibraryApply-\(recipe.id)")
            Button("Delete", role: .destructive) {
                pendingDelete = recipe
            }
            .accessibilityIdentifier("btnMediaLibraryDelete-\(recipe.id)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mediaRow-\(recipe.id)")
        .tag(recipe.id)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { applyAndDismiss(recipe) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Media Recipes").font(.title3).foregroundStyle(Theme.text)

            List(selection: $selection) {
                if media.recipes.isEmpty {
                    Text("No media recipes yet. Capture the current printer, paper and preset.")
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("mediaLibraryEmpty")
                }
                ForEach(media.recipes) { recipe in
                    row(recipe)
                }
            }
            .accessibilityIdentifier("mediaLibraryList")
            .frame(minHeight: 260)

            HStack {
                Button("Apply selected") {
                    if let id = selection,
                       let recipe = media.recipes.first(where: { $0.id == id }) {
                        applyAndDismiss(recipe)
                    }
                }
                .disabled(selection == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("btnMediaLibraryApply")
                Button("Capture current…") {
                    media.captureAfterManageDismiss = true
                    workflow.showingManageMedia = false
                }
                .accessibilityIdentifier("btnMediaLibraryCaptureFromManage")
                Spacer()
                Button("Close") { workflow.showingManageMedia = false }
                    .accessibilityIdentifier("btnCloseManageMediaDialog")
            }
        }
        .padding(20)
        .frame(width: 640)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manageMediaDialog")
        .onAppear {
            media.reload()
            media.refreshStaleness()
        }
        .alert(
            "Delete media recipe?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { recipe in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                media.delete(recipe)
                pendingDelete = nil
            }
        } message: { recipe in
            Text("Delete \"\(recipe.name)\"? This does not delete the .cal or the preset.")
        }
    }
}
