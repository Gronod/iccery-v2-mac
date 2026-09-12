import Foundation
import XCTest
@testable import ICCeryCore

final class IccgamutArgsTests: XCTestCase {

    func testDensityNotDirectory() throws {
        let config = IccgamutConfig(
            profileURL: URL(fileURLWithPath: "/tmp/MyProfile.icc")
        )
        let args = try IccgamutArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-d", "10", "/tmp/MyProfile.icc"])
    }
}
