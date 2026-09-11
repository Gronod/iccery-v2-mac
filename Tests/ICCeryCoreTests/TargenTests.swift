import Testing
import XCTest
import Foundation
@testable import ICCeryCore

final class TargenArgsTests: XCTestCase {

    func testRgbBaseline() throws {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            basename: "test_rgb"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-d", "2", "-f", "800", "-e", "4", "-B", "4", "test_rgb"])
        XCTAssertFalse(args.contains("-u"))
    }

    func testCmykBaseline() throws {
        let config = TargenConfig(
            colourSpace: .cmyk,
            patchCount: 1500,
            whitePatches: 4,
            blackPatches: 0,
            basename: "test_cmyk"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-d", "4", "-f", "1500", "-e", "4", "-B", "0", "test_cmyk"])
    }

    func testCustomPatchCount() throws {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 2500,
            whitePatches: 4,
            blackPatches: 4,
            basename: "custom_patches"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertTrue(args.contains("-f"))
        XCTAssertEqual(args[args.firstIndex(of: "-f")! + 1], "2500")
    }

    func testAllAdvancedFlags() throws {
        let config = TargenConfig(
            colourSpace: .cmyk,
            patchCount: 1200,
            whitePatches: 6,
            blackPatches: 2,
            greySteps: 12,
            singleChannelSteps: 8,
            neutralSteps: 6,
            neutralConcentration: 0.75,
            preconditioningProfile: "/path/to/profile.icc",
            ofpsHighQuality: true,
            ofpsAdaptation: 0.10,
            fullSpreadAlgorithm: .target,
            totalInkLimit: 320,
            darkEmphasis: 1.50,
            devicePower: 2.0,
            basename: "advanced_cmyk"
        )
        let args = try TargenArgs.build(config: config)
        let expected = [
            "-v", "-d", "4",
            "-f", "1200",
            "-e", "6",
            "-B", "2",
            "-g", "12",
            "-s", "8",
            "-n", "6",
            "-N", "0.75",
            "-c", "/path/to/profile.icc",
            "-G",
            "-A", "0.10",
            "-t",
            "-l", "320",
            "-V", "1.50",
            "-p", "2.00",
            "advanced_cmyk"
        ]
        XCTAssertEqual(args, expected)
    }

    func testRgbIgnoresInkLimit() throws {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            totalInkLimit: 300,
            basename: "rgb_no_ink"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertFalse(args.contains("-l"))
    }

    func testNeutralConcentrationOmittedWhenDefault() throws {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            neutralConcentration: 0.5005,
            basename: "n_default"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertFalse(args.contains("-N"))
    }

    func testAdaptationEmittedAtPointOne() throws {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            ofpsAdaptation: 0.10,
            basename: "a_flag"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertTrue(args.contains("-A"))
        XCTAssertEqual(args[args.firstIndex(of: "-A")! + 1], "0.10")
    }

    func testOfpsEmitsNoFlag() throws {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            fullSpreadAlgorithm: .ofps,
            basename: "ofps_test"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertFalse(args.contains("ofps"))
        XCTAssertFalse(args.contains("-t"))
    }

    func testDarkEmphasisAndPowerOmittedWhenOne() throws {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            darkEmphasis: 1.0,
            devicePower: 1.0,
            basename: "defaults_omitted"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertFalse(args.contains("-V"))
        XCTAssertFalse(args.contains("-p"))
    }

    func testWhitespacePreconditioner() throws {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            preconditioningProfile: "   \n\t  ",
            basename: "ws_pre"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertFalse(args.contains("-c"))
    }

    func testPreconditionerTrimmed() throws {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            preconditioningProfile: "  /path/to/profile.icc  ",
            basename: "trim_pre"
        )
        let args = try TargenArgs.build(config: config)
        XCTAssertEqual(args[args.firstIndex(of: "-c")! + 1], "/path/to/profile.icc")
    }

