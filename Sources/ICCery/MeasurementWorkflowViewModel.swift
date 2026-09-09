import Foundation
import Observation
import SwiftUI
import ICCeryCore

/// A single evaluated swatch for the live grid.
struct Swatch: Sendable, Equatable, Identifiable {
    let rowId: String
    let loc: String
    let isPad: Bool
    let intended: DisplayRGB
    let measured: DisplayRGB
    let deltaE: Double?
    let classification: SwatchClassification

    var id: String { "\(rowId)\(loc)" }
}

/// A row of swatches in display order.
struct SwatchRow: Sendable, Equatable, Identifiable {
    let index: Int
    let rowId: String
    let patches: [Swatch]

    var id: String { rowId }
}

/// Stage of the XY-table badge bar.
enum XYStep: Equatable, Sendable {
    case place, align, scan, remove
}

/// Stage 3 workflow state and interaction (issues #18–#22).
@MainActor
@Observable
final class MeasurementWorkflowViewModel {

    // MARK: - Authorities

    let wizard: WizardViewModel
    let environment: AppEnvironment

    // MARK: - Settings-driven thresholds

    private(set) var goodMax: Double = 2.0
    private(set) var warningMax: Double = 5.0
    private(set) var enableLEDs: Bool = false

    // MARK: - Instrument detection

    var instruments: [InstrumentDevice] = []
    var selectedInstrument: InstrumentSelection = .auto
    var isDetecting = false
    var detectionError: String?

    // MARK: - Chartread session

    var isChartreadRunning = false
    var chartreadState: ChartreadState = .idle
    var currentPrompt: String?
    var requestedWarningKey: String?
    var chartreadLog: [String] = []
    var rows: [ChartreadRow] = []
    var swatchRows: [SwatchRow] = []
    var showRemoveSheetNotice = false
    var lastError: String?
    private var chartreadTask: Task<Void, Never>?

    // MARK: - Averaging

    var passSnapshots: [URL] = []
    var isFinishing = false
    var finishNotice: String?
    var finishNoticeIsError = false
    var resumedFromTi2 = false

    init(wizard: WizardViewModel, environment: AppEnvironment) {
        self.wizard = wizard
        self.environment = environment
        loadSettings()
        discoverPassSnapshots()
    }

    // MARK: - Derived state

    var basename: String { wizard.basename }
    var workingDirectory: URL? { wizard.effectiveWorkingDirectory }

    var canDetect: Bool { !isDetecting }

    var canStartRead: Bool {
        !basename.isEmpty && workingDirectory != nil && !isChartreadRunning
    }

    var canMeasureAnotherSheet: Bool {
        isFinished && !passSnapshots.isEmpty
    }

    var canFinish: Bool {
        isFinished && !passSnapshots.isEmpty
    }

    var isFinished: Bool {
        chartreadState == .allStripsRead || chartreadState == .finished
    }

    var xyStep: XYStep {
        if showRemoveSheetNotice { return .remove }
        switch chartreadState {
        case .tablePlaceSheet:
            return .place
        case .tableAlign:
            return .align
        case .reading, .awaitingStrip:
            return .scan
        default:
            return .place
        }
    }

