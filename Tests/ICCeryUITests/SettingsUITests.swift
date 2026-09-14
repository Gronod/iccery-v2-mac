import Foundation
import XCTest

/// Settings sheet UI tests (issue #165).
///
/// The Verification thresholds once shared one non-wrapping `HStack` and
/// drew past the sheet's right clip on the macOS grouped `Form`. AX
/// existence cannot see clipping (#163), so containment is asserted on
/// real frame geometry against the sheet's bounds.
@MainActor
final class SettingsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = ["ICCERY_UI_TESTING": "1"]
        app.launch()
        app.activate()
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
    }

    /// Sheet content lives under `app.sheets`, outside the main window's
    /// a11y tree (Milestone2 pattern).
    private var sheet: XCUIElement {
        app.sheets.firstMatch
    }

    private func openSettings() {
        let gear = app.buttons["openSettingsBtn"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.click()
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
    }

    private func thresholdField(_ rowID: String) -> XCUIElement {
        let row = sheet.descendants(matching: .any)[rowID]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "missing \(rowID)")
        let field = row.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        return field
    }

    private func replaceFieldValue(_ field: XCUIElement, with text: String) {
        field.click()
        app.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private func waitForSheetDismiss(timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !sheet.exists { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(sheet.exists, "Expected sheet to disappear")
    }

    /// Both ΔE rows must render fully inside the 560×620 sheet with at
    /// least the issue's 12 pt inset, aligned with other form controls;
    /// the Warning row must sit below the Good row so the two fields
    /// cannot overlap on one clipped line.
    func testVerificationRowsStayInsideSheet() throws {
        openSettings()

        let goodRow = sheet.descendants(matching: .any)["settingsDeltaEGood"]
        let warningRow = sheet.descendants(matching: .any)["settingsDeltaEWarning"]
        XCTAssertTrue(goodRow.waitForExistence(timeout: 10))
        XCTAssertTrue(warningRow.waitForExistence(timeout: 10))

        let goodField = goodRow.textFields.firstMatch
        let warningField = warningRow.textFields.firstMatch
        XCTAssertTrue(goodField.waitForExistence(timeout: 10))
        XCTAssertTrue(warningField.waitForExistence(timeout: 10))

        // Left boundary: labels and rows must be inside the sheet with >=12 pt inset
        XCTAssertTrue(goodRow.frame.minX >= sheet.frame.minX + 12.0)
        XCTAssertTrue(warningRow.frame.minX >= sheet.frame.minX + 12.0)

        // Right boundary: text fields must be inside the sheet with >=12 pt inset
        XCTAssertTrue(
            goodField.frame.maxX <= sheet.frame.maxX - 12.0,
            "Good ΔE field clips the sheet's right edge")
        XCTAssertTrue(
            warningField.frame.maxX <= sheet.frame.maxX - 12.0,
            "Warning ΔE field clips the sheet's right edge")

        // Vertical separation
        XCTAssertTrue(
            warningRow.frame.minY > goodRow.frame.minY,
            "thresholds must be two separate rows")

        // Both threshold fields align at the same control column margin
        XCTAssertTrue(
            abs(goodField.frame.minX - warningField.frame.minX) <= 1.0,
            "Good and Warning ΔE fields should align at the same column margin")

        // Other labels must not overflow the left boundary
        let defaultInstLabel = sheet.staticTexts["Default instrument"]
        XCTAssertTrue(defaultInstLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(
            defaultInstLabel.frame.minX >= sheet.frame.minX + 12.0,
            "Default instrument label must not overflow left edge")

        let bundledSidecarsLabel = sheet.staticTexts["Bundled sidecars"]
        XCTAssertTrue(bundledSidecarsLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(
            bundledSidecarsLabel.frame.minX >= sheet.frame.minX + 12.0,
            "Bundled sidecars label must not overflow left edge")

        sheet.buttons["Cancel"].click()
        waitForSheetDismiss(timeout: 5)
    }

    /// `warning <= good` fails `AppSettings.validate()` and keeps the
    /// sheet open with the contract error text; restoring valid values
    /// lets Save dismiss (issue #165 acceptance, strings are the #5
    /// contract).
    func testDeltaEValidationBlocksSaveThenValidSaveDismisses() throws {
        openSettings()

        replaceFieldValue(thresholdField("settingsDeltaEWarning"), with: "1")
        sheet.buttons["Save"].click()

        let error = sheet.staticTexts[
            "Good ΔE threshold must be strictly less than the warning threshold."
        ]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(sheet.exists, "invalid ΔE must not dismiss the sheet")

        replaceFieldValue(thresholdField("settingsDeltaEWarning"), with: "5")
        sheet.buttons["Save"].click()
        waitForSheetDismiss(timeout: 10)
    }
}
