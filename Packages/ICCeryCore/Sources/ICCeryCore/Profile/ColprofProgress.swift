import Foundation

/// Classified `colprof` stdout progress milestone.
public enum ColprofProgress: Sendable, Equatable {
    case gamutMapping
    case fittingClut
    case writingIcc
    case unknown
}

/// Parses `colprof` plaintext progress (docs/16 §6.3).
///
/// The Gronod fork supports `-u` JSON, but ICCery v2.0 does not pass it.
/// Progress is therefore inferred from case-insensitive substring matches.
public enum ColprofProgressClassifier {

    public static func classify(line: String) -> ColprofProgress {
        let lower = line.lowercased()
        if lower.contains("gamut mapping") {
            return .gamutMapping
        }
        if lower.contains("fitting") || lower.contains("clut") {
            return .fittingClut
        }
        if lower.contains("writing") || lower.contains("icc profile") {
            return .writingIcc
        }
        return .unknown
    }
}
