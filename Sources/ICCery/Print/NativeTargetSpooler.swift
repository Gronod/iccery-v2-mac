import AppKit
import ApplicationServices
import ICCeryCore

/// One page to draw — the TIFF plus its printtarg manifest size for
/// the drift check (#201 D9).
struct TargetPrintPage: Equatable {
    let url: URL
    let expectedWidthMm: Double?
    let expectedHeightMm: Double?
}

/// One spool job — a single-element `pages` in per-page mode, all
/// pages when `singleJobForAllPages` is on (#201 D5).
struct TargetPrintRequest {
    let queue: String
    let displayName: String?
    let pages: [TargetPrintPage]
    let jobTitle: String              // "ICCery Target - <basename>"
    /// nil → bind + PM defaults + suppression only (the ticket carries
    /// the captured PDE state; without it the job is Stage 2 writes
    /// over queue defaults).
    let ticket: PrintTicket?
    let overrides: TargetPrintOverrides
    /// The queue's `lpoptions -l` key roster — feeds vendor media-key
    /// and driver-bypass detection.
    let optionKeys: Set<String>
    /// Test-only: `.save` to this URL instead of `.spool` (#201 D8).
    var savePDFTo: URL?
}

enum TargetSpoolError: LocalizedError, Equatable {
    case noPages
    case printerUnresolved(queue: String)
    case operationFailed(queue: String, jobTitle: String)

    var errorDescription: String? {
        switch self {
        case .noPages:
            return "Nothing to print."
        case .printerUnresolved(let queue):
            return "The print queue '\(queue)' could not be resolved."
        case .operationFailed(_, let jobTitle):
            return "The print operation for '\(jobTitle)' failed."
        }
    }
}

@MainActor
protocol TargetSpooling {
    /// Warn-only diagnostics (manifest drift, oversize page, rejected
    /// key) are delivered here; the throw path is reserved for real
    /// failures.
    var diagnostics: ((Notice) -> Void)? { get set }
    func spool(_ request: TargetPrintRequest) throws
}

/// Production spooler — rehydrates the captured ticket, applies the
/// resolved Stage 2 writes, and draws each TIFF 1:1 through a silent
/// `NSPrintOperation` (#201, the S1–S14 trace in the M12 megaplan).
@MainActor
final class NativeTargetSpooler: TargetSpooling {
    var suppressor = ColorSyncSuppressor()
    var diagnostics: ((Notice) -> Void)?
    var log: (LogLevel, String) -> Void = { AppLogger.shared.log($0, $1) }

