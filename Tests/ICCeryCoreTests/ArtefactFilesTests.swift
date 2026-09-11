import XCTest
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ICCeryCore

private func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("iccery-af-\(UUID().uuidString)")
        .appendingPathComponent(name)
}

final class Ti2HeaderTests: XCTestCase {
    func testParsesKeywordsAndSibling() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ti2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        CTI2
        TARGET_INSTRUMENT "i1iO"
        NUMBER_OF_FIELDS 9
        NUMBER_OF_SETS 800
        NUMBER_OF_PAGES 3
        BEGIN_DATA_FORMAT
        SAMPLE_ID RGB_R
        END_DATA_FORMAT
        """.write(to: dir.appendingPathComponent("job.ti2"), atomically: true, encoding: .utf8)
        try "CGATS".write(
            to: dir.appendingPathComponent("job.ti1"), atomically: true, encoding: .utf8
        )

        let h = Ti2Header.parse(dir.appendingPathComponent("job.ti2"))
        XCTAssertEqual(h.instrument, "i1iO")
        XCTAssertEqual(h.patchCount, 800)
        XCTAssertEqual(h.pageCount, 3)
        XCTAssertTrue(h.hasSiblingTi1)
    }

    func testMissingFileYieldsEmptyHeader() {
        let h = Ti2Header.parse(URL(fileURLWithPath: "/nonexistent/x.ti2"))
        XCTAssertTrue(h.instrument == nil && h.patchCount == nil && !h.hasSiblingTi1)
    }

    func testNumberOfFieldsIsNotPatchCount() throws {
        let url = tempURL("t.ti2")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "NUMBER_OF_FIELDS 9\nNUMBER_OF_SETS 52\nBEGIN_DATA\n".write(
            to: url, atomically: true, encoding: .utf8
        )
        XCTAssertEqual(Ti2Header.parse(url).patchCount, 52)
    }
}

final class TiffPreviewTests: XCTestCase {
    /// Builds a real 2000×1000 TIFF in a temp dir via ImageIO.
    private func makeTiff(width: Int = 2000, height: Int = 1000) throws -> URL {
        let url = tempURL("big.tif")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    func testProducesCappedPNG() throws {
        let tiff = try makeTiff()
        let png = TiffPreview.previewPNG(tiff: tiff)
        XCTAssertNotNil(png)
        // PNG magic
        XCTAssertEqual(png!.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        // Verify the cap by decoding the thumbnail header.
        let src = CGImageSourceCreateWithData(png! as CFData, nil)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        XCTAssertTrue(max(img.width, img.height) <= TiffPreview.maxEdge)
        XCTAssertEqual(img.width, 1200)
    }

    func testNonTiffReturnsNil() throws {
        let url = tempURL("not-tiff.txt")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(TiffPreview.previewPNG(tiff: url))
    }
}

final class ArtefactFilesTests: XCTestCase {
    func testBase64RoundTrip() throws {
        let url = tempURL("a.txt")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        let b64 = try ArtefactFiles.readBase64(url)
        XCTAssertEqual(Data(base64Encoded: b64), Data("hello".utf8))
    }

    func testDefaultWorkingDirExists() {
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: ArtefactFiles.defaultWorkingDirectory().path
        ))
    }
}

final class ArtefactProbeProfileTests: XCTestCase {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Basename probe matrix (#69)

    func testOnlyIcc() throws {
        let dir = try makeDir()
        let icc = dir.appendingPathComponent("job.icc")
        try Data("icc".utf8).write(to: icc)
        XCTAssertEqual(ArtefactProbe.resolveProfile(basename: "job", cwd: dir)?.path, icc.path)
    }

    func testOnlyIcm() throws {
        let dir = try makeDir()
        let icm = dir.appendingPathComponent("job.icm")
        try Data("icm".utf8).write(to: icm)
        XCTAssertEqual(ArtefactProbe.resolveProfile(basename: "job", cwd: dir)?.path, icm.path)
    }

    func testIcmWins() throws {
        let dir = try makeDir()
        try Data("icc".utf8).write(to: dir.appendingPathComponent("job.icc"))
        let icm = dir.appendingPathComponent("job.icm")
        try Data("icm".utf8).write(to: icm)
        let url = ArtefactProbe.resolveProfile(basename: "job", cwd: dir)
        XCTAssertEqual(url?.path, icm.path)
    }

    func testNeitherExists() throws {
        let dir = try makeDir()
        XCTAssertNil(ArtefactProbe.resolveProfile(basename: "job", cwd: dir))
    }

    // MARK: Explicit URL matrix (#69 / #83)

    func testExplicitIccWins() throws {
        let dir = try makeDir()
        let icc = dir.appendingPathComponent("job.icc")
        try Data("icc".utf8).write(to: icc)
        try Data("icm".utf8).write(to: dir.appendingPathComponent("job.icm"))
        XCTAssertEqual(ArtefactProbe.resolveProfile(icc).path, icc.path)
    }

    func testExplicitIcmWins() throws {
        let dir = try makeDir()
        try Data("icc".utf8).write(to: dir.appendingPathComponent("job.icc"))
        let icm = dir.appendingPathComponent("job.icm")
        try Data("icm".utf8).write(to: icm)
        XCTAssertEqual(ArtefactProbe.resolveProfile(icm).path, icm.path)
    }

    func testFlipExtension() throws {
        let dir = try makeDir()
        let icc = dir.appendingPathComponent("job.icc")
        let icm = dir.appendingPathComponent("job.icm")
        try Data("icm".utf8).write(to: icm)
        let resolved = ArtefactProbe.resolveProfile(icc)
        XCTAssertEqual(resolved.path, icm.path)
    }

    func testFlipToIcc() throws {
        let dir = try makeDir()
        let icc = dir.appendingPathComponent("job.icc")
        let icm = dir.appendingPathComponent("job.icm")
        try Data("icc".utf8).write(to: icc)
        XCTAssertEqual(ArtefactProbe.resolveProfile(icm).path, icc.path)
    }

    func testMissingBoth() throws {
        let dir = try makeDir()
        let icc = dir.appendingPathComponent("job.icc")
        XCTAssertEqual(ArtefactProbe.resolveProfile(icc).path, icc.path)
    }

    func testUnrelatedExtension() throws {
        let dir = try makeDir()
        let mpp = dir.appendingPathComponent("job.mpp")
        let icc = dir.appendingPathComponent("job.icc")
        try Data("icc".utf8).write(to: icc)
        // Even though a sibling .icc exists, a missing .mpp stays .mpp.
        XCTAssertEqual(ArtefactProbe.resolveProfile(mpp).path, mpp.path)
        let txt = dir.appendingPathComponent("job.txt")
        XCTAssertEqual(ArtefactProbe.resolveProfile(txt).path, txt.path)
    }
}
