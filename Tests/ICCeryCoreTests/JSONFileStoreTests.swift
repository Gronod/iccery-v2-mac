import Foundation
import Testing
@testable import ICCeryCore

@Suite("JSONFileStore")
struct JSONFileStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("json-store-\(UUID().uuidString).json")
    }

    @Test("Corrupt file with replaceWithDefault returns default")
    func corruptDefaults() throws {
        let url = tempURL()
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        let store = JSONFileStore<AppSettings>(
            fileURL: url,
            corrupt: .replaceWithDefault,
            defaultValue: { .default }
        )
        #expect(try store.load() == .default)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Corrupt file with throwCorrupt throws and leaves bytes")
    func corruptThrows() throws {
        let url = tempURL()
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let store = JSONFileStore<[Int]>(
            fileURL: url,
            corrupt: .throwCorrupt,
            defaultValue: { [] }
        )
        #expect(throws: DecodingError.self) {
            _ = try store.load()
        }
        let kept = try String(contentsOf: url, encoding: .utf8)
        #expect(kept == "not json")
    }

    @Test("Pretty sorted keys")
    func prettySorted() throws {
        let url = tempURL()
        let store = JSONFileStore<AppSettings>(
            fileURL: url,
            corrupt: .replaceWithDefault,
            defaultValue: { .default }
        )
        try store.save(.default)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\n"))
        #expect(text.contains("\"delta_e_good_max\""))
    }
}

@Suite("CalibrationIdentity")
struct CalibrationIdentityTests {
    @Test("live foo, no persisted")
    func livePlain() {
        let id = CalibrationIdentity.parse(liveBasename: "foo", persistedOriginal: "")
        #expect(id.originalBasename == "foo")
        #expect(id.calibrationBasename == "CAL_foo")
    }

    @Test("live CAL_foo, persisted foo")
    func liveCalPersisted() {
        let id = CalibrationIdentity.parse(liveBasename: "CAL_foo", persistedOriginal: "foo")
        #expect(id.originalBasename == "foo")
        #expect(id.calibrationBasename == "CAL_foo")
    }

    @Test("live CAL_foo, empty persisted strips prefix")
    func liveCalNoPersist() {
        let id = CalibrationIdentity.parse(liveBasename: "CAL_foo", persistedOriginal: "")
        #expect(id.originalBasename == "foo")
        #expect(id.calibrationBasename == "CAL_foo")
    }

    @Test("persisted original wins")
    func persistedWins() {
        let id = CalibrationIdentity.parse(liveBasename: "CAL_foo", persistedOriginal: "bar")
        #expect(id.originalBasename == "bar")
        #expect(id.calibrationBasename == "CAL_bar")
    }

    @Test("empty live does not invent a name")
    func emptyLive() {
        let id = CalibrationIdentity.parse(liveBasename: "", persistedOriginal: "")
        #expect(id.originalBasename.isEmpty)
        #expect(id.calibrationBasename.isEmpty)
    }
}
