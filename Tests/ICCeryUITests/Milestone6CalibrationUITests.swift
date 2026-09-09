import Foundation
import XCTest

/// Milestone 6 — Stage 0 printer calibration UI acceptance.
///
/// Uses the mock Argyll fixtures and UI-test environment flags so no real
/// instrument, printer, or modal file panel is required.
@MainActor
final class Milestone6CalibrationUITests: XCTestCase {

    private var app: XCUIApplication!
    private var testWorkDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false

        testWorkDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cal-ui-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: testWorkDir,
            withIntermediateDirectories: true
        )

        let binaryDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bin")

        app = XCUIApplication()
        app.launchEnvironment = [
            "ICCERY_UI_TESTING": "1",
            "ICCERY_ARGYLL_BINARY_DIR": binaryDir.path,
            "ICCERY_TEST_WORKDIR": testWorkDir.path
        ]
        app.launch()
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
        if let testWorkDir {
            try? FileManager.default.removeItem(at: testWorkDir)
        }
    }

    func testCalibrationDashboardOpensAndCanGenerate() throws {
        // Set up a target and working directory on Stage 1.
        let basename = app.textFields["targetBasename"]
        XCTAssertTrue(basename.waitForExistence(timeout: 5))
        basename.tap()
        basename.typeText("DemoTarget")

        let workDir = app.buttons["btnSelectWorkDir"]
        XCTAssertTrue(workDir.waitForExistence(timeout: 5))
        workDir.tap()

        let generate = app.buttons["btnGenerate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()

        // Open the calibration dashboard once Stage 2 is reached.
        let advance = app.buttons["btnAdvanceToStage3"]
        XCTAssertTrue(advance.waitForExistence(timeout: 10))

        let calButton = app.buttons["btnCalibratePrinter"]
        XCTAssertTrue(calButton.waitForExistence(timeout: 5))
        calButton.tap()

        XCTAssertTrue(app.staticTexts["Calibrate Printer"].waitForExistence(timeout: 5))

        // Start the calibration wedge. The mock targen will create CAL_DemoTarget.ti1.
        let calGenerate = app.buttons["btnCalGenerate"]
        XCTAssertTrue(calGenerate.waitForExistence(timeout: 5))
        calGenerate.tap()

        // After generation the wizard should advance to Stage 2 (layout) because
        // a CAL_ .ti1 now exists and the session is in calibration mode.
        let layout = app.buttons["btnCreateLayout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 10))
    }
}
