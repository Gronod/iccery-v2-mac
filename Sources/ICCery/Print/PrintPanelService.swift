import AppKit
import ApplicationServices
import ICCeryCore

/// Errors raised while preparing the bound print panel.
enum PrintPanelError: LocalizedError {
    case sessionBindingFailed(OSStatus)
    case noPrinterFound(String)

    var errorDescription: String? {
        switch self {
        case .sessionBindingFailed(let status):
            return "Could not bind the print session to the queue (OSStatus \(status))."
        case .noPrinterFound(let name):
            return "No printer found for '\(name)'."
        }
    }
}

/// Stage 2 selections pre-applied to the bound print panel before it
/// opens (#183/#186). Every write is warn-only — the panel still
/// opens when a driver ignores a key.
struct PrintPanelInitialSelections {
    /// CUPS `PageSize` token, e.g. `"A4"` / `"Custom.595x842"`. Written
    /// to `PMPrintSettings` **and** `PMPageFormat` (#186 E1).
    var paperSize: String?
    /// The queue's detected quality enumeration key, e.g. `EPIJ_Qual`.
    var qualityKey: String?
    /// The selected quality token.
    var quality: String?
    /// The selected media token — written to the queue's detected
    /// vendor key (`CNIJMediaType`/`EPIJ_Medi`/…) (#186).
    var mediaType: String?
    /// `"portrait"`/`"landscape"` → `orientation-requested` 3|4 (#186).
    var orientation: String?
}

/// Preferences → native `NSPrintPanel` bound to the selected CUPS
/// queue (issue 13, docs/11).
///
/// This is a **settings-capture** dialog — the default button is
/// "Use Settings", never "Print". It is never System Settings, the
/// CUPS web UI, or an `NSWorkspace` open (#188). Cancel returns `nil`
/// and is not an error.
///
/// Binding: `PMPrinterCreateFromPrinterID(CUPS queue id)` →
/// `PMSessionSetCurrentPMPrinter` → session default settings/page
/// format. `PMPrinter` is `PMRelease`d on every path. Fallback when PM
/// binding fails: `NSPrinter(name: displayName)` (the `printer-info`
/// label) → `printInfo.printer`.
@MainActor
struct PrintPanelService {

    /// The suppression engine — injectable for tests.
    var suppressor = ColorSyncSuppressor()

    /// Resolves the display name (off-panel `lpoptions` fetch) and runs
    /// the modal panel. Returns `nil` when the user cancels.
    func showProperties(
        queue: String,
        displayName: String?,
        cupsService: CupsService,
        initialSelections: PrintPanelInitialSelections =
            PrintPanelInitialSelections()
    ) async throws -> PrintPropertiesResult? {
        #if DEBUG
        if UITestHooks.printPanelStubbed {
            return UITestHooks.printPanelResult(forQueue: queue)
        }
        #endif
        // `??` rhs is a non-async @autoclosure — fetch first.
        let fetched = try? await cupsService.displayName(for: queue)
        let display = displayName ?? fetched
        // Layer ④ needs the queue's option keys (lpoptions -l) to pick
        // the driver colour-bypass before the panel opens.
        let optionKeys = (try? await cupsService.optionKeys(for: queue))
            ?? []
        return try runNativePanel(
            queue: queue, displayName: display, optionKeys: optionKeys,
            initialSelections: initialSelections)
    }

    // MARK: - Panel

