import AppKit

/// Headless print canvas (#201, docs/14 §6). Never installed in a
/// window; `NSPrintOperation` is its only client.
@MainActor
final class TargetPageCanvasView: NSView {

    private let pages: [TargetPageRaster]
    private let paperSize: NSSize

    /// Test probe — invoked once per drawn page with the live context
    /// so the interpolation/antialias contract is assertable without a
    /// printer.
    var drawProbe: ((NSGraphicsContext, Int, NSRect) -> Void)?

    init(pages: [TargetPageRaster], paperSize: NSSize) {
        self.pages = pages
        self.paperSize = paperSize
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: paperSize.width,
            height: paperSize.height * CGFloat(pages.count)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TargetPageCanvasView is code-only")
    }

    /// Bottom-up CoreGraphics space: `CGContext.draw(_:in:)` renders
    /// the raster upright — a flipped view prints mirrored (#211).
    /// Page 1 is the BOTTOM band of the frame, the non-flipped
    /// pagination convention.
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { true }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: pages.count)
        return true
    }

    /// 1-based page → its paper-sized rect, stacked bottom-up.
    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0,
               y: CGFloat(page - 1) * paperSize.height,
               width: paperSize.width,
               height: paperSize.height)
    }

    /// Where page `page`'s image lands: top-left anchored inside
    /// `rectForPage`, sized `raster.pointSize`, origin snapped to
    /// 0.001 pt (docs/14 §6) so a fractional origin cannot trigger
    /// device resampling. `internal` for unit tests.
    func destinationRect(forPage page: Int) -> NSRect {
        let pageRect = rectForPage(page)
        let size = pages[page - 1].pointSize
        return NSRect(x: Self.snap(pageRect.minX),
                      y: Self.snap(pageRect.maxY - size.height),
                      width: size.width,
                      height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.imageInterpolation = .none
        ctx.shouldAntialias = false
        let cg = ctx.cgContext
        cg.interpolationQuality = .none
        cg.setShouldAntialias(false)
        cg.setAllowsAntialiasing(false)
        cg.setShouldSmoothFonts(false)
        for index in pages.indices {
            let pageRect = rectForPage(index + 1)
            guard pageRect.intersects(dirtyRect) else { continue }
            cg.saveGState()   // page N never inherits N-1's CTM
            NSColor.white.setFill()
            pageRect.fill()
            cg.draw(pages[index].cgImage,
                    in: destinationRect(forPage: index + 1))
            cg.restoreGState()
            drawProbe?(ctx, index + 1, destinationRect(forPage: index + 1))
        }
    }

    private static func snap(_ value: CGFloat) -> CGFloat {
        (value * 1000).rounded() / 1000
    }
}
