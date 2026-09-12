import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue #146 — `MediaLibraryViewModel` apply / capture / staleness
/// under an isolated `TestAppEnvironment` with a mock CUPS `bin` dir.
@MainActor
final class MediaLibraryViewModelTests: XCTestCase {

    // CTI3 fixture mirrored from CalibrationStoreTests.
    private static let sampleCal = """
    CTI3
    DESCRIPTOR "Test printer"
    COLOR_REP "RGB"
    DEVICE_CLASS "OUTPUT"
    MAX_TAC "300"
    NUMBER_OF_FIELDS 5
    NUMBER_OF_SETS 3
    BEGIN_DATA_FORMAT
    SAMPLE_ID INPUT_VALUE R G B
    END_DATA_FORMAT
    BEGIN_DATA
    1 0 0 0 0
    2 128 64 64 64
    3 255 255 255 255
    END_DATA
    """

    /// Same fixture plus an old CREATED keyword so the age check fires.
    private static let staleCal = """
    CTI3
    DESCRIPTOR "Test printer"
    CREATED "2020-01-01T00:00:00Z"
    COLOR_REP "RGB"
    DEVICE_CLASS "OUTPUT"
    NUMBER_OF_FIELDS 5
    NUMBER_OF_SETS 3
    BEGIN_DATA_FORMAT
    SAMPLE_ID INPUT_VALUE R G B
    END_DATA_FORMAT
    BEGIN_DATA
    1 0 0 0 0
    2 128 64 64 64
    3 255 255 255 255
    END_DATA
    """

    private var env: TestAppEnvironment!
    private var workflow: TargetWorkflowViewModel!
    private var media: MediaLibraryViewModel!

    override func setUp() async throws {
        env = try TestAppEnvironment.make()
        try installMockCups()
        workflow = TargetWorkflowViewModel(environment: env.environment)
        media = workflow.media
        await media.reloadAsync()
    }

    override func tearDown() async throws {
        env?.cleanup()
        env = nil
        workflow = nil
        media = nil
    }

