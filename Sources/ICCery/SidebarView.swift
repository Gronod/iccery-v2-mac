import SwiftUI
import ICCeryCore

/// 270 pt sidebar (docs/21 §Shell): logo, settings/about buttons, preset
/// select, Calibrate Printer + status chip, and the 1–5 stepper.
struct SidebarView: View {
    @ObservedObject var workflow: TargetWorkflowViewModel
    /// Observed directly: nested ObservableObjects are not tracked
    /// through the parent's `objectWillChange`.
    @ObservedObject private var model: WizardViewModel
    @ObservedObject private var profile: ProfileWorkflowViewModel
    @ObservedObject private var media: MediaLibraryViewModel
    @ObservedObject private var printSession: PrintSessionViewModel
    @ObservedObject private var measurement: MeasurementWorkflowViewModel
    @ObservedObject private var project: ProjectSession
    var onOpenSettings: () -> Void
    var onOpenAbout: () -> Void
    @Binding var showingAllHelp: Bool

    init(
        workflow: TargetWorkflowViewModel,
        onOpenSettings: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void,
        showingAllHelp: Binding<Bool>
    ) {
        self.workflow = workflow
        self._model = ObservedObject(wrappedValue: workflow.wizard)
        self._profile = ObservedObject(wrappedValue: workflow.profile)
        self._media = ObservedObject(wrappedValue: workflow.media)
        self._printSession = ObservedObject(wrappedValue: workflow.print)
        self._measurement = ObservedObject(wrappedValue: workflow.measurement)
        self._project = ObservedObject(wrappedValue: workflow.project)
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self._showingAllHelp = showingAllHelp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            presetBlock
            mediaBlock
            studioButtons
            stepperAndProject
        }
        .frame(width: Theme.Metrics.sidebarWidth)
        .background(Theme.panel)
    }

    // Swift 5.7 (Xcode 14.2 CI runner) caps a ViewBuilder body at 10
    // children (#146); these Group blocks are layout-transparent, so
    // visual order, ids and the 270 pt column are unchanged.
    private var header: some View {
        Group {
            HStack {
                Image("ICCery-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .helpOverlay("Open the Settings dialog.", showing: $showingAllHelp)
                .accessibilityIdentifier("openSettingsBtn")
                Button(action: onOpenAbout) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .helpOverlay("Open the About dialog.", showing: $showingAllHelp)
                .accessibilityIdentifier("openAboutBtn")
                Button(action: { showingAllHelp.toggle() }) {
                    Image(systemName: showingAllHelp ? "questionmark.circle.fill" : "questionmark.circle")
                }
                .buttonStyle(.plain)
                .help("Toggle help overlays")
                .accessibilityIdentifier("btnToggleAllHelp")
            }
            .padding(12)

            Divider().overlay(Theme.border)
        }
    }

    private var presetBlock: some View {
        Group {
            // Preset select (`#presetSelect`) — issue #11. Selection
            // applies the preset immediately; names render via Text only.
            Picker("Preset", selection: Binding(
                get: { workflow.selectedPresetID },
                set: { id in
                    if id == "none" {
                        workflow.selectedPresetID = "none"
                    } else if let preset = workflow.presets.first(where: { $0.id == id }) {
                        workflow.applyPreset(preset)
                    }
                }
            )) {
                Text("No preset").tag("none")
                ForEach(workflow.presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("presetSelect")
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                Button("Save") { workflow.showingSavePreset = true }
                    .accessibilityIdentifier("btnSavePresetModal")
                Button("Manage") { workflow.showingManagePresets = true }
                    .accessibilityIdentifier("btnOpenPresetsDialog")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var mediaBlock: some View {
        Group {
            // Media library (`#mediaSelect`) — issue #146. Selection
            // applies the recipe immediately, like presets; names render
            // via Text only (#114). Never reuses `presetSelect` (#137).
            Picker("Media", selection: Binding(
                get: { media.selectedRecipeID },
                set: { media.selectRecipe($0) }
            )) {
                Text("No media recipe").tag("none")
                ForEach(media.recipes) { recipe in
                    Text(recipe.name).tag(recipe.id)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("mediaSelect")
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .helpOverlay(
                "Saved printer + paper + ink + .cal bound to a preset.",
                showing: $showingAllHelp)

            if let reasons = media.staleReasons[media.selectedRecipeID],
               !reasons.isEmpty {
                Text(reasons.contains(.printer)
                     ? "Printer not installed" : "Calibration stale")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("mediaRecipeStale")
                    .helpOverlay(
                        "Re-run Stage 0 or pick a different recipe.",
                        showing: $showingAllHelp)
            }

            HStack(spacing: 8) {
                Button("Capture") { media.beginCapture() }
                    .disabled(printSession.selectedPrinter.isEmpty)
                    .accessibilityIdentifier("btnMediaLibraryCapture")
                    .helpOverlay(
                        "Select a printer in Stage 2 first",
                        showing: $showingAllHelp)
                Button("Manage") { workflow.showingManageMedia = true }
                    .accessibilityIdentifier("btnMediaLibraryManage")
                    .helpOverlay(
                        "Apply or delete saved media recipes.",
                        showing: $showingAllHelp)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var studioButtons: some View {
        Group {
            // Calibrate Printer (`#btnCalibratePrinter`).
            Button(action: { model.enterCalibration() }) {
                Label("Calibrate Printer", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .accessibilityIdentifier("btnCalibratePrinter")
            .padding(.horizontal, 12)

            Button(action: { model.openGamut(profileGamURL: workflow.profile.createdGamutURL) }) {
                Label("View Gamut", systemImage: "view.3d")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .helpOverlay(
                "View the profile gamut in 3D against sRGB.",
                showing: $showingAllHelp)
            .accessibilityIdentifier("btnViewGamut")
            .padding(.horizontal, 12)

            // Spot Read sheet (`#btnSpotRead`) — issue #148. Enabled
            // only with a working folder (#59) and while no Stage 3
            // chartread child is live; opening never kills
            // `chartread_{basename}`.
            Button(action: { workflow.showingSpotRead = true }) {
                Label("Spot Read", systemImage: "eyedropper")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.workingDirectory == nil || measurement.isChartreadRunning)
            .helpOverlay(
                model.workingDirectory == nil
                    ? "Set a working folder in Stage 1 first."
                    : (measurement.isChartreadRunning
                        ? "Stop the Stage 3 chart read first."
                        : "Read a single patch as Lab/XYZ from the instrument."),
                showing: $showingAllHelp)
            .accessibilityIdentifier("btnSpotRead")
            .padding(.horizontal, 12)
        }
    }

    private var stepperAndProject: some View {
        Group {
            Divider().overlay(Theme.border)
                .padding(.vertical, 8)

            // Stepper 1–5.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(WizardStage.stepperStages, id: \.self) { stage in
                    StepperRow(
                        stage: stage,
                        isActive: model.stage == stage,
                        // Artefact gating (issue #4) — disk is truth.
                        isEnabled: model.isUnlocked(stage)
                    ) {
                        model.go(to: stage)
                    }
                }
            }
            .padding(.horizontal, 6)

            Spacer()

            // Project chip (issue #149) — a compact footer in the
            // spacer's bottom, under the stepper. The 270 pt column
            // cannot take four more large buttons (R10).
            ProjectChip(project: project, showingAllHelp: $showingAllHelp)
                .padding(8)
        }
    }
}

private struct StepperRow: View {
    let stage: WizardStage
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isActive ? Theme.accent : Theme.border)
                        .frame(width: 26, height: 26)
                    Text("\(stage.stepperIndex ?? 0)")
                        .font(.callout.bold())
                        .foregroundStyle(isActive ? .white : Theme.text)
                }
                Label(stage.title, systemImage: stage.symbolName)
                    .font(.callout)
                    .foregroundStyle(isActive ? Theme.text : .secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium)
                .fill(isActive ? Theme.accent.opacity(0.15) : .clear)
        )
    }
}
