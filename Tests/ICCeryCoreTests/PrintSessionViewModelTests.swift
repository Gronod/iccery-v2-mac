import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue #183 — Stage 2 paper-size / quality selection: seeding from
/// Stage 1 `pageSize`, the synthetic `Custom.<pt>x<pt>` entry, re-mirror
/// triggers, and `TargetPrintOverrides` wiring into the resolved
/// ticket writes (#201 — the `RecordingTargetSpooler` seam replaces
/// the deleted `lp` argv log).
/// `lpoptions` is a mock script in the test env's `cups-bin` — no
/// live CUPS is touched.
@MainActor
final class PrintSessionViewModelTests: XCTestCase {

    private var env: TestAppEnvironment!
    private var spoolLogURL: URL!

    override func setUp() async throws {
        env = try TestAppEnvironment.make()
        spoolLogURL = env.root.appendingPathComponent("spool.log")
        try writeCupsFixtures()
    }

    override func tearDown() async throws {
        env?.cleanup()
        env = nil
        spoolLogURL = nil
    }

    private var binDir: URL {
        env.root.appendingPathComponent("cups-bin")
    }

    /// Mock `lpoptions -l` advertises paper sizes + a quality key —
    /// the queue's option-key roster feeds media/quality detection.
    private func writeCupsFixtures() throws {
        try FileManager.default.createDirectory(
            at: binDir, withIntermediateDirectories: true)
        let lpoptions = """
            #!/bin/sh
            list=0
            queue=""
            for arg in "$@"; do
              case "$arg" in
                -l) list=1 ;;
                -*) ;;
                *) queue="$arg" ;;
              esac
            done
            if [ "$list" = "1" ]; then
              printf 'PageSize/Media Size: 4x6 5x7 *A4 Letter Legal Custom.WIDTHxHEIGHT\\n'
              printf 'InputSlot/Media Source: Auto *Main Rear\\n'
              printf 'MediaType/Media Type: *Stationery Glossy Matte\\n'
              printf 'EPIJ_Qual/Print Quality: 301 302 *303 308 304 305 307\\n'
              exit 0
            fi
            printf "printer-info='Mock %s' printer-type=42\\n" "$queue"
            exit 0
            """
        let url = binDir.appendingPathComponent("lpoptions")
        try lpoptions.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeWorkflow() -> TargetWorkflowViewModel {
        TargetWorkflowViewModel(environment: env.environment)
    }

    private func loadCaps(
        _ vm: PrintSessionViewModel, queue: String = "Mock_Q"
    ) async {
        vm.selectedPrinter = queue
        await vm.reloadSelectedCapabilities()
    }

    private func waitForFile(
        _ url: URL, timeout: TimeInterval = 10
    ) async -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               !text.isEmpty {
                return text
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Seeding / mirror

    /// `pageSize = .a4` matches the capability named "A4" → its id.
    func testSeedMatchesPageSizeRawValue() async {
        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)

        XCTAssertEqual(workflow.pageSize, .a4)
        XCTAssertEqual(workflow.print.selectedPaperSize, 3)
        // Quality seeds from the `*` default on caps load.
        XCTAssertEqual(workflow.print.selectedQuality, "303")
        // All seven Epson codes enumerate in driver order (#180).
        XCTAssertEqual(workflow.print.printerCaps.qualities.map(\.id),
            ["301", "302", "303", "308", "304", "305", "307"])
    }

    /// `.custom` → synthetic `id: 0` entry whose token is the
    /// dimensions in **points** (mm × 72/25.4): 210×297 → `Custom.595x842`.
    func testSeedCustomPageSizeSyntheticEntry() async {
        let workflow = makeWorkflow()
        workflow.pageSize = .custom
        workflow.customPageW = 210
        workflow.customPageH = 297
        await loadCaps(workflow.print)

        XCTAssertEqual(workflow.print.selectedPaperSize, 0)
        let synthetic = workflow.print.printerCaps.paperSizes
            .first { $0.id == 0 }
        XCTAssertEqual(synthetic?.name, "Custom.595x842")
        XCTAssertEqual(workflow.print.selectedPaperSizeToken, "Custom.595x842")
    }

    /// A `workflow.pageSize` change re-mirrors the picker.
    func testReseedOnPageSizeChange() async {
        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        XCTAssertEqual(workflow.print.selectedPaperSize, 3)

        workflow.pageSize = .letter
        workflow.print.seedPaperSelection()
        XCTAssertEqual(workflow.print.selectedPaperSize, 4)
    }

    /// A user pick survives unrelated publishes — re-seed only fires
    /// on pageSize / printer / caps triggers (#183, R14).
    func testUserEditPreservedAcrossUnrelatedPublishes() async {
        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        workflow.print.selectedPaperSize = 5

        workflow.print.selectedTray = 2
        workflow.print.printOrientation = "landscape"
        workflow.print.printNotice = Notice(kind: .info, text: "x")

        XCTAssertEqual(workflow.print.selectedPaperSize, 5)
    }

    /// A printer change re-seeds from `workflow.pageSize` after the
    /// capabilities reload (the picker re-mirrors, not guesses).
    func testPrinterChangeReseeds() async {
        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        workflow.print.selectedPaperSize = 5
        workflow.print.selectedQuality = "301"

        // The view nils quality on printer change before reloading —
        // the VM re-seeds `when nil` only (#183 contract).
        workflow.print.selectedPrinter = "Other_Q"
        workflow.print.selectedQuality = nil
        await workflow.print.reloadSelectedCapabilities()

        XCTAssertEqual(workflow.print.selectedPaperSize, 3)
        XCTAssertEqual(workflow.print.selectedQuality, "303")
    }

    /// A pageSize with no capability match leaves the pick nil —
    /// never a guessed id.
    func testSeedNoMatchLeavesNil() async {
        let workflow = makeWorkflow()
        workflow.pageSize = .a2
        await loadCaps(workflow.print)
        XCTAssertNil(workflow.print.selectedPaperSize)
        XCTAssertNil(workflow.print.selectedPaperSizeToken)
    }

    // MARK: - Spool wiring

    /// `spool` resolves the Stage 2 paper token and quality into the
    /// ticket writes (`PageSize=`, `<qualityKey>=`) recorded by the
    /// DEBUG spool seam (#201 D8).
    func testSpoolPassesPaperTokenAndQuality() async throws {
        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        workflow.print.selectedPaperSize = 4 // Letter
        workflow.print.selectedQuality = "301"
        workflow.print.spooler = RecordingTargetSpooler(
            logURL: spoolLogURL)

        let tiff = env.root.appendingPathComponent("page1.tif")
        try Data([0x49, 0x49]).write(to: tiff)
        let page = GalleryPage(
            index: 0,
            page: PrinttargPage(
                filename: "page1.tif", patches: 10,
                widthMm: 210, heightMm: 297),
            fileURL: tiff, previewPNG: nil, previewError: nil)
        let result = PrinttargResult(
            ti2URL: env.root.appendingPathComponent("target.ti2"),
            manifest: PrinttargManifest(pages: [page.page]),
            pages: [page])
        workflow.print.printAllPages(from: result)

        let log = await waitForFile(spoolLogURL)
        XCTAssertTrue(log.contains("PageSize=Letter"), log)
        XCTAssertTrue(log.contains("EPIJ_Qual=301"), log)
    }

    /// #201 — the stubbed panel never produces a `PrintTicket`, so a
    /// spool with `capturedTickets` empty must still resolve every
    /// Stage 2 write (the default UI-test path).
    func testSpoolWithoutTicketResolvesStage2Writes() async throws {
        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        workflow.print.spooler = RecordingTargetSpooler(
            logURL: spoolLogURL)
        XCTAssertTrue(workflow.print.capturedTickets.isEmpty)

        let tiff = env.root.appendingPathComponent("page1.tif")
        try Data([0x49, 0x49]).write(to: tiff)
        let page = GalleryPage(
            index: 0,
            page: PrinttargPage(
                filename: "page1.tif", patches: 10,
                widthMm: 210, heightMm: 297),
            fileURL: tiff, previewPNG: nil, previewError: nil)
        let result = PrinttargResult(
            ti2URL: env.root.appendingPathComponent("target.ti2"),
            manifest: PrinttargManifest(pages: [page.page]),
            pages: [page])
        workflow.print.printAllPages(from: result)

        let log = await waitForFile(spoolLogURL)
        XCTAssertTrue(log.contains("pages=1"), log)
        XCTAssertTrue(log.contains("PageSize=A4"), log)
        XCTAssertTrue(log.contains("EPIJ_Qual=303"), log)
        XCTAssertTrue(log.contains("MediaType=Stationery"), log)
        XCTAssertTrue(log.contains("orientation-requested=3"), log)
        XCTAssertTrue(log.contains(
            "AP_ColorMatchingMode=AP_ApplicationColorMatching"), log)
        XCTAssertTrue(log.contains(
            "PMColorMatchingMode=APCustomColorMatching"), log)
    }

    // MARK: - Panel apply-back (stubbed NSPrintPanel)

    /// The stubbed panel's captured `PageSize=`/`EPIJ_Qual=` apply back
    /// to `selectedPaperSize`/`selectedQuality` (#183 capture-return).
    func testPanelResultAppliesBackSelections() async throws {
        setenv("ICCERY_UI_TESTING", "1", 1)
        setenv("ICCERY_TEST_PRINT_PANEL", "ok", 1)
        setenv("ICCERY_TEST_PANEL_OPTIONS",
               "PageSize=Letter EPIJ_Qual=305", 1)
        defer {
            unsetenv("ICCERY_UI_TESTING")
            unsetenv("ICCERY_TEST_PRINT_PANEL")
            unsetenv("ICCERY_TEST_PANEL_OPTIONS")
        }

        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        XCTAssertEqual(workflow.print.selectedPaperSize, 3)
        XCTAssertEqual(workflow.print.selectedQuality, "303")

        workflow.print.openPrinterPreferences()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              workflow.print.selectedPaperSize != 4
              || workflow.print.selectedQuality != "305" {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(workflow.print.selectedPaperSize, 4)
        XCTAssertEqual(workflow.print.selectedQuality, "305")
    }

    /// #186 — the captured `orientation-requested`/media token apply
    /// back to `printOrientation`/`selectedMediaType`, and a dialog
    /// result never mutates `workflow.pageSize` (printtarg layout).
    func testPanelResultAppliesBackOrientationAndMedia() async throws {
        setenv("ICCERY_UI_TESTING", "1", 1)
        setenv("ICCERY_TEST_PRINT_PANEL", "ok", 1)
        setenv("ICCERY_TEST_PANEL_OPTIONS",
               "orientation-requested=4 MediaType=Glossy", 1)
        defer {
            unsetenv("ICCERY_UI_TESTING")
            unsetenv("ICCERY_TEST_PRINT_PANEL")
            unsetenv("ICCERY_TEST_PANEL_OPTIONS")
        }

        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        XCTAssertEqual(workflow.print.printOrientation, "portrait")
        XCTAssertEqual(workflow.print.selectedMediaType, "Stationery")

        workflow.print.openPrinterPreferences()
        await waitForNotice(workflow.print, containing: "Settings captured")
        XCTAssertEqual(workflow.print.printOrientation, "landscape")
        XCTAssertEqual(workflow.print.selectedMediaType, "Glossy")
        XCTAssertEqual(workflow.pageSize, .a4)
    }

    /// #186 — a captured `PageSize` token with no capability match
    /// leaves `selectedPaperSize` unchanged (never a guessed id).
    func testPanelResultUnknownPaperLeavesSelection() async throws {
        setenv("ICCERY_UI_TESTING", "1", 1)
        setenv("ICCERY_TEST_PRINT_PANEL", "ok", 1)
        setenv("ICCERY_TEST_PANEL_OPTIONS", "PageSize=Bogus", 1)
        defer {
            unsetenv("ICCERY_UI_TESTING")
            unsetenv("ICCERY_TEST_PRINT_PANEL")
            unsetenv("ICCERY_TEST_PANEL_OPTIONS")
        }

        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        XCTAssertEqual(workflow.print.selectedPaperSize, 3)

        workflow.print.openPrinterPreferences()
        await waitForNotice(workflow.print, containing: "Settings captured")
        XCTAssertEqual(workflow.print.selectedPaperSize, 3)
    }

    /// #186 — a stub result pointing at another queue in `printers`
    /// switches `selectedPrinter` and reloads its capabilities.
    func testPanelResultSwitchesToKnownQueue() async throws {
        setenv("ICCERY_UI_TESTING", "1", 1)
        setenv("ICCERY_TEST_PRINT_PANEL", "ok", 1)
        setenv("ICCERY_TEST_PANEL_OPTIONS", "PageSize=Letter", 1)
        setenv("ICCERY_TEST_PANEL_PRINTER", "Other_Q", 1)
        defer {
            unsetenv("ICCERY_UI_TESTING")
            unsetenv("ICCERY_TEST_PRINT_PANEL")
            unsetenv("ICCERY_TEST_PANEL_OPTIONS")
            unsetenv("ICCERY_TEST_PANEL_PRINTER")
        }

        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        workflow.print.printers = [
            Printer(name: "Mock_Q", isDefault: true),
            Printer(name: "Other_Q"),
        ]
        await loadCaps(workflow.print)

        workflow.print.openPrinterPreferences()
        await waitForNotice(
            workflow.print, containing: "Settings captured for Other_Q")
        XCTAssertEqual(workflow.print.selectedPrinter, "Other_Q")
        // Caps reloaded for the new queue: paper re-seeded, then the
        // captured PageSize applied back onto the new caps.
        XCTAssertEqual(workflow.print.selectedPaperSize, 4)
        XCTAssertEqual(workflow.print.capturedCupsOptions["Other_Q"],
            "PageSize=Letter")
    }

    /// #186 — a stub result naming a queue absent from `printers`
    /// leaves the selection on the opened queue.
    func testPanelResultGhostQueueIgnored() async throws {
        setenv("ICCERY_UI_TESTING", "1", 1)
        setenv("ICCERY_TEST_PRINT_PANEL", "ok", 1)
        setenv("ICCERY_TEST_PANEL_PRINTER", "Ghost_Q", 1)
        defer {
            unsetenv("ICCERY_UI_TESTING")
            unsetenv("ICCERY_TEST_PRINT_PANEL")
            unsetenv("ICCERY_TEST_PANEL_PRINTER")
        }

        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        workflow.print.printers = [Printer(name: "Mock_Q", isDefault: true)]
        await loadCaps(workflow.print)

        workflow.print.openPrinterPreferences()
        await waitForNotice(
            workflow.print, containing: "Settings captured for Mock_Q")
        XCTAssertEqual(workflow.print.selectedPrinter, "Mock_Q")
    }

    /// #186 — cancel returns `nil`: info notice, no field changes.
    func testPanelCancelLeavesSelections() async throws {
        setenv("ICCERY_UI_TESTING", "1", 1)
        setenv("ICCERY_TEST_PRINT_PANEL", "cancel", 1)
        defer {
            unsetenv("ICCERY_UI_TESTING")
            unsetenv("ICCERY_TEST_PRINT_PANEL")
        }

        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        workflow.print.printOrientation = "landscape"

        workflow.print.openPrinterPreferences()
        await waitForNotice(workflow.print, containing: "cancelled")
        XCTAssertEqual(workflow.print.selectedPaperSize, 3)
        XCTAssertEqual(workflow.print.selectedQuality, "303")
        XCTAssertEqual(workflow.print.selectedMediaType, "Stationery")
        XCTAssertEqual(workflow.print.printOrientation, "landscape")
        XCTAssertTrue(workflow.print.capturedCupsOptions.isEmpty)
    }

    // MARK: - Media-aware quality filtering (#214)

    /// Constrains the loaded fixture caps: `Stationery` allows
    /// {301,302,303,304}, `Glossy` allows {305,307}, `Matte` is
    /// unconstrained. Mirrors the Epson `EPIJUIConstraint` matrix.
    private func constrainCaps(_ vm: PrintSessionViewModel) {
        var caps = vm.printerCaps
        caps.qualityIDsByMediaType = [
            "Stationery": ["301", "302", "303", "304"],
            "Glossy": ["305", "307"],
        ]
        vm.printerCaps = caps
    }

    /// Media switch → an invalid quality pick re-seeds to the first
    /// allowed choice; the picker source shrinks to the media's set.
    func testMediaChangeClampsInvalidQuality() async {
        let workflow = makeWorkflow()
        await loadCaps(workflow.print)
        constrainCaps(workflow.print)
        XCTAssertEqual(workflow.print.selectedMediaType, "Stationery")
        XCTAssertEqual(workflow.print.selectedQuality, "303")

        workflow.print.selectedMediaType = "Glossy"
        XCTAssertEqual(workflow.print.selectedQuality, "305")
        XCTAssertEqual(workflow.print.availableQualities.map(\.id),
            ["305", "307"])
    }

    /// A still-valid pick survives a media switch; an unconstrained
    /// media keeps the pick too.
    func testMediaChangeKeepsValidQuality() async {
        let workflow = makeWorkflow()
        await loadCaps(workflow.print)
        constrainCaps(workflow.print)
        workflow.print.selectedQuality = "302"

        workflow.print.selectedMediaType = "Matte" // unconstrained
        XCTAssertEqual(workflow.print.selectedQuality, "302")

        workflow.print.selectedMediaType = "Glossy" // 302 invalid
        XCTAssertEqual(workflow.print.selectedQuality, "305")
        workflow.print.selectedQuality = "307"
        workflow.print.selectedMediaType = "Stationery" // 307 invalid
        // Driver default 303 is allowed there → preferred over first.
        XCTAssertEqual(workflow.print.selectedQuality, "303")
    }

    /// Seeding lands inside the allowed set even when the driver
    /// default quality is invalid for the first media — end to end
    /// through `CupsService.capabilities(for:)` + a fixture
    /// `PDEData.dat` (#214).
    func testQualitySeedRespectsMediaMap() async throws {
        let ppdDir = env.root.appendingPathComponent("ppd")
        let epsonRoot = env.root.appendingPathComponent("epson-driver")
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
                to: ppdDir.appendingPathComponent("Mock_Q.ppd"),
                atomically: true, encoding: .utf8)
        // Stationery forbids everything except 305/307 — including the
        // `lpoptions` default 303.
        try """
            *EPIJUIConstraint: *MediaType Stationery|*EPIJ_Qual 301
            *EPIJUIConstraint: *MediaType Stationery|*EPIJ_Qual 302
            *EPIJUIConstraint: *MediaType Stationery|*EPIJ_Qual 303
            *EPIJUIConstraint: *MediaType Stationery|*EPIJ_Qual 308
            *EPIJUIConstraint: *MediaType Stationery|*EPIJ_Qual 304
            """.write(
                to: datDir.appendingPathComponent("PDEData.dat"),
                atomically: true, encoding: .utf8)

        var environment = env.environment
        environment = AppEnvironment(
            stateStore: environment.stateStore,
            settingsStore: environment.settingsStore,
            presetStore: environment.presetStore,
            runner: environment.runner,
            cupsService: CupsService(
                processManager: ProcessManager(),
                binaryDir: binDir, ppdDir: ppdDir),
            historyStore: environment.historyStore,
            mediaStore: environment.mediaStore,
            recentProjectsStore: environment.recentProjectsStore)
        let workflow = TargetWorkflowViewModel(environment: environment)
        workflow.print.selectedPrinter = "Mock_Q"
        await workflow.print.reloadSelectedCapabilities()

        XCTAssertEqual(workflow.print.selectedMediaType, "Stationery")
        XCTAssertEqual(workflow.print.printerCaps
            .qualityIDsByMediaType["Stationery"], ["305", "307"])
        // 303 is the driver default but invalid on Stationery → 305.
        XCTAssertEqual(workflow.print.selectedQuality, "305")
        XCTAssertEqual(workflow.print.availableQualities.map(\.id),
            ["305", "307"])
    }

    /// No constraint map → every quality stays selectable on every
    /// media (the pre-#214 behaviour, by design for unknown drivers).
    func testUnconstrainedDriverKeepsAllQualities() async {
        let workflow = makeWorkflow()
        await loadCaps(workflow.print)
        workflow.print.selectedMediaType = "Glossy"
        XCTAssertEqual(workflow.print.availableQualities.map(\.id),
            ["301", "302", "303", "308", "304", "305", "307"])
        XCTAssertEqual(workflow.print.selectedQuality, "303")
    }

    /// A captured quality invalid for the captured media is dropped —
    /// the clamped selection stands.
    func testPanelResultInvalidQualityDropped() async throws {
        setenv("ICCERY_UI_TESTING", "1", 1)
        setenv("ICCERY_TEST_PRINT_PANEL", "ok", 1)
        setenv("ICCERY_TEST_PANEL_OPTIONS", "EPIJ_Qual=305", 1)
        defer {
            unsetenv("ICCERY_UI_TESTING")
            unsetenv("ICCERY_TEST_PRINT_PANEL")
            unsetenv("ICCERY_TEST_PANEL_OPTIONS")
        }

        let workflow = makeWorkflow()
        await loadCaps(workflow.print)
        constrainCaps(workflow.print) // Stationery forbids 305
        XCTAssertEqual(workflow.print.selectedQuality, "303")

        workflow.print.openPrinterPreferences()
        await waitForNotice(workflow.print, containing: "Settings captured")
        XCTAssertEqual(workflow.print.selectedQuality, "303")
    }

    /// `makeRequest` substitutes a stale-invalid quality before the
    /// ticket is written — the last gate before the driver (#214).
    func testSpoolSubstitutesStaleQuality() async throws {
        let workflow = makeWorkflow()
        await loadCaps(workflow.print)
        constrainCaps(workflow.print)
        workflow.print.selectedMediaType = "Glossy"
        workflow.print.selectedQuality = "308" // stale, invalid
        workflow.print.spooler = RecordingTargetSpooler(
            logURL: spoolLogURL)

        let tiff = env.root.appendingPathComponent("page1.tif")
        try Data([0x49, 0x49]).write(to: tiff)
        let page = GalleryPage(
            index: 0,
            page: PrinttargPage(
                filename: "page1.tif", patches: 10,
                widthMm: 210, heightMm: 297),
            fileURL: tiff, previewPNG: nil, previewError: nil)
        workflow.print.printPage(page)

        let log = await waitForFile(spoolLogURL)
        XCTAssertTrue(log.contains("EPIJ_Qual=305"), log)
        XCTAssertFalse(log.contains("EPIJ_Qual=308"), log)
    }

    /// Poll until the panel task posts a notice whose text contains
    /// `fragment` (the Task-completion signal for `nil` results too).
    private func waitForNotice(
        _ vm: PrintSessionViewModel,
        containing fragment: String,
        timeout: TimeInterval = 10
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = vm.printNotice?.text, text.contains(fragment) {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out waiting for notice containing '\(fragment)'")
    }
}
