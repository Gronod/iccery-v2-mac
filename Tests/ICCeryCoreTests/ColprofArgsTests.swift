import Foundation
import XCTest
@testable import ICCeryCore

final class ColprofArgsTests: XCTestCase {

    func testDefaults() throws {
        let config = ColprofConfig(basename: "target")
        let args = try ColprofArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-a", "l", "-q", "m", "target"])
    }

    func testFwaBareFlag() throws {
        let config = ColprofConfig(fwa: "", basename: "target")
        let args = try ColprofArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-a", "l", "-q", "m", "-f", "target"])
    }

    func testFwaD50() throws {
        let config = ColprofConfig(fwa: "D50", basename: "target")
        let args = try ColprofArgs.build(config: config)
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("D50"))
        XCTAssertEqual(args.last, "target")
    }

    func testFwaNoneOmitted() throws {
        let config = ColprofConfig(fwa: "none", basename: "target")
        let args = try ColprofArgs.build(config: config)
        XCTAssertFalse(args.contains("-f"))
    }

    func testViewingCondNoneSkipped() throws {
        let config = ColprofConfig(
            inputViewingCond: "none",
            outputViewingCond: "mt",
            basename: "target"
        )
        let args = try ColprofArgs.build(config: config)
        XCTAssertFalse(args.contains("-c"))
        XCTAssertTrue(args.contains("-d"))
        XCTAssertTrue(args.contains("mt"))
    }

    func testDescriptionFallback() throws {
        let config = ColprofConfig(description: "", basename: "target")
        let args = try ColprofArgs.build(config: config)
        XCTAssertFalse(args.contains("-D"))
    }

    func testCopyright() throws {
        let config = ColprofConfig(copyright: "Gronod 2026", basename: "target")
        let args = try ColprofArgs.build(config: config)
        XCTAssertTrue(args.contains("-C"))
        XCTAssertTrue(args.contains("Gronod 2026"))
    }

    func testNoProgressJsonFlag() throws {
        let config = ColprofConfig(basename: "target")
        let args = try ColprofArgs.build(config: config)
        XCTAssertFalse(args.contains("-u"))
    }
}
