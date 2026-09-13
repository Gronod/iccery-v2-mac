import XCTest
@testable import ICCeryCore

/// `SpotReadClassifier` / `SpotReadParser` against real `spotread`
/// phrasing (issue #148). The calibration-tile line classifies through
/// `ChartreadClassifier`; the spot prompt and its continuation lines
/// need the spot-specific matchers.
final class SpotReadClassifierTests: XCTestCase {

    // Real `spotread` stdout (calibration then spot prompt).
    private let calibrateLines = [
        "Spot read needs a calibration before continuing",
        "Place instrument on spot reading white calibration tile,",
        " and then hit any key to continue,",
        "or hit Esc or Q to abort:",
    ]
    private let spotPromptLines = [
        "Place instrument on a spot to be measured,",
        " and hit a key to take a reading,",
        "or hit Esc or Q to abort:",
    ]

    func testCalibrationPrompt() {
        var state = ChartreadState.idle
        for line in calibrateLines {
            state = SpotReadClassifier.classify(line: line, previousState: state).state
        }
        XCTAssertEqual(state, .calibrating)
    }

    func testSpotPromptIsAwaitingTrigger() {
        var state = ChartreadState.calibrating
        for line in spotPromptLines {
            state = SpotReadClassifier.classify(line: line, previousState: state).state
        }
        XCTAssertEqual(state, .awaitingStrip)
    }

    func testAbortLineDoesNotBecomeWarning() {
        // "or hit Esc or Q to abort:" contains no '?' but does contain
        // "abort" — it must stay on the current prompt, never flip to
        // a warning.
        let r = SpotReadClassifier.classify(
            line: "or hit Esc or Q to abort:", previousState: .awaitingStrip)
        XCTAssertEqual(r.state, .awaitingStrip)
    }

    func testParseResultLine() throws {
        let parsed = SpotReadParser.parse(
            line: "Result is XYZ: 18.51 20.05 15.71, D50 Lab: 51.9 -8.3 12.2")
        let lab = try XCTUnwrap(parsed?.lab)
        XCTAssertEqual(lab.l, 51.9, accuracy: 0.001)
        XCTAssertEqual(lab.a, -8.3, accuracy: 0.001)
        XCTAssertEqual(lab.b, 12.2, accuracy: 0.001)
        let xyz = try XCTUnwrap(parsed?.xyz)
        XCTAssertEqual(xyz.x, 18.51, accuracy: 0.001)
        XCTAssertEqual(xyz.y, 20.05, accuracy: 0.001)
        XCTAssertEqual(xyz.z, 15.71, accuracy: 0.001)
    }

    func testParseLabOnlyLine() throws {
        let parsed = SpotReadParser.parse(line: "Result is Lab: 40.0 1.2 -3.4")
        let lab = try XCTUnwrap(parsed?.lab)
        XCTAssertEqual(lab.l, 40.0, accuracy: 0.001)
        XCTAssertNil(parsed?.xyz)
    }

    func testNonSampleLineParsesNil() {
        XCTAssertNil(SpotReadParser.parse(line: "Place instrument on a spot to be measured,"))
        XCTAssertNil(SpotReadParser.parse(line: "Calibration successful."))
        XCTAssertNil(SpotReadParser.parse(line: ""))
    }

    func testDeltaEBetweenFixtures() {
        let a = SpotReadParser.parse(
            line: "Result is XYZ: 18.51 20.05 15.71, D50 Lab: 51.9 -8.3 12.2")!.lab
        let b = SpotReadParser.parse(
            line: "Result is XYZ: 19.00 20.50 16.00, D50 Lab: 52.3 -8.0 12.6")!.lab
        XCTAssertEqual(ColorDifference.deltaE00(a, a), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(ColorDifference.deltaE00(a, b), 0)
        XCTAssertEqual(
            ColorDifference.classify(deltaE: 1.0, goodMax: 2.0, warningMax: 5.0),
            .good)
        XCTAssertEqual(
            ColorDifference.classify(deltaE: 3.0, goodMax: 2.0, warningMax: 5.0),
            .warning)
        XCTAssertEqual(
            ColorDifference.classify(deltaE: 6.0, goodMax: 2.0, warningMax: 5.0),
            .bad)
    }
}
