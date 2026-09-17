import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import ICCery

/// Issue #201 Phase 3 — `TargetPageCanvasView` top-down page stacking,
/// snapped top-left anchoring, and the draw-time interpolation /
/// antialias contract asserted via `drawProbe`.
@MainActor
final class TargetCanvasGeometryTests: XCTestCase {

    /// A4-ish paper, points.
    private let paperSize = NSSize(width: 595.28, height: 841.89)

    private func raster(
        pixelWidth: Int = 2480,
        pixelHeight: Int = 3508,
        dpi: Double = 300
    ) -> TargetPageRaster {
        let image = TargetTestFixtures.makeImage(
            px: CGSize(width: 8, height: 8),
            components: 3, bitsPerComponent: 8)!
        return TargetPageRaster(
            sourceURL: URL(fileURLWithPath: "/fixture.tiff"),
            cgImage: image,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            dpiX: dpi, dpiY: dpi,
            componentCount: 3,
            bitsPerComponent: 8,
            expectedWidthMm: nil,
            expectedHeightMm: nil)
    }

    // MARK: - Page stacking

    func testRectForPageStacksTopDown() {
        let view = TargetPageCanvasView(
            pages: [raster(), raster(), raster()],
            paperSize: paperSize)
        XCTAssertFalse(view.isFlipped)

        let page1 = view.rectForPage(1)
        let page3 = view.rectForPage(3)
        XCTAssertEqual(page1.minY, 0, accuracy: 0.001)
        XCTAssertEqual(page3.minY, 2 * paperSize.height, accuracy: 0.001)
        XCTAssertEqual(page1.size, paperSize)
        XCTAssertEqual(page3.size, paperSize)
    }

    func testKnowsPageRangeAndFrame() {
        let view = TargetPageCanvasView(
            pages: [raster(), raster()],
            paperSize: paperSize)
        var range = NSRange()
        XCTAssertTrue(view.knowsPageRange(&range))
        XCTAssertEqual(range, NSRange(location: 1, length: 2))
        XCTAssertEqual(
            view.frame.height, 2 * paperSize.height, accuracy: 0.001)
        XCTAssertEqual(view.frame.width, paperSize.width, accuracy: 0.001)
    }

    // MARK: - Destination rect

    func testDestinationRectAnchorsTopLeftAndSnaps() {
        let view = TargetPageCanvasView(
            pages: [raster(), raster()],
            paperSize: paperSize)

        let first = view.destinationRect(forPage: 1)
        XCTAssertEqual(first.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(first.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(first.width, 595.2, accuracy: 0.01)
        XCTAssertEqual(first.height, 841.92, accuracy: 0.01)

        let second = view.destinationRect(forPage: 2)
        XCTAssertEqual(
            second.origin.y, paperSize.height, accuracy: 0.001)
        XCTAssertEqual(second.size, first.size)

        for rect in [first, second] {
            XCTAssertEqual(
                rect.origin.x * 1000,
                (rect.origin.x * 1000).rounded(),
                accuracy: 1e-9)
            XCTAssertEqual(
                rect.origin.y * 1000,
                (rect.origin.y * 1000).rounded(),
                accuracy: 1e-9)
        }
    }

    // MARK: - Draw flags

    /// Render the canvas into an offscreen bitmap context and assert —
    /// from inside `drawProbe` — that interpolation and antialiasing
    /// are off and the drawn rect is `destinationRect(forPage:)`.
    func testDrawDisablesInterpolationAndAntialias() throws {
        let pages = [raster(), raster()]
        let view = TargetPageCanvasView(
            pages: pages, paperSize: paperSize)

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(view.frame.width)),
            pixelsHigh: Int(ceil(view.frame.height)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0))
        let context = try XCTUnwrap(
            NSGraphicsContext(bitmapImageRep: rep))

        var probed: [(page: Int, rect: NSRect)] = []
        view.drawProbe = { ctx, page, rect in
            XCTAssertEqual(ctx.imageInterpolation, .none,
                           "page \(page): interpolation not .none")
            XCTAssertFalse(ctx.shouldAntialias,
                           "page \(page): antialiasing still on")
            probed.append((page, rect))
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()

        XCTAssertEqual(probed.count, pages.count)
        for (page, rect) in probed {
            XCTAssertEqual(
                rect, view.destinationRect(forPage: page),
                "page \(page): probe rect mismatch")
        }
    }

    /// A dirty rect covering only page 2's band must draw only page 2.
    func testDrawSkipsPagesOutsideDirtyRect() throws {
        let view = TargetPageCanvasView(
            pages: [raster(), raster(), raster()],
            paperSize: paperSize)

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(view.frame.width)),
            pixelsHigh: Int(ceil(view.frame.height)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0))
        let context = try XCTUnwrap(
            NSGraphicsContext(bitmapImageRep: rep))

        var probedPages: [Int] = []
        view.drawProbe = { _, page, _ in probedPages.append(page) }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.draw(view.rectForPage(2))
        NSGraphicsContext.restoreGraphicsState()

        XCTAssertEqual(probedPages, [2])
    }
}
