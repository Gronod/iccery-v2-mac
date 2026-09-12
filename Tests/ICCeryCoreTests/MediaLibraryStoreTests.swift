import Foundation
import XCTest
@testable import ICCeryCore

/// Issue #146 — `MediaLibraryStore` persistence contract.
final class MediaLibraryStoreTests: XCTestCase {

    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-lib-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        url = nil
    }

    private func recipe(id: String, name: String = "R") -> MediaRecipe {
        MediaRecipe(
            id: id, name: name, printerID: "q",
            colourSpace: "rgb", presetID: "preset-std-rgb")
    }

    func testRoundTrip() async throws {
        let store = MediaLibraryStore(url: url)
        let r = recipe(id: "recipe-1", name: "Epson Rag")
        try await store.upsert(r)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [r])
    }

    func testCorruptFileThrowsAndPreservesBytes() async throws {
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: url)

        let store = MediaLibraryStore(url: url)
        await assertAsyncThrows(expectedType: DecodingError.self) {
            try await store.load()
        }
        // upsert must also propagate — a corrupt file is never wiped.
        await assertAsyncThrows(expectedType: DecodingError.self) {
            try await store.upsert(recipe(id: "x"))
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testDelete() async throws {
        let store = MediaLibraryStore(url: url)
        try await store.upsert(recipe(id: "a"))
        try await store.upsert(recipe(id: "b"))

        let removed = try await store.delete(id: "a")
        XCTAssertTrue(removed)
        let remaining = try await store.load().map(\.id)
        XCTAssertEqual(remaining, ["b"])

        let again = try await store.delete(id: "a")
        XCTAssertFalse(again)
    }

    func testCapacityReached() async throws {
        let store = MediaLibraryStore(url: url, capacity: 2)
        try await store.upsert(recipe(id: "1"))
        try await store.upsert(recipe(id: "2"))
        await assertAsyncThrows(
            expectedType: MediaLibraryStore.MediaLibraryError.self
        ) {
            try await store.upsert(recipe(id: "3"))
        } errorHandler: {
            XCTAssertEqual($0, .capacityReached(2))
        }
        let stored = try await store.load()
        XCTAssertEqual(stored.count, 2)
    }

    func testUpsertPreservesCreatedBumpsUpdated() async throws {
        let store = MediaLibraryStore(url: url)
        var r = recipe(id: "recipe-1")
        r.created = Date(timeIntervalSince1970: 1_000_000)
        r.updated = Date(timeIntervalSince1970: 1_000_000)
        try await store.upsert(r)

        var edit = r
        edit.name = "Renamed"
        edit.updated = Date(timeIntervalSince1970: 2_000_000)
        try await store.upsert(edit)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Renamed")
        XCTAssertEqual(loaded[0].created, r.created)
        XCTAssertGreaterThan(loaded[0].updated, r.updated)
    }
}
