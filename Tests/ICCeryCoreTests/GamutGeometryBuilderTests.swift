import Testing
import SceneKit
import ICCeryCore
@testable import ICCery

/// ``GamutSceneGeometryBuilder`` edge-case tests.
@Suite("Gamut scene geometry builder")
@MainActor
struct GamutGeometryBuilderTests {

    @Test("Drops out-of-bounds faces from the element without crashing")
    func dropsOutOfBoundsFaces() {
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

        #expect(element.primitiveCount == 1, "Only the in-bounds face should be in the index buffer")
    }
}
