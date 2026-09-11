import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ICCeryCore

private func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("iccery-af-\(UUID().uuidString)")
        .appendingPathComponent(name)
}

@Suite("Ti2Header")
struct Ti2HeaderTests {
    @Test func parsesKeywordsAndSibling() throws {
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
        #expect(h.instrument == "i1iO")
        #expect(h.patchCount == 800)
        #expect(h.pageCount == 3)
        #expect(h.hasSiblingTi1)
    }

    @Test func missingFileYieldsEmptyHeader() {
        let h = Ti2Header.parse(URL(fileURLWithPath: "/nonexistent/x.ti2"))
        #expect(h.instrument == nil && h.patchCount == nil && !h.hasSiblingTi1)
    }

    @Test func numberOfFieldsIsNotPatchCount() throws {
        let url = tempURL("t.ti2")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "NUMBER_OF_FIELDS 9\nNUMBER_OF_SETS 52\nBEGIN_DATA\n".write(
            to: url, atomically: true, encoding: .utf8
        )
        #expect(Ti2Header.parse(url).patchCount == 52)
    }
}

@Suite("TiffPreview")
struct TiffPreviewTests {
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

    @Test func producesCappedPNG() throws {
        let tiff = try makeTiff()
        let png = TiffPreview.previewPNG(tiff: tiff)
        #expect(png != nil)
        // PNG magic
        #expect(png!.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        // Verify the cap by decoding the thumbnail header.
        let src = CGImageSourceCreateWithData(png! as CFData, nil)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        #expect(max(img.width, img.height) <= TiffPreview.maxEdge)
        #expect(img.width == 1200)
    }

    @Test func nonTiffReturnsNil() throws {
        let url = tempURL("not-tiff.txt")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        #expect(TiffPreview.previewPNG(tiff: url) == nil)
    }
}

@Suite("ArtefactFiles")
struct ArtefactFilesTests {
    @Test func base64RoundTrip() throws {
        let url = tempURL("a.txt")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        let b64 = try ArtefactFiles.readBase64(url)
        #expect(Data(base64Encoded: b64) == Data("hello".utf8))
    }

    @Test func defaultWorkingDirExists() {
        #expect(FileManager.default.fileExists(
            atPath: ArtefactFiles.defaultWorkingDirectory().path
        ))
    }
}

@Suite("ArtefactProbe profile resolve")
struct ArtefactProbeProfileTests {
    @Test("basename probe prefers .icm")
    func icmWins() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("icc".utf8).write(to: dir.appendingPathComponent("job.icc"))
        try Data("icm".utf8).write(to: dir.appendingPathComponent("job.icm"))
        let url = ArtefactProbe.resolveProfile(basename: "job", cwd: dir)
        #expect(url?.pathExtension == "icm")
    }

    @Test("explicit missing .icc flips to sibling .icm")
    func flipExtension() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let icc = dir.appendingPathComponent("job.icc")
        let icm = dir.appendingPathComponent("job.icm")
        try Data("icm".utf8).write(to: icm)
        let resolved = ArtefactProbe.resolveProfile(icc)
        #expect(resolved.path == icm.path)
    }
}
