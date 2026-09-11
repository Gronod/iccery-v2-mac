import Foundation
import XCTest
@testable import ICCeryCore

final class CGATSParserTests: XCTestCase {

    private static let canonicalCTI3 = """
    CTI3
    DESCRIPTOR "Sample target"
    COLOR_REP "RGB"
    DEVICE_CLASS "DISPLAY"
    NUMBER_OF_FIELDS 11
    NUMBER_OF_SETS 2
    BEGIN_DATA_FORMAT
    SAMPLE_ID\tSAMPLE_LOC\tRGB_R\tRGB_G\tRGB_B\tXYZ_X\tXYZ_Y\tXYZ_Z\tLAB_L\tLAB_A\tLAB_B
    END_DATA_FORMAT
    BEGIN_DATA
    1\tA1\t50.0\t0.0\t0.0\t20.0\t10.0\t5.0\t50.0\t60.0\t30.0
    2\tA2\t0.0\t50.0\t0.0\t10.0\t30.0\t5.0\t60.0\t-50.0\t40.0
    END_DATA
    """

    func testParseCTI3() throws {
        let dataset = try CGATSParser.parse(Self.canonicalCTI3)
        XCTAssertEqual(dataset.format, .cti3)
        XCTAssertEqual(dataset.samples.count, 2)
        XCTAssertEqual(dataset.colorRep, "RGB")
        XCTAssertEqual(dataset.deviceClass, "DISPLAY")
        XCTAssertEqual(dataset.samples[0].id, "1")
        XCTAssertEqual(dataset.samples[0].loc, "A1")
        XCTAssertEqual(dataset.samples[1].values["RGB_G"], "50.0000")
    }

    func testRoundTrip() throws {
        let first = try CGATSParser.parse(Self.canonicalCTI3)
        let text = try CGATSWriter.write(first)
        let second = try CGATSParser.parse(text)
        XCTAssertEqual(second.format, first.format)
        XCTAssertEqual(second.samples.count, first.samples.count)
        XCTAssertEqual(second.colorRep, first.colorRep)
        XCTAssertEqual(second.deviceClass, first.deviceClass)
    }

    func testParseCSV() throws {
        let csv = """
        SAMPLE_ID,SAMPLE_LOC,RGB_R,RGB_G,RGB_B,XYZ_X,XYZ_Y,XYZ_Z,LAB_L,LAB_A,LAB_B
        1,A1,50,0,0,20,10,5,50,60,30
        2,A2,0,50,0,10,30,5,60,-50,40
        """
        let dataset = try CGATSParser.parse(csv, sourceURL: URL(fileURLWithPath: "/tmp/sample.csv"))
        XCTAssertEqual(dataset.format, .csv)
        XCTAssertEqual(dataset.samples.count, 2)
        XCTAssertEqual(dataset.samples[0].values["RGB_R"], "50.0000")
    }

    func testConverts255To100() throws {
        let rgb = """
        CTI3
        COLOR_REP RGB
        NUMBER_OF_FIELDS 6
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID RGB_R RGB_G RGB_B XYZ_X XYZ_Y
        END_DATA_FORMAT
        BEGIN_DATA
        1 255 128 0 50 25
        END_DATA
        """
        let dataset = try CGATSParser.parse(rgb)
        XCTAssertEqual(dataset.samples[0].values["RGB_R"], "100.0000")
        XCTAssertEqual(dataset.samples[0].values["RGB_G"], "50.1961")
    }

    func testSynthesizesMetadata() throws {
        let cmyk = """
        CTI3
        NUMBER_OF_FIELDS 6
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID CMYK_C CMYK_M CMYK_Y CMYK_K LAB_L
        END_DATA_FORMAT
        BEGIN_DATA
        1 50 50 50 50 50
        END_DATA
        """
        let dataset = try CGATSParser.parse(cmyk)
        XCTAssertEqual(dataset.colorRep, "CMYK")
        XCTAssertEqual(dataset.deviceClass, "PRINTER")
    }

    func testRejectsEmpty() {
        XCTAssertThrowsError(try CGATSParser.parse(""))
    }

    func testRejectsArity() {
        let bad = """
        CTI3
        NUMBER_OF_FIELDS 2
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID RGB_R
        END_DATA_FORMAT
        BEGIN_DATA
        1
        END_DATA
        """
        XCTAssertThrowsError(try CGATSParser.parse(bad))
    }

    func testWriterFormat() throws {
        let dataset = try CGATSParser.parse(Self.canonicalCTI3)
        let text = try CGATSWriter.write(dataset)
        XCTAssertTrue(text.contains("CTI3"))
        XCTAssertTrue(text.contains("BEGIN_DATA_FORMAT"))
        XCTAssertTrue(text.contains("BEGIN_DATA"))
        XCTAssertTrue(text.contains("END_DATA"))
        XCTAssertTrue(text.contains("COLOR_REP"))
        XCTAssertTrue(text.contains("DEVICE_CLASS"))
        XCTAssertTrue(text.contains("\t"))
    }
}
