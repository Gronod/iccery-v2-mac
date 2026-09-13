import Foundation
import XCTest
@testable import ICCeryCore

/// ``GamutGeometry`` containment and volume goldens on the bundled
/// `sRGB.gam` reference mesh (issue #147). No GPU involved.
final class GamutContainmentTests: XCTestCase {

    /// Returns the bundled real `sRGB.gam` in `Resources/Argyll/reference_gamuts`.
    private var bundledSRGBGamURL: URL {
        let bundle = Bundle.main
        let resource = bundle.resourceURL ?? bundle.bundleURL
        return resource.appendingPathComponent("Argyll/reference_gamuts/sRGB.gam")
    }

    private func loadSRGB() throws -> GamutMesh {
        try GamutMeshParser.parse(url: bundledSRGBGamURL)
    }

    func testNeutralMidGreyIsInsideSRGB() throws {
        let mesh = try loadSRGB()
        XCTAssertEqual(
            GamutGeometry.containment(of: LabColor(l: 50, a: 0, b: 0), in: mesh),
            .inside)
    }

    func testSaturatedColourIsOutsideSRGB() throws {
        let mesh = try loadSRGB()
        XCTAssertEqual(
            GamutGeometry.containment(of: LabColor(l: 50, a: 80, b: 80), in: mesh),
            .outside)
    }

    func testVolumeIsFiniteAndPositiveOnBundledSRGB() throws {
        let mesh = try loadSRGB()
        let volume = GamutGeometry.volume(of: mesh)
        XCTAssertTrue(volume.isFinite)
        XCTAssertGreaterThan(volume, 0)
    }

    func testVertexOnlyMeshReportsUnknown() {
        let mesh = GamutMesh(
            vertices: [
                GamutVertex(lab: LabColor(l: 50, a: 0, b: 0), rgb: DisplayRGB(r: 0.5, g: 0.5, b: 0.5)),
            ],
            faces: [])
        XCTAssertEqual(
            GamutGeometry.containment(of: LabColor(l: 50, a: 0, b: 0), in: mesh),
            .unknown)
        XCTAssertEqual(GamutGeometry.volume(of: mesh), 0)
    }

    func testKnownCubeFixture() throws {
        // Unit cube centred at Lab (50, 0, 0): a*,b* ∈ ±10, L* ∈ 40...60.
        // Two triangles per face, outward winding.
        let lab = { (l: Double, a: Double, b: Double) in
            GamutVertex(lab: LabColor(l: l, a: a, b: b), rgb: DisplayRGB(r: 0, g: 0, b: 0))
        }
        // Corners in (a, L, b) space.
        let c = [
            lab(40, -10, -10), lab(40, 10, -10), lab(40, 10, 10), lab(40, -10, 10),  // bottom
            lab(60, -10, -10), lab(60, 10, -10), lab(60, 10, 10), lab(60, -10, 10),  // top
        ]
        let quad = { (a: UInt32, b: UInt32, c: UInt32, d: UInt32) in
            [GamutTriangle(a: a, b: b, c: c), GamutTriangle(a: a, b: c, c: d)]
        }
        var faces: [GamutTriangle] = []
        faces += quad(0, 3, 2, 1)  // bottom (y=40)
        faces += quad(4, 5, 6, 7)  // top (y=60)
        faces += quad(0, 1, 5, 4)  // z=-10
        faces += quad(3, 7, 6, 2)  // z=+10
        faces += quad(1, 2, 6, 5)  // x=+10
        faces += quad(0, 4, 7, 3)  // x=-10
        let mesh = GamutMesh(vertices: c, faces: faces)

        XCTAssertEqual(
            GamutGeometry.containment(of: LabColor(l: 50, a: 0, b: 0), in: mesh),
            .inside)
        XCTAssertEqual(
            GamutGeometry.containment(of: LabColor(l: 50, a: 20, b: 0), in: mesh),
            .outside)
        // 20 × 20 × 20 Lab-cube.
        XCTAssertEqual(GamutGeometry.volume(of: mesh), 8000, accuracy: 1)
    }
}
