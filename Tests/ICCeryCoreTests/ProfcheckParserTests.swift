import Foundation
import XCTest
@testable import ICCeryCore

final class ProfcheckParserTests: XCTestCase {

    func testJsonReport() {
        let output = """
        No of test patches = 52
        {"event": "report", "peak_de2000": 2.41, "avg_de2000": 0.85, "rms": 1.02}
        Profile check complete, errors(CIEDE2000): max. = 9.99, avg. = 9.99, RMS = 9.99
        """
        let report = ProfcheckParser.parse(output)
        XCTAssertEqual(report.isValid, true)
        XCTAssertEqual(report.patchCount, 52)
        XCTAssertEqual(report.avgDE, 0.85)
        XCTAssertEqual(report.maxDE, 2.41)
        XCTAssertEqual(report.rmsDE, 1.02)
        XCTAssertEqual(report.status, .excellent)
    }

    func testLegacyText() {
        let output = """
        No of test patches = 120
        Profile check complete, errors(CIEDE2000): max. = 3.50, avg. = 1.80, RMS = 0.95
        """
        let report = ProfcheckParser.parse(output)
        XCTAssertEqual(report.isValid, true)
        XCTAssertEqual(report.patchCount, 120)
        XCTAssertEqual(report.avgDE, 1.80)
        XCTAssertEqual(report.maxDE, 3.50)
        XCTAssertEqual(report.rmsDE, 0.95)
        XCTAssertEqual(report.status, .good)
    }

    func testRegexFallback() {
        let output = """
        No of test patches = 10
        avg = 4.25
        max = 6.10
        rms = 2.30
        """
        let report = ProfcheckParser.parse(output)
        XCTAssertEqual(report.isValid, true)
        XCTAssertEqual(report.avgDE, 4.25)
        XCTAssertEqual(report.maxDE, 6.10)
        XCTAssertEqual(report.rmsDE, 2.30)
        XCTAssertEqual(report.status, .poor)
    }

    func testUnparseable() {
        let output = "some random text without metrics"
        let report = ProfcheckParser.parse(output)
        XCTAssertEqual(report.isValid, false)
        XCTAssertNotNil(report.warning)
        XCTAssertNil(report.avgDE)
    }

    func testStatusBands() {
        XCTAssertEqual(VerificationStatus.from(avgDE: 0.5), .excellent)
        XCTAssertEqual(VerificationStatus.from(avgDE: 1.5), .good)
        XCTAssertEqual(VerificationStatus.from(avgDE: 2.5), .acceptable)
        XCTAssertEqual(VerificationStatus.from(avgDE: 4.0), .poor)
    }
}
