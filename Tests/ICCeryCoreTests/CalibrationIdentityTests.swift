import Foundation
import Testing
@testable import ICCeryCore

/// Issue #83 — canonical `CAL_` / original-stem pairing.
@Suite("CalibrationIdentity")
struct CalibrationIdentityTests {
    @Test("live foo, no persisted")
    func livePlain() {
        let id = CalibrationIdentity.parse(liveBasename: "foo", persistedOriginal: "")
        #expect(id.originalBasename == "foo")
        #expect(id.calibrationBasename == "CAL_foo")
    }

    @Test("live foo ignores stale persisted")
    func livePlainIgnoresPersisted() {
        let id = CalibrationIdentity.parse(liveBasename: "foo", persistedOriginal: "bar")
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

    @Test("persisted original wins over CAL_ live")
    func persistedWins() {
        let id = CalibrationIdentity.parse(liveBasename: "CAL_foo", persistedOriginal: "bar")
        #expect(id.originalBasename == "bar")
        #expect(id.calibrationBasename == "CAL_bar")
    }

    @Test("empty live yields empty identity even with persisted original")
    func emptyLiveWithPersisted() {
        let id = CalibrationIdentity.parse(liveBasename: "", persistedOriginal: "foo")
        #expect(id.originalBasename.isEmpty)
        #expect(id.calibrationBasename.isEmpty)
    }

    @Test("empty live, empty persisted")
    func emptyLive() {
        let id = CalibrationIdentity.parse(liveBasename: "", persistedOriginal: "")
        #expect(id.originalBasename.isEmpty)
        #expect(id.calibrationBasename.isEmpty)
    }

    @Test("prefix is idempotent on already-prefixed input")
    func alreadyPrefixed() {
        #expect(CalibrationIdentity.prefix("CAL_foo") == "CAL_foo")
        #expect(CalibrationIdentity.prefix("foo") == "CAL_foo")
        let id = CalibrationIdentity.parse(liveBasename: "CAL_CAL_foo", persistedOriginal: "")
        #expect(id.originalBasename == "CAL_foo")
        #expect(id.calibrationBasename == "CAL_foo")
    }

    @Test("prefix never invents a name from empty input")
    func prefixEmpty() {
        #expect(CalibrationIdentity.prefix("").isEmpty)
        #expect(CalibrationIdentity.strip("foo") == "foo")
        #expect(CalibrationIdentity.strip("CAL_foo") == "foo")
    }

    @Test("runner process id for a calibration targen is targen_CAL_*")
    func processIdMatches() {
        let cal = CalibrationIdentity.prefix("foo")
        #expect(ProcessID.targen(cal) == "targen_CAL_foo")
    }
}
