import Foundation
import XCTest

/// Milestone 10 — Issue #147 gamut compare chrome tests.
///
/// Sheet-opened only: no GPU hit-test assertions (no reliable SceneKit
/// click on the runner). Containment itself is covered by
/// `GamutContainmentTests`.
@MainActor
final class Milestone10GamutCompareUITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!
    private var appDataDir: URL!
    private var referenceGamutURL: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui-m10-gamut-\(UUID().uuidString)")
        binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bin")
        workDir = testRoot.appendingPathComponent("work")
        appDataDir = testRoot.appendingPathComponent("AppData")
        referenceGamutURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Argyll/reference_gamuts/sRGB.gam")

        try FileManager.default.createDirectory(
            at: workDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: appDataDir, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchEnvironment = [
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_ROOT": testRoot.path,
            "ICCERY_ARGYLL_BINARY_DIR": binDir.path,
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

    private func element(_ id: String) -> XCUIElement {
        let inApp = app.descendants(matching: .any)[id].firstMatch
        if inApp.exists { return inApp }
        let inSheet = app.sheets.firstMatch.descendants(matching: .any)[id].firstMatch
        if inSheet.exists { return inSheet }
        // Menu popup items live outside the window hierarchy.
        return app.menuItems[id].firstMatch
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

    /// Exists **and** `isEnabled`. Layer toggles render as disabled
    /// placeholders until the async layer load lands — on the macOS 12
    /// runner `waitFor` alone wins the race against `parse`.
    private func waitUntilEnabled(_ id: String, timeout: TimeInterval = 15) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let el = element(id)
            if el.exists && el.isEnabled { return el }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let el = element(id)
        XCTAssertTrue(
            el.exists && el.isEnabled, "Expected enabled element \(id)")
        return el
    }

    private func launchApp() {
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 10) {
            app.activate()
        }
    }

    private func openGamutSheet() {
        launchApp()
        waitFor("btnViewGamut").click()
        _ = waitFor("gamutView")
    }

    func testLayerTogglesExistWithSRGB() throws {
        openGamutSheet()

        let srgb = waitUntilEnabled("gamutLayer-sRGB")
        XCTAssertTrue(srgb.exists)
        // NSButton checkbox value is 1 when checked.
        XCTAssertEqual(srgb.value as? Int, 1, "sRGB layer should be on")

        let compare = waitFor("gamutLayer-compare")
        XCTAssertTrue(compare.exists)
        XCTAssertFalse(compare.isEnabled, "Compare toggle must be disabled before a load")
    }

    func testAddCompareButtonExists() throws {
        openGamutSheet()

        waitFor("btnGamutAddCompare").click()
        // No ICCERY_TEST_GAMUT_FILE set → the stubbed picker cancels;
        // the sRGB status must stay non-empty.
        waitFor("btnGamutOpenGam").click()

        let status = waitFor("gamutStatusText")
        let value = status.value as? String ?? ""
        XCTAssertTrue(value.contains("sRGB"), "Status should keep the sRGB clause, got: \(value)")
    }

    func testCompareGamLoadEnablesToggle() throws {
        let compareURL = workDir.appendingPathComponent("compare.gam")
        try FileManager.default.copyItem(at: referenceGamutURL, to: compareURL)
        app.launchEnvironment["ICCERY_TEST_GAMUT_FILE"] = compareURL.path

        openGamutSheet()
        waitFor("btnGamutAddCompare").click()
        waitFor("btnGamutOpenGam").click()

        // The pre-load placeholder also exists — wait for enabled.
        let compare = waitUntilEnabled("gamutLayer-compare")
        XCTAssertTrue(compare.isEnabled, "Compare toggle should enable after load")

        let status = waitFor("gamutStatusText")
        let value = status.value as? String ?? ""
        XCTAssertTrue(value.contains("compare"), "Status should list the compare layer, got: \(value)")

        let remove = waitFor("btnGamutRemoveCompare")
        XCTAssertTrue(remove.isEnabled)
    }

    func testOpenProfileRunsIccgamutForCompare() throws {
        // A profile with no sibling .gam → the mock iccgamut writes one.
        let profileURL = workDir.appendingPathComponent("myprinter.icc")
        try Data("MOCK_ICC".utf8).write(to: profileURL)
        app.launchEnvironment["ICCERY_TEST_GAMUT_PROFILE"] = profileURL.path
        app.launchEnvironment["ICCERY_MOCK_GAMUT_SOURCE"] = referenceGamutURL.path

        openGamutSheet()
        waitFor("btnGamutAddCompare").click()
        waitFor("btnGamutOpenProfile").click()

        let compare = waitUntilEnabled("gamutLayer-compare")
        XCTAssertTrue(compare.isEnabled, "Compare toggle should enable after iccgamut")
    }

    func testInspectPanelIdleStableHeight() throws {
        openGamutSheet()

        let panel = waitFor("gamutInspectPanel")
        XCTAssertTrue(panel.exists)
        XCTAssertTrue(element("gamutInspectIdle").exists)
        XCTAssertTrue(element("gamutStatusText").exists)
    }

    func testManualLabInspectShowsContainment() throws {
        openGamutSheet()

        waitFor("gamutLabEntryL").click()
        element("gamutLabEntryL").typeText("50")
        element("gamutLabEntryA").click()
        element("gamutLabEntryA").typeText("0")
        element("gamutLabEntryB").click()
        element("gamutLabEntryB").typeText("0")

        waitFor("btnGamutInspectLab").click()

        let inside = waitFor("gamutInspect-sRGB")
        let value = inside.value as? String ?? inside.label
        XCTAssertTrue(value.contains("in"), "Lab(50,0,0) should be inside sRGB, got: \(value)")
        XCTAssertTrue(element("gamutInspectL").exists)
        XCTAssertTrue(element("gamutInspectSwatch").exists)
    }

    func testResetIdentifierUnchanged() throws {
        openGamutSheet()
        let reset = waitFor("btnResetGamutCamera")
        XCTAssertTrue(reset.isEnabled)
    }
}
