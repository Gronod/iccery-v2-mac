import XCTest

/// Milestone 10 UI tests — issue #146 media recipe library. Mock CUPS
/// binaries (`ICCERY_CUPS_BIN_DIR` → `Fixtures/bin`) emit
/// `Mock_Epson_7450` / `Mock_Canon_Pro`; recipes are seeded by writing
/// `<ICCERY_TEST_ROOT>/AppData/media_library.json` before launch —
/// `AppPaths` redirects app data under `ICCERY_TEST_ROOT`. All queries
/// are by identifier only ("Media" also appears in help overlays).
@MainActor
final class Milestone10MediaLibraryUITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui10-\(UUID().uuidString)")
        binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bin")

        let appData = testRoot.appendingPathComponent("AppData", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appData, withIntermediateDirectories: true)
        // A recipe bound to a queue that is never enumerated.
        let fixture = """
        [
          {
            "id": "fixture-missing-queue",
            "name": "Missing Queue Recipe",
            "notes": "",
            "printer_id": "No_Such_Queue",
            "printer_display_name": "Missing Queue",
            "paper_name": "Rag",
            "ink_set": "PK",
            "colour_space": "rgb",
            "preset_id": "preset-std-rgb",
            "calibration_url": null,
            "apply_calibration": false,
            "created": "2026-09-12T00:00:00Z",
            "updated": "2026-09-12T00:00:00Z"
          }
        ]
        """
        try fixture.write(
            to: appData.appendingPathComponent("media_library.json"),
            atomically: true, encoding: .utf8)

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

    private func waitForEnabled(_ id: String, timeout: TimeInterval = 15) -> XCUIElement {
        let el = waitFor(id, timeout: timeout)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if el.isEnabled { return el }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return el
    }

    func testMediaPickerDoesNotReusePresetSelect() throws {
        launchApp()

        let preset = app.popUpButtons["presetSelect"]
        XCTAssertTrue(preset.waitForExistence(timeout: 10))
        let media = app.popUpButtons["mediaSelect"]
        XCTAssertTrue(media.waitForExistence(timeout: 10))
    }

    func testCaptureRequiresNamePaperInk() throws {
        launchApp()

        // Capture enables once the mock CUPS enumeration selects a queue.
        let capture = waitForEnabled("btnMediaLibraryCapture")
        XCTAssertTrue(capture.isEnabled)
        capture.click()

        _ = waitFor("saveMediaRecipeDialog")
        let save = element("btnConfirmSaveMedia")
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)

        for (id, text) in [
            ("saveMediaName", "UI Recipe"),
            ("saveMediaPaper", "Rag"),
            ("saveMediaInk", "PK"),
        ] {
            let field = element(id)
            field.click()
            field.typeText(text)
        }

        XCTAssertTrue(save.isEnabled)
    }

    func testManageApplyMissingPrinterShowsBanner() throws {
        launchApp()

        let manage = app.buttons["btnMediaLibraryManage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        manage.click()
        _ = waitFor("manageMediaDialog")

        let apply = element("btnMediaLibraryApply-fixture-missing-queue")
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        apply.click()

        let notice = waitFor("noticeText")
        let text = (notice.value as? String) ?? notice.label
        XCTAssertTrue(
            text.contains("is not installed"),
            "expected not-installed notice, got: \(text)")

        // A failed apply keeps the manage sheet open and the sidebar
        // picker reverts.
        XCTAssertTrue(element("manageMediaDialog").exists)
        XCTAssertTrue(element("mediaSelect").exists)
    }
}
