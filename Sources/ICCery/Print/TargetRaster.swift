import CoreGraphics
import Foundation
import ICCeryCore
import ImageIO

/// One decoded target page ready to draw 1:1 (#201, docs/14 §6).
struct TargetPageRaster: Equatable {
    let sourceURL: URL
    /// Re-tagged into a **device** colour space — the image Quartz draws.
    let cgImage: CGImage
    let pixelWidth: Int
    let pixelHeight: Int
    let dpiX: Double
    let dpiY: Double
    let componentCount: Int
    let bitsPerComponent: Int
    /// Expected physical size from the printtarg manifest, when known.
    let expectedWidthMm: Double?
    let expectedHeightMm: Double?

    /// `pixels / dpi * 72`. The ONLY size the canvas ever draws at.
    /// 72 pt = 1 in. **Never** `backingScaleFactor` (docs/14 §6).
    var pointSize: CGSize {
        CGSize(width: Double(pixelWidth) / dpiX * 72,
               height: Double(pixelHeight) / dpiY * 72)
    }

    /// `pixels / dpi * 25.4` — the physical size the DPI implies.
    var physicalMm: CGSize {
        CGSize(width: Double(pixelWidth) / dpiX * 25.4,
               height: Double(pixelHeight) / dpiY * 25.4)
    }

    /// `nil` when within 0.5 mm of the manifest, else the drift
    /// message (D9 — warn + spool, never rescale).
    var manifestDrift: String? {
        var parts: [String] = []
        if let expectedWidthMm,
           abs(physicalMm.width - expectedWidthMm) > 0.5 {
            parts.append(String(
                format: "width %.2f mm vs manifest %.2f mm",
                physicalMm.width, expectedWidthMm))
        }
        if let expectedHeightMm,
           abs(physicalMm.height - expectedHeightMm) > 0.5 {
            parts.append(String(
                format: "height %.2f mm vs manifest %.2f mm",
                physicalMm.height, expectedHeightMm))
        }
        guard !parts.isEmpty else { return nil }
        return "TIFF DPI disagrees with the printtarg manifest — "
            + parts.joined(separator: "; ")
    }

    static func == (lhs: TargetPageRaster, rhs: TargetPageRaster) -> Bool {
        lhs.sourceURL == rhs.sourceURL
            && lhs.cgImage === rhs.cgImage
            && lhs.pixelWidth == rhs.pixelWidth
            && lhs.pixelHeight == rhs.pixelHeight
            && lhs.dpiX == rhs.dpiX
            && lhs.dpiY == rhs.dpiY
            && lhs.componentCount == rhs.componentCount
            && lhs.bitsPerComponent == rhs.bitsPerComponent
            && lhs.expectedWidthMm == rhs.expectedWidthMm
            && lhs.expectedHeightMm == rhs.expectedHeightMm
    }
}

enum TargetRasterError: LocalizedError, Equatable {
    case tiffMissing(String)
    case undecodable(String)
    case unsupportedLayout(path: String, components: Int,
                           bitsPerComponent: Int, hasAlpha: Bool)

    var errorDescription: String? {
        switch self {
        case .tiffMissing(let path):
            return "Target TIFF is missing: \(path)"
        case .undecodable(let path):
            return "Target TIFF could not be decoded: \(path)"
        case .unsupportedLayout(let path, let components,
                               let bitsPerComponent, let hasAlpha):
            return "Target TIFF has an unsupported layout "
                + "(\(components) components, \(bitsPerComponent) bpc"
                + "\(hasAlpha ? ", alpha" : "")): \(path)"
        }
    }
}

enum TargetRasterLoader {
    /// Absent DPI metadata defaults to 72 (docs/14 §6) — and logs `warn`.
    static let fallbackDPI: Double = 72

    static func load(
        tiff url: URL,
        expectedWidthMm: Double? = nil,
        expectedHeightMm: Double? = nil
    ) throws -> TargetPageRaster {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TargetRasterError.tiffMissing(url.path)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else {
            throw TargetRasterError.undecodable(url.path)
        }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldAllowFloat: false,
        ]
        guard let image = CGImageSourceCreateImageAtIndex(
            source, 0, options as CFDictionary)
        else {
            throw TargetRasterError.undecodable(url.path)
        }

