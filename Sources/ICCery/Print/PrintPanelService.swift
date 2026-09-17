import AppKit
import ApplicationServices
import ICCeryCore

/// Errors raised while preparing the bound print panel.
enum PrintPanelError: LocalizedError {
    case noPrinterFound(String)

    var errorDescription: String? {
        switch self {
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
    ) async throws -> PanelCaptureResult? {
        #if DEBUG
        if UITestHooks.printPanelStubbed {
            return UITestHooks.printPanelResult(forQueue: queue).map {
                PanelCaptureResult(properties: $0, ticket: nil)
            }
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
    ) throws -> PanelCaptureResult? {
        let printInfo = NSPrintInfo()
        var pmPrinter: PMPrinter?
        var boundViaPM = false

        // ① Bind the session to the selected CUPS queue (docs/11).
        if let printer = PMTicketBridge.makePrinter(queue: queue) {
            pmPrinter = printer
            let session = PMTicketBridge.session(printInfo)
            let settings = PMTicketBridge.settings(printInfo)

            do {
                try PMTicketBridge.bind(printer: printer, to: printInfo)
            } catch {
                PMTicketBridge.release(printer)
                throw error
            }
            // Initial selections — after `PMSessionDefault*`, before
            // ColorSync suppression ②–⑤ (locked write order,
            // #183/#186). Paper is TWO writes (E1): the `PageSize`
            // print-settings value drivers/capture read AND the
            // `PMPageFormat` paper the panel's dropdown reflects.
            applyInitialSelections(
                initialSelections, to: settings, optionKeys: optionKeys)
            if let paperToken = initialSelections.paperSize {
                PMTicketBridge.applyPaper(
                    token: paperToken, printer: printer,
                    session: session, printInfo: printInfo)
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
                PMTicketBridge.release(printer)
            }
        }

        // ②–⑤ ColourSync suppression — only on the PM path: the SPI
        // and PMPrintSettingsSetValue need a session with a current
        // printer to attach to.
        var settings = PMTicketBridge.settings(printInfo)
        var driverBypass: (key: String, value: String)?
        if boundViaPM {
            let session = PMTicketBridge.session(printInfo)
            suppressor.applySPIMode(to: session)                    // ②
            suppressor.applyLockedKeys(to: settings)                // ③
            suppressor.applyQuartzMode(to: settings)                // ⑤′-a (D2)
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
            settings = PMTicketBridge.settings(printInfo)
            let captured = suppressor.captureOptions(from: settings)
            cupsOptions = captured.cupsOptions
            mediaType = captured.mediaType
        }
        let capturedOptions = cupsOptions ?? ""
        let resolvedQueue = boundViaPM
            ? PMTicketBridge.currentPrinterID(
                session: PMTicketBridge.session(printInfo),
                fallback: queue)
            : queue
        // ⑦ Serialise the native ticket — the payload `lp -o` could
        // never carry (#201). Warn-only via `try?`: a serialise
        // failure must not lose the Stage 2 mirror above.
        let ticket = try? PMTicketBridge.serialise(
            printInfo, queue: resolvedQueue)
        return PanelCaptureResult(
            properties: PrintPropertiesResult(
                selectedPrinter: boundViaPM ? resolvedQueue : nil,
                options: PrintOptions(
                    orientation: CupsParsers.extractOrientation(
                        fromOptionsString: capturedOptions),
                    paperSize: CupsParsers.extractOption(
                        named: "PageSize",
                        fromOptionsString: capturedOptions),
                    mediaType: mediaType,
                    quality: CupsParsers.extractQuality(
                        fromOptionsString: capturedOptions),
                    ppdUncorrectedPassthrough: true,
                    cupsOptions: cupsOptions)),
            ticket: ticket)
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
            PMTicketBridge.setValue(
                paperSize, forKey: "PageSize", locked: false,
                in: settings, context: "Print panel")
        }
        if let key = selections.qualityKey, let value = selections.quality {
            PMTicketBridge.setValue(
                value, forKey: key, locked: false,
                in: settings, context: "Print panel")
        }
        // Media type via the queue's detected vendor key (#186).
        if let mediaType = selections.mediaType,
           let mediaKey = CupsParsers.detectMediaTypeKey(
               optionKeys: optionKeys) {
            PMTicketBridge.setValue(
                mediaType, forKey: mediaKey, locked: false,
                in: settings, context: "Print panel")
        }
        // Orientation — portrait=3, landscape=4 (CUPS IPP codes).
        if let orientation = selections.orientation {
            let code = orientation == "landscape" ? "4" : "3"
            PMTicketBridge.setValue(
                code, forKey: "orientation-requested", locked: false,
                in: settings, context: "Print panel")
        }
    }

}
