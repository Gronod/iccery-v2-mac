import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import ICCery

/// Issue #201 Phase 3 — real `NSPrintOperation` with
/// `jobDisposition = .save`: proves the canvas paginates at paper size,
/// draws the raster 1:1 at the top-left, and survives end-to-end
/// without a printer. Skippable via `ICCERY_SKIP_PRINT_PDF=1` for
/// hosts where the print system cannot run (R8).
@MainActor
final class NativeSpoolPDFTests: XCTestCase {

    private var tempRoot: URL!

    /// A4 in points.
    private let paperSize = NSSize(width: 595.28, height: 841.89)
    /// Known top-left patch colour — solid fill across the fixture.
    private let patchBytes: [UInt8] = [230, 40, 50]

    override func setUpWithError() throws {
        tempRoot = try TargetTestFixtures.makeTempDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testSavePDFDrawsPagesOneToOne() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["ICCERY_SKIP_PRINT_PDF"]
                == "1",
            "ICCERY_SKIP_PRINT_PDF=1 — print system unavailable")

        // 72×72 px @ 72 dpi → a 72×72 pt solid block at the top-left.
        let tiff = try TargetTestFixtures.makeTIFF(
            px: CGSize(width: 72, height: 72), dpi: 72,
            components: 3, bitsPerComponent: 8,
            pixelBytes: patchBytes, in: tempRoot)
        let raster = try TargetRasterLoader.load(tiff: tiff)

        let info = NSPrintInfo()
        info.paperSize = paperSize
        info.orientation = .portrait
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.scalingFactor = 1.0
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        let pdfURL = tempRoot.appendingPathComponent("spool.pdf")
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = pdfURL

        let canvas = TargetPageCanvasView(
            pages: [raster, raster], paperSize: paperSize)
        let operation = NSPrintOperation(view: canvas, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.canSpawnSeparateThread = false

        XCTAssertTrue(operation.run(),
                      "NSPrintOperation.save failed")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: pdfURL.path))

        let document = try XCTUnwrap(
            CGPDFDocument(pdfURL as CFURL))
        XCTAssertEqual(document.numberOfPages, 2)

        let page = try XCTUnwrap(document.page(at: 1))
        let mediaBox = page.getBoxRect(.mediaBox)
        XCTAssertEqual(mediaBox.width, paperSize.width, accuracy: 0.5)
        XCTAssertEqual(mediaBox.height, paperSize.height, accuracy: 0.5)

        try assertTopLeftPatch(on: page, mediaBox: mediaBox)
    }

    /// Render the page at 1 px/pt and check the fixture's solid block
    /// landed at the top-left at its point size — the coarse 1:1 +
    /// no-scaling check.
    private func assertTopLeftPatch(
        on page: CGPDFPage, mediaBox: CGRect
    ) throws {
        let width = Int(ceil(mediaBox.width))
        let height = Int(ceil(mediaBox.height))
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0))
        let context = try XCTUnwrap(
            NSGraphicsContext(bitmapImageRep: rep))
        let cg = context.cgContext
        let transform = page.getDrawingTransform(
            .mediaBox,
            rect: CGRect(x: 0, y: 0, width: width, height: height),
            rotate: 0, preserveAspectRatio: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        cg.concatenate(transform)
        cg.drawPDFPage(page)
        NSGraphicsContext.restoreGraphicsState()

        func pixel(_ x: Int, _ y: Int) throws -> (Double, Double, Double) {
            let color = try XCTUnwrap(
                rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            return (color.redComponent,
                    color.greenComponent,
                    color.blueComponent)
        }
        func isPatch(_ p: (Double, Double, Double)) -> Bool {
            abs(p.0 - Double(patchBytes[0]) / 255) < 0.04
                && abs(p.1 - Double(patchBytes[1]) / 255) < 0.04
                && abs(p.2 - Double(patchBytes[2]) / 255) < 0.04
        }

        // The print system insets the view by the queue's unprintable
        // margin (R10) — host-dependent, ~18 pt on this machine — so
        // the block's anchor is the painted region's top-left, not
        // (0,0). Find the painted origin by the first opaque pixel.
        var originX = width, originY = height
        for y in 0..<height {
            for x in 0..<width
            where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                originX = min(originX, x)
                originY = min(originY, y)
            }
        }
        XCTAssertLessThan(originX, width, "PDF page rendered empty")
        XCTAssertLessThan(originY, height, "PDF page rendered empty")

        // 10 px inside the 72 pt block on each axis → patch colour.
        XCTAssertTrue(try isPatch(pixel(originX + 10, originY + 10)),
                      "top-left block is not the fixture colour")

        // Measure the block's painted width on a row through it:
        // 72 pt at 1 px/pt — the 1:1 / no-scaling assertion.
        var blockWidth = 0
        var x = originX
        while x < width,
              isPatch(try pixel(x, originY + 10)) {
            blockWidth += 1
            x += 1
        }
        XCTAssertEqual(blockWidth, 72, accuracy: 2)

        // Past the block edge the canvas's white page fill shows.
        let outside = try pixel(originX + 80, originY + 80)
        XCTAssertEqual(outside.0, 1, accuracy: 0.04)
        XCTAssertEqual(outside.1, 1, accuracy: 0.04)
        XCTAssertEqual(outside.2, 1, accuracy: 0.04)
    }
}