    private func runNativePanel(
        queue: String,
        displayName: String?,
        optionKeys: Set<String>,
        initialSelections: PrintPanelInitialSelections
    ) throws -> PrintPropertiesResult? {
        let printInfo = NSPrintInfo()
        var pmPrinter: PMPrinter?
        var boundViaPM = false

        // ① Bind the session to the selected CUPS queue (docs/11).
        if let printer = PMPrinterCreateFromPrinterID(queue as CFString) {
            pmPrinter = printer
            let session = unsafeBitCast(
                printInfo.pmPrintSession(), to: PMPrintSession.self)
            let settings = unsafeBitCast(
                printInfo.pmPrintSettings(), to: PMPrintSettings.self)
            let pageFormat = unsafeBitCast(
                printInfo.pmPageFormat(), to: PMPageFormat.self)

            let status = PMSessionSetCurrentPMPrinter(session, printer)
            if status != 0 {
                PMRelease(Self.pmObject(printer))
                throw PrintPanelError.sessionBindingFailed(status)
            }
            // Warn-only: defaults keep the panel consistent with the
            // queue but are not fatal when they fail.
            _ = PMSessionDefaultPrintSettings(session, settings)
            _ = PMSessionDefaultPageFormat(session, pageFormat)
            // Initial selections — after `PMSessionDefault*`, before
            // ColorSync suppression ②–⑤ (locked write order,
            // #183/#186). Paper is TWO writes (E1): the `PageSize`
            // print-settings value drivers/capture read AND the
            // `PMPageFormat` paper the panel's dropdown reflects.
            applyInitialSelections(
                initialSelections, to: settings, optionKeys: optionKeys)
            if let paperToken = initialSelections.paperSize {
                applyPaperPageFormat(
                    paperToken, printer: printer, session: session,
                    printInfo: printInfo)
            }
            boundViaPM = true
        } else {
            // Fallback: NSPrinter by display name (docs/11 §binding).
            // Warn — the display name can resolve a *different* queue
            // (#186 E2: diagnosable, not a proven defect).
            AppLogger.shared.warn(
                "Print panel: PM binding unavailable for '\(queue)' — "
                    + "falling back to NSPrinter(displayName)")
            guard let displayName,
                  let nsPrinter = NSPrinter(name: displayName)
            else {
                throw PrintPanelError.noPrinterFound(
                    displayName ?? queue)
            }
            printInfo.printer = nsPrinter
            printInfo.setUpPrintOperationDefaultValues()
        }
        defer {
            if let printer = pmPrinter {
                PMRelease(Self.pmObject(printer))
            }
        }

        // ②–⑤ ColourSync suppression — only on the PM path: the SPI
        // and PMPrintSettingsSetValue need a session with a current
        // printer to attach to.
        var settings = unsafeBitCast(
            printInfo.pmPrintSettings(), to: PMPrintSettings.self)
        var driverBypass: (key: String, value: String)?
        if boundViaPM {
            let session = unsafeBitCast(
                printInfo.pmPrintSession(), to: PMPrintSession.self)
            suppressor.applySPIMode(to: session)                    // ②
            suppressor.applyLockedKeys(to: settings)                // ③
            driverBypass = suppressor.applyDriverBypass(            // ④
                to: settings, optionKeys: optionKeys)
            suppressor.mirror(into: printInfo, driverBypass: driverBypass) // ⑤
        }

        let panel = NSPrintPanel()
        panel.options = [
            .showsCopies, .showsPageRange, .showsPaperSize,
            .showsOrientation, .showsScaling, .showsPrintSelection,
            .showsPageSetupAccessory, .showsPreview,
        ]
        panel.setDefaultButtonTitle("Use Settings")

        let response = panel.runModal(with: printInfo)
        guard response == NSApplication.ModalResponse.OK.rawValue else {
            return nil
        }

        // ⑥ Capture the user's choices — filtered replay options plus
        // the media type they picked. Re-fetch the settings handle so
        // we read back what the modal wrote. Paper size, quality, and
        // orientation ride back parsed from the captured `k=v` string
        // (#183); the PDE may rewrite or drop them (R12).
        var cupsOptions: String?
        var mediaType: String?
        if boundViaPM {
            settings = unsafeBitCast(
                printInfo.pmPrintSettings(), to: PMPrintSettings.self)
            let captured = suppressor.captureOptions(from: settings)
            cupsOptions = captured.cupsOptions
            mediaType = captured.mediaType
        }
        let capturedOptions = cupsOptions ?? ""
        return PrintPropertiesResult(
            selectedPrinter: boundViaPM
                ? Self.currentPrinterID(
                    session: unsafeBitCast(
                        printInfo.pmPrintSession(), to: PMPrintSession.self),
                    fallback: queue)
                : nil,
            options: PrintOptions(
                orientation: CupsParsers.extractOrientation(
                    fromOptionsString: capturedOptions),
                paperSize: CupsParsers.extractOption(
                    named: "PageSize", fromOptionsString: capturedOptions),
                mediaType: mediaType,
                quality: CupsParsers.extractQuality(
                    fromOptionsString: capturedOptions),
                ppdUncorrectedPassthrough: true,
                cupsOptions: cupsOptions))
    }

    /// Initial-selection `PMPrintSettings` writes — paper, quality,
    /// media type, orientation. All warn-only: a driver that ignores
    /// a key must not keep the panel from opening (R12 surfaces via
    /// the capture echo instead).
    private func applyInitialSelections(
        _ selections: PrintPanelInitialSelections,
        to settings: PMPrintSettings,
        optionKeys: Set<String>
    ) {
        if let paperSize = selections.paperSize {
            warnOnFailure(PMPrintSettingsSetValue(
                settings, "PageSize" as CFString,
                paperSize as CFString, false), key: "PageSize")
        }
        if let key = selections.qualityKey, let value = selections.quality {
            warnOnFailure(PMPrintSettingsSetValue(
                settings, key as CFString,
                value as CFString, false), key: key)
        }
        // Media type via the queue's detected vendor key (#186).
        if let mediaType = selections.mediaType,
           let mediaKey = CupsParsers.detectMediaTypeKey(
               optionKeys: optionKeys) {
            warnOnFailure(PMPrintSettingsSetValue(
                settings, mediaKey as CFString,
                mediaType as CFString, false), key: mediaKey)
        }
        // Orientation — portrait=3, landscape=4 (CUPS IPP codes).
        if let orientation = selections.orientation {
            let code = orientation == "landscape" ? "4" : "3"
            warnOnFailure(PMPrintSettingsSetValue(
                settings, "orientation-requested" as CFString,
                code as CFString, false), key: "orientation-requested")
        }
    }

