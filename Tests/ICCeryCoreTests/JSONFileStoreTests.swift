import Foundation
import Testing
@testable import ICCeryCore

@Suite("JSONFileStore")
struct JSONFileStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("json-store-\(UUID().uuidString).json")
    }

    @Test("Missing file returns default")
    func missingFileDefaults() throws {
        let store = JSONFileStore<AppSettings>(
            fileURL: tempURL(),
            corrupt: .throwCorrupt,
            defaultValue: { .default }
        )
        #expect(try store.load() == .default)
    }

    @Test("Corrupt file with replaceWithDefault returns default and leaves bytes")
    func corruptDefaults() throws {
        let url = tempURL()
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        let store = JSONFileStore<AppSettings>(
            fileURL: url,
            corrupt: .replaceWithDefault,
            defaultValue: { .default }
        )
        #expect(try store.load() == .default)
        let kept = try String(contentsOf: url, encoding: .utf8)
        #expect(kept == "{ not json")
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
        // Lexical key sorting: ascending order of top-level keys.
        let keys = [
            "ask_before_overwrite_profile",
            "calibration_stale_days",
            "custom_presets",
            "default_install_location",
            "delta_e_good_max",
            "delta_e_warning_max",
            "enable_i1pro2_leds",
            "open_color_panel_after_install",
        ]
        var lastIndex = text.startIndex
        for key in keys {
            guard let range = text.range(of: "\"\(key)\"", range: lastIndex..<text.endIndex) else {
                Issue.record("missing or out-of-order key \(key)")
                return
            }
            lastIndex = range.upperBound
        }
    }
}
