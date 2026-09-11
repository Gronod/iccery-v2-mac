import Foundation
import XCTest
@testable import ICCeryCore

final class CalibrationStoreTests: XCTestCase {

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

    func testParseCal() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).cal")
        try Self.sampleCal.write(to: url, atomically: true, encoding: .utf8)

        let store = CalibrationStore(staleDays: 30)
        try await store.load(url: url)

        let data = await store.data
        XCTAssertEqual(data?.colorRep, "RGB")
        XCTAssertEqual(data?.descriptor, "Test printer")
        XCTAssertEqual(data?.maxTac, 300)
        XCTAssertEqual(data?.curves.count, 3)

        let r = data?.curves.first { $0.channel == "R" }
        XCTAssertEqual(r?.output, [0, 64, 255])
    }

    func testStaleCalibration() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale_\(UUID().uuidString).cal")
        try Self.sampleCal.write(to: url, atomically: true, encoding: .utf8)

        let store = CalibrationStore(staleDays: 0)
        try await store.load(url: url)
        let stale = await store.isStale(comparedTo: "Other")
        XCTAssertEqual(stale, true)
    }

    func testPrinterMismatch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mismatch_\(UUID().uuidString).cal")
        try Self.sampleCal.write(to: url, atomically: true, encoding: .utf8)

        let store = CalibrationStore(staleDays: 9999)
        try await store.load(url: url)
        await store.setPrinterName("Printer A")
        let stale = await store.isStale(comparedTo: "Printer B")
        XCTAssertEqual(stale, true)
    }
}
