import Foundation
import XCTest
@testable import ICCeryCore

final class ProfcheckArgsTests: XCTestCase {

    func testArgv() throws {
        let config = ProfcheckConfig(
            ti3URL: URL(fileURLWithPath: "/tmp/target.ti3"),
            iccURL: URL(fileURLWithPath: "/tmp/target.icc")
        )
        let args = try ProfcheckArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-k", "-s", "-u", "/tmp/target.ti3", "/tmp/target.icc"])
    }
}
