import XCTest

/// Milestone 12 UI tests — #202 AirPrint queue detection. The mock
/// `lpstat -v` fixture reports `Mock_Canon_Pro` as a local unencrypted
/// `ipp://` queue resolved via the `_universal._sub._ipp._tcp` mDNS
/// subtype (rule 5), while `Mock_Epson_7450` is a plain USB raster
/// queue — so the badge must track the picker selection.
@MainActor
final class Milestone12AirPrintUITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!
    private var spoolLogURL: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui12-\(UUID().uuidString)")
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

    /// Poll until `id` no longer resolves — the badge is conditionally
    /// rendered, so absence is only meaningful after a settle window.
    private func waitForAbsence(_ id: String, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element(id).exists { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(element(id).exists, "Element \(id) should be absent")
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

    /// Select the printer-picker menu item whose title contains
    /// `needle` (display names come from the `lpoptions` fixture).
    private func selectPrinter(containing needle: String) {
        let picker = app.popUpButtons["printerSelect"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.click()
        let item = app.menuItems
            .matching(NSPredicate(format: "title CONTAINS %@", needle))
            .firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "No printer menu item containing \(needle)")
        item.click()
    }

    // MARK: - Tests

    /// The badge appears while the AirPrint fixture queue is selected
    /// and is absent for the USB Epson — in both directions.
    func testAirPrintBadgeTracksSelectedQueue() throws {
        app.launch()
        app.activate()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        // Default queue is the USB Epson — no badge.
        waitForAbsence("airPrintWarningBadge")

        selectPrinter(containing: "Canon")
        let badge = element("airPrintWarningBadge")
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        // StaticText exposes its content via AXValue, not the label.
        let badgeText = [badge.value as? String, badge.label, badge.title]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? ""
        XCTAssertTrue(
            badgeText.contains(
                "AirPrint queue — unmanaged colour cannot be guaranteed."),
            "Unexpected badge text: \(badgeText)")

        selectPrinter(containing: "Epson")
        waitForAbsence("airPrintWarningBadge")
    }
}
