import Foundation
import Testing
@testable import ICCeryCore

/// Focused contracts for the shared `runStreamingTool` loop (#79).
///
/// Every test uses a per-test temporary directory, unique basenames,
/// and a fresh `ProcessManager` — no shared UI fixture scripts and no
/// process-environment mutation.
@Suite("ArgyllRunner streaming loop contracts")
struct ArgyllRunnerStreamingLoopTests {

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

    @Test("Non-zero exit throws toolFailed retaining code and collected stdout/stderr lines")
    func nonZeroExitThrowsToolFailed() async throws {
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
            Issue.record("Expected toolFailed")
        } catch let error as ArgyllRunnerError {
            guard case .toolFailed(let tool, let code, let logs) = error else {
                Issue.record("Expected toolFailed, got \(error)")
                return
            }
            #expect(tool == "targen")
            #expect(code == 3)
            #expect(logs.contains("Generating patches..."))
            #expect(logs.contains("targen: too few patches"))
        }
    }

    @Test("Exit 0 without expected artefact throws missingArtefact with the artefact path")
    func zeroExitMissingArtefact() async throws {
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

        await #expect(throws: ArgyllRunnerError.missingArtefact(expectedPath)) {
            try await runner.runTargen(config: config)
        }
    }

    @Test("Immediate exit after one stdout line still delivers the line and succeeds")
    func immediateExitDeliversLine() async throws {
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
        #expect(url.lastPathComponent == "quick.ti1")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(holder.lines.contains("only line"))
    }

    @Test("colprof unterminated progress fragment reaches onLogBatch before exit")
    func colprofPartialLineFlush() async throws {
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
        #expect(url.lastPathComponent == "frag.icc")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(holder.lines.contains("Doing gamut mapping"))
    }

    @Test("toolFailed maps each tool to its user-facing description",
          arguments: [
            (tool: "chartread", expected: "Chartread failed: boom"),
            (tool: "average", expected: "Averaging failed: boom"),
            (tool: "colprof", expected: "Profile creation failed: boom"),
            (tool: "printcal", expected: "Calibration curve computation failed: boom"),
            (tool: "applycal", expected: "Apply calibration failed: boom"),
            (tool: "iccgamut", expected: "Gamut extraction failed: boom"),
            (tool: "profcheck", expected: "Profile verification failed: boom"),
          ])
    func toolDescriptions(tool: String, expected: String) {
        let error = ArgyllRunnerError.toolFailed(tool: tool, code: 1, logs: ["boom"])
        #expect(error.errorDescription == expected)
    }

    @Test("toolFailed falls back to a generic description for unmapped tools and empty logs")
    func genericFallbacks() {
        let unknown = ArgyllRunnerError.toolFailed(tool: "targen", code: 7, logs: ["boom"])
        #expect(unknown.errorDescription == "Process exited with code 7")

        let emptyLogs = ArgyllRunnerError.toolFailed(tool: "colprof", code: 2, logs: [])
        #expect(emptyLogs.errorDescription
            == "Profile creation failed: exited with code 2")
    }
}
