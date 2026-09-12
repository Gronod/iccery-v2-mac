import XCTest
import Foundation
@testable import ICCeryCore

/// Helpers shared across ProcessManager tests. Fixture binaries are shell
/// scripts written to a temp dir — no resource bundling required.
/// XCTest executes test methods serially by default.
final class ProcessManagerTests: XCTestCase {

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
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
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

    /// Subscribes synchronously (registration happens inside `events()`)
    /// then records every event for `id` until the task is cancelled.
    /// Unlike `collect`, observation continues past `.exit` so tests can
    /// prove exactly-once exit emission.
    private func observe(
        _ manager: ProcessManager,
        id: String,
        into box: Box
    ) -> Task<Void, Never> {
        let stream = manager.events()
        return Task {
            for await event in stream {
                guard event.id == id else { continue }
                box.append(event)
            }
        }
    }

    private func exitCount(in box: Box) -> Int {
        box.events.filter { if case .exit = $0 { return true }; return false }.count
    }

    private func waitForExit(in box: Box, timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exitCount(in: box) > 0 { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private func waitForRunning(
        _ manager: ProcessManager,
        id: String,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await manager.isRunning(id) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    // MARK: - Tests

    func testStreamsStdoutAndEmitsExit() async throws {
        let pm = ProcessManager()
        let bin = try script("lines.sh", "#!/bin/sh\necho hello\necho world\n")
        async let events = collect(pm, id: "t1")
        try await pm.runStreaming(id: "t1", binary: bin, arguments: [])
        let evs = await events
        let lines = evs.compactMap { e -> String? in
            if case .stdout(_, let l) = e { return l }; return nil
        }
        XCTAssertEqual(lines, ["hello", "world"])
        XCTAssertTrue(evs.contains(.exit(id: "t1", code: 0)))
    }

    func testRoutesStderrSeparately() async throws {
        let pm = ProcessManager()
        let bin = try script("err.sh", "#!/bin/sh\necho out\necho oops 1>&2\n")
        async let evs = collect(pm, id: "t2")
        try await pm.runStreaming(id: "t2", binary: bin, arguments: [])
        let events = await evs
        XCTAssertTrue(events.contains(.stdout(id: "t2", line: "out")))
        XCTAssertTrue(events.contains(.stderr(id: "t2", line: "oops")))
    }

    func testStripsRowColorsJSONPrefix() async throws {
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
        XCTAssertEqual(rows, ["{\"row\":1}"])
        XCTAssertTrue(events.contains(.stdout(id: "t3", line: "plain")))
        // Prefixed lines must not leak into stdout.
        XCTAssertFalse(events.contains(.stdout(id: "t3", line: "ROW_COLORS_JSON: {\"row\":1}")))
    }

    func testUnterminatedTailFlushesOnExit() async throws {
        let pm = ProcessManager()
        let bin = try script("tail.sh", "#!/bin/sh\nprintf 'no-newline'\n")
        async let evs = collect(pm, id: "t4")
        try await pm.runStreaming(id: "t4", binary: bin, arguments: [])
        let t4SawTail = await evs.contains(.stdout(id: "t4", line: "no-newline"))
        XCTAssertTrue(t4SawTail)
    }

    func testStdinRoundTrip() async throws {
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
        XCTAssertTrue(events.contains(.stdout(id: "t5", line: "got: ")))
        XCTAssertTrue(events.contains(.stdout(id: "t5", line: "got:d")))
    }

    func testDuplicateIDRejected() async throws {
        let pm = ProcessManager()
        let bin = try script("slow.sh", "#!/bin/sh\nsleep 30\n")
        try await pm.runStreaming(id: "t6", binary: bin, arguments: [])
        await assertAsyncThrows(expectedType: ProcessError.self) {
            try await pm.runStreaming(id: "t6", binary: bin, arguments: [])
        } errorHandler: { error in
            XCTAssertEqual(error, .duplicateID("t6"))
        }
        await pm.kill(id: "t6")
    }

    func testKillEmitsExitAndClosesStdin() async throws {
        let pm = ProcessManager()
        let bin = try script("slow2.sh", "#!/bin/sh\ncat\n")
        async let evs = collect(pm, id: "t7")
        try await pm.runStreaming(id: "t7", binary: bin, arguments: [])
        await pm.kill(id: "t7")
        let events = await evs
        // exit emitted exactly once
        let exits = events.filter { if case .exit = $0 { return true }; return false }
        XCTAssertEqual(exits.count, 1)
        await assertAsyncThrows(expectedType: ProcessError.self) {
            try await pm.sendStdin(id: "t7", text: "d\n")
        } errorHandler: { error in
            XCTAssertEqual(error, .unknownID("t7"))
        }
    }

    func testKillAllCountsSignaled() async throws {
        let pm = ProcessManager()
        let bin = try script("slow3.sh", "#!/bin/sh\nsleep 30\n")
        try await pm.runStreaming(id: "a", binary: bin, arguments: [])
        try await pm.runStreaming(id: "b", binary: bin, arguments: [])
        let count = await pm.killAll()
        XCTAssertEqual(count, 2)
    }

    func testCapturedRunReturnsBothStreams() async throws {
        let pm = ProcessManager()
        let bin = try script("cap.sh", "#!/bin/sh\necho out-data\necho err-data 1>&2\nexit 3\n")
        let result = try await pm.runCaptured(id: "cap", binary: bin, arguments: [])
        XCTAssertTrue(result.stdout.contains("out-data"))
        XCTAssertTrue(result.stderr.contains("err-data"))
        XCTAssertEqual(result.exitCode, 3)
    }

    func testCapturedRunFastExit() async throws {
        let pm = ProcessManager()
        let bin = try script("fast.sh", "#!/bin/sh\nexit 7\n")
        let result = try await pm.runCaptured(id: "fast", binary: bin, arguments: [])
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
    }

    func testCapturedRunStderrOnly() async throws {
        let pm = ProcessManager()
        let bin = try script("stderr-only.sh", "#!/bin/sh\necho 'mock lp failure' 1>&2\nexit 1\n")
        let result = try await pm.runCaptured(id: "stderr-only", binary: bin, arguments: [])
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("mock lp failure"))
    }

    func testCapturedRunDoesNotDeadlockOnLargeOutput() async throws {
        let pm = ProcessManager()
        // 5000 lines each stream exceeds the 64 KiB pipe buffer.
        let bin = try script(
            "big.sh",
            "#!/bin/sh\ni=0; while [ $i -lt 5000 ]; do echo \"out-$i\"; echo \"err-$i\" 1>&2; i=$((i+1)); done\n"
        )
        let result = try await pm.runCaptured(id: "big", binary: bin, arguments: [])
        XCTAssertTrue(result.stdout.contains("out-4999"))
        XCTAssertTrue(result.stderr.contains("err-4999"))
    }

    func testArgyllEnvVarIsSet() async throws {
        let pm = ProcessManager()
        let bin = try script("env.sh", "#!/bin/sh\necho \"ANI=$ARGYLL_NOT_INTERACTIVE\"\n")
        async let evs = collect(pm, id: "t10")
        try await pm.runStreaming(id: "t10", binary: bin, arguments: [])
        let t10SawEnv = await evs.contains(.stdout(id: "t10", line: "ANI=1"))
        XCTAssertTrue(t10SawEnv)
    }

    func testUnknownIDStdinThrows() async throws {
        let pm = ProcessManager()
        await assertAsyncThrows(expectedType: ProcessError.self) {
            try await pm.sendStdin(id: "nope", text: "d\n")
        } errorHandler: { error in
            XCTAssertEqual(error, .unknownID("nope"))
        }
    }

    func testExplicitPartialFlushEmitsRowColorsJSON() async throws {
        let pm = ProcessManager()
        let marker = Self.fixtureDir
            .appendingPathComponent("partial-row-ready-\(UUID().uuidString)")
        let bin = try script(
            "partial-row.sh",
            "#!/bin/sh\nprintf 'ROW_COLORS_JSON: {\"row\":9}'\ntouch \"$1\"\nsleep 30\n"
        )
        let box = Box()
        let observer = observe(pm, id: "t11", into: box)
        try await pm.runStreaming(id: "t11", binary: bin, arguments: [marker.path])
        let markerReady = await waitForFile(marker)
        XCTAssertTrue(markerReady)
        // Retry the flush so the pipe-ingest task can win the actor race
        // on a loaded host; the first successful flush emits the row.
        var flushed = false
        for _ in 0..<50 {
            await pm.flushPartialLine(id: "t11")
            if box.events.contains(where: { if case .jsonRow = $0 { return true }; return false }) {
                flushed = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(flushed)
        await pm.kill(id: "t11")
        let sawExit = await waitForExit(in: box)
        XCTAssertTrue(sawExit)
        observer.cancel()
        let events = box.events
        let rows = events.compactMap { e -> String? in
            if case .jsonRow(_, let d) = e { return String(decoding: d, as: UTF8.self) }
            return nil
        }
        XCTAssertEqual(rows, ["{\"row\":9}"])
        // Prefixed tails must not leak into stdout, even via finalize.
        XCTAssertFalse(events.contains(.stdout(id: "t11", line: "ROW_COLORS_JSON: {\"row\":9}")))
        XCTAssertEqual(exitCount(in: box), 1)
    }

    func testUnterminatedRowTailFinalizesAsJSONRow() async throws {
        let pm = ProcessManager()
        let bin = try script(
            "row-tail.sh",
            "#!/bin/sh\nprintf 'ROW_COLORS_JSON: {\"row\":42}'\n"
        )
        let box = Box()
        let observer = observe(pm, id: "t12", into: box)
        try await pm.runStreaming(id: "t12", binary: bin, arguments: [])
        let sawExit = await waitForExit(in: box)
        XCTAssertTrue(sawExit)
        observer.cancel()
        let events = box.events
        let rows = events.compactMap { e -> String? in
            if case .jsonRow(_, let d) = e { return String(decoding: d, as: UTF8.self) }
            return nil
        }
        XCTAssertEqual(rows, ["{\"row\":42}"])
        XCTAssertFalse(events.contains(.stdout(id: "t12", line: "ROW_COLORS_JSON: {\"row\":42}")))
        let rowIndex = events.firstIndex {
            if case .jsonRow = $0 { return true }; return false
        }
        let exitIndexes = events.indices.filter {
            if case .exit = events[$0] { return true }; return false
        }
        XCTAssertEqual(exitIndexes.count, 1)
        if let rowIndex, let exitIndex = exitIndexes.first {
            XCTAssertTrue(rowIndex < exitIndex)
        } else {
            XCTFail("expected a jsonRow before the exit event")
        }
    }

    func testFastStreamingExitEmitsExactlyOneExit() async throws {
        let pm = ProcessManager()
        let bin = try script("fast-stream.sh", "#!/bin/sh\nexit 0\n")
        let box = Box()
        let observer = observe(pm, id: "t13", into: box)
        try await pm.runStreaming(id: "t13", binary: bin, arguments: [])
        let sawExit = await waitForExit(in: box)
        XCTAssertTrue(sawExit)
        // The grace window must outlast the 2 s finalize watchdog so a
        // duplicate emission from it would be observed.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        observer.cancel()
        XCTAssertEqual(box.events, [.exit(id: "t13", code: 0)])
    }

    func testFastCapturedExitEmitsExactlyOneExit() async throws {
        let pm = ProcessManager()
        let bin = try script("fast-cap.sh", "#!/bin/sh\nexit 7\n")
        let box = Box()
        let observer = observe(pm, id: "t14", into: box)
        let result = try await pm.runCaptured(id: "t14", binary: bin, arguments: [])
        XCTAssertEqual(result.exitCode, 7)
        // Both the termination handler and the waitUntilExit watchdog
        // resume the same box; give the slower path time to fire.
        try await Task.sleep(nanoseconds: 500_000_000)
        observer.cancel()
        XCTAssertEqual(box.events, [.exit(id: "t14", code: 7)])
    }

    func testCapturedRunSetsArgyllNotInteractive() async throws {
        let pm = ProcessManager()
        let bin = try script(
            "cap-env.sh",
            "#!/bin/sh\necho \"ANI=$ARGYLL_NOT_INTERACTIVE\"\n"
        )
        let result = try await pm.runCaptured(id: "t15", binary: bin, arguments: [])
        XCTAssertEqual(result.stdout, "ANI=1\n")
    }

    func testKillAllTerminatesStreamingAndCapturedChildren() async throws {
        let pm = ProcessManager()
        let marker = Self.fixtureDir
            .appendingPathComponent("mixed-cap-ready-\(UUID().uuidString)")
        let slowBin = try script("mixed-slow.sh", "#!/bin/sh\nsleep 30\n")
        let capBin = try script("mixed-cap.sh", "#!/bin/sh\ntouch \"$1\"\nsleep 30\n")
        let streamBox = Box()
        let capBox = Box()
        let streamObserver = observe(pm, id: "t16", into: streamBox)
        let capObserver = observe(pm, id: "t17", into: capBox)
        try await pm.runStreaming(id: "t16", binary: slowBin, arguments: [])
        let capTask = Task {
            try await pm.runCaptured(id: "t17", binary: capBin, arguments: [marker.path])
        }
        let markerReady = await waitForFile(marker)
        XCTAssertTrue(markerReady)
        let t16Running = await waitForRunning(pm, id: "t16")
        XCTAssertTrue(t16Running)
        let t17Running = await waitForRunning(pm, id: "t17")
        XCTAssertTrue(t17Running)
        let killed = await pm.killAll()
        XCTAssertEqual(killed, 2)
        _ = try await capTask.value
        let streamExit = await waitForExit(in: streamBox)
        XCTAssertTrue(streamExit)
        let capExit = await waitForExit(in: capBox)
        XCTAssertTrue(capExit)
        // Grace window outlasts the streaming finalize watchdog.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        streamObserver.cancel()
        capObserver.cancel()
        let t16RunningAfter = await pm.isRunning("t16")
        XCTAssertFalse(t16RunningAfter)
        let t17RunningAfter = await pm.isRunning("t17")
        XCTAssertFalse(t17RunningAfter)
        XCTAssertEqual(exitCount(in: streamBox), 1)
        XCTAssertEqual(exitCount(in: capBox), 1)
    }
}

final class ProcessLineDecoderTests: XCTestCase {
    func testSplitsAcrossChunkBoundaries() {
        var d = ProcessLineDecoder()
        XCTAssertEqual(d.feed(Data("he".utf8)), [])
        XCTAssertEqual(d.feed(Data("llo\nwor".utf8)), ["hello"])
        XCTAssertEqual(d.feed(Data("ld\n".utf8)), ["world"])
        XCTAssertNil(d.finish())
    }

    func testCrlfIsStripped() {
        var d = ProcessLineDecoder()
        XCTAssertEqual(d.feed(Data("a\r\nb\r\n".utf8)), ["a", "b"])
    }

    func testFinishReturnsRemainder() {
        var d = ProcessLineDecoder()
        _ = d.feed(Data("x".utf8))
        XCTAssertEqual(d.finish(), "x")
        XCTAssertNil(d.finish())
    }
}

final class JSONAccumulatorTests: XCTestCase {
    func testMultilinePrettyJSON() {
        var acc = JSONAccumulator()
        XCTAssertNil(acc.feed(line: "{"))
        XCTAssertNil(acc.feed(line: "  \"k\": 1"))
        let done = acc.feed(line: "}")
        XCTAssertNotNil(done)
        let obj = try? JSONSerialization.jsonObject(with: done!) as? [String: Int]
        XCTAssertEqual(obj?["k"], 1)
    }

    func testNonJSONLinesIgnored() {
        var acc = JSONAccumulator()
        XCTAssertNil(acc.feed(line: "Reading instrument..."))
        XCTAssertNil(acc.feed(line: "still text"))
        XCTAssertNil(acc.completeData)
    }

    func testDecodeTyped() {
        struct Doc: Decodable { let n: Int }
        var acc = JSONAccumulator()
        // Split so the doc completes on the second feed.
        XCTAssertNil(acc.feed(line: "{\"n\":"))
        let data = acc.feed(line: "7}")
        XCTAssertNotNil(data)
        let doc = data.flatMap { try? JSONDecoder().decode(Doc.self, from: $0) }
        XCTAssertEqual(doc?.n, 7)
        XCTAssertTrue(acc.isEmpty)
    }
}

final class LogSanitizerTests: XCTestCase {
    func testHomeIsRewritten() {
        let path = "\(NSHomeDirectory())/Documents/foo.ti1"
        XCTAssertEqual(LogSanitizer.sanitize(path), "~/Documents/foo.ti1")
    }
}
