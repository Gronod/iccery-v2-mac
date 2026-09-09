import SwiftUI
import ICCeryCore

/// Stage 1 — `#stage-1` Generate Target (`targen` → `.ti1`, issue #7,
/// docs/08). All documented element ids are wired as accessibility
/// identifiers so the UI-test contract stays stable.
struct Stage1View: View {
    @Bindable var workflow: TargetWorkflowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                colourSpaceSection
                patchSection
                targetSection
                advancedSection
                actionRow
                logSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .accessibilityIdentifier("stage-1")
    }

    // MARK: - Colour space (name="colourSpace")

    private var colourSpaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour space").font(.headline).foregroundStyle(Theme.text)
            Picker("Colour space", selection: $workflow.colourSpace) {
                Text("RGB (print drivers)").tag(ColourSpace.rgb)
                Text("CMYK (RIP output)").tag(ColourSpace.cmyk)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("colourSpace")
        }
    }

    // MARK: - Patch count + white/black

    private var patchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Patches").font(.headline).foregroundStyle(Theme.text)
            HStack(spacing: 16) {
                Picker("Patch count", selection: $workflow.patchPreset) {
                    ForEach(PatchCountPreset.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .accessibilityIdentifier("patchCountPreset")
                .frame(maxWidth: 220)

                if workflow.patchPreset == .custom {
                    TextField("Patches", value: $workflow.customPatchCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .accessibilityIdentifier("patchCountCustom")
                }
            }
            HStack(spacing: 16) {
                Stepper(value: $workflow.whitePatches, in: 0...50) {
                    Text("White patches: \(workflow.whitePatches)")
                }
                .accessibilityIdentifier("whitePatches")
                Stepper(value: $workflow.blackPatches, in: 0...50) {
                    Text("Black patches: \(workflow.blackPatches)")
                }
                .accessibilityIdentifier("blackPatches")
            }
            .foregroundStyle(Theme.text)
        }
    }

    // MARK: - Target file / working directory

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target file").font(.headline).foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                TextField("Basename (no extension)", text: $workflow.targetBasename)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("targetBasename")
                Button("Browse…") { workflow.browseForTargetFile() }
                    .accessibilityIdentifier("btnBrowse")
                Button("Working Dir…") { workflow.browseForWorkingDirectory() }
                    .accessibilityIdentifier("btnSelectWorkDir")
                Button("Open Existing…") { workflow.openExistingTarget() }
                    .accessibilityIdentifier("btnOpenExisting")
                Button("Import Dataset…") { workflow.importMeasurementDataset() }
                    .accessibilityIdentifier("btn-import-dataset")
            }
            Text(workflow.targetDirectory?.path ?? "No working directory selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityIdentifier("selectedPathDisplay")
        }
    }

    // MARK: - Advanced (#targenAdvancedDetails)

    /// UI tests pre-expand the group — XCUI cannot reliably toggle a
    /// macOS `DisclosureTriangle` (its click lands on the label).
    @State private var advancedExpanded = UITestHooks.isEnabled

    private var advancedSection: some View {
        DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        optionalInt("Grey steps (-g)",
                                    enabled: $workflow.greyStepsEnabled,
                                    value: $workflow.greySteps)
                        .accessibilityIdentifier("targenGreySteps")
                        optionalInt("Single-channel steps (-s)",
                                    enabled: $workflow.singleChannelEnabled,
                                    value: $workflow.singleChannelSteps)
                        .accessibilityIdentifier("targenSingleChannelSteps")
                        optionalInt("Neutral steps (-n)",
                                    enabled: $workflow.neutralStepsEnabled,
                                    value: $workflow.neutralSteps)
                        .accessibilityIdentifier("targenNeutralSteps")
                        optionalDouble("Neutral concentration (-N)",
                                       enabled: $workflow.neutralConcEnabled,
                                       value: $workflow.neutralConcentration,
                                       range: 0.0...1.0)
                        .accessibilityIdentifier("targenNeutralConcentration")
                        optionalDouble("OFPS adaptation (-A)",
                                       enabled: $workflow.adaptationEnabled,
                                       value: $workflow.adaptation,
                                       range: 0.0...1.0)
                        .accessibilityIdentifier("targenAdaptation")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Preconditioning profile",
                                      text: Binding(
                                        get: { workflow.preconditioningProfile ?? "" },
                                        set: {
                                            workflow.preconditioningProfile =
                                                $0.isEmpty ? nil : $0
                                        }))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("targenPrecondProfile")
                            Button("…") { workflow.browseForPreconditioningProfile() }
                                .accessibilityIdentifier("btnBrowsePrecondProfile")
                        }
                        Toggle("OFPS high quality (-G)", isOn: $workflow.highQuality)
                            .accessibilityIdentifier("targenHighQuality")
                        Picker("Full-spread algorithm", selection: $workflow.algorithm) {
                            ForEach(FullSpreadAlgorithm.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .accessibilityIdentifier("targenAlgorithm")
                        if workflow.colourSpace == .cmyk {
                            optionalInt("Total ink limit (-l)",
                                        enabled: $workflow.inkLimitEnabled,
                                        value: $workflow.totalInkLimit)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("targenInkLimitGroup")
                        }
                        optionalDouble("Dark emphasis (-V)",
                                       enabled: $workflow.darkEmphasisEnabled,
                                       value: $workflow.darkEmphasis,
                                       range: 0.0...3.0)
                        .accessibilityIdentifier("targenDarkEmphasis")
                        optionalDouble("Device power (-p)",
                                       enabled: $workflow.devicePowerEnabled,
                                       value: $workflow.devicePower,
                                       range: 0.0...3.0)
                        .accessibilityIdentifier("targenDevicePower")
                    }
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.top, 8)
        }
        .foregroundStyle(Theme.text)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("targenAdvancedDetails")
    }

    private func optionalInt(
        _ title: String,
        enabled: Binding<Bool>,
        value: Binding<Int>
    ) -> some View {
        HStack {
            Toggle(title, isOn: enabled)
                .toggleStyle(.checkbox)
            if enabled.wrappedValue {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
        }
    }

    private func optionalDouble(
        _ title: String,
        enabled: Binding<Bool>,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: enabled)
                .toggleStyle(.checkbox)
            if enabled.wrappedValue {
                HStack {
                    Slider(value: value, in: range)
                    Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                        .frame(width: 44)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Actions + log

    private var actionRow: some View {
        HStack {
            Button(action: workflow.generateTarget) {
                Label(workflow.targenRunning ? "Generating…" : "Generate Target",
                      systemImage: "square.grid.3x3")
            }
            .controlSize(.large)
            .disabled(!workflow.canGenerate || workflow.targenRunning)
            .accessibilityIdentifier("btnGenerate")
            if workflow.targenRunning {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
    }

    private var logSection: some View {
        DisclosureGroup("Process log") {
            ScrollView {
                Text(workflow.targenLog.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 200)
            .accessibilityIdentifier("targenLog")
        }
        .foregroundStyle(Theme.text)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("targenLogContainer")
    }
}
