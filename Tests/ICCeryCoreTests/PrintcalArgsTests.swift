import Foundation
import XCTest
@testable import ICCeryCore

final class PrintcalArgsTests: XCTestCase {

    private let tmp = URL(fileURLWithPath: "/tmp/out.cal")

    func testDefaults() throws {
        let config = PrintcalConfig(
            ti3Basename: "CAL_demo",
            outputURL: tmp
        )
        let args = try PrintcalArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-e", "-o", "/tmp/out.cal", "CAL_demo"])
    }

    func testAllOptions() throws {
        let config = PrintcalConfig(
            ti3Basename: "demo",
            outputURL: tmp,
            noInkLimit: true,
            verify: true,
            previousCalPath: "/tmp/old.cal",
            totalInkLimit: 280,
            channelLimits: [
                PrintcalChannelLimit(channel: "C", percent: 95),
                PrintcalChannelLimit(channel: "M", percent: 90)
            ]
        )
        let args = try PrintcalArgs.build(config: config)
        XCTAssertEqual(args, [
            "-v", "-e",
            "-I", "-z",
            "-a", "/tmp/old.cal",
            "-m", "280.0",
            "-xC", "95.0",
            "-xM", "90.0",
            "-o", "/tmp/out.cal",
            "CAL_demo"
        ])
    }

    func testWhitespacePreviousCal() throws {
        let config = PrintcalConfig(
            ti3Basename: "demo",
            outputURL: tmp,
            previousCalPath: "   \n\t "
        )
        let args = try PrintcalArgs.build(config: config)
        XCTAssertFalse(args.contains("-a"))
        XCTAssertEqual(args, ["-v", "-e", "-o", "/tmp/out.cal", "CAL_demo"])
    }

    func testPreviousCalTrimmed() throws {
        let config = PrintcalConfig(
            ti3Basename: "demo",
            outputURL: tmp,
            previousCalPath: "  /tmp/old.cal  "
        )
        let args = try PrintcalArgs.build(config: config)
        XCTAssertEqual(args[args.firstIndex(of: "-a")! + 1], "/tmp/old.cal")
    }

    func testRejectsBadChannelLimit() {
        let config = PrintcalConfig(
            ti3Basename: "demo",
            outputURL: tmp,
            channelLimits: [PrintcalChannelLimit(channel: "K", percent: 150)]
        )
        XCTAssertThrowsError(try PrintcalArgs.build(config: config))
    }

}
