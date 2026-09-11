import Testing
import Foundation
@testable import ICCeryCore

private func tempStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("iccery-settings-\(UUID().uuidString)")
        .appendingPathComponent("settings.json")
}

@Suite("AppSettings")
struct AppSettingsTests {
    @Test func defaults() {
        let s = AppSettings.default
        #expect(s.argyllBinaryDir == nil)
        #expect(s.defaultInstrument == nil)
        #expect(s.logLevel == nil)
        #expect(s.deltaEGoodMax == 2.0)
        #expect(s.deltaEWarningMax == 5.0)
        #expect(s.customPresets.isEmpty)
        #expect(!s.enableI1Pro2Leds)
        #expect(s.calibrationStaleDays == 30)
        #expect(s.defaultInstallLocation == .user)
        #expect(s.askBeforeOverwriteProfile)
        #expect(!s.openColorPanelAfterInstall)
        #expect(s.isValid)
    }

    @Test func negativeThresholds() {
        var s = AppSettings.default
        s.deltaEGoodMax = -1
        #expect(s.validate() == [AppSettings.errorNegativeDeltaE])
        s.deltaEGoodMax = 2.0
        s.deltaEWarningMax = -0.5
        // -0.5 < 0 → negative error; good(2.0) >= warn(-0.5) → order error too
        #expect(s.validate() == [
            AppSettings.errorNegativeDeltaE,
            AppSettings.errorThresholdOrder,
        ])
    }

    @Test func goodMustBeStrictlyLessThanWarning() {
        var s = AppSettings.default
        s.deltaEGoodMax = 5.0
        #expect(s.validate() == [AppSettings.errorThresholdOrder])
        s.deltaEGoodMax = 6.0
        #expect(s.validate() == [AppSettings.errorThresholdOrder])
        s.deltaEGoodMax = 4.9
        #expect(s.isValid)
    }

    @Test func snakeCaseKeys() throws {
        let s = AppSettings.default
        let data = try JSONEncoder().encode(s)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"delta_e_good_max\""))
        #expect(json.contains("\"default_install_location\""))
        #expect(json.contains("\"enable_i1pro2_leds\""))
    }
}

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test func roundTrip() throws {
        let url = tempStoreURL()
        let store = SettingsStore(fileURL: url)
        var s = AppSettings.default
        s.deltaEGoodMax = 1.5
        s.defaultInstrument = "p3"
        try store.save(s)
        #expect(store.load() == s)
    }

    @Test func corruptJsonFallsBackToDefaults() throws {
        let url = tempStoreURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        #expect(SettingsStore(fileURL: url).load() == .default)
    }

    @Test func missingFileReturnsDefaults() {
        #expect(SettingsStore(fileURL: tempStoreURL()).load() == .default)
    }

    @Test func invalidSettingsNotPersisted() throws {
        let url = tempStoreURL()
        let store = SettingsStore(fileURL: url)
        var s = AppSettings.default
        s.deltaEGoodMax = 9.0 // >= warning 5.0
        #expect(throws: SettingsStore.SettingsError.self) { try store.save(s) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func invalidSaveOverValidFilePreservesBytesAndPostsNothing() throws {
        let url = tempStoreURL()
        let store = SettingsStore(fileURL: url)
        var valid = AppSettings.default
        valid.deltaEGoodMax = 1.5
        try store.save(valid)
        let originalBytes = try Data(contentsOf: url)

        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: SettingsStore.settingsDidChange, object: nil, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        var invalid = AppSettings.default
        invalid.deltaEGoodMax = 9.0
        #expect(throws: SettingsStore.SettingsError.self) { try store.save(invalid) }
        #expect(try Data(contentsOf: url) == originalBytes)
        #expect(!fired)
        #expect(store.load() == valid)
    }

    @Test func savePostsNotification() async throws {
        let url = tempStoreURL()
        let store = SettingsStore(fileURL: url)
        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: SettingsStore.settingsDidChange, object: nil, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }
        try store.save(.default)
        #expect(fired)
    }
}

@Suite("LogSink")
struct LogSinkTests {
    private func tempLog() -> (URL, LogSink) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-log-\(UUID().uuidString)")
            .appendingPathComponent("iccery.log")
        return (url, LogSink(fileURL: url))
    }

    @Test func writesFormattedLines() {
        let (url, sink) = tempLog()
        sink.setLevel(.debug)
        sink.write(level: .info, category: "test", message: "hello")
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        #expect(content.contains("[INFO] test: hello"))
    }

    @Test func levelFilteringIsLive() {
        let (url, sink) = tempLog()
        sink.setLevel(.error)
        sink.write(level: .info, category: "t", message: "hidden")
        sink.setLevel(.info)   // runtime change, no restart (#158)
        sink.write(level: .info, category: "t", message: "shown")
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        #expect(!content.contains("hidden"))
        #expect(content.contains("shown"))
    }

    @Test func rotatesAt5MiBKeeping5Segments() throws {
        let (url, sink) = tempLog()
        sink.setLevel(.trace)
        // Pre-fill the active log just under the cap, then cross it.
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let big = String(repeating: "x", count: Int(LogSink.maxSegmentBytes))
        try big.write(to: url, atomically: true, encoding: .utf8)

        sink.write(level: .info, category: "t", message: "trigger rotation")
        #expect(FileManager.default.fileExists(
            atPath: url.appendingPathExtension("1").path
        ))
        // Active log is small again.
        let size = try FileManager.default.attributesOfItem(
            atPath: url.path
        )[.size] as? UInt64
        #expect((size ?? 0) < 1024)
    }

    @Test func tailExcerptCaps() throws {
        let (url, sink) = tempLog()
        sink.setLevel(.debug)
        sink.write(level: .info, category: "t", message: "line")
        #expect(sink.tailExcerpt(maxBytes: 8).count <= 8)
    }
}
