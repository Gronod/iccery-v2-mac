import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue #183 — Stage 2 paper-size / quality selection: seeding from
/// Stage 1 `pageSize`, the synthetic `Custom.<pt>x<pt>` entry, re-mirror
/// triggers, and `PrintOptions` wiring into `lp` argv.
/// `lpoptions`/`lp` are mock scripts in the test env's `cups-bin` — no
/// live CUPS is touched.
@MainActor
final class PrintSessionViewModelTests: XCTestCase {

    private var env: TestAppEnvironment!
    private var lpArgvURL: URL!

    override func setUp() async throws {
        env = try TestAppEnvironment.make()
        lpArgvURL = env.root.appendingPathComponent("lp-argv.log")
        try writeCupsFixtures()
    }

    override func tearDown() async throws {
        env?.cleanup()
        env = nil
        lpArgvURL = nil
    }

    private var binDir: URL {
        env.root.appendingPathComponent("cups-bin")
    }

    /// Mock `lpoptions -l` advertises paper sizes + a quality key;
    /// mock `lp` appends its argv to `lpArgvURL` for assertions.
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
              printf 'EPIJ_Qual/Print Quality: 301 302 *303 304\\n'
              exit 0
            fi
            printf "printer-info='Mock %s' printer-type=42\\n" "$queue"
            exit 0
            """
        let lp = """
            #!/bin/sh
            printf '%s\\n' "$*" >> "\(lpArgvURL.path)"
            exit 0
            """
        for (name, body) in [("lpoptions", lpoptions), ("lp", lp)] {
            let url = binDir.appendingPathComponent(name)
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
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

    /// `spool` emits the Stage 2 paper token and quality through
    /// `PrintOptions` → `lp` argv (`-o PageSize=`, `-o <qualityKey>=`).
    func testSpoolPassesPaperTokenAndQuality() async throws {
        let workflow = makeWorkflow()
        workflow.pageSize = .a4
        await loadCaps(workflow.print)
        workflow.print.selectedPaperSize = 4 // Letter
        workflow.print.selectedQuality = "301"

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

        let argv = await waitForFile(lpArgvURL)
        XCTAssertTrue(argv.contains("PageSize=Letter"), argv)
        XCTAssertTrue(argv.contains("EPIJ_Qual=301"), argv)
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
}
