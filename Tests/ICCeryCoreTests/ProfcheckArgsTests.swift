import Foundation
import Testing
@testable import ICCeryCore

@Suite("ProfcheckArgs")
struct ProfcheckArgsTests {

    @Test("Hard-coded argv")
    func argv() throws {
        let config = ProfcheckConfig(
            ti3URL: URL(fileURLWithPath: "/tmp/target.ti3"),
            iccURL: URL(fileURLWithPath: "/tmp/target.icc")
        )
        let args = try ProfcheckArgs.build(config: config)
        #expect(args == ["-v", "-k", "-s", "-u", "/tmp/target.ti3", "/tmp/target.icc"])
    }
}
