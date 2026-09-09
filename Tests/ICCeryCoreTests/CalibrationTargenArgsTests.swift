import Foundation
import Testing
@testable import ICCeryCore

@Suite("CalibrationTargenArgs")
struct CalibrationTargenArgsTests {

    @Test("RGB baseline")
    func rgbBaseline() throws {
        let config = CalibrationTargenConfig(
            colourSpace: .rgb,
            steps: 21,
            whitePatches: 4,
            basename: "demo",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        let args = try CalibrationTargenArgs.build(config: config)
        #expect(args == ["-v", "-d", "2", "-s", "21", "-g", "21", "-e", "4", "-f", "0", "CAL_demo"])
    }

    @Test("CMYK baseline with ink limit and neutral emphasis")
    func cmykWithOptions() throws {
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
        #expect(args == ["-v", "-d", "4", "-s", "25", "-g", "25", "-e", "4", "-f", "0", "-n", "25", "-l", "320", "CAL_printer"])
    }

    @Test("Rejects out-of-range steps")
    func rejectsBadSteps() {
        let config = CalibrationTargenConfig(steps: 5, basename: "demo")
        #expect(throws: (any Error).self) {
            _ = try CalibrationTargenArgs.build(config: config)
        }
    }

    @Test("Rejects bad CMYK ink limit")
    func rejectsBadInkLimit() {
        let config = CalibrationTargenConfig(
            colourSpace: .cmyk,
            inkLimit: 500,
            basename: "demo"
        )
        #expect(throws: (any Error).self) {
            _ = try CalibrationTargenArgs.build(config: config)
        }
    }

    @Test("Does not double-prefix an existing CAL_ basename")
    func noDoublePrefix() throws {
        let config = CalibrationTargenConfig(basename: "CAL_test")
        let args = try CalibrationTargenArgs.build(config: config)
        #expect(args.last == "CAL_test")
    }
}
