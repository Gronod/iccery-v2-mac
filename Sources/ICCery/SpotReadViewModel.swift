import AppKit
import Combine
import Foundation
import ICCeryCore

/// Spot-read console state and interaction (issue #148).
///
/// Runs the bundled `spotread` sidecar under the single-lease process id
/// `spotread`; Stage 3 `chartread` is untouched. `defaultInstrument`
/// seeds the instrument picker on sheet open — it is never written into
/// `printtarg -i` or `targen` argv (R15).
@MainActor
final class SpotReadViewModel: ObservableObject {

    let workflow: TargetWorkflowViewModel
    let environment: AppEnvironment
    private let fileDialogs = FileDialogService.shared

    // MARK: - Instrument card

    @Published var instruments: [InstrumentDevice] = []
    @Published var selectedInstrument: InstrumentSelection = .auto
    @Published var isDetecting = false
    @Published var detectionError: String?
    /// `spotDefaultMissing` — set when `defaultInstrument` is saved but
    /// no detected device matches it.
    @Published var defaultMissing = false
    /// `spotSetDefault` toggle state.
    @Published var setAsDefault = false

    // MARK: - Session

    @Published var isRunning = false
    @Published var state: ChartreadState = .idle
    @Published var prompt = "Press Start to open the instrument."
    @Published var lastError: String?
    @Published var log: [String] = []

    // MARK: - Samples / history (in-memory, cap 50, newest first)

    @Published private(set) var samples: [SpotReadSample] = []
    @Published private(set) var displayedSample: SpotReadSample?
    @Published private(set) var displayedDeltaE: Double?

    private let historyLimit = 50
    private var streamTask: Task<Void, Never>?

    init(workflow: TargetWorkflowViewModel, environment: AppEnvironment) {
        self.workflow = workflow
        self.environment = environment
    }

    // MARK: - Derived state

    /// Whether the bundled `spotread` sidecar resolves to an executable.
    /// `BinaryResolver` only — never `$PATH`, never `chartread`.
    var sidecarAvailable: Bool {
        let url = environment.runner.binaryResolver.resolve("spotread")
        return environment.runner.binaryResolver.exists(url)
    }

    var isChartreadRunning: Bool { workflow.measurement.isChartreadRunning }

    var canStart: Bool {
        sidecarAvailable && !isDetecting && !isRunning && !isChartreadRunning
            && workflow.wizard.effectiveWorkingDirectory != nil
    }

    var canDetect: Bool { !isDetecting && !isRunning }

    var deltaEClassification: SwatchClassification? {
        guard let de = displayedDeltaE else { return nil }
        let settings = environment.settingsStore.load()
        return ColorDifference.classify(
            deltaE: de,
            goodMax: settings.deltaEGoodMax,
            warningMax: settings.deltaEWarningMax)
    }

    /// `spotLabImplausible` — L* outside 0…100 still displays, unclamped.
    var isDisplayedLabImplausible: Bool {
        guard let l = displayedSample?.lab.l else { return false }
        return l < 0 || l > 100
    }

    // MARK: - Sheet lifecycle

    /// Called from `SpotReadView.onAppear`. Resets the in-memory session
    /// and runs detection once; a missing sidecar gets a wizard notice.
    func sheetOpened() {
        samples = []
        displayedSample = nil
        displayedDeltaE = nil
        log = []
        lastError = nil
        state = .idle
        prompt = "Press Start to open the instrument."

        guard sidecarAvailable else {
            workflow.wizard.showNotice(
                "spotread sidecar missing — run fetch-argyll", kind: .error)
            return
        }
        detectInstruments()
    }

    /// Called from `onDisappear` *and* the sheet's `onDismiss` — clearing
    /// the flag alone is not enough; a live child must be quit and
    /// killed (R14).
    func sheetClosed() {
        stopIfNeeded()
        samples = []
        displayedSample = nil
        displayedDeltaE = nil
        log = []
        defaultMissing = false
    }

    // MARK: - Detection

