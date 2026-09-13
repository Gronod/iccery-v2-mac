import Foundation
import Metal
import XCTest

/// Milestone 6 — Issue #28 native SceneKit gamut viewer acceptance tests.
@MainActor
final class Milestone6GamutUITests: XCTestCase {

    /// Metal on the test host — the app under test runs on the same
    /// machine, so this predicts whether the sheet mounts SceneKit.
    private var hasGPU: Bool { MTLCreateSystemDefaultDevice() != nil }

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
        // Never leave the gamut sheet up for `terminate()` (#147).
        if app != nil, element("btnCloseGamut").exists {
            element("btnCloseGamut").click()
        }
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

    /// Inverse of `waitFor` — polls until the element leaves the tree.
    private func waitForGone(_ id: String, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element(id).exists { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(element(id).exists, "Expected element \(id) to disappear")
    }

    /// `btnCloseGamut` dismisses the sheet so `tearDown`'s `terminate()`
    /// is not stuck behind a key sheet (#147). No-op when already closed.
    private func closeGamutSheet() {
        let close = element("btnCloseGamut")
        guard close.waitForExistence(timeout: 5) else { return }
        close.click()
        waitForGone("gamutView")
    }

    /// Build and verify the mock profile, then open the native gamut viewer.
    /// The viewer should load both the reference sRGB mesh and the profile
    /// gamut copied from that reference.
    private func openGamutSheet() {
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 10) {
            app.activate()
        }

        waitFor("btnCreateProfile").click()

        waitFor("btnVerifyProfile").click()

        waitFor("btnViewGamut").click()

        _ = waitFor("gamutView")
    }

    func testViewGamutOpensSceneKitSheet() throws {
        openGamutSheet()

        let gamutView = waitFor("gamutView")
        XCTAssertTrue(gamutView.exists)

        let status = waitFor("gamutStatusText")
        let value = status.value as? String ?? ""
        XCTAssertTrue(value.contains("faces"), "Gamut status should report mesh faces, got: \(value)")

        // The fallback banner appears exactly when the host lacks Metal
        // — no SCNView is constructed without a GPU (#147).
        if hasGPU {
            XCTAssertFalse(
                element("gamutViewerUnavailable").exists,
                "GPU host must mount the SceneKit view, not the fallback")
        } else {
            _ = waitFor("gamutViewerUnavailable")
        }

        // The reset button demonstrates that the viewer is interactive.
        let reset = waitFor("btnResetGamutCamera")
        XCTAssertTrue(reset.isEnabled)

        closeGamutSheet()
    }

    /// Clicking Reset drives the live `SCNView` — runs only on Metal
    /// hosts, skipped on GPU-less runners so the same suite exercises
    /// 3D once CI has a GPU (#147).
    func testResetCameraInteractsWithScene() throws {
        guard hasGPU else { throw XCTSkip("No Metal") }
        openGamutSheet()

        let reset = waitFor("btnResetGamutCamera")
        reset.click()

        closeGamutSheet()
    }
}
