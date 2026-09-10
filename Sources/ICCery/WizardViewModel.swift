import Foundation
import Observation
import ICCeryCore

/// Wizard state machine + artefact gating (issue #4, docs/06).
///
/// `wizardState` fields (`currentStage`, `basename`, `cwd`,
/// `printerName`, `sessionMode`, `profileBasename`,
/// `calibrationOriginalBasename`) are persisted to
/// `wizard_state.json`; unlocks come from `ArtefactProbe.verify` —
/// navigation is disk, not buttons.
@MainActor
@Observable
final class WizardViewModel {

    // MARK: - wizardState fields (persisted)

    var stage: WizardStage {
        didSet { if stage != oldValue { persist() } }
    }
    /// `wizardState.basename` — empty until a real artefact names it (#60).
    var basename: String {
        didSet { if basename != oldValue { refreshGating(); persist() } }
    }
    /// `wizardState.cwd` — resolved via `resolveSafeCwd` (#59).
    var workingDirectory: URL? {
        didSet { if workingDirectory != oldValue { refreshGating(); persist() } }
    }
    var printerName: String? {
        didSet { if printerName != oldValue { persist() } }
    }
    var sessionMode: SessionMode {
        didSet { if sessionMode != oldValue { persist() } }
    }
    /// `profileBasename` may differ after a `.ti3` import (#94).
    var profileBasename: String? {
        didSet { if profileBasename != oldValue { persist() } }
    }
    /// Pre-`CAL_` basename, persisted so relaunch/Force Quit can restore it (#29).
    var calibrationOriginalBasename: String {
        didSet { if calibrationOriginalBasename != oldValue { persist() } }
    }

    // MARK: - Ephemeral

    /// Banner notice currently displayed (`#wizardNotification`).
    var notice: Notice?
    /// Current artefact probe result; recomputed on `refreshGating()`.
    private(set) var artefacts = StageArtefacts()
    /// Whether the 3D gamut viewer sheet is open (issue #28).
    var showingGamutViewer = false
    /// Optional `.gam` URL to show alongside the sRGB reference.
    var gamutProfileURL: URL?

    private let stateStore: WizardStateStore
    private var noticeDismissTask: Task<Void, Never>?

    init(stateStore: WizardStateStore = WizardStateStore()) {
        self.stateStore = stateStore
        let s = stateStore.load()
        self.stage = s.stage
        self.basename = s.basename
        self.workingDirectory = s.cwd.isEmpty ? nil : URL(fileURLWithPath: s.cwd)
        self.printerName = s.printerName
        self.sessionMode = s.sessionMode
        self.profileBasename = s.profileBasename
        self.calibrationOriginalBasename = s.calibrationOriginalBasename
        // A Force Quit mid-calibration leaves a CAL_ basename behind; restore
        // the original before the UI can do anything with it (#29).
        if basename.hasPrefix("CAL_"), !calibrationOriginalBasename.isEmpty {
            basename = calibrationOriginalBasename
            calibrationOriginalBasename = ""
            sessionMode = .profile
            stage = .generate
        }
        refreshGating()
        // A restored stage may have been locked since (#151).
        if !WizardGating.isUnlocked(stage, artefacts: artefacts), stage != .calibrate {
            stage = WizardGating.deepestUnlocked(artefacts: artefacts)
        }
    }

    // MARK: - Gating

    /// `isUnlocked` for the sidebar stepper.
    func isUnlocked(_ stage: WizardStage) -> Bool {
        WizardGating.isUnlocked(stage, artefacts: artefacts)
    }

    /// `true` while Stage 0 (printer calibration) is shown.
    var isCalibrating: Bool { stage == .calibrate }

    /// Re-probes the artefact directory and re-locks (#151). Called on
    /// window focus, stage entry, and basename/cwd changes.
    func refreshGating() {
        guard !basename.isEmpty, let dir = effectiveWorkingDirectory else {
            artefacts = StageArtefacts()
            return
        }
        artefacts = ArtefactProbe.verify(basename: basename, cwd: dir)
    }

