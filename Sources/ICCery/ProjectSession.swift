import AppKit
import Combine
import Foundation
import ICCeryCore

/// Project file session (issue #149): `.icceryproj` open/save/new/close,
/// recents, the dirty flag, and the window title.
///
/// The project is an **index** — disk artefacts still own the stepper
/// (R18). Open writes `WizardState` through the normal setters and ends
/// in the same probe `windowDidBecomeKey` uses; it never auto-runs
/// `targen`/`colprof`/`chartread` and never unlocks a stage the disk
/// does not back.
@MainActor
final class ProjectSession: ObservableObject {

    /// What to do once the dirty alert resolves.
    enum PendingAction {
        case new
        case open(URL)
        case close
    }

    /// A live session snapshot, compared against the bound project for
    /// the dirty flag (title `•`, `btnProjectSave`).
    private struct Snapshot: Equatable {
        var basename: String
        var cwd: String
        var printerID: String?
        var presetID: String?
        var mediaRecipeID: String?
        var calibrationURL: String?
    }

    let workflow: TargetWorkflowViewModel
    let environment: AppEnvironment
    private let fileDialogs = FileDialogService.shared
    private let recentsStore: RecentProjectsStore
    private var cancellables = Set<AnyCancellable>()

    /// Bound project file location; `nil` = no project.
    @Published var projectURL: URL?
    /// Last saved/opened project payload.
    @Published var project: ICCeryProject?
    /// Open Recent entries, newest first, missing files pruned.
    @Published var recents: [RecentProjectEntry] = []
    /// JSON claimed a finished profile but disk stops earlier —
    /// `projectChipStale` + info banner (R18).
    @Published var diskBehindNotes = false
    /// `ICCery` / `ICCery — {name}` / `ICCery — {name} •`.
    @Published var windowTitle = "ICCery"
    /// Live session fields differ from the bound project — computed
    /// fresh so decision paths (`requestNew`/`requestClose`) never see
    /// a stale willSet value.
    var isDirty: Bool {
        guard let project else { return false }
        return liveSnapshot() != snapshot(of: project)
    }

    // Flow state for RootView.
    @Published var showingNewAlert = false
    @Published var showingDirtyAlert = false
    @Published var showingRelocateSheet = false

    private var pendingAction: PendingAction?
    /// Loaded project whose `cwd` is missing — relocate sheet payload.
    @Published private(set) var pendingRelocate:
        (project: ICCeryProject, url: URL)?

