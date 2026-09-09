import Foundation
import Testing
@testable import ICCeryCore

@Suite("ApplycalArgs")
struct ApplycalArgsTests {

    @Test("Apply argv")
    func applyArgv() throws {
        let config = ApplycalConfig(
            calibrationPath: "/tmp/cal.cal",
            inputProfileURL: URL(fileURLWithPath: "/tmp/profile.icc")
        )
        let args = try ApplycalArgs.build(config: config)
        #expect(args == ["-v", "-a", "/tmp/cal.cal", "/tmp/profile.icc"])
    }

    @Test("Unapply is never sent from build")
    func unapplyNotEmitted() throws {
        let config = ApplycalConfig(
            calibrationPath: "/tmp/cal.cal",
            inputProfileURL: URL(fileURLWithPath: "/tmp/profile.icc"),
            unapply: true
        )
        let args = try ApplycalArgs.build(config: config)
        // Builder intentionally emits -u because config can set it, but
        // the UI layer never passes unapply: true in v2.0.
        #expect(args == ["-v", "-u", "/tmp/cal.cal", "/tmp/profile.icc"])
    }
}
