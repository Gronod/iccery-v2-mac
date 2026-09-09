import Foundation
import Testing
@testable import ICCeryCore

@Suite("VerificationHistoryStore")
struct VerificationHistoryStoreTests {

    @Test("Append and cap")
    func appendAndCap() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("verification_history.json")

        let store = VerificationHistoryStore(url: url, capacity: 3)
        for i in 0..<5 {
            let record = VerificationRecord(
                id: "vr-\(i)",
                profileName: "p",
                printerName: "",
                avgDE: Double(i),
                maxDE: Double(i),
                rmsDE: Double(i),
                patchCount: i,
                status: .good,
                timestamp: Date(timeIntervalSince1970: TimeInterval(i))
            )
            _ = try await store.append(record)
        }

        let all = await store.all()
        #expect(all.count == 3)
        #expect(all.first?.avgDE == 2.0)
    }

    @Test("Parse failure preserves file")
    func parseFailurePreservesFile() async {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("verification_history.json")

        try? "not json".write(to: url, atomically: true, encoding: .utf8)

        let store = VerificationHistoryStore(url: url)
        do {
            _ = try await store.load()
            Issue.record("load() should throw on invalid JSON")
        } catch {
            #expect(fm.fileExists(atPath: url.path))
        }
    }

    @Test("CSV export quoting")
    func csvQuoting() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("verification_history.json")

        let store = VerificationHistoryStore(url: url)
        let record = VerificationRecord(
            id: "a,b",
            profileName: "\"quoted\"",
            printerName: "",
            avgDE: 1.0,
            maxDE: 2.0,
            rmsDE: 3.0,
            patchCount: 1,
            status: .good,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        _ = try await store.append(record)

        let csv = await store.exportCSV()
        #expect(csv.contains("\"a,b\""))
        #expect(csv.contains("\"\"quoted\"\""))
    }
}