    init(workflow: TargetWorkflowViewModel, environment: AppEnvironment) {
        self.workflow = workflow
        self.environment = environment
        self.recentsStore = environment.recentProjectsStore
        refreshRecents()

        // Dirty / title derive from live fields — observe each source;
        // child VMs are not tracked through the parent's
        // objectWillChange (R22-style weak sinks). `@Published` fires on
        // willSet, so the recompute is deferred one main turn to read
        // post-set values.
        let wizard = workflow.wizard
        let printSession = workflow.print
        let media = workflow.media
        let profile = workflow.profile
        wizard.$basename.sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)
        wizard.$workingDirectory.sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)
        wizard.$printerName.sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)
        printSession?.$selectedPrinter.sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)
        workflow.$selectedPresetID.sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)
        media?.$selectedRecipeID.sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)
        profile.$calibrationFile.sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)
        recomputeDerived()
    }

    deinit { cancellables.removeAll() }

    // MARK: - Derived

    var isBound: Bool { project != nil }

    /// A chartread / spotread / colprof child is live — project changes
    /// wait for the instrument run to finish.
    var childSessionLive: Bool {
        workflow.measurement.isChartreadRunning
            || workflow.spotRead.isRunning
            || workflow.profile.isColprofRunning
    }

    /// Basename eligible for persistence. A live `CAL_` stem resolves
    /// only through the persisted original — never by stripping, so a
    /// bare `CAL_` (Force-Quit anomaly, empty persisted original) is
    /// refused rather than trusted (R11).
    var resolvedBasename: String? {
        let live = workflow.wizard.basename
        guard CalibrationIdentity.isCalibration(live) else {
            return live.isEmpty ? nil : live
        }
        let original = workflow.wizard.calibrationOriginalBasename
        return original.isEmpty ? nil : original
    }

    /// ⌘S / `btnProjectSave` enable rule. A `CAL_` live basename stays
    /// enabled so the refusal can show its banner.
    var canSave: Bool {
        isBound && !workflow.wizard.basename.isEmpty
            && workflow.wizard.workingDirectory != nil
    }

    /// `menuProjectSaveAs` — no binding required.
    var canSaveAs: Bool {
        !workflow.wizard.basename.isEmpty
            && workflow.wizard.workingDirectory != nil
    }

    /// `menuProjectReport` — needs a real basename and cwd on disk.
    var canReport: Bool {
        !workflow.wizard.basename.isEmpty
            && workflow.wizard.workingDirectory != nil
    }

    private func liveSnapshot() -> Snapshot {
        Snapshot(
            basename: resolvedBasename ?? "",
            cwd: workflow.wizard.workingDirectory?.path ?? "",
            printerID: workflow.print.selectedPrinter.isEmpty
                ? nil : workflow.print.selectedPrinter,
            presetID: workflow.selectedPresetID == "none"
                ? nil : workflow.selectedPresetID,
            mediaRecipeID: workflow.media.selectedRecipeID == "none"
                ? nil : workflow.media.selectedRecipeID,
            calibrationURL: workflow.profile.calibrationFile.isEmpty
                ? nil : workflow.profile.calibrationFile)
    }

    private func snapshot(of project: ICCeryProject) -> Snapshot {
        Snapshot(
            basename: project.basename,
            cwd: project.cwd,
            printerID: project.printerID,
            presetID: project.presetID,
            mediaRecipeID: project.mediaRecipeID,
            calibrationURL: project.calibrationURL)
    }

    /// Recomputes the window title from live fields.
    func recomputeDerived() {
        if let project {
            windowTitle = "ICCery — \(project.name)" + (isDirty ? " •" : "")
        } else {
            windowTitle = "ICCery"
        }
    }

    /// Defer the recompute one main turn — the Combine sinks fire on
    /// willSet, before the changed property holds its new value.
    private func scheduleRecompute() {
        Task { @MainActor [weak self] in self?.recomputeDerived() }
    }

    // MARK: - New

    /// ⌘N / `menuProjectNew`. Dirty sessions detour through the dirty
    /// alert first; a live child gets a banner instead of the alert.
    func requestNew() {
        guard !childSessionLive else {
            workflow.wizard.showNotice(
                "Finish the instrument session before starting a project.",
                kind: .warning)
            return
        }
        if isDirty {
            pendingAction = .new
            showingDirtyAlert = true
            return
        }
        showingNewAlert = true
    }

    /// `btnProjectNewConfirm` — unbinds and clears the basename. Empty
    /// is the legal "no target yet" state (#60); artefacts and
    /// `media_library.json` are never deleted (R18).
    func confirmNew() {
        showingNewAlert = false
        projectURL = nil
        project = nil
        pendingRelocate = nil
        diskBehindNotes = false
        workflow.wizard.basename = ""
        workflow.targetBasename = ""
        workflow.media.selectedRecipeID = "none"
        workflow.wizard.sessionMode = .profile
        // Re-probe — an empty basename locks stages 2–5.
        workflow.wizard.windowDidBecomeKey()
        recomputeDerived()
    }

    // MARK: - Open

    /// ⌘O / `btnProjectOpen` — `selectProjectFile` (`.icceryproj`
    /// only). Cancel is a no-op.
    func requestOpen() {
        guard !childSessionLive else {
            workflow.wizard.showNotice(
                "Finish the instrument session before opening a project.",
                kind: .warning)
            return
        }
        let url = UITestHooks.isEnabled
            ? UITestHooks.projectOpenURL
            : fileDialogs.selectProjectFile()
        guard let url else { return }
        if isDirty {
            pendingAction = .open(url)
            showingDirtyAlert = true
            return
        }
        open(url)
    }

    /// Open from the recents submenu — same path, no open panel. A
    /// missing file is dropped with a banner; no relocate is offered.
    func openRecent(_ entry: RecentProjectEntry) {
        guard !childSessionLive else {
            workflow.wizard.showNotice(
                "Finish the instrument session before opening a project.",
                kind: .warning)
            return
        }
        let url = URL(fileURLWithPath: entry.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Task { try? await recentsStore.remove(path: entry.path) }
            refreshRecents()
            workflow.wizard.showNotice("Project file is gone.", kind: .warning)
            return
        }
        if isDirty {
            pendingAction = .open(url)
            showingDirtyAlert = true
            return
        }
        open(url)
    }

    /// Shared open path — validates, routes to relocate when `cwd` is
    /// gone, then applies. Failures leave live state untouched.
    func open(_ url: URL) {
        guard let loaded = loadProject(url) else { return }
        apply(loaded, from: url)
    }

    /// Awaitable open for tests — identical to `open` but completes
    /// after apply finishes.
    func openAsync(_ url: URL) async {
        guard let loaded = loadProject(url) else { return }
        await applyAsync(loaded, from: url)
    }

    /// Decode + validate + cwd-existence check. Returns the project
    /// ready to apply, or nil after presenting an error banner / the
    /// relocate sheet.
    private func loadProject(_ url: URL) -> ICCeryProject? {
        let loaded: ICCeryProject
        do {
            loaded = try ICCeryProject.load(from: url)
        } catch let error as ICCeryProject.ValidationError {
            workflow.wizard.showNotice(
                error.errorDescription ?? "Could not open project.",
                kind: .error)
            return nil
        } catch {
            workflow.wizard.showNotice(
                "Could not open project: \(error.localizedDescription)",
                kind: .error)
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: loaded.cwd, isDirectory: &isDir), isDir.boolValue
        else {
            pendingRelocate = (loaded, url)
            showingRelocateSheet = true
            return nil
        }
        return loaded
    }

    /// Sync entry — the apply half runs in a Task so `media.apply`
    /// (async) can run inside it.
    private func apply(_ project: ICCeryProject, from url: URL) {
        Task { @MainActor [weak self] in
            await self?.applyAsync(project, from: url)
        }
    }

    /// Apply order (issue #149):
    /// 1. cwd + basename on the wizard **and** Stage 1 fields.
    /// 2. `mediaRecipeID` → `MediaLibraryViewModel.apply`; else
    ///    `presetID` → existing preset apply. Missing recipe is not
    ///    fatal — open still succeeds.
    /// 3. Re-probe via the existing window-focus path (#151).
    /// 4. Never auto-run `targen` / `colprof` / `chartread`.
    private func applyAsync(_ project: ICCeryProject, from url: URL) async {
        let cwdURL = URL(fileURLWithPath: project.cwd, isDirectory: true)

        workflow.wizard.setTarget(
            basename: project.basename, workingDirectory: cwdURL)
        workflow.targetBasename = project.basename
        workflow.targetDirectory = cwdURL
        workflow.wizard.printerName = project.printerDisplayName
            ?? project.printerID
        workflow.wizard.profileBasename = project.profileBasename
        workflow.wizard.sessionMode = .profile
        if let queue = project.printerID,
           workflow.print.printers.contains(where: { $0.name == queue }) {
            workflow.print.selectedPrinter = queue
        }

        var appliedRecipe = false
        if let recipeID = project.mediaRecipeID {
            if workflow.media.recipes.isEmpty {
                await workflow.media.reloadAsync()
            }
            if let recipe = workflow.media.recipes
                .first(where: { $0.id == recipeID }) {
                appliedRecipe = await workflow.media.apply(recipe)
            }
        }
        if !appliedRecipe, let presetID = project.presetID,
           let preset = workflow.presets
               .first(where: { $0.id == presetID }) {
            workflow.applyPreset(preset)
        }

        // Disk owns the stepper — same probe window focus uses.
        workflow.wizard.windowDidBecomeKey()

        // JSON-vs-disk mismatch: notes say the profile is done but the
        // artefacts stop earlier — index drift, not gating truth.
        let artefacts = workflow.wizard.artefacts
        if project.lastVerification != nil && !artefacts.stage4Complete {
            let already = diskBehindNotes && projectURL == url
            diskBehindNotes = true
            if !already {
                let last = artefacts.stage3Complete ? ".ti3"
                    : artefacts.stage2Complete ? ".ti2"
                    : artefacts.stage1Complete ? ".ti1" : nil
                let detail = last.map { "artefacts on disk stop at \($0)." }
                    ?? "no artefacts found on disk."
                workflow.wizard.showNotice(
                    "Project notes say profile done; \(detail)",
                    kind: .info)
            }
        } else {
            diskBehindNotes = false
        }

        self.project = project
        projectURL = url
        pushRecent(url: url, name: project.name)
        recomputeDerived()
    }

    // MARK: - Relocate

    /// `btnProjectRelocate` — pick a new cwd, rewrite the project file
    /// atomically, then continue Apply.
    func chooseRelocateFolder() {
        guard let pending = pendingRelocate else { return }
        let url = UITestHooks.isEnabled
            ? UITestHooks.projectRelocateURL
            : fileDialogs.selectDirectory()
        guard let url else { return }
        var rewritten = pending.project
        rewritten.cwd = url.path
        rewritten.updated = Date()
        do {
            try rewritten.save(to: pending.url)
        } catch {
            workflow.wizard.showNotice(
                "Could not update project: \(error.localizedDescription)",
                kind: .error)
            return
        }
        pendingRelocate = nil
        showingRelocateSheet = false
        apply(rewritten, from: pending.url)
    }

    /// `btnProjectRelocateCancel` — aborts the open; live session
    /// unchanged.
    func cancelRelocate() {
        pendingRelocate = nil
        showingRelocateSheet = false
    }

    // MARK: - Save / Save As

    /// ⌘S / `btnProjectSave` — writes the live session into the bound
    /// URL. A live `CAL_` stem refuses unless the persisted original
    /// resolves; `CAL_` is never persisted (R11).
    func saveProject() {
        Task { @MainActor in _ = await saveProjectAsync() }
    }

    @discardableResult
    func saveProjectAsync() async -> Bool {
        guard let url = projectURL, project != nil else { return false }
        guard let basename = resolvedBasename else {
            refuseUnsavable()
            return false
        }
        return await write(to: url, basename: basename)
    }

    /// ⇧⌘S / `menuProjectSaveAs` — always shows the save picker, then
    /// binds the chosen URL and pushes recents.
    func saveProjectAs() {
        guard let basename = resolvedBasename else {
            refuseUnsavable()
            return
        }
        guard let cwd = workflow.wizard.workingDirectory else {
            refuseUnsavable()
            return
        }
        let url = UITestHooks.isEnabled
            ? UITestHooks.projectSaveURL
            : fileDialogs.selectProjectSavePath(
                basename: basename, startingAt: cwd)
        guard let url else { return }
        Task { @MainActor in _ = await write(to: url, basename: basename) }
    }

    private func refuseUnsavable() {
        if CalibrationIdentity.isCalibration(workflow.wizard.basename) {
            workflow.wizard.showNotice(
                "Finish or exit calibration before saving a project.",
                kind: .warning)
        } else {
            workflow.wizard.showNotice(
                "Set a target basename and working folder before saving a project.",
                kind: .warning)
        }
    }

    /// Builds the project payload from live session fields and writes
    /// it atomically. On success binds `url`, refreshes recents, and
    /// clears the stale-chip flag. Failure → error banner, bound URL
    /// unchanged.
    @discardableResult
    private func write(to url: URL, basename: String) async -> Bool {
        guard let cwd = workflow.wizard.workingDirectory,
              !cwd.path.isEmpty else {
            refuseUnsavable()
            return false
        }
        let stem = workflow.wizard.profileBasename ?? basename
        let snapshot = await lastVerificationSnapshot(stem: stem)
            ?? project?.lastVerification
        let queue = workflow.print.selectedPrinter
        let display = workflow.print.printers
            .first { $0.name == queue }?.displayName
            ?? workflow.wizard.printerName
        let existing = project
        let name = (existing?.name.isEmpty == false)
            ? existing!.name : basename
        let updated = ICCeryProject(
            name: name,
            notes: existing?.notes ?? "",
            basename: basename,
            cwd: cwd.path,
            profileBasename: workflow.wizard.profileBasename,
            printerID: queue.isEmpty ? nil : queue,
            printerDisplayName: display,
            mediaRecipeID: workflow.media.selectedRecipeID == "none"
                ? nil : workflow.media.selectedRecipeID,
            presetID: workflow.selectedPresetID == "none"
                ? nil : workflow.selectedPresetID,
            calibrationURL: workflow.profile.calibrationFile.isEmpty
                ? nil : workflow.profile.calibrationFile,
            lastVerification: snapshot,
            updated: Date())
        do {
            try updated.save(to: url)
        } catch {
            workflow.wizard.showNotice(
                "Could not save project: \(error.localizedDescription)",
                kind: .error)
            return false
        }
        project = updated
        projectURL = url
        diskBehindNotes = false
        pushRecent(url: url, name: updated.name)
        workflow.wizard.showNotice("Project saved: \(url.lastPathComponent)")
        recomputeDerived()
        return true
    }

    /// Last `VerificationHistoryStore` record for this profile stem,
    /// if any — notes only.
    private func lastVerificationSnapshot(
        stem: String
    ) async -> VerificationSnapshot? {
        guard let records = try? await environment.historyStore.load()
        else { return nil }
        guard let record = records.last(where: {
            $0.profileName == stem || $0.profileName == workflow.wizard.basename
        }) else { return nil }
        return VerificationSnapshot(record: record)
    }

    // MARK: - Close

    /// `menuProjectClose` — unbinds; live basename/cwd/artefacts stay.
    func requestClose() {
        guard isBound else { return }
        if isDirty {
            pendingAction = .close
            showingDirtyAlert = true
            return
        }
        closeProject()
    }

    func closeProject() {
        projectURL = nil
        project = nil
        diskBehindNotes = false
        recomputeDerived()
    }

    // MARK: - Dirty alert

    /// `btnProjectDirtySave` / `btnProjectDirtyDiscard`. Save proceeds
    /// to the pending action only when the write succeeded.
    func resolveDirty(save: Bool) {
        showingDirtyAlert = false
        guard let action = pendingAction else { return }
        if save {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if await self.saveProjectAsync() {
                    self.pendingAction = nil
                    self.proceed(with: action)
                }
            }
        } else {
            pendingAction = nil
            proceed(with: action)
        }
    }

    /// `btnProjectDirtyCancel` — abandons the pending action.
    func cancelDirty() {
        pendingAction = nil
        showingDirtyAlert = false
    }

    private func proceed(with action: PendingAction) {
        switch action {
        case .new:
            confirmNew()
        case .open(let url):
            open(url)
        case .close:
            closeProject()
        }
    }

    // MARK: - Report

    /// `menuProjectReport` — writes `{cwd}/{basename}-report.md`
    /// atomically (generated; overwrites). No picker.
    func saveReport() {
        guard canReport, let cwd = workflow.wizard.workingDirectory else {
            return
        }
        let basename = workflow.wizard.basename
        Task { @MainActor [weak self] in
            guard let self else { return }
            let stem = self.workflow.wizard.profileBasename ?? basename
            let snapshot = await self.lastVerificationSnapshot(stem: stem)
                ?? self.project?.lastVerification
            let queue = self.workflow.print.selectedPrinter
            let display = self.workflow.print.printers
                .first { $0.name == queue }?.displayName
                ?? self.workflow.wizard.printerName
            let recipeName = self.workflow.media.recipes
                .first { $0.id == self.workflow.media.selectedRecipeID }?.name
            let payload = ICCeryProject(
                name: self.project?.name.isEmpty == false
                    ? self.project!.name : basename,
                notes: self.project?.notes ?? "",
                basename: basename,
                cwd: cwd.path,
                profileBasename: self.workflow.wizard.profileBasename,
                printerID: queue.isEmpty ? nil : queue,
                printerDisplayName: display,
                mediaRecipeID: self.workflow.media.selectedRecipeID == "none"
                    ? nil : self.workflow.media.selectedRecipeID,
                presetID: self.workflow.selectedPresetID == "none"
                    ? nil : self.workflow.selectedPresetID,
                calibrationURL: self.workflow.profile.calibrationFile.isEmpty
                    ? nil : self.workflow.profile.calibrationFile,
                lastVerification: snapshot,
                updated: Date())
            do {
                let written = try ProjectReport.write(
                    project: payload,
                    recipeName: recipeName,
                    artefacts: self.workflow.wizard.artefacts)
                self.workflow.wizard.showNotice(
                    "Wrote \(written.lastPathComponent)")
            } catch {
                self.workflow.wizard.showNotice(
                    "Report failed: \(error.localizedDescription)",
                    kind: .error)
            }
        }
    }

    // MARK: - Recents / reveal

    /// Rebuilds the recents list; entries whose file is gone are
    /// dropped here (submenu build), not at launch. Corrupt → `[]`,
    /// file kept (R12).
    func refreshRecents() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.recents = try await self.recentsStore.pruneMissing()
            } catch {
                self.recents = []
            }
        }
    }

    private func pushRecent(url: URL, name: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.recentsStore.add(url: url, name: name)
            self.refreshRecents()
        }
    }

    /// `menuProjectRecentsClear` — wipes `recent_projects.json` only;
    /// `.icceryproj` files are never deleted.
    func clearRecents() {
        Task { @MainActor [weak self] in
            try? await self?.recentsStore.clear()
            self?.recents = []
        }
    }

    /// `btnProjectReveal` — reveals the bound **project file** in
    /// Finder, not the cwd.
    func revealInFinder() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }
}
