import Foundation

/// Captured output from `runCaptured` — one-shot tools whose results
/// arrive as buffered stdout/stderr (printcal/applycal, CUPS tools).
public struct CapturedResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

/// Spawn / stdin / kill / event bus for Argyll sidecar children
/// (docs/02 §Event bus, docs/03 §Process manager).
///
/// Invariants:
/// - Duplicate `id` while a child runs is rejected (#116).
/// - The stdin handle lives in its own map, independent of wait, so
///   `sendStdin` never blocks on process exit (#84).
/// - `ARGYLL_NOT_INTERACTIVE=1` is set on every child.
/// - stdout lines beginning `ROW_COLORS_JSON: ` become `jsonRow` events
///   with the prefix stripped; all other stdout is `stdout` events.
/// - `exit` is emitted exactly once per child, and only after both
///   output pipes reach EOF — so no buffered output is lost on fast
///   exits or kills.
/// - `kill` drops the stdin handle so writers fail fast.
public actor ProcessManager {

    public static let rowColorsPrefix = "ROW_COLORS_JSON: "

    public static let shared = ProcessManager()

    // MARK: - Event bus (multicast)

    /// Lock-protected subscriber table. Registration is *synchronous*
    /// inside `events()` so a caller can subscribe, then spawn, without
    /// racing the child's first output or exit event.
    private final class SubscriberBox: @unchecked Sendable {
        private let lock = NSLock()
        private var map: [UUID: AsyncStream<ProcessEvent>.Continuation] = [:]

        func add(_ continuation: AsyncStream<ProcessEvent>.Continuation, token: UUID) {
            lock.lock()
            map[token] = continuation
            lock.unlock()
        }

        func remove(_ token: UUID) {
            lock.lock()
            map.removeValue(forKey: token)
            lock.unlock()
        }

        func yield(_ event: ProcessEvent) {
            lock.lock()
            let continuations = Array(map.values)
            lock.unlock()
            for continuation in continuations {
                continuation.yield(event)
            }
        }
    }

    private nonisolated let subscriberBox = SubscriberBox()

    /// Subscribe to the event bus. Each call returns an independent
    /// stream; every event is delivered to every live subscriber.
    /// The subscriber is registered before `events()` returns — callers
    /// may spawn immediately after subscribing without losing events.
    public nonisolated func events() -> AsyncStream<ProcessEvent> {
        let box = subscriberBox
        let token = UUID()
        return AsyncStream { continuation in
            box.add(continuation, token: token)
            continuation.onTermination = { _ in box.remove(token) }
        }
    }

    private nonisolated func emit(_ event: ProcessEvent) {
        subscriberBox.yield(event)
    }

    // MARK: - Child registry

    private struct RunningChild {
        let process: Process
        /// stdin lives in its own slot, independent of process wait (#84).
        var stdin: FileHandle?
        var stdoutDecoder: ProcessLineDecoder
        var stderrDecoder: ProcessLineDecoder
        var stdoutEOF = false
        var stderrEOF = false
        /// Set by the termination handler; `exit` is emitted once both
        /// pipes have also reached EOF.
        var pendingExitCode: Int32?
        var finalized = false
    }

    private var children: [String: RunningChild] = [:]
    /// Processes owned by `runCaptured` (dup detection + kill support).
    private var captured: [String: Process] = [:]

    /// Ids of currently-running children.
    public var runningIDs: [String] { Array(children.keys) + captured.keys }

    public func isRunning(_ id: String) -> Bool {
        children[id] != nil || captured[id] != nil
    }

    // MARK: - Spawn (streaming)

    /// Spawns a streaming child. Returns after spawn; callers wait for
    /// `exit(id:)` events — never assume the return means the tool
    /// finished (docs/03).
    public func runStreaming(
        id: String,
        binary: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) throws {
        guard !isRunning(id) else { throw ProcessError.duplicateID(id) }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = childEnvironment(extra: environment)

        AppLogger(category: "process").debug(
            "spawn \(id): \(binary.path) \(LogSanitizer.sanitizeArgs(arguments))"
        )

        children[id] = RunningChild(
            process: process,
            stdin: stdinPipe.fileHandleForWriting,
            stdoutDecoder: ProcessLineDecoder(),
            stderrDecoder: ProcessLineDecoder()
        )

        do {
            try process.run()
        } catch {
            children.removeValue(forKey: id)
            emit(.error(id: id, message: error.localizedDescription))
            throw ProcessError.spawnFailed("\(binary.path): \(error.localizedDescription)")
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            Task { await self.ingestOutput(data, id: id, isStderr: false, handle: handle) }
        }
        stderrHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            Task { await self.ingestOutput(data, id: id, isStderr: true, handle: handle) }
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            Task { await self.didTerminate(id: id, code: proc.terminationStatus) }
        }
    }

    // MARK: - Spawn (captured)

    /// Runs a child to completion and returns all output. Reads stdout
    /// and stderr concurrently so a full pipe buffer can never deadlock
    /// the child. Used by `printcal` / `applycal` (docs/03) and by
    /// `CupsService` for `/usr/bin/lpstat`, `lpoptions`, `lp` (#12/#15).
    public func runCaptured(
        id: String,
        binary: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) async throws -> CapturedResult {
        guard !isRunning(id) else { throw ProcessError.duplicateID(id) }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = childEnvironment(extra: environment)

        AppLogger(category: "process").debug(
            "spawn(captured) \(id): \(binary.path) \(LogSanitizer.sanitizeArgs(arguments))"
        )

        // Register before run() so a concurrent duplicate spawn fails.
        captured[id] = process

        do {
            try process.run()
        } catch {
            captured.removeValue(forKey: id)
            emit(.error(id: id, message: error.localizedDescription))
            throw ProcessError.spawnFailed("\(binary.path): \(error.localizedDescription)")
        }

        async let outData = Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
        async let errData = Task.detached {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        let code = await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
        }

        let (out, err) = await (outData, errData)
        // If kill() already reaped this child, its exit event went out.
        if captured.removeValue(forKey: id) != nil {
            emit(.exit(id: id, code: code))
        }

        return CapturedResult(
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self),
            exitCode: code
        )
    }

    // MARK: - stdin

    /// Writes the exact bytes (caller includes `\n`) to a child's stdin
    /// and flushes (docs/03 §stdin protocol).
    public func sendStdin(id: String, bytes: Data) throws {
        guard let child = children[id] else { throw ProcessError.unknownID(id) }
        guard let handle = child.stdin else {
            throw ProcessError.stdinFailed("stdin closed for \(id)")
        }
        do {
            try handle.write(contentsOf: bytes)
        } catch {
            throw ProcessError.stdinFailed("\(id): \(error.localizedDescription)")
        }
    }

    public func sendStdin(id: String, text: String) throws {
        try sendStdin(id: id, bytes: Data(text.utf8))
    }

    // MARK: - Kill

    /// Terminates a child. The `exit` event still fires exactly once.
    /// stdin is dropped immediately so writers fail fast (docs/03 rule 7).
    public func kill(id: String) {
        if var child = children[id] {
            try? child.stdin?.close()
            child.stdin = nil
            children[id] = child
            if child.process.isRunning {
                child.process.terminate()
            } else {
                Task { await self.didTerminate(id: id, code: child.process.terminationStatus) }
            }
            return
        }
        if let process = captured[id] {
            if process.isRunning { process.terminate() }
            if captured.removeValue(forKey: id) != nil {
                emit(.exit(id: id, code: process.terminationStatus))
            }
        }
    }

    /// Terminates every running child; returns how many were signaled
    /// (`kill_all_processes`, docs/03). Mandatory on app exit (#147/#149).
    @discardableResult
    public func killAll() -> Int {
        let ids = Array(children.keys) + Array(captured.keys)
        for id in ids { kill(id: id) }
        return ids.count
    }

    // MARK: - Internals

    private func childEnvironment(extra: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ARGYLL_NOT_INTERACTIVE"] = "1"
        for (key, value) in extra { env[key] = value }
        return env
    }

    private func ingestOutput(
        _ data: Data,
        id: String,
        isStderr: Bool,
        handle: FileHandle
    ) {
        guard var child = children[id] else { return }

        if data.isEmpty {
            // EOF on this pipe.
            handle.readabilityHandler = nil
            if isStderr { child.stderrEOF = true } else { child.stdoutEOF = true }
            children[id] = child
            maybeFinalize(id: id)
            return
        }

        let lines: [String] = isStderr
            ? child.stderrDecoder.feed(data)
            : child.stdoutDecoder.feed(data)
        children[id] = child

        let log = AppLogger(category: "subprocess")
        for line in lines {
            if !isStderr, line.hasPrefix(Self.rowColorsPrefix) {
                let payload = Data(line.dropFirst(Self.rowColorsPrefix.count).utf8)
                emit(.jsonRow(id: id, payload: payload))
            } else if isStderr {
                log.warn("[\(id)] \(line)")
                emit(.stderr(id: id, line: line))
            } else {
                log.info("[\(id)] \(line)")
                emit(.stdout(id: id, line: line))
            }
        }
    }

    private func didTerminate(id: String, code: Int32) {
        guard var child = children[id], !child.finalized else { return }
        child.pendingExitCode = code
        try? child.stdin?.close()
        child.stdin = nil
        children[id] = child
        maybeFinalize(id: id)
    }

    /// Emits `exit` once the child has terminated *and* both pipes have
    /// drained to EOF, so no buffered output is lost.
    private func maybeFinalize(id: String) {
        guard var child = children[id],
              let code = child.pendingExitCode,
              child.stdoutEOF, child.stderrEOF,
              !child.finalized
        else { return }
        child.finalized = true
        children.removeValue(forKey: id)

        // Flush unterminated tail lines.
        if var decoder = Optional(child.stdoutDecoder),
           let tail = decoder.finish() {
            if tail.hasPrefix(Self.rowColorsPrefix) {
                emit(.jsonRow(id: id, payload: Data(tail.dropFirst(Self.rowColorsPrefix.count).utf8)))
            } else {
                emit(.stdout(id: id, line: tail))
            }
        }
        if var decoder = Optional(child.stderrDecoder),
           let tail = decoder.finish() {
            emit(.stderr(id: id, line: tail))
        }
        emit(.exit(id: id, code: code))
    }
}
