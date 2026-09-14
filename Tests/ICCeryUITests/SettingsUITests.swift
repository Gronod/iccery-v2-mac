import Foundation
import XCTest

/// Settings sheet UI tests (issue #165).
///
/// The Verification thresholds once shared one non-wrapping `HStack` and
/// drew past the sheet's right clip on the macOS grouped `Form`. AX
/// existence cannot see clipping (#163), so containment is asserted on
/// real frame geometry against the sheet's bounds.
///
/// All three numeric fields also passed their default value as the
/// `TextField` label; inside an `HStack` row that label renders inline —
/// it is not a placeholder — producing "Stale after 30 [30] days". The
/// fields are now direct `Form` children, so the descriptive label
/// renders once in the label column and the box fills the control
/// column; `testNumericFieldsCarryLabelsNotDuplicatedValues` pins it.
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

    private func thresholdField(_ fieldID: String) -> XCUIElement {
        let field = sheet.textFields[fieldID]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "missing \(fieldID)")
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

    /// Both ΔE rows must render fully inside the 560×620 sheet: the
    /// label-column `StaticText`s and the control-column fields all sit
    /// within the sheet bounds, the two fields share the Form's control
    /// column margin, and the Warning row sits below the Good row so the
    /// two cannot overlap on one clipped line.
    ///
    /// The numeric fields are direct `Form` children, so macOS lifts
    /// each `TextField` label into the right-aligned label column and
    /// the editable box fills the control column — the same layout the
    /// Pickers use. The control column ends only ~3.5 pt inside the
    /// sheet (PopUpButtons reach it too), so the right-edge assertion is
    /// "inside the sheet", not the older 12 pt compact-field inset.
    func testVerificationRowsStayInsideSheet() throws {
        openSettings()

        let goodField = thresholdField("settingsDeltaEGood")
        let warningField = thresholdField("settingsDeltaEWarning")

        // Labels render as sibling staticTexts in the label column.
        let goodLabel = sheet.staticTexts["Good ΔE ≤"]
        let warningLabel = sheet.staticTexts["Warning ΔE ≤"]
        XCTAssertTrue(goodLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(warningLabel.waitForExistence(timeout: 5))

        // Left boundary: labels must be inside the sheet with >=12 pt inset
        XCTAssertTrue(goodLabel.frame.minX >= sheet.frame.minX + 12.0)
        XCTAssertTrue(warningLabel.frame.minX >= sheet.frame.minX + 12.0)

        // Right boundary: fields must not draw past the sheet's clip
        XCTAssertTrue(
            goodField.frame.maxX <= sheet.frame.maxX,
            "Good ΔE field clips the sheet's right edge")
        XCTAssertTrue(
            warningField.frame.maxX <= sheet.frame.maxX,
            "Warning ΔE field clips the sheet's right edge")

        // Vertical separation
        XCTAssertTrue(
            warningField.frame.minY > goodField.frame.minY,
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

    /// macOS renders a `TextField`'s first argument as a label, not a
    /// placeholder — inside the old `HStack` rows it drew inline, so the
    /// sheet read "Stale after 30 [30] days" / "Good ΔE ≤ 2.0 [2.0]".
    /// As direct `Form` children each label now renders exactly once, in
    /// the label column; no `staticText` may echo the field's value.
    func testNumericFieldsCarryLabelsNotDuplicatedValues() throws {
        openSettings()

        // (identifier, label-column text, rendered default value, the
        // literal that used to double-render as the field's label)
        // `value:` shows the formatted number — 2.0 renders as "2".
        let rows: [(id: String, label: String, value: String, dup: String)] = [
            ("settingsDeltaEGood", "Good ΔE ≤", "2", "2.0"),
            ("settingsDeltaEWarning", "Warning ΔE ≤", "5", "5.0"),
            ("settingsCalStaleDays", "Stale after (days)", "30", "30"),
        ]

        for spec in rows {
            let field = sheet.textFields[spec.id]
            XCTAssertTrue(field.waitForExistence(timeout: 10), "missing \(spec.id)")
            XCTAssertEqual(
                field.value as? String, spec.value,
                "\(spec.id) default value changed unexpectedly")
            XCTAssertTrue(
                sheet.staticTexts[spec.label].waitForExistence(timeout: 5),
                "\(spec.id) must render \"\(spec.label)\" once in the label column")
            for ghost in Set([spec.value, spec.dup]) {
                XCTAssertFalse(
                    sheet.staticTexts[ghost].exists,
                    "\(spec.id) must not render \"\(ghost)\" as a second label")
            }
            XCTAssertTrue(
                field.frame.maxX <= sheet.frame.maxX,
                "\(spec.id) field clips the sheet's right edge")
        }

        sheet.buttons["Cancel"].click()
        waitForSheetDismiss(timeout: 5)
    }
}
