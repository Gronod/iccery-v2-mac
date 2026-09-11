import Testing
import XCTest
import Foundation
@testable import ICCeryCore

final class PrinttargArgsTests: XCTestCase {

    private func config(
        instrument: PrintInstrument = .i1,
        pageSize: PageSize = .a4,
        customW: Double = 210, customH: Double = 297,
        bitDepth: TiffBitDepth = .eight,
        dpi: Int = 300,
        layout: LayoutOrder = .deterministic,
        seed: Int = 1,
        label: String? = nil,
        calFile: String? = nil,
        calEmbed: Bool = false,
        basename: String = "target"
    ) -> PrinttargConfig {
        PrinttargConfig(
            instrument: instrument, pageSize: pageSize,
            customPageWidth: customW, customPageHeight: customH,
            bitDepth: bitDepth, dpi: dpi,
            layoutOrder: layout, customSeed: seed, label: label,
            calibrationFile: calFile, calibrationEmbedOnly: calEmbed,
            basename: basename
        )
    }

    func testBaseline() throws {
        let args = try PrinttargArgs.build(config: config())
        XCTAssertEqual(args, ["-v", "-u", "-i", "i1", "-p", "A4",
                         "-R", "1", "-t", "300", "target"])
    }

    func testDeterministicDefault() throws {
        let args = try PrinttargArgs.build(config: config())
        XCTAssertTrue(args.contains("-R"))
        XCTAssertFalse(args.contains("-r"))
        XCTAssertEqual(args[args.firstIndex(of: "-R")! + 1], "1")
    }

    func testCustomSeed() throws {
        let args = try PrinttargArgs.build(config: config(layout: .customSeed, seed: 42))
        XCTAssertEqual(args[args.firstIndex(of: "-R")! + 1], "42")
        XCTAssertThrowsError(try PrinttargArgs.build(config: config(layout: .customSeed, seed: 0))) { error in
            XCTAssertTrue(error is PrinttargArgError)
        }
    }

    func testRaster() throws {
        let args = try PrinttargArgs.build(config: config(layout: .raster, seed: 9))
        XCTAssertTrue(args.contains("-r"))
        XCTAssertFalse(args.contains("-R"))
    }

    func testLabel() throws {
        let args = try PrinttargArgs.build(
            config: config(label: "ICCery - t - P - I - D - A - 01/02/2026 03:04"))
        let i = args.firstIndex(of: "-d")!
        XCTAssertTrue(args[i + 1].hasPrefix("ICCery - t"))
    }

    func testBitDepthAndDPI() throws {
        XCTAssertTrue(try PrinttargArgs.build(config: config(bitDepth: .sixteen, dpi: 600))
            .contains("-T"))
        XCTAssertTrue(try PrinttargArgs.build(config: config(bitDepth: .eight, dpi: 72))
            .contains("-t"))
        XCTAssertThrowsError(try PrinttargArgs.build(config: config(dpi: 71))) { error in
            XCTAssertTrue(error is PrinttargArgError)
        }
        XCTAssertThrowsError(try PrinttargArgs.build(config: config(dpi: 601))) { error in
            XCTAssertTrue(error is PrinttargArgError)
        }
    }

    func testInstruments() throws {
        let expected: [(PrintInstrument, String)] = [
            (.i1, "i1"), (.p3, "p3"), (.cm, "CM"), (.ss, "SS"),
            (.dtp20, "20"), (.dtp22, "22"), (.dtp41, "41"), (.dtp51, "51"),
        ]
        for (inst, code) in expected {
            let args = try PrinttargArgs.build(config: config(instrument: inst))
            XCTAssertEqual(args[args.firstIndex(of: "-i")! + 1], code)
        }
    }

    func testPageSizes() throws {
        for size in PageSize.allCases where size != .custom {
            let args = try PrinttargArgs.build(config: config(pageSize: size))
            XCTAssertEqual(args[args.firstIndex(of: "-p")! + 1], size.rawValue)
        }
        let custom = try PrinttargArgs.build(config: config(
            pageSize: .custom, customW: 150, customH: 220))
        XCTAssertEqual(custom[custom.firstIndex(of: "-p")! + 1], "150x220")
    }

