import Foundation

/// Errors from `ArgyllRunner` executions.
public enum ArgyllRunnerError: LocalizedError, Equatable, Sendable {
    case toolFailed(tool: String, code: Int32, logs: [String])
    case missingArtefact(String)
    case malformedManifest(String)
    case instrumentDetectionFailed(String)
    case profcheckUnparseable

    public var errorDescription: String? {
        switch self {
        case .toolFailed(let tool, let code, let logs):
            let detail = logs.last.flatMap { $0.isEmpty ? nil : $0 }
                ?? "exited with code \(code)"
            switch tool {
            case "chartread":
                return "Chartread failed: \(detail)"
            case "average":
                return "Averaging failed: \(detail)"
            case "colprof":
                return "Profile creation failed: \(detail)"
            case "printcal":
                return "Calibration curve computation failed: \(detail)"
            case "applycal":
                return "Apply calibration failed: \(detail)"
            case "iccgamut":
                return "Gamut extraction failed: \(detail)"
            case "profcheck":
                return "Profile verification failed: \(detail)"
            default:
                return "Process exited with code \(code)"
            }
        case .missingArtefact(let path):
            return "Expected output file was not created: \(path)"
        case .malformedManifest(let reason):
            return "Failed to parse printtarg manifest: \(reason)"
        case .instrumentDetectionFailed(let reason):
            return "Instrument detection failed: \(reason)"
        case .profcheckUnparseable:
            return "Profile verification produced unparseable output"
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

    // MARK: - Shared streaming loop (issue #79)

    private func runStreamingTool(
        name: String,
        id: String,
        arguments: [String],
        workingDirectory: URL?,
        flushPartialLines: Bool = false,
        onLogBatch: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> CollectedRun {
        let binaryURL = binaryResolver.resolve(name)
        await ensureNotRunning(id: id)
        let events = processManager.events()
        try await processManager.runStreaming(
            id: id,
            binary: binaryURL,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
        let run = await collect(
            id: id,
            events: events,
            onLogBatch: onLogBatch,
            flushPartialLines: flushPartialLines
        )
        guard run.exitCode == 0 else {
            throw ArgyllRunnerError.toolFailed(
                tool: name,
                code: run.exitCode ?? -1,
                logs: run.lines
            )
        }
        return run
    }

    private func requireArtefact(_ url: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArgyllRunnerError.missingArtefact(url.path)
        }
        return url
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
        let processId = ProcessID.targen(cleanBasename)
        _ = try await runStreamingTool(
            name: "targen",
            id: processId,
            arguments: args,
            workingDirectory: cwd,
            onLogBatch: onLogBatch
        )
        let ti1URL = cwd.appendingPathComponent("\(cleanBasename).ti1")
        return try requireArtefact(ti1URL)
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
        let processId = ProcessID.printtarg(cleanBasename)
        let run = try await runStreamingTool(
            name: "printtarg",
            id: processId,
            arguments: args,
            workingDirectory: cwd,
            onLogBatch: onLogBatch
        )
        let ti2URL = try requireArtefact(cwd.appendingPathComponent("\(cleanBasename).ti2"))

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

    /// Cancels any previous child with the same id and waits for it to
    /// finalize, so `runStreaming` / `runCaptured` never sees a
    /// `duplicateID` from a leftover process (#50, #52).
    private func ensureNotRunning(id: String) async {
        guard await processManager.isRunning(id) else { return }
        await processManager.kill(id: id)
        var attempts = 0
        while await processManager.isRunning(id), attempts < 30 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
    }

    private struct CollectedRun {
        var exitCode: Int32?
        var stdout: String
        var stderr: String
        var lines: [String]
    }

    /// Drains the event stream until this child's `exit` event.
    /// stdout is accumulated both per-line (logs) and verbatim (for
    /// the manifest parse — the pretty JSON needs its newlines).
    ///
    /// When `flushPartialLines` is `true`, a background `Task` flushes
    /// unterminated output every 500 ms so tools like `colprof` that
    /// print dots without newlines still produce log batches.
    private func collect(
        id processId: String,
        events: AsyncStream<ProcessEvent>,
        onLogBatch: (@Sendable ([String]) -> Void)?,
        flushPartialLines: Bool = false
    ) async -> CollectedRun {
        var lines: [String] = []
        var stdout = ""
        var stderr = ""
        var pendingBatch: [String] = []
        var exitCode: Int32?
        var lastFlush = Date()

        func flush(_ batch: inout [String]) {
            guard !batch.isEmpty else { return }
            let out = batch
            batch.removeAll(keepingCapacity: true)
            onLogBatch?(out)
        }

        var dotFlushTask: Task<Void, Never>?
        if flushPartialLines {
            dotFlushTask = Task { [processManager] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if Task.isCancelled { break }
                    await processManager.flushPartialLine(id: processId)
                }
            }
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
                stderr += line + "\n"
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

        dotFlushTask?.cancel()
        if let dotFlushTask {
            _ = await dotFlushTask.value
        }

        return CollectedRun(exitCode: exitCode, stdout: stdout, stderr: stderr, lines: lines)
    }

    // MARK: - instlist (Stage 3 detection)

    /// Runs `instlist` and returns the detected devices.
    ///
    /// The fork emits pretty-printed JSON; if that cannot be decoded a regex
    /// fallback constrained to known instrument tokens is used.
    public func detectInstruments() async throws -> [InstrumentDevice] {
        let binaryURL = binaryResolver.resolve("instlist")
        let processId = ProcessID.instlist

        await ensureNotRunning(id: processId)
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
        let processId = ProcessID.average(config.basename)
        _ = try await runStreamingTool(
            name: "average",
            id: processId,
            arguments: args,
            workingDirectory: cwd,
            onLogBatch: onLogBatch
        )
        let canonical = cwd.appendingPathComponent("\(config.basename).ti3")
        return try requireArtefact(canonical)
    }

    // MARK: - colprof (Stage 4)

    /// Runs `colprof` streaming, collecting logs and classifying progress
    /// until the profile is written.
    public func runColprof(
        config: ColprofConfig,
        onLogBatch: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> URL {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.basename)
        let cwd = PathSecurity.resolveSafeCwd(config.workingDirectory)
        let args = try ColprofArgs.build(config: config)
        let processId = ProcessID.colprof(cleanBasename)
        _ = try await runStreamingTool(
            name: "colprof",
            id: processId,
            arguments: args,
            workingDirectory: cwd,
            flushPartialLines: true,
            onLogBatch: onLogBatch
        )

        // Argyll may produce `.icm` on Windows, but on macOS we expect `.icc`.
        // `resolveProfile` checks `.icm` first, then `.icc`, matching #69.
        guard let profileURL = ArtefactProbe.resolveProfile(
            basename: cleanBasename,
            cwd: cwd
        ) else {
            let defaultURL = cwd.appendingPathComponent("\(cleanBasename).icc")
            throw ArgyllRunnerError.missingArtefact(defaultURL.path)
        }
        return profileURL
    }

    // MARK: - applycal (post-colprof calibration curve)

    /// Embeds a `.cal` curve into an `.icc`/`.icm` profile.
    ///
    /// Runs `applycal` captured and performs an in-place replace via
    /// `{input}.applycal.tmp` then `replaceItemAt`. On failure the tmp
    /// file is removed and the original is left untouched. The UI must
    /// never request `unapply` (#52).
    public func runApplycal(
        config: ApplycalConfig
    ) async throws -> URL {
        assert(!config.unapply, "runApplycal does not support unapply")

        let inputURL = config.inputProfileURL
        let cwd = inputURL.deletingLastPathComponent()
        let binaryURL = binaryResolver.resolve("applycal")
        let processId = ProcessID.applycal(inputURL.lastPathComponent)

        let tmpURL = inputURL.appendingPathExtension("applycal.tmp")
        let fm = FileManager.default

        // Remove any stale tmp from a previous crash.
        try? fm.removeItem(at: tmpURL)

        await ensureNotRunning(id: processId)

        let outputConfig = ApplycalConfig(
            calibrationPath: config.calibrationPath,
            inputProfileURL: inputURL,
            outputProfileURL: tmpURL,
            unapply: false
        )
        let outputArgs = try ApplycalArgs.build(config: outputConfig)

        let result = try await processManager.runCaptured(
            id: processId,
            binary: binaryURL,
            arguments: outputArgs,
            workingDirectory: cwd
        )

        guard result.exitCode == 0, !Task.isCancelled else {
            try? fm.removeItem(at: tmpURL)
            if Task.isCancelled {
                throw CancellationError()
            }
            throw ArgyllRunnerError.toolFailed(
                tool: "applycal",
                code: result.exitCode,
                logs: [result.stderr.isEmpty
                    ? "applycal exited with code \(result.exitCode)"
                    : result.stderr]
            )
        }

        guard fm.fileExists(atPath: tmpURL.path) else {
            throw ArgyllRunnerError.toolFailed(
                tool: "applycal",
                code: -1,
                logs: ["applycal did not create temp profile"]
            )
        }

        let attrs = try? fm.attributesOfItem(atPath: tmpURL.path)
        let size = attrs?[.size] as? UInt64 ?? 0
        guard size >= 128 else {
            try? fm.removeItem(at: tmpURL)
            throw ArgyllRunnerError.toolFailed(
                tool: "applycal",
                code: -1,
                logs: ["calibrated profile is too small (\(size) bytes)"]
            )
        }

        do {
            if fm.fileExists(atPath: inputURL.path) {
                _ = try fm.replaceItemAt(inputURL, withItemAt: tmpURL)
            } else {
                try fm.moveItem(at: tmpURL, to: inputURL)
            }
        } catch {
            try? fm.removeItem(at: tmpURL)
            throw ArgyllRunnerError.toolFailed(
                tool: "applycal",
                code: -1,
                logs: [error.localizedDescription]
            )
        }

        return inputURL
    }

    // MARK: - iccgamut (post-colprof gamut mesh)

    /// Extracts a `.gam` mesh from the finished profile.
    public func runIccgamut(
        config: IccgamutConfig,
        onLogBatch: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> URL {
        let profileURL = config.profileURL
        let cwd = profileURL.deletingLastPathComponent()
        let stem = profileURL.deletingPathExtension().lastPathComponent
        let args = try IccgamutArgs.build(config: config)
        let processId = ProcessID.iccgamut(stem: stem)
        _ = try await runStreamingTool(
            name: "iccgamut",
            id: processId,
            arguments: args,
            workingDirectory: cwd,
            onLogBatch: onLogBatch
        )
        let gamURL = cwd.appendingPathComponent("\(stem).gam")
        return try requireArtefact(gamURL)
    }

    // MARK: - profcheck (Stage 5 verification)

    /// Verifies a profile against the canonical `.ti3`.
    public func runProfcheck(
        config: ProfcheckConfig,
        onLogBatch: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> ProfcheckReport {
        let cwd = config.ti3URL.deletingLastPathComponent()
        let ti3Path = config.ti3URL.path

        let iccURL = ArtefactProbe.resolveProfile(config.iccURL)
        let config = ProfcheckConfig(ti3URL: config.ti3URL, iccURL: iccURL)

        let args = try ProfcheckArgs.build(config: config)
        let processId = ProcessID.profcheck(ti3Path: ti3Path)
        let run = try await runStreamingTool(
            name: "profcheck",
            id: processId,
            arguments: args,
            workingDirectory: cwd,
            onLogBatch: onLogBatch
        )

        let output = (run.stdout + "\n" + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        let report = ProfcheckParser.parse(output)
        guard report.isValid else {
            throw ArgyllRunnerError.profcheckUnparseable
        }
        return report
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
                continuation.yield(.failed(ArgyllRunnerError.toolFailed(tool: "chartread", code: -1, logs: [error.localizedDescription])))
                continuation.finish()
            }
        }

        let args: [String]
        do {
            args = try ChartreadArgs.build(config: config)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.failed(ArgyllRunnerError.toolFailed(tool: "chartread", code: -1, logs: [error.localizedDescription])))
                continuation.finish()
            }
        }

        let binaryURL = binaryResolver.resolve("chartread")
        let processId = ProcessID.chartread(cleanBasename)
        let processManager = self.processManager
        let isXY = config.isXY

        return AsyncStream { continuation in
            let task = Task {
                await ensureNotRunning(id: processId)
                let events = processManager.events()

                // Register the XY parking hook before spawning.
                await processManager.setPreKillHook(id: processId) { [processManager] in
                    if isXY {
                        try? await processManager.sendStdin(id: processId, bytes: ChartreadInput.quit.bytes)
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }

                do {
                    try await processManager.runStreaming(
                        id: processId,
                        binary: binaryURL,
                        arguments: args,
                        workingDirectory: cwd
                    )
                } catch {
                    continuation.yield(.failed(ArgyllRunnerError.toolFailed(tool: "chartread", code: -1, logs: [error.localizedDescription])))
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
                        let previous = state
                        let classified = ChartreadClassifier.classify(line: line, previousState: previous)
                        state = classified.state

                        if classified.isRemoveSheetNotice {
                            continuation.yield(.removeSheetNotice)
                        }

                        let shouldPrompt =
                            classified.sheetNumber != nil
                            || classified.alignmentPatch != nil
                            || classified.requestedWarningKey != nil
                            || classified.state != previous
                            || classified.isTableContinuation

                        if shouldPrompt {
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

                if Task.isCancelled {
                    continuation.finish()
                    return
                }

                let canonical = cwd.appendingPathComponent("\(cleanBasename).ti3")
                if let code = exitCode, code == 0 {
                    if FileManager.default.fileExists(atPath: canonical.path) {
                        continuation.yield(.completed(canonical))
                    } else {
                        continuation.yield(.failed(ArgyllRunnerError.missingArtefact(canonical.path)))
                    }
                } else {
                    continuation.yield(.failed(ArgyllRunnerError.toolFailed(
                        tool: "chartread",
                        code: exitCode ?? -1,
                        logs: ["chartread exited with code \(exitCode ?? -1)"]
                    )))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    await processManager.kill(id: processId)
                }
            }
        }
    }

    /// Send an exact input sequence to the running `chartread` child.
    public func sendChartreadInput(basename: String, input: ChartreadInput) async throws {
        let cleanBasename = try PathSecurity.sanitizeBasename(basename)
        let processId = ProcessID.chartread(cleanBasename)
        try await processManager.sendStdin(id: processId, bytes: input.bytes)
    }

    /// Terminate a running `chartread` child.
    ///
    /// The actual XY parking is handled by the pre-kill hook registered in
    /// `runChartread`.
    public func cancelChartread(basename: String, isXY: Bool = false) {
        let cleanBasename = try? PathSecurity.sanitizeBasename(basename)
        guard let cleanBasename else { return }
        let processId = ProcessID.chartread(cleanBasename)

        Task {
            await processManager.kill(id: processId)
        }
    }

    // MARK: - Stage 0 calibration

    /// Generates a calibration wedge `.ti1`.
    public func runCalibrationTargen(
        config: CalibrationTargenConfig,
        onLogBatch: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> URL {
        let args = try CalibrationTargenArgs.build(config: config)
        let cwd = PathSecurity.resolveSafeCwd(config.workingDirectory)
        let cleanBasename = try PathSecurity.sanitizeBasename(
            CalibrationIdentity.prefix(config.basename)
        )
        let processId = ProcessID.targen(cleanBasename)
        _ = try await runStreamingTool(
            name: "targen",
            id: processId,
            arguments: args,
            workingDirectory: cwd,
            onLogBatch: onLogBatch
        )
        let ti1URL = cwd.appendingPathComponent("\(cleanBasename).ti1")
        return try requireArtefact(ti1URL)
    }

    /// Computes a `.cal` curve from a measured `CAL_*.ti3`.
    ///
    /// `printcal` is captured (not streamed) and is exempt from the `-u`
    /// JSON policy.
    public func runPrintcal(
        config: PrintcalConfig,
        onLogBatch: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> URL {
        let args = try PrintcalArgs.build(config: config)
        let cwd = PathSecurity.resolveSafeCwd(config.workingDirectory)
        let binaryURL = binaryResolver.resolve("printcal")
        let calBasename = CalibrationIdentity.prefix(config.ti3Basename)
        let processId = ProcessID.printcal(calBasename)

        await ensureNotRunning(id: processId)
        let result = try await processManager.runCaptured(
            id: processId,
            binary: binaryURL,
            arguments: args,
            workingDirectory: cwd
        )

        if let onLogBatch = onLogBatch, !result.stdout.isEmpty {
            onLogBatch(result.stdout.components(separatedBy: .newlines))
        }

        guard result.exitCode == 0 else {
            throw ArgyllRunnerError.toolFailed(
                tool: "printcal",
                code: result.exitCode,
                logs: [result.stderr.isEmpty
                    ? "printcal exited with code \(result.exitCode)"
                    : result.stderr]
            )
        }

        let calURL = config.outputURL
        guard FileManager.default.fileExists(atPath: calURL.path) else {
            throw ArgyllRunnerError.missingArtefact(calURL.path)
        }
        return calURL
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