    /// The `PMPageFormat` half of paper preselect (#186 E1): the
    /// panel's paper dropdown reflects the page format's `PMPaper`,
    /// not `PMPrintSettings`. Match the Stage 2 `PageSize` token to a
    /// paper from `PMPrinterGetPaperList`, rebuild the page format
    /// around it, and copy it into the printInfo's format (TN2248:
    /// `PMCreatePageFormatWithPMPaper` → `PMSessionValidatePageFormat`
    /// → `PMCopyPageFormat` → `updateFromPMPageFormat`).
    /// `Custom.<w>x<h>` tokens (already points) have no `PMPaper` —
    /// set the Cocoa `paperSize` directly. Warn-only throughout: a
    /// missed match must not keep the panel from opening.
    private func applyPaperPageFormat(
        _ token: String,
        printer: PMPrinter,
        session: PMPrintSession,
        printInfo: NSPrintInfo
    ) {
        if let custom = Self.customPaperDimensions(from: token) {
            printInfo.paperSize = NSSize(
                width: custom.width, height: custom.height)
            return
        }
        var paperList: Unmanaged<CFArray>?
        guard PMPrinterGetPaperList(printer, &paperList) == 0,
              let papers = paperList?.takeUnretainedValue()
        else {
            AppLogger.shared.warn(
                "Print panel: PMPrinterGetPaperList failed — "
                    + "paper preselect skipped")
            return
        }
        // The list (and its elements) is owned by the printer —
        // borrowed, never released.
        var match: PMPaper?
        for index in 0..<CFArrayGetCount(papers) {
            let paper = unsafeBitCast(
                CFArrayGetValueAtIndex(papers, index), to: PMPaper.self)
            var idRef: Unmanaged<CFString>?
            guard PMPaperGetID(paper, &idRef) == 0,
                  let paperID = idRef?.takeUnretainedValue() as String?
            else { continue }
            if paperID == token {
                match = paper
                break
            }
        }
        guard let paper = match else {
            AppLogger.shared.warn(
                "Print panel: no PMPaper id matches '\(token)'")
            return
        }
        var created: PMPageFormat?
        guard PMCreatePageFormatWithPMPaper(&created, paper) == 0,
              let newFormat = created
        else {
            AppLogger.shared.warn(
                "Print panel: PMCreatePageFormatWithPMPaper failed "
                    + "for '\(token)'")
            return
        }
        defer { PMRelease(unsafeBitCast(newFormat, to: PMObject.self)) }
        _ = PMSessionValidatePageFormat(session, newFormat, nil)
        let destination = unsafeBitCast(
            printInfo.pmPageFormat(), to: PMPageFormat.self)
        _ = PMCopyPageFormat(newFormat, destination)
        printInfo.updateFromPMPageFormat()
    }

    /// `Custom.<w>x<h>` → dimensions in points (the token builder
    /// emits integer points, mm × 72/25.4). `nil` for non-custom or
    /// malformed tokens — a malformed `Custom.*` then misses the
    /// `PMPaper` match and logs instead of guessing a size.
    static func customPaperDimensions(
        from token: String
    ) -> (width: Double, height: Double)? {
        guard token.hasPrefix("Custom.") else { return nil }
        let dims = token.dropFirst("Custom.".count).split(separator: "x")
        guard dims.count == 2,
              let width = Double(dims[0]), let height = Double(dims[1]),
              width > 0, height > 0
        else { return nil }
        return (width, height)
    }

    private func warnOnFailure(_ status: OSStatus, key: String) {
        if status != 0 {
            AppLogger.shared.warn(
                "Print panel: PMPrintSettingsSetValue(\(key)) "
                    + "rejected (\(status))")
        }
    }

    // MARK: - PM helpers

    /// `PMPrinter` → `PMObject` for `PMRelease` — the Carbon API wants
    /// `UnsafeRawPointer`, Swift imports `PMPrinter` as `OpaquePointer`.
    static func pmObject(_ printer: PMPrinter) -> PMObject {
        unsafeBitCast(printer, to: PMObject.self)
    }

    /// `PMSessionGetCurrentPrinter` → `PMPrinterGetID` → String.
    private static func currentPrinterID(
        session: PMPrintSession,
        fallback: String
    ) -> String {
        var current: PMPrinter?
        guard PMSessionGetCurrentPrinter(session, &current) == 0,
              let printer = current
        else { return fallback }
        defer { PMRelease(pmObject(printer)) }
        guard let id = PMPrinterGetID(printer)
        else { return fallback }
        return id.takeUnretainedValue() as String
    }
}