    func testCustomPageTooSmall() {
        XCTAssertThrowsError(try PrinttargArgs.build(config: config(pageSize: .custom, customW: 49.9))) { error in
            XCTAssertTrue(error is PrinttargArgError)
        }
        XCTAssertThrowsError(try PrinttargArgs.build(config: config(pageSize: .custom, customH: 10))) { error in
            XCTAssertTrue(error is PrinttargArgError)
        }
    }

    func testCalibrationFlags() throws {
        let k = try PrinttargArgs.build(config: config(calFile: "/tmp/a.cal"))
        XCTAssertEqual(k[k.firstIndex(of: "-K")! + 1], "/tmp/a.cal")
        let i = try PrinttargArgs.build(config: config(calFile: "/tmp/a.cal", calEmbed: true))
        XCTAssertEqual(i[i.firstIndex(of: "-I")! + 1], "/tmp/a.cal")
        XCTAssertFalse(i.contains("-K"))
    }

    func testCalProtection() throws {
        let args = try PrinttargArgs.build(
            config: config(calFile: "/tmp/a.cal", basename: "CAL_test"))
        XCTAssertFalse(args.contains("-K"))
        XCTAssertFalse(args.contains("-I"))
    }

    func testWhitespaceOptions() throws {
        let args = try PrinttargArgs.build(
            config: config(label: "   \n ", calFile: " \t "))
        XCTAssertFalse(args.contains("-d"))
        XCTAssertFalse(args.contains("-K"))
        XCTAssertFalse(args.contains("-I"))
    }

    func testTrimmedOptions() throws {
        let args = try PrinttargArgs.build(
            config: config(label: "  My Label  ", calFile: "  /tmp/a.cal  "))
        XCTAssertEqual(args[args.firstIndex(of: "-d")! + 1], "My Label")
        XCTAssertEqual(args[args.firstIndex(of: "-K")! + 1], "/tmp/a.cal")
    }

    func testUnsafeBasename() {
        XCTAssertThrowsError(try PrinttargArgs.build(config: config(basename: "../x"))) { error in
            XCTAssertTrue(error is PathSecurity.Error)
        }
    }
}

final class PrinttargLabelTests: XCTestCase {

    private var fixedDate: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 2; comps.day = 3
        comps.hour = 14; comps.minute = 5
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    func testAutomatic() {
        let label = PrinttargLabel.automatic(
            basename: "tgt",
            metadata: TargetLabelMetadata(
                printer: "Epson", inkSet: "CMYK",
                driverPaper: "Photo", actualPaper: "Matte"),
            date: fixedDate, timeZone: .current)
        XCTAssertTrue(label.hasPrefix("ICCery - tgt - Epson - CMYK - Photo - Matte - "))
        XCTAssertTrue(label.hasSuffix("03/02/2026") || label.contains("/02/2026"))
    }

    func testUnspecified() {
        let label = PrinttargLabel.automatic(
            basename: "tgt", metadata: TargetLabelMetadata(),
            date: fixedDate, timeZone: .current)
        XCTAssertTrue(label.contains(" - Unspecified - Unspecified - Unspecified - Unspecified - "))
    }

    func testManualWins() {
        let resolved = PrinttargLabel.resolved(
            customLabel: "  My Label  ", basename: "tgt",
            metadata: TargetLabelMetadata(), date: fixedDate)
        XCTAssertEqual(resolved, "My Label")
    }
}

final class PrinttargManifestTests: XCTestCase {

    private let prettySingle = """
        Some log line
        Doing work...
        {
            "event": "manifest",
            "pages": [
                {
                    "filename": "target.tif",
                    "patches": 800,
                    "width_mm": 210.0,
                    "height_mm": 297.0
                }
            ]
        }
        trailing text
        """

    private let prettyMulti = """
        {
            "event": "manifest",
            "pages": [
                {"filename": "p1.tif", "patches": 400, "width_mm": 210, "height_mm": 148},
                {"filename": "p2.tif", "patches": 400, "width_mm": 210, "height_mm": 148}
            ]
        }
        """

    func testSinglePage() throws {
        let m = try PrinttargManifestExtractor.manifest(from: prettySingle)
        XCTAssertEqual(m.event, "manifest")
        XCTAssertEqual(m.pages.count, 1)
        XCTAssertEqual(m.pages[0].filename, "target.tif")
        XCTAssertEqual(m.pages[0].patches, 800)
    }

    func testMultiPage() throws {
        let m = try PrinttargManifestExtractor.manifest(from: prettyMulti)
        XCTAssertEqual(m.pages.map(\.filename), ["p1.tif", "p2.tif"])
    }

