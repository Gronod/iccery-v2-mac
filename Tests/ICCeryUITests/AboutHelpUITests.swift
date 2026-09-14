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
        if !openAbout.waitForExistence(timeout: 10) {
            // CI triage (#128): print the a11y tree so an empty or
            // unexpected hierarchy shows up directly in the job log.
            print("AXTREE-BEGIN windows=\(app.windows.count)\n\(app.debugDescription)\nAXTREE-END")
        }
        XCTAssertTrue(openAbout.exists)
        openAbout.click()

        _ = waitFor("aboutVersion", timeout: 10)
        XCTAssertTrue(element("aboutBuildDate").exists)

        let close = waitFor("closeAboutBtn", timeout: 10)
        close.click()

        XCTAssertFalse(element("aboutDialog").exists)
    }

    func testHelpOverlaysDoNotChangeSidebarHeight() throws {
        launchApp()

        let toggle = app.buttons["btnToggleAllHelp"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))

        // SDK 13.1 emits no AXGroup for the sidebar root, and an
        // identifier on the container clobbers child identifiers
        // (#130) — measure a stable sidebar child instead. Query the
        // pop-up by type: the Picker's "Preset" label inherits the same
        // identifier, so an .any query matches twice.
        let sidebarChild = app.popUpButtons["presetSelect"]
        XCTAssertTrue(sidebarChild.waitForExistence(timeout: 10))
        let before = sidebarChild.frame

        toggle.click()
        let after = sidebarChild.frame

        XCTAssertEqual(before, after,
                       "Toggling global help must not reflow the sidebar.")
        XCTAssertTrue(app.descendants(matching: .any)["openSettingsBtn"].exists)
    }

    func testAboutDialogShowsViewLicensesButton() throws {
        launchApp()

        let openAbout = app.buttons["openAboutBtn"]
        XCTAssertTrue(openAbout.waitForExistence(timeout: 10))
        openAbout.click()

        _ = waitFor("aboutVersion", timeout: 10)

        let viewLicensesBtn = waitFor("viewLicensesBtn", timeout: 10)
        XCTAssertTrue(viewLicensesBtn.exists)
        viewLicensesBtn.click()

        // License window should open as a sheet
        _ = waitFor("licenseWindow", timeout: 10)
        XCTAssertTrue(element("licenseWindow").exists)

        // Close license window
        let closeLicenseBtn = waitFor("closeLicenseBtn", timeout: 5)
        closeLicenseBtn.click()

        // License window should be dismissed
        XCTAssertFalse(element("licenseWindow").exists)

        // Close about dialog
        let closeAboutBtn = waitFor("closeAboutBtn", timeout: 5)
        closeAboutBtn.click()
        XCTAssertFalse(element("aboutDialog").exists)
    }

    func testLicenseWindowShowsICCeryLicense() throws {
        launchApp()

        let openAbout = app.buttons["openAboutBtn"]
        XCTAssertTrue(openAbout.waitForExistence(timeout: 10))
        openAbout.click()

        let viewLicensesBtn = waitFor("viewLicensesBtn", timeout: 10)
        viewLicensesBtn.click()

        _ = waitFor("licenseWindow", timeout: 10)

        // Verify ICCery license section exists
        let icceryLicenseSection = waitFor("icceryLicenseSectionHeader", timeout: 5)
        XCTAssertTrue(icceryLicenseSection.exists)

        // Verify ICCery license content contains key phrases
        let icceryLicenseContent = element("icceryLicenseSectionContent")
        XCTAssertTrue(icceryLicenseContent.waitForExistence(timeout: 5))
        let licenseText = icceryLicenseContent.value as? String ?? ""
        XCTAssertTrue(licenseText.contains("Copyright (c) 2026 Gordon Bolton"))
        XCTAssertTrue(licenseText.contains("All Rights Reserved"))
        XCTAssertTrue(licenseText.contains("AGPLv3"))

        // Close license window
        let closeLicenseBtn = waitFor("closeLicenseBtn", timeout: 5)
        closeLicenseBtn.click()

        let closeAboutBtn = waitFor("closeAboutBtn", timeout: 5)
        closeAboutBtn.click()
    }

    func testLicenseWindowShowsArgyllLicense() throws {
        launchApp()

        let openAbout = app.buttons["openAboutBtn"]
        XCTAssertTrue(openAbout.waitForExistence(timeout: 10))
        openAbout.click()

        let viewLicensesBtn = waitFor("viewLicensesBtn", timeout: 10)
        viewLicensesBtn.click()

        _ = waitFor("licenseWindow", timeout: 10)

        // Verify ArgyllCMS license section exists
        let argyllLicenseSection = waitFor("argyllLicenseSectionHeader", timeout: 5)
        XCTAssertTrue(argyllLicenseSection.exists)

        // Verify Argyll license content exists (may be fallback if License.txt not bundled)
        let argyllLicenseContent = element("argyllLicenseSectionContent")
        XCTAssertTrue(argyllLicenseContent.waitForExistence(timeout: 5))
        let licenseText = argyllLicenseContent.value as? String ?? ""
        // Should contain either the actual AGPLv3 license or the fallback notice
        XCTAssertTrue(licenseText.contains("AGPLv3") || licenseText.contains("GNU Affero General Public License") || licenseText.contains("fetch-argyll"))

        // Close license window
        let closeLicenseBtn = waitFor("closeLicenseBtn", timeout: 5)
        closeLicenseBtn.click()

        let closeAboutBtn = waitFor("closeAboutBtn", timeout: 5)
        closeAboutBtn.click()
    }

    func testLicenseWindowShowsAttributionLinks() throws {
        launchApp()

        let openAbout = app.buttons["openAboutBtn"]
        XCTAssertTrue(openAbout.waitForExistence(timeout: 10))
        openAbout.click()

        let viewLicensesBtn = waitFor("viewLicensesBtn", timeout: 10)
        viewLicensesBtn.click()

        _ = waitFor("licenseWindow", timeout: 10)

        // Verify attribution section exists
        let attributionHeader = waitFor("attributionHeader", timeout: 5)
        XCTAssertTrue(attributionHeader.exists)

        // Verify upstream link
        let upstreamLink = element("argyllUpstreamLink")
        XCTAssertTrue(upstreamLink.waitForExistence(timeout: 5))
        let upstreamLabel = upstreamLink.label
        XCTAssertTrue(upstreamLabel.contains("Graeme Gill") || upstreamLabel.contains("argyllcms.com"))

        // Verify fork link
        let forkLink = element("argyllForkLink")
        XCTAssertTrue(forkLink.waitForExistence(timeout: 5))
        let forkLabel = forkLink.label
        XCTAssertTrue(forkLabel.contains("Gronod") || forkLabel.contains("git.i3omb.com"))

        // Verify AGPL isolation note
        let isolationNote = element("agplIsolationNote")
        XCTAssertTrue(isolationNote.waitForExistence(timeout: 5))
        let noteText = isolationNote.value as? String ?? ""
        XCTAssertTrue(noteText.contains("isolated subprocesses") || noteText.contains("AGPLv3 isolation"))

        // Close license window
        let closeLicenseBtn = waitFor("closeLicenseBtn", timeout: 5)
        closeLicenseBtn.click()

        let closeAboutBtn = waitFor("closeAboutBtn", timeout: 5)
        closeAboutBtn.click()
    }
}
