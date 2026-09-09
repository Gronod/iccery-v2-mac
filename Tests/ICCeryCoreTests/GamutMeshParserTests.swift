import Foundation
import Testing
@testable import ICCeryCore

/// ``GamutMeshParser`` acceptance + edge-case tests.
@Suite("Gamut mesh parser")
struct GamutMeshParserTests {

    /// Returns the bundled real `sRGB.gam` in `Resources/Argyll/reference_gamuts`.
    private var bundledSRGBGamURL: URL {
        let bundle = Bundle.main
        let resource = bundle.resourceURL ?? bundle.bundleURL
        return resource.appendingPathComponent("Argyll/reference_gamuts/sRGB.gam")
    }

    @Test("Parses bundled sRGB.gam")
    func parsesBundledSRGB() throws {
        let mesh = try GamutMeshParser.parse(url: bundledSRGBGamURL)

        #expect(mesh.vertices.count == 448, "sRGB.gam has 448 vertices")
        #expect(mesh.faces.count == 892, "sRGB.gam has 892 faces")
    }

    @Test("Discards VERTEX_NO and uses push-order indices")
    func discardsVertexNo() throws {
        let text = """
        GAMUT
        NUMBER_OF_FIELDS 4
        BEGIN_DATA_FORMAT
        VERTEX_NO LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        NUMBER_OF_SETS 4
        BEGIN_DATA
        100 10.0 20.0 30.0
        50  20.0 30.0 40.0
        2   30.0 40.0 50.0
        7   40.0 50.0 60.0
        END_DATA
        NUMBER_OF_FIELDS 3
        BEGIN_DATA_FORMAT
        VERTEX_0 VERTEX_1 VERTEX_2
        END_DATA_FORMAT
        NUMBER_OF_SETS 2
        BEGIN_DATA
        0 1 2
        1 2 3
        END_DATA
        """

        let mesh = try GamutMeshParser.parse(text: text)

        #expect(mesh.vertices.count == 4)
        #expect(mesh.faces.count == 2)
        #expect(mesh.vertices[0].lab == LabColor(l: 10, a: 20, b: 30))
        #expect(mesh.vertices[3].lab == LabColor(l: 40, a: 50, b: 60))
    }

    @Test("Ignores comments and blank lines")
    func ignoresComments() throws {
        let text = """
        # Header comment
        NUMBER_OF_FIELDS 4
        BEGIN_DATA_FORMAT
        VERTEX_NO LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        NUMBER_OF_SETS 2
        BEGIN_DATA
        0 10.0 20.0 30.0
        # inline comment
        1 20.0 30.0 40.0
        END_DATA
        # another comment
        NUMBER_OF_FIELDS 3
        BEGIN_DATA_FORMAT
        VERTEX_0 VERTEX_1 VERTEX_2
        END_DATA_FORMAT
        NUMBER_OF_SETS 1
        BEGIN_DATA
        0 1 0
        END_DATA
        """

        let mesh = try GamutMeshParser.parse(text: text)
        #expect(mesh.vertices.count == 2)
        #expect(mesh.faces.count == 1)
    }

    @Test("Remaps coordinates to x=a*, y=L*, z=b*")
    func remapsCoordinates() throws {
        let text = """
        NUMBER_OF_FIELDS 4
        BEGIN_DATA_FORMAT
        VERTEX_NO LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        NUMBER_OF_SETS 1
        BEGIN_DATA
        0 50.0 -20.0 80.0
        END_DATA
        """

        let mesh = try GamutMeshParser.parse(text: text)
        #expect(mesh.vertices.first?.position == SIMD3<Float>(-20, 50, 80))
    }

    @Test("Computes per-vertex sRGB colour")
    func computesVertexColor() throws {
        let text = """
        NUMBER_OF_FIELDS 4
        BEGIN_DATA_FORMAT
        VERTEX_NO LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        NUMBER_OF_SETS 1
        BEGIN_DATA
        0 100.0 0.0 0.0
        END_DATA
        """

        let mesh = try GamutMeshParser.parse(text: text)
        let white = try #require(mesh.vertices.first).rgb
        #expect(white.r > 0.95)
        #expect(white.g > 0.95)
        #expect(white.b > 0.95)
    }

    @Test("Drops out-of-bounds face indices")
    func dropsOutOfBoundsFaces() throws {
        let text = """
        NUMBER_OF_FIELDS 4
        BEGIN_DATA_FORMAT
        VERTEX_NO LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        NUMBER_OF_SETS 2
        BEGIN_DATA
        0 10.0 0.0 0.0
        1 20.0 0.0 0.0
        END_DATA
        NUMBER_OF_FIELDS 3
        BEGIN_DATA_FORMAT
        VERTEX_0 VERTEX_1 VERTEX_2
        END_DATA_FORMAT
        NUMBER_OF_SETS 2
        BEGIN_DATA
        0 1 0
        0 1 99
        END_DATA
        """

        let mesh = try GamutMeshParser.parse(text: text)
        #expect(mesh.faces.count == 1)
    }

    @Test("Throws on empty file")
    func throwsOnEmptyFile() {
        #expect(throws: GamutMeshParseError.noDataBlock) {
            _ = try GamutMeshParser.parse(text: "")
        }
    }

    @Test("Throws when file is missing")
    func throwsWhenMissing() {
        let url = URL(fileURLWithPath: "/nonexistent/path/to/mesh.gam")
        #expect(throws: GamutMeshParseError.missingFile) {
            _ = try GamutMeshParser.parse(url: url)
        }
    }
}