    func detectInstruments() {
        guard canDetect else { return }
        isDetecting = true
        detectionError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            // `instlist` is an exclusive lease (#116) — never spawn a
            // second one; surface the busy state instead.
            if await self.environment.runner.processManager.isRunning(ProcessID.instlist) {
                self.detectionError = "Instrument detection is already running."
                self.isDetecting = false
                return
            }
            do {
                let devices = try await self.environment.runner.detectInstruments()
                self.instruments = devices
                self.seedDefault(from: devices)
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

    /// Seed the picker from `AppSettings.defaultInstrument`; no match →
    /// `.auto` + `spotDefaultMissing`.
    private func seedDefault(from devices: [InstrumentDevice]) {
        guard let code = environment.settingsStore.load().defaultInstrument,
              !code.isEmpty else {
            defaultMissing = false
            return
        }
        if let match = devices.first(where: { Self.matches(code: code, device: $0) }) {
            selectedInstrument = .device(match)
            defaultMissing = false
        } else {
            selectedInstrument = .auto
            defaultMissing = true
        }
    }

    /// Whether an `instlist` device corresponds to a `printtarg -i` /
    /// settings instrument code (`i1`, `CM`, `p3`, `SS`, `20`/`22`/`41`/`51`).
    static func matches(code: String, device: InstrumentDevice) -> Bool {
        let haystack = "\(device.name) \(device.type)".lowercased()
        switch code {
        case "i1": return haystack.contains("i1pro") && !haystack.contains("i1pro 3") && !haystack.contains("i1pro3")
        case "p3": return haystack.contains("i1pro 3") || haystack.contains("i1pro3")
        case "CM": return haystack.contains("colormunki")
        case "SS": return haystack.contains("specbos") || haystack.contains("spectraval") || haystack.contains("spectroscan") || haystack.contains("spectro scan")
        case "20": return haystack.contains("display 2")
        case "22": return haystack.contains("display")
        case "41": return haystack.contains("spyder 4") || haystack.contains("spyder 5") || haystack.contains("spyder4") || haystack.contains("spyder5")
        case "51": return haystack.contains("spyder x")
        default: return false
        }
    }

    /// Reverse of `matches` — most specific codes first.
    static func code(for device: InstrumentDevice) -> String? {
        for code in ["p3", "51", "41", "22", "20", "CM", "SS", "i1"]
        where matches(code: code, device: device) {
            return code
        }
        return nil
    }

    /// `spotSetDefault` — writes `AppSettings.defaultInstrument` only.
    /// Never touches `printtarg -i` or `targen`.
    func applyDefaultToggle(_ on: Bool) {
        setAsDefault = on
        var settings = environment.settingsStore.load()
        if on, case .device(let device) = selectedInstrument {
            settings.defaultInstrument = Self.code(for: device)
        } else if !on {
            settings.defaultInstrument = nil
        }
        try? environment.settingsStore.save(settings)
    }

    // MARK: - Session control

    func start() {
        guard sidecarAvailable else {
            lastError = "spotread sidecar missing — run fetch-argyll"
            return
        }
        guard !isChartreadRunning else {
            lastError = "Stop the Stage 3 chart read first."
            return
        }
        guard let cwd = workflow.wizard.effectiveWorkingDirectory else {
            lastError = "Set a working folder in Stage 1 first."
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // `spotread` is an exclusive lease — a second Start while a
            // child is live is an error, not a kill + respawn (#116).
            if await self.environment.runner.processManager.isRunning(ProcessID.spotread) {
                self.lastError = "A spotread session is already running."
                return
            }
            self.begin(config: self.buildConfig(cwd: cwd))
        }
    }

    private func buildConfig(cwd: URL) -> SpotReadConfig {
        let port: Int?
        let name: String
        switch selectedInstrument {
        case .auto:
            port = nil
            name = "Auto"
        case .device(let device):
            port = device.port
            name = device.name
        }
        return SpotReadConfig(
            workingDirectory: cwd,
            selectedPort: selectedInstrument.chartreadPort,
            enableLEDs: environment.settingsStore.load().enableI1Pro2Leds,
            isXY: selectedInstrument.isXY,
            instrumentName: name,
            instrumentPort: port
        )
    }

    private func begin(config: SpotReadConfig) {
        isRunning = true
        state = .idle
        lastError = nil
        prompt = "Waiting for a reading…"

        let stream = environment.runner.runSpotread(config: config)
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in stream {
                self.handle(event: event)
            }
            self.isRunning = false
            self.state = .idle
            if self.lastError == nil {
                self.prompt = "Press Start to open the instrument."
            }
        }
    }

    private func handle(event: SpotReadEvent) {
        switch event {
        case .prompt(let result):
            state = result.state
            prompt = promptText(for: result.state)

        case .sample(let sample):
            let previous = samples.first
            samples.insert(sample, at: 0)
            if samples.count > historyLimit {
                samples.removeLast()
            }
            displayedSample = sample
            displayedDeltaE = previous.map {
                ColorDifference.deltaE00($0.lab, sample.lab)
            }

        case .log(let batch):
            log.append(contentsOf: batch)

        case .exit(let code):
            if code != 0 {
                lastError = "spotread exited with code \(code)"
            }

        case .failed(let error):
            lastError = error.localizedDescription
        }
    }

    private func promptText(for state: ChartreadState) -> String {
        switch state {
        case .calibrating:
            return "Place the instrument on the calibration tile, then Calibrate."
        case .awaitingStrip:
            return "Place on the patch, then Read."
        case .reading, .promptContinue:
            return "Waiting for a reading…"
        case .warning:
            return "Instrument warning — stop and restart if it persists."
        case .error:
            return "Read error — Stop, then Start again."
        default:
            return "Waiting for a reading…"
        }
    }

    // MARK: - Transport

    /// `btnSpotCalibrate` — same bytes Stage 3 sends for calibrate.
    func calibrate() {
        send(.trigger)
    }

    /// `btnSpotTrigger` — the Read key (`" \n"`).
    func trigger() {
        send(.trigger)
    }

    private func send(_ input: ChartreadInput) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            try? await self.environment.runner.sendSpotreadInput(input)
        }
    }

    /// `btnSpotStop` / sheet dismiss: `q\n`, ~500 ms, then kill if the
    /// child is still live.
    func stopIfNeeded() {
        guard isRunning else { return }
        streamTask?.cancel()
        streamTask = nil
        let processManager = environment.runner.processManager
        Task { @MainActor in
            try? await processManager.sendStdin(
                id: ProcessID.spotread, bytes: ChartreadInput.quit.bytes)
            try? await Task.sleep(nanoseconds: 500_000_000)
            await processManager.kill(id: ProcessID.spotread)
        }
        isRunning = false
        state = .idle
        prompt = "Press Start to open the instrument."
    }

    // MARK: - History / export

    /// Click a history row: copies that sample into the last-sample card.
    /// Never re-triggers the instrument.
    func selectFromHistory(_ sample: SpotReadSample) {
        displayedSample = sample
        if let index = samples.firstIndex(of: sample), index + 1 < samples.count {
            displayedDeltaE = ColorDifference.deltaE00(samples[index + 1].lab, sample.lab)
        } else {
            displayedDeltaE = nil
        }
    }

    /// `btnSpotCopyLab` — `L* a* b*` of the displayed sample as plain
    /// text (`50.0 1.2 -3.4`).
    func copyLab() {
        guard let sample = displayedSample else { return }
        let text = String(format: "%.1f %.1f %.1f", sample.lab.l, sample.lab.a, sample.lab.b)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// `btnSpotExportCsv` — RFC-4180 via `selectCsvSavePath`. Cancel is
    /// a no-op. Rows are newest-first, matching the history list.
    func exportCsv() {
        guard !samples.isEmpty else { return }
        let url = UITestHooks.isEnabled
            ? UITestHooks.csvExportURL
            : fileDialogs.selectCsvSavePath()
        guard let url else { return }

        var out = "timestamp,L,a,b,dE00,instrument,port\r\n"
        for (index, sample) in samples.enumerated() {
            let deltaE = index + 1 < samples.count
                ? String(format: "%.2f", ColorDifference.deltaE00(samples[index + 1].lab, sample.lab))
                : ""
            out += "\(csvField(iso8601(sample.timestamp))),\(f1(sample.lab.l)),\(f1(sample.lab.a)),\(f1(sample.lab.b)),\(deltaE),\(csvField(sample.instrumentName)),\(sample.port.map(String.init) ?? "")\r\n"
        }

        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
            workflow.wizard.showNotice("Spot readings exported: \(url.lastPathComponent)")
        } catch {
            workflow.wizard.showNotice(
                "Export failed: \(error.localizedDescription)", kind: .error)
        }
    }

    private func f1(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func csvField(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else {
            return text
        }
        return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
