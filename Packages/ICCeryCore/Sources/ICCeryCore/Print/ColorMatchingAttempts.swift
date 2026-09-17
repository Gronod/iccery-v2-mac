import Foundation

/// Ordered private-SPI attempt table for the ColorSync suppression
/// engine (issue 14 layer ②, docs/11).
///
/// The ordering is data so the exact dlsym/mode sequence is unit-
/// testable without resolving any private symbols. The app layer walks
/// `attempts`, resolves each symbol via `dlsym(RTLD_DEFAULT,…)`, and
/// calls the first `(symbol, mode)` that returns `0` — verified on
/// macOS 14+ that all three symbols exist.
///
/// The SPI signature is `(PMPrintSession, CFStringRef) -> OSStatus`.
/// The second argument is the **mode string**, never integer `1`
/// (#188 — a 3-arg call is a SIGSEGV). `AP_ColorSyncMatching` and
/// `AP_VendorColorMatching` are forbidden modes — they re-enable
/// ColorSync/driver colour management.
public enum ColorMatchingAttempts {

    /// dlsym order: `…Lock` first (holds the print-session lock while
    /// setting), then the plain setter, then `…NoLock`.
    public static let symbols: [String] = [
        "PMSessionSetColorMatchingModeLock",
        "PMSessionSetColorMatchingMode",
        "PMSessionSetColorMatchingModeNoLock",
    ]

    /// Mode strings tried per symbol, in order. `AP_…` is the
    /// documented mode; the unprefixed variant is the older alias.
    public static let modes: [String] = [
        "AP_ApplicationColorMatching",
        "ApplicationColorMatching",
    ]

    /// Symbol-outer, mode-inner — the full attempt sequence; the app
    /// stops at the first call that returns `0`.
    public static var attempts: [(symbol: String, mode: String)] {
        symbols.flatMap { symbol in
            modes.map { (symbol: symbol, mode: $0) }
        }
    }

    /// Layer ③: both spellings of the print-settings key are written
    /// with `locked = true`. Written as `CFString` values.
    public static let applicationMatchingValue = "AP_ApplicationColorMatching"
    public static let printSettingsKeys: [String] = [
        "AP_ColorMatchingMode",
        "AP.ColorMatchingMode",
    ]

    /// The Quartz/`NSPrintOperation` colour-matching vocabulary
    /// (docs/14 §7). With the `lp` path removed there is a single
    /// spool path and it carries **both** dictionaries — these keys
    /// are written alongside the AP_* pair (#201 D2).
    ///
    /// `PMColorMatchingMode=APCustomColorMatching` plus an empty
    /// `PMCustomColorMatchingProfile` tell Quartz the application
    /// supplies device colour; the `com.apple.print.PrintSettings.*`
    /// legacy spelling covers drivers that read the flattened
    /// dictionary.
    public static let quartzModeKey = "PMColorMatchingMode"
    public static let quartzCustomMatching = "APCustomColorMatching"
    public static let quartzProfileKey = "PMCustomColorMatchingProfile"
    public static let quartzLegacyModeKey =
        "com.apple.print.PrintSettings.PMColorMatchingMode"
    /// The nested sub-dictionary inside `NSPrintInfo.dictionary()` the
    /// colour keys are mirrored into.
    public static let quartzNestedDictKey = "com.apple.print.printSettings"
}
