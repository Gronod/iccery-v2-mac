import XCTest

/// Milestone 2 UI tests — issues #7–#11 (docs/21 element contract).
/// Every test launches the app with an isolated `ICCERY_TEST_ROOT`,
/// fixture sidecars via `ICCERY_ARGYLL_BINARY_DIR`, and
/// `ICCERY_UI_TESTING=1` so file dialogs resolve to env-provided
/// paths instead of modal panels. No hardware, no network, no real
/// Argyll install, and nothing is written to the developer's app data.
@MainActor
final class Milestone2UITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        // The xctrunner sandbox only permits writes inside its own
        // container — the work dir lives there (the app can read/write
        // it). Executable fixtures, however, must live outside the
        // container or the app-under-test cannot posix_spawn them, so
        // `bin` points at the committed Fixtures/bin scripts in the
        // repo checkout (resolved via #filePath).
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui-\(UUID().uuidString)")
        binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/ICCeryUITests
            .appendingPathComponent("Fixtures/bin")
        workDir = testRoot.appendingPathComponent("work")
        try FileManager.default.createDirectory(
            at: workDir, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchEnvironment = [
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_ROOT": testRoot.path,
            "ICCERY_ARGYLL_BINARY_DIR": binDir.path,
            "ICCERY_TEST_SAVE_TARGET":
                workDir.appendingPathComponent("mytarget.ti1").path,
            "ICCERY_TEST_WORKDIR": workDir.path,
        ]
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
        testRoot = nil
    }

    /// Force the fixture printtarg to exit with `code`.
    private func failPrinttarg(exitCode: Int) {
        app.launchEnvironment["ICCERY_MOCK_PRINTTARG_EXIT"] = "\(exitCode)"
    }

    /// Launch and bring the app to the front — other app windows
    /// (the IDE, notification banners) covering the test window count
    /// as "interrupting elements" and stall synthesized clicks.
    private func launchApp() {
        app.launch()
        app.activate()
    }

    /// Sheet content on macOS lives under `app.sheets`, outside the
    /// main window's descendant tree — probe both scopes.
    private func element(_ id: String) -> XCUIElement {
        let inApp = app.descendants(matching: .any)[id]
        if inApp.exists { return inApp }
        return app.sheets.firstMatch.descendants(matching: .any)[id]
    }

    private func waitFor(_ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        // Poll both scopes so sheet-hosted elements resolve too.
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

    private func staticText(_ exact: String) -> XCUIElement {
        let inApp = app.staticTexts[exact]
        if inApp.exists { return inApp }
        return app.sheets.firstMatch.staticTexts[exact]
    }

    private func buttonsMatching(_ predicateFormat: String) -> XCUIElementQuery {
        let pred = NSPredicate(format: predicateFormat)
        let inApp = app.buttons.matching(pred)
        if inApp.count > 0 { return inApp }
        return app.sheets.firstMatch.buttons.matching(pred)
    }

    // MARK: - Tests

    /// Stage 1 opens with the Standard 800-patch default; Generate stays
    /// disabled until basename + cwd are valid (issue #7).
    func testStage1DefaultsAndGenerateGate() throws {
        launchApp()
        XCTAssertTrue(waitFor("btnGenerate").exists)
        XCTAssertTrue(element("patchCountPreset").exists)
        XCTAssertTrue(element("targetBasename").exists)
        XCTAssertTrue(element("btnOpenExisting").exists)
        XCTAssertFalse(app.buttons["btnGenerate"].isEnabled)

        // Browse fills basename + working dir via the test hook.
        app.buttons["btnBrowse"].click()
        XCTAssertTrue(app.buttons["btnGenerate"].isEnabled)
    }

    /// RGB/CMYK + advanced controls expose the documented identifiers
    /// and the ink-limit group is hidden for RGB (issue #7).
    func testStage1AdvancedVisibility() throws {
        launchApp()
        XCTAssertTrue(waitFor("targenAdvancedDetails").exists)
        // RGB default: ink-limit group must not exist.
        XCTAssertFalse(element("targenInkLimitGroup").exists)
        // The ink-limit group lives inside the Advanced disclosure —
        // pre-expanded under UI testing (XCUI can't toggle a macOS
        // DisclosureTriangle reliably). Switch the picker to CMYK.
        XCTAssertTrue(element("targenAdvancedDetails").exists)
        let cmyk = app.radioGroups["colourSpace"]
            .radioButtons["CMYK (RIP output)"]
        XCTAssertTrue(cmyk.waitForExistence(timeout: 5))
        cmyk.click()
        XCTAssertTrue(element("targenInkLimitGroup").waitForExistence(timeout: 5))
    }

    /// Stage 1/2 process-log containers resolve under the shared
    /// `ProcessLogView` identifiers (issue #80).
    func testProcessLogContainersResolve() throws {
        launchApp()
        XCTAssertTrue(waitFor("targenLogContainer").exists)

        app.buttons["btnBrowse"].click()
        app.buttons["btnGenerate"].click()
        XCTAssertTrue(waitFor("btnCreateLayout", timeout: 20).exists)
        XCTAssertTrue(element("printtargLogContainer").exists)
    }

    /// Fixture-backed targen run creates .ti1 and unlocks Stage 2.
    func testTargenFixtureUnlocksStage2() throws {
        launchApp()
        app.buttons["btnBrowse"].click()
        app.buttons["btnGenerate"].click()
        XCTAssertTrue(waitFor("btnCreateLayout", timeout: 20).exists)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: workDir.appendingPathComponent("mytarget.ti1").path))
    }

    /// Fixture printtarg → .ti2, gallery page renders, print controls
    /// stay disabled, Stage 3 advance becomes available (issues #9/#10).
    func testPrinttargFixtureGalleryAndStubbedPrint() throws {
        launchApp()

        app.buttons["btnBrowse"].click()
        app.buttons["btnGenerate"].click()
        XCTAssertTrue(waitFor("btnCreateLayout", timeout: 20).exists)

        // Colour-management warning is always present on Stage 2.
        XCTAssertTrue(element("cmWarningBanner").exists)
        XCTAssertTrue(element("instrumentSelect").exists)
        XCTAssertTrue(element("pageSizeSelect").exists)
        XCTAssertTrue(element("tiffDpi").exists)
        XCTAssertTrue(element("targetLabelPreview").exists)

        app.buttons["btnCreateLayout"].click()
        XCTAssertTrue(waitFor("galleryPage-0", timeout: 20).exists)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: workDir.appendingPathComponent("mytarget.ti2").path))

        // Print panel is live from M3; a default printer is selected
        // so both the all-pages and per-page print buttons are enabled.
        XCTAssertTrue(element("rawPrintPanel").exists)
        XCTAssertTrue(app.buttons["btnPrintAll"].isEnabled)
        XCTAssertTrue(app.buttons["btnPrintPage-0"].isEnabled)
        XCTAssertTrue(app.buttons["btnAdvanceToStage3"].isEnabled)
    }

    /// A failed printtarg run stays on Stage 2 (non-zero exit, #156).
    func testPrinttargFailureStaysOnStage2() throws {
        failPrinttarg(exitCode: 3)
        launchApp()
        app.buttons["btnBrowse"].click()
        app.buttons["btnGenerate"].click()
        XCTAssertTrue(waitFor("btnCreateLayout", timeout: 20).exists)

        app.buttons["btnCreateLayout"].click()
        // The notice banner reports the failure and we never advance:
        // btnCreateLayout is still the stage's action, and no gallery
        // appears.
        let failureText = element("noticeText")
        XCTAssertTrue(failureText.waitForExistence(timeout: 20))
        XCTAssertTrue((failureText.value as? String ?? "")
            .contains("printtarg failed"))
        XCTAssertTrue(element("btnCreateLayout").exists)
        XCTAssertFalse(element("galleryPage-0").exists)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: workDir.appendingPathComponent("mytarget.ti2").path))
    }

    /// Resume: .ti1 jumps to Stage 2 (issue #8).
    func testResumeTi1() throws {
        FileManager.default.createFile(
            atPath: workDir.appendingPathComponent("old.ti1").path,
            contents: Data("CGATS".utf8))
        app.launchEnvironment["ICCERY_TEST_EXISTING_TARGET"] =
            workDir.appendingPathComponent("old.ti1").path
        launchApp()
        app.buttons["btnOpenExisting"].click()
        XCTAssertTrue(waitFor("btnCreateLayout", timeout: 10).exists)
    }

    /// Resume: .ti2 with sibling .ti1 reaches the Stage 3 shell and
    /// shows the persisted "Resumed from .ti2" state (issue #8).
    func testResumeTi2ShowsStage3AndNotice() throws {
        FileManager.default.createFile(
            atPath: workDir.appendingPathComponent("old.ti1").path,
            contents: Data("CGATS".utf8))
        FileManager.default.createFile(
            atPath: workDir.appendingPathComponent("old.ti2").path,
            contents: Data("""
                CTI2
                TARGET_INSTRUMENT "i1"
                NUMBER_OF_SETS 4
                NUMBER_OF_PAGES 1
                BEGIN_DATA_FORMAT
                """.utf8))
        app.launchEnvironment["ICCERY_TEST_EXISTING_TARGET"] =
            workDir.appendingPathComponent("old.ti2").path
        launchApp()
        app.buttons["btnOpenExisting"].click()
        XCTAssertTrue(waitFor("stage3TargetBasename", timeout: 10).exists)
        XCTAssertTrue(element("stage3LoadedTargetBanner").exists)
        let notice = element("noticeText")
        XCTAssertTrue(notice.exists)
        XCTAssertTrue((notice.value as? String ?? "")
            .contains("Resumed from .ti2"))
    }

    /// A .ti2 without its sibling .ti1 must not advance (issue #8).
    func testResumeTi2WithoutSiblingFails() throws {
        FileManager.default.createFile(
            atPath: workDir.appendingPathComponent("orphan.ti2").path,
            contents: Data("CTI2".utf8))
        app.launchEnvironment["ICCERY_TEST_EXISTING_TARGET"] =
            workDir.appendingPathComponent("orphan.ti2").path
        launchApp()
        app.buttons["btnOpenExisting"].click()
        let err = element("noticeText")
        XCTAssertTrue(err.waitForExistence(timeout: 10))
        XCTAssertTrue((err.value as? String ?? "").contains("Cannot resume"))
        XCTAssertTrue(element("btnGenerate").exists) // still Stage 1
    }

    /// Preset apply is bidirectional: the draft preset's 150 dpi must
    /// be visible on Stage 2; built-ins cannot be deleted (issue #11).
    func testPresetApplyAndBuiltInProtection() throws {
        // Land on Stage 2 via a .ti1 resume so tiffDpi is visible.
        FileManager.default.createFile(
            atPath: workDir.appendingPathComponent("p.ti1").path,
            contents: Data("CGATS".utf8))
        app.launchEnvironment["ICCERY_TEST_EXISTING_TARGET"] =
            workDir.appendingPathComponent("p.ti1").path
        launchApp()

        // Sidebar preset picker is enabled; apply the draft preset.
        let picker = app.popUpButtons["presetSelect"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(picker.isEnabled)
        picker.click()
        let draftItem = app.menuItems["Fast RGB Draft (400 patches)"]
        XCTAssertTrue(draftItem.waitForExistence(timeout: 5))
        draftItem.click()

        app.buttons["btnOpenExisting"].click()
        XCTAssertTrue(waitFor("btnCreateLayout", timeout: 10).exists)
        // StaticText content is exposed via `value` on macOS, not `label`.
        XCTAssertTrue(app.staticTexts
            .matching(NSPredicate(format: "value CONTAINS 'DPI: 150'"))
            .firstMatch.waitForExistence(timeout: 5))

        // Manage dialog: built-ins show "Built-in" and have no delete.
        app.buttons["btnOpenPresetsDialog"].click()
        XCTAssertTrue(waitFor("managePresetsList", timeout: 10).exists)
        XCTAssertFalse(element("btnDeletePreset-preset-std-rgb").exists)
        XCTAssertTrue(element("presetRow-preset-std-rgb").exists)
        element("btnCloseManagePresetsDialog").click()
    }

    /// Save a custom preset through the dialog; it appears in the list
    /// and can be deleted (issue #11).
    func testSaveAndDeleteCustomPreset() throws {
        launchApp()
        app.buttons["btnSavePresetModal"].click()
        XCTAssertTrue(waitFor("savePresetDialog", timeout: 10).exists)
        let nameField = element("savePresetName")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText("UI Test Preset")
        element("btnConfirmSavePreset").click()

        app.buttons["btnOpenPresetsDialog"].click()
        XCTAssertTrue(waitFor("managePresetsList", timeout: 10).exists)
        XCTAssertTrue(staticText("UI Test Preset")
            .waitForExistence(timeout: 5))
        // The custom row is deletable (id prefix custom-).
        let deleteButtons = buttonsMatching(
            "identifier BEGINSWITH 'btnDeletePreset-'")
        XCTAssertTrue(deleteButtons.firstMatch.waitForExistence(timeout: 5))
        deleteButtons.firstMatch.click()
        XCTAssertFalse(staticText("UI Test Preset").waitForExistence(timeout: 3))
    }

    /// Export a preset to JSON and re-import it (issue #11).
    func testPresetExportImport() throws {
        let exportURL = testRoot.appendingPathComponent("export.json")
        let importURL = testRoot.appendingPathComponent("import.json")
        app.launchEnvironment["ICCERY_TEST_PRESET_EXPORT"] = exportURL.path
        app.launchEnvironment["ICCERY_TEST_PRESET_IMPORT"] = importURL.path
        launchApp()

        // Save a custom preset first, then export it.
        app.buttons["btnSavePresetModal"].click()
        let nameField = element("savePresetName")
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.click()
        nameField.typeText("RoundTrip")
        element("btnConfirmSavePreset").click()

        // Export via the manage dialog.
        app.buttons["btnOpenPresetsDialog"].click()
        XCTAssertTrue(waitFor("managePresetsList", timeout: 10).exists)
        let exportButtons = buttonsMatching(
            "identifier BEGINSWITH 'btnExportPreset-'")
        XCTAssertTrue(exportButtons.firstMatch.waitForExistence(timeout: 5))
        exportButtons.firstMatch.click()
        XCTAssertTrue(waitForFile(exportURL), "preset export file missing")

        // Import must land back in the store (delete → re-import).
        let deleteButtons = buttonsMatching(
            "identifier BEGINSWITH 'btnDeletePreset-'")
        deleteButtons.firstMatch.click()
        XCTAssertFalse(staticText("RoundTrip").waitForExistence(timeout: 3))

        // Copy the export to the import path so the hook picks it up.
        try FileManager.default.copyItem(at: exportURL, to: importURL)
        element("btnImportPreset").click()
        XCTAssertTrue(staticText("RoundTrip")
            .waitForExistence(timeout: 5))
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
