import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import ICCery

/// Issue #201 Phase 3 — `TargetRasterLoader` DPI handling, device
/// re-tag (D10), unsupported-layout rejection, and manifest drift (D9).
final class TargetRasterTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try TargetTestFixtures.makeTempDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func load(_ url: URL) throws -> TargetPageRaster {
        try TargetRasterLoader.load(tiff: url)
    }

    /// Decode index 0 the same way the loader does, for provider-byte
    /// comparisons that prove the re-tag did not resample.
    private func decoded(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(
            CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(
            CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    // MARK: - pointSize / physicalMm

    func testPointSizeFromDPI() throws {
        let url = try TargetTestFixtures.makeTIFF(
            px: CGSize(width: 2480, height: 3508), dpi: 300,
            in: tempRoot)
        let raster = try load(url)
        XCTAssertEqual(raster.pointSize.width, 595.2, accuracy: 0.01)
        XCTAssertEqual(raster.pointSize.height, 841.92, accuracy: 0.01)
        XCTAssertEqual(raster.physicalMm.width, 209.97, accuracy: 0.01)
        XCTAssertEqual(raster.physicalMm.height, 297.01, accuracy: 0.01)
    }

    func testPointSizeAt600dpi() throws {
        let url = try TargetTestFixtures.makeTIFF(
            px: CGSize(width: 1200, height: 1800), dpi: 600,
            in: tempRoot)
        let raster = try load(url)
        XCTAssertEqual(raster.pointSize.width, 144, accuracy: 0.01)
        XCTAssertEqual(raster.pointSize.height, 216, accuracy: 0.01)
    }

    func testMissingDPIFallsBackTo72() throws {
        let url = try TargetTestFixtures.makeTIFF(
            px: CGSize(width: 100, height: 80), dpi: nil,
            in: tempRoot)
        let raster = try load(url)
        XCTAssertEqual(raster.dpiX, TargetRasterLoader.fallbackDPI)
        XCTAssertEqual(raster.dpiY, TargetRasterLoader.fallbackDPI)
        XCTAssertEqual(raster.pointSize.width, 100, accuracy: 0.01)
        XCTAssertEqual(raster.pointSize.height, 80, accuracy: 0.01)
    }

    func testMissingFileThrows() {
        let url = tempRoot.appendingPathComponent("nope.tiff")
        XCTAssertThrowsError(try load(url)) { error in
            XCTAssertEqual(
                error as? TargetRasterError,
                .tiffMissing(url.path))
        }
    }

    func testGarbageFileThrowsUndecodable() throws {
        let url = tempRoot.appendingPathComponent("junk.tiff")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        XCTAssertThrowsError(try load(url)) { error in
            XCTAssertEqual(
                error as? TargetRasterError,
                .undecodable(url.path))
        }
    }

    // MARK: - deviceTagged (D10)

    func testDeviceTaggedRGB8() throws {
        let source = try XCTUnwrap(TargetTestFixtures.makeImage(
            px: CGSize(width: 16, height: 16),
            components: 3, bitsPerComponent: 8))
        let tagged = try XCTUnwrap(
            TargetRasterLoader.deviceTagged(source))
        XCTAssertEqual(tagged.colorSpace?.model, .rgb)
        XCTAssertEqual(tagged.bitsPerComponent, 8)
        XCTAssertFalse(tagged.shouldInterpolate)
        XCTAssertEqual(
            tagged.dataProvider?.data as? Data,
            source.dataProvider?.data as? Data)
    }

    func testDeviceTaggedCMYK8() throws {
        let source = try XCTUnwrap(TargetTestFixtures.makeImage(
            px: CGSize(width: 16, height: 16),
            components: 4, bitsPerComponent: 8))
        let tagged = try XCTUnwrap(
            TargetRasterLoader.deviceTagged(source))
        XCTAssertEqual(tagged.colorSpace?.model, .cmyk)
        XCTAssertEqual(tagged.bitsPerComponent, 8)
        XCTAssertEqual(
            tagged.dataProvider?.data as? Data,
            source.dataProvider?.data as? Data)
    }

    func testDeviceTaggedGray8() throws {
        let source = try XCTUnwrap(TargetTestFixtures.makeImage(
            px: CGSize(width: 16, height: 16),
            components: 1, bitsPerComponent: 8))
        let tagged = try XCTUnwrap(
            TargetRasterLoader.deviceTagged(source))
        XCTAssertEqual(tagged.colorSpace?.model, .monochrome)
        XCTAssertEqual(tagged.bitsPerComponent, 8)
        XCTAssertEqual(
            tagged.dataProvider?.data as? Data,
            source.dataProvider?.data as? Data)
    }

    func testDeviceTaggedRGB16KeepsBitDepth() throws {
        let source = try XCTUnwrap(TargetTestFixtures.makeImage(
            px: CGSize(width: 16, height: 16),
            components: 3, bitsPerComponent: 16))
        let tagged = try XCTUnwrap(
            TargetRasterLoader.deviceTagged(source))
        XCTAssertEqual(tagged.colorSpace?.model, .rgb)
        XCTAssertEqual(tagged.bitsPerComponent, 16)
        XCTAssertEqual(
            tagged.dataProvider?.data as? Data,
            source.dataProvider?.data as? Data)
    }

    /// The loaded raster reuses the decoder's provider verbatim — byte
    /// equality is the no-resample guarantee (R5).
    func testLoadedRasterSharesDecodedBytes() throws {
        let url = try TargetTestFixtures.makeTIFF(
            px: CGSize(width: 32, height: 24), dpi: 300,
            in: tempRoot)
        let raster = try load(url)
        let decoded = try decoded(url)
        XCTAssertEqual(
            raster.cgImage.dataProvider?.data as? Data,
            decoded.dataProvider?.data as? Data)
        XCTAssertEqual(raster.cgImage.colorSpace?.model, .rgb)
    }

    // MARK: - Rejections

    func testAlphaTIFFThrowsUnsupportedLayout() throws {
        let url = try TargetTestFixtures.makeTIFF(
            px: CGSize(width: 16, height: 16), dpi: 300,
            components: 3, alpha: true, in: tempRoot)
        XCTAssertThrowsError(try load(url)) { error in
            guard case .unsupportedLayout(_, _, _, let hasAlpha) =
                error as? TargetRasterError
            else {
                return XCTFail("expected unsupportedLayout, got \(error)")
            }
            XCTAssertTrue(hasAlpha)
        }
    }

    func testDeviceTaggedRejectsFloat() throws {
        var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        info.insert(.floatComponents)
        info.insert(.byteOrder32Little)
        var bytes = [Float](repeating: 0.5, count: 4 * 4 * 3)
        let floatImage = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            CGImage(
                width: 4, height: 4,
                bitsPerComponent: 32, bitsPerPixel: 96,
                bytesPerRow: 4 * 3 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: info,
                provider: CGDataProvider(data: Data(buffer) as CFData)!,
                decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
        }
        bytes = []
        let image = try XCTUnwrap(floatImage)
        XCTAssertNil(TargetRasterLoader.deviceTagged(image))
    }

    func testDeviceTaggedRejectsIndexed() throws {
        var table = [UInt8](repeating: 0, count: 256 * 3)
        let indexed = try XCTUnwrap(CGColorSpace(
            indexedBaseSpace: CGColorSpaceCreateDeviceRGB(),
            last: 255, colorTable: &table))
        let image = try XCTUnwrap(CGImage(
            width: 8, height: 8,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: 8,
            space: indexed,
            bitmapInfo: CGBitmapInfo(),
            provider: CGDataProvider(
                data: Data(repeating: 7, count: 64) as CFData)!,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
        XCTAssertNil(TargetRasterLoader.deviceTagged(image))
    }

    /// No 2-component `CGImage` is fabricatable through public API —
    /// the rejection lives in `deviceSpace(for:)`, asserted here.
    func testDeviceSpaceRejectsTwoAndFiveComponents() {
        XCTAssertNil(TargetRasterLoader.deviceSpace(for: 2))
        XCTAssertNil(TargetRasterLoader.deviceSpace(for: 0))
        XCTAssertNil(TargetRasterLoader.deviceSpace(for: 5))
        XCTAssertNotNil(TargetRasterLoader.deviceSpace(for: 1))
        XCTAssertNotNil(TargetRasterLoader.deviceSpace(for: 3))
        XCTAssertNotNil(TargetRasterLoader.deviceSpace(for: 4))
    }

    // MARK: - Manifest drift (D9)

    func testManifestDriftWhenMismatch() throws {
        let url = try TargetTestFixtures.makeTIFF(
            px: CGSize(width: 2480, height: 3508), dpi: 300,
            in: tempRoot)
        let raster = try TargetRasterLoader.load(
            tiff: url, expectedWidthMm: 200, expectedHeightMm: 297)
        XCTAssertNotNil(raster.manifestDrift)
    }

    func testManifestDriftNilWhenMatching() throws {
        let url = try TargetTestFixtures.makeTIFF(
            px: CGSize(width: 2480, height: 3508), dpi: 300,
            in: tempRoot)
        // 2480 px @300 dpi = 209.97 mm — inside the 0.5 mm band.
        let raster = try TargetRasterLoader.load(
            tiff: url, expectedWidthMm: 210, expectedHeightMm: 297)
        XCTAssertNil(raster.manifestDrift)
    }
}
