import Combine
import Foundation
import SwiftUI
import ICCeryCore

/// Stage 4/5 workflow: build a profile, verify it, track drift, and install.
@MainActor
final class ProfileWorkflowViewModel: ObservableObject {

    let wizard: WizardViewModel
    let environment: AppEnvironment
    private let fileDialogs = FileDialogService.shared

    // MARK: - Stage 4 form

    @Published var algorithm: String = "l"      // l | x | X | m
    @Published var quality: String = "m"        // l | m | h | u
    @Published var intent: String = ""          // usually empty at Stage 4
    @Published var fwaSelection: ColprofFwaSelection = .none
    @Published var fwaCustomPath: String = ""
    @Published var illuminant: String = ""
    @Published var observer: String = ""
    @Published var inputViewingCond: String = ""
    @Published var outputViewingCond: String = ""
    @Published var profileDescription: String = ""
    @Published var copyright: String = ""

    // MARK: - Run state

    @Published var isColprofRunning = false
    @Published var colprofLog: [String] = []
    @Published var colprofProgress: String?
    @Published var createdProfileURL: URL?
    /// Path to the `.gam` gamut mesh extracted post-`colprof` (issue #28).
    @Published var createdGamutURL: URL?

    // MARK: - Stage 4/5 calibration (issue #24)

    @Published var applyCalibration = false
    @Published var calibrationFile: String = ""

    // MARK: - Stage 5 verification (issue #25)

    @Published var profcheckReport: ProfcheckReport?
    @Published var profcheckWarning: String?
    @Published var isProfcheckRunning = false

    // MARK: - History / drift (issue #26)

    @Published var verificationHistory: [VerificationRecord] = []
    @Published var driftPrinterFilter: String? = nil
    @Published var driftAlert: String?
    @Published var isHistoryStoreError: String?

    // MARK: - Install (issue #27)

    @Published var installResult: InstallProfileResult?
    @Published var showingInstallCollision = false
    @Published var installCollisionMessage: String = ""
    var pendingInstallOptions: InstallProfileOptions?

    init(wizard: WizardViewModel, environment: AppEnvironment) {
        self.wizard = wizard
        self.environment = environment
        restoreCreatedProfileURL()
    }

    /// Restores `createdProfileURL` and `createdGamutURL` from the wizard
    /// artefacts or by probing the working directory (#52, #28).
    func restoreCreatedProfileURL() {
        let cwd = wizard.effectiveWorkingDirectory ?? PathSecurity.resolveSafeCwd(nil)
        createdProfileURL = wizard.artefacts.profilePath
            ?? ArtefactProbe.resolveProfile(basename: wizard.basename, cwd: cwd)
        createdGamutURL = wizard.artefacts.gamPath
            ?? ArtefactProbe.artefact(wizard.basename, "gam", cwd)
        if let gam = createdGamutURL, !FileManager.default.fileExists(atPath: gam.path) {
            createdGamutURL = nil
        }
    }

    // MARK: - Derived

    var canCreateProfile: Bool {
        !wizard.basename.isEmpty && wizard.effectiveWorkingDirectory != nil && !isColprofRunning
    }

    var canVerify: Bool {
        createdProfileURL != nil && !isProfcheckRunning
    }

    var fwaValue: String? {
        fwaSelection.presetValue(customPath: fwaCustomPath)
    }

    // MARK: - Preset application

    func applyPreset(_ preset: ProfilingPreset?) {
        guard let preset else { return }
        let config = ColprofConfig(
            preset: preset,
            basename: wizard.basename,
            workingDirectory: wizard.effectiveWorkingDirectory
        )
        algorithm = config.algorithm
        quality = config.quality
        intent = config.intent ?? ""
        fwaSelection = ColprofFwaSelection(presetValue: config.fwa)
        fwaCustomPath = fwaSelection == .custom ? (config.fwa ?? "") : ""
        illuminant = config.illuminant ?? ""
        observer = config.observer ?? ""
        inputViewingCond = config.inputViewingCond ?? ""
        outputViewingCond = config.outputViewingCond ?? ""
        profileDescription = ""
        copyright = ""
        applyCalibration = preset.applyCalibration == true
        calibrationFile = preset.calibrationFile ?? ""
    }

    /// Stage 4 form values for saving into a custom preset.
    func presetSnapshot() -> (
        algorithm: String,
        quality: String,
        intent: String?,
        fwa: String?,
        illuminant: String?,
        observer: String?,
        inputViewingCond: String?,
        outputViewingCond: String?
    ) {
        (
            algorithm: algorithm,
            quality: quality,
            intent: intent.isEmpty ? nil : intent,
            fwa: fwaValue,
            illuminant: illuminant.isEmpty ? nil : illuminant,
            observer: observer.isEmpty ? nil : observer,
            inputViewingCond: inputViewingCond.isEmpty ? nil : inputViewingCond,
            outputViewingCond: outputViewingCond.isEmpty ? nil : outputViewingCond
        )
    }

    // MARK: - Stage 4: build profile

