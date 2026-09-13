import Foundation
import XCTest
@testable import ICCeryCore

/// Issue #149 — `recent_projects.json`: cap 20, newest first, dedupe
/// by path, missing files pruned on submenu build, Clear Menu wipes the
/// recents file only, corrupt file kept (R12).
final class RecentProjectsStoreTests: XCTestCase {

    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-recents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    private var storeURL: URL {
        root.appendingPathComponent("recent_projects.json")
    }

    private func projectFile(_ name: String) throws -> URL {
        let url = root.appendingPathComponent("\(name).icceryproj")
        try "{}".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testCapTwentyNewestFirst() async throws {
        let store = RecentProjectsStore(url: storeURL)
        for i in 0..<25 {
            let url = try projectFile("p\(i)")
            try await store.add(url: url, name: "P\(i)")
        }
        let all = try await store.load()
        XCTAssertEqual(all.count, 20)
        XCTAssertEqual(all.first?.name, "P24")
        XCTAssertEqual(all.last?.name, "P5")
    }

    func testAddDeduplicatesByPath() async throws {
        let store = RecentProjectsStore(url: storeURL)
        let url = try projectFile("dup")
        try await store.add(url: url, name: "First")
        try await store.add(url: try projectFile("other"), name: "Other")
        try await store.add(url: url, name: "Second")

        let all = try await store.load()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.name, "Second")
        XCTAssertEqual(
            all.filter { $0.path == url.path }.count, 1)
    }

    func testPruneMissingDropsGoneFiles() async throws {
        let store = RecentProjectsStore(url: storeURL)
        let live = try projectFile("live")
        try await store.add(url: live, name: "Live")
        try await store.add(
            url: root.appendingPathComponent("gone.icceryproj"),
            name: "Gone")

        let pruned = try await store.pruneMissing()
        XCTAssertEqual(pruned.count, 1)
        XCTAssertEqual(pruned.first?.name, "Live")

        // The rewrite persisted the drop.
        let reloaded = try await RecentProjectsStore(url: storeURL).load()
        XCTAssertEqual(reloaded.count, 1)
    }

    func testRemoveByPath() async throws {
        let store = RecentProjectsStore(url: storeURL)
        let url = try projectFile("a")
        try await store.add(url: url, name: "A")
        let removed = try await store.remove(path: url.path)
        XCTAssertTrue(removed)
        let loaded = try await store.load()
        XCTAssertTrue(loaded.isEmpty)
        let second = try await store.remove(path: url.path)
        XCTAssertFalse(second)
    }

    func testClearWipesRecentsFileOnly() async throws {
        let store = RecentProjectsStore(url: storeURL)
        let projectURL = try projectFile("keep")
        try await store.add(url: projectURL, name: "Keep")

        try await store.clear()

        let loaded = try await store.load()
        XCTAssertTrue(loaded.isEmpty)
        // The `.icceryproj` itself survives Clear Menu.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: projectURL.path))
        let raw = try String(contentsOf: storeURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("["))
    }

    func testCorruptFileThrowsAndKeepsBytes() async throws {
        try "not json".write(
            to: storeURL, atomically: true, encoding: .utf8)
        let store = RecentProjectsStore(url: storeURL)

        await assertAsyncThrows(expectedType: DecodingError.self) {
            try await store.load()
        }
        XCTAssertEqual(
            try String(contentsOf: storeURL, encoding: .utf8), "not json")
    }

    func testEntryStoresBookmarkAndPath() async throws {
        let store = RecentProjectsStore(url: storeURL)
        let url = try projectFile("b")
        try await store.add(url: url, name: "B")
        let entry = try await store.load().first
        XCTAssertEqual(entry?.path, url.path)
        XCTAssertNotNil(entry?.bookmark)
        XCTAssertFalse(entry?.bookmarkHash.isEmpty ?? true)
    }

    func testBookmarkHashStableAcrossStores() async throws {
        let a = RecentProjectEntry(name: "x", path: "/tmp/p.icceryproj")
        let b = RecentProjectEntry(name: "y", path: "/tmp/p.icceryproj")
        XCTAssertEqual(a.bookmarkHash, b.bookmarkHash)
        let c = RecentProjectEntry(name: "z", path: "/tmp/q.icceryproj")
        XCTAssertNotEqual(a.bookmarkHash, c.bookmarkHash)
    }
}
