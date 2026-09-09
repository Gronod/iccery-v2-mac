import Foundation
import simd

/// A single vertex of an Argyll `.gam` surface mesh.
///
/// Coordinates follow the v0.8.5 SceneKit convention: `x = a*`, `y = L*`,
/// `z = b*` so that the a* (green-red) axis is horizontal, L* (lightness)
/// is vertical, and b* (blue-yellow) is depth.
public struct GamutVertex: Sendable, Equatable {
    public let lab: LabColor
    public let rgb: DisplayRGB
    public let position: SIMD3<Float>

    public init(lab: LabColor, rgb: DisplayRGB) {
        self.lab = lab
        self.rgb = rgb
        self.position = SIMD3<Float>(Float(lab.a), Float(lab.l), Float(lab.b))
    }
}

/// A face from an Argyll `.gam` file.
///
/// Indices are 0-based and index into `GamutMesh.vertices` in the order the
/// vertices were pushed by the parser (the `VERTEX_NO` column is discarded).
public struct GamutTriangle: Sendable, Equatable {
    public let a: UInt32
    public let b: UInt32
    public let c: UInt32

    public init(a: UInt32, b: UInt32, c: UInt32) {
        self.a = a
        self.b = b
        self.c = c
    }
}

/// Parsed gamut surface mesh.
public struct GamutMesh: Sendable, Equatable {
    public let vertices: [GamutVertex]
    public let faces: [GamutTriangle]

    public init(vertices: [GamutVertex], faces: [GamutTriangle]) {
        self.vertices = vertices
        self.faces = faces
    }

    /// A printable summary for diagnostics.
    public var summary: String {
        "GamutMesh(vertices: \(vertices.count), faces: \(faces.count))"
    }
}
