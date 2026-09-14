import Combine
import Foundation
import ICCeryCore

/// Media recipe library: capture / apply / staleness for issue #146.
///
/// A recipe binds a CUPS queue + paper + ink + `.cal` to a
/// `ProfilingPreset`. Applying a recipe goes through the existing
/// `applyPreset` (#82) path — there is no second Stage 1 form. Paper
/// and ink are library metadata only; they are never written to the
/// targen label fields.
@MainActor
final class MediaLibraryViewModel: ObservableObject {

    /// Why a recipe row is flagged stale.
    struct StaleReason: OptionSet {
        let rawValue: Int
        static let calibration = StaleReason(rawValue: 1 << 0)
        static let printer = StaleReason(rawValue: 1 << 1)
    }

    let workflow: TargetWorkflowViewModel
    let environment: AppEnvironment
    private let store: MediaLibraryStore
    private var cancellables = Set<AnyCancellable>()

    @Published var recipes: [MediaRecipe] = []
    /// Sidebar picker selection; `"none"` = no media recipe. Written
    /// only on a successful apply so a failed apply snaps back.
    @Published var selectedRecipeID = "none"
    /// `recipe.id` → stale reasons for the sidebar badge / manage sheet.
    @Published var staleReasons: [String: StaleReason] = [:]
    /// `recipe.id` → whole days since the bound `.cal` was created.
    @Published var calAgeDays: [String: Int] = [:]

    // Save-sheet state (mirrors savePresetName/savePresetDesc).
    @Published var saveMediaName = ""
    @Published var saveMediaNotes = ""
    @Published var saveMediaPaper = ""
    @Published var saveMediaInk = ""
    @Published var saveMediaApplyCal = false
    /// Inline caption inside the capture sheet (no a11y id — roster complete).
    @Published var saveMediaError: String?
    /// Last failed Apply while Manage is open. The window banner sits
    /// behind the sheet on Monterey, so the dialog shows this too (#170).
    @Published var manageApplyNotice: String?

    /// Pure flow flag — the manage sheet's "Capture current…" asks the
    /// sheet's `onDismiss` to open the capture sheet, avoiding a
    /// present-while-dismissing race.
    var captureAfterManageDismiss = false

    init(workflow: TargetWorkflowViewModel, environment: AppEnvironment) {
        self.workflow = workflow
        self.environment = environment
        self.store = environment.mediaStore

        reload()
        refreshStaleness()
        // The library needs queues enumerated at launch so Capture can
        // enable and the not-installed badge is computable; Stage 2 only
        // enumerates when a printtarg manifest exists.
        if workflow.print.printers.isEmpty {
            workflow.print.refreshPrinters()
        }

        NotificationCenter.default
            .publisher(for: SettingsStore.settingsDidChange)
            .sink { [weak self] _ in self?.refreshStaleness() }
            .store(in: &cancellables)
        workflow.print.$printers
            .sink { [weak self] _ in self?.refreshStaleness() }
            .store(in: &cancellables)
        workflow.print.$selectedPrinter
            .sink { [weak self] _ in self?.refreshStaleness() }
            .store(in: &cancellables)
    }

    deinit { cancellables.removeAll() }

    // MARK: - Load / corrupt

    func reload() {
        Task { await reloadAsync() }
    }

    func reloadAsync() async {
        do {
            recipes = try await store.load()
        } catch {
            // Corrupt-file policy: keep the file, keep the cache,
            // persistent warning; the picker falls back to "none".
            workflow.wizard.showNotice(
                "Media library is unreadable — the existing file was kept.",
                kind: .warning,
                autoHideAfter: nil
            )
            if recipes.isEmpty { selectedRecipeID = "none" }
        }
    }

    // MARK: - Selection / apply

    /// Sidebar `mediaSelect` binding. `"none"` clears the selection
    /// without resetting any Stage 1/2/4 field — it is not "reset to
    /// factory".
    func selectRecipe(_ id: String) {
        if id == "none" {
            selectedRecipeID = "none"
            return
        }
        guard let recipe = recipes.first(where: { $0.id == id }) else { return }
        Task { _ = await apply(recipe) }
    }

