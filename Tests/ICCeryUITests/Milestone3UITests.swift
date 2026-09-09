import XCTest

/// Milestone 3 UI tests — issue #17 print panel end-to-end with mock
/// CUPS binaries and a stubbed `NSPrintPanel`. The real panel is a
/// system modal XCUITest cannot drive; `ICCERY_TEST_PRINT_PANEL`
/// returns a canned `PrintPropertiesResult` instead. Mock `lp` appends
/// its argv to `ICCERY_TEST_LP_ARGV` for assertions — that file is the
/// evidence that captured options are replayed (docs/11 §tests).
@MainActor
final class Milestone3UITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!
    private var lpArgvURL: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui3-\(UUID().uuidString)")
        binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bin")
        workDir = testRoot.appendingPathComponent("work")
        lpArgvURL = testRoot.appendingPathComponent("lp-argv.log")
        try FileManager.default.createDirectory(
            at: workDir, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchEnvironment = [
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_ROOT": testRoot.path,
            "ICCERY_ARGYLL_BINARY_DIR": binDir.path,
            "ICCERY_CUPS_BIN_DIR": binDir.path,
            "ICCERY_TEST_SAVE_TARGET":
                workDir.appendingPathComponent("mytarget.ti1").path,
            "ICCERY_TEST_WORKDIR": workDir.path,
            "ICCERY_TEST_LP_ARGV": lpArgvURL.path,
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

    private func waitForFileContent(
        _ url: URL,
        containing needle: String,
        timeout: TimeInterval = 10
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               text.contains(needle) {
                return text
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func launchApp() {
        app.launch()
        app.activate()
    }

    private func element(_ id: String) -> XCUIElement {
        let inApp = app.descendants(matching: .any)[id]
        if inApp.exists { return inApp }
        return app.sheets.firstMatch.descendants(matching: .any)[id]
    }

    private func waitFor(_ id: String, timeout: TimeInterval = 15) -> XCUIElement {
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

    /// Drive the app through targen + printtarg so the print panel is
    /// live with a manifest.
    private func reachPrintPanel() {
        app.buttons["btnBrowse"].click()
        app.buttons["btnGenerate"].click()
        _ = waitFor("btnCreateLayout", timeout: 25)
        app.buttons["btnCreateLayout"].click()
        _ = waitFor("galleryPage-0", timeout: 25)
    }

    private func recordedLpArgv() -> String {
        (try? String(contentsOf: lpArgvURL, encoding: .utf8)) ?? ""
    }

    private func waitForLpLine(_ timeout: TimeInterval = 10) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let out = recordedLpArgv()
            if !out.isEmpty { return out }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return recordedLpArgv()
    }

    // MARK: - Tests

    /// Panel appears after the manifest; refresh populates the printer
    /// select with the mock queues and shows a status badge.
    func testPrintPanelEnumeratesPrinters() throws {
        launchApp()
        reachPrintPanel()

        XCTAssertTrue(waitFor("rawPrintPanel").exists)
        // The panel auto-refreshes on appear; the default mock queue is
        // selected and its status badge shows.
        XCTAssertTrue(element("printerSelect").waitForExistence(timeout: 10))
        XCTAssertTrue(element("printerStatusBadge")
            .waitForExistence(timeout: 10))
        XCTAssertTrue(element("printerTraySelect").exists)
        XCTAssertTrue(element("printerMediaTypeSelect").exists)
        XCTAssertTrue(element("btnOrientPortrait").exists)
        XCTAssertTrue(element("btnOrientLandscape").exists)
        XCTAssertTrue(app.buttons["btnPrintAll"].isEnabled)
    }

    /// Preferences cancel → info notice, no error, no cache mutation.
    func testPreferencesCancelIsInfo() throws {
        app.launchEnvironment["ICCERY_TEST_PRINT_PANEL"] = "cancel"
        launchApp()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        element("btnPrinterProperties").click()
        let notice = element("printNotificationText")
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue((notice.value as? String ?? "")
            .contains("cancelled"))
    }

    /// Preferences OK → captured options are replayed verbatim in the
    /// `lp` argv alongside the two mandatory AP_* headers (issue 17's
    /// acceptance test: "captured options replayed in argv").
    func testCapturedOptionsReplayedInLpArgv() throws {
        app.launchEnvironment["ICCERY_TEST_PRINT_PANEL"] = "ok"
        app.launchEnvironment["ICCERY_TEST_PANEL_OPTIONS"] =
            "InputSlot=Rear MediaType=PhotographicGlossy"
        launchApp()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        element("btnPrinterProperties").click()
        let notice = element("printNotificationText")
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue((notice.value as? String ?? "")
            .contains("Settings captured"))

        app.buttons["btnPrintAll"].click()
        let argv = waitForLpLine()
        XCTAssertTrue(argv.contains(
            "AP_ColorMatchingMode=AP_ApplicationColorMatching"), argv)
        XCTAssertTrue(argv.contains(
            "AP.ColorMatchingMode=AP_ApplicationColorMatching"), argv)
        XCTAssertTrue(argv.contains("InputSlot=Rear"), argv)
        XCTAssertTrue(argv.contains("MediaType=PhotographicGlossy"), argv)
        // Detected bypass for the mock queue (EPIJ_CMat present in
        // lpoptions -l) is appended when not captured.
        XCTAssertTrue(argv.contains("EPIJ_CMat=3"), argv)
        XCTAssertTrue(argv.contains("orientation-requested=3"), argv)
        // Last token is the TIFF.
        XCTAssertTrue(argv.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasSuffix("page1.tif"), argv)
    }

    /// Per-page print uses the same spool path (btnPrintPage-N).
    func testPerPagePrint() throws {
        launchApp()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        // Wait for the async printer enumeration to select a queue; once
        // `btnPrintAll` is enabled, `btnPrintPage-0` is too.
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, !app.buttons["btnPrintAll"].isEnabled {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(app.buttons["btnPrintAll"].isEnabled)

        app.buttons["btnPrintPage-0"].click()
        let argv = waitForLpLine()
        XCTAssertTrue(argv.contains("AP_ColorMatchingMode"), argv)
        XCTAssertTrue(argv.contains("page1.tif"), argv)
    }

    /// lp failure surfaces in the in-panel notice, not the wizard banner.
    func testLpFailureShowsPrintNotice() throws {
        app.launchEnvironment["ICCERY_MOCK_LP_EXIT"] = "1"
        launchApp()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        app.buttons["btnPrintAll"].click()
        let notice = element("printNotificationText")
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue((notice.value as? String ?? "")
            .contains("Print failed"))
    }

    /// wizardState.printerName records the queue used for spooling (#95).
    func testPrinterNamePersistedOnSpool() throws {
        launchApp()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        app.buttons["btnPrintAll"].click()
        _ = waitForLpLine()
        let stateURL = testRoot
            .appendingPathComponent("AppData")
            .appendingPathComponent("wizard_state.json")
        let state = waitForFileContent(
            stateURL, containing: "Mock_Epson_7450", timeout: 15)
        XCTAssertNotNil(state)
        XCTAssertTrue((state ?? "").contains("Mock_Epson_7450"))
    }


}
