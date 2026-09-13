import Foundation

/// Deterministic process ids (docs/02 §Event bus). Listeners must always
/// filter events on `id` — historical bug #56 was an id mismatch.
public enum ProcessID {
    public static let instlist = "instlist"
    /// Spot-read console (issue #148) — single lease, like `instlist`.
    public static let spotread = "spotread"

    public static func targen(_ basename: String) -> String { "targen_\(basename)" }
    public static func printtarg(_ basename: String) -> String { "printtarg_\(basename)" }
    public static func chartread(_ basename: String) -> String { "chartread_\(basename)" }
    public static func average(_ basename: String) -> String { "average_\(basename)" }
    public static func colprof(_ basename: String) -> String { "colprof_\(basename)" }
    public static func profcheck(ti3Path: String) -> String { "profcheck_\(ti3Path)" }
    public static func iccgamut(stem: String) -> String { "iccgamut_\(stem)" }
    public static func printcal(_ stem: String) -> String { "printcal_\(stem)" }
    public static func applycal(_ stem: String) -> String { "applycal_\(stem)" }

    /// CUPS system tools (`/usr/bin/…`) — captured one-shots, not
    /// streaming Argyll children.
    public static func lpstat(_ mode: String) -> String { "lpstat_\(mode)" }
    public static func lpoptions(_ queue: String) -> String { "lpoptions_\(queue)" }
    public static func lp(_ queue: String, page: Int) -> String { "lp_\(queue)_\(page)" }
}
