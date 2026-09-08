import Foundation

/// Deterministic process ids (docs/02 §Event bus). Listeners must always
/// filter events on `id` — historical bug #56 was an id mismatch.
public enum ProcessID {
    public static let instlist = "instlist"

    public static func targen(_ basename: String) -> String { "targen_\(basename)" }
    public static func printtarg(_ basename: String) -> String { "printtarg_\(basename)" }
    public static func chartread(_ basename: String) -> String { "chartread_\(basename)" }
    public static func average(_ basename: String) -> String { "average_\(basename)" }
    public static func colprof(_ basename: String) -> String { "colprof_\(basename)" }
    public static func profcheck(ti3Path: String) -> String { "profcheck_\(ti3Path)" }
    public static func iccgamut(stem: String) -> String { "iccgamut_\(stem)" }
    public static func printcal(_ stem: String) -> String { "printcal_\(stem)" }
    public static func applycal(_ stem: String) -> String { "applycal_\(stem)" }
}
