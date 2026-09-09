import Foundation

/// Errors from `ArgyllRunner` executions.
public enum ArgyllRunnerError: LocalizedError, Equatable, Sendable {
    case processFailed(code: Int32, logs: [String])
    case missingArtefact(String)
    case malformedManifest(String)
    case instrumentDetectionFailed(String)
    case chartreadFailed(String)
    case averageFailed(String)

    public var errorDescription: String? {
        switch self {
        case .processFailed(let code, _):
            return "Process exited with code \(code)"
        case .missingArtefact(let path):
            return "Expected output file was not created: \(path)"
        case .malformedManifest(let reason):
            return "Failed to parse printtarg manifest: \(reason)"
        case .instrumentDetectionFailed(let reason):
            return "Instrument detection failed: \(reason)"
        case .chartreadFailed(let reason):
            return "Chartread failed: \(reason)"
        case .averageFailed(let reason):
            return "Averaging failed: \(reason)"
        }
    }
}

/// Result of a successful `printtarg` run: the `.ti2` artefact plus the
/// validated manifest with per-page PNG previews already decoded.
public struct PrinttargResult: Sendable, Equatable {
    public let ti2URL: URL
    public let manifest: PrinttargManifest
    public let pages: [GalleryPage]
}

/// Service driving Argyll subprocesses off the main actor
/// (docs/03, docs/08, docs/09).
///
/// - Subscribes to the event bus *before* spawning so no stdout or exit
///   is ever lost (subscription is synchronous in `ProcessManager`).
/// - Accumulates stdout/stderr without touching `@MainActor`; the
///   optional `onLogBatch` callback receives coalesced chunks (20 lines
///   or ~100 ms), never one call per line.
/// - Exit code 0 is necessary but not sufficient: the expected artefact
///   (`.ti1` / `.ti2`) must exist on disk, and printtarg must emit a
///   valid `-u` manifest.
public struct ArgyllRunner: Sendable {
    public let processManager: ProcessManager
    public let binaryResolver: BinaryResolver

    public init(
        processManager: ProcessManager = .shared,
        binaryResolver: BinaryResolver = BinaryResolver()
    ) {
        self.processManager = processManager
        self.binaryResolver = binaryResolver
    }

    // MARK: - targen (Stage 1)

    /// Runs `targen` streaming, collecting logs and verifying `.ti1`
    /// upon completion. Returns the `.ti1` URL.
    public func runTargen(
        config: TargenConfig,
        onLogBatch: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> URL {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.basename)
        let cwd = PathSecurity.resolveSafeCwd(config.workingDirectory)
        let args = try TargenArgs.build(config: config)
        let binaryURL = binaryResolver.resolve("targen")
        let processId = ProcessID.targen(cleanBasename)

        let events = processManager.events()
        try await processManager.runStreaming(
            id: processId,
            binary: binaryURL,
            arguments: args,
            workingDirectory: cwd
        )
        let run = await collect(id: processId, events: events, onLogBatch: onLogBatch)

        guard run.exitCode == 0 else {
            throw ArgyllRunnerError.processFailed(code: run.exitCode ?? -1, logs: run.lines)
        }
        let ti1URL = cwd.appendingPathComponent("\(cleanBasename).ti1")
        guard FileManager.default.fileExists(atPath: ti1URL.path) else {
            throw ArgyllRunnerError.missingArtefact(ti1URL.path)
        }
        return ti1URL
    }

    // MARK: - printtarg (Stage 2)