    func spool(_ request: TargetPrintRequest) throws {
        guard !request.pages.isEmpty else { throw TargetSpoolError.noPages }

        // The PM printer handle is held for the whole operation and
        // released on every path (S14).
        let printer = PMTicketBridge.makePrinter(queue: request.queue)
        defer { if let printer { PMTicketBridge.release(printer) } }

        let (printInfo, _) = try makePrintInfo(for: request, boundTo: printer)

        // S10 — decode every page 1:1. Warn-only findings ride the
        // `diagnostics` seam, never the throw path (D9).
        var rasters: [TargetPageRaster] = []
        rasters.reserveCapacity(request.pages.count)
        for page in request.pages {
            let raster = try TargetRasterLoader.load(
                tiff: page.url,
                expectedWidthMm: page.expectedWidthMm,
                expectedHeightMm: page.expectedHeightMm)
            if let drift = raster.manifestDrift {
                diagnostics?(Notice(kind: .warning, text: drift))
            }
            if raster.pointSize.width > printInfo.paperSize.width + 0.5
                || raster.pointSize.height
                    > printInfo.paperSize.height + 0.5 {
                diagnostics?(Notice(
                    kind: .warning,
                    text: "\(page.url.lastPathComponent) exceeds the "
                        + "paper size — it will be clipped, not scaled."))
            }
            rasters.append(raster)
        }

        // S11–S13 — headless canvas + silent operation (D7).
        let canvas = TargetPageCanvasView(
            pages: rasters, paperSize: printInfo.paperSize)
        let operation = NSPrintOperation(view: canvas, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.canSpawnSeparateThread = false
        operation.jobTitle = request.jobTitle
        guard operation.run() else {
            throw TargetSpoolError.operationFailed(
                queue: request.queue, jobTitle: request.jobTitle)
        }
    }

    /// S1–S9 — a fully configured `NSPrintInfo` plus the resolved
    /// write list. Extracted for the PDF harness + unit tests;
    /// `spool(_:)` is the production entry point (it keeps the PM
    /// printer handle alive through `run()`).
    func makePrintInfo(
        for request: TargetPrintRequest
    ) throws -> (NSPrintInfo, ResolvedTicketWrites) {
        let printer = PMTicketBridge.makePrinter(queue: request.queue)
        defer { if let printer { PMTicketBridge.release(printer) } }
        return try makePrintInfo(for: request, boundTo: printer)
    }

    private func makePrintInfo(
        for request: TargetPrintRequest,
        boundTo printer: PMPrinter?
    ) throws -> (NSPrintInfo, ResolvedTicketWrites) {
        // S1
        let printInfo = NSPrintInfo()

        // S2 — Cocoa-level printer first: it runs before binding and
        // ticket restore, so a printer-driven settings reset cannot
        // clobber the ticket (R9). Best effort; PM binding is
        // authoritative.
        var resolvedNSPrinter = false
        if let nsPrinter = NSPrinter(name: request.queue)
            ?? request.displayName.flatMap({ NSPrinter(name: $0) }) {
            printInfo.printer = nsPrinter
            resolvedNSPrinter = true
        }

        // S3 — PM binding + session defaults. A failed bind degrades
        // to the NSPrinter fallback; with neither, the job would land
        // on the default queue — a wrong answer, so it throws.
        var boundViaPM = false
        if let printer {
            do {
                try PMTicketBridge.bind(printer: printer, to: printInfo)
                boundViaPM = true
            } catch {
                log(.warn, "Spool: PM bind failed for "
                    + "'\(request.queue)' — continuing on the "
                    + "NSPrinter fallback")
            }
        }
        guard boundViaPM || resolvedNSPrinter else {
            throw TargetSpoolError.printerUnresolved(queue: request.queue)
        }

        // S4 — rehydrate the captured ticket. `restore` itself refuses
        // a cross-queue replay (R3).
        if let ticket = request.ticket {
            try PMTicketBridge.restore(ticket, into: printInfo)
        }

        // S5 — Stage 2 writes (AP_* + Quartz vocabularies + media /
        // quality / bypass, D2/D6) onto the live PMPrintSettings.
        let resolved = TicketWriteResolver.resolve(
            overrides: request.overrides, optionKeys: request.optionKeys)
        let settings = PMTicketBridge.settings(printInfo)
        for write in resolved.writes {
            // R4 — write only when the value differs, and log old→new
            // so a vendor companion-key desync is diagnosable.
            let current = PMTicketBridge.stringValue(
                forKey: write.key, in: settings)
            guard current != write.value else { continue }
            if let current {
                log(.info, "Spool: \(write.key): '\(current)' "
                    + "→ '\(write.value)'")
            }
            PMTicketBridge.setValue(
                write.value, forKey: write.key, locked: write.locked,
                in: settings, context: "Spool")
        }
        printInfo.updateFromPMPrintSettings()
        mirror(resolved.writes, into: printInfo)

        // S6 — paper override: `PMPaper` match on the bound printer;
        // `Custom.<w>x<h>` tokens (already points) set the Cocoa paper
        // size directly.
        if let token = resolved.paperToken {
            if let printer, boundViaPM {
                PMTicketBridge.applyPaper(
                    token: token, printer: printer,
                    session: PMTicketBridge.session(printInfo),
                    printInfo: printInfo)
            } else if let custom = PMTicketBridge
                .customPaperDimensions(from: token) {
                printInfo.paperSize = NSSize(
                    width: custom.width, height: custom.height)
            }
        }

        // S7 — orientation on the Cocoa page format; the
        // `orientation-requested` write above is the driver half.
        if let orientation = resolved.orientation {
            printInfo.orientation = orientation == "landscape"
                ? .landscape : .portrait
        }

        // S8 — private SPI on the live session; only meaningful with
        // a bound printer (same constraint as the panel path).
        if boundViaPM {
            suppressor.applySPIMode(to: PMTicketBridge.session(printInfo))
        }

        // S9 — Cocoa geometry: margins 0, `.clip` pagination, 1:1
        // scale, no centring; `.spool`, or `.save` + jobSavingURL
        // under the PDF harness (D8/D9).
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .clip
        printInfo.verticalPagination = .clip
        printInfo.scalingFactor = 1.0
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        if let saveURL = request.savePDFTo {
            printInfo.jobDisposition = .save
            printInfo.dictionary()[
                NSPrintInfo.AttributeKey.jobSavingURL] = saveURL
        } else {
            printInfo.jobDisposition = .spool
        }

        return (printInfo, resolved)
    }

    /// The resolved writes also land in `NSPrintInfo.printSettings` so
    /// the driver sees them through Cocoa — the
    /// `com.apple.print.printSettings` sub-dictionary carries the
    /// colour keys (D2 / docs/14 §7).
    private func mirror(
        _ writes: [TicketWrite], into printInfo: NSPrintInfo
    ) {
        let settings = printInfo.printSettings
        for write in writes {
            settings[write.key as NSString] = write.value as NSString
        }
        let nestedKey = ColorMatchingAttempts.quartzNestedDictKey as NSString
        let nested = (settings[nestedKey] as? NSMutableDictionary)
            ?? NSMutableDictionary()
        for write in writes where Self.isColourKey(write.key) {
            nested[write.key] = write.value
        }
        settings[nestedKey] = nested
    }

    private static func isColourKey(_ key: String) -> Bool {
        ColorMatchingAttempts.printSettingsKeys.contains(key)
            || key == ColorMatchingAttempts.quartzModeKey
            || key == ColorMatchingAttempts.quartzProfileKey
            || key == ColorMatchingAttempts.quartzLegacyModeKey
    }
}

#if DEBUG
/// UI-test seam (#201 D8). Runs the same `TicketWriteResolver` the
/// native spooler runs, appends one deterministic line per request to
/// `ICCERY_TEST_SPOOL_LOG`, and never touches the print system — so
/// UI tests need no queue, no driver and no PM binding.
///
/// `ICCERY_TEST_SPOOL_FAIL=1` injects an `operationFailed` error for
/// the failure-notice tests.
@MainActor
final class RecordingTargetSpooler: TargetSpooling {
    let logURL: URL
    var diagnostics: ((Notice) -> Void)?

