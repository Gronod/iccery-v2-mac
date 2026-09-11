import Foundation
import XCTest
@testable import ICCeryCore

/// Issue #83 — canonical `CAL_` / original-stem pairing.
final class CalibrationIdentityTests: XCTestCase {
    func testLivePlain() {
        let id = CalibrationIdentity.parse(liveBasename: "foo", persistedOriginal: "")
        XCTAssertEqual(id.originalBasename, "foo")
        XCTAssertEqual(id.calibrationBasename, "CAL_foo")
    }

    func testLivePlainIgnoresPersisted() {
        let id = CalibrationIdentity.parse(liveBasename: "foo", persistedOriginal: "bar")
        XCTAssertEqual(id.originalBasename, "foo")
        XCTAssertEqual(id.calibrationBasename, "CAL_foo")
    }

    func testLiveCalPersisted() {
        let id = CalibrationIdentity.parse(liveBasename: "CAL_foo", persistedOriginal: "foo")
        XCTAssertEqual(id.originalBasename, "foo")
        XCTAssertEqual(id.calibrationBasename, "CAL_foo")
    }

    func testLiveCalNoPersist() {
        let id = CalibrationIdentity.parse(liveBasename: "CAL_foo", persistedOriginal: "")
        XCTAssertEqual(id.originalBasename, "foo")
        XCTAssertEqual(id.calibrationBasename, "CAL_foo")
    }

    func testPersistedWins() {
        let id = CalibrationIdentity.parse(liveBasename: "CAL_foo", persistedOriginal: "bar")
        XCTAssertEqual(id.originalBasename, "bar")
        XCTAssertEqual(id.calibrationBasename, "CAL_bar")
    }

    func testEmptyLiveWithPersisted() {
        let id = CalibrationIdentity.parse(liveBasename: "", persistedOriginal: "foo")
        XCTAssertTrue(id.originalBasename.isEmpty)
        XCTAssertTrue(id.calibrationBasename.isEmpty)
    }

    func testEmptyLive() {
        let id = CalibrationIdentity.parse(liveBasename: "", persistedOriginal: "")
        XCTAssertTrue(id.originalBasename.isEmpty)
        XCTAssertTrue(id.calibrationBasename.isEmpty)
    }

    func testAlreadyPrefixed() {
        XCTAssertEqual(CalibrationIdentity.prefix("CAL_foo"), "CAL_foo")
        XCTAssertEqual(CalibrationIdentity.prefix("foo"), "CAL_foo")
        let id = CalibrationIdentity.parse(liveBasename: "CAL_CAL_foo", persistedOriginal: "")
        XCTAssertEqual(id.originalBasename, "CAL_foo")
        XCTAssertEqual(id.calibrationBasename, "CAL_foo")
    }

    func testPrefixEmpty() {
        XCTAssertTrue(CalibrationIdentity.prefix("").isEmpty)
        XCTAssertEqual(CalibrationIdentity.strip("foo"), "foo")
        XCTAssertEqual(CalibrationIdentity.strip("CAL_foo"), "foo")
    }

    func testProcessIdMatches() {
        let cal = CalibrationIdentity.prefix("foo")
        XCTAssertEqual(ProcessID.targen(cal), "targen_CAL_foo")
    }
}