    /// The single apply path — sidebar picker, manage-row Apply, and
    /// the manage footer all funnel here.
    ///
    /// Returns `false` when any bound resource is unresolved (missing
    /// preset, colour-space mismatch, queue absent, missing/unparseable
    /// `.cal`) so the manage sheet stays open and the picker reverts.
    /// A `CAL_`-blocked calibration counts as applied (`true` — success
    /// with warning; the refusal is permanent so re-clicking can't help).
    @discardableResult
    func apply(_ recipe: MediaRecipe) async -> Bool {
        manageApplyNotice = nil
        guard let r = try? recipe.validated() else {
            return failApply("Media recipe is invalid — not applied.", kind: .error)
        }
        guard let preset = environment.presetStore.all()
            .first(where: { $0.id == r.presetID })
        else {
            return failApply(
                "Preset \(r.presetID) no longer exists — recipe not applied.",
                kind: .error)
        }
        guard preset.colourSpace.lowercased() == r.colourSpace.lowercased() else {
            return failApply(
                "Recipe colour space does not match its preset — not applied.",
                kind: .error)
        }

        // Existing #82 mapping: presetSelect jumps, Stage 1/2/4 fields.
        workflow.applyPreset(preset)
        // Literal per issue: displayName, not the queue id.
        workflow.wizard.printerName = r.printerDisplayName

        // Queue: enumerate fresh via the session's serialized path —
        // listPrinters uses fixed process ids, so an overlapping
        // enumeration would throw duplicateID. An empty result is a
        // valid list.
        if let queues = await workflow.print.enumeratePrinters() {
            if queues.contains(where: { $0.name == r.printerID }) {
                workflow.print.selectedPrinter = r.printerID
                await workflow.print.reloadSelectedCapabilities()
            } else {
                return failApply(
                    "Printer \(r.printerDisplayName) is not installed.",
                    kind: .warning)
            }
        } else {
            return failApply(
                "Could not enumerate printers — queue left unchanged.",
                kind: .warning)
        }

        // Calibration — the recipe is authoritative and runs after
        // applyPreset so the preset's own cal fields don't win.
        let calPath = r.calibrationURL?.trimmingCharacters(in: .whitespaces) ?? ""
        let calStem = URL(fileURLWithPath: calPath)
            .deletingPathExtension().lastPathComponent
        let blocked = r.applyCalibration && !calPath.isEmpty
            && (CalibrationIdentity.isCalibration(calStem)
                || CalibrationIdentity.isCalibration(workflow.wizard.basename))

        if blocked {
            // Literal CAL_ refusal on both names (decision 1): keep the
            // path for display but never let `printtarg -K` see it.
            workflow.profile.applyCalibration = false
            workflow.profile.calibrationFile = calPath
            selectedRecipeID = r.id
            refreshStaleness()
            workflow.wizard.showNotice(
                "Applied \(r.name) — CAL_ calibrations cannot enable printtarg -K.",
                kind: .warning,
                autoHideAfter: nil)
            return true
        }

        if r.applyCalibration && !calPath.isEmpty {
            guard FileManager.default.fileExists(atPath: calPath) else {
                workflow.profile.applyCalibration = false
                workflow.profile.calibrationFile = calPath
                return failApply(
                    "Calibration file is missing: \(calPath)", kind: .error)
            }
            do {
                let staleDays = environment.settingsStore.load().calibrationStaleDays
                let calStore = CalibrationStore(staleDays: staleDays)
                try await calStore.load(url: URL(fileURLWithPath: calPath))
                workflow.profile.calibrationFile = calPath
                workflow.profile.applyCalibration = true
                // Age check only — the .cal DESCRIPTOR is free text, not
                // a queue id, so a name compare false-positives.
                if await calStore.isStale() {
                    workflow.wizard.showNotice(
                        "Applied \(r.name) — calibration is stale.",
                        kind: .warning)
                }
            } catch {
                workflow.profile.applyCalibration = false
                return failApply(
                    "Could not load calibration: \(error.localizedDescription)",
                    kind: .error)
            }
        } else {
            workflow.profile.applyCalibration = false
            workflow.profile.calibrationFile = calPath
        }

        selectedRecipeID = r.id
        workflow.wizard.showNotice("Applied \(r.name)")
        refreshStaleness()
        return true
    }

    private func failApply(_ text: String, kind: Notice.Kind) -> Bool {
        manageApplyNotice = text
        workflow.wizard.showNotice(text, kind: kind)
        refreshStaleness()
        return false
    }

    // MARK: - Capture