    /// Mock `lpstat`/`lpoptions` inside the env's `cups-bin` (the
    /// `CupsService.binaryDir` `TestAppEnvironment` points at). Queues:
    /// `Mock_Queue` (default) and `Other_Queue`.
    private func installMockCups() throws {
        let bin = env.root.appendingPathComponent("cups-bin")
        try FileManager.default.createDirectory(
            at: bin, withIntermediateDirectories: true)

        let lpstat = """
        #!/bin/sh
        case "$1" in
          -e) printf 'Mock_Queue\\nOther_Queue\\n' ;;
          -p) printf 'printer Mock_Queue is idle.\\nprinter Other_Queue is idle.\\n' ;;
          -d) printf 'system default destination: Mock_Queue\\n' ;;
        esac
        exit 0
        """
        let lpoptions = """
        #!/bin/sh
        list=0
        queue=""
        for arg in "$@"; do
          case "$arg" in
            -l) list=1 ;;
            -p) ;;
            *) queue="$arg" ;;
          esac
        done
        if [ "$list" = "1" ]; then
          printf 'PageSize/Media Size: *A4 Letter\\n'
          printf 'MediaType/Media Type: *Stationery Glossy\\n'
          exit 0
        fi
        printf "printer-info='Mock %s' printer-type=42\\n" "$queue"
        exit 0
        """
        for (name, body) in ["lpstat": lpstat, "lpoptions": lpoptions] {
            let url = bin.appendingPathComponent(name)
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    private func writeCal(
        _ contents: String = MediaLibraryViewModelTests.sampleCal,
        named name: String = "recipe.cal"
    ) throws -> String {
        let url = env.root.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func makeRecipe(
        id: String = "recipe-t1",
        printerID: String = "Mock_Queue",
        colourSpace: String = "rgb",
        presetID: String = "preset-std-rgb",
        calibrationURL: String? = nil,
        applyCalibration: Bool = false
    ) -> MediaRecipe {
        MediaRecipe(
            id: id,
            name: "Test Recipe",
            printerID: printerID,
            printerDisplayName: "Mock Queue Display",
            paperName: "Rag",
            inkSet: "PK",
            colourSpace: colourSpace,
            presetID: presetID,
            calibrationURL: calibrationURL,
            applyCalibration: applyCalibration)
    }

    private func seed(_ recipe: MediaRecipe) async throws {
        try await env.environment.mediaStore.upsert(recipe)
        await media.reloadAsync()
    }

    // MARK: - Apply

    func testApplyHappyPath() async throws {
        let calPath = try writeCal()
        let r = makeRecipe(
            calibrationURL: calPath, applyCalibration: true)
        try await seed(r)

        let applied = await media.apply(r)

        XCTAssertTrue(applied)
        XCTAssertEqual(workflow.print.selectedPrinter, "Mock_Queue")
        XCTAssertEqual(workflow.wizard.printerName, "Mock Queue Display")
        XCTAssertTrue(workflow.profile.applyCalibration)
        XCTAssertEqual(workflow.profile.calibrationFile, calPath)
        XCTAssertEqual(media.selectedRecipeID, r.id)
        XCTAssertEqual(workflow.selectedPresetID, "preset-std-rgb")
        XCTAssertEqual(
            workflow.buildPrinttargConfig().calibrationFile, calPath)
    }

    func testApplyMissingPresetRefuses() async throws {
        let r = makeRecipe(presetID: "preset-nonexistent")
        try await seed(r)

        let applied = await media.apply(r)

        XCTAssertFalse(applied)
        XCTAssertEqual(media.selectedRecipeID, "none")
        XCTAssertEqual(workflow.selectedPresetID, "none")
        XCTAssertTrue(
            workflow.wizard.notice?.text.contains("no longer exists") == true)
    }

    func testApplyColourSpaceMismatchRefuses() async throws {
        let r = makeRecipe(colourSpace: "cmyk", presetID: "preset-std-rgb")
        try await seed(r)

        let applied = await media.apply(r)

        XCTAssertFalse(applied)
        XCTAssertEqual(media.selectedRecipeID, "none")
        XCTAssertTrue(
            workflow.wizard.notice?.text.contains("colour space") == true)
    }

    func testApplyMissingCalFileFails() async throws {
        let missing = env.root.appendingPathComponent("gone.cal").path
        let r = makeRecipe(
            calibrationURL: missing, applyCalibration: true)
        try await seed(r)

        let applied = await media.apply(r)

        XCTAssertFalse(applied)
        XCTAssertFalse(workflow.profile.applyCalibration)
        XCTAssertEqual(workflow.profile.calibrationFile, missing)
        XCTAssertEqual(workflow.wizard.notice?.kind, .error)
        XCTAssertEqual(media.selectedRecipeID, "none")
    }

    func testApplyCalPrefixedCalCannotArmK() async throws {
        let calPath = try writeCal(named: "CAL_target.cal")
        let r = makeRecipe(
            calibrationURL: calPath, applyCalibration: true)
        try await seed(r)

        let applied = await media.apply(r)

        // Success with warning — the refusal is permanent, re-clicking
        // cannot unstick it (decision 6).
        XCTAssertTrue(applied)
        XCTAssertFalse(workflow.profile.applyCalibration)
        XCTAssertEqual(workflow.profile.calibrationFile, calPath)
        XCTAssertNil(workflow.buildPrinttargConfig().calibrationFile)
        XCTAssertEqual(media.selectedRecipeID, r.id)
        XCTAssertEqual(workflow.wizard.notice?.kind, .warning)
    }

    func testApplyLiveCalBasenameBlocks() async throws {
        let calPath = try writeCal()
        let r = makeRecipe(
            calibrationURL: calPath, applyCalibration: true)
        try await seed(r)
        workflow.wizard.basename = "CAL_live"

        let applied = await media.apply(r)

        XCTAssertTrue(applied)
        XCTAssertFalse(workflow.profile.applyCalibration)
        XCTAssertNil(workflow.buildPrinttargConfig().calibrationFile)
    }

    func testApplyMissingQueueLeavesQueueUntouched() async throws {
        workflow.print.selectedPrinter = "Other_Queue"
        let r = makeRecipe(printerID: "No_Such_Queue")
        try await seed(r)

        let applied = await media.apply(r)

        XCTAssertFalse(applied)
        XCTAssertEqual(workflow.print.selectedPrinter, "Other_Queue")
        XCTAssertTrue(
            workflow.wizard.notice?.text.contains("is not installed") == true)
        XCTAssertEqual(media.selectedRecipeID, "none")
    }

    // MARK: - Capture

    func testCaptureCopiesPrinterAndPreset() async throws {
        workflow.print.printers = [
            Printer(name: "Mock_Queue", displayName: "Mock Queue Display")
        ]
        workflow.print.selectedPrinter = "Mock_Queue"
        workflow.selectedPresetID = "preset-std-rgb"
        media.saveMediaName = "My Recipe"
        media.saveMediaPaper = "Rag"
        media.saveMediaInk = "PK"

        let saved = await media.captureFromSession()

        XCTAssertTrue(saved)
        let stored = await env.environment.mediaStore.all()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].printerID, "Mock_Queue")
        XCTAssertEqual(stored[0].printerDisplayName, "Mock Queue Display")
        XCTAssertEqual(stored[0].presetID, "preset-std-rgb")
        XCTAssertEqual(stored[0].colourSpace, "rgb")
        XCTAssertEqual(media.selectedRecipeID, stored[0].id)
    }

    func testCaptureNoPresetAutoSnapshots() async throws {
        workflow.print.printers = [
            Printer(name: "Mock_Queue", displayName: "Mock Queue Display")
        ]
        workflow.print.selectedPrinter = "Mock_Queue"
        workflow.selectedPresetID = "none"
        media.saveMediaName = "Snap"
        media.saveMediaPaper = "Rag"
        media.saveMediaInk = "MK"

        let saved = await media.captureFromSession()

        XCTAssertTrue(saved)
        let stored = await env.environment.mediaStore.all()
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(stored[0].presetID.hasPrefix("custom-"))
        XCTAssertTrue(
            env.environment.presetStore.customs()
                .contains { $0.id == stored[0].presetID })
        XCTAssertEqual(workflow.selectedPresetID, stored[0].presetID)
    }

    func testCaptureRequiresPrinter() async {
        workflow.print.selectedPrinter = ""
        media.saveMediaName = "n"
        media.saveMediaPaper = "p"
        media.saveMediaInk = "i"

        let saved = await media.captureFromSession()

        XCTAssertFalse(saved)
        XCTAssertNotNil(media.saveMediaError)
    }

    func testCaptureForcesOffCalToggleForCalFile() async throws {
        let calPath = try writeCal(named: "CAL_target.cal")
        workflow.profile.calibrationFile = calPath
        workflow.profile.applyCalibration = true
        workflow.print.printers = [Printer(name: "Mock_Queue")]
        workflow.print.selectedPrinter = "Mock_Queue"
        workflow.selectedPresetID = "preset-std-rgb"
        media.saveMediaName = "n"
        media.saveMediaPaper = "p"
        media.saveMediaInk = "i"
        media.saveMediaApplyCal = true   // forced off by calApplyable

        XCTAssertFalse(media.calApplyable)
        let saved = await media.captureFromSession()

        XCTAssertTrue(saved)
        let stored = await env.environment.mediaStore.all()
        XCTAssertEqual(stored[0].calibrationURL, calPath)   // verbatim
        XCTAssertFalse(stored[0].applyCalibration)
    }

    // MARK: - Staleness

    func testStaleCalFlagged() async throws {
        let calPath = try writeCal(
            MediaLibraryViewModelTests.staleCal, named: "old.cal")
        let r = makeRecipe(calibrationURL: calPath)
        try await seed(r)
        workflow.print.printers = [Printer(name: "Mock_Queue")]

        await media.refreshStalenessAsync()

        XCTAssertTrue(
            media.staleReasons[r.id]?.contains(.calibration) == true)
        XCTAssertNotNil(media.calAgeDays[r.id])
    }

    func testAbsentQueueFlaggedOnlyWhenListNonEmpty() async throws {
        let r = makeRecipe(printerID: "No_Such_Queue")
        try await seed(r)

        // Un-enumerated list is indeterminate → no flag.
        workflow.print.printers = []
        await media.refreshStalenessAsync()
        XCTAssertNil(media.staleReasons[r.id])

        // Absent from a non-empty list → .printer.
        workflow.print.printers = [Printer(name: "Other_Queue")]
        await media.refreshStalenessAsync()
        XCTAssertTrue(
            media.staleReasons[r.id]?.contains(.printer) == true)

        // Present but unselected → no flag.
        workflow.print.printers = [
            Printer(name: "Other_Queue"), Printer(name: "No_Such_Queue"),
        ]
        workflow.print.selectedPrinter = "Other_Queue"
        await media.refreshStalenessAsync()
        XCTAssertNil(media.staleReasons[r.id])
    }

    // MARK: - Delete

    func testDeleteResetsSelection() async throws {
        let r = makeRecipe()
        try await seed(r)
        media.selectedRecipeID = r.id

        media.delete(r)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(media.selectedRecipeID, "none")
        let stored = await env.environment.mediaStore.all()
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - Corrupt library

    func testCorruptLibraryKeepsFileAndWarns() async throws {
        // Fresh environment so the store's `loaded` flag is still false.
        let env2 = try TestAppEnvironment.make()
        defer { env2.cleanup() }
        try "garbage".write(
            to: env2.mediaLibraryURL, atomically: true, encoding: .utf8)
        let workflow2 = TargetWorkflowViewModel(
            environment: env2.environment)
        await workflow2.media.reloadAsync()

        XCTAssertTrue(workflow2.media.recipes.isEmpty)
        XCTAssertEqual(workflow2.media.selectedRecipeID, "none")
        XCTAssertEqual(workflow2.wizard.notice?.kind, .warning)
        XCTAssertEqual(try Data(contentsOf: env2.mediaLibraryURL),
                       "garbage".data(using: .utf8))
    }
}
