import Foundation
import Testing
@testable import ICCeryCore

@Suite("ArgyllRunner Calibration")
struct ArgyllRunnerCalibrationTests {

    private func makeRunner(processManager: ProcessManager = ProcessManager()) -> ArgyllRunner {
        let binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ICCeryUITests/Fixtures/bin")
        return ArgyllRunner(
            processManager: processManager,
            binaryResolver: BinaryResolver(overrideDir: binDir)
        )
    }

    private func makeTestDir() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("calibration-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("Calibration targen produces CAL_*.ti1")
    func calibrationTargenProducesTi1() async throws {
        let testRoot = try makeTestDir()
        let runner = makeRunner()
        let config = CalibrationTargenConfig(
            colourSpace: .rgb,
            steps: 21,
            basename: "demo",
            workingDirectory: testRoot
        )

        let url = try await runner.runCalibrationTargen(config: config)

        #expect(url.lastPathComponent == "CAL_demo.ti1")
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: testRoot)
    }

    @Test("Calibration targen from foo runs as process id targen_CAL_foo")
    func calibrationTargenProcessId() async throws {
        let testRoot = try makeTestDir()
        let pm = ProcessManager()
        let runner = makeRunner(processManager: pm)
        let events = pm.events()
        // Subscribed before spawn; the exit event is emitted before
        // runCalibrationTargen returns, so this always terminates.
        let sawExit = Task {
            for await event in events {
                guard event.id == "targen_CAL_foo" else { continue }
                if case .exit = event { return true }
            }
            return false
        }
        let config = CalibrationTargenConfig(
            colourSpace: .rgb,
            steps: 21,
            basename: "foo",
            workingDirectory: testRoot
        )

        let url = try await runner.runCalibrationTargen(config: config)

        #expect(url.lastPathComponent == "CAL_foo.ti1")
        #expect(await sawExit.value)
        try? FileManager.default.removeItem(at: testRoot)
    }

    @Test("printcal captured run creates .cal")
    func printcalProducesCal() async throws {
        let testRoot = try makeTestDir()
        let runner = makeRunner()
        let output = testRoot.appendingPathComponent("CAL_demo.cal")
        let config = PrintcalConfig(
            ti3Basename: "CAL_demo",
            workingDirectory: testRoot,
            outputURL: output
        )

        let url = try await runner.runPrintcal(config: config)

        #expect(url.lastPathComponent == "CAL_demo.cal")
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: testRoot)
    }

    @Test("printcal failure throws toolFailed")
    func printcalFailureThrows() async throws {
        let testRoot = try makeTestDir()
        defer { try? FileManager.default.removeItem(at: testRoot) }

        // Per-test mock printcal that always fails — no global
        // environment mutation, no shared fixture changes.
        let binDir = try makeTestDir()
        defer { try? FileManager.default.removeItem(at: binDir) }
        let mockURL = binDir.appendingPathComponent("printcal")
        try """
        #!/bin/sh
        echo "printcal mock failure" >&2
        exit 1
        """.write(to: mockURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: mockURL.path)

        let runner = ArgyllRunner(
            processManager: ProcessManager(),
            binaryResolver: BinaryResolver(bundledRoot: binDir, overrideDir: binDir)
        )
        let output = testRoot.appendingPathComponent("CAL_demo.cal")
        let config = PrintcalConfig(
            ti3Basename: "CAL_demo",
            workingDirectory: testRoot,
            outputURL: output
        )

        await #expect(throws: ArgyllRunnerError.toolFailed(
            tool: "printcal", code: 1, logs: ["printcal mock failure\n"])) {
            _ = try await runner.runPrintcal(config: config)
        }
    }
}
