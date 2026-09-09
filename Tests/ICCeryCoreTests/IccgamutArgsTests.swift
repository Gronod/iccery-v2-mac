import Foundation
import Testing
@testable import ICCeryCore

@Suite("IccgamutArgs")
struct IccgamutArgsTests {

    @Test("Density is 10 and not a directory")
    func densityNotDirectory() throws {
        let config = IccgamutConfig(
            profileURL: URL(fileURLWithPath: "/tmp/MyProfile.icc")
        )
        let args = try IccgamutArgs.build(config: config)
        #expect(args == ["-v", "-d", "10", "/tmp/MyProfile.icc"])
    }
}