    var hasCanonicalTi3: Bool {
        guard let cwd = workingDirectory else { return false }
        let url = cwd.appendingPathComponent("\(basename).ti3")
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Settings

    func loadSettings() {
        let settings = environment.settingsStore.load()
        goodMax = settings.deltaEGoodMax
        warningMax = settings.deltaEWarningMax
        enableLEDs = settings.enableI1Pro2Leds
    }

    // MARK: - Instrument detection

    func detectInstruments() {
        guard !isDetecting else { return }
        isDetecting = true
        detectionError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let devices = try await self.environment.runner.detectInstruments()
                self.instruments = devices
                if case .device(let selected) = self.selectedInstrument,
                   !devices.contains(where: { $0.port == selected.port }) {
                    self.selectedInstrument = .auto
                }
            } catch {
                self.detectionError = error.localizedDescription
            }
            self.isDetecting = false
        }
    }

    // MARK: - Chartread lifecycle

    func startRead() {
        guard canStartRead, let cwd = workingDirectory else { return }
        let config = buildChartreadConfig(cwd: cwd)
        startChartread(config: config)
    }

    func measureAnotherSheet() {
        guard let cwd = workingDirectory, isFinished else { return }
        let config = buildChartreadConfig(cwd: cwd)
        startChartread(config: config)
    }

    private func buildChartreadConfig(cwd: URL) -> ChartreadConfig {
        ChartreadConfig(
            basename: basename,
            workingDirectory: cwd,
            selectedPort: selectedInstrument.chartreadPort,
            enableLEDs: enableLEDs,
            isXY: selectedInstrument.isXY
        )
    }

    private func startChartread(config: ChartreadConfig) {
        guard !isChartreadRunning else { return }

        isChartreadRunning = true
        chartreadState = .idle
        currentPrompt = nil
        lastError = nil
        chartreadLog.removeAll()

        // Optional: reset rows when starting a fresh first pass.
        if passSnapshots.isEmpty {
            rows.removeAll()
            swatchRows.removeAll()
        }

        let stream = environment.runner.runChartread(config: config)

        chartreadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in stream {
                self.handle(event: event)
            }
            self.isChartreadRunning = false
        }
    }

    private func handle(event: ChartreadEvent) {
        switch event {
        case .prompt(let result):
            chartreadState = result.state
            currentPrompt = promptText(for: result)
            requestedWarningKey = result.requestedWarningKey
            showRemoveSheetNotice = result.isRemoveSheetNotice

        case .row(let row):
            upsert(row: row)
            if row.isFinalRow {
                chartreadState = .allStripsRead
            }

        case .log(let batch):
            chartreadLog.append(contentsOf: batch)

        case .removeSheetNotice:
            showRemoveSheetNotice = true

        case .exit(let code):
            if code != 0 {
                lastError = "chartread exited with code \(code)"
            }

        case .completed(let canonicalURL):
            chartreadState = .finished
            completePass(canonicalURL: canonicalURL)

        case .failed(let error):
            lastError = error.localizedDescription
            chartreadState = .error
            isChartreadRunning = false
        }
    }

    private func promptText(for result: ChartreadClassifyResult) -> String {
        switch result.state {
        case .calibrating:
            return "Place instrument on calibration tile and press Calibrate."
        case .awaitingStrip:
            return "Press a key to read the next strip."
        case .allStripsRead:
            return "All strips read. Press Done & Save when ready."
        case .warning:
            if let key = result.requestedWarningKey {
                return "Warning — press '\(key.uppercased())' to continue."
            }
            return "Warning — press Continue."
        case .promptContinue:
            return "Press Continue."
        case .tablePlaceSheet:
            if let n = result.sheetNumber, let t = result.sheetTotal {
                return "Place sheet \(n) of \(t) on the table."
            }
            return "Place the sheet on the table."
        case .tableAlign:
            if let patch = result.alignmentPatch {
                return "Locate patch \(patch) with the sight, then continue."
            }
            return "Align the fiducial, then continue."
        case .reading:
            return "Reading..."
        case .error:
            return "Read error — you can Retry or Cancel."
        case .finished:
            return "Measurement saved."
        case .idle:
            return "Press Start to begin reading."
        }
    }

    // MARK: - User actions

    func calibrate() {
        send(.trigger)
    }

    func accept() {
        if let key = requestedWarningKey {
            send(.customKey(key))
            requestedWarningKey = nil
        } else {
            send(.accept)
        }
    }

    func retry() {
        send(.trigger)
    }

    func doneAndSave() {
        send(.done)
    }

    func cancelRead() {
        environment.runner.cancelChartread(basename: basename, isXY: selectedInstrument.isXY)
        chartreadTask?.cancel()
        isChartreadRunning = false
    }

    func sendWarningKey(_ key: String) {
        send(.customKey(key))
    }

    private func send(_ input: ChartreadInput) {
        Task { @MainActor [weak self] in
            guard let self, self.isChartreadRunning else { return }
            try? await self.environment.runner.sendChartreadInput(basename: self.basename, input: input)
        }
    }

    // MARK: - Rows and swatches

    private func upsert(row: ChartreadRow) {
        if let index = rows.firstIndex(where: { $0.rowIndex == row.rowIndex }) {
            rows[index] = row
        } else {
            rows.append(row)
        }
        rows.sort { $0.rowIndex < $1.rowIndex }
        recomputeSwatches()
    }

    func recomputeSwatches() {
        var displayRows: [SwatchRow] = []
        for (rowIndex, row) in rows.enumerated() {
            var swatches: [Swatch] = []
            for patch in row.patches {
                let skip = shouldSkipPad(patch)
                if skip { continue }

                let eval = ColorDifference.evaluate(
                    patch: patch,
                    goodMax: goodMax,
                    warningMax: warningMax
                )
                if let eval {
                    swatches.append(Swatch(
                        rowId: row.rowId,
                        loc: patch.loc,
                        isPad: patch.isPad,
                        intended: eval.intended,
                        measured: eval.measured,
                        deltaE: eval.deltaE,
                        classification: eval.classification
                    ))
                }
            }
            if !swatches.isEmpty {
                displayRows.append(SwatchRow(index: rowIndex, rowId: row.rowId, patches: swatches))
            }
        }
        swatchRows = displayRows
    }

    private func shouldSkipPad(_ patch: ChartreadPatch) -> Bool {
        guard patch.isPad else { return false }
        let measuredEmpty = patch.measured.xyz == nil && patch.measured.lab == nil
        let deviceAllZero = patch.device.allSatisfy { $0 == 0 }
        return measuredEmpty && deviceAllZero
    }

    // MARK: - Pass management

    private func completePass(canonicalURL: URL) {
        guard let cwd = workingDirectory else { return }
        do {
            _ = try MeasurementArtefacts.snapshotPass(basename: basename, cwd: cwd)
            discoverPassSnapshots()
            wizard.refreshGating()
        } catch {
            lastError = "Could not snapshot pass: \(error.localizedDescription)"
        }
    }

    func discoverPassSnapshots() {
        guard let cwd = workingDirectory else {
            passSnapshots = []
            return
        }
        passSnapshots = MeasurementArtefacts.passSnapshots(basename: basename, cwd: cwd)
    }

    // MARK: - Finish / Average

    func finishAndAverage() {
        guard !isFinishing, let cwd = workingDirectory, !passSnapshots.isEmpty else { return }
        isFinishing = true
        finishNotice = nil
        finishNoticeIsError = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let canonical: URL
                if self.passSnapshots.count == 1, let pass = self.passSnapshots.first {
                    canonical = try MeasurementArtefacts.promotePass(
                        pass: pass,
                        basename: self.basename,
                        cwd: cwd
                    )
                } else {
                    let config = AverageConfig(
                        workingDirectory: cwd,
                        basename: self.basename,
                        passFiles: self.passSnapshots
                    )
                    canonical = try await self.environment.runner.runAverage(
                        config: config,
                        onLogBatch: { [weak self] batch in
                            Task { @MainActor [weak self] in
                                self?.chartreadLog.append(contentsOf: batch)
                            }
                        }
                    )
                }
                self.discoverPassSnapshots()
                self.wizard.refreshGating()
                if self.wizard.isUnlocked(.buildProfile) {
                    self.wizard.go(to: .buildProfile)
                } else {
                    self.finishNotice = "Finished: \(canonical.lastPathComponent) ready."
                }
            } catch {
                // Fallback to pass 1 promotion if averaging failed.
                if let pass = self.passSnapshots.first {
                    do {
                        _ = try MeasurementArtefacts.promotePass(
                            pass: pass,
                            basename: self.basename,
                            cwd: cwd
                        )
                        self.discoverPassSnapshots()
                        self.wizard.refreshGating()
                        self.finishNotice = "Averaging failed — promoted first pass."
                        self.finishNoticeIsError = true
                    } catch {
                        self.finishNotice = "Finish failed: \(error.localizedDescription)"
                        self.finishNoticeIsError = true
                    }
                } else {
                    self.finishNotice = "Finish failed: \(error.localizedDescription)"
                    self.finishNoticeIsError = true
                }
            }
            self.isFinishing = false
        }
    }
}
