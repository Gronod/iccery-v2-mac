import Foundation
import Testing
@testable import ICCeryCore

@Suite("PrintcalArgs")
struct PrintcalArgsTests {

    private let tmp = URL(fileURLWithPath: "/tmp/out.cal")

    @Test("Default printcal argv")
    func defaults() throws {
        let config = PrintcalConfig(
            ti3Basename: "CAL_demo",
            outputURL: tmp
        )
        let args = try PrintcalArgs.build(config: config)
        #expect(args == ["-v", "-e", "-o", "/tmp/out.cal", "CAL_demo"])
    }

    @Test("All options and channel limits")
    func allOptions() throws {
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
        #expect(args == [
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

    @Test("Rejects invalid per-channel limit")
    func rejectsBadChannelLimit() {
        let config = PrintcalConfig(
            ti3Basename: "demo",
            outputURL: tmp,
            channelLimits: [PrintcalChannelLimit(channel: "K", percent: 150)]
        )
        #expect(throws: (any Error).self) {
            _ = try PrintcalArgs.build(config: config)
        }
    }

}
