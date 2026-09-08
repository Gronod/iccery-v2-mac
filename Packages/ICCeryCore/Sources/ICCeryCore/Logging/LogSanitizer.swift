import Foundation

/// Rewrites the user's home directory to `~` in log output
/// (docs/03 §Logging hygiene — `sanitize_arg_for_logging`).
public enum LogSanitizer {
    /// Replaces every occurrence of the current user's home path with `~`.
    public static func sanitize(_ text: String) -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }

    /// Sanitizes an argv list for display.
    public static func sanitizeArgs(_ args: [String]) -> String {
        args.map(sanitize).joined(separator: " ")
    }
}
