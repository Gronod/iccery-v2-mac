import Foundation
import ICCeryCore

/// A captured native print ticket (#201) — the payload `lp -o` could
/// never carry. Vendor PDE state, including opaque binary blobs, is
/// preserved verbatim inside `printSettings`.
///
/// In-memory, session-only. Never written to `settings.json` or an
/// `.icceryproj` (a ticket is queue- and driver-version-specific).
struct PrintTicket: Equatable, Sendable {
    /// CUPS queue id this ticket was captured for. Replay onto any other
    /// queue is refused (R3).
    let queue: String
    /// `PMPrintSettingsCreateDataRepresentation(…, kPMDataFormatXMLDefault)`.
    let printSettings: Data
    /// `PMPageFormatCreateDataRepresentation(…, kPMDataFormatXMLDefault)`.
    let pageFormat: Data
    /// Binary-plist snapshot of `NSPrintInfo.dictionary()`, plist-filtered.
    /// Cocoa-level fallback only — never the primary restore path.
    let printInfoPlist: Data?
    let capturedAt: Date
}

/// App-level panel outcome: the ICCeryCore `PrintPropertiesResult`
/// (Stage 2 mirror values, #183/#186) **plus** the native ticket the
/// spooler replays (#201).
struct PanelCaptureResult {
    var properties: PrintPropertiesResult
    var ticket: PrintTicket?
}