    init(logURL: URL) {
        self.logURL = logURL
    }

    /// `queue=<q> title=<t> page=<basename> pages=<n> paper=<token|->
    /// orientation=<o> keys=<k=v k=v …>` — keys sorted alphabetically
    /// so assertions are order-free.
    func spool(_ request: TargetPrintRequest) throws {
        guard !request.pages.isEmpty else { throw TargetSpoolError.noPages }
        if ProcessInfo.processInfo.environment["ICCERY_TEST_SPOOL_FAIL"]
            == "1" {
            throw TargetSpoolError.operationFailed(
                queue: request.queue, jobTitle: request.jobTitle)
        }
        let resolved = TicketWriteResolver.resolve(
            overrides: request.overrides, optionKeys: request.optionKeys)
        let keys = resolved.writes
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let line = "queue=\(request.queue)"
            + " title=\(request.jobTitle)"
            + " page=\(request.pages[0].url.lastPathComponent)"
            + " pages=\(request.pages.count)"
            + " paper=\(resolved.paperToken ?? "-")"
            + " orientation=\(resolved.orientation ?? "-")"
            + " keys=\(keys)\n"
        // Atomic append — existing content + one line via the
        // `.tmp`-then-rename convention (#213).
        let existing = (try? String(contentsOf: logURL, encoding: .utf8))
            ?? ""
        try AtomicFileWriter.write(existing + line, to: logURL)
    }
}
#endif