    func testNoJSON() {
        XCTAssertThrowsError(try PrinttargManifestExtractor.manifest(from: "plain text\nno json")) { error in
            XCTAssertTrue(error is ManifestError)
        }
    }

    func testWrongEvent() {
        let stdout = "{\n  \"event\": \"row\",\n  \"row\": 1\n}\n"
        XCTAssertThrowsError(try PrinttargManifestExtractor.manifest(from: stdout)) { error in
            XCTAssertTrue(error is ManifestError)
        }
    }

    func testRowColorsNotManifest() {
        let stdout = "ROW_COLORS_JSON: {\"a\":1}\n{\"event\":\"manifest\",\"pages\":[]}"
        // Extraction only starts at a '{' that begins a trimmed line,
        // so the ROW_COLORS_JSON line is skipped entirely.
        let m = try? PrinttargManifestExtractor.manifest(from: stdout)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.event, "manifest")
    }

    func testBracesInFilename() throws {
        let stdout = "log\n{\n\"event\": \"manifest\",\n\"pages\": [{\"filename\": \"a}b.tif\", \"patches\": 1, \"width_mm\": 50, \"height_mm\": 50}]\n}\n"
        let m = try PrinttargManifestExtractor.manifest(from: stdout)
        XCTAssertEqual(m.pages[0].filename, "a}b.tif")
    }

    func testUnsafeFilenames() {
        for bad in ["../x.tif", "/abs/x.tif", "dir/x.tif", "x.txt", ""] {
            let stdout = "{\n\"event\":\"manifest\",\"pages\":[{\"filename\":\"\(bad)\",\"patches\":1,\"width_mm\":50,\"height_mm\":50}]\n}"
            XCTAssertThrowsError(try PrinttargManifestExtractor.manifest(from: stdout)) { error in
                XCTAssertTrue(error is ManifestError)
            }
        }
    }
}

@Suite("ArgyllRunner Printtarg")
struct ArgyllRunnerPrinttargTests {

