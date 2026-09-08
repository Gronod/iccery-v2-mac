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
}