    func testInvalidBasenameThrows() {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            basename: "../bad_name"
        )
        XCTAssertThrowsError(try TargenArgs.build(config: config)) { error in
            XCTAssertTrue(error is PathSecurity.Error)
        }
    }

    func testInvalidPatchCountThrows() {
        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 0,
            whitePatches: 4,
            blackPatches: 4,
            basename: "bad_count"
        )
        XCTAssertThrowsError(try TargenArgs.build(config: config)) { error in
            XCTAssertTrue(error is TargenArgError)
        }
    }

    func testInvalidInkLimitThrows() {
        let config = TargenConfig(
            colourSpace: .cmyk,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 0,
            totalInkLimit: 450,
            basename: "bad_ink"
        )
        XCTAssertThrowsError(try TargenArgs.build(config: config)) { error in
            XCTAssertTrue(error is TargenArgError)
        }
    }
}

@Suite("ArgyllRunner Targen")
struct ArgyllRunnerTargenTests {

    @Test("Successful targen execution creates .ti1 and returns URL")
    func successfulTargenExecution() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a mock targen script
        let mockScript = """
        #!/bin/sh
        # Find the last argument which is the basename
        for arg do shift; set -- "$@" "$arg"; done
        last="$arg"
        echo "Generating patches..."
        touch "$last.ti1"
        echo "Done!"
        exit 0
        """
        let mockURL = tempDir.appendingPathComponent("targen")
        try mockScript.write(to: mockURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockURL.path)

        let resolver = BinaryResolver(bundledRoot: tempDir, overrideDir: tempDir)
        let pm = ProcessManager()
        let runner = ArgyllRunner(processManager: pm, binaryResolver: resolver)

        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            basename: "mock_test",
            workingDirectory: tempDir
        )

        var logLines: [String] = []
        final class LogBox: @unchecked Sendable {
            var lines: [String] = []
            let lock = NSLock()
            func append(_ batch: [String]) {
                lock.lock(); lines.append(contentsOf: batch); lock.unlock()
            }
        }
        let box = LogBox()
        let ti1URL = try await runner.runTargen(config: config) { batch in
            box.append(batch)
        }
        logLines = box.lines
        #expect(logLines.contains("Generating patches..."))

        #expect(FileManager.default.fileExists(atPath: ti1URL.path))
        #expect(ti1URL.lastPathComponent == "mock_test.ti1")
    }

    @Test("Failed targen execution throws toolFailed")
    func failedTargenExecution() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mockScript = """
        #!/bin/sh
        echo "Error: something went wrong" >&2
        exit 1
        """
        let mockURL = tempDir.appendingPathComponent("targen")
        try mockScript.write(to: mockURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockURL.path)

        let resolver = BinaryResolver(bundledRoot: tempDir, overrideDir: tempDir)
        let pm = ProcessManager()
        let runner = ArgyllRunner(processManager: pm, binaryResolver: resolver)

        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            basename: "fail_test",
            workingDirectory: tempDir
        )

        await #expect(throws: ArgyllRunnerError.toolFailed(
            tool: "targen", code: 1, logs: ["Error: something went wrong"])) {
            try await runner.runTargen(config: config)
        }
    }

    @Test("Targen exit 0 without .ti1 throws missingArtefact")
    func missingArtefactThrows() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mockScript = """
        #!/bin/sh
        echo "Exited 0 but did not create file"
        exit 0
        """
        let mockURL = tempDir.appendingPathComponent("targen")
        try mockScript.write(to: mockURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockURL.path)

        let resolver = BinaryResolver(bundledRoot: tempDir, overrideDir: tempDir)
        let pm = ProcessManager()
        let runner = ArgyllRunner(processManager: pm, binaryResolver: resolver)

        let config = TargenConfig(
            colourSpace: .rgb,
            patchCount: 800,
            whitePatches: 4,
            blackPatches: 4,
            basename: "no_file",
            workingDirectory: tempDir
        )

        await #expect(throws: ArgyllRunnerError.missingArtefact(
            tempDir.appendingPathComponent("no_file.ti1").path)) {
            try await runner.runTargen(config: config)
        }
    }
}