    private func makeFixture(_ body: String, name: String = "printtarg") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
        return dir
    }

    /// A minimal valid TIFF (8-bit, tiny) for gallery preview tests.
    private func writeTinyTIFF(at url: URL) throws {
        // 1x1 8-bit grayscale TIFF, little-endian.
        var bytes: [UInt8] = [
            0x49, 0x49, 0x2A, 0x00, // II + magic
            0x08, 0x00, 0x00, 0x00, // IFD offset
        ]
        let ifdCount: UInt16 = 10
        bytes += withUnsafeBytes(of: ifdCount.littleEndian) { Array($0) }
        func tag(_ t: UInt16, _ type: UInt16, _ count: UInt32, _ value: UInt32) {
            bytes += withUnsafeBytes(of: t.littleEndian) { Array($0) }
            bytes += withUnsafeBytes(of: type.littleEndian) { Array($0) }
            bytes += withUnsafeBytes(of: count.littleEndian) { Array($0) }
            bytes += withUnsafeBytes(of: value.littleEndian) { Array($0) }
        }
        tag(256, 3, 1, 1)      // ImageWidth = 1
        tag(257, 3, 1, 1)      // ImageLength = 1
        tag(258, 3, 1, 8)      // BitsPerSample = 8
        tag(259, 3, 1, 1)      // Compression = none
        tag(262, 3, 1, 1)      // Photometric = BlackIsZero
        tag(273, 4, 1, 0)      // StripOffsets — patched below
        tag(277, 3, 1, 1)      // SamplesPerPixel = 1
        tag(278, 3, 1, 1)      // RowsPerStrip = 1
        tag(279, 4, 1, 1)      // StripByteCounts = 1
        tag(284, 3, 1, 1)      // PlanarConfig
        bytes += [0, 0, 0, 0]  // next IFD = none
        let pixelOffset = bytes.count
        bytes += [0x80]        // the pixel
        // Patch StripOffsets (located right after the tag header at
        // offset 8 + 2 + 5*12 + 8 = position of value field).
        let valuePos = 8 + 2 + 5 * 12 + 8
        let off = UInt32(pixelOffset).littleEndian
        withUnsafeBytes(of: off) { b in
            bytes[valuePos] = b[0]; bytes[valuePos+1] = b[1]
            bytes[valuePos+2] = b[2]; bytes[valuePos+3] = b[3]
        }
        try Data(bytes).write(to: url)
    }

    @Test("Successful printtarg emits .ti2 + manifest + PNG previews")
    func success() async throws {
        let dir = try makeFixture("""
            #!/bin/sh
            last=""
            for arg in "$@"; do last="$arg"; done
            printf 'log line\\n'
            printf '{\\n  "event": "manifest",\\n  "pages": [\\n    {"filename": "%s.tif", "patches": 4, "width_mm": 210, "height_mm": 297}\\n  ]\\n}\\n' "$last"
            touch "$last.ti2"
            exit 0
            """)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Basename "pt" → manifest references pt.tif; write a real TIFF.
        try writeTinyTIFF(at: dir.appendingPathComponent("pt.tif"))

        let resolver = BinaryResolver(bundledRoot: dir, overrideDir: dir)
        let runner = ArgyllRunner(
            processManager: ProcessManager(), binaryResolver: resolver)
        let config = PrinttargConfig(basename: "pt", workingDirectory: dir)
        let result = try await runner.runPrinttarg(config: config)
        #expect(result.ti2URL.lastPathComponent == "pt.ti2")
        #expect(result.manifest.pages.count == 1)
        #expect(result.pages.count == 1)
        let png = result.pages[0].previewPNG
        #expect(png != nil)
        if let png {
            #expect(png.prefix(8) == Data([0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A]))
        }
    }

    @Test("Non-zero exit throws toolFailed and stays on stage")
    func failure() async throws {
        let dir = try makeFixture("""
            #!/bin/sh
            echo "oops" >&2
            exit 3
            """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ArgyllRunner(
            processManager: ProcessManager(),
            binaryResolver: BinaryResolver(bundledRoot: dir, overrideDir: dir))
        await #expect(throws: ArgyllRunnerError.toolFailed(
            tool: "printtarg", code: 3, logs: ["oops"])) {
            try await runner.runPrinttarg(
                config: PrinttargConfig(basename: "x", workingDirectory: dir))
        }
    }

    @Test("Exit 0 without manifest → malformedManifest")
    func noManifest() async throws {
        let dir = try makeFixture("""
            #!/bin/sh
            last=""
            for arg in "$@"; do last="$arg"; done
            touch "$last.ti2"
            echo "no json here"
            exit 0
            """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ArgyllRunner(
            processManager: ProcessManager(),
            binaryResolver: BinaryResolver(bundledRoot: dir, overrideDir: dir))
        await #expect(throws: ArgyllRunnerError.self) {
            try await runner.runPrinttarg(
                config: PrinttargConfig(basename: "x", workingDirectory: dir))
        }
    }

    @Test("Exit 0 without .ti2 → missingArtefact")
    func noTi2() async throws {
        let dir = try makeFixture("""
            #!/bin/sh
            printf '{\\n"event":"manifest",\\n"pages":[]\\n}\\n'
            exit 0
            """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ArgyllRunner(
            processManager: ProcessManager(),
            binaryResolver: BinaryResolver(bundledRoot: dir, overrideDir: dir))
        await #expect(throws: ArgyllRunnerError.self) {
            try await runner.runPrinttarg(
                config: PrinttargConfig(basename: "x", workingDirectory: dir))
        }
    }

    @Test("Deterministic config produces byte-identical .ti2")
    func determinism() async throws {
        let dir = try makeFixture("""
            #!/bin/sh
            last=""
            for arg in "$@"; do last="$arg"; done
            printf 'TI2\\nDETERMINISTIC\\n' > "$last.ti2"
            printf '{\\n"event":"manifest",\\n"pages":[]\\n}\\n'
            exit 0
            """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ArgyllRunner(
            processManager: ProcessManager(),
            binaryResolver: BinaryResolver(bundledRoot: dir, overrideDir: dir))
        // Two runs, two basenames — same argv except basename.
        _ = try await runner.runPrinttarg(
            config: PrinttargConfig(basename: "a", workingDirectory: dir))
        _ = try await runner.runPrinttarg(
            config: PrinttargConfig(basename: "b", workingDirectory: dir))
        let d1 = try Data(contentsOf: dir.appendingPathComponent("a.ti2"))
        let d2 = try Data(contentsOf: dir.appendingPathComponent("b.ti2"))
        #expect(d1 == d2)
    }
}