    /// Runs `printtarg` streaming, then parses the `-u` manifest from
    /// the complete accumulated stdout and loads each page's PNG
    /// preview via `TiffPreview` (host-side, never raw TIFF to the UI).
    public func runPrinttarg(
        config: PrinttargConfig,
        onLogBatch: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> PrinttargResult {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.basename)
        let cwd = PathSecurity.resolveSafeCwd(config.workingDirectory)
        let args = try PrinttargArgs.build(config: config)
        let binaryURL = binaryResolver.resolve("printtarg")
        let processId = ProcessID.printtarg(cleanBasename)

        let events = processManager.events()
        try await processManager.runStreaming(
            id: processId,
            binary: binaryURL,
            arguments: args,
            workingDirectory: cwd
        )
        let run = await collect(id: processId, events: events, onLogBatch: onLogBatch)

        guard run.exitCode == 0 else {
            throw ArgyllRunnerError.processFailed(code: run.exitCode ?? -1, logs: run.lines)
        }
        let ti2URL = cwd.appendingPathComponent("\(cleanBasename).ti2")
        guard FileManager.default.fileExists(atPath: ti2URL.path) else {
            throw ArgyllRunnerError.missingArtefact(ti2URL.path)
        }

        let manifest: PrinttargManifest
        do {
            manifest = try PrinttargManifestExtractor.manifest(from: run.stdout)
        } catch {
            throw ArgyllRunnerError.malformedManifest(error.localizedDescription)
        }

        let pages = manifest.pages.enumerated().map { index, page -> GalleryPage in
            let fileURL = cwd.appendingPathComponent(page.filename)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return GalleryPage(
                    index: index, page: page, fileURL: fileURL,
                    previewPNG: nil, previewError: "File not found"
                )
            }
            if let png = TiffPreview.previewPNG(tiff: fileURL) {
                return GalleryPage(
                    index: index, page: page, fileURL: fileURL,
                    previewPNG: png, previewError: nil
                )
            }
            return GalleryPage(
                index: index, page: page, fileURL: fileURL,
                previewPNG: nil, previewError: "Could not decode TIFF"
            )
        }
        return PrinttargResult(ti2URL: ti2URL, manifest: manifest, pages: pages)
    }

    // MARK: - Shared collection

    private struct CollectedRun {
        var exitCode: Int32?
        var stdout: String
        var lines: [String]
    }

    /// Drains the event stream until this child's `exit` event.
    /// stdout is accumulated both per-line (logs) and verbatim (for
    /// the manifest parse — the pretty JSON needs its newlines).
    private func collect(
        id processId: String,
        events: AsyncStream<ProcessEvent>,
        onLogBatch: (@Sendable ([String]) -> Void)?
    ) async -> CollectedRun {
        var lines: [String] = []
        var stdout = ""
        var pendingBatch: [String] = []
        var exitCode: Int32?
        var lastFlush = Date()

        func flush(_ batch: inout [String]) {
            guard !batch.isEmpty else { return }
            let out = batch
            batch.removeAll(keepingCapacity: true)
            onLogBatch?(out)
        }

        for await event in events {
            guard event.id == processId else { continue }
            switch event {
            case .stdout(_, let line):
                lines.append(line)
                stdout += line + "\n"
                pendingBatch.append(line)
            case .stderr(_, let line):
                lines.append(line)
                pendingBatch.append(line)
            case .error(_, let message):
                lines.append("Error: \(message)")
                pendingBatch.append("Error: \(message)")
            case .jsonRow:
                // Only chartread emits these; targen/printtarg never do.
                break
            case .exit(_, let code):
                exitCode = code
            }
            if exitCode == nil,
               pendingBatch.count >= 20
                || Date().timeIntervalSince(lastFlush) >= 0.1 {
                flush(&pendingBatch)
                lastFlush = Date()
            }
            if exitCode != nil {
                flush(&pendingBatch)
                break
            }
        }
        return CollectedRun(exitCode: exitCode, stdout: stdout, lines: lines)
    }

    // MARK: - instlist (Stage 3 detection)

    /// Runs `instlist` and returns the detected devices.
    ///
    /// The fork emits pretty-printed JSON; if that cannot be decoded a regex
    /// fallback constrained to known instrument tokens is used.
    public func detectInstruments() async throws -> [InstrumentDevice] {
        let binaryURL = binaryResolver.resolve("instlist")
        let processId = ProcessID.instlist

        let events = processManager.events()
        try await processManager.runStreaming(
            id: processId,
            binary: binaryURL,
            arguments: [],
            workingDirectory: nil
        )

        var accumulator = JSONAccumulator()
        var stdout = ""
        var stderr: [String] = []
        var exitCode: Int32?

        for await event in events {
            guard event.id == processId else { continue }
            switch event {
            case .stdout(_, let line):
                stdout += line + "\n"
                _ = accumulator.feed(line: line)
            case .stderr(_, let line):
                stderr.append(line)
            case .exit(_, let code):
                exitCode = code
            default:
                break
            }
            if exitCode != nil { break }
        }

        if let data = accumulator.completeData ?? stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) {
            if let devices = try? InstrumentParser.parse(String(data: data, encoding: .utf8) ?? stdout) {
                return devices
            }
        }

        if let code = exitCode, code != 0, stderr.isEmpty == false {
            throw ArgyllRunnerError.instrumentDetectionFailed(stderr.joined(separator: "\n"))
        }

        // Final fallback: try to parse the raw stdout as a text document.
        if let devices = try? InstrumentParser.parse(stdout) {
            return devices
        }

        throw ArgyllRunnerError.instrumentDetectionFailed("Could not parse instlist output")
    }

    // MARK: - average (Stage 3 multi-pass finish)

    /// Runs `average` to merge two or more pass snapshots into the canonical `.ti3`.
    public func runAverage(
        config: AverageConfig,
        onLogBatch: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> URL {
        let cwd = PathSecurity.resolveSafeCwd(config.workingDirectory)
        let args = try AverageArgs.build(config: config)
        let binaryURL = binaryResolver.resolve("average")
        let processId = ProcessID.average(config.basename)

        let events = processManager.events()
        try await processManager.runStreaming(
            id: processId,
            binary: binaryURL,
            arguments: args,
            workingDirectory: cwd
        )
        let run = await collect(id: processId, events: events, onLogBatch: onLogBatch)

        guard run.exitCode == 0 else {
            throw ArgyllRunnerError.averageFailed("average exited with code \(run.exitCode ?? -1)")
        }

        let canonical = cwd.appendingPathComponent("\(config.basename).ti3")
        guard FileManager.default.fileExists(atPath: canonical.path) else {
            throw ArgyllRunnerError.missingArtefact(canonical.path)
        }
        return canonical
    }

    // MARK: - chartread (Stage 3 interactive)

    /// Runs `chartread` and returns an `AsyncStream` of typed events.
    ///
    /// Subscribe-before-spawn, prompt/row/log forwarding, and exit verification
    /// are all handled here. Use `sendChartreadInput` to drive the child and
    /// `cancelChartread` to terminate it.
    public func runChartread(config: ChartreadConfig) -> AsyncStream<ChartreadEvent> {
        let cleanBasename: String
        let cwd: URL
        do {
            cleanBasename = try PathSecurity.sanitizeBasename(config.basename)
            cwd = PathSecurity.resolveSafeCwd(config.workingDirectory)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.failed(ArgyllRunnerError.chartreadFailed(error.localizedDescription)))
                continuation.finish()
            }
        }

        let args: [String]
        do {
            args = try ChartreadArgs.build(config: config)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.failed(ArgyllRunnerError.chartreadFailed(error.localizedDescription)))
                continuation.finish()
            }
        }

        let binaryURL = binaryResolver.resolve("chartread")
        let processId = ProcessID.chartread(cleanBasename)
        let processManager = self.processManager

        return AsyncStream { continuation in
            let task = Task {
                let events = processManager.events()

                do {
                    try await processManager.runStreaming(
                        id: processId,
                        binary: binaryURL,
                        arguments: args,
                        workingDirectory: cwd
                    )
                } catch {
                    continuation.yield(.failed(ArgyllRunnerError.chartreadFailed(error.localizedDescription)))
                    continuation.finish()
                    return
                }

                var state: ChartreadState = .idle
                var pendingLogs: [String] = []
                var lastFlush = Date()
                var exitCode: Int32?

                func flushLogs() {
                    guard !pendingLogs.isEmpty else { return }
                    let batch = pendingLogs
                    pendingLogs.removeAll(keepingCapacity: true)
                    continuation.yield(.log(batch))
                }

                for await event in events {
                    guard event.id == processId else { continue }

                    switch event {
                    case .stdout(_, let line):
                        let classified = ChartreadClassifier.classify(line: line, previousState: state)
                        state = classified.state
                        if classified.isRemoveSheetNotice {
                            continuation.yield(.removeSheetNotice)
                        }
                        if classified.sheetNumber != nil || classified.alignmentPatch != nil {
                            continuation.yield(.prompt(classified))
                        } else if state != previousOrContinuationState(state, classified) {
                            // Only emit prompt when the state meaningfully changes.
                            continuation.yield(.prompt(classified))
                        } else if state == .tablePlaceSheet || state == .tableAlign {
                            // Continuation lines in table states are still prompts.
                            continuation.yield(.prompt(classified))
                        } else if classified.requestedWarningKey != nil {
                            continuation.yield(.prompt(classified))
                        }

                        pendingLogs.append(line)

                    case .stderr(_, let line):
                        pendingLogs.append(line)

                    case .jsonRow(_, let payload):
                        do {
                            let row = try JSONDecoder().decode(ChartreadRow.self, from: payload)
                            state = row.isFinalRow ? .allStripsRead : state
                            continuation.yield(.row(row))
                        } catch {
                            pendingLogs.append("Malformed row JSON: \(error.localizedDescription)")
                        }

                    case .error(_, let message):
                        pendingLogs.append("Error: \(message)")

                    case .exit(_, let code):
                        exitCode = code
                    }

                    if exitCode == nil,
                       pendingLogs.count >= 20 || Date().timeIntervalSince(lastFlush) >= 0.1 {
                        flushLogs()
                        lastFlush = Date()
                    }

                    if exitCode != nil {
                        flushLogs()
                        break
                    }
                }

                let canonical = cwd.appendingPathComponent("\(cleanBasename).ti3")
                if let code = exitCode, code == 0 {
                    if FileManager.default.fileExists(atPath: canonical.path) {
                        continuation.yield(.completed(canonical))
                    } else {
                        continuation.yield(.failed(ArgyllRunnerError.missingArtefact(canonical.path)))
                    }
                } else {
                    continuation.yield(.failed(ArgyllRunnerError.chartreadFailed("chartread exited with code \(exitCode ?? -1)")))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func previousOrContinuationState(_ state: ChartreadState, _ classified: ChartreadClassifyResult) -> ChartreadState {
        if classified.isTableContinuation { return .promptContinue }
        return state
    }

    /// Send an exact input sequence to the running `chartread` child.
    public func sendChartreadInput(basename: String, input: ChartreadInput) async throws {
        let cleanBasename = try PathSecurity.sanitizeBasename(basename)
        let processId = ProcessID.chartread(cleanBasename)
        try await processManager.sendStdin(id: processId, bytes: input.bytes)
    }

    /// Terminate a running `chartread` child.
    ///
    /// For XY tables, sends `q\n` first and waits ~500 ms so the head parks.
    public func cancelChartread(basename: String, isXY: Bool = false) {
        let cleanBasename = try? PathSecurity.sanitizeBasename(basename)
        guard let cleanBasename else { return }
        let processId = ProcessID.chartread(cleanBasename)

        Task {
            if isXY {
                try? await processManager.sendStdin(id: processId, bytes: ChartreadInput.quit.bytes)
                try? await Task.sleep(for: .milliseconds(500))
            }
            await processManager.kill(id: processId)
        }
    }
}

/// Events emitted by a running `chartread` session.
public enum ChartreadEvent: Sendable {
    /// Classified prompt / state update.
    case prompt(ChartreadClassifyResult)
    /// A decoded `ROW_COLORS_JSON` row.
    case row(ChartreadRow)
    /// A batched log chunk (stdout + stderr lines).
    case log([String])
    /// Informational "remove last sheet" notice.
    case removeSheetNotice
    /// Process exited with the given code.
    case exit(Int32)
    /// Successful completion with the canonical `.ti3` URL.
    case completed(URL)
    /// Failure (non-zero exit, missing artefact, spawn/parse error).
    case failed(ArgyllRunnerError)
}

/// Exact bytes sent to `chartread` stdin.
public enum ChartreadInput: Sendable {
    case trigger    // " \n"
    case accept     // "\n"
    case done       // "d\n"
    case quit       // "q\n"
    case customKey(String)

    public var bytes: Data {
        switch self {
        case .trigger:
            return Data(" \n".utf8)
        case .accept:
            return Data("\n".utf8)
        case .done:
            return Data("d\n".utf8)
        case .quit:
            return Data("q\n".utf8)
        case .customKey(let key):
            return Data("\(key)\n".utf8)
        }
    }
}