        // DPI lives in the container metadata, not the CGImage.
        var dpiX = fallbackDPI
        var dpiY = fallbackDPI
        var foundX = false
        var foundY = false
        if let properties = CGImageSourceCopyPropertiesAtIndex(
            source, 0, nil) as? [CFString: Any] {
            if let x = (properties[kCGImagePropertyDPIWidth]
                        as? NSNumber)?.doubleValue, x > 0 {
                dpiX = x
                foundX = true
            }
            if let y = (properties[kCGImagePropertyDPIHeight]
                        as? NSNumber)?.doubleValue, y > 0 {
                dpiY = y
                foundY = true
            }
        }
        if !foundX || !foundY {
            AppLogger.shared.warn(
                "TargetRaster: '\(url.lastPathComponent)' carries no "
                    + "usable DPI metadata — assuming \(fallbackDPI) dpi")
        }

        let components = image.colorSpace?.numberOfComponents ?? 0
        guard !Self.hasRealAlpha(image), let tagged = deviceTagged(image)
        else {
            throw TargetRasterError.unsupportedLayout(
                path: url.path,
                components: components,
                bitsPerComponent: image.bitsPerComponent,
                hasAlpha: Self.hasRealAlpha(image))
        }

        return TargetPageRaster(
            sourceURL: url,
            cgImage: tagged,
            pixelWidth: image.width,
            pixelHeight: image.height,
            dpiX: dpiX,
            dpiY: dpiY,
            componentCount: components,
            bitsPerComponent: image.bitsPerComponent,
            expectedWidthMm: expectedWidthMm,
            expectedHeightMm: expectedHeightMm)
    }

    /// Re-tag into `DeviceGray` (1 comp) / `DeviceRGB` (3) /
    /// `DeviceCMYK` (4) by reusing the decoded image's own
    /// `dataProvider`, `bitsPerComponent`, `bitsPerPixel`, `bytesPerRow`
    /// and `bitmapInfo` — **no resample, no bit-depth change, no
    /// `CGImageCreateCopyWithColorSpace` into a calibrated space**
    /// (docs/14 §6.3). `shouldInterpolate: false`,
    /// `intent: .defaultIntent`.
    ///
    /// Returns `nil` (caller throws `.unsupportedLayout`) for alpha,
    /// indexed, float, or >4-component images — a profiling target
    /// never has those, and guessing would corrupt patches.
    static func deviceTagged(_ image: CGImage) -> CGImage? {
        guard !hasRealAlpha(image),
              !image.bitmapInfo.contains(.floatComponents),
              let colorSpace = image.colorSpace,
              colorSpace.model != .indexed,
              colorSpace.model != .pattern,
              let space = deviceSpace(for: colorSpace.numberOfComponents),
              let provider = image.dataProvider
        else { return nil }
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel,
            bytesPerRow: image.bytesPerRow,
            space: space,
            bitmapInfo: image.bitmapInfo,
            provider: provider,
            decode: image.decode,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }

    /// Skip-only padding (`noneSkipLast`/`noneSkipFirst`) is **not**
    /// alpha — ImageIO pads opaque RGB TIFFs to 32 bpp that way, so
    /// accepting it is required for real printtarg files. True coverage
    /// alpha (`last`/`first`/`premultiplied*`/`only`) is rejected.
    static func hasRealAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        default:
            return true
        }
    }

    /// The device colour space for a component count — `nil` for
    /// layouts a profiling target can never legally be (2 channels,
    /// DeviceN, >4 components).
    static func deviceSpace(for componentCount: Int) -> CGColorSpace? {
        switch componentCount {
        case 1: return CGColorSpaceCreateDeviceGray()
        case 3: return CGColorSpaceCreateDeviceRGB()
        case 4: return CGColorSpaceCreateDeviceCMYK()
        default: return nil
        }
    }
}
