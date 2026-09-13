import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue #149 — `ProjectSession` open/save/new/close against an
/// isolated `TestAppEnvironment`. Disk artefacts always win over the
/// project JSON (R18); a `CAL_` basename is never persisted (R11).
@MainActor
final class ProjectSessionTests: XCTestCase {

    private var env: TestAppEnvironment!
    private var workflow: TargetWorkflowViewModel!
    private var project: ProjectSession!
    private var cwd: URL!

    override func setUp() async throws {
        env = try TestAppEnvironment.make()
        workflow = TargetWorkflowViewModel(environment: env.environment)
        project = workflow.project
        cwd = env.root.appendingPathComponent("proj-cwd")
        try FileManager.default.createDirectory(
            at: cwd, withIntermediateDirectories: true)
        // Recents are pushed asynchronously; drain before asserting.
        await flush()
    }

    override func tearDown() async throws {
        env?.cleanup()
        env = nil
        workflow = nil
        project = nil
        cwd = nil
    }

    /// Lets pending `Task`s in the view models run.
    private func flush() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    private func artefact(_ ext: String, stem: String = "job") throws {
        try "x".write(
            to: cwd.appendingPathComponent("\(stem).\(ext)"),
            atomically: true, encoding: .utf8)
    }

    private func writeProjectFile(
        _ name: String = "job.icceryproj",
        basename: String = "job",
        cwdOverride: String? = nil,
        lastVerification: Bool = false,
        mediaRecipeID: String? = nil,
        presetID: String? = nil
    ) throws -> URL {
        let snapshot: VerificationSnapshot? = lastVerification
            ? VerificationSnapshot(
                date: Date(), avgDE00: 0.7, maxDE00: 1.9,
                status: "excellent", profileFilename: "\(basename).icc")
            : nil
        let p = ICCeryProject(
            name: "Fixture Project",
            basename: basename,
            cwd: cwdOverride ?? cwd.path,
            mediaRecipeID: mediaRecipeID,
            presetID: presetID,
            lastVerification: snapshot)
        let url = env.root.appendingPathComponent(name)
        try p.save(to: url)
        return url
    }

    // MARK: - Open

    func testOpenAppliesBasenameCwdAndBinds() async throws {
        try artefact("ti1")
        try artefact("ti2")
        try artefact("ti3")
        let url = try writeProjectFile()

        await project.openAsync(url)

        XCTAssertEqual(workflow.wizard.basename, "job")
        XCTAssertEqual(workflow.wizard.workingDirectory?.path, cwd.path)
        XCTAssertEqual(workflow.targetBasename, "job")
        XCTAssertEqual(workflow.targetDirectory?.path, cwd.path)
        XCTAssertEqual(project.projectURL, url)
        XCTAssertEqual(project.project?.name, "Fixture Project")
        XCTAssertEqual(project.windowTitle, "ICCery — Fixture Project")
        XCTAssertFalse(project.isDirty)
        XCTAssertTrue(workflow.wizard.isUnlocked(.buildProfile))
        XCTAssertFalse(workflow.wizard.isUnlocked(.verifyInstall))
    }

    func testOpenDiskWinsOverJsonStage() async throws {
        // JSON claims a finished profile; disk only has .ti2 (R18).
        try artefact("ti2")
        let url = try writeProjectFile(lastVerification: true)

        await project.openAsync(url)

        XCTAssertFalse(workflow.wizard.isUnlocked(.buildProfile))
        XCTAssertFalse(workflow.wizard.isUnlocked(.verifyInstall))
        XCTAssertTrue(project.diskBehindNotes)
        let notice = workflow.wizard.notice
        XCTAssertEqual(notice?.kind, .info)
        XCTAssertTrue(
            notice?.text.contains("artefacts on disk stop at .ti2") == true,
            "got: \(notice?.text ?? "nil")")
    }

    func testOpenWithTi3ButNoIccLocksStage5Only() async throws {
        try artefact("ti3")
        let url = try writeProjectFile(lastVerification: true)

        await project.openAsync(url)

        XCTAssertTrue(workflow.wizard.isUnlocked(.buildProfile))
        XCTAssertFalse(workflow.wizard.isUnlocked(.verifyInstall))
        XCTAssertTrue(project.diskBehindNotes)
    }

    func testOpenSchema2LeavesLiveStateUntouched() async throws {
        workflow.wizard.setTarget(basename: "live", workingDirectory: cwd)
        let url = env.root.appendingPathComponent("v2.icceryproj")
        try """
        {"schema_version": 2, "basename": "other", "cwd": "\(cwd.path)"}
        """.write(to: url, atomically: true, encoding: .utf8)

        await project.openAsync(url)

        XCTAssertNil(project.projectURL)
        XCTAssertEqual(workflow.wizard.basename, "live")
        XCTAssertEqual(workflow.wizard.notice?.kind, .error)
        XCTAssertTrue(
            workflow.wizard.notice?.text.contains("not schema 1") == true)
    }

