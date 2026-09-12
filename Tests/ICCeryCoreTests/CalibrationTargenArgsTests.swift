import Foundation
import XCTest
@testable import ICCeryCore

final class CalibrationTargenArgsTests: XCTestCase {

    func testRgbBaseline() throws {
        let config = CalibrationTargenConfig(
            colourSpace: .rgb,
            steps: 21,
            whitePatches: 4,
            basename: "demo",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        let args = try CalibrationTargenArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-d", "2", "-s", "21", "-g", "21", "-e", "4", "-f", "0", "CAL_demo"])
    }

    func testCmykWithOptions() throws {
        let config = CalibrationTargenConfig(
            colourSpace: .cmyk,
            steps: 25,
            whitePatches: 4,
            includeNeutralEmphasis: true,
            inkLimit: 320,
            basename: "printer",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        let args = try CalibrationTargenArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-d", "4", "-s", "25", "-g", "25", "-e", "4", "-f", "0", "-n", "25", "-l", "320", "CAL_printer"])
    }

    func testRejectsBadSteps() {
        let config = CalibrationTargenConfig(steps: 5, basename: "demo")
        XCTAssertThrowsError(try CalibrationTargenArgs.build(config: config))
    }

    func testRejectsBadInkLimit() {
        let config = CalibrationTargenConfig(
            colourSpace: .cmyk,
            inkLimit: 500,
            basename: "demo"
        )
        XCTAssertThrowsError(try CalibrationTargenArgs.build(config: config))
    }

    func testNoDoublePrefix() throws {
        let config = CalibrationTargenConfig(basename: "CAL_test")
        let args = try CalibrationTargenArgs.build(config: config)
        XCTAssertEqual(args.last, "CAL_test")
    }
}
