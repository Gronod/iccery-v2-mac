import Foundation
import Testing
@testable import ICCeryCore

@Suite("DriftAlert")
struct DriftAlertTests {

    @Test("No alert with fewer than two poor results")
    func notEnough() {
        let records = [
            record(avg: 4.0, at: 1000)
        ]
        #expect(DriftAlert.compute(from: records) == nil)
    }

    @Test("Alert on two poor results one hour apart")
    func oneHourApart() {
        let records = [
            record(avg: 4.0, at: 1000),
            record(avg: 5.0, at: 4600)
        ]
        #expect(DriftAlert.compute(from: records) != nil)
    }

    @Test("No alert if same day and under one hour")
    func sameDayUnderHour() {
        let records = [
            record(avg: 4.0, at: 1000),
            record(avg: 5.0, at: 2000)
        ]
        #expect(DriftAlert.compute(from: records) == nil)
    }

    @Test("Alert on distinct days")
    func distinctDays() {
        let day1 = record(avg: 4.0, at: 0)
        let day2 = record(avg: 5.0, at: 86400 + 1000)
        #expect(DriftAlert.compute(from: [day1, day2]) != nil)
    }

    @Test("Non-poor records do not trigger")
    func nonPoor() {
        let records = [
            record(avg: 1.0, at: 0),
            record(avg: 1.5, at: 86400)
        ]
        #expect(DriftAlert.compute(from: records) == nil)
    }

    @Test("Non-poor records break the consecutive poor run")
    func nonPoorBreaksRun() {
        let records = [
            record(avg: 4.0, at: 0),      // poor
            record(avg: 4.5, at: 86400),  // poor, far apart
            record(avg: 1.0, at: 90000),  // good — breaks the run
            record(avg: 4.0, at: 92000)   // poor, recent but close to previous poor
        ]
        #expect(DriftAlert.compute(from: records) == nil)
    }

    @Test("Only the final consecutive poor run is considered")
    func onlySuffixRun() {
        let records = [
            record(avg: 4.0, at: 0),     // poor
            record(avg: 4.5, at: 18000), // poor, > 1h from first
            record(avg: 1.0, at: 20000), // good — breaks the run
            record(avg: 4.0, at: 25000), // poor
            record(avg: 4.5, at: 26000)  // poor, < 1h and same day
        ]
        #expect(DriftAlert.compute(from: records) == nil)
    }

    @Test("Final consecutive poor run alerts when far apart")
    func suffixRunAlerts() {
        let records = [
            record(avg: 1.0, at: 0),      // good
            record(avg: 4.0, at: 1000),   // poor
            record(avg: 4.5, at: 4600)    // poor, 1h after previous
        ]
        #expect(DriftAlert.compute(from: records) != nil)
    }

    @Test("A single final poor record after good records does not alert")
    func singleFinalPoor() {
        let records = [
            record(avg: 1.0, at: 0),
            record(avg: 4.0, at: 86400)
        ]
        #expect(DriftAlert.compute(from: records) == nil)
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
