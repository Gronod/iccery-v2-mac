import Foundation

/// Canonical `CAL_` / original-stem pairing for Stage 0 (issue #29 / #83).
///
/// The live wizard basename, the persisted `calibrationOriginalBasename`,
/// and the runner all derive identity from this type. Do not add a second
/// `hasPrefix("CAL_")` ternary elsewhere.
public struct CalibrationIdentity: Equatable, Sendable {
    /// Never has a `CAL_` prefix. Empty only when the live basename is empty.
    public var originalBasename: String
    /// Always `CAL_{original}` when original is non-empty.
    public var calibrationBasename: String

    public init(originalBasename: String, calibrationBasename: String) {
        self.originalBasename = originalBasename
        self.calibrationBasename = calibrationBasename
    }

    public static func isCalibration(_ basename: String) -> Bool {
        basename.hasPrefix("CAL_")
    }

    /// The only place that adds a `CAL_` prefix.
    public static func prefix(_ original: String) -> String {
        if original.isEmpty { return original }
        return original.hasPrefix("CAL_") ? original : "CAL_\(original)"
    }

    /// Strip a single leading `CAL_` if present.
    public static func strip(_ basename: String) -> String {
        basename.hasPrefix("CAL_") ? String(basename.dropFirst(4)) : basename
    }

    /// Derive identity from the live wizard basename and the persisted
    /// original. A non-empty persisted original wins over a `CAL_` live
    /// name (Force Quit mid-calibration).
    public static func parse(liveBasename: String, persistedOriginal: String) -> CalibrationIdentity {
        if liveBasename.isEmpty && persistedOriginal.isEmpty {
            return CalibrationIdentity(originalBasename: "", calibrationBasename: "")
        }
        let original: String
        if liveBasename.hasPrefix("CAL_") {
            original = persistedOriginal.isEmpty ? strip(liveBasename) : persistedOriginal
        } else if liveBasename.isEmpty {
            original = persistedOriginal
        } else {
            original = liveBasename
        }
        return CalibrationIdentity(
            originalBasename: original,
            calibrationBasename: prefix(original)
        )
    }
}
