import Foundation

/// Tiny argv helpers. Each Argyll tool keeps its own `*Args` enum —
/// `-d` / `-u` / `-r` still mean different things per binary.
public enum ArgsBuilder {
    /// `["-f", value]` when `value` is non-nil.
    public static func option(_ flag: String, _ value: String?) -> [String] {
        guard let value else { return [] }
        return [flag, value]
    }

    /// `["-f", trimmed]` when trimmed is non-empty.
    public static func optionIfNonEmpty(_ flag: String, _ value: String?) -> [String] {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return [] }
        return [flag, raw]
    }

    /// Omits the flag when `value` is nil or within `epsilon` of `skip`.
    public static func optionUnlessApprox(
        _ flag: String,
        _ value: Double?,
        skip: Double,
        epsilon: Double = 0.001,
        format: String = "%.2f"
    ) -> [String] {
        guard let value, abs(value - skip) >= epsilon else { return [] }
        return [flag, String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)]
    }

    /// Bare flag when `when` is true.
    public static func flag(_ flag: String, when: Bool) -> [String] {
        when ? [flag] : []
    }
}
