import Foundation
import XCTest
@testable import ICCeryCore

/// ``GamutMeshParser`` acceptance + edge-case tests.
final class GamutMeshParserTests: XCTestCase {

    /// Returns the bundled real `sRGB.gam` in `Resources/Argyll/reference_gamuts`.
    private var bundledSRGBGamURL: URL {
        let bundle = Bundle.main
        let resource = bundle.resourceURL ?? bundle.bundleURL
        return resource.appendingPathComponent("Argyll/reference_gamuts/sRGB.gam")
    }

    func testParsesBundledSRGB() throws {
        let mesh = try GamutMeshParser.parse(url: bundledSRGBGamURL)

        XCTAssertEqual(mesh.vertices.count, 448, "sRGB.gam has 448 vertices")
        XCTAssertEqual(mesh.faces.count, 892, "sRGB.gam has 892 faces")
    }

    func testDiscardsVertexNo() throws {
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

        XCTAssertEqual(mesh.vertices.count, 4)
        XCTAssertEqual(mesh.faces.count, 2)
        XCTAssertEqual(mesh.vertices[0].lab, LabColor(l: 10, a: 20, b: 30))
        XCTAssertEqual(mesh.vertices[3].lab, LabColor(l: 40, a: 50, b: 60))
    }

    func testIgnoresComments() throws {
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
        XCTAssertEqual(mesh.vertices.count, 2)
        XCTAssertEqual(mesh.faces.count, 1)
    }

    func testRemapsCoordinates() throws {
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
        XCTAssertEqual(mesh.vertices.first?.position, SIMD3<Float>(-20, 50, 80))
    }

    func testComputesVertexColor() throws {
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
        let white = try XCTUnwrap(mesh.vertices.first).rgb
        XCTAssertTrue(white.r > 0.95)
        XCTAssertTrue(white.g > 0.95)
        XCTAssertTrue(white.b > 0.95)
    }

    func testDropsOutOfBoundsFaces() throws {
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
        XCTAssertEqual(mesh.faces.count, 1)
    }

    func testThrowsOnEmptyFile() {
        XCTAssertThrowsError(try GamutMeshParser.parse(text: "")) { error in
            guard case GamutMeshParseError.noDataBlock = error else {
                return XCTFail("Expected GamutMeshParseError.noDataBlock, got \(error)")
            }
        }
    }

    func testThrowsWhenMissing() {
        let url = URL(fileURLWithPath: "/nonexistent/path/to/mesh.gam")
        XCTAssertThrowsError(try GamutMeshParser.parse(url: url)) { error in
            guard case GamutMeshParseError.missingFile = error else {
                return XCTFail("Expected GamutMeshParseError.missingFile, got \(error)")
            }
        }
    }
}
