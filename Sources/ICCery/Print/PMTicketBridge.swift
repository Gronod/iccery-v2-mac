import AppKit
import ApplicationServices
import ICCeryCore

/// Errors raised by Core Printing bridge operations.
enum PMTicketError: LocalizedError, Equatable {
    case printerUnknown(queue: String)
    case sessionBindingFailed(OSStatus)
    case serialiseFailed(stage: String, status: OSStatus)
    case restoreFailed(stage: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .printerUnknown(let queue):
            return "No printer found for queue '\(queue)'."
        case .sessionBindingFailed(let status):
            return "Could not bind the print session to the queue (OSStatus \(status))."
        case .serialiseFailed(let stage, let status):
            return "Print ticket capture failed at \(stage) (OSStatus \(status))."
        case .restoreFailed(let stage, let status):
            return "Print ticket restore failed at \(stage) (OSStatus \(status))."
        }
    }
}

/// Every Core Printing (`PM*`) call in ICCery lives here (#201 D12).
///
/// Ownership — the ONLY rules, do not improvise:
/// * `PMPrinterCreateFromPrinterID`, `PMCreatePageFormatWithPMPaper`,
///   `PMPrintSettingsCreateWithDataRepresentation`,
///   `PMPageFormatCreateWithDataRepresentation` return **+1** →
///   `PMRelease(object(_:))` on every path (`defer`).
/// * `PM*CreateDataRepresentation` writes a **+1 CFData** →
///   `takeRetainedValue()` (the headers say "the caller is responsible
///   for releasing"; the out-param is not `CF_RETURNS_RETAINED`-annotated,
///   so Swift hands back an unbalanced `Unmanaged`).
/// * `PMPrinterGetPaperList`, `PMPaperGetID`, `PMPrinterGetID`,
///   `PMPrintSettingsGetValue` are **borrowed** → `takeUnretainedValue()`,
///   never released. `PMSessionGetCurrentPrinter` hands back the
///   session's own printer — also borrowed, never `PMRelease`d (an
///   over-release here dangles the session and crashes AppKit's
///   `_printerInPrintSession` / session teardown).
/// * `printInfo.pmPrintSession()/pmPrintSettings()/pmPageFormat()` are
///   borrowed from the `NSPrintInfo` → never released.
@MainActor
enum PMTicketBridge {

    // MARK: Handles

    /// Borrowed `PMPrintSession` from the `NSPrintInfo` — never released.
    static func session(_ printInfo: NSPrintInfo) -> PMPrintSession {
        unsafeBitCast(printInfo.pmPrintSession(), to: PMPrintSession.self)
    }

    /// Borrowed `PMPrintSettings` from the `NSPrintInfo` — never released.
    static func settings(_ printInfo: NSPrintInfo) -> PMPrintSettings {
        unsafeBitCast(printInfo.pmPrintSettings(), to: PMPrintSettings.self)
    }

    /// Borrowed `PMPageFormat` from the `NSPrintInfo` — never released.
    static func pageFormat(_ printInfo: NSPrintInfo) -> PMPageFormat {
        unsafeBitCast(printInfo.pmPageFormat(), to: PMPageFormat.self)
    }

    /// Any `PM*` handle → `PMObject` for `PMRelease` — the Carbon API
    /// wants `UnsafeRawPointer`, Swift imports handles as `OpaquePointer`.
    static func object<Handle>(_ handle: Handle) -> PMObject {
        unsafeBitCast(handle, to: PMObject.self)
    }

    // MARK: Binding  (layer ①)

    /// `PMPrinterCreateFromPrinterID` — **+1**, caller must
    /// `PMTicketBridge.release` on every path.
    static func makePrinter(queue: String) -> PMPrinter? {
        PMPrinterCreateFromPrinterID(queue as CFString)
    }

    /// Balances `makePrinter(queue:)` / any +1 PM handle.
    static func release(_ printer: PMPrinter) {
        PMRelease(object(printer))
    }

