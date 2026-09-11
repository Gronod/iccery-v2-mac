import Foundation
import XCTest
@testable import ICCeryCore

private func tempStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("iccery-settings-\(UUID().uuidString)")
        .appendingPathComponent("settings.json")
}

final class AppSettingsTests: XCTestCase {
    func testDefaults() {
        let s = AppSettings.default
        XCTAssertNil(s.argyllBinaryDir)
        XCTAssertNil(s.defaultInstrument)
        XCTAssertNil(s.logLevel)
        XCTAssertEqual(s.deltaEGoodMax, 2.0)
        XCTAssertEqual(s.deltaEWarningMax, 5.0)
        XCTAssertTrue(s.customPresets.isEmpty)
        XCTAssertFalse(s.enableI1Pro2Leds)
        XCTAssertEqual(s.calibrationStaleDays, 30)
        XCTAssertEqual(s.defaultInstallLocation, .user)
        XCTAssertTrue(s.askBeforeOverwriteProfile)
        XCTAssertFalse(s.openColorPanelAfterInstall)
        XCTAssertTrue(s.isValid)
    }

    func testNegativeThresholds() {
        var s = AppSettings.default
        s.deltaEGoodMax = -1
        XCTAssertEqual(s.validate(), [AppSettings.errorNegativeDeltaE])
        s.deltaEGoodMax = 2.0
        s.deltaEWarningMax = -0.5
        // -0.5 < 0 → negative error; good(2.0) >= warn(-0.5) → order error too
        XCTAssertTrue(s.validate() == [
            AppSettings.errorNegativeDeltaE,
            AppSettings.errorThresholdOrder,
        ])
    }

    func testGoodMustBeStrictlyLessThanWarning() {
        var s = AppSettings.default
        s.deltaEGoodMax = 5.0
        XCTAssertEqual(s.validate(), [AppSettings.errorThresholdOrder])
        s.deltaEGoodMax = 6.0
        XCTAssertEqual(s.validate(), [AppSettings.errorThresholdOrder])
        s.deltaEGoodMax = 4.9
        XCTAssertTrue(s.isValid)
    }

    func testSnakeCaseKeys() throws {
        let s = AppSettings.default
        let data = try JSONEncoder().encode(s)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"delta_e_good_max\""))
        XCTAssertTrue(json.contains("\"default_install_location\""))
        XCTAssertTrue(json.contains("\"enable_i1pro2_leds\""))
    }
}

final class SettingsStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let url = tempStoreURL()
        let store = SettingsStore(fileURL: url)
        var s = AppSettings.default
        s.deltaEGoodMax = 1.5
        s.defaultInstrument = "p3"
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testCorruptJsonFallsBackToDefaults() throws {
        let url = tempStoreURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(SettingsStore(fileURL: url).load(), .default)
    }

    func testMissingFileReturnsDefaults() {
        XCTAssertEqual(SettingsStore(fileURL: tempStoreURL()).load(), .default)
    }

    func testInvalidSettingsNotPersisted() throws {
        let url = tempStoreURL()
        let store = SettingsStore(fileURL: url)
        var s = AppSettings.default
        s.deltaEGoodMax = 9.0 // >= warning 5.0
        XCTAssertThrowsError(try store.save(s)) { error in XCTAssertTrue(error is SettingsStore.SettingsError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testInvalidSaveOverValidFilePreservesBytesAndPostsNothing() throws {
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
        XCTAssertThrowsError(try store.save(invalid)) { error in XCTAssertTrue(error is SettingsStore.SettingsError) }
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        XCTAssertFalse(fired)
        XCTAssertEqual(store.load(), valid)
    }

    func testSavePostsNotification() async throws {
        let url = tempStoreURL()
        let store = SettingsStore(fileURL: url)
        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: SettingsStore.settingsDidChange, object: nil, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }
        try store.save(.default)
        XCTAssertTrue(fired)
    }
}

final class LogSinkTests: XCTestCase {
    private func tempLog() -> (URL, LogSink) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-log-\(UUID().uuidString)")
            .appendingPathComponent("iccery.log")
        return (url, LogSink(fileURL: url))
    }

    func testWritesFormattedLines() {
        let (url, sink) = tempLog()
        sink.setLevel(.debug)
        sink.write(level: .info, category: "test", message: "hello")
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertTrue(content.contains("[INFO] test: hello"))
    }

    func testLevelFilteringIsLive() {
        let (url, sink) = tempLog()
        sink.setLevel(.error)
        sink.write(level: .info, category: "t", message: "hidden")
        sink.setLevel(.info)   // runtime change, no restart (#158)
        sink.write(level: .info, category: "t", message: "shown")
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertFalse(content.contains("hidden"))
        XCTAssertTrue(content.contains("shown"))
    }

    func testRotatesAt5MiBKeeping5Segments() throws {
        let (url, sink) = tempLog()
        sink.setLevel(.trace)
        // Pre-fill the active log just under the cap, then cross it.
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let big = String(repeating: "x", count: Int(LogSink.maxSegmentBytes))
        try big.write(to: url, atomically: true, encoding: .utf8)

        sink.write(level: .info, category: "t", message: "trigger rotation")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: url.appendingPathExtension("1").path
        ))
        // Active log is small again.
        let size = try FileManager.default.attributesOfItem(
            atPath: url.path
        )[.size] as? UInt64
        XCTAssertTrue((size ?? 0) < 1024)
    }

    func testTailExcerptCaps() throws {
        let (url, sink) = tempLog()
        sink.setLevel(.debug)
        sink.write(level: .info, category: "t", message: "line")
        XCTAssertTrue(sink.tailExcerpt(maxBytes: 8).count <= 8)
    }
}
