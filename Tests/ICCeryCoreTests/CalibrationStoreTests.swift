import Foundation
import Testing
@testable import ICCeryCore

@Suite("CalibrationStore")
struct CalibrationStoreTests {

    private static let sampleCal = """
    CTI3
    DESCRIPTOR "Test printer"
    COLOR_REP "RGB"
    DEVICE_CLASS "OUTPUT"
    MAX_TAC "300"
    NUMBER_OF_FIELDS 5
    NUMBER_OF_SETS 3
    BEGIN_DATA_FORMAT
    SAMPLE_ID INPUT_VALUE R G B
    END_DATA_FORMAT
    BEGIN_DATA
    1 0 0 0 0
    2 128 64 64 64
    3 255 255 255 255
    END_DATA
    """

    @Test("Loads metadata and curves from .cal")
    func parseCal() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).cal")
        try Self.sampleCal.write(to: url, atomically: true, encoding: .utf8)

        let store = CalibrationStore(staleDays: 30)
        try await store.load(url: url)

        let data = await store.data
        #expect(data?.colorRep == "RGB")
        #expect(data?.descriptor == "Test printer")
        #expect(data?.maxTac == 300)
        #expect(data?.curves.count == 3)

        let r = data?.curves.first { $0.channel == "R" }
        #expect(r?.output == [0, 64, 255])
    }

    @Test("Staleness is true for a very old calibration")
    func staleCalibration() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale_\(UUID().uuidString).cal")
        try Self.sampleCal.write(to: url, atomically: true, encoding: .utf8)

        let store = CalibrationStore(staleDays: 0)
        try await store.load(url: url)
        let stale = await store.isStale(comparedTo: "Other")
        #expect(stale == true)
    }

    @Test("Printer mismatch is flagged as stale")
    func printerMismatch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mismatch_\(UUID().uuidString).cal")
        try Self.sampleCal.write(to: url, atomically: true, encoding: .utf8)

        let store = CalibrationStore(staleDays: 9999)
        try await store.load(url: url)
        await store.setPrinterName("Printer A")
        let stale = await store.isStale(comparedTo: "Printer B")
        #expect(stale == true)
    }
}
