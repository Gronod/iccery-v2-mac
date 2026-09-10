import Foundation
import XCTest

/// Milestone 6 — Issue #28 native SceneKit gamut viewer acceptance tests.
@MainActor
final class Milestone6GamutUITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!
    private var appDataDir: URL!
    private var referenceGamutURL: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui-m6-gamut-\(UUID().uuidString)")
        binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bin")
        workDir = testRoot.appendingPathComponent("work")
        appDataDir = testRoot.appendingPathComponent("AppData")

        // The bundled sRGB reference used by the app; copied into the test workdir
        // by the mock iccgamut so the profile gamut is a real, parseable mesh.
        referenceGamutURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Argyll/reference_gamuts/sRGB.gam")

        try FileManager.default.createDirectory(
            at: workDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: appDataDir, withIntermediateDirectories: true)

        // Pre-stage a measured .ti3 and start the wizard on Stage 4.
        FileManager.default.createFile(
            atPath: workDir.appendingPathComponent("mytarget.ti3").path,
            contents: Data("MOCK_TI3".utf8),
            attributes: nil)

        let state: [String: Any] = [
            "currentStage": 4,
            "basename": "mytarget",
            "cwd": workDir.path,
            "printerName": "MockPrinter",
            "sessionMode": "profile",
            "profileBasename": "mytarget",
            "calibrationOriginalBasename": ""
        ]
        let stateData = try JSONSerialization.data(withJSONObject: state, options: [])
        try stateData.write(to: appDataDir.appendingPathComponent("wizard_state.json"))

        app = XCUIApplication()
        app.launchEnvironment = [
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_ROOT": testRoot.path,
            "ICCERY_ARGYLL_BINARY_DIR": binDir.path,
            "ICCERY_TEST_WORKDIR": workDir.path,
            "ICCERY_MOCK_GAMUT_SOURCE": referenceGamutURL.path,
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
        return app.sheets.firstMatch.descendants(matching: .any)[id].firstMatch
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

    /// Build and verify the mock profile, then open the native gamut viewer.
    /// The viewer should load both the reference sRGB mesh and the profile
    /// gamut copied from that reference.
    func testViewGamutOpensSceneKitSheet() throws {
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 10) {
            app.activate()
        }

        waitFor("btnCreateProfile").click()

        waitFor("btnVerifyProfile").click()

        waitFor("btnViewGamut").click()

        let gamutView = waitFor("gamutView")
        XCTAssertTrue(gamutView.exists)

        let status = waitFor("gamutStatusText")
        let value = status.value as? String ?? ""
        XCTAssertTrue(value.contains("faces"), "Gamut status should report mesh faces, got: \(value)")

        // The reset button demonstrates that the viewer is interactive.
        let reset = waitFor("btnResetGamutCamera")
        XCTAssertTrue(reset.isEnabled)
        reset.click()
    }
}
