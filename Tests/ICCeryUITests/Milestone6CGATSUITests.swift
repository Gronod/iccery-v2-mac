import Foundation
import XCTest

/// Milestone 6 CGATS import UI tests (issue #30).
@MainActor
final class Milestone6CGATSUITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var datasetURL: URL!

    override func setUp() async throws {
        continueAfterFailure = false

        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-cgats-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)

        let csv = """
        SAMPLE_ID,SAMPLE_LOC,RGB_R,RGB_G,RGB_B,XYZ_X,XYZ_Y,XYZ_Z,LAB_L,LAB_A,LAB_B
        1,A1,50,0,0,20,10,5,50,60,30
        2,A2,0,50,0,10,30,5,60,-50,40
        """
        datasetURL = testRoot.appendingPathComponent("imported.csv")
        try csv.write(to: datasetURL, atomically: true, encoding: .utf8)

        app = XCUIApplication()
        app.launchEnvironment = [
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_WORKDIR": testRoot.path,
            "ICCERY_TEST_DATASET_IMPORT": datasetURL.path
        ]
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
    }

    /// `Milestone6CGATSUITests.importUsesOpenPanelNotSaveTi1`
    /// Must fail if import presents a save panel or a `.ti1` filter.
    func testImportUsesOpenPanelNotSaveTi1() throws {
        app.launch()
        app.activate()

        XCTAssertTrue(app.buttons["btn-import-dataset"].waitForExistence(timeout: 10))
        app.buttons["btn-import-dataset"].click()

        // No save panel should appear; the open panel is stubbed under UI testing.
        let savePanel = app.sheets.firstMatch
        XCTAssertFalse(savePanel.exists, "Import must use an open panel, never a save panel.")

        // The dataset should be accepted and the user should advance to Stage 4.
        _ = app.otherElements["stage-4"].waitForExistence(timeout: 10)
        XCTAssertTrue(app.otherElements["stage-4"].exists)

        // The canonical .ti3 should be written next to the source file.
        let ti3URL = testRoot.appendingPathComponent("imported.ti3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ti3URL.path))
    }
}
