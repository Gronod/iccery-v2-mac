import Foundation

/// CUPS option filtering for `PMPrintSettingsToOptions` capture
/// (issue 14 layer ⑥, docs/11 §filter).
///
/// The captured `key=value` string is reduced to the options that
/// should be replayed on `lp`: `com.apple.*` ticket keys, job
/// bookkeeping (`collate`, `copies`, `pserrorhandler-requested`,
/// `job-sheets`), empty values, and **both** `AP_*ColorMatchingMode`
/// keys are dropped — `build_lp_args` always re-adds those itself
/// (issue 15). Unknown non-`com.*` keys are kept (permissive — vendor
/// driver keys survive).
public enum CupsOptionsFilter {

    /// Option keys forwarded from the panel to `lp` (docs/11 roster).
    public static let relevantKeys: Set<String> = [
        // Media
        "MediaType", "CNIJMediaType", "EPIJ_Medi", "StpMediaType",
        // Tray
        "InputSlot", "AP_D_InputSlot",
        // Size
        "PageSize",
        // Colour bypass
        "CNIJIntent2", "CNIJIntent", "EPIJ_CMat", "EPIJ_CCor",
        "EPIJ_OSColMat", "ColorCorrection", "StpColorCorrection",
        "EpsonColorMode", "ColorModel",
        // Quality
        "Resolution", "cupsPrintQuality", "Quality", "EPIJ_Quality",
        "CNIJQuality", "StpQuality", "OutputMode",
        // Duplex
        "Duplex", "sides",
    ]

    /// Keys we always drop regardless of the relevant list. `raw` is
    /// included — a captured `raw=…` would re-enable CUPS raw mode and
    /// bypass the raster filter that honours `AP_ApplicationColorMatching`
    /// (#92).
    public static let alwaysDropped: Set<String> = [
        "collate", "copies", "pserrorhandler-requested", "job-sheets",
        "AP_ColorMatchingMode", "AP.ColorMatchingMode", "raw",
    ]

    /// A `key=value` pair survives when the key is non-empty, the value
    /// is non-empty, the key is not `com.apple.*`, not always-dropped,
    /// and either relevant or an unknown non-`com.*` driver key.
    public static func isRelevant(key: String, value: String) -> Bool {
        guard !key.isEmpty, !value.isEmpty else { return false }
        if key.hasPrefix("com.apple.") { return false }
        if alwaysDropped.contains(key) { return false }
        if relevantKeys.contains(key) { return true }
        // Permissive: unknown vendor keys survive (non-com.*).
        return !key.hasPrefix("com.")
    }

    /// `key=value key=value …` → filtered string, order preserved.
    public static func filter(_ options: String) -> String {
        CupsParsers.lpoptions(options)
            .filter { isRelevant(key: $0.key, value: $0.value) }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
