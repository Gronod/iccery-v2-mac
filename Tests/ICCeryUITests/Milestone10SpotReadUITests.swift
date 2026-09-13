import XCTest

/// Milestone 10 UI tests — issue #148 spot-read console. Mock Argyll
/// sidecars (`ICCERY_ARGYLL_BINARY_DIR` → `Fixtures/bin`) provide
/// `instlist`, `chartread`, and `spotread`; no real USB Detect is ever
/// clicked. All queries are by identifier only.
@MainActor
final class Milestone10SpotReadUITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui10spot-\(UUID().uuidString)")
        binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bin")
        workDir = testRoot.appendingPathComponent("work")
        try FileManager.default.createDirectory(
            at: workDir, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchEnvironment = [
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_ROOT": testRoot.path,
            "ICCERY_ARGYLL_BINARY_DIR": binDir.path,
            // Redirect the bundled root too so the real sidecars copied
            // into the product by the build phase cannot mask a missing
            // override binary (`testMissingSidecarShowsMessage`).
            "ICCERY_ARGYLL_BUNDLED_ROOT": binDir.path,
            "ICCERY_CUPS_BIN_DIR": binDir.path,
            "ICCERY_TEST_SAVE_TARGET":
                workDir.appendingPathComponent("mytarget.ti1").path,
            "ICCERY_TEST_WORKDIR": workDir.path,
            "ICCERY_TEST_CSV_EXPORT":
                workDir.appendingPathComponent("spot-history.csv").path,
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

    private func launchApp() {
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 10) {
            app.activate()
        }
    }

    /// Seed `wizard_state.json` with a working directory so `btnSpotRead`
    /// is enabled without driving the whole Stage 1/2 flow.
    private func seedWorkingDirectory() throws {
        let appData = testRoot.appendingPathComponent("AppData", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appData, withIntermediateDirectories: true)
        let state = """
        {
          "currentStage": 0,
          "basename": "spotui",
          "cwd": "\(workDir.path)",
          "sessionMode": "profile"
        }
        """
        try state.write(
            to: appData.appendingPathComponent("wizard_state.json"),
            atomically: true, encoding: .utf8)
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

    // MARK: - Sidebar gating

    func testSpotReadButtonDisabledWithoutCwd() throws {
        launchApp()
        let button = app.buttons["btnSpotRead"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertFalse(button.isEnabled)
    }

    func testSpotReadButtonDisabledDuringChartread() throws {
        launchApp()
        // Drive to Stage 3 with the mock targen/printtarg fixtures.
        app.buttons["btnBrowse"].click()
        app.buttons["btnGenerate"].click()
        _ = waitFor("btnCreateLayout", timeout: 20)
        app.buttons["btnCreateLayout"].click()
        _ = waitFor("galleryPage-0", timeout: 20)
        _ = waitFor("btnAdvanceToStage3", timeout: 10)
        app.buttons["btnAdvanceToStage3"].click()
        _ = waitFor("stage3TargetBasename", timeout: 10)

        // Start the mock chartread — it blocks on the calibrate prompt.
        app.buttons["btnStartRead"].click()
        _ = waitFor("btnCalibrate", timeout: 25)

        let button = app.buttons["btnSpotRead"]
        XCTAssertTrue(button.exists)
        XCTAssertFalse(button.isEnabled)

        // Clean up the live chartread child before teardown.
        if app.buttons["btnCancel"].exists {
            app.buttons["btnCancel"].click()
        }
    }

    // MARK: - Sheet contract

    func testSheetHasOwnInstrumentIds() throws {
        try seedWorkingDirectory()
        launchApp()

        let button = app.buttons["btnSpotRead"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(10)
        while !button.isEnabled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(button.isEnabled)
        button.click()

        _ = waitFor("spotReadView", timeout: 10)
        XCTAssertTrue(element("spotInstrumentSelect").waitForExistence(timeout: 10))
        // Stage 3 ids must not appear inside the sheet.
        XCTAssertFalse(
            app.sheets.firstMatch.descendants(matching: .any)["chartreadInstrumentSelect"].exists)
        XCTAssertFalse(
            app.sheets.firstMatch.descendants(matching: .any)["btnDetectInstruments"].exists)
        XCTAssertTrue(element("btnCloseSpotRead").exists)
    }

    func testMissingSidecarShowsMessage() throws {
        // Point the override at an empty dir; the bundled root has no
        // real sidecars in this checkout, so resolve() misses both.
        let emptyBin = testRoot.appendingPathComponent("empty-bin")
        try FileManager.default.createDirectory(
            at: emptyBin, withIntermediateDirectories: true)
        app.launchEnvironment["ICCERY_ARGYLL_BINARY_DIR"] = emptyBin.path
        try seedWorkingDirectory()
        launchApp()

        let button = app.buttons["btnSpotRead"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(10)
        while !button.isEnabled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        button.click()

        _ = waitFor("spotReadView", timeout: 10)
        XCTAssertTrue(element("spotSidecarMissing").waitForExistence(timeout: 10))
        XCTAssertFalse(element("btnSpotStart").exists)
        XCTAssertFalse(element("btnSpotDetectInstruments").exists)
        XCTAssertTrue(element("btnCloseSpotRead").exists)
    }

    func testHistoryCopyDisabledWhenEmpty() throws {
        try seedWorkingDirectory()
        launchApp()

        let button = app.buttons["btnSpotRead"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(10)
        while !button.isEnabled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        button.click()

        _ = waitFor("spotReadView", timeout: 10)
        XCTAssertTrue(element("spotHistoryEmpty").waitForExistence(timeout: 10))
        XCTAssertTrue(element("spotLastEmpty").exists)
        XCTAssertFalse(element("btnSpotCopyLab").isEnabled)
        XCTAssertFalse(element("btnSpotExportCsv").isEnabled)
    }

    /// Full mock session: Start → Calibrate → Read produces one Lab
    /// sample and enables Copy/Export.
    func testMockSessionProducesSample() throws {
        try seedWorkingDirectory()
        launchApp()

        let button = app.buttons["btnSpotRead"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(10)
        while !button.isEnabled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        button.click()

        _ = waitFor("spotReadView", timeout: 10)
        let start = element("btnSpotStart")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.click()

        XCTAssertTrue(element("btnSpotCalibrate").waitForExistence(timeout: 15))
        element("btnSpotCalibrate").click()

        XCTAssertTrue(element("btnSpotTrigger").waitForExistence(timeout: 15))
        element("btnSpotTrigger").click()

        XCTAssertTrue(element("spotLastSample").waitForExistence(timeout: 15))
        XCTAssertTrue(element("spotLabL").exists)
        XCTAssertTrue(element("spotSwatch").exists)
        XCTAssertTrue(element("btnSpotCopyLab").isEnabled)
        XCTAssertTrue(element("btnSpotExportCsv").isEnabled)

        element("btnSpotStop").click()
        element("btnCloseSpotRead").click()
    }
}
