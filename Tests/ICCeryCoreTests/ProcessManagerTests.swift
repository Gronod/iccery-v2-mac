import Testing
import Foundation
@testable import ICCeryCore

/// Helpers shared across ProcessManager tests. Fixture binaries are shell
/// scripts written to a temp dir — no resource bundling required.
@Suite("ProcessManager", .serialized)
struct ProcessManagerTests {

    // MARK: - Fixture plumbing

    private static let fixtureDir: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-pm-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Writes a shell script fixture and returns its executable URL.
    private func script(_ name: String, _ body: String) throws -> URL {
        let url = Self.fixtureDir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path
        )
        return url
    }

    /// Collects events for `id` until `.exit`, `timeout` seconds max.
    private func collect(
        _ manager: ProcessManager,
        id: String,
        timeout: TimeInterval = 10
    ) async -> [ProcessEvent] {
        await withCheckedContinuation { cont in
            let box = Box()
            Task {
                for await event in manager.events() {
                    guard event.id == id else { continue }
                    box.append(event)
                    if case .exit = event { break }
                }
                if box.finish() { cont.resume(returning: box.events) }
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if box.finish() { cont.resume(returning: box.events) }
            }
        }
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [ProcessEvent] = []
        private var finished = false
        var events: [ProcessEvent] { lock.lock(); defer { lock.unlock() }; return _events }
        func append(_ e: ProcessEvent) { lock.lock(); _events.append(e); lock.unlock() }
        func finish() -> Bool { lock.lock(); defer { lock.unlock() }; if finished { return false }; finished = true; return true }
    }

    // MARK: - Tests

    @Test func streamsStdoutAndEmitsExit() async throws {
        let pm = ProcessManager()
        let bin = try script("lines.sh", "#!/bin/sh\necho hello\necho world\n")
        async let events = collect(pm, id: "t1")
        try await pm.runStreaming(id: "t1", binary: bin, arguments: [])
        let evs = await events
        let lines = evs.compactMap { e -> String? in
            if case .stdout(_, let l) = e { return l }; return nil
        }
        #expect(lines == ["hello", "world"])
        #expect(evs.contains(.exit(id: "t1", code: 0)))
    }

    @Test func routesStderrSeparately() async throws {
        let pm = ProcessManager()
        let bin = try script("err.sh", "#!/bin/sh\necho out\necho oops 1>&2\n")
        async let evs = collect(pm, id: "t2")
        try await pm.runStreaming(id: "t2", binary: bin, arguments: [])
        let events = await evs
        #expect(events.contains(.stdout(id: "t2", line: "out")))
        #expect(events.contains(.stderr(id: "t2", line: "oops")))
    }

    @Test func stripsRowColorsJSONPrefix() async throws {
        let pm = ProcessManager()
        let bin = try script(
            "rows.sh",
            "#!/bin/sh\necho 'ROW_COLORS_JSON: {\"row\":1}'\necho plain\n"
        )
        async let evs = collect(pm, id: "t3")
        try await pm.runStreaming(id: "t3", binary: bin, arguments: [])
        let events = await evs
        let rows = events.compactMap { e -> String? in
            if case .jsonRow(_, let d) = e { return String(decoding: d, as: UTF8.self) }
            return nil
        }
        #expect(rows == ["{\"row\":1}"])
        #expect(events.contains(.stdout(id: "t3", line: "plain")))
        // Prefixed lines must not leak into stdout.
        #expect(!events.contains(.stdout(id: "t3", line: "ROW_COLORS_JSON: {\"row\":1}")))
    }

    @Test func unterminatedTailFlushesOnExit() async throws {
        let pm = ProcessManager()
        let bin = try script("tail.sh", "#!/bin/sh\nprintf 'no-newline'\n")
        async let evs = collect(pm, id: "t4")
        try await pm.runStreaming(id: "t4", binary: bin, arguments: [])
        #expect(await evs.contains(.stdout(id: "t4", line: "no-newline")))
    }

    @Test func stdinRoundTrip() async throws {
        let pm = ProcessManager()
        // Read two lines then exit naturally — a killed sh would lose its
        // buffered stdio output, which is exactly the chartread pattern.
        let bin = try script(
            "echo.sh",
            "#!/bin/sh\nIFS= read -r a; echo \"got:$a\"\nIFS= read -r b; echo \"got:$b\"\n"
        )
        async let evs = collect(pm, id: "t5")
        try await pm.runStreaming(id: "t5", binary: bin, arguments: [])
        try await pm.sendStdin(id: "t5", text: " \n")
        try await pm.sendStdin(id: "t5", text: "d\n")
        let events = await evs
        #expect(events.contains(.stdout(id: "t5", line: "got: ")))
        #expect(events.contains(.stdout(id: "t5", line: "got:d")))
    }

    @Test func duplicateIDRejected() async throws {
        let pm = ProcessManager()
        let bin = try script("slow.sh", "#!/bin/sh\nsleep 30\n")
        try await pm.runStreaming(id: "t6", binary: bin, arguments: [])
        await #expect(throws: ProcessError.duplicateID("t6")) {
            try await pm.runStreaming(id: "t6", binary: bin, arguments: [])
        }
        await pm.kill(id: "t6")
    }

    @Test func killEmitsExitAndClosesStdin() async throws {
        let pm = ProcessManager()
        let bin = try script("slow2.sh", "#!/bin/sh\ncat\n")
        async let evs = collect(pm, id: "t7")
        try await pm.runStreaming(id: "t7", binary: bin, arguments: [])
        await pm.kill(id: "t7")
        let events = await evs
        // exit emitted exactly once
        let exits = events.filter { if case .exit = $0 { return true }; return false }
        #expect(exits.count == 1)
        await #expect(throws: ProcessError.unknownID("t7")) {
            try await pm.sendStdin(id: "t7", text: "d\n")
        }
    }

    @Test func killAllCountsSignaled() async throws {
        let pm = ProcessManager()
        let bin = try script("slow3.sh", "#!/bin/sh\nsleep 30\n")
        try await pm.runStreaming(id: "a", binary: bin, arguments: [])
        try await pm.runStreaming(id: "b", binary: bin, arguments: [])
        let count = await pm.killAll()
        #expect(count == 2)
    }

    @Test func capturedRunReturnsBothStreams() async throws {
        let pm = ProcessManager()
        let bin = try script("cap.sh", "#!/bin/sh\necho out-data\necho err-data 1>&2\nexit 3\n")
        let result = try await pm.runCaptured(id: "cap", binary: bin, arguments: [])
        #expect(result.stdout.contains("out-data"))
        #expect(result.stderr.contains("err-data"))
        #expect(result.exitCode == 3)
    }

    @Test func capturedRunFastExit() async throws {
        let pm = ProcessManager()
        let bin = try script("fast.sh", "#!/bin/sh\nexit 7\n")
        let result = try await pm.runCaptured(id: "fast", binary: bin, arguments: [])
        #expect(result.exitCode == 7)
        #expect(result.stdout == "")
        #expect(result.stderr == "")
    }

    @Test func capturedRunStderrOnly() async throws {
        let pm = ProcessManager()
        let bin = try script("stderr-only.sh", "#!/bin/sh\necho 'mock lp failure' 1>&2\nexit 1\n")
        let result = try await pm.runCaptured(id: "stderr-only", binary: bin, arguments: [])
        #expect(result.exitCode == 1)
        #expect(result.stdout == "")
        #expect(result.stderr.contains("mock lp failure"))
    }

    @Test func capturedRunDoesNotDeadlockOnLargeOutput() async throws {
        let pm = ProcessManager()
        // 5000 lines each stream exceeds the 64 KiB pipe buffer.
        let bin = try script(
            "big.sh",
            "#!/bin/sh\ni=0; while [ $i -lt 5000 ]; do echo \"out-$i\"; echo \"err-$i\" 1>&2; i=$((i+1)); done\n"
        )
        let result = try await pm.runCaptured(id: "big", binary: bin, arguments: [])
        #expect(result.stdout.contains("out-4999"))
        #expect(result.stderr.contains("err-4999"))
    }

    @Test func argyllEnvVarIsSet() async throws {
        let pm = ProcessManager()
        let bin = try script("env.sh", "#!/bin/sh\necho \"ANI=$ARGYLL_NOT_INTERACTIVE\"\n")
        async let evs = collect(pm, id: "t10")
        try await pm.runStreaming(id: "t10", binary: bin, arguments: [])
        #expect(await evs.contains(.stdout(id: "t10", line: "ANI=1")))
    }

    @Test func unknownIDStdinThrows() async throws {
        let pm = ProcessManager()
        await #expect(throws: ProcessError.unknownID("nope")) {
            try await pm.sendStdin(id: "nope", text: "d\n")
        }
    }
}