    /// `PMSessionSetCurrentPMPrinter` + session defaults (warn-only).
    /// Throws `PMTicketError.sessionBindingFailed` when the bind itself
    /// fails — the caller still owns `printer` on every path.
    static func bind(printer: PMPrinter, to printInfo: NSPrintInfo) throws {
        let session = session(printInfo)
        let status = PMSessionSetCurrentPMPrinter(session, printer)
        guard status == 0 else {
            throw PMTicketError.sessionBindingFailed(status)
        }
        // Warn-only: defaults keep the panel consistent with the
        // queue but are not fatal when they fail.
        _ = PMSessionDefaultPrintSettings(session, settings(printInfo))
        _ = PMSessionDefaultPageFormat(session, pageFormat(printInfo))
    }

    /// `PMSessionGetCurrentPrinter` → `PMPrinterGetID` → String.
    static func currentPrinterID(
        session: PMPrintSession,
        fallback: String
    ) -> String {
        var current: PMPrinter?
        guard PMSessionGetCurrentPrinter(session, &current) == 0,
              let printer = current
        else { return fallback }
        // Borrowed from the session — never released (see header doc).
        guard let id = PMPrinterGetID(printer)
        else { return fallback }
        return id.takeUnretainedValue() as String
    }

    // MARK: Ticket  (#201 D3)

    /// Capture the live `PMPrintSettings` + `PMPageFormat` as XML
    /// `Data` plus a plist-safe `NSPrintInfo.dictionary()` fallback.
    /// The CFData out-params are **+1** by header contract
    /// ("the caller is responsible for releasing") →
    /// `takeRetainedValue()`.
    static func serialise(
        _ printInfo: NSPrintInfo,
        queue: String
    ) throws -> PrintTicket {
        var settingsRef: Unmanaged<CFData>?
        let settingsStatus = PMPrintSettingsCreateDataRepresentation(
            settings(printInfo), &settingsRef, kPMDataFormatXMLDefault)
        guard settingsStatus == noErr, let settingsRef else {
            throw PMTicketError.serialiseFailed(
                stage: "printSettings", status: settingsStatus)
        }
        let settingsData = settingsRef.takeRetainedValue() as Data

        var pageFormatRef: Unmanaged<CFData>?
        let pageFormatStatus = PMPageFormatCreateDataRepresentation(
            pageFormat(printInfo), &pageFormatRef, kPMDataFormatXMLDefault)
        guard pageFormatStatus == noErr, let pageFormatRef else {
            throw PMTicketError.serialiseFailed(
                stage: "pageFormat", status: pageFormatStatus)
        }
        let pageFormatData = pageFormatRef.takeRetainedValue() as Data

        // Cocoa-level fallback — warn-only, never fatal: filter the
        // dictionary to plist-safe values so one exotic attribute
        // cannot fail the whole snapshot.
        let plist = try? PropertyListSerialization.data(
            fromPropertyList: plistSafe(printInfo.dictionary()) ?? [:],
            format: .binary, options: 0)

        return PrintTicket(
            queue: queue,
            printSettings: settingsData,
            pageFormat: pageFormatData,
            printInfoPlist: plist,
            capturedAt: Date())
    }

