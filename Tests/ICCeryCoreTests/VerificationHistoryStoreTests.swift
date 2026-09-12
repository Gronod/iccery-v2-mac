import Foundation
import XCTest
@testable import ICCeryCore

final class VerificationHistoryStoreTests: XCTestCase {

    func testAppendAndCap() async throws {
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
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first?.avgDE, 2.0)
    }

    func testParseFailurePreservesFile() async {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("verification_history.json")

        try? "not json".write(to: url, atomically: true, encoding: .utf8)

        let store = VerificationHistoryStore(url: url)
        do {
            _ = try await store.load()
            XCTFail("load() should throw on invalid JSON")
        } catch {
            XCTAssertTrue(fm.fileExists(atPath: url.path))
        }
    }

    func testAppendLoadsExisting() async throws {
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
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.id == "vr-existing" })
        XCTAssertTrue(all.contains { $0.id == "vr-new" })
    }

    func testAppendPreservesUnparseableFile() async {
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
            XCTFail("append() should propagate the load error")
        } catch {
            XCTAssertTrue(fm.fileExists(atPath: url.path))
            if let data = try? Data(contentsOf: url),
               let contents = String(data: data, encoding: .utf8) {
                XCTAssertEqual(contents, badJSON)
            } else {
                XCTFail("Could not read preserved file")
            }
        }
    }

    func testClearPreservesUnparseableFile() async {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("verification_history.json")

        let badJSON = "not json"
        try? badJSON.write(to: url, atomically: true, encoding: .utf8)

        let store = VerificationHistoryStore(url: url)
        do {
            try await store.clear()
            XCTFail("clear() should propagate the load error")
        } catch {
            let contents = try? String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(contents, badJSON)
        }
    }

    func testIso8601RoundTrip() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("verification_history.json")

        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let record = VerificationRecord(
            id: "vr-iso",
            profileName: "p",
            printerName: "",
            avgDE: 1.0,
            maxDE: 2.0,
            rmsDE: 1.5,
            patchCount: 1,
            status: .good,
            timestamp: timestamp
        )
        let store1 = VerificationHistoryStore(url: url)
        _ = try await store1.append(record)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains(ISO8601DateFormatter().string(from: timestamp)))

        let store2 = VerificationHistoryStore(url: url)
        let loaded = try await store2.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.timestamp, timestamp)
    }

    func testCsvQuoting() async throws {
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
        XCTAssertTrue(csv.contains("\"a,b\""))
        XCTAssertTrue(csv.contains("\"\"quoted\"\""))
    }
}
