import SwiftUI
import ICCeryCore

/// Stage 4 — build an ICC/ICM profile from the canonical `.ti3`.
struct Stage4View: View {
    @Bindable var model: ProfileWorkflowViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formSection
                    runSection
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear { model.restoreCreatedProfileURL() }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.wizard.basename)
                    .font(.title3)
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("stage4TargetBasename")
                Text("Build the ICC profile from the measured .ti3.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("stage4TargetMeta")
            }

            Spacer()

            if let progress = model.colprofProgress, model.isColprofRunning {
                Text(progress)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.border)
                    .cornerRadius(4)
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("colprofProgress")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    // MARK: - Form

    @ViewBuilder
    private var formSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile settings")
                .font(.headline)
                .foregroundStyle(Theme.text)

            HStack(spacing: 16) {
                Picker("Algorithm", selection: $model.algorithm) {
                    Text("Lab cLUT").tag("l")
                    Text("XYZ cLUT").tag("x")
                    Text("Display XYZ+matrix").tag("X")
                    Text("Matrix").tag("m")
                }
                .accessibilityIdentifier("colprofAlgorithm")

                Picker("Quality", selection: $model.quality) {
                    Text("Low").tag("l")
                    Text("Medium").tag("m")
                    Text("High").tag("h")
                    Text("Ultra").tag("u")
                }
                .accessibilityIdentifier("colprofQuality")
            }

            Picker("FWA / OBA compensation", selection: $model.fwaSelection) {
                ForEach(ColprofFwaSelection.allCases, id: \.self) { selection in
                    Text(selection.displayName).tag(selection)
                }
            }
            .accessibilityIdentifier("colprofFwa")

            if model.fwaSelection == .custom {
                HStack {
                    TextField("Custom .sp spectrum path", text: $model.fwaCustomPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("colprofFwaCustomPath")
                    Button("Browse…") { model.browseForSpectrumFile() }
                        .accessibilityIdentifier("btnBrowseFwaSp")
                }
            }

            HStack(spacing: 16) {
                TextField("Illuminant", text: $model.illuminant)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("colprofIlluminant")

                TextField("Observer", text: $model.observer)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("colprofObserver")
            }

            HStack(spacing: 16) {
                TextField("Input viewing condition", text: $model.inputViewingCond)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("colprofInputViewCond")

                TextField("Output viewing condition", text: $model.outputViewingCond)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("colprofOutputViewCond")
            }

            Text("Use 'none' to skip a viewing condition.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Description", text: $model.profileDescription)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("colprofDescription")

            TextField("Copyright", text: $model.copyright)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("colprofCopyright")

            Toggle("Apply calibration curve", isOn: $model.applyCalibration)
                .accessibilityIdentifier("colprofApplyCalibration")

            if model.applyCalibration {
                HStack {
                    TextField("Calibration .cal file", text: $model.calibrationFile)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("colprofCalibrationFile")
                    Button("Browse…") { model.browseForCalibrationFile() }
                        .accessibilityIdentifier("btnBrowseCalibrationFile")
                }
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    // MARK: - Run controls

    @ViewBuilder
    private var runSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Create Profile") {
                    model.createProfile()
                }
                .disabled(!model.canCreateProfile)
                .accessibilityIdentifier("btnCreateProfile")

                if model.isColprofRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                        .accessibilityIdentifier("colprofProgressIndicator")
                }

                Spacer()

                if let lastError = model.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("colprofLastError")
                }
            }

            if !model.colprofLog.isEmpty {
                DisclosureGroup("Log") {
                    VStack(alignment: .leading) {
                        ForEach(model.colprofLog, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("colprofLogContainer")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }
}
