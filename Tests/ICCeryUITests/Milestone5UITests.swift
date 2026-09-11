import Foundation
import XCTest

/// Milestone 5 UI tests — issues #23–#27.
@MainActor
final class Milestone5UITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!
    private var appDataDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui-m5-\(UUID().uuidString)")
        binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bin")
        workDir = testRoot.appendingPathComponent("work")
        appDataDir = testRoot.appendingPathComponent("AppData")

        try FileManager.default.createDirectory(
            at: workDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: appDataDir, withIntermediateDirectories: true)

        // Pre-stage a measured .ti3 so the wizard is already on Stage 4.
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
        app.descendants(matching: .any)[id]
    }

    private func waitFor(_ id: String, timeout: TimeInterval = 20) -> XCUIElement {
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

    /// Mock colprof produces a profile, unlocks Stage 5, and the
    /// mock profcheck reports Good.
    func testBuildProfileAndVerify() throws {
        launchApp()

        let create = waitFor("btnCreateProfile")
        XCTAssertTrue(create.isEnabled)
        create.click()

        _ = waitFor("btnVerifyProfile", timeout: 30)

        // The mock iccgamut should have written a .gam next to the profile.
        let gam = workDir.appendingPathComponent("mytarget.gam")
        let icc = workDir.appendingPathComponent("mytarget.icc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: icc.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: gam.path))

        app.buttons["btnVerifyProfile"].click()
        _ = waitFor("profcheckStatus", timeout: 30)

        let statusValue = app.staticTexts["profcheckStatus"].firstMatch.value as? String ?? ""
        XCTAssertTrue(
            statusValue.contains("Good") || statusValue.contains("Excellent"),
            "Expected verification status, got '\(statusValue)'"
        )
    }

    /// A failing colprof run surfaces through the session-wide wizard
    /// notice only — no duplicate stage-local error view (issue #80).
    func testProfileFailureShowsWizardNotice() throws {
        app.launchEnvironment["ICCERY_MOCK_COLPROF_EXIT"] = "2"
        launchApp()

        let create = waitFor("btnCreateProfile")
        XCTAssertTrue(create.isEnabled)
        create.click()

        let notice = element("noticeText")
        XCTAssertTrue(notice.waitForExistence(timeout: 20))
        XCTAssertTrue((notice.value as? String ?? "")
            .contains("Profile creation failed"))
        XCTAssertFalse(element("colprofLastError").exists)
    }
}
