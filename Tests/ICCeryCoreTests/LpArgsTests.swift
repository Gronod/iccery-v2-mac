import Testing
import Foundation
@testable import ICCeryCore

/// Issue 15 — `lp` argv goldens (docs/11 `build_lp_args`).
/// `-d`/`options`/`-t` handling is in `CupsService`; these tests cover
/// flag order, captured-option precedence, and sanitisation.
@Suite("LpArgs")
struct LpArgsTests {

    private let tiff = "/tmp/work/target_001.tif"
    private let queue = "EPSON_XP_55_Series"

    private func build(
        options: PrintOptions = PrintOptions(),
        optionKeys: Set<String> = []
    ) throws -> [String] {
        try LpArgs.build(
            queue: queue, tiffPath: tiff,
            options: options, optionKeys: optionKeys)
    }

    @Test("Header: -d queue -t title, both AP_* first, TIFF last")
    func header() throws {
        let argv = try build()
        #expect(Array(argv[0...1]) == ["-d", queue])
        #expect(Array(argv[2...3]) == ["-t", "ICCery Target - target_001.tif"])
        #expect(Array(argv[4...5])
            == ["-o", "AP_ColorMatchingMode=AP_ApplicationColorMatching"])
        #expect(Array(argv[6...7])
            == ["-o", "AP.ColorMatchingMode=AP_ApplicationColorMatching"])
        #expect(argv.last == tiff)
        #expect(!argv.contains { $0 == "raw" || $0 == "-o raw" })
    }

    @Test("Never emits -o raw; captured raw= is dropped")
    func neverRaw() throws {
        let argv = try build(options: PrintOptions(
            cupsOptions: "raw=true MediaType=Photo"))
        for (i, arg) in argv.enumerated() where arg == "-o" {
            #expect(argv[i + 1] != "raw")
            #expect(argv[i + 1] != "raw=true")
        }
        #expect(!argv.contains { $0.hasPrefix("raw=") })
        #expect(argv.contains("MediaType=Photo"))
    }

    @Test("Captured options replayed after AP_* headers")
    func capturedReplay() throws {
        let argv = try build(options: PrintOptions(
            cupsOptions: "InputSlot=Rear MediaType=Photo"))
        let rear = argv.firstIndex(of: "InputSlot=Rear")!
        let apFirst = argv.firstIndex(of:
            "AP_ColorMatchingMode=AP_ApplicationColorMatching")!
        #expect(rear > apFirst)
    }

    @Test("Captured wins: media key present → derived media skipped")
    func capturedWinsMedia() throws {
        let argv = try build(
            options: PrintOptions(
                mediaType: "Plain",
                cupsOptions: "MediaType=Glossy"),
            optionKeys: ["MediaType"])
        #expect(argv.contains("MediaType=Glossy"))
        #expect(!argv.contains("MediaType=Plain"))
    }

    @Test("Media emitted via detected key when not captured")
    func mediaDerived() throws {
        let argv = try build(
            options: PrintOptions(mediaType: "SemiGloss"),
            optionKeys: ["CNIJMediaType", "MediaType"])
        // CNIJMediaType wins over MediaType in detection order.
        #expect(argv.contains("CNIJMediaType=SemiGloss"))
        #expect(!argv.contains("MediaType=SemiGloss"))
    }

    @Test("Driver bypass emitted when absent, skipped when captured")
    func bypassRules() throws {
        let withBypass = try build(
            optionKeys: ["EPIJ_CMat"])
        #expect(withBypass.contains("EPIJ_CMat=3"))

        let captured = try build(
            options: PrintOptions(cupsOptions: "EPIJ_CMat=1"),
            optionKeys: ["EPIJ_CMat"])
        // Captured value kept, detection not re-applied.
        #expect(captured.filter { $0.hasPrefix("EPIJ_CMat") }
            == ["EPIJ_CMat=1"])
    }

    @Test("Orientation: portrait=3 landscape=4; captured wins")
    func orientation() throws {
        #expect(try build(options: PrintOptions(orientation: "portrait"))
            .contains("orientation-requested=3"))
        #expect(try build(options: PrintOptions(orientation: "landscape"))
            .contains("orientation-requested=4"))
        #expect(!try build(options: PrintOptions(
            orientation: "landscape",
            cupsOptions: "orientation-requested=5"))
            .contains("orientation-requested=4"))
    }

    @Test("PageSize emitted unless captured")
    func pageSize() throws {
        #expect(try build(options: PrintOptions(paperSize: "A4"))
            .contains("PageSize=A4"))
        #expect(!try build(options: PrintOptions(
            paperSize: "A4", cupsOptions: "PageSize=Letter"))
            .contains("PageSize=A4"))
    }

    @Test("Sanitise rejects `;`, newline, and shell metachars")
    func sanitise() throws {
        #expect(throws: LpArgsError.self) {
            _ = try build(options: PrintOptions(
                cupsOptions: "InputSlot=Rear;rm -rf /"))
        }
        #expect(throws: LpArgsError.self) {
            _ = try build(options: PrintOptions(
                cupsOptions: "InputSlot=Rear\nMediaType=Photo"))
        }
        #expect(throws: LpArgsError.self) {
            _ = try build(options: PrintOptions(
                cupsOptions: "InputSlot=$(whoami)"))
        }
    }
}
