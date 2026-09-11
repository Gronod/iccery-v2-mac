import Foundation
import XCTest
@testable import ICCeryCore

/// Focused contracts for the shared `runStreamingTool` loop (#79).
///
/// Every test uses a per-test temporary directory, unique basenames,
/// and a fresh `ProcessManager` — no shared UI fixture scripts and no
/// process-environment mutation.
final class ArgyllRunnerStreamingLoopTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeMock(_ name: String, _ body: String, in dir: URL) throws {
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeRunner(binDir: URL) -> ArgyllRunner {
        ArgyllRunner(
            processManager: ProcessManager(),
            binaryResolver: BinaryResolver(bundledRoot: binDir, overrideDir: binDir))
    }

    func testNonZeroExitThrowsToolFailed() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeMock("targen", """
            #!/bin/sh
            echo "Generating patches..."
            echo "targen: too few patches" >&2
            exit 3
            """, in: dir)
        let runner = makeRunner(binDir: dir)
        let config = TargenConfig(
            colourSpace: .rgb, patchCount: 800, whitePatches: 4,
            blackPatches: 4, basename: "fail", workingDirectory: dir)

        do {
            _ = try await runner.runTargen(config: config)
            XCTFail("Expected toolFailed")
        } catch let error as ArgyllRunnerError {
            guard case .toolFailed(let tool, let code, let logs) = error else {
                XCTFail("Expected toolFailed, got \(error)")
                return
            }
            XCTAssertEqual(tool, "targen")
            XCTAssertEqual(code, 3)
            XCTAssertTrue(logs.contains("Generating patches..."))
            XCTAssertTrue(logs.contains("targen: too few patches"))
        }
    }

    func testZeroExitMissingArtefact() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeMock("targen", """
            #!/bin/sh
            echo "done but wrote nothing"
            exit 0
            """, in: dir)
        let runner = makeRunner(binDir: dir)
        let expectedPath = dir.appendingPathComponent("gone.ti1").path
        let config = TargenConfig(
            colourSpace: .rgb, patchCount: 800, whitePatches: 4,
            blackPatches: 4, basename: "gone", workingDirectory: dir)

        await assertAsyncThrows(expectedType: ArgyllRunnerError.self) {
            try await runner.runTargen(config: config)
        } errorHandler: { error in
            XCTAssertEqual(error, .missingArtefact(expectedPath))
        }
    }

    func testImmediateExitDeliversLine() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeMock("targen", """
            #!/bin/sh
            last=""
            for arg in "$@"; do last="$arg"; done
            echo "only line"
            touch "$last.ti1"
            exit 0
            """, in: dir)
        let runner = makeRunner(binDir: dir)
        let config = TargenConfig(
            colourSpace: .rgb, patchCount: 800, whitePatches: 4,
            blackPatches: 4, basename: "quick", workingDirectory: dir)

        let holder = LogHolder()
        let url = try await runner.runTargen(config: config) { batch in
            holder.append(batch)
        }
        XCTAssertEqual(url.lastPathComponent, "quick.ti1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(holder.lines.contains("only line"))
    }

    func testColprofPartialLineFlush() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // The fragment is printed without a newline, then the mock sleeps
        // past the 500 ms partial-line flush interval before writing the
        // artefact and exiting — so the tail is delivered mid-run.
        try writeMock("colprof", """
            #!/bin/sh
            last=""
            for arg in "$@"; do last="$arg"; done
            printf 'Doing gamut mapping'
            sleep 2
            touch "$last.icc"
            exit 0
            """, in: dir)
        let runner = makeRunner(binDir: dir)
        let config = ColprofConfig(basename: "frag", workingDirectory: dir)

        let holder = LogHolder()
        let url = try await runner.runColprof(config: config) { batch in
            holder.append(batch)
        }
        XCTAssertEqual(url.lastPathComponent, "frag.icc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(holder.lines.contains("Doing gamut mapping"))
    }

    func testToolDescriptions() {
        let cases: [(tool: String, expected: String)] = [
            (tool: "chartread", expected: "Chartread failed: boom"),
            (tool: "average", expected: "Averaging failed: boom"),
            (tool: "colprof", expected: "Profile creation failed: boom"),
            (tool: "printcal", expected: "Calibration curve computation failed: boom"),
            (tool: "applycal", expected: "Apply calibration failed: boom"),
            (tool: "iccgamut", expected: "Gamut extraction failed: boom"),
            (tool: "profcheck", expected: "Profile verification failed: boom"),
        ]
        for (tool, expected) in cases {
            let error = ArgyllRunnerError.toolFailed(tool: tool, code: 1, logs: ["boom"])
            XCTAssertEqual(error.errorDescription, expected)
        }
    }

    func testGenericFallbacks() {
        let unknown = ArgyllRunnerError.toolFailed(tool: "targen", code: 7, logs: ["boom"])
        XCTAssertEqual(unknown.errorDescription, "Process exited with code 7")

        let emptyLogs = ArgyllRunnerError.toolFailed(tool: "colprof", code: 2, logs: [])
        XCTAssertEqual(emptyLogs.errorDescription,
            "Profile creation failed: exited with code 2")
    }
}