    func testOpenMissingCwdPresentsRelocateSheet() async throws {
        let gone = env.root.appendingPathComponent("no-such-dir").path
        let url = try writeProjectFile(cwdOverride: gone)
        workflow.wizard.setTarget(basename: "live", workingDirectory: cwd)

        await project.openAsync(url)

        XCTAssertTrue(project.showingRelocateSheet)
        XCTAssertNotNil(project.pendingRelocate)
        XCTAssertNil(project.projectURL)
        XCTAssertEqual(workflow.wizard.basename, "live")
    }

    func testRelocateCancelAbortsOpen() async throws {
        let gone = env.root.appendingPathComponent("no-such-dir").path
        let url = try writeProjectFile(cwdOverride: gone)

        await project.openAsync(url)
        project.cancelRelocate()

        XCTAssertFalse(project.showingRelocateSheet)
        XCTAssertNil(project.projectURL)
    }

    func testOpenUnknownMediaRecipeStillOpens() async throws {
        let url = try writeProjectFile(mediaRecipeID: "recipe-absent")

        await project.openAsync(url)
        await flush()

        XCTAssertEqual(project.projectURL, url)
        XCTAssertEqual(workflow.wizard.basename, "job")
        // The unknown recipe was ignored, not fatal.
        XCTAssertEqual(workflow.media.selectedRecipeID, "none")
    }

    func testOpenAppliesPresetWhenNoRecipe() async throws {
        let url = try writeProjectFile(presetID: "preset-std-rgb")

        await project.openAsync(url)
        await flush()

        XCTAssertEqual(workflow.selectedPresetID, "preset-std-rgb")
    }

    // MARK: - Save

    func testSaveRefusesEmptyBasename() async throws {
        let url = try writeProjectFile()
        await project.openAsync(url)
        await flush()
        workflow.wizard.basename = ""

        XCTAssertFalse(project.canSave)
        let saved = await project.saveProjectAsync()
        XCTAssertFalse(saved)
        // The file keeps its original basename.
        let reloaded = try ICCeryProject.load(from: url)
        XCTAssertEqual(reloaded.basename, "job")
    }

    func testSaveRefusesEmptyCwd() async throws {
        let url = try writeProjectFile()
        await project.openAsync(url)
        await flush()
        workflow.wizard.workingDirectory = nil

        XCTAssertFalse(project.canSave)
        let saved = await project.saveProjectAsync()
        XCTAssertFalse(saved)
    }

    func testCalBasenameRefusedWithoutPersistedOriginal() async throws {
        let url = try writeProjectFile()
        await project.openAsync(url)
        await flush()
        // Bare CAL_ stem — no persisted original to trust (R11).
        workflow.wizard.basename = "CAL_job"
        workflow.wizard.calibrationOriginalBasename = ""

        XCTAssertTrue(project.canSave)  // enabled so the banner shows
        let saved = await project.saveProjectAsync()

        XCTAssertFalse(saved)
        XCTAssertTrue(
            workflow.wizard.notice?.text.contains(
                "Finish or exit calibration") == true)
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(raw.contains("CAL_"))
        XCTAssertEqual(try ICCeryProject.load(from: url).basename, "job")
    }

    func testCalBasenameSavesPersistedOriginal() async throws {
        let url = try writeProjectFile()
        await project.openAsync(url)
        await flush()
        workflow.wizard.basename = "CAL_job"
        workflow.wizard.calibrationOriginalBasename = "job"

        let saved = await project.saveProjectAsync()

        XCTAssertTrue(saved)
        let reloaded = try ICCeryProject.load(from: url)
        XCTAssertEqual(reloaded.basename, "job")
        XCTAssertFalse(rawContainsCal(url))
    }

    private func rawContainsCal(_ url: URL) -> Bool {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return raw.contains("CAL_")
    }

    func testSaveCapturesLiveFields() async throws {
        let url = try writeProjectFile()
        await project.openAsync(url)
        await flush()
        workflow.print.printers = [
            Printer(name: "Mock_Queue", displayName: "Mock Queue Display")
        ]
        workflow.print.selectedPrinter = "Mock_Queue"
        workflow.selectedPresetID = "preset-std-rgb"
        workflow.profile.calibrationFile = "/tmp/live.cal"

        XCTAssertTrue(project.isDirty)
        await flush()  // title recompute is deferred one main turn
        XCTAssertTrue(project.windowTitle.hasSuffix("•"))

        let saved = await project.saveProjectAsync()
        XCTAssertTrue(saved)
        let reloaded = try ICCeryProject.load(from: url)
        XCTAssertEqual(reloaded.printerID, "Mock_Queue")
        XCTAssertEqual(
            reloaded.printerDisplayName, "Mock Queue Display")
        XCTAssertEqual(reloaded.presetID, "preset-std-rgb")
        XCTAssertEqual(reloaded.calibrationURL, "/tmp/live.cal")
        XCTAssertFalse(project.isDirty)
    }

