import Foundation

/// Computes a consecutive-breach warning from verification history.
///
/// A drift alert triggers when there are at least two `poor` records on
/// distinct calendar days, or two `poor` records at least one hour apart.
public enum DriftAlert {

    /// Returns an alert message, or `nil` when no consecutive breach exists.
    public static func compute(from records: [VerificationRecord]) -> String? {
        let poor = records
            .filter { $0.status == .poor }
            .sorted { $0.timestamp < $1.timestamp }

        guard poor.count >= 2 else { return nil }

        for i in 0..<poor.count {
            for j in (i + 1)..<poor.count {
                let a = poor[i]
                let b = poor[j]

                let sameDay = Calendar.utc.isDate(a.timestamp, inSameDayAs: b.timestamp)
                let oneHour = b.timestamp.timeIntervalSince(a.timestamp) >= 3600

                if !sameDay || oneHour {
                    return "Drift alert: poor results between \(a.id) and \(b.id)."
                }
            }
        }

        return nil
    }
}

private extension Calendar {
    static let utc: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
