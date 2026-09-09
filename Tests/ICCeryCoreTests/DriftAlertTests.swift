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

    @Test("Non-poor results do not trigger")
    func nonPoor() {
        let records = [
            record(avg: 1.0, at: 0),
            record(avg: 1.5, at: 86400)
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
