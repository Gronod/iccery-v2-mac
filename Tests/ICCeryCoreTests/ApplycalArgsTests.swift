import Foundation
import XCTest
@testable import ICCeryCore

final class ApplycalArgsTests: XCTestCase {

    func testApplyArgv() throws {
        let config = ApplycalConfig(
            calibrationPath: "/tmp/cal.cal",
            inputProfileURL: URL(fileURLWithPath: "/tmp/profile.icc")
        )
        let args = try ApplycalArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-a", "/tmp/cal.cal", "/tmp/profile.icc"])
    }

    func testUnapplyEmittedWhenConfigSet() throws {
        let config = ApplycalConfig(
            calibrationPath: "/tmp/cal.cal",
            inputProfileURL: URL(fileURLWithPath: "/tmp/profile.icc"),
            unapply: true
        )
        let args = try ApplycalArgs.build(config: config)
        // Builder emits -u only when the caller explicitly sets unapply.
        // The UI layer never passes unapply: true in v2.0.
        XCTAssertEqual(args, ["-v", "-u", "/tmp/cal.cal", "/tmp/profile.icc"])
    }
}
