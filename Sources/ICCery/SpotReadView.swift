import SwiftUI
import ICCeryCore

/// Spot Read sheet (issue #148) — one patch Lab/XYZ from the live
/// instrument. A `RootView` sheet, not a wizard stage and not a Stage 3
/// tab; all identifiers are `spot*` — Stage 3 `chartread` ids are never
/// reused here.
struct SpotReadView: View {
    @ObservedObject var model: SpotReadViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !model.sidecarAvailable {
                missingSidecar
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        instrumentCard
                        promptLine
                        transport
                        lastSampleCard
                        historySection
                    }
                }
            }
            footer
        }
        .padding(16)
        .frame(width: 560, height: 640)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spotReadView")
        .onAppear { model.sheetOpened() }
        .onDisappear { model.sheetClosed() }
    }

    // MARK: - Header / missing sidecar

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Spot Read")
                .font(.title3)
                .foregroundStyle(Theme.text)
            Spacer()
            if model.isRunning {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }

    private var missingSidecar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("spotread sidecar missing — run fetch-argyll")
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("spotSidecarMissing")
            Spacer()
        }
    }

    // MARK: - Instrument card (clones Stage 3 look, own ids)

    private var instrumentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Instrument")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(action: { model.detectInstruments() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!model.canDetect)
                .accessibilityIdentifier("btnSpotDetectInstruments")
            }

            if let error = model.detectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("spotDetectError")
            }

            Picker("Instrument", selection: Binding(
                get: { instrumentTag },
                set: { newTag in
                    if newTag.isEmpty {
                        model.selectedInstrument = .auto
                    } else if let device = model.instruments.first(where: { "\($0.port)" == newTag }) {
                        model.selectedInstrument = .device(device)
                    }
                }
            )) {
                Text("Auto (first available port)").tag("")
                ForEach(model.instruments) { device in
                    Text(device.displayName).tag("\(device.port)")
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isRunning)
            .accessibilityIdentifier("spotInstrumentSelect")

            if model.defaultMissing {
                Text("Saved default instrument not present")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("spotDefaultMissing")
            }

            Toggle("Also set as default instrument", isOn: Binding(
                get: { model.setAsDefault },
                set: { model.applyDefaultToggle($0) }
            ))
            .accessibilityIdentifier("spotSetDefault")

            if model.selectedInstrument.isXY {
                Text("XY tables use Stage 3. Spot Read is a handheld / reflective probe.")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("spotXYHint")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    private var instrumentTag: String {
        switch model.selectedInstrument {
        case .auto:
            return ""
        case .device(let device):
            return "\(device.port)"
        }
    }

    // MARK: - Prompt line

    private var promptLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Status")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(model.prompt)
                    .font(.callout)
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("spotPrompt")
            }
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("spotLastError")
                    .accessibilityValue(error)
            }
            if !model.log.isEmpty {
                ProcessLogView(
                    lines: model.log,
                    minHeight: 60,
                    maxHeight: 100,
                    containerId: "spotLogContainer",
                    logId: "spotLog"
                )
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 12) {
            if !model.isRunning {
                Button("Start") { model.start() }
                    .disabled(!model.canStart)
                    .accessibilityIdentifier("btnSpotStart")
            } else {
                switch model.state {
                case .calibrating:
                    Button("Calibrate") { model.calibrate() }
                        .accessibilityIdentifier("btnSpotCalibrate")
                case .awaitingStrip:
                    Button("Read") { model.trigger() }
                        .accessibilityIdentifier("btnSpotTrigger")
                default:
                    EmptyView()
                }
                Button("Stop") { model.stopIfNeeded() }
                    .accessibilityIdentifier("btnSpotStop")
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Last sample

    @ViewBuilder
    private var lastSampleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last sample")
                .font(.headline)
                .foregroundStyle(Theme.text)

            if let sample = model.displayedSample {
                HStack(spacing: 16) {
                    let rgb = LabColorMath.labToSRGB(sample.lab)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                        .frame(width: 32, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border))
                        .accessibilityIdentifier("spotSwatch")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 12) {
                            Text(String(format: "L* %.1f", sample.lab.l))
                                .accessibilityIdentifier("spotLabL")
                            Text(String(format: "a* %.1f", sample.lab.a))
                                .accessibilityIdentifier("spotLabA")
                            Text(String(format: "b* %.1f", sample.lab.b))
                                .accessibilityIdentifier("spotLabB")
                        }
                        .font(.callout)
                        .foregroundStyle(Theme.text)

                        if let xyz = sample.xyz {
                            Text(String(format: "XYZ %.2f %.2f %.2f", xyz.x, xyz.y, xyz.z))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("spotXYZ")
                        }

                        HStack(spacing: 8) {
                            Text(sample.port.map { "\(sample.instrumentName) · port \($0)" }
                                 ?? sample.instrumentName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("spotLastInstrument")

                            if let de = model.displayedDeltaE {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(deltaEColor)
                                        .frame(width: 8, height: 8)
                                    Text(String(format: "ΔE %.2f", de))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("spotDeltaE")
                            }
                        }

                        if model.isDisplayedLabImplausible {
                            Text("Implausible L*")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityIdentifier("spotLabImplausible")
                        }
                    }
                    Spacer()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("spotLastSample")
            } else {
                Text("No readings yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("spotLastEmpty")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    private var deltaEColor: Color {
        switch model.deltaEClassification {
        case .good, nil: return .green
        case .warning: return .orange
        case .bad: return .red
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)
                .foregroundStyle(Theme.text)

            if model.samples.isEmpty {
                Text("No history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("spotHistoryEmpty")
            } else {
                List {
                    ForEach(Array(model.samples.enumerated()), id: \.element.id) { index, sample in
                        historyRow(index: index, sample: sample)
                    }
                }
                .frame(minHeight: 120)
                .accessibilityIdentifier("spotHistoryTable")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    private func historyRow(index: Int, sample: SpotReadSample) -> some View {
        let previous = index + 1 < model.samples.count ? model.samples[index + 1] : nil
        let deltaE = previous.map { ColorDifference.deltaE00($0.lab, sample.lab) }
        return Button(action: { model.selectFromHistory(sample) }) {
            HStack(spacing: 10) {
                Text(sample.timestamp, style: .time)
                    .frame(width: 70, alignment: .leading)
                Text(String(format: "%.1f", sample.lab.l))
                    .frame(width: 44, alignment: .trailing)
                Text(String(format: "%.1f", sample.lab.a))
                    .frame(width: 44, alignment: .trailing)
                Text(String(format: "%.1f", sample.lab.b))
                    .frame(width: 44, alignment: .trailing)
                Text(deltaE.map { String(format: "%.2f", $0) } ?? "")
                    .frame(width: 44, alignment: .trailing)
                Text(sample.instrumentName)
                    .lineLimit(1)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(Theme.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("spotHistoryRow-\(sample.id.uuidString)")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Copy Lab") { model.copyLab() }
                .disabled(model.displayedSample == nil)
                .accessibilityIdentifier("btnSpotCopyLab")
            Button("Export CSV…") { model.exportCsv() }
                .disabled(model.samples.isEmpty)
                .accessibilityIdentifier("btnSpotExportCsv")
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("btnCloseSpotRead")
        }
        .padding(.top, 4)
    }
}
