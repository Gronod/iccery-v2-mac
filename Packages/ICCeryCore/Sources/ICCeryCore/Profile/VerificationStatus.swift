import Foundation

/// ICCery quality band for a verification run.
///
/// Bands are on the **average** ΔE₀₀:
/// - < 1.0 → Excellent
/// - < 2.0 → Good
/// - < 3.5 → Acceptable
/// - ≥ 3.5 → Warning
public enum VerificationStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case excellent
    case good
    case acceptable
    case poor

    public var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .acceptable: return "Acceptable"
        case .poor: return "Warning"
        }
    }

    /// Returns the quality band for the given average ΔE₀₀.
    public static func from(avgDE: Double) -> VerificationStatus {
        if avgDE < 1.0 { return .excellent }
        if avgDE < 2.0 { return .good }
        if avgDE < 3.5 { return .acceptable }
        return .poor
    }
}