    // MARK: - New / Close

    func testNewClearsBasenameKeepsArtefacts() async throws {
        try artefact("ti3")
        let url = try writeProjectFile()
        await project.openAsync(url)
        await flush()
        XCTAssertTrue(workflow.wizard.isUnlocked(.buildProfile))

        project.requestNew()
        XCTAssertTrue(project.showingNewAlert)
        project.confirmNew()

        XCTAssertEqual(workflow.wizard.basename, "")
        XCTAssertEqual(workflow.targetBasename, "")
        XCTAssertNil(project.projectURL)
        XCTAssertEqual(project.windowTitle, "ICCery")
        XCTAssertEqual(workflow.media.selectedRecipeID, "none")
        XCTAssertEqual(workflow.wizard.sessionMode, .profile)
        // The artefact is untouched; the stepper just can't see it.
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: cwd.appendingPathComponent("job.ti3").path))
        XCTAssertFalse(workflow.wizard.isUnlocked(.buildProfile))
    }

    func testNewWhileChildLiveBannersInstead() async throws {
        workflow.measurement.isChartreadRunning = true
        project.requestNew()
        XCTAssertFalse(project.showingNewAlert)
        XCTAssertNotNil(workflow.wizard.notice)
    }

    func testDirtyNewShowsDirtyAlert() async throws {
        let url = try writeProjectFile()
        await project.openAsync(url)
        await flush()
        workflow.wizard.basename = "changed"

        project.requestNew()
        XCTAssertFalse(project.showingNewAlert)
        XCTAssertTrue(project.showingDirtyAlert)

        // Don't Save → New proceeds.
        project.resolveDirty(save: false)
        XCTAssertEqual(workflow.wizard.basename, "")
        XCTAssertNil(project.projectURL)
    }

    func testCloseKeepsLiveSession() async throws {
        try artefact("ti1")
        let url = try writeProjectFile()
        await project.openAsync(url)
        await flush()

        project.requestClose()

        XCTAssertNil(project.projectURL)
        XCTAssertEqual(workflow.wizard.basename, "job")
        XCTAssertEqual(workflow.wizard.workingDirectory?.path, cwd.path)
        XCTAssertEqual(project.windowTitle, "ICCery")
    }

    func testDirtyCloseSaveThenCloses() async throws {
        let url = try writeProjectFile()
        await project.openAsync(url)
        await flush()
        workflow.wizard.basename = "renamed"

        project.requestClose()
        XCTAssertTrue(project.showingDirtyAlert)

        project.resolveDirty(save: true)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(project.projectURL)
        XCTAssertEqual(try ICCeryProject.load(from: url).basename,
                       "renamed")
    }

    // MARK: - Report / recents

    func testSaveReportWritesMarkdown() async throws {
        try artefact("ti1")
        try artefact("ti3")
        let url = try writeProjectFile(lastVerification: true)
        await project.openAsync(url)
        await flush()

        project.saveReport()
        try await Task.sleep(nanoseconds: 300_000_000)

        let report = cwd.appendingPathComponent("job-report.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.path))
        let text = try String(contentsOf: report, encoding: .utf8)
        XCTAssertTrue(text.contains("job.ti1 | exists"))
        XCTAssertTrue(text.contains("job.ti2 | missing"))
        XCTAssertTrue(text.contains("job.ti3 | exists"))
        XCTAssertTrue(text.contains("avg ΔE₀₀ 0.70"))
        XCTAssertTrue(
            workflow.wizard.notice?.text.contains("job-report.md") == true)
    }

    func testOpenPushesRecent() async throws {
        let url = try writeProjectFile()
        await project.openAsync(url)
        try await Task.sleep(nanoseconds: 300_000_000)

        let recents = project.recents
        XCTAssertEqual(recents.first?.path, url.path)
        XCTAssertEqual(recents.first?.name, "Fixture Project")
    }

    func testOpenRecentMissingFileDropped() async throws {
        let store = env.environment.recentProjectsStore
        let ghost = env.root.appendingPathComponent("ghost.icceryproj")
        try await store.add(url: ghost, name: "Ghost")

        project.openRecent(
            RecentProjectEntry(name: "Ghost", path: ghost.path))
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(
            workflow.wizard.notice?.text.contains("gone") == true)
        let loaded = try await store.load()
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertNil(project.projectURL)
    }
}
