import XCTest

/// Milestone 3 UI tests — issue #17 print panel end-to-end with mock
/// CUPS binaries and a stubbed `NSPrintPanel`. The real panel is a
/// system modal XCUITest cannot drive; `ICCERY_TEST_PRINT_PANEL`
/// returns a canned `PrintPropertiesResult` instead. The DEBUG
/// `RecordingTargetSpooler` appends one resolved-ticket line per
/// request to `ICCERY_TEST_SPOOL_LOG` (#201 D8) — that file is the
/// evidence that the Stage 2 selections reach the spool.
@MainActor
final class Milestone3UITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!
    private var spoolLogURL: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui3-\(UUID().uuidString)")
        binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bin")
        workDir = testRoot.appendingPathComponent("work")
        spoolLogURL = testRoot.appendingPathComponent("spool.log")
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
            "ICCERY_TEST_SPOOL_LOG": spoolLogURL.path,
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

    private func recordedSpoolLog() -> String {
        (try? String(contentsOf: spoolLogURL, encoding: .utf8)) ?? ""
    }

    private func waitForSpoolLine(_ timeout: TimeInterval = 10) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let out = recordedSpoolLog()
            if !out.isEmpty { return out }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return recordedSpoolLog()
    }

    /// Scrolls `stage-2` with the synthesized scroll wheel so
    /// `identifier`'s button moves up, clear of the Dock collision
    /// zone at the window's bottom edge (#132).
    ///
    /// macOS overlay scrollbars are not in the AX tree — never use
    /// `app.scrollBars` — and a click-drag does not scroll a macOS
    /// ScrollView (content-drag scrolling is iOS-only); the scroll
    /// wheel is the mechanism the platform supports (#215). A
    /// stale/off-screen AX frame resolves to a screen point that can
    /// be a Dock icon — a coordinate click there once opened Calendar
    /// instead of Print. Callers must click only when the returned
    /// element `isHittable`; never coordinate-click a stale frame.
    @discardableResult
    private func scrollStage2UntilHittable(
        _ identifier: String,
        timeout: TimeInterval = 20
    ) -> XCUIElement {
        var button = app.buttons[identifier]
        let cell = app.descendants(matching: .any)["galleryPage-0"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "galleryPage-0")
        let scrollView = app.scrollViews["stage-2"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10), "stage-2")

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let windowBottom = app.windows.firstMatch.frame.maxY
            if button.exists, button.isHittable,
               button.frame.maxY < windowBottom - 80 {
                return button
            }
            // Wheel-down inside the stage-2 viewport: content moves
            // UP ⇒ Print leaves the Dock zone. Negative deltaY scrolls
            // toward the document bottom (#215).
            scrollView.coordinate(withNormalizedOffset:
                CGVector(dx: 0.5, dy: 0.5))
                .scroll(byDeltaX: 0, deltaY: -60)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            button = app.buttons[identifier]
        }
        return button
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
        // Cancellation is informational, never an error (#80).
        XCTAssertEqual(element("printNotificationIcon").value as? String, "info")
    }

    /// Preferences OK → the captured media selection applies back to
    /// Stage 2 and reaches the recorded ticket writes alongside the
    /// mandatory colour keys (issue 17's acceptance test, ported to
    /// the native spool seam in #201). The captured `InputSlot` is no
    /// longer replayed — captured vendor state lives inside the
    /// `PrintTicket`, which the stub deliberately does not produce.
    func testPanelSelectionsApplyBackToSpoolWrites() throws {
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
        let log = waitForSpoolLine()
        XCTAssertTrue(log.contains(
            "AP_ColorMatchingMode=AP_ApplicationColorMatching"), log)
        XCTAssertTrue(log.contains(
            "AP.ColorMatchingMode=AP_ApplicationColorMatching"), log)
        XCTAssertTrue(log.contains("MediaType=PhotographicGlossy"), log)
        // Detected bypass for the mock queue (EPIJ_CMat present in
        // lpoptions -l) is always written.
        XCTAssertTrue(log.contains("EPIJ_CMat=3"), log)
        XCTAssertTrue(log.contains("orientation-requested=3"), log)
        XCTAssertTrue(log.contains("page=page1.tif"), log)
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

        // The gallery cell's Print button sits at the window's bottom
        // edge; scroll until it is genuinely hittable (#132). Never
        // coordinate-click a stale frame — that point can be the Dock.
        let printPage = scrollStage2UntilHittable("btnPrintPage-0")
        guard printPage.isHittable else {
            print("AXTREE-BEGIN frame=\(printPage.frame)\n" +
                  "\(app.debugDescription)\nAXTREE-END")
            XCTFail("btnPrintPage-0 never became hittable; frame=\(printPage.frame)")
            return
        }
        printPage.click()
        let log = waitForSpoolLine()
        XCTAssertTrue(log.contains("AP_ColorMatchingMode"), log)
        XCTAssertTrue(log.contains("page=page1.tif"), log)
    }

    /// A spool failure surfaces in the in-panel notice, not the
    /// wizard banner (`ICCERY_TEST_SPOOL_FAIL` makes the recording
    /// spooler throw `TargetSpoolError.operationFailed`).
    func testSpoolFailureShowsPrintNotice() throws {
        app.launchEnvironment["ICCERY_TEST_SPOOL_FAIL"] = "1"
        launchApp()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        app.buttons["btnPrintAll"].click()
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", "Print failed")
        let notice = app.staticTexts.containing(predicate).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(notice.label.contains("Print failed"))
        // Spool failure exposes the .error kind on the icon (#80).
        XCTAssertEqual(element("printNotificationIcon").value as? String, "error")
    }

    /// wizardState.printerName records the queue used for spooling (#95).
    func testPrinterNamePersistedOnSpool() throws {
        launchApp()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        app.buttons["btnPrintAll"].click()
        _ = waitForSpoolLine()
        let stateURL = testRoot
            .appendingPathComponent("AppData")
            .appendingPathComponent("wizard_state.json")
        let state = waitForFileContent(
            stateURL, containing: "Mock_Epson_7450", timeout: 15)
        XCTAssertNotNil(state)
        XCTAssertTrue((state ?? "").contains("Mock_Epson_7450"))
    }


}
