import Foundation

/// Approximate sRGB → CIELab D50 conversion for the gamut inspect panel
/// (issue #147).
///
/// This is a fixed-matrix helper, **not** a colour-management module: it
/// never touches ICC profiles, ColorSync, or lcms. The UI labels its
/// output "approx. Lab, not ColorSync".
public enum ApproximateLab {

    /// linear-sRGB → XYZ (D65) matrix, IEC 61966-2-1.
    private static let srgbToXYZ: [[Double]] = [
        [0.4124, 0.3576, 0.1805],
        [0.2126, 0.7152, 0.0722],
        [0.0193, 0.1192, 0.9505],
    ]

    /// 8-bit sRGB triple → Lab D50 (approximate).
    public static func srgb8ToLab(r: Int, g: Int, b: Int) -> LabColor {
        srgbToLab(DisplayRGB(
            r: Double(r) / 255.0,
            g: Double(g) / 255.0,
            b: Double(b) / 255.0))
    }

    /// 0–1 sRGB triple → Lab D50 (approximate).
    public static func srgbToLab(_ rgb: DisplayRGB) -> LabColor {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let v = [linear(rgb.r), linear(rgb.g), linear(rgb.b)]
        // 0–1 XYZ D65 → the 0–100 scale `LabColorMath` works in.
        let xyz65 = XYZColor(
            x: (srgbToXYZ[0][0] * v[0] + srgbToXYZ[0][1] * v[1] + srgbToXYZ[0][2] * v[2]) * 100,
            y: (srgbToXYZ[1][0] * v[0] + srgbToXYZ[1][1] * v[1] + srgbToXYZ[1][2] * v[2]) * 100,
            z: (srgbToXYZ[2][0] * v[0] + srgbToXYZ[2][1] * v[1] + srgbToXYZ[2][2] * v[2]) * 100)
        return LabColorMath.xyzToLab(adaptD65ToD50(xyz65))
    }

    /// Bradford D65 → D50 chromatic adaptation — the mirror of
    /// `LabColorMath.adaptD50ToD65`.
    private static func adaptD65ToD50(_ xyz: XYZColor) -> XYZColor {
        let m = LabColorMath.bradford
        let inv = LabColorMath.bradfordInv
        let d65 = LabColorMath.d65White
        let d50 = LabColorMath.d50White
        let source = multiply(m, [xyz.x, xyz.y, xyz.z])
        let srcWhite = multiply(m, [d65.X, d65.Y, d65.Z])
        let dstWhite = multiply(m, [d50.X, d50.Y, d50.Z])
        let scaled = [
            source[0] * (dstWhite[0] / srcWhite[0]),
            source[1] * (dstWhite[1] / srcWhite[1]),
            source[2] * (dstWhite[2] / srcWhite[2]),
        ]
        return XYZColor(
            x: inv[0][0] * scaled[0] + inv[0][1] * scaled[1] + inv[0][2] * scaled[2],
            y: inv[1][0] * scaled[0] + inv[1][1] * scaled[1] + inv[1][2] * scaled[2],
            z: inv[2][0] * scaled[0] + inv[2][1] * scaled[1] + inv[2][2] * scaled[2])
    }

    private static func multiply(_ m: [[Double]], _ v: [Double]) -> [Double] {
        m.map { row in zip(row, v).reduce(0) { $0 + $1.0 * $1.1 } }
    }
}
