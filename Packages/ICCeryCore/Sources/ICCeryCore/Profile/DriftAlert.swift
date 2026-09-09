import Foundation

/// Computes a consecutive-breach warning from verification history.
///
/// A drift alert triggers when the most recent chronologically consecutive
/// poor records form a run of at least two, and the first and last of that
/// run are on distinct UTC days or at least one hour apart.
public enum DriftAlert {

    /// Returns an alert message, or `nil` when no consecutive breach exists.
    public static func compute(from records: [VerificationRecord]) -> String? {
        // Work in chronological order.
        let chronological = records.sorted { $0.timestamp < $1.timestamp }

        // Build the longest suffix of consecutive `.poor` records.
        // Non-poor records break the run, so we stop at the first non-poor
        // encountered from the end.
        var run: [VerificationRecord] = []
        for record in chronological.reversed() {
            if record.status == .poor {
                run.insert(record, at: 0)
            } else {
                break
            }
        }

        guard run.count >= 2 else { return nil }

        let first = run.first!
        let last = run.last!

        let sameDay = Calendar.utc.isDate(first.timestamp, inSameDayAs: last.timestamp)
        let oneHour = last.timestamp.timeIntervalSince(first.timestamp) >= 3600

        if !sameDay || oneHour {
            return "Drift alert: poor results between \(first.id) and \(last.id)."
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
