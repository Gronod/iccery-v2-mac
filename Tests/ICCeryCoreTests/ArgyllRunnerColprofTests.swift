import Foundation
import XCTest
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

final class ArgyllRunnerColprofTests: XCTestCase {

    func testColprofProducesIcc() async throws {
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

        XCTAssertEqual(url.lastPathComponent, "testrun.icc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(holder.lines.contains { $0.contains("Gamut mapping") })

        try? FileManager.default.removeItem(at: testRoot)
    }

    func testColprofFailureThrowsToolFailed() async throws {
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

        await assertAsyncThrows(expectedType: ArgyllRunnerError.self) {
            try await runner.runColprof(config: config)
        } errorHandler: { error in
            XCTAssertEqual(error, .toolFailed(
                tool: "colprof", code: 4, logs: ["colprof broke"]))
        }
    }
}