    /// Rehydrate a ticket into `printInfo`'s live PM objects. Order is
    /// load-bearing: create → copy → session-validate → Cocoa update.
    /// Cross-queue replay is refused (R3) — the destination's bound
    /// queue is the session's current printer; a destination with no
    /// bound printer accepts the ticket (the spooler always binds
    /// first, so production replay is always guarded).
    /// A page-format failure is warn-only — paper is re-derived
    /// upstream by the spooler's S6/S7.
    static func restore(
        _ ticket: PrintTicket,
        into printInfo: NSPrintInfo
    ) throws {
        let bound = currentPrinterID(
            session: session(printInfo),
            fallback: ticket.queue)
        guard ticket.queue == bound else {
            AppLogger.shared.warn(
                "PrintTicket: refusing to replay a ticket captured "
                    + "for '\(ticket.queue)' onto '\(bound)'")
            return
        }

        var srcSettings: PMPrintSettings?
        let createStatus = PMPrintSettingsCreateWithDataRepresentation(
            ticket.printSettings as CFData, &srcSettings)
        defer {
            if let srcSettings { PMRelease(object(srcSettings)) }
        }
        guard createStatus == noErr, let srcSettings else {
            throw PMTicketError.restoreFailed(
                stage: "printSettings", status: createStatus)
        }
        let copyStatus = PMCopyPrintSettings(
            srcSettings, settings(printInfo))
        guard copyStatus == noErr else {
            throw PMTicketError.restoreFailed(
                stage: "printSettings", status: copyStatus)
        }
        var changed = DarwinBoolean(false)
        _ = PMSessionValidatePrintSettings(
            session(printInfo), settings(printInfo), &changed)
        if changed.boolValue {
            AppLogger.shared.info(
                "PrintTicket: driver adjusted the restored ticket")
        }
        printInfo.updateFromPMPrintSettings()

        // Page format — warn-only.
        var srcFormat: PMPageFormat?
        let formatStatus = PMPageFormatCreateWithDataRepresentation(
            ticket.pageFormat as CFData, &srcFormat)
        defer {
            if let srcFormat { PMRelease(object(srcFormat)) }
        }
        guard formatStatus == noErr, let srcFormat else {
            AppLogger.shared.warn(
                "PrintTicket: page format restore failed "
                    + "(\(formatStatus)) — paper re-derived upstream")
            return
        }
        guard PMCopyPageFormat(srcFormat, pageFormat(printInfo)) == noErr
        else {
            AppLogger.shared.warn(
                "PrintTicket: page format copy failed — "
                    + "paper re-derived upstream")
            return
        }
        var formatChanged = DarwinBoolean(false)
        _ = PMSessionValidatePageFormat(
            session(printInfo), pageFormat(printInfo), &formatChanged)
        printInfo.updateFromPMPageFormat()
    }

    /// Recursive plist-safety filter for `NSPrintInfo.dictionary()`:
    /// keeps String / NSNumber / Bool / Date / Data / URL (→
    /// absoluteString) / Array / Dictionary, drops everything else, so
    /// one non-plist attribute cannot fail the whole snapshot.
    private static func plistSafe(_ value: Any) -> Any? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let date as Date:
            return date
        case let data as Data:
            return data
        case let url as URL:
            return url.absoluteString
        case let array as [Any]:
            return array.compactMap(plistSafe)
        case let dictionary as [String: Any]:
            var safe: [String: Any] = [:]
            for (key, element) in dictionary {
                if let filtered = plistSafe(element) {
                    safe[key] = filtered
                }
            }
            return safe
        case let dictionary as [NSPrintInfo.AttributeKey: Any]:
            var safe: [String: Any] = [:]
            for (key, element) in dictionary {
                if let filtered = plistSafe(element) {
                    safe[key.rawValue] = filtered
                }
            }
            return safe
        default:
            return nil
        }
    }

    // MARK: Values

    /// Warn-only `PMPrintSettingsSetValue`: a driver that rejects a key
    /// must not abort the caller's flow. Returns `true` on success.
    @discardableResult
    static func setValue(
        _ value: String,
        forKey key: String,
        locked: Bool,
        in settings: PMPrintSettings,
        context: String
    ) -> Bool {
        let status = PMPrintSettingsSetValue(
            settings, key as CFString, value as CFString, locked)
        if status != 0 {
            AppLogger.shared.warn(
                "\(context): PMPrintSettingsSetValue(\(key)) "
                    + "rejected (\(status))")
            return false
        }
        return true
    }

    /// `PMPrintSettingsGetValue` — borrowed value, never released.
    /// `nil` for absent keys, non-string values, or lookup errors.
    static func stringValue(
        forKey key: String,
        in settings: PMPrintSettings
    ) -> String? {
        var value: Unmanaged<CFTypeRef>?
        guard PMPrintSettingsGetValue(
            settings, key as CFString, &value) == 0,
              let ref = value?.takeUnretainedValue()
        else { return nil }
        return ref as? String
    }

    // MARK: Paper

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
    static func applyPaper(
        token: String,
        printer: PMPrinter,
        session: PMPrintSession,
        printInfo: NSPrintInfo
    ) {
        if let custom = customPaperDimensions(from: token) {
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
        defer { PMRelease(object(newFormat)) }
        _ = PMSessionValidatePageFormat(session, newFormat, nil)
        _ = PMCopyPageFormat(newFormat, pageFormat(printInfo))
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
}
