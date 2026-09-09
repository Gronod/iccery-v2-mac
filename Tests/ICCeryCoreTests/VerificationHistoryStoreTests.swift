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

    @Test("Append loads existing records first")
    func appendLoadsExisting() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("verification_history.json")

        // Pre-populate the store on disk.
        let existing = VerificationRecord(
            id: "vr-existing",
            profileName: "p",
            printerName: "",
            avgDE: 1.0,
            maxDE: 1.0,
            rmsDE: 1.0,
            patchCount: 1,
            status: .good,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let store1 = VerificationHistoryStore(url: url)
        _ = try await store1.append(existing)

        // A fresh store appending a new record must keep the existing one.
        let store2 = VerificationHistoryStore(url: url)
        let new = VerificationRecord(
            id: "vr-new",
            profileName: "p",
            printerName: "",
            avgDE: 2.0,
            maxDE: 2.0,
            rmsDE: 2.0,
            patchCount: 2,
            status: .good,
            timestamp: Date(timeIntervalSince1970: 10)
        )
        _ = try await store2.append(new)

        let all = await store2.all()
        #expect(all.count == 2)
        #expect(all.contains { $0.id == "vr-existing" })
        #expect(all.contains { $0.id == "vr-new" })
    }

    @Test("Append does not overwrite an unparseable file")
    func appendPreservesUnparseableFile() async {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("verification_history.json")

        let badJSON = "not json"
        try? badJSON.write(to: url, atomically: true, encoding: .utf8)

        let store = VerificationHistoryStore(url: url)
        let record = VerificationRecord(
            id: "vr-new",
            profileName: "p",
            printerName: "",
            avgDE: 1.0,
            maxDE: 1.0,
            rmsDE: 1.0,
            patchCount: 1,
            status: .good,
            timestamp: Date(timeIntervalSince1970: 0)
        )

        do {
            _ = try await store.append(record)
            Issue.record("append() should propagate the load error")
        } catch {
            #expect(fm.fileExists(atPath: url.path))
            if let data = try? Data(contentsOf: url),
               let contents = String(data: data, encoding: .utf8) {
                #expect(contents == badJSON)
            } else {
                Issue.record("Could not read preserved file")
            }
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