    /// `setTarget(basename, cwd)` — validates the basename (no `/`, `\`,
    /// `..`; no placeholders — #60) and resolves the cwd (#59).
    func setTarget(basename: String, workingDirectory: URL?) {
        do {
            self.basename = try PathSecurity.sanitizeBasename(basename)
        } catch {
            showNotice("Invalid target name.", kind: .error)
            return
        }
        self.workingDirectory = PathSecurity.resolveSafeCwd(workingDirectory)
    }

    /// cwd never stays empty once a basename exists (#59).
    var effectiveWorkingDirectory: URL? {
        if let workingDirectory { return workingDirectory }
        return basename.isEmpty ? nil : PathSecurity.resolveSafeCwd(nil)
    }

    // MARK: - Navigation

    /// `navigateToStage(n)` — refuses locked forward moves with a
    /// warning banner; backward is always allowed (docs/06).
    ///
    /// If the live basename has a `CAL_` prefix, only `.calibrate`,
    /// `.layOutPrint`, and `.measure` are allowed; any other target is
    /// refused and the original basename is restored (#29).
    func go(to target: WizardStage) {
        guard target != .calibrate else { enterCalibration(); return }
        if basename.hasPrefix("CAL_") {
            guard !calibrationOriginalBasename.isEmpty else {
                showNotice(
                    "Cannot leave calibration — the original target name is missing.",
                    kind: .warning
                )
                return
            }
            if target == .generate || target == .buildProfile || target == .verifyInstall {
                restoreCalibration()
                return
            }
        }
        if WizardGating.canNavigate(to: target, from: stage, artefacts: artefacts) {
            stage = target
        } else {
            showNotice(
                "Stage \(target.stepperIndex ?? 0) is locked — the required artefact is missing.",
                kind: .warning
            )
        }
    }

    func enterCalibration() {
        if !basename.isEmpty, !basename.hasPrefix("CAL_"), calibrationOriginalBasename.isEmpty {
            calibrationOriginalBasename = basename
        }
        sessionMode = .calibration
        stage = .calibrate
    }

    func exitCalibration() {
        sessionMode = .profile
        stage = .generate
    }

    /// Restore the original profile basename and leave calibration mode.
    func restoreCalibration() {
        if !calibrationOriginalBasename.isEmpty {
            basename = calibrationOriginalBasename
            calibrationOriginalBasename = ""
        }
        sessionMode = .profile
    }

    /// Open the 3D gamut viewer (issue #28).
    func openGamut(profileGamURL: URL? = nil) {
        self.gamutProfileURL = profileGamURL
        showingGamutViewer = true
    }

    /// Window-focus hook (#151): files deleted in Finder re-lock stages.
    /// If the current stage re-locked, fall back to the deepest unlocked.
    func windowDidBecomeKey() {
        refreshGating()
        if stage != .calibrate,
           !WizardGating.isUnlocked(stage, artefacts: artefacts) {
            stage = WizardGating.deepestUnlocked(artefacts: artefacts)
        }
    }

    // MARK: - Notice

    func showNotice(_ text: String, kind: Notice.Kind = .info, autoHideAfter: TimeInterval? = 6) {
        noticeDismissTask?.cancel()
        let notice = Notice(kind: kind, text: text, autoHideAfter: autoHideAfter)
        self.notice = notice
        if let delay = notice.autoHideAfter {
            noticeDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                if self?.notice?.id == notice.id {
                    self?.notice = nil
                }
            }
        }
    }

    func dismissNotice() {
        noticeDismissTask?.cancel()
        notice = nil
    }

    // MARK: - Persistence

    private func persist() {
        let state = WizardState(
            currentStage: stage.rawValue,
            basename: basename,
            cwd: workingDirectory?.path ?? "",
            printerName: printerName,
            sessionMode: sessionMode,
            profileBasename: profileBasename,
            calibrationOriginalBasename: calibrationOriginalBasename
        )
        try? stateStore.save(state)
    }
}
