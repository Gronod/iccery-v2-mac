import Foundation

/// Errors from CUPS tool invocations.
public enum CupsError: LocalizedError, Equatable {
    case toolFailed(tool: String, code: Int32, stderr: String)
    case tiffMissing(String)

    public var errorDescription: String? {
        switch self {
        case .toolFailed(let tool, let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(tool) failed with exit code \(code)"
                : "\(tool) failed (\(code)): \(detail)"
        case .tiffMissing(let path):
            return "Target TIFF does not exist: \(path)"
        }
    }
}

/// CUPS command surface (issue 12): enumerates queues and reads
/// per-queue capabilities via `/usr/bin/lpstat` and
/// `/usr/bin/lpoptions`. Spawning goes through
/// `ProcessManager.runCaptured` so spawns are logged, get killAll
/// coverage, and share the dup-id discipline; `binaryDir`/`ppdDir` are
/// injectable so tests use fixture scripts and never touch real CUPS.
public struct CupsService: Sendable {
    public let processManager: ProcessManager
    /// Directory containing `lpstat`/`lpoptions`/`lp` — `/usr/bin` in
    /// production, a fixture dir under test.
    public let binaryDir: URL
    /// `/etc/cups/ppd` in production.
    public let ppdDir: URL

    public init(
        processManager: ProcessManager = .shared,
        binaryDir: URL = URL(fileURLWithPath: "/usr/bin"),
        ppdDir: URL = URL(fileURLWithPath: "/etc/cups/ppd")
    ) {
        self.processManager = processManager
        self.binaryDir = binaryDir
        self.ppdDir = ppdDir
    }

    // MARK: - Enumeration (lpstat -e/-p/-d)

    /// All CUPS destinations with status and default flag. An empty
    /// list is a valid result, not an error.
    public func listPrinters() async throws -> [Printer] {
        // lpstat exits non-zero when no destinations exist — an empty
        // queue list is a valid result, not a failure (issue 12).
        let destinationsOut = try await run(
            "lpstat", ["-e"], id: ProcessID.lpstat("e"), tolerateFailure: true)
        let statusOut = try await run(
            "lpstat", ["-p"], id: ProcessID.lpstat("p"), tolerateFailure: true)
        let defaultOut = try await run(
            "lpstat", ["-d"], id: ProcessID.lpstat("d"), tolerateFailure: true)

        let names = CupsParsers.lpstatDestinations(destinationsOut.stdout)
        let statuses = CupsParsers.lpstatStatuses(statusOut.stdout)
        let defaultName = CupsParsers.lpstatDefault(defaultOut.stdout)

        var printers: [Printer] = []
        for name in names {
            let displayName = try? await displayName(for: name)
            printers.append(Printer(
                name: name,
                status: statuses[name] ?? .unknown,
                isDefault: name == defaultName,
                displayName: displayName
            ))
        }
        return printers
    }

    /// `lpoptions -p <queue>` → `printer-info` (the NSPrinter fallback
    /// display name, docs/11 §binding).
    public func displayName(for queue: String) async throws -> String? {
        let result = try await run(
            "lpoptions", ["-p", queue], id: ProcessID.lpoptions(queue))
        return CupsParsers.lpoptionsDisplayName(result.stdout)
    }

    // MARK: - Capabilities (lpoptions -l + PPD)

    /// Raw `Key/Label: choices` listings for a queue — also the input
    /// to media-key and colour-bypass detection (docs/11 layer ④).
    public func optionListings(for queue: String) async throws -> [CupsOptionListing] {
        let result = try await run(
            "lpoptions", ["-p", queue, "-l"], id: ProcessID.lpoptions("\(queue)-l"))
        return CupsParsers.lpoptionsList(result.stdout)
    }

    /// Trays / paper sizes / media types for a queue, with PPD
    /// `*Key id/Human:` enrichment when the queue's PPD is readable.
    public func capabilities(for queue: String) async throws -> PrinterCapabilities {
        let listings = try await optionListings(for: queue)
        return capabilities(from: listings, ppd: loadPPD(for: queue))
    }

    /// Pure mapping — extracted so fixture tests need no process.
    public func capabilities(
        from listings: [CupsOptionListing],
        ppd: String?
    ) -> PrinterCapabilities {
        var trays: [PrinterTray] = []
        var sizes: [PrinterPaperSize] = []
        var media: [PrinterMediaType] = []

        for listing in listings {
            switch listing.key {
            case "InputSlot", "MediaSource":
                trays = listing.choices.enumerated().map {
                    PrinterTray(id: $0.offset + 1, name: $0.element)
                }
            case "PageSize", "MediaSize":
                sizes = listing.choices.enumerated().map {
                    PrinterPaperSize(id: $0.offset + 1, name: $0.element)
                }
            case let key where CupsParsers.mediaTypeKeys.contains(key):
                guard media.isEmpty else { continue }
                let labels = ppd.map {
                    CupsParsers.ppdChoiceLabels($0, key: key)
                } ?? [:]
                media = listing.choices.map {
                    PrinterMediaType(id: $0, name: labels[$0] ?? $0)
                }
            default:
                continue
            }
        }
        return PrinterCapabilities(
            trays: trays, paperSizes: sizes, mediaTypes: media)
    }

    /// The set of option keys a queue advertises — input to
    /// `detectDriverColorBypass` / `detectMediaTypeKey`.
    public func optionKeys(for queue: String) async throws -> Set<String> {
        Set(try await optionListings(for: queue).map(\.key))
    }

    // MARK: - PPD

    private func loadPPD(for queue: String) -> String? {
        let url = ppdDir.appendingPathComponent("\(queue).ppd")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Spawn

    @discardableResult
    func run(
        _ tool: String,
        _ arguments: [String],
        id: String,
        tolerateFailure: Bool = false
    ) async throws -> CapturedResult {
        let binary = binaryDir.appendingPathComponent(tool)
        let result = try await processManager.runCaptured(
            id: id, binary: binary, arguments: arguments)
        if result.exitCode != 0, !tolerateFailure {
            throw CupsError.toolFailed(
                tool: tool, code: result.exitCode, stderr: result.stderr)
        }
        return result
    }
}
