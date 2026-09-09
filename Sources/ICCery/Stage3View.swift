import Combine
import SwiftUI
import ICCeryCore

/// Stage 3 — measurement, live swatches, and multi-pass averaging.
struct Stage3View: View {
    @Bindable var model: MeasurementWorkflowViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    instrumentSection
                    chartreadControlsSection
                    xyTableSection
                    swatchGridSection
                    averagingSection
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear { model.discoverPassSnapshots() }
        .onReceive(NotificationCenter.default.publisher(for: SettingsStore.settingsDidChange)) { _ in
            model.loadSettings()
            model.recomputeSwatches()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if model.resumedFromTi2 {
                    Label("Resumed from .ti2", systemImage: "arrow.uturn.right")
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("stage3LoadedTargetBanner")
                }
                Text(model.basename)
                    .font(.title3)
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("stage3TargetBasename")
                Text("Measure the printed chart with a spectrophotometer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("stage3TargetMeta")
            }

            Spacer()

            if model.isChartreadRunning {
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityIdentifier("readProgress")
            }

            if let badge = targetBadge {
                Text(badge)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.border)
                    .cornerRadius(4)
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("stage3TargetBadge")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    private var targetBadge: String? {
        if model.isFinished { return "All strips read" }
        if model.isChartreadRunning { return "Reading" }
        if !model.passSnapshots.isEmpty { return "\(model.passSnapshots.count) pass(es)" }
        return nil
    }

    // MARK: - Instrument detection

    @ViewBuilder
    private var instrumentSection: some View {
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
                .accessibilityIdentifier("btnDetectInstruments")
            }

            if model.detectionError != nil {
                Text(model.detectionError ?? "")
                    .font(.caption)
                    .foregroundStyle(.red)
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
            .accessibilityIdentifier("chartreadInstrumentSelect")

            if model.selectedInstrument.isXY {
                Text("XY table workflow selected.")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("xyTableHint")
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

    // MARK: - Chartread controls

    @ViewBuilder
    private var chartreadControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Status")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(model.currentPrompt ?? "Press Start to begin reading.")
                    .font(.callout)
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("chartreadPrompt")
            }

            if model.showRemoveSheetNotice {
                Text("Please remove last sheet from table.")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("chartreadLastError")
                    .accessibilityValue(lastError)
            }

            controlButtons

            if !model.chartreadLog.isEmpty {
                DisclosureGroup("Log") {
                    VStack(alignment: .leading) {
                        ForEach(model.chartreadLog, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("chartreadLogContainer")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 12) {
            if !model.isChartreadRunning {
                Button("Start Read") {
                    model.startRead()
                }
                .disabled(!model.canStartRead)
                .accessibilityIdentifier("btnStartRead")
            }

            if model.isChartreadRunning {
                switch model.chartreadState {
                case .calibrating:
                    Button("Calibrate") { model.calibrate() }
                        .accessibilityIdentifier("btnCalibrate")
                case .awaitingStrip:
                    Button("Trigger") { model.calibrate() }
                        .accessibilityIdentifier("btnCalibrate")
                case .tablePlaceSheet, .tableAlign, .promptContinue, .warning:
                    Button(continueTitle) { model.accept() }
                        .accessibilityIdentifier("btnAccept")
                case .error:
                    Button("Retry") { model.retry() }
                        .accessibilityIdentifier("btnRetry")
                case .allStripsRead:
                    Button("Done & Save") { model.doneAndSave() }
                        .accessibilityIdentifier("btnDoneRead")
                default:
                    EmptyView()
                }

                if model.chartreadState == .awaitingStrip || model.chartreadState == .allStripsRead {
                    Button("Done & Save") { model.doneAndSave() }
                        .accessibilityIdentifier("btnDoneRead")
                }

                if model.chartreadState == .error {
                    Button("Retry") { model.retry() }
                        .accessibilityIdentifier("btnRetry")
                }

                Button("Cancel") { model.cancelRead() }
                    .accessibilityIdentifier("btnCancel")
            }
        }
    }

    private var continueTitle: String {
        if let key = model.requestedWarningKey {
            return "Continue (send '\(key.uppercased())')"
        }
        return "Continue"
    }

    // MARK: - XY table badges

    @ViewBuilder
    private var xyTableSection: some View {
        if model.selectedInstrument.isXY {
            HStack(spacing: 8) {
                xyStep("Place", active: model.xyStep == .place, id: "xyStepPlace")
                xyStep("Align", active: model.xyStep == .align, id: "xyStepAlign")
                xyStep("Scan", active: model.xyStep == .scan, id: "xyStepScan")
                xyStep("Remove", active: model.xyStep == .remove, id: "xyStepRemove")
            }
            .padding(12)
            .background(Theme.panel)
            .accessibilityIdentifier("xyTablePanel")
        }
    }

    private func xyStep(_ label: String, active: Bool, id: String) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(active ? .bold : .regular)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(active ? Theme.accent : Theme.border)
            .foregroundStyle(active ? Color.white : Theme.text)
            .cornerRadius(4)
            .accessibilityIdentifier(id)
    }

    // MARK: - Swatch grid

    @ViewBuilder
    private var swatchGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Swatches")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                statsView
            }

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.swatchRows) { row in
                        HStack(spacing: 2) {
                            Text(row.rowId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            ForEach(row.patches) { swatch in
                                SwatchPatchView(swatch: swatch)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 120, maxHeight: 360)
            .background(Theme.panel)
            .accessibilityIdentifier("swatchGrid")
        }
        .padding(16)
        .background(Theme.background)
    }

    @ViewBuilder
    private var statsView: some View {
        let patches = model.swatchRows.flatMap(\.patches)
        let valid = patches.compactMap(\.deltaE)
        let avg = valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
        let max = valid.max() ?? 0

        HStack(spacing: 12) {
            if let avg = avg {
                Text("avg ΔE \(String(format: "%.2f", avg))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("max ΔE \(String(format: "%.2f", max))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(patches.count) patches")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("readStats")
    }

    // MARK: - Averaging

    @ViewBuilder
    private var averagingSection: some View {
        if !model.passSnapshots.isEmpty || model.isFinished {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Averaging")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(model.passSnapshots.count) pass(es)")
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.border)
                        .cornerRadius(4)
                        .accessibilityIdentifier("passCounterBadge")
                }

                ForEach(model.passSnapshots, id: \.lastPathComponent) { url in
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("passesList")

                HStack(spacing: 12) {
                    Button("Measure Another Sheet") {
                        model.measureAnotherSheet()
                    }
                    .disabled(!model.isFinished || model.isChartreadRunning)
                    .accessibilityIdentifier("btnMeasureAnotherSheet")

                    Button("Finish & Average") {
                        model.finishAndAverage()
                    }
                    .disabled(!model.isFinished || model.isFinishing)
                    .accessibilityIdentifier("btnFinishAndAverage")
                }

                if let notice = model.finishNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(model.finishNoticeIsError ? .red : .green)
                }
            }
            .padding(16)
            .background(Theme.panel)
            .accessibilityIdentifier("chartreadAveragingPanel")
        }
    }
}
