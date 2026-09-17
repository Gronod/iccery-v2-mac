import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared TIFF fixture builder for the #201 raster / canvas / PDF
/// harness tests. Writes real TIFFs via `CGImageDestination` so the
/// loader exercises the same decode path as production.
enum TargetTestFixtures {

    enum FixtureError: Error {
        case imageNotCreated
        case destinationNotCreated
        case finalizeFailed
    }

    /// Fresh per-test directory under the temp root.
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-raster-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    /// A solid-fill (or repeating-pattern) `CGImage` with a device
    /// colour space for 1/3/4 components at 8 or 16 bpc. `alpha: true`
    /// appends one alpha sample per pixel (`last`). `pixelBytes` is the
    /// repeating per-pixel pattern (big-endian for 16 bpc).
    static func makeImage(
        px: CGSize,
        components: Int,
        bitsPerComponent: Int,
        alpha: Bool = false,
        pixelBytes: [UInt8]? = nil
    ) -> CGImage? {
        let width = Int(px.width)
        let height = Int(px.height)
        let bytesPerComponent = bitsPerComponent / 8
        let samples = components + (alpha ? 1 : 0)
        let bytesPerPixel = samples * bytesPerComponent
        let bytesPerRow = width * bytesPerPixel
        let pattern = pixelBytes
            ?? Array(0..<bytesPerPixel).map { UInt8(($0 * 37 + 11) & 0xff) }
        var row = [UInt8](repeating: 0, count: bytesPerRow)
        for offset in stride(from: 0, to: bytesPerRow, by: pattern.count) {
            for (index, byte) in pattern.enumerated()
            where offset + index < bytesPerRow {
                row[offset + index] = byte
            }
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(bytesPerRow * height)
        for _ in 0..<height {
            bytes.append(contentsOf: row)
        }
        let data = Data(bytes)

        let space: CGColorSpace
        switch components {
        case 1: space = CGColorSpaceCreateDeviceGray()
        case 3: space = CGColorSpaceCreateDeviceRGB()
        case 4: space = CGColorSpaceCreateDeviceCMYK()
        default: return nil
        }
        var info = CGBitmapInfo()
        if bitsPerComponent == 16 {
            info.insert(.byteOrder16Big)
        }
        if alpha {
            info = CGBitmapInfo(
                rawValue: info.rawValue | CGImageAlphaInfo.last.rawValue)
        }
        guard let provider = CGDataProvider(data: data as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerComponent * samples,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }

    /// Writes `makeImage` output to a single-page TIFF. `dpi` nil
    /// produces a TIFF with no resolution tags (the 72-fallback path).
    static func makeTIFF(
        px: CGSize,
        dpi: Double?,
        components: Int = 3,
        bitsPerComponent: Int = 8,
        alpha: Bool = false,
        pixelBytes: [UInt8]? = nil,
        in directory: URL
    ) throws -> URL {
        guard let image = makeImage(
            px: px, components: components,
            bitsPerComponent: bitsPerComponent,
            alpha: alpha, pixelBytes: pixelBytes)
        else { throw FixtureError.imageNotCreated }
        let url = directory.appendingPathComponent(
            "fixture-\(UUID().uuidString).tiff")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil)
        else { throw FixtureError.destinationNotCreated }
        var properties: [CFString: Any] = [:]
        if let dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFXResolution: dpi,
                kCGImagePropertyTIFFYResolution: dpi,
                kCGImagePropertyTIFFResolutionUnit: 2,   // inches
            ]
        }
        CGImageDestinationAddImage(
            destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination)
        else { throw FixtureError.finalizeFailed }
        return url
    }
}
