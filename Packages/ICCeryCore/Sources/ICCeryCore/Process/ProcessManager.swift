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
///   exits or kills.  If EOFs never arrive, a watchdog finalizes.
/// - `kill` runs a pre-kill hook (e.g. XY `q\n` + 500 ms park) before
///   terminating.  Hooks are removed once the child finalizes.
/// - `killAll` on `NSApplication.willTerminate` and last-window close
///   runs all hooks and terminates every child (#147, #149).
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
        /// Watchdog that forces finalization if EOFs never arrive.
        var finalizeTask: Task<Void, Never>?
    }

    private var children: [String: RunningChild] = [:]
    /// Processes owned by `runCaptured` (dup detection + kill support).
    private var captured: [String: Process] = [:]

    /// Hooks run by `kill` before terminating the child.
    /// Used by `chartread` to park an XY head with `q\n`.
    private var preKillHooks: [String: @Sendable () async -> Void] = [:]

    /// Ids of currently-running children.
    public var runningIDs: [String] { Array(children.keys) + captured.keys }

    public func isRunning(_ id: String) -> Bool {
        children[id] != nil || captured[id] != nil
    }

    // MARK: - Pre-kill hooks

    /// Register a hook to run before `kill(id:)` terminates the child.
    /// The hook is removed once the child finalizes.
    public func setPreKillHook(id: String, hook: @escaping @Sendable () async -> Void) {
        preKillHooks[id] = hook
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

        let prepared = makeProcess(
            binary: binary,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            includeStdin: true
        )
        let process = prepared.process

        AppLogger(category: "process").debug(
            "spawn \(id): \(binary.path) \(LogSanitizer.sanitizeArgs(arguments))"
        )

        children[id] = RunningChild(
            process: process,
            stdin: prepared.stdinPipe?.fileHandleForWriting,
            stdoutDecoder: ProcessLineDecoder(),
            stderrDecoder: ProcessLineDecoder()
        )

        let stdoutHandle = prepared.stdoutPipe.fileHandleForReading
        let stderrHandle = prepared.stderrPipe.fileHandleForReading
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

        attachExitWatchdog(process) { [weak self] code in
            guard let self else { return }
            Task { await self.didTerminate(id: id, code: code) }
        }

        do {
            try process.run()
        } catch {
            preKillHooks.removeValue(forKey: id)
            children.removeValue(forKey: id)
            emit(.error(id: id, message: error.localizedDescription))
            throw ProcessError.spawnFailed("\(binary.path): \(error.localizedDescription)")
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

        let prepared = makeProcess(
            binary: binary,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            includeStdin: false
        )
        let process = prepared.process
        let stdoutPipe = prepared.stdoutPipe
        let stderrPipe = prepared.stderrPipe

        AppLogger(category: "process").debug(
            "spawn(captured) \(id): \(binary.path) \(LogSanitizer.sanitizeArgs(arguments))"
        )

        // Register and set up the termination hand-off before run() so
        // a very fast exit is never missed (#50, #52).
        captured[id] = process

        let capturedProcess = process

        // Box is local and synchronised with an NSLock; the @unchecked
        // Sendable annotation is safe because all access is under the lock.
        final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private var status: Int32?
            private var continuation: CheckedContinuation<Int32, Never>?

            /// Try to resume an already-stored continuation with the exit
            /// status. Returns true if a continuation was resumed.
            func resume(with status: Int32) -> Bool {
                lock.lock()
                if let cont = continuation {
                    continuation = nil
                    lock.unlock()
                    cont.resume(returning: status)
                    return true
                }
                self.status = status
                lock.unlock()
                return false
            }

            /// Store a continuation, returning any status that arrived
            /// before it. The caller must resume with the returned status.
            func store(_ continuation: CheckedContinuation<Int32, Never>) -> Int32? {
                lock.lock()
                if let status = status {
                    self.status = nil
                    self.continuation = nil
                    lock.unlock()
                    return status
                }
                self.continuation = continuation
                // A fast exit may have raced past the first nil-check.
                if let status = status {
                    self.status = nil
                    self.continuation = nil
                    lock.unlock()
                    return status
                }
                lock.unlock()
                return nil
            }
        }
        let box = Box()
        attachExitWatchdog(capturedProcess) { status in
            _ = box.resume(with: status)
        }

        do {
            try process.run()
        } catch {
            _ = box.resume(with: -1)
            captured.removeValue(forKey: id)
            preKillHooks.removeValue(forKey: id)
            emit(.error(id: id, message: error.localizedDescription))
            throw ProcessError.spawnFailed("\(binary.path): \(error.localizedDescription)")
        }

        // Close the parent write ends so readDataToEndOfFile() gets EOF
        // as soon as the child exits; the child still has its own copies.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        return await withTaskCancellationHandler {
            async let outData = Task.detached {
                stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            }.value
            async let errData = Task.detached {
                stderrPipe.fileHandleForReading.readDataToEndOfFile()
            }.value

            let code = await withCheckedContinuation { continuation in
                if let status = box.store(continuation) {
                    continuation.resume(returning: status)
                }
            }

            let (out, err) = await (outData, errData)

            // Emit the real exit code once, regardless of whether kill()
            // already removed the id from `captured`.
            _ = captured.removeValue(forKey: id)
            preKillHooks.removeValue(forKey: id)
            emit(.exit(id: id, code: code))

            return CapturedResult(
                stdout: String(decoding: out, as: UTF8.self),
                stderr: String(decoding: err, as: UTF8.self),
                exitCode: code
            )
        } onCancel: { [weak self] in
            // If the awaiting Task is cancelled, terminate the child so
            // callers like runApplycal never replace a good profile with
            // a truncated tmp.
            if capturedProcess.isRunning {
                capturedProcess.terminate()
            }
            Task { [weak self] in
                await self?.kill(id: id)
            }
        }
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

    // MARK: - Partial-line flush

    /// Emits the current unterminated tail of a streaming child's stdout
    /// and stderr as ordinary lines.  Callers (e.g. `colprof`) use this
    /// to flush progress dots without waiting for a newline.
    public func flushPartialLine(id: String) {
        guard var child = children[id], !child.finalized else { return }

        if let tail = child.stdoutDecoder.flushPartial() {
            emitStdoutLine(id: id, line: tail)
        }
        if let tail = child.stderrDecoder.flushPartial() {
            emit(.stderr(id: id, line: tail))
        }

        children[id] = child
    }

    // MARK: - Kill

    /// Terminates a child.  First runs any registered pre-kill hook, then
    /// drops stdin and signals the process.  For streaming children the
    /// `exit` event is emitted once both stdout and stderr EOFs have been
    /// seen (or the watchdog finalizes).  For captured children the real
    /// exit code is emitted by `runCaptured` itself.
    public func kill(id: String) async {
        if let hook = preKillHooks.removeValue(forKey: id) {
            await hook()
        }

        if var child = children[id] {
            try? child.stdin?.close()
            child.stdin = nil
            children[id] = child

            if child.process.isRunning {
                child.process.terminate()
            } else if child.pendingExitCode == nil {
                // The process already exited but `didTerminate` has not
                // run; synthesize it so `maybeFinalize` can fire.
                didTerminate(id: id, code: child.process.terminationStatus)
            }
            return
        }

        if let process = captured[id] {
            if process.isRunning { process.terminate() }
            // Do not emit `.exit` here; `runCaptured` emits the real code
            // after the process reaps.
            return
        }
    }

    /// Terminates every running child; returns how many were signaled
    /// (`kill_all_processes`, docs/03). Mandatory on app exit (#147/#149).
    @discardableResult
    public func killAll() async -> Int {
        let ids = runningIDs
        for id in ids { await kill(id: id) }
        return ids.count
    }

    // MARK: - Force kill (SIGKILL fallback)

    /// Sends `SIGKILL` to a streaming child if it is still running.
    /// Used by the finalization watchdog when a graceful `terminate()`
    /// does not cause the process to exit.
    public func forceKill(id: String) {
        guard let child = children[id],
              !child.finalized,
              child.process.isRunning
        else { return }

        let pid = child.process.processIdentifier
        guard pid > 0 else { return }
        _ = Darwin.kill(pid, SIGKILL)
    }

    // MARK: - Internals

    private struct PreparedProcess {
        let process: Process
        let stdinPipe: Pipe?
        let stdoutPipe: Pipe
        let stderrPipe: Pipe
    }

    private func makeProcess(
        binary: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String],
        includeStdin: Bool
    ) -> PreparedProcess {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe: Pipe? = includeStdin ? Pipe() : nil
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let stdinPipe {
            process.standardInput = stdinPipe
        }
        process.environment = childEnvironment(extra: environment)
        return PreparedProcess(
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )
    }

    /// terminationHandler can lose a fast-exit race on a loaded host;
    /// `waitUntilExit` on a detached thread is the fallback (#50, #52).
    private func attachExitWatchdog(
        _ process: Process,
        onExit: @escaping @Sendable (Int32) -> Void
    ) {
        process.terminationHandler = { proc in
            onExit(proc.terminationStatus)
        }
        Task.detached { [process] in
            process.waitUntilExit()
            onExit(process.terminationStatus)
        }
    }

    private func emitStdoutLine(id: String, line: String) {
        if line.hasPrefix(Self.rowColorsPrefix) {
            let payload = Data(line.dropFirst(Self.rowColorsPrefix.count).utf8)
            emit(.jsonRow(id: id, payload: payload))
        } else {
            emit(.stdout(id: id, line: line))
        }
    }

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
            if !isStderr {
                emitStdoutLine(id: id, line: line)
                if !line.hasPrefix(Self.rowColorsPrefix) {
                    log.info("[\(id)] \(line)")
                }
            } else {
                log.warn("[\(id)] \(line)")
                emit(.stderr(id: id, line: line))
            }
        }
    }

    private func didTerminate(id: String, code: Int32) {
        guard var child = children[id], !child.finalized else { return }
        child.pendingExitCode = code
        try? child.stdin?.close()
        child.stdin = nil

        // Start a watchdog in case the `readabilityHandler` EOFs never
        // arrive after the process exits (e.g. a hung pipe).
        child.finalizeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            await self.forceKill(id: id)
            await self.forceFinalize(id: id)
        }

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
        child.finalizeTask?.cancel()
        child.finalizeTask = nil
        children.removeValue(forKey: id)
        preKillHooks.removeValue(forKey: id)

        // Flush unterminated tail lines.
        if var decoder = Optional(child.stdoutDecoder),
           let tail = decoder.finish() {
            emitStdoutLine(id: id, line: tail)
        }
        if var decoder = Optional(child.stderrDecoder),
           let tail = decoder.finish() {
            emit(.stderr(id: id, line: tail))
        }
        emit(.exit(id: id, code: code))
    }

    /// Forces finalization even when one or both EOFs are missing.
    /// Used by the `didTerminate` watchdog.
    private func forceFinalize(id: String) {
        guard var child = children[id], !child.finalized else { return }

        if child.pendingExitCode == nil {
            child.pendingExitCode = -9
        }
        child.stdoutEOF = true
        child.stderrEOF = true
        child.finalizeTask?.cancel()
        child.finalizeTask = nil
        children[id] = child
        maybeFinalize(id: id)
    }
}
