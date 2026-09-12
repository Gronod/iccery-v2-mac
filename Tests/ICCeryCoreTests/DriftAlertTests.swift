import Foundation
import XCTest
@testable import ICCeryCore

final class DriftAlertTests: XCTestCase {

    func testNotEnough() {
        let records = [
            record(avg: 4.0, at: 1000)
        ]
        XCTAssertNil(DriftAlert.compute(from: records))
    }

    func testOneHourApart() {
        let records = [
            record(avg: 4.0, at: 1000),
            record(avg: 5.0, at: 4600)
        ]
        XCTAssertNotNil(DriftAlert.compute(from: records))
    }

    func testSameDayUnderHour() {
        let records = [
            record(avg: 4.0, at: 1000),
            record(avg: 5.0, at: 2000)
        ]
        XCTAssertNil(DriftAlert.compute(from: records))
    }

    func testDistinctDays() {
        let day1 = record(avg: 4.0, at: 0)
        let day2 = record(avg: 5.0, at: 86400 + 1000)
        XCTAssertNotNil(DriftAlert.compute(from: [day1, day2]))
    }

    func testNonPoor() {
        let records = [
            record(avg: 1.0, at: 0),
            record(avg: 1.5, at: 86400)
        ]
        XCTAssertNil(DriftAlert.compute(from: records))
    }

    func testNonPoorBreaksRun() {
        let records = [
            record(avg: 4.0, at: 0),      // poor
            record(avg: 4.5, at: 86400),  // poor, far apart
            record(avg: 1.0, at: 90000),  // good — breaks the run
            record(avg: 4.0, at: 92000)   // poor, recent but close to previous poor
        ]
        XCTAssertNil(DriftAlert.compute(from: records))
    }

    func testOnlySuffixRun() {
        let records = [
            record(avg: 4.0, at: 0),     // poor
            record(avg: 4.5, at: 18000), // poor, > 1h from first
            record(avg: 1.0, at: 20000), // good — breaks the run
            record(avg: 4.0, at: 25000), // poor
            record(avg: 4.5, at: 26000)  // poor, < 1h and same day
        ]
        XCTAssertNil(DriftAlert.compute(from: records))
    }

    func testSuffixRunAlerts() {
        let records = [
            record(avg: 1.0, at: 0),      // good
            record(avg: 4.0, at: 1000),   // poor
            record(avg: 4.5, at: 4600)    // poor, 1h after previous
        ]
        XCTAssertNotNil(DriftAlert.compute(from: records))
    }

    func testSingleFinalPoor() {
        let records = [
            record(avg: 1.0, at: 0),
            record(avg: 4.0, at: 86400)
        ]
        XCTAssertNil(DriftAlert.compute(from: records))
    }

    private func record(avg: Double, at offset: TimeInterval) -> VerificationRecord {
        VerificationRecord(
            id: "vr-\(Int(offset))",
            profileName: "p",
            printerName: "",
            avgDE: avg,
            maxDE: avg,
            rmsDE: avg,
            patchCount: 1,
            status: VerificationStatus.from(avgDE: avg),
            timestamp: Date(timeIntervalSince1970: offset)
        )
    }
}