    /// Whether the live `profile.calibrationFile` may be applied:
    /// non-empty, not a `CAL_` stem, and present on disk.
    var calApplyable: Bool {
        let path = workflow.profile.calibrationFile
        guard !path.isEmpty else { return false }
        let stem = URL(fileURLWithPath: path)
            .deletingPathExtension().lastPathComponent
        guard !CalibrationIdentity.isCalibration(stem) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// A bound preset whose colour space disagrees with the live form —
    /// the sheet shows the mismatch caption and disables Save.
    var captureColourSpaceMismatch: Bool {
        guard let preset = workflow.selectedPreset else { return false }
        return preset.colourSpace.lowercased() != workflow.colourSpace.rawValue
    }

    /// Opens the capture sheet, prefilled from the selected recipe else
    /// the most recently captured one ("last recipe … or empty").
    func beginCapture() {
        let source = recipes.first(where: { $0.id == selectedRecipeID })
            ?? recipes.last
        saveMediaPaper = source?.paperName ?? ""
        saveMediaInk = source?.inkSet ?? ""
        saveMediaName = ""
        saveMediaNotes = ""
        saveMediaError = nil
        saveMediaApplyCal = workflow.profile.applyCalibration && calApplyable
        if workflow.print.printers.isEmpty {
            workflow.print.refreshPrinters()
        }
        workflow.showingSaveMedia = true
    }

    /// Save button — the sheet closes only on `true`.
    func captureFromSession() async -> Bool {
        let name = saveMediaName.trimmingCharacters(in: .whitespacesAndNewlines)
        let paper = saveMediaPaper.trimmingCharacters(in: .whitespacesAndNewlines)
        let ink = saveMediaInk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !paper.isEmpty, !ink.isEmpty else {
            saveMediaError = "Name, paper and ink are required."
            return false
        }

        let queue = workflow.print.selectedPrinter
        guard !queue.isEmpty else {
            saveMediaError = "Select a printer in Stage 2 first."
            return false
        }

        // Preset binding: the selected preset when its colour space
        // matches the live form; otherwise auto-snapshot the live form
        // as a custom preset (decision 2).
        let presetID: String
        if let bound = workflow.selectedPreset {
            guard bound.colourSpace.lowercased() == workflow.colourSpace.rawValue else {
                saveMediaError = "Colour space does not match the selected preset."
                return false
            }
            presetID = bound.id
        } else {
            let snapshot = ProfilingPreset(
                id: "custom-\(UUID().uuidString.lowercased())",
                name: name,
                description: "Auto-saved for media recipe",
                targen: workflow.buildTargenConfig(),
                printtarg: workflow.buildPrinttargConfig(),
                colprof: workflow.profile.buildColprofConfig(),
                calibrationFile: nil,
                applyCalibration: nil
            )
            do {
                try environment.presetStore.saveCustom(snapshot)
                workflow.reloadPresets()
                workflow.selectedPresetID = snapshot.id
            } catch {
                saveMediaError = "Could not save preset: \(error.localizedDescription)"
                return false
            }
            presetID = snapshot.id
        }

        // The cal path is stored verbatim; applyCalibration is forced
        // off for CAL_/missing paths via calApplyable.
        let calPath = workflow.profile.calibrationFile
        let printer = workflow.print.printers.first { $0.name == queue }
        let now = Date()
        let recipe = MediaRecipe(
            id: "recipe-\(UUID().uuidString.lowercased())",
            name: name,
            notes: saveMediaNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            printerID: queue,
            printerDisplayName: printer?.displayName ?? queue,
            paperName: paper,
            driverMediaType: workflow.print.selectedMediaType,
            inkSet: ink,
            colourSpace: workflow.colourSpace.rawValue,
            presetID: presetID,
            calibrationURL: calPath.isEmpty ? nil : calPath,
            applyCalibration: saveMediaApplyCal && calApplyable,
            created: now,
            updated: now
        )

        do {
            let validated = try recipe.validated()
            try await store.upsert(validated)
            await reloadAsync()
            selectedRecipeID = validated.id
            workflow.wizard.showNotice("Media recipe saved: \(validated.name)")
            return true
        } catch let error as MediaLibraryStore.MediaLibraryError {
            saveMediaError = error.errorDescription
            return false
        } catch {
            saveMediaError = "Could not save: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Delete

    func delete(_ recipe: MediaRecipe) {
        Task {
            do {
                try await store.delete(id: recipe.id)
                await reloadAsync()
                if selectedRecipeID == recipe.id {
                    selectedRecipeID = "none"
                }
            } catch {
                workflow.wizard.showNotice(
                    "Could not delete: \(error.localizedDescription)",
                    kind: .error)
            }
        }
    }

    // MARK: - Staleness

    func refreshStaleness() {
        Task { await refreshStalenessAsync() }
    }

    /// Recomputes `staleReasons` + `calAgeDays` for every recipe.
    ///
    /// `.printer` fires only when `printerID` is absent from a
    /// **non-empty** enumerated queue list — an un-enumerated list is
    /// indeterminate, not stale (decision 5). `.calibration` is a pure
    /// age check (`isStale()` with no `comparedTo:`) — the `.cal`
    /// DESCRIPTOR is free text, not a queue id.
    func refreshStalenessAsync() async {
        let staleDays = environment.settingsStore.load().calibrationStaleDays
        let queues = workflow.print.printers
        let now = Date()
        let calStore = CalibrationStore(staleDays: staleDays)

        var reasons: [String: StaleReason] = [:]
        var ages: [String: Int] = [:]
        for r in recipes {
            var flags: StaleReason = []
            if !queues.isEmpty, !queues.contains(where: { $0.name == r.printerID }) {
                flags.insert(.printer)
            }
            if let raw = r.calibrationURL?.trimmingCharacters(in: .whitespaces),
               !raw.isEmpty,
               FileManager.default.fileExists(atPath: raw),
               (try? await calStore.load(url: URL(fileURLWithPath: raw))) != nil,
               let created = await calStore.data?.created {
                ages[r.id] = Calendar.current
                    .dateComponents([.day], from: created, to: now).day ?? 0
                if await calStore.isStale() {
                    flags.insert(.calibration)
                }
            }
            if !flags.isEmpty { reasons[r.id] = flags }
        }
        staleReasons = reasons
        calAgeDays = ages
    }

    // MARK: - Manage sheet flow

    /// Called from the manage sheet's `onDismiss`. A deferred capture
    /// request opens the save sheet only now, after the manage sheet has
    /// fully dismissed.
    func manageDismissed() {
        if captureAfterManageDismiss {
            captureAfterManageDismiss = false
            beginCapture()
        }
    }
}
