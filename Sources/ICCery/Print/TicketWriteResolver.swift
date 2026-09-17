import Foundation
import ICCeryCore

/// Stage 2 inline overrides applied on top of a rehydrated ticket
/// (#201 AC3 / D6 — Stage 2 always wins).
struct TargetPrintOverrides: Equatable {
    var paperSize: String?      // CUPS `PageSize` token or `Custom.<w>x<h>`
    var mediaType: String?
    var qualityKey: String?     // PrinterCapabilities.qualityKey
    var quality: String?
    var orientation: String?    // "portrait" | "landscape"
}

/// One resolved ticket write.
struct TicketWrite: Equatable {
    let key: String
    let value: String
    let locked: Bool
}

/// The fully-resolved write list for one job — a **pure value**,
/// computed with zero Core Printing calls so it is unit- and
/// UI-testable without a live queue. Replaces the old `lp` argv
/// builder (#201 D4/D8).
struct ResolvedTicketWrites: Equatable {
    var writes: [TicketWrite]
    var paperToken: String?
    var orientation: String?
}

enum TicketWriteResolver {

    /// Quartz vocabulary constants (docs/14 §7) live on
    /// `ColorMatchingAttempts` next to the AP_* half — written
    /// alongside because there is no `lp` path left (D2).
    ///
    /// Order is locked and is the contract the tests assert:
    ///  1 `AP_ColorMatchingMode`          = AP_ApplicationColorMatching  (locked)
    ///  2 `AP.ColorMatchingMode`          = AP_ApplicationColorMatching  (locked)
    ///  3 `PMColorMatchingMode`           = APCustomColorMatching        (locked)
    ///  4 `PMCustomColorMatchingProfile`  = ""                           (unlocked)
    ///  5 `com.apple.print.PrintSettings.PMColorMatchingMode`
    ///                                    = APCustomColorMatching        (unlocked)
    ///  6 `PageSize`                      = overrides.paperSize
    ///  7 detectMediaTypeKey(optionKeys)  = overrides.mediaType
    ///  8 overrides.qualityKey            = overrides.quality
    ///  9 detectDriverColorBypass(optionKeys)                            (unlocked)
    /// 10 `orientation-requested`         = 3 | 4
    ///
    /// Invariants: `raw` can never appear (there is no `lp`); nothing
    /// is suppressed because a captured key already exists (D6 — the
    /// ticket carries the captured keys and Stage 2 writes land on
    /// top unconditionally); an override with a `nil` value emits no
    /// write.
    static func resolve(
        overrides: TargetPrintOverrides,
        optionKeys: Set<String>
    ) -> ResolvedTicketWrites {
        var writes: [TicketWrite] = []

        // 1–2 — locked AP_* pair (layer ③).
        for key in ColorMatchingAttempts.printSettingsKeys {
            writes.append(TicketWrite(
                key: key,
                value: ColorMatchingAttempts.applicationMatchingValue,
                locked: true))
        }
        // 3–5 — Quartz/`NSPrintOperation` vocabulary (D2).
        writes.append(TicketWrite(
            key: ColorMatchingAttempts.quartzModeKey,
            value: ColorMatchingAttempts.quartzCustomMatching,
            locked: true))
        writes.append(TicketWrite(
            key: ColorMatchingAttempts.quartzProfileKey,
            value: "",
            locked: false))
        writes.append(TicketWrite(
            key: ColorMatchingAttempts.quartzLegacyModeKey,
            value: ColorMatchingAttempts.quartzCustomMatching,
            locked: false))

        // 6 — the Stage 2 paper token.
        var paperToken: String?
        if let paperSize = overrides.paperSize, !paperSize.isEmpty {
            paperToken = paperSize
            writes.append(TicketWrite(
                key: "PageSize", value: paperSize, locked: false))
        }

        // 7 — media type via the queue's detected vendor key.
        if let mediaType = overrides.mediaType,
           let mediaKey = CupsParsers.detectMediaTypeKey(
               optionKeys: optionKeys) {
            writes.append(TicketWrite(
                key: mediaKey, value: mediaType, locked: false))
        }

        // 8 — print quality; the detected enumeration key travels in
        // the overrides (`PrinterCapabilities.qualityKey`, #183).
        if let qualityKey = overrides.qualityKey,
           let quality = overrides.quality {
            writes.append(TicketWrite(
                key: qualityKey, value: quality, locked: false))
        }

        // 9 — driver "no colour adjustment" bypass. Never gated on
        // `ppdUncorrectedPassthrough` — macOS always bypasses.
        if let bypass = CupsParsers.detectDriverColorBypass(
            optionKeys: optionKeys) {
            writes.append(TicketWrite(
                key: bypass.key, value: bypass.value, locked: false))
        }

        // 10 — orientation, CUPS IPP codes portrait=3 / landscape=4.
        if let orientation = overrides.orientation {
            writes.append(TicketWrite(
                key: "orientation-requested",
                value: orientation == "landscape" ? "4" : "3",
                locked: false))
        }

        return ResolvedTicketWrites(
            writes: writes.filter { $0.key.lowercased() != "raw" },
            paperToken: paperToken,
            orientation: overrides.orientation)
    }
}
