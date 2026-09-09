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
            processManager: .shared,
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
}
