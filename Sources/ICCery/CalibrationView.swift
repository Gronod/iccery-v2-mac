import SwiftUI
import ICCeryCore

/// Stage 0 calibration dashboard (issue #29, docs/07).
struct CalibrationView: View {
    @ObservedObject var model: CalibrationViewModel
    @ObservedObject var wizard: WizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Calibrate Printer")
                .font(.title2.bold())
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Form {
                Section("Wedge Settings") {
                    Picker("Colour Space", selection: $model.colourSpace) {
                        Text("RGB").tag(ColourSpace.rgb)
                        Text("CMYK").tag(ColourSpace.cmyk)
                    }

                    HStack {
                        Text("Steps per channel")
                        Spacer()
                        TextField("", value: $model.steps, format: .number)
                            .frame(width: 60)
                            .accessibilityIdentifier("calSteps")
                    }

                    HStack {
                        Text("White patches")
                        Spacer()
                        TextField("", value: $model.whitePatches, format: .number)
                            .frame(width: 60)
                    }

                    if model.colourSpace == .cmyk {
                        HStack {
                            Text("Ink-limit exploration")
                            Spacer()
                            TextField("", text: $model.inkLimit)
                                .frame(width: 60)
                                .accessibilityIdentifier("calInkExplore")
                        }
                    }

                    Toggle("Neutral emphasis", isOn: $model.includeNeutralEmphasis)
                }

                Section("Workflow") {
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
                            .onChange(of: model.applyToProfile) { _ in model.updateApplyToProfile() }
                            .accessibilityIdentifier("calApplyToggle")

                        Text("Loaded: \(url.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !model.calibrationLog.isEmpty {
                    Section("Log") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(model.calibrationLog, id: \.self) { line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                }
                            }
                        }
                        .frame(minHeight: 80, maxHeight: 120)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Return to Profiling") { model.returnToProfiling() }
                    .accessibilityIdentifier("btnCalReturn")
            }
            .padding(16)
        }
    }
}
