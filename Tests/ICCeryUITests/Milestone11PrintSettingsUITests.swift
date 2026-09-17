import XCTest

/// Milestone 11 UI tests — issue #183 Stage 2 paper size + print
/// quality pickers. Runs against the same mock CUPS fixture binaries
/// as `Milestone3UITests`; the `NSPrintPanel` stays stubbed through
/// `ICCERY_TEST_PRINT_PANEL` (XCUITest cannot drive the system modal).
@MainActor
final class Milestone11PrintSettingsUITests: XCTestCase {

    private var app: XCUIApplication!
    private var testRoot: URL!
    private var binDir: URL!
    private var workDir: URL!
    private var spoolLogURL: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ui11-\(UUID().uuidString)")
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

    /// Drive the app through targen + printtarg so the print panel is
    /// live with a manifest.
    private func reachPrintPanel() {
        app.buttons["btnBrowse"].click()
        app.buttons["btnGenerate"].click()
        _ = waitFor("btnCreateLayout", timeout: 25)
        app.buttons["btnCreateLayout"].click()
        _ = waitFor("galleryPage-0", timeout: 25)
    }

    private func spoolLogLines() -> [String] {
        ((try? String(contentsOf: spoolLogURL, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    private func waitForSpoolLine(_ timeout: TimeInterval = 10) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let lines = spoolLogLines()
            if !lines.isEmpty { return lines.joined(separator: "\n") }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return spoolLogLines().joined(separator: "\n")
    }

    /// Poll until the spool log holds at least `count` lines.
    @discardableResult
    private func waitForSpoolLineCount(
        _ count: Int, timeout: TimeInterval = 15
    ) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let lines = spoolLogLines()
            if lines.count >= count { return lines }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return spoolLogLines()
    }

    // MARK: - Tests

    /// The paper-size and quality pickers exist with their new ids;
    /// the existing tray / media / orientation ids are unchanged (#183).
    func testPaperAndQualityPickersExist() throws {
        launchAppWithDefaults()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        XCTAssertTrue(element("printerPaperSizeSelect").exists)
        XCTAssertTrue(element("printerQualitySelect").exists)
        XCTAssertTrue(element("paperSizeGroup").exists)
        XCTAssertTrue(element("qualityGroup").exists)

        // Existing ids untouched. (`mediaTypeGroup` is not asserted —
        // stacked `.accessibilityIdentifier` modifiers collapse to the
        // last one, so it never resolved even before this change.)
        XCTAssertTrue(element("printerSelect").exists)
        XCTAssertTrue(element("printerTraySelect").exists)
        XCTAssertTrue(element("printerMediaTypeSelect").exists)
        XCTAssertTrue(element("btnOrientPortrait").exists)
        XCTAssertTrue(element("btnOrientLandscape").exists)
        XCTAssertTrue(element("btnPrinterProperties").exists)
    }

    /// The displayed selection of a picker — `AXTitle` for a popup
    /// button, falling back to label/value depending on how AppKit
    /// exposes the current item.
    private func selection(of id: String) -> String {
        let el = element(id)
        for candidate in [el.title, el.label, el.value as? String ?? ""] {
            if !candidate.isEmpty, candidate != el.identifier {
                return candidate
            }
        }
        return el.title
    }

    /// The paper picker seeds from Stage 1's `pageSize` (A4 default)
    /// and the quality picker from the driver's `*` default choice.
    func testPickersSeedFromStage1AndDriverDefault() throws {
        launchAppWithDefaults()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        _ = waitFor("printerPaperSizeSelect")
        _ = waitFor("printerQualitySelect")
        XCTAssertEqual(selection(of: "printerPaperSizeSelect"), "A4")
        XCTAssertEqual(selection(of: "printerQualitySelect"), "303")
    }

    /// #180 — the quality picker lists all seven Epson `EPIJ_Qual`
    /// codes in the driver's own order (308 between 303 and 304); no
    /// PPD is injected under UI testing so items show raw tokens.
    func testQualityPickerListsAllSevenDriverOptions() throws {
        launchAppWithDefaults()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        let picker = app.popUpButtons["printerQualitySelect"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.click()

        let expected = ["301", "302", "303", "308", "304", "305", "307"]
        for token in expected {
            XCTAssertTrue(
                app.menuItems[token].waitForExistence(timeout: 5),
                "Missing quality menu item \(token)")
        }
        let titles = app.menuItems.allElementsBoundByIndex
            .map(\.title)
            .filter { expected.contains($0) }
        XCTAssertEqual(titles, expected)

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }

    /// The stubbed panel result's captured `PageSize=`/`EPIJ_Qual=`
    /// apply back into the Stage 2 pickers and reach the recorded
    /// ticket writes (#201 — the real modal is never driven).
    func testPanelResultAppliesBackToPickers() throws {
        app.launchEnvironment["ICCERY_TEST_PRINT_PANEL"] = "ok"
        app.launchEnvironment["ICCERY_TEST_PANEL_OPTIONS"] =
            "PageSize=Letter EPIJ_Qual=305"
        launchAppWithDefaults()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        element("btnPrinterProperties").click()
        let notice = element("printNotificationText")
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue((notice.value as? String ?? "")
            .contains("Settings captured"))

        XCTAssertEqual(selection(of: "printerPaperSizeSelect"), "Letter")
        XCTAssertEqual(selection(of: "printerQualitySelect"), "305")

        app.buttons["btnPrintAll"].click()
        let log = waitForSpoolLine()
        XCTAssertTrue(log.contains("PageSize=Letter"), log)
        XCTAssertTrue(log.contains("EPIJ_Qual=305"), log)
    }

    /// #186 — the stubbed panel result's `orientation-requested=` /
    /// `MediaType=` apply back to the Stage 2 selections and reach the
    /// recorded ticket writes via the Stage 2 overrides (#201 D6).
    func testPanelResultAppliesBackOrientationAndMedia() throws {
        app.launchEnvironment["ICCERY_TEST_PRINT_PANEL"] = "ok"
        app.launchEnvironment["ICCERY_TEST_PANEL_OPTIONS"] =
            "PageSize=Letter EPIJ_Qual=305 orientation-requested=4 MediaType=PhotographicGlossy"
        launchAppWithDefaults()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        element("btnPrinterProperties").click()
        let notice = element("printNotificationText")
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue((notice.value as? String ?? "")
            .contains("Settings captured"))

        // `printerMediaTypeSelect` is the group's id — the popup is a
        // descendant (stacked identifiers collapse to the container).
        // The popup's AX title lags the binding — poll for the
        // apply-back value.
        let mediaPopup = element("printerMediaTypeSelect")
            .descendants(matching: .popUpButton).firstMatch
        XCTAssertTrue(mediaPopup.waitForExistence(timeout: 5))
        var mediaSelection = ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, mediaSelection != "PhotographicGlossy" {
            mediaSelection = [
                mediaPopup.title, mediaPopup.label,
                mediaPopup.value as? String ?? "",
            ].first { !$0.isEmpty } ?? ""
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(mediaSelection, "PhotographicGlossy")
        XCTAssertEqual(selection(of: "printerPaperSizeSelect"), "Letter")

        app.buttons["btnPrintAll"].click()
        let log = waitForSpoolLine()
        XCTAssertTrue(log.contains("orientation-requested=4"), log)
        XCTAssertTrue(log.contains("MediaType=PhotographicGlossy"), log)
        XCTAssertTrue(log.contains("PageSize=Letter"), log)
        XCTAssertTrue(log.contains("EPIJ_Qual=305"), log)
    }

    /// #214 — a fixture PPD pointing at a fixture `PDEData.dat` (via
    /// `ICCERY_CUPS_PPD_DIR`) constrains the quality picker to the
    /// media's allowed set; switching media re-filters and clamps the
    /// selection.
    func testQualityPickerFiltersByMediaConstraints() throws {
        let ppdDir = testRoot.appendingPathComponent("ppd")
        let epsonRoot = testRoot.appendingPathComponent("epson-driver")
        let datDir = epsonRoot.appendingPathComponent(
            "Machine/M.data/Contents/Resources")
        try FileManager.default.createDirectory(
            at: ppdDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: datDir, withIntermediateDirectories: true)
        try """
            *EPIJDriverBasePath: "\(epsonRoot.path)"
            *EPIJMachineBundleName: "M.data"
            """.write(
                to: ppdDir.appendingPathComponent("Mock_Epson_7450.ppd"),
                atomically: true, encoding: .utf8)
        try """
            *EPIJUIConstraint: *MediaType Stationery|*EPIJ_Qual 305
            *EPIJUIConstraint: *MediaType Stationery|*EPIJ_Qual 307
            *EPIJUIConstraint: *MediaType Stationery|*EPIJ_Qual 308
            *EPIJUIConstraint: *MediaType PhotographicGlossy|*EPIJ_Qual 301
            *EPIJUIConstraint: *MediaType PhotographicGlossy|*EPIJ_Qual 302
            *EPIJUIConstraint: *MediaType PhotographicGlossy|*EPIJ_Qual 303
            *EPIJUIConstraint: *MediaType PhotographicGlossy|*EPIJ_Qual 304
            """.write(
                to: datDir.appendingPathComponent("PDEData.dat"),
                atomically: true, encoding: .utf8)
        app.launchEnvironment["ICCERY_CUPS_PPD_DIR"] = ppdDir.path
        launchAppWithDefaults()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")

        let qualityPopup = app.popUpButtons["printerQualitySelect"]
        XCTAssertTrue(qualityPopup.waitForExistence(timeout: 10))

        // Default media Stationery → {301,302,303,304} only.
        qualityPopup.click()
        let stationeryExpected = ["301", "302", "303", "304"]
        for token in stationeryExpected {
            XCTAssertTrue(
                app.menuItems[token].waitForExistence(timeout: 5),
                "Missing quality menu item \(token)")
        }
        XCTAssertFalse(app.menuItems["307"].exists)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        // Switch to PhotographicGlossy → {305,307,308} in driver
        // order (308 first — lpoptions order), selection clamped.
        let mediaPopup = element("printerMediaTypeSelect")
            .descendants(matching: .popUpButton).firstMatch
        XCTAssertTrue(mediaPopup.waitForExistence(timeout: 5))
        mediaPopup.click()
        let glossyItem = app.menuItems["PhotographicGlossy"]
        XCTAssertTrue(glossyItem.waitForExistence(timeout: 5))
        glossyItem.click()

        qualityPopup.click()
        let glossyExpected = ["308", "305", "307"]
        for token in glossyExpected {
            XCTAssertTrue(
                app.menuItems[token].waitForExistence(timeout: 5),
                "Missing quality menu item \(token)")
        }
        let titles = app.menuItems.allElementsBoundByIndex
            .map(\.title)
            .filter { glossyExpected.contains($0) }
        XCTAssertEqual(titles, glossyExpected)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        // The stale pick (303) clamped to the first allowed token.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline,
              selection(of: "printerQualitySelect") != "308" {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(selection(of: "printerQualitySelect"), "308")
    }

    /// #201 D5 — per-page mode records one line per page; the
    /// `chkSingleSpoolJob` toggle collapses the job into a single
    /// request logged once with `pages=N`.
    func testSingleSpoolJobTogglesGranularity() throws {
        app.launchEnvironment["ICCERY_MOCK_PRINTTARG_PAGES"] = "2"
        launchAppWithDefaults()
        reachPrintPanel()
        _ = waitFor("printerStatusBadge")
        XCTAssertTrue(element("chkSingleSpoolJob").exists)

        // Default off → one request per page → one line per page.
        app.buttons["btnPrintAll"].click()
        var lines = waitForSpoolLineCount(2)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.contains("pages=1") },
                      lines.joined(separator: "\n"))

        // Toggle on → one request for all pages → a single line.
        element("chkSingleSpoolJob").click()
        app.buttons["btnPrintAll"].click()
        lines = waitForSpoolLineCount(3)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(
            lines.filter { $0.contains("pages=2") }.count, 1,
            lines.joined(separator: "\n"))
    }

    private func launchAppWithDefaults() {
        app.launch()
        app.activate()
    }
}