@Suite("ProcessLineDecoder")
struct ProcessLineDecoderTests {
    @Test func splitsAcrossChunkBoundaries() {
        var d = ProcessLineDecoder()
        #expect(d.feed(Data("he".utf8)) == [])
        #expect(d.feed(Data("llo\nwor".utf8)) == ["hello"])
        #expect(d.feed(Data("ld\n".utf8)) == ["world"])
        #expect(d.finish() == nil)
    }

    @Test func crlfIsStripped() {
        var d = ProcessLineDecoder()
        #expect(d.feed(Data("a\r\nb\r\n".utf8)) == ["a", "b"])
    }

    @Test func finishReturnsRemainder() {
        var d = ProcessLineDecoder()
        _ = d.feed(Data("x".utf8))
        #expect(d.finish() == "x")
        #expect(d.finish() == nil)
    }
}

@Suite("JSONAccumulator")
struct JSONAccumulatorTests {
    @Test func multilinePrettyJSON() {
        var acc = JSONAccumulator()
        #expect(acc.feed(line: "{") == nil)
        #expect(acc.feed(line: "  \"k\": 1") == nil)
        let done = acc.feed(line: "}")
        #expect(done != nil)
        let obj = try? JSONSerialization.jsonObject(with: done!) as? [String: Int]
        #expect(obj?["k"] == 1)
    }

    @Test func nonJSONLinesIgnored() {
        var acc = JSONAccumulator()
        #expect(acc.feed(line: "Reading instrument...") == nil)
        #expect(acc.feed(line: "still text") == nil)
        #expect(acc.completeData == nil)
    }

    @Test func decodeTyped() {
        struct Doc: Decodable { let n: Int }
        var acc = JSONAccumulator()
        // Split so the doc completes on the second feed.
        #expect(acc.feed(line: "{\"n\":") == nil)
        let data = acc.feed(line: "7}")
        #expect(data != nil)
        let doc = data.flatMap { try? JSONDecoder().decode(Doc.self, from: $0) }
        #expect(doc?.n == 7)
        #expect(acc.isEmpty)
    }
}

@Suite("LogSanitizer")
struct LogSanitizerTests {
    @Test func homeIsRewritten() {
        let path = "\(NSHomeDirectory())/Documents/foo.ti1"
        #expect(LogSanitizer.sanitize(path) == "~/Documents/foo.ti1")
    }
}
