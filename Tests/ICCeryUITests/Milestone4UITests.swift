import XCTest

/// Milestone 4 UI tests — issues #18–#22.
/// Uses the same isolated-fixture strategy as M2/M3.
@MainActor
final class Milestone4UITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui-\(UUID().uuidString)")
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

    private func launchApp() {
        app.launch()
        app.activate()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
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

    /// Reach Stage 3 by generating a target, creating a layout, and
    /// advancing from Stage 2.
    private func reachStage3() {
        launchApp()
        app.buttons["btnBrowse"].click()
        app.buttons["btnGenerate"].click()
        _ = waitFor("btnCreateLayout", timeout: 20)
        app.buttons["btnCreateLayout"].click()
        _ = waitFor("galleryPage-0", timeout: 20)
        _ = waitFor("btnAdvanceToStage3", timeout: 10)
        app.buttons["btnAdvanceToStage3"].click()
        _ = waitFor("stage3TargetBasename", timeout: 10)
    }

    /// Fixture-driven instrument detection populates the picker.
    func testInstrumentDetectionPopulatesPicker() throws {
        reachStage3()
        app.buttons["btnDetectInstruments"].click()
        XCTAssertTrue(waitFor("chartreadInstrumentSelect", timeout: 20).exists)

        let picker = app.popUpButtons["chartreadInstrumentSelect"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()

        // The fixture provides three devices plus the default Auto entry.
        XCTAssertTrue(app.menuItems.count >= 3)
    }

    /// End-to-end handheld chartread with the mock fixture produces a
    /// canonical .ti3 and unlocks Stage 4.
    func testHandheldFixtureChartreadAndAverage() throws {
        reachStage3()

        app.buttons["btnDetectInstruments"].click()
        _ = waitFor("chartreadInstrumentSelect", timeout: 20)

        // Keep Auto (port 1) and start the session.
        XCTAssertTrue(app.buttons["btnStartRead"].waitForExistence(timeout: 5))
        app.buttons["btnStartRead"].click()

        // Calibrate.
        let calibrate = element("btnCalibrate")
        if !calibrate.waitForExistence(timeout: 25) {
            let error = element("chartreadLastError").label
            let value = element("chartreadLastError").value as? String ?? "<nil>"
            XCTFail("No calibrate button. lastError.label='\(error)' value='\(value)'")
        }
        app.buttons["btnCalibrate"].click()

        // Trigger strip A.
        _ = waitFor("btnTrigger", timeout: 20)
        app.buttons["btnTrigger"].click()

        // Trigger strip B.
        _ = waitFor("btnTrigger", timeout: 20)
        app.buttons["btnTrigger"].click()

        // All strips read → Done & Save appears.
        _ = waitFor("btnDoneRead", timeout: 20)
        app.buttons["btnDoneRead"].firstMatch.click()

        // Averaging panel appears with one pass snapshot.
        _ = waitFor("chartreadAveragingPanel", timeout: 20)
        _ = waitFor("passCounterBadge", timeout: 20)
        XCTAssertTrue(app.buttons["btnFinishAndAverage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["btnFinishAndAverage"].isEnabled)

        app.buttons["btnFinishAndAverage"].click()

        // Finish promotion should create the canonical .ti3 and
        // advance the wizard to Stage 4.
        let ti3 = workDir.appendingPathComponent("mytarget.ti3")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !FileManager.default.fileExists(atPath: ti3.path) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ti3.path))
    }
}
