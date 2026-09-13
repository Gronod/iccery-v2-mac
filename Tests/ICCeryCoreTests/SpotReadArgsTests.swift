import XCTest
@testable import ICCeryCore

/// `SpotReadArgs` goldens (issue #148):
/// `spotread -v -e [-c port] [-Y l]` — never `-u`, never a basename,
/// `-c` only for ports > 1, `-Y l` only when the LED setting is on.
final class SpotReadArgsTests: XCTestCase {

    func testAutoOmitsPort() {
        let args = SpotReadArgs.build(config: SpotReadConfig())
        XCTAssertEqual(args, ["-v", "-e"])
    }

    func testPort1OmitsC() {
        let args = SpotReadArgs.build(config: SpotReadConfig(selectedPort: 1))
        XCTAssertEqual(args, ["-v", "-e"])
    }

    func testPort2IncludesC() {
        let args = SpotReadArgs.build(config: SpotReadConfig(selectedPort: 2))
        XCTAssertEqual(args, ["-v", "-e", "-c", "2"])
    }

    func testLedFlag() {
        let args = SpotReadArgs.build(config: SpotReadConfig(enableLEDs: true))
        XCTAssertEqual(args, ["-v", "-e", "-Y", "l"])
    }

    func testPortAndLeds() {
        let args = SpotReadArgs.build(
            config: SpotReadConfig(selectedPort: 2, enableLEDs: true))
        XCTAssertEqual(args, ["-v", "-e", "-c", "2", "-Y", "l"])
    }

    func testNeverU() {
        for config in [
            SpotReadConfig(),
            SpotReadConfig(selectedPort: 2),
            SpotReadConfig(enableLEDs: true),
            SpotReadConfig(selectedPort: 3, enableLEDs: true),
        ] {
            XCTAssertFalse(SpotReadArgs.build(config: config).contains("-u"))
            XCTAssertFalse(SpotReadArgs.build(config: config).contains("-d"))
        }
    }
}
