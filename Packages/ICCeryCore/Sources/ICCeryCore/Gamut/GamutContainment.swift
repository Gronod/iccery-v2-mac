import Foundation
import simd

/// Result of a point-in-gamut test (issue #147).
public enum GamutContainment: String, Sendable, Equatable {
    /// The point lies inside the mesh volume.
    case inside
    /// The point lies outside the mesh volume.
    case outside
    /// The mesh has no faces to test against.
    case unknown
}

/// Point-in-mesh containment and volume estimation for ``GamutMesh``.
///
/// Both tests run on the scene-space positions stored on
/// ``GamutVertex/position`` (`x = a*`, `y = L*`, `z = b*`), the same
/// mapping the SceneKit viewer uses. No colour management is involved.
public enum GamutGeometry {

    /// Whether `lab` is inside `mesh`.
    ///
    /// Ray-casts through the face list: an odd crossing count means the
    /// point is inside a closed surface. A ray that grazes a vertex or
    /// edge gives an ambiguous count, so the test retries with off-axis
    /// directions before answering. Meshes without faces report
    /// ``GamutContainment/unknown``.
    public static func containment(of lab: LabColor, in mesh: GamutMesh) -> GamutContainment {
        guard !mesh.faces.isEmpty else { return .unknown }
        let origin = SIMD3<Double>(lab.a, lab.l, lab.b)
        for direction in rayDirections {
            if let inside = castRay(from: origin, direction: direction, mesh: mesh) {
                return inside ? .inside : .outside
            }
        }
        return .unknown
    }

    /// Approximate mesh volume in Lab-cubic units.
    ///
    /// Sums signed tetrahedra from the vertex centroid to each face; for
    /// a closed surface the magnitude equals the enclosed volume
    /// regardless of face winding. Returns 0 for empty or face-less
    /// meshes.
    public static func volume(of mesh: GamutMesh) -> Double {
        guard !mesh.faces.isEmpty, !mesh.vertices.isEmpty else { return 0 }
        var centroid = SIMD3<Double>.zero
        for vertex in mesh.vertices {
            centroid += SIMD3<Double>(vertex.position)
        }
        centroid /= Double(mesh.vertices.count)

        var sum = 0.0
        let count = mesh.vertices.count
        for face in mesh.faces {
            guard Int(face.a) < count, Int(face.b) < count, Int(face.c) < count else {
                continue
            }
            let a = SIMD3<Double>(mesh.vertices[Int(face.a)].position) - centroid
            let b = SIMD3<Double>(mesh.vertices[Int(face.b)].position) - centroid
            let c = SIMD3<Double>(mesh.vertices[Int(face.c)].position) - centroid
            sum += simd_dot(a, simd_cross(b, c)) / 6.0
        }
        return abs(sum)
    }

    // MARK: - Ray casting

    /// Primary +X ray, then off-axis retries for degenerate edge hits.
    private static let rayDirections: [SIMD3<Double>] = [
        SIMD3(1, 0, 0),
        simd_normalize(SIMD3<Double>(0.71, 1.0, 0.53)),
        simd_normalize(SIMD3<Double>(0.53, 0.71, 1.0)),
    ]

    /// Möller–Trumbore crossing count. Returns `nil` when a crossing
    /// lands on a triangle edge or vertex (ambiguous parity) so the
    /// caller can retry with a different direction.
    private static func castRay(
        from origin: SIMD3<Double>,
        direction dir: SIMD3<Double>,
        mesh: GamutMesh
    ) -> Bool? {
        let epsilon = 1e-9
        var crossings = 0
        let count = mesh.vertices.count
        for face in mesh.faces {
            guard Int(face.a) < count, Int(face.b) < count, Int(face.c) < count else {
                continue
            }
            let va = SIMD3<Double>(mesh.vertices[Int(face.a)].position)
            let vb = SIMD3<Double>(mesh.vertices[Int(face.b)].position)
            let vc = SIMD3<Double>(mesh.vertices[Int(face.c)].position)

            let e1 = vb - va
            let e2 = vc - va
            let p = simd_cross(dir, e2)
            let det = simd_dot(e1, p)
            if abs(det) < 1e-12 { continue }  // ray parallel to face
            let inv = 1.0 / det
            let tvec = origin - va
            let u = simd_dot(tvec, p) * inv
            let q = simd_cross(tvec, e1)
            let v = simd_dot(dir, q) * inv
            let t = simd_dot(e2, q) * inv

            guard t > epsilon else { continue }
            if u < -epsilon || v < -epsilon || u + v > 1 + epsilon { continue }
            // Crossing on an edge or vertex — parity is ambiguous.
            if u < epsilon || v < epsilon || u + v > 1 - epsilon { return nil }
            crossings += 1
        }
        return crossings % 2 == 1
    }
}
