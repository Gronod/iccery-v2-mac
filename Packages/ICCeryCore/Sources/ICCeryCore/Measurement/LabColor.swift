import Foundation

/// XYZ tristimulus values, stored in the 0–100 scale used by the Argyll fork.
/// Unkeyed Codable matches `ROW_COLORS_JSON` `[x, y, z]`.
public struct XYZColor: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.x = try container.decode(Double.self)
        self.y = try container.decode(Double.self)
        self.z = try container.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}

/// CIELab value (D50). Unkeyed Codable matches `ROW_COLORS_JSON` `[L, a, b]`.
public struct LabColor: Codable, Sendable, Equatable {
    public let l: Double
    public let a: Double
    public let b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.l = try container.decode(Double.self)
        self.a = try container.decode(Double.self)
        self.b = try container.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(l)
        try container.encode(a)
        try container.encode(b)
    }
}

/// JSON aliases used by `chartread` row payloads.
public typealias CIEXYZ = XYZColor
public typealias CIELab = LabColor

/// sRGB colour in 0–1 display space.
public struct DisplayRGB: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var clamped: DisplayRGB {
        DisplayRGB(r: min(1, max(0, r)), g: min(1, max(0, g)), b: min(1, max(0, b)))
    }
}

/// Colour-space conversions used by the swatch grid.
///
/// All numeric paths are deterministic and avoid platform colour-management APIs.
public enum LabColorMath {

    // Reference white for D50 (0–100 scale).
    static let d50White = (X: 96.4212, Y: 100.0, Z: 82.5188)

    // Reference white for D65 (0–100 scale).
    static let d65White = (X: 95.0489, Y: 100.0, Z: 108.8840)

    // Bradford cone-response matrix and its inverse (XYZ -> LMS).
    static let bradford = [
        [ 0.8951,  0.2664, -0.1614],
        [-0.7502,  1.7135,  0.0367],
        [ 0.0389, -0.0685,  1.0296]
    ]

    static let bradfordInv = [
        [ 0.9869929, -0.1470543,  0.1599627],
        [ 0.4323053,  0.5183603,  0.0492912],
        [-0.0085287,  0.0400428,  0.9684866]
    ]

    // sRGB D65 matrix (XYZ -> linear sRGB, using 0–100 inputs).
    static let srgbMatrix = [
        [ 3.2406, -1.5372, -0.4986],
        [-0.9689,  1.8758,  0.0415],
        [ 0.0557, -0.2040,  1.0570]
    ]

    /// Convert XYZ (0–100) to CIELab D50.
    public static func xyzToLab(_ xyz: XYZColor) -> LabColor {
        let f: (Double) -> Double = { t in
            let delta = 6.0 / 29.0
            if t > delta * delta * delta {
                return pow(t, 1.0 / 3.0)
            } else {
                return t / (3 * delta * delta) + 4.0 / 29.0
            }
        }

        let x = f(xyz.x / d50White.X)
        let y = f(xyz.y / d50White.Y)
        let zr = f(xyz.z / d50White.Z)

        return LabColor(
            l: 116.0 * y - 16.0,
            a: 500.0 * (x - y),
            b: 200.0 * (y - zr)
        )
    }

    /// Convert CIELab D50 to XYZ (0–100).
    public static func labToXYZ(_ lab: LabColor) -> XYZColor {
        let finv: (Double) -> Double = { t in
            let delta = 6.0 / 29.0
            if t > delta {
                return t * t * t
            } else {
                return 3 * delta * delta * (t - 4.0 / 29.0)
            }
        }

        let yr = (lab.l + 16.0) / 116.0
        let xr = yr + lab.a / 500.0
        let zr = yr - lab.b / 200.0

        return XYZColor(
            x: finv(xr) * d50White.X,
            y: finv(yr) * d50White.Y,
            z: finv(zr) * d50White.Z
        )
    }

    /// Convert XYZ D50 to XYZ D65 using the Bradford chromatic adaptation.
    public static func adaptD50ToD65(_ xyz: XYZColor) -> XYZColor {
        let source = matrixMultiply(bradford, [xyz.x, xyz.y, xyz.z])
        let srcWhite = matrixMultiply(bradford, [d50White.X, d50White.Y, d50White.Z])
        let dstWhite = matrixMultiply(bradford, [d65White.X, d65White.Y, d65White.Z])

        let scaled = [
            source[0] * (dstWhite[0] / srcWhite[0]),
            source[1] * (dstWhite[1] / srcWhite[1]),
            source[2] * (dstWhite[2] / srcWhite[2])
        ]

        return XYZColor(
            x: scaled[0] * bradfordInv[0][0] + scaled[1] * bradfordInv[0][1] + scaled[2] * bradfordInv[0][2],
            y: scaled[0] * bradfordInv[1][0] + scaled[1] * bradfordInv[1][1] + scaled[2] * bradfordInv[1][2],
            z: scaled[0] * bradfordInv[2][0] + scaled[1] * bradfordInv[2][1] + scaled[2] * bradfordInv[2][2]
        )
    }

    /// Convert XYZ D65 (0–100) to linear sRGB, apply gamma, and clamp.
    public static func xyzToSRGB(_ xyz: XYZColor) -> DisplayRGB {
        // sRGB matrix is defined for XYZ with D65 white at Y = 1.0.
        // The input is 0–100, so scale by 100 first.
        let scaled = [xyz.x / 100.0, xyz.y / 100.0, xyz.z / 100.0]
        let linear = matrixMultiply(srgbMatrix, scaled)

        func gamma(_ c: Double) -> Double {
            if c <= 0.0031308 {
                return 12.92 * c
            } else {
                return 1.055 * pow(c, 1.0 / 2.4) - 0.055
            }
        }

        return DisplayRGB(
            r: gamma(linear[0]),
            g: gamma(linear[1]),
            b: gamma(linear[2])
        ).clamped
    }

    /// Complete D50 Lab -> display sRGB conversion.
    public static func labToSRGB(_ lab: LabColor) -> DisplayRGB {
        let xyz50 = labToXYZ(lab)
        let xyz65 = adaptD50ToD65(xyz50)
        return xyzToSRGB(xyz65)
    }

    /// Convert an Argyll XYZ array (0–100) to Lab and then to sRGB.
    public static func xyzArrayToSRGB(_ xyz: [Double]) -> DisplayRGB? {
        guard xyz.count >= 3 else { return nil }
        return labToSRGB(xyzToLab(XYZColor(x: xyz[0], y: xyz[1], z: xyz[2])))
    }

    private static func matrixMultiply(_ m: [[Double]], _ v: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: m.count)
        for i in 0..<m.count {
            for j in 0..<v.count {
                result[i] += m[i][j] * v[j]
            }
        }
        return result
    }
}
