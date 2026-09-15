import XCTest
import Foundation
@testable import ICCeryCore

/// Issue 15 — `lp` argv goldens (docs/11 `build_lp_args`).
/// `-d`/`options`/`-t` handling is in `CupsService`; these tests cover
/// flag order, captured-option precedence, and sanitisation.
final class LpArgsTests: XCTestCase {

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

    func testHeader() throws {
        let argv = try build()
        XCTAssertEqual(Array(argv[0...1]), ["-d", queue])
        XCTAssertEqual(Array(argv[2...3]), ["-t", "ICCery Target - target_001.tif"])
        XCTAssertEqual(Array(argv[4...5]), ["-o", "AP_ColorMatchingMode=AP_ApplicationColorMatching"])
        XCTAssertEqual(Array(argv[6...7]), ["-o", "AP.ColorMatchingMode=AP_ApplicationColorMatching"])
        XCTAssertEqual(argv.last, tiff)
        XCTAssertFalse(argv.contains { $0 == "raw" || $0 == "-o raw" })
    }

    func testNeverRaw() throws {
        let argv = try build(options: PrintOptions(
            cupsOptions: "raw=true MediaType=Photo"))
        for (i, arg) in argv.enumerated() where arg == "-o" {
            XCTAssertNotEqual(argv[i + 1], "raw")
            XCTAssertNotEqual(argv[i + 1], "raw=true")
        }
        XCTAssertFalse(argv.contains { $0.hasPrefix("raw=") })
        XCTAssertTrue(argv.contains("MediaType=Photo"))
    }

    func testCapturedReplay() throws {
        let argv = try build(options: PrintOptions(
            cupsOptions: "InputSlot=Rear MediaType=Photo"))
        let rear = argv.firstIndex(of: "InputSlot=Rear")!
        let apFirst = argv.firstIndex(of:
            "AP_ColorMatchingMode=AP_ApplicationColorMatching")!
        XCTAssertTrue(rear > apFirst)
    }

    func testCapturedWinsMedia() throws {
        let argv = try build(
            options: PrintOptions(
                mediaType: "Plain",
                cupsOptions: "MediaType=Glossy"),
            optionKeys: ["MediaType"])
        XCTAssertTrue(argv.contains("MediaType=Glossy"))
        XCTAssertFalse(argv.contains("MediaType=Plain"))
    }

    func testMediaDerived() throws {
        let argv = try build(
            options: PrintOptions(mediaType: "SemiGloss"),
            optionKeys: ["CNIJMediaType", "MediaType"])
        // CNIJMediaType wins over MediaType in detection order.
        XCTAssertTrue(argv.contains("CNIJMediaType=SemiGloss"))
        XCTAssertFalse(argv.contains("MediaType=SemiGloss"))
    }

    func testBypassRules() throws {
        let withBypass = try build(
            optionKeys: ["EPIJ_CMat"])
        XCTAssertTrue(withBypass.contains("EPIJ_CMat=3"))

        let captured = try build(
            options: PrintOptions(cupsOptions: "EPIJ_CMat=1"),
            optionKeys: ["EPIJ_CMat"])
        // Captured value kept, detection not re-applied.
        XCTAssertEqual(captured.filter { $0.hasPrefix("EPIJ_CMat") }, ["EPIJ_CMat=1"])
    }

    func testOrientation() throws {
        XCTAssertTrue(try build(options: PrintOptions(orientation: "portrait"))
            .contains("orientation-requested=3"))
        XCTAssertTrue(try build(options: PrintOptions(orientation: "landscape"))
            .contains("orientation-requested=4"))
        let capturedOrients = try build(options: PrintOptions(
            orientation: "landscape",
            cupsOptions: "orientation-requested=5"))
        XCTAssertFalse(capturedOrients.contains("orientation-requested=4"))
        XCTAssertTrue(capturedOrients.contains("orientation-requested=5"))
    }

    func testPageSize() throws {
        XCTAssertTrue(try build(options: PrintOptions(paperSize: "A4"))
            .contains("PageSize=A4"))
        let capturedSize = try build(options: PrintOptions(
            paperSize: "A4", cupsOptions: "PageSize=Letter"))
        XCTAssertFalse(capturedSize.contains("PageSize=A4"))
        XCTAssertTrue(capturedSize.contains("PageSize=Letter"))
    }

    // MARK: - #183 print quality

    func testQualityDerived() throws {
        let argv = try build(
            options: PrintOptions(
                orientation: "portrait", mediaType: "Photo", quality: "305"),
            optionKeys: ["EPIJ_Qual", "MediaType"])
        XCTAssertTrue(argv.contains("EPIJ_Qual=305"))
        // Emit order: after the media option, before orientation.
        let media = argv.firstIndex(of: "MediaType=Photo")!
        let quality = argv.firstIndex(of: "EPIJ_Qual=305")!
        let orient = argv.firstIndex(of: "orientation-requested=3")!
        XCTAssertTrue(media < quality && quality < orient)
    }

    func testQualityDetectedKey() throws {
        // The detected queue key is used, not a hardcoded one.
        let argv = try build(
            options: PrintOptions(quality: "High"),
            optionKeys: ["cupsPrintQuality"])
        XCTAssertTrue(argv.contains("cupsPrintQuality=High"))
    }

    func testCapturedWinsQuality() throws {
        let argv = try build(
            options: PrintOptions(
                quality: "303",
                cupsOptions: "EPIJ_Qual=308"),
            optionKeys: ["EPIJ_Qual"])
        XCTAssertTrue(argv.contains("EPIJ_Qual=308"))
        XCTAssertFalse(argv.contains("EPIJ_Qual=303"))
    }

    func testCapturedQualityCaseInsensitiveDedup() throws {
        let argv = try build(
            options: PrintOptions(
                quality: "303",
                cupsOptions: "epij_qual=308"),
            optionKeys: ["EPIJ_Qual"])
        XCTAssertFalse(argv.contains("EPIJ_Qual=303"))
        XCTAssertTrue(argv.contains("epij_qual=308"))
    }

    func testQualityNilNoEmit() throws {
        let argv = try build(
            options: PrintOptions(mediaType: "Photo"),
            optionKeys: ["EPIJ_Qual", "MediaType"])
        XCTAssertFalse(argv.contains { $0.hasPrefix("EPIJ_Qual=") })
        // No quality key on the queue → no emit either.
        let noKey = try build(
            options: PrintOptions(quality: "303"),
            optionKeys: ["MediaType"])
        XCTAssertFalse(noKey.contains { $0.hasPrefix("EPIJ_Qual=") })
    }

    func testSanitise() throws {
        XCTAssertThrowsError(try build(options: PrintOptions(
            cupsOptions: "InputSlot=Rear;rm -rf /"))) { error in
            XCTAssertTrue(error is LpArgsError)
        }
        XCTAssertThrowsError(try build(options: PrintOptions(
            cupsOptions: "InputSlot=Rear\nMediaType=Photo"))) { error in
            XCTAssertTrue(error is LpArgsError)
        }
        XCTAssertThrowsError(try build(options: PrintOptions(
            cupsOptions: "InputSlot=$(whoami)"))) { error in
            XCTAssertTrue(error is LpArgsError)
        }
    }
}
