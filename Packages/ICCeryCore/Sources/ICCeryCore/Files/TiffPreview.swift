import Foundation
import ImageIO
import UniformTypeIdentifiers

/// TIFF → PNG preview for the Stage 2 gallery (#58): decode on the host
/// side, cap the long edge at 1200 px, emit PNG. Never hand raw TIFF
/// bytes to the UI.
public enum TiffPreview {

    public static let maxEdge: Int = 1200

    /// Returns PNG data for the first page of a TIFF, or `nil` when the
    /// file cannot be decoded.
    public static func previewPNG(
        tiff url: URL,
        maxEdge: Int = Self.maxEdge
    ) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
