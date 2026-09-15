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
/// opens (#183). This phase consumes `paperSize` + `qualityKey`/
/// `quality` only; `mediaType` and `orientation` preselect — and the
/// `PMPageFormat`/`PMPaper` half of paper — are #186's scope.
struct PrintPanelInitialSelections {
    /// CUPS `PageSize` token, e.g. `"A4"` / `"Custom.595x842"`.
    var paperSize: String?
    /// The queue's detected quality enumeration key, e.g. `EPIJ_Qual`.
    var qualityKey: String?
    /// The selected quality token.
    var quality: String?
    var mediaType: String?      // #186 consumes
    var orientation: String?    // #186 consumes
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
            // ColorSync suppression ②–⑤ (locked write order, #183).
            applyInitialSelections(initialSelections, to: settings)
            boundViaPM = true
        } else {
            // Fallback: NSPrinter by display name (docs/11 §binding).
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

    /// Initial-selection `PMPrintSettings` writes — paper size and
    /// quality only this phase; media type / orientation and the
    /// `PMPageFormat`/`PMPaper` paper half are #186's contract.
    private func applyInitialSelections(
        _ selections: PrintPanelInitialSelections,
        to settings: PMPrintSettings
    ) {
        if let paperSize = selections.paperSize {
            _ = PMPrintSettingsSetValue(
                settings, "PageSize" as CFString,
                paperSize as CFString, false)
        }
        if let key = selections.qualityKey, let value = selections.quality {
            _ = PMPrintSettingsSetValue(
                settings, key as CFString, value as CFString, false)
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
