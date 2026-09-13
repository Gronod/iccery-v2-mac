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

    /// Both ΔE rows must render fully inside the 560×620 sheet with at
    /// least the issue's 12 pt inset; the Warning row must sit below the
    /// Good row so the two fields cannot overlap on one clipped line.
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
        XCTAssertGreaterThanOrEqual(goodRow.frame.minX, sheet.frame.minX + 12)
        XCTAssertGreaterThanOrEqual(warningRow.frame.minX, sheet.frame.minX + 12)

        // Right boundary: text fields must be inside the sheet with >=12 pt inset
        XCTAssertLessThanOrEqual(
            goodField.frame.maxX, sheet.frame.maxX - 12,
            "Good ΔE field clips the sheet's right edge")
        XCTAssertLessThanOrEqual(
            warningField.frame.maxX, sheet.frame.maxX - 12,
            "Warning ΔE field clips the sheet's right edge")

        // Vertical separation
        XCTAssertGreaterThan(
            warningRow.frame.minY, goodRow.frame.minY,
            "thresholds must be two separate rows")

        // Controls are aligned with other form controls (e.g. calibration stale days field)
        let calField = sheet.textFields.matching(NSPredicate(format: "value == '30'")).firstMatch
        if calField.waitForExistence(timeout: 5) {
            XCTAssertEqual(goodField.frame.minX, calField.frame.minX, accuracy: 2.0,
                           "Good ΔE field should align with other form fields")
            XCTAssertEqual(warningField.frame.minX, calField.frame.minX, accuracy: 2.0,
                           "Warning ΔE field should align with other form fields")
        }

        // Other labels must not overflow the left boundary
        let defaultInstLabel = sheet.staticTexts["Default instrument"]
        XCTAssertTrue(defaultInstLabel.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(defaultInstLabel.frame.minX, sheet.frame.minX + 12,
                                    "Default instrument label must not overflow left edge")

        let bundledSidecarsLabel = sheet.staticTexts["Bundled sidecars"]
        XCTAssertTrue(bundledSidecarsLabel.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(bundledSidecarsLabel.frame.minX, sheet.frame.minX + 12,
                                    "Bundled sidecars label must not overflow left edge")

        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
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
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
    }
}