    func buildColprofConfig() -> ColprofConfig {
        let description = profileDescription.isEmpty ? wizard.basename : profileDescription
        return ColprofConfig(
            algorithm: algorithm,
            quality: quality,
            intent: intent.isEmpty ? nil : intent,
            fwa: fwaValue,
            illuminant: illuminant.isEmpty ? nil : illuminant,
            observer: observer.isEmpty ? nil : observer,
            inputViewingCond: inputViewingCond.isEmpty ? nil : inputViewingCond,
            outputViewingCond: outputViewingCond.isEmpty ? nil : outputViewingCond,
            description: description,
            copyright: copyright.isEmpty ? nil : copyright,
            basename: wizard.basename,
            workingDirectory: wizard.effectiveWorkingDirectory
        )
    }

    func createProfile() {
        guard canCreateProfile, let _ = wizard.effectiveWorkingDirectory else { return }
        let config = buildColprofConfig()

        colprofProgress = nil
        createdProfileURL = nil
        createdGamutURL = nil

        let runner = environment.runner
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await ProcessRunSupport.runLogged(
                    setRunning: { self.isColprofRunning = $0 },
                    resetLog: { self.colprofLog = [] },
                    onLog: { batch in
                        self.colprofLog.append(contentsOf: batch)
                        if let last = batch.last {
                            self.updateProgress(ColprofProgressClassifier.classify(line: last))
                        }
                    }
                ) { onLog in
                    let url = try await runner.runColprof(config: config, onLogBatch: onLog)

                    var finalProfileURL = url

                    if self.applyCalibration, !self.calibrationFile.isEmpty {
                        let applyConfig = ApplycalConfig(
                            calibrationPath: self.calibrationFile,
                            inputProfileURL: url
                        )
                        assert(!applyConfig.unapply, "applycal unapply is not supported in v2.0")
                        finalProfileURL = try await runner.runApplycal(config: applyConfig)
                        self.colprofLog.append("Calibration embedded: \(self.calibrationFile)")
                    }

                    // Gamut extraction is best-effort for Stage 5 / M6 viewer.
                    var gamutURL: URL?
                    do {
                        let gamConfig = IccgamutConfig(profileURL: finalProfileURL)
                        let url = try await runner.runIccgamut(config: gamConfig, onLogBatch: onLog)
                        gamutURL = url
                        self.colprofLog.append("Gamut mesh extracted: \(url.lastPathComponent)")
                    } catch {
                        self.wizard.showNotice(
                            "Gamut extraction skipped: \(error.localizedDescription)",
                            kind: .info
                        )
                    }
                    return (profileURL: finalProfileURL, gamutURL: gamutURL)
                }
                self.createdProfileURL = outcome.profileURL
                self.createdGamutURL = outcome.gamutURL
                self.wizard.refreshGating()
                self.wizard.showNotice("Profile created: \(outcome.profileURL.lastPathComponent)")
                self.wizard.go(to: .verifyInstall)
            } catch {
                self.wizard.showNotice(
                    "Profile creation failed: \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    private func updateProgress(_ progress: ColprofProgress) {
        switch progress {
        case .gamutMapping:
            colprofProgress = "Gamut mapping calculation…"
        case .fittingClut:
            colprofProgress = "Fitting cLUT grid points…"
        case .writingIcc:
            colprofProgress = "Writing ICC profile…"
        case .unknown:
            break
        }
    }

    // MARK: - Stage 5: verify profile

    var knownPrinters: [String] {
        var names = Set<String>()
        for record in verificationHistory {
            if record.printerName.isEmpty {
                names.insert("Unknown")
            } else {
                names.insert(record.printerName)
            }
        }
        return Array(names).sorted()
    }

    func loadHistory() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.verificationHistory = try await self.environment.historyStore.load()
                self.driftAlert = DriftAlert.compute(from: self.filteredHistory)
            } catch {
                self.isHistoryStoreError = error.localizedDescription
                self.wizard.showNotice(
                    "Could not load verification history: \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    var filteredHistory: [VerificationRecord] {
        guard let filter = driftPrinterFilter, !filter.isEmpty else {
            return verificationHistory
        }
        return verificationHistory.filter { $0.printerName == filter }
    }

    func verifyProfile() {
        guard canVerify,
              let cwd = wizard.effectiveWorkingDirectory,
              let profileURL = createdProfileURL else { return }

        let ti3URL = ArtefactProbe.artefact(wizard.basename, "ti3", cwd)
        let config = ProfcheckConfig(ti3URL: ti3URL, iccURL: profileURL)

        profcheckReport = nil
        profcheckWarning = nil

        let runner = environment.runner
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await ProcessRunSupport.runLogged(
                    setRunning: { self.isProfcheckRunning = $0 },
                    resetLog: {},
                    onLog: { self.colprofLog.append(contentsOf: $0) }
                ) { onLog in
                    let report = try await runner.runProfcheck(config: config, onLogBatch: onLog)
                    var history: [VerificationRecord]?
                    if let record = self.makeVerificationRecord(from: report) {
                        history = try await self.environment.historyStore.append(record)
                    }
                    return (report: report, history: history)
                }
                self.profcheckReport = outcome.report
                if let history = outcome.history {
                    self.verificationHistory = history
                    self.driftAlert = DriftAlert.compute(from: self.filteredHistory)
                }
            } catch let error as ArgyllRunnerError where error == .profcheckUnparseable {
                self.profcheckWarning = "profcheck output could not be parsed."
                self.profcheckReport = ProfcheckReport(warning: self.profcheckWarning)
            } catch {
                self.profcheckWarning = error.localizedDescription
                self.profcheckReport = ProfcheckReport(warning: self.profcheckWarning)
                self.wizard.showNotice(
                    "Verification failed: \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    func makeVerificationRecord(from report: ProfcheckReport) -> VerificationRecord? {
        guard let avg = report.avgDE,
              let max = report.maxDE,
              let rms = report.rmsDE,
              let status = report.status else { return nil }

        let timestamp = Date()
        let id = "vr-\(Int(timestamp.timeIntervalSince1970))-\(Self.nextSeq())"
        let printerName = wizard.printerName?.isEmpty == false ? wizard.printerName! : "Unknown"
        return VerificationRecord(
            id: id,
            profileName: createdProfileURL?.lastPathComponent ?? wizard.basename,
            printerName: printerName,
            avgDE: avg,
            maxDE: max,
            rmsDE: rms,
            patchCount: report.patchCount ?? 0,
            status: status,
            timestamp: timestamp
        )
    }

    private static func nextSeq() -> Int {
        Int.random(in: 0..<1_000_000)
    }

    func clearHistory() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.environment.historyStore.clear()
                self.verificationHistory = []
                self.driftAlert = nil
            } catch {
                self.wizard.showNotice(
                    "Could not clear history: \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    // MARK: - Profile install

    func beginInstallProfile() {
        guard let sourceURL = createdProfileURL,
              let _ = wizard.effectiveWorkingDirectory else { return }

        let settings = environment.settingsStore.load()
        let preferSystem = settings.defaultInstallLocation == .system
        let options = InstallProfileOptions(
            forceOverwrite: !settings.askBeforeOverwriteProfile,
            preferSystem: preferSystem,
            collisionPolicy: .overwrite,
            openColorPanel: settings.openColorPanelAfterInstall
        )

        do {
            let config = InstallProfileConfig(sourceURL: sourceURL, options: options)
            let destURL = try ProfileInstaller.resolveDestinationURL(for: config)
            let collision = FileManager.default.fileExists(atPath: destURL.path)

            if collision && settings.askBeforeOverwriteProfile {
                pendingInstallOptions = options
                installCollisionMessage = "A profile named \(destURL.lastPathComponent) already exists."
                showingInstallCollision = true
                return
            }

            runInstall(sourceURL: sourceURL, options: options)
        } catch {
            wizard.showNotice(
                "Install failed: \(error.localizedDescription)",
                kind: .error
            )
        }
    }

    func resolveInstallCollision(policy: ProfileCollisionPolicy) {
        showingInstallCollision = false
        guard let sourceURL = createdProfileURL,
              var options = pendingInstallOptions else { return }

        if policy == .cancel {
            installResult = InstallProfileResult(
                destPath: "",
                registered: false,
                overwritten: false,
                renamed: false,
                openedPanel: false,
                message: "Install cancelled."
            )
            return
        }

        options.collisionPolicy = policy
        if policy == .overwrite {
            options.forceOverwrite = true
        }
        runInstall(sourceURL: sourceURL, options: options)
    }

    private func runInstall(sourceURL: URL, options: InstallProfileOptions) {
        let config = InstallProfileConfig(sourceURL: sourceURL, options: options)
        Task(priority: .userInitiated) { [weak self] in
            do {
                let result = try ProfileInstaller.install(config: config)
                await MainActor.run { [weak self] in
                    self?.installResult = result
                    self?.wizard.showNotice(result.message)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.wizard.showNotice(
                        "Install failed: \(error.localizedDescription)",
                        kind: .error
                    )
                }
            }
        }
    }

    func exportHistory() {
        guard let url = fileDialogs.selectCsvSavePath() else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let csv = await self.environment.historyStore.exportCSV()
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                self.wizard.showNotice("History exported: \(url.lastPathComponent)")
            } catch {
                self.wizard.showNotice(
                    "Export failed: \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    // MARK: - File pickers

    func browseForSpectrumFile() {
        let start = wizard.effectiveWorkingDirectory
        let url = UITestHooks.isEnabled
            ? nil
            : fileDialogs.selectSpectrumFile(startingAt: start)
        if let url {
            fwaSelection = .custom
            fwaCustomPath = url.path
        }
    }

    func browseForCalibrationFile() {
        let start = wizard.effectiveWorkingDirectory
        let url = fileDialogs.selectCalFile(startingAt: start)
        if let url {
            calibrationFile = url.path
            applyCalibration = true
        }
    }
}
