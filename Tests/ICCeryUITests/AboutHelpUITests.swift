import XCTest

/// About and help chrome UI tests (issue #31).
@MainActor
final class AboutHelpUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = ["ICCERY_UI_TESTING": "1"]
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
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

    private func launchApp() {
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 10) {
            app.activate()
        }
    }

    func testAboutDialogShowsVersionAndBuildDate() throws {
        launchApp()

        let openAbout = app.buttons["openAboutBtn"]
        XCTAssertTrue(openAbout.waitForExistence(timeout: 10))
        openAbout.click()

        _ = waitFor("aboutVersion", timeout: 10)
        XCTAssertTrue(element("aboutBuildDate").exists)

        let close = app.sheets.firstMatch.buttons["closeAboutBtn"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.click()

        XCTAssertFalse(element("aboutDialog").exists)
    }

    func testHelpOverlaysDoNotChangeSidebarHeight() throws {
        launchApp()

        let toggle = app.buttons["btnToggleAllHelp"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))

        let sidebar = app.groups.containing(.button, identifier: "openSettingsBtn").element
        let before = sidebar.frame

        toggle.click()
        let after = sidebar.frame

        XCTAssertEqual(before.size.height, after.size.height,
                       "Toggling global help must not reflow the sidebar height.")
        XCTAssertTrue(app.descendants(matching: .any)["openSettingsBtn"].exists)
    }
}
