import Foundation
import Testing
@testable import ICCeryCore

@Suite("CGATS Parser & Writer")
struct CGATSParserTests {

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

    @Test("Parses CTI3 with canonical field names")
    func parseCTI3() throws {
        let dataset = try CGATSParser.parse(Self.canonicalCTI3)
        #expect(dataset.format == .cti3)
        #expect(dataset.samples.count == 2)
        #expect(dataset.colorRep == "RGB")
        #expect(dataset.deviceClass == "DISPLAY")
        #expect(dataset.samples[0].id == "1")
        #expect(dataset.samples[0].loc == "A1")
        #expect(dataset.samples[1].values["RGB_G"] == "50.0000")
    }

    @Test("Round-trips parse, write, reparse")
    func roundTrip() throws {
        let first = try CGATSParser.parse(Self.canonicalCTI3)
        let text = try CGATSWriter.write(first)
        let second = try CGATSParser.parse(text)
        #expect(second.format == first.format)
        #expect(second.samples.count == first.samples.count)
        #expect(second.colorRep == first.colorRep)
        #expect(second.deviceClass == first.deviceClass)
    }

    @Test("Parses CSV with comma delimiters")
    func parseCSV() throws {
        let csv = """
        SAMPLE_ID,SAMPLE_LOC,RGB_R,RGB_G,RGB_B,XYZ_X,XYZ_Y,XYZ_Z,LAB_L,LAB_A,LAB_B
        1,A1,50,0,0,20,10,5,50,60,30
        2,A2,0,50,0,10,30,5,60,-50,40
        """
        let dataset = try CGATSParser.parse(csv, sourceURL: URL(fileURLWithPath: "/tmp/sample.csv"))
        #expect(dataset.format == .csv)
        #expect(dataset.samples.count == 2)
        #expect(dataset.samples[0].values["RGB_R"] == "50.0000")
    }

    @Test("Converts 0-255 device values to 0-100")
    func converts255To100() throws {
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
        #expect(dataset.samples[0].values["RGB_R"] == "100.0000")
        #expect(dataset.samples[0].values["RGB_G"] == "50.1961")
    }

    @Test("Synthesizes COLOR_REP and DEVICE_CLASS when missing")
    func synthesizesMetadata() throws {
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
        #expect(dataset.colorRep == "CMYK")
        #expect(dataset.deviceClass == "PRINTER")
    }

    @Test("Rejects empty file")
    func rejectsEmpty() {
        #expect(throws: (any Error).self) {
            _ = try CGATSParser.parse("")
        }
    }

    @Test("Rejects malformed arity")
    func rejectsArity() {
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
        #expect(throws: (any Error).self) {
            _ = try CGATSParser.parse(bad)
        }
    }

    @Test("Writer emits valid .ti3 with tabs and required keywords")
    func writerFormat() throws {
        let dataset = try CGATSParser.parse(Self.canonicalCTI3)
        let text = try CGATSWriter.write(dataset)
        #expect(text.contains("CTI3"))
        #expect(text.contains("BEGIN_DATA_FORMAT"))
        #expect(text.contains("BEGIN_DATA"))
        #expect(text.contains("END_DATA"))
        #expect(text.contains("COLOR_REP"))
        #expect(text.contains("DEVICE_CLASS"))
        #expect(text.contains("\t"))
    }
}
