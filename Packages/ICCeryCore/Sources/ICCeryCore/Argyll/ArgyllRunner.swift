import Foundation

/// Errors from `ArgyllRunner` executions.
public enum ArgyllRunnerError: LocalizedError, Equatable {
    case processFailed(code: Int32, logs: [String])
    case missingArtefact(String)
    case malformedManifest(String)

    public var errorDescription: String? {
        switch self {
        case .processFailed(let code, _):
            return "Process exited with code \(code)"
        case .missingArtefact(let path):
            return "Expected output file was not created: \(path)"
        case .malformedManifest(let reason):
            return "Failed to parse printtarg manifest: \(reason)"
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
}
