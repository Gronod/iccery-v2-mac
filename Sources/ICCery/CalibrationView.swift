import SwiftUI
import ICCeryCore

/// Stage 0 calibration dashboard (issue #29, docs/07).
struct CalibrationView: View {
    @ObservedObject var model: CalibrationViewModel
    @ObservedObject var wizard: WizardViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Calibrate Printer")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.text)
                    wedgeSection
                    workflowSection
                    if !model.calibrationLog.isEmpty { logSection }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)

            Divider().overlay(Theme.border)

            HStack {
                Spacer()
                Button("Return to Profiling", role: .cancel) { model.returnToProfiling() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("btnCalReturn")
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stage-cal")
    }

    // MARK: - Wedge settings

    private var wedgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wedge Settings").font(.headline).foregroundStyle(Theme.text)
            Picker("Colour Space", selection: $model.colourSpace) {
                Text("RGB").tag(ColourSpace.rgb)
                Text("CMYK").tag(ColourSpace.cmyk)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            HStack(spacing: 12) {
                Text("Steps per channel")
                    .foregroundStyle(Theme.text)
                    .frame(width: 140, alignment: .leading)
                TextField("", value: $model.steps, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .accessibilityIdentifier("calSteps")
            }

            HStack(spacing: 12) {
                Text("White patches")
                    .foregroundStyle(Theme.text)
                    .frame(width: 140, alignment: .leading)
                TextField("", value: $model.whitePatches, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }

            if model.colourSpace == .cmyk {
                HStack(spacing: 12) {
                    Text("Ink-limit exploration")
                        .foregroundStyle(Theme.text)
                        .frame(width: 140, alignment: .leading)
                    TextField("", text: $model.inkLimit)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .accessibilityIdentifier("calInkExplore")
                }
            }

            Toggle("Neutral emphasis", isOn: $model.includeNeutralEmphasis)
                .toggleStyle(.checkbox)
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("calNeutralEmphasis")
        }
    }

    // MARK: - Workflow

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workflow").font(.headline).foregroundStyle(Theme.text)
            HStack(spacing: 12) {
                Button("Generate Target") { model.generateTarget() }
                    .accessibilityIdentifier("btnCalGenerate")
                    .disabled(wizard.basename.isEmpty
                              || wizard.effectiveWorkingDirectory == nil
                              || model.isGenerating)

                Button("Create Layout & Print") { model.createLayout() }
                    .accessibilityIdentifier("btnCalLayout")
                    .disabled(wizard.basename.isEmpty
                              || wizard.effectiveWorkingDirectory == nil
                              || model.isGenerating)

                Button("Measure") { model.measureChart() }
                    .accessibilityIdentifier("btnCalMeasure")
                    .disabled(model.calibrationTi3URL == nil)

                Button("Compute Curves") { model.computeCurves() }
                    .accessibilityIdentifier("btnCalCompute")
                    .disabled(!model.canCompute)
            }

            if let url = model.computedCalURL {
                Toggle("Apply calibration to next profile", isOn: $model.applyToProfile)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(Theme.text)
                    .onChange(of: model.applyToProfile) { _ in model.updateApplyToProfile() }
                    .accessibilityIdentifier("calApplyToggle")

                Text("Loaded: \(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Log

    private var logSection: some View {
        ProcessLogView(
            lines: model.calibrationLog,
            minHeight: 80,
            maxHeight: 120,
            containerId: "calLogContainer",
            logId: "calLog"
        )
    }
}
