import Foundation
import Testing
@testable import ICCeryCore

final class LogHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []

    func append(_ batch: [String]) {
        lock.lock()
        _lines.append(contentsOf: batch)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _lines
    }
}

@Suite("ArgyllRunner colprof")
struct ArgyllRunnerColprofTests {

    @Test("Mock colprof produces .icc")
    func colprofProducesIcc() async throws {
        let binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ICCeryUITests/Fixtures/bin")
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("colprof-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)

        let runner = ArgyllRunner(
            processManager: ProcessManager(),
            binaryResolver: BinaryResolver(overrideDir: binDir)
        )

        let holder = LogHolder()
        let config = ColprofConfig(basename: "testrun", workingDirectory: testRoot)
        let url = try await runner.runColprof(config: config) { batch in
            holder.append(batch)
        }

        #expect(url.lastPathComponent == "testrun.icc")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(holder.lines.contains { $0.contains("Gamut mapping") })

        try? FileManager.default.removeItem(at: testRoot)
    }

    @Test("Failing colprof throws toolFailed with code and logs")
    func colprofFailureThrowsToolFailed() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("colprof-fail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mockURL = dir.appendingPathComponent("colprof")
        try """
        #!/bin/sh
        echo "colprof broke" >&2
        exit 4
        """.write(to: mockURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: mockURL.path)

        let runner = ArgyllRunner(
            processManager: ProcessManager(),
            binaryResolver: BinaryResolver(bundledRoot: dir, overrideDir: dir)
        )
        let config = ColprofConfig(basename: "failrun", workingDirectory: dir)

        await #expect(throws: ArgyllRunnerError.toolFailed(
            tool: "colprof", code: 4, logs: ["colprof broke"])) {
            try await runner.runColprof(config: config)
        }
    }
}
