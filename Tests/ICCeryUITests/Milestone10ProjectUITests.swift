import XCTest

/// Milestone 10 UI tests — issue #149 project file. Panels are never
/// real: `ICCERY_TEST_PROJECT_OPEN` / `ICCERY_TEST_PROJECT_SAVE`
/// inject fixture paths through `UITestHooks`. Menu commands are driven
/// through the File menu when it is in the AX tree, else by their
/// keyboard shortcuts (⌘N) — the tests do not depend on menu AX
/// exposure (R19). All queries by identifier.
@MainActor
final class Milestone10ProjectUITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui10p-\(UUID().uuidString)")
        workDir = testRoot.appendingPathComponent("WorkDir")
        binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bin")

        try FileManager.default.createDirectory(
            at: testRoot.appendingPathComponent("AppData"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: workDir, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchEnvironment = [
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_ROOT": testRoot.path,
            "ICCERY_ARGYLL_BINARY_DIR": binDir.path,
            "ICCERY_CUPS_BIN_DIR": binDir.path,
        ]
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
        testRoot = nil
        workDir = nil
    }

    private func launchApp() {
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 10) {
            app.activate()
        }
    }

    private func element(_ id: String) -> XCUIElement {
        let inApp = app.descendants(matching: .any)[id].firstMatch
        if inApp.exists { return inApp }
        return app.sheets.firstMatch.descendants(matching: .any)[id].firstMatch
    }

    private func waitFor(_ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let el = element(id)
            if el.exists { return el }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let el = element(id)
        XCTAssertTrue(el.exists, "Expected element \(id)")
        return el
    }

    private func noticeText(timeout: TimeInterval = 10) -> String {
        let el = waitFor("noticeText", timeout: timeout)
        return (el.value as? String) ?? el.label
    }

    /// Alert/sheet button by visible title, falling back to the a11y
    /// id; nil when neither matches. macOS 12 SwiftUI alerts often
    /// drop `accessibilityIdentifier` on their buttons, so the title
    /// is the reliable handle there.
    private func alertButton(title: String, id: String) -> XCUIElement? {
        let inDialog = app.dialogs.firstMatch.buttons[title].firstMatch
        if inDialog.exists { return inDialog }
        let inSheet = app.sheets.firstMatch.buttons[title].firstMatch
        if inSheet.exists { return inSheet }
        let byId = element(id)
        return byId.exists ? byId : nil
    }

    /// Fires File ▸ New Project via the menu when it is in the AX
    /// tree, else ⌘N. On macOS 12 `typeKey` may not reach the
    /// `CommandGroup`, and menu item ids are unreliable — the menu
    /// item is matched by its "New Project" label first.
    private func triggerNewProject() {
        let fileMenu = app.menuBarItems["File"]
        if fileMenu.waitForExistence(timeout: 5) {
            fileMenu.click()
            let byTitle = app.menuItems["New Project"].firstMatch
            let byId = app.menuItems["menuProjectNew"].firstMatch
            let item = byTitle.exists ? byTitle : byId
            if item.waitForExistence(timeout: 5) {
                item.click()
                return
            }
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
        app.typeKey("n", modifierFlags: .command)
    }

    /// Writes a `.icceryproj` fixture under `testRoot` and points the
    /// open-picker hook at it.
    private func stageProjectFixture(
        basename: String = "ui149job",
        lastVerification: Bool = false
    ) throws -> URL {
        let verification = lastVerification ? """
          "last_verification": {
            "date": "2026-09-12T00:00:00Z",
            "avg_de00": 0.7,
            "max_de00": 1.9,
            "status": "excellent",
            "profile_filename": "\(basename).icc"
          },
        """ : ""
        let json = """
        {
          "schema_version": 1,
          "name": "UI Fixture Project",
          "notes": "",
          "basename": "\(basename)",
          "cwd": "\(workDir.path)",
          "printer_id": null,
          "media_recipe_id": null,
          "preset_id": null,
          "calibration_url": null,
          \(verification)
          "updated": "2026-09-13T00:00:00Z"
        }
        """
        let url = testRoot.appendingPathComponent("fixture.icceryproj")
        try json.write(to: url, atomically: true, encoding: .utf8)
        app.launchEnvironment["ICCERY_TEST_PROJECT_OPEN"] = url.path
        return url
    }

    private func artefact(_ ext: String, stem: String = "ui149job") throws {
        try "x".write(
            to: workDir.appendingPathComponent("\(stem).\(ext)"),
            atomically: true, encoding: .utf8)
    }

    // MARK: - Tests

    func testNewProjectClearsBasenameDoesNotDeleteFixtureTi3() throws {
        try artefact("ti3")
        _ = try stageProjectFixture()
        launchApp()

        // Open the fixture via the chip — never a real panel.
        waitFor("btnProjectOpen").click()
        _ = waitFor("projectChipPath")
        let basenameField = app.textFields["targetBasename"]
        XCTAssertTrue(basenameField.waitForExistence(timeout: 10))
        XCTAssertEqual(basenameField.value as? String, "ui149job")

        // File ▸ New Project when the menu is in the AX tree, else
        // ⌘N. Mock CUPS may have enumerated a queue that the fixture
        // does not record, making the session dirty — in that case
        // the dirty alert gates New first. macOS 12 alerts often lack
        // button identifiers, so confirm by title with id fallback.
        triggerNewProject()
        let deadline = Date().addingTimeInterval(10)
        var confirmed = false
        while Date() < deadline {
            // Dirty sessions show the dirty alert first; discarding it
            // runs the New reset directly (no second confirm).
            if let discard = alertButton(
                title: "Don't Save", id: "btnProjectDirtyDiscard") {
                discard.click()
                confirmed = true
                break
            }
            if let start = alertButton(
                title: "Start", id: "btnProjectNewConfirm") {
                start.click()
                confirmed = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(confirmed, "expected the New or dirty alert")

        // Basename cleared (legal "no target" state — not a
        // placeholder), fixture `.ti3` untouched on disk.
        let cleared = basenameField.value as? String ?? ""
        XCTAssertEqual(cleared, "")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: workDir.appendingPathComponent("ui149job.ti3").path))
        XCTAssertTrue(element("projectChip").exists)
        XCTAssertEqual(
            element("projectChipName").value as? String, "No project")
    }

    func testOpenProjectDiskWinsOverJsonStage() throws {
        // JSON claims a finished profile; disk stops at .ti2 (R18).
        try artefact("ti2")
        _ = try stageProjectFixture(lastVerification: true)
        launchApp()

        waitFor("btnProjectOpen").click()

        let notice = noticeText()
        XCTAssertTrue(
            notice.contains("artefacts on disk stop at .ti2"),
            "got: \(notice)")
        XCTAssertTrue(element("projectChipStale").exists)
        XCTAssertEqual(
            element("projectChipPath").value as? String, workDir.lastPathComponent)
    }

    func testSaveDisabledWithoutBasename() throws {
        launchApp()

        _ = waitFor("projectChip")
        XCTAssertEqual(element("projectChipName").value as? String, "No project")
        // Chip Save is hidden while unbound; Save As lives in the menu.
        XCTAssertFalse(element("btnProjectSave").exists)

        // When the File menu is in the AX tree, Save must be disabled.
        let fileMenu = app.menuBarItems["File"]
        if fileMenu.waitForExistence(timeout: 3) {
            fileMenu.click()
            let save = app.menuItems["menuProjectSave"].firstMatch
            if save.waitForExistence(timeout: 3) {
                XCTAssertFalse(save.isEnabled)
            }
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
    }

    func testCalBasenameRefused() throws {
        // A fixture whose stem is CAL_-prefixed binds a live CAL_
        // basename; the persisted original is empty, so Save must
        // refuse and never write CAL_ back (R11).
        let url = try stageProjectFixture(basename: "CAL_ui149")
        let before = try Data(contentsOf: url)
        launchApp()

        waitFor("btnProjectOpen").click()
        let save = waitFor("btnProjectSave")
        XCTAssertTrue(save.isEnabled)
        save.click()

        XCTAssertTrue(
            noticeText().contains("Finish or exit calibration"),
            "got: \(noticeText())")
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
}
