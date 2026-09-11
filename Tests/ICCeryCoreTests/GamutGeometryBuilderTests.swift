import XCTest
import SceneKit
import ICCeryCore
@testable import ICCery

/// ``GamutSceneGeometryBuilder`` edge-case tests.
@MainActor
final class GamutGeometryBuilderTests: XCTestCase {

    func testDropsOutOfBoundsFaces() {
        let white = GamutVertex(
            lab: LabColor(l: 100, a: 0, b: 0),
            rgb: DisplayRGB(r: 1, g: 1, b: 1)
        )
        let black = GamutVertex(
            lab: LabColor(l: 0, a: 0, b: 0),
            rgb: DisplayRGB(r: 0, g: 0, b: 0)
        )
        let mesh = GamutMesh(
            vertices: [white, black],
            faces: [
                GamutTriangle(a: 0, b: 1, c: 0),
                GamutTriangle(a: 0, b: 1, c: 99)
            ]
        )

        let (_, element) = GamutSceneGeometryBuilder.geometry(for: mesh)

        XCTAssertEqual(element.primitiveCount, 1, "Only the in-bounds face should be in the index buffer")
    }
}
