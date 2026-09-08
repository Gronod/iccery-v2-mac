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
        cupsService: CupsService
    ) async throws -> PrintPropertiesResult? {
        #if DEBUG
        if UITestHooks.printPanelStubbed {
            return UITestHooks.printPanelResult(forQueue: queue)
        }
        #endif
        let display = displayName
            ?? (try? await cupsService.displayName(for: queue))
        // Layer ④ needs the queue's option keys (lpoptions -l) to pick
        // the driver colour-bypass before the panel opens.
        let optionKeys = (try? await cupsService.optionKeys(for: queue))
            ?? []
        return try runNativePanel(
            queue: queue, displayName: display, optionKeys: optionKeys)
    }

    // MARK: - Panel

    private func runNativePanel(
        queue: String,
        displayName: String?,
        optionKeys: Set<String>
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
                PMRelease(pmObject(printer))
                throw PrintPanelError.sessionBindingFailed(status)
            }
            // Warn-only: defaults keep the panel consistent with the
            // queue but are not fatal when they fail.
            _ = PMSessionDefaultPrintSettings(session, settings)
            _ = PMSessionDefaultPageFormat(session, pageFormat)
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
                PMRelease(pmObject(printer))
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
        panel.defaultButtonTitle = "Use Settings"

        let response = panel.runModal(with: printInfo)
        guard response == NSApplication.ModalResponse.OK.rawValue else {
            return nil
        }

        // ⑥ Capture the user's choices — filtered replay options plus
        // the media type they picked. Re-fetch the settings handle so
        // we read back what the modal wrote.
        var cupsOptions: String?
        var mediaType: String?
        if boundViaPM {
            settings = unsafeBitCast(
                printInfo.pmPrintSettings(), to: PMPrintSettings.self)
            let captured = suppressor.captureOptions(from: settings)
            cupsOptions = captured.cupsOptions
            mediaType = captured.mediaType
        }
        return PrintPropertiesResult(
            selectedPrinter: boundViaPM
                ? Self.currentPrinterID(
                    session: unsafeBitCast(
                        printInfo.pmPrintSession(), to: PMPrintSession.self),
                    fallback: queue)
                : nil,
            options: PrintOptions(
                mediaType: mediaType,
                ppdUncorrectedPassthrough: true,
                cupsOptions: cupsOptions))
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
