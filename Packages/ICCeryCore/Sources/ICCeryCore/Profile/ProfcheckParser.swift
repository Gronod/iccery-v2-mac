import Foundation

/// Errors returned when `profcheck` output cannot be parsed.
public enum ProfcheckParserError: LocalizedError, Equatable, Sendable {
    case unparseable
    case jsonDecodingFailed

    public var errorDescription: String? {
        switch self {
        case .unparseable:
            return "Could not parse profcheck report"
        case .jsonDecodingFailed:
            return "profcheck JSON report could not be decoded"
        }
    }
}

/// Parses the mixed JSON/text output from `profcheck -v -k -s -u`.
public enum ProfcheckParser {

    /// Parsing order (issue #25):
    /// 1. Patch count from `No of test patches = N`.
    /// 2. JSON objects; prefer one with `event == "report"` or `*_de2000` keys.
    /// 3. Legacy text: `Profile check complete, errors(CIEDE2000): max. = X, avg. = Y, RMS = Z`.
    /// 4. Broad regex fallback.
    /// 5. If no metrics found, return a report whose `warning` is set.
    public static func parse(_ output: String) -> ProfcheckReport {
        var report = ProfcheckReport()

        // 1. Patch count.
        let patchRegex = try? NSRegularExpression(
            pattern: #"No of test patches\s*=\s*(\d+)"#,
            options: [.caseInsensitive]
        )
        if let match = patchRegex?.firstMatch(
            in: output,
            options: [],
            range: NSRange(output.startIndex..., in: output)
        ), let range = Range(match.range(at: 1), in: output) {
            let count = Int(output[range])
            report.patchCount = count
        }

        // 2. JSON objects.
        let jsonObjects = extractJSONObjects(from: output)
        for object in jsonObjects {
            if let event = object["event"] as? String, event == "report" {
                if let parsed = metrics(from: object) {
                    apply(metrics: parsed, to: &report)
                    return report
                }
            }
            if hasMetricKeys(object) {
                if let parsed = metrics(from: object) {
                    apply(metrics: parsed, to: &report)
                    return report
                }
            }
        }

        // 3. Legacy text.
        let textRegex = try? NSRegularExpression(
            pattern: #"Profile check complete, errors\(CIEDE2000\): max\.\s*=\s*([0-9.]+),\s*avg\.\s*=\s*([0-9.]+),\s*RMS\s*=\s*([0-9.]+)"#,
            options: [.caseInsensitive]
        )
        if let match = textRegex?.firstMatch(
            in: output,
            options: [],
            range: NSRange(output.startIndex..., in: output)
        ) {
            let numbers = (1...3).compactMap { i -> Double? in
                guard let range = Range(match.range(at: i), in: output) else { return nil }
                return Double(output[range])
            }
            if numbers.count == 3 {
                report.maxDE = numbers[0]
                report.avgDE = numbers[1]
                report.rmsDE = numbers[2]
                report.status = report.avgDE.map { VerificationStatus.from(avgDE: $0) }
                return report
            }
        }

        // 4. Broad regex fallback.
        if let fallback = parseRegexFallback(output) {
            var merged = fallback
            merged.patchCount = report.patchCount
            return merged
        }

        // 5. Unparseable.
        report.warning = "profcheck output did not contain a recognisable report."
        return report
    }

    // MARK: - JSON extraction

    private static func extractJSONObjects(from output: String) -> [[String: Any]] {
        var objects: [[String: Any]] = []
        var start: String.Index?
        var depth = 0

        for index in output.indices {
            let char = output[index]
            if char == "{" {
                if depth == 0 {
                    start = index
                }
                depth += 1
            } else if char == "}" {
                if depth > 0 {
                    depth -= 1
                    if depth == 0, let start = start {
                        let jsonString = String(output[start...index])
                        if let data = jsonString.data(using: .utf8),
                           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            objects.append(object)
                        }
                    }
                }
            }
        }

        return objects
    }

    private static func hasMetricKeys(_ object: [String: Any]) -> Bool {
        let keys = [
            "avg_de", "avg_de2000",
            "peak_de", "peak_de2000", "max_de",
            "rms", "rms_de"
        ]
        return keys.contains { object[$0] != nil }
    }

    private struct Metrics {
        var avg: Double?
        var max: Double?
        var rms: Double?
    }

    private static func metrics(from object: [String: Any]) -> Metrics? {
        var m = Metrics()
        m.avg = doubleValue(for: "avg_de2000", in: object)
            ?? doubleValue(for: "avg_de", in: object)
        m.max = doubleValue(for: "peak_de2000", in: object)
            ?? doubleValue(for: "peak_de", in: object)
            ?? doubleValue(for: "max_de", in: object)
            ?? doubleValue(for: "max_de2000", in: object)
        m.rms = doubleValue(for: "rms", in: object)
            ?? doubleValue(for: "rms_de", in: object)
            ?? doubleValue(for: "rms_de2000", in: object)

        guard m.avg != nil || m.max != nil || m.rms != nil else { return nil }
        return m
    }

    private static func doubleValue(for key: String, in object: [String: Any]) -> Double? {
        if let number = object[key] as? Double { return number }
        if let number = object[key] as? NSNumber { return number.doubleValue }
        if let string = object[key] as? String { return Double(string) }
        return nil
    }

    private static func apply(metrics: Metrics, to report: inout ProfcheckReport) {
        report.avgDE = metrics.avg
        report.maxDE = metrics.max
        report.rmsDE = metrics.rms
        if let avg = metrics.avg {
            report.status = VerificationStatus.from(avgDE: avg)
        }
    }

    // MARK: - Regex fallback

    private static func parseRegexFallback(_ output: String) -> ProfcheckReport? {
        var report = ProfcheckReport()

        let avgRegex = try? NSRegularExpression(
            pattern: #"(?:avg\.?|average)\s*(?:=|:)\s*([0-9.]+)"#,
            options: [.caseInsensitive]
        )
        let maxRegex = try? NSRegularExpression(
            pattern: #"(?:max\.?|peak|maximum)\s*(?:=|:)\s*([0-9.]+)"#,
            options: [.caseInsensitive]
        )
        let rmsRegex = try? NSRegularExpression(
            pattern: #"(?:rms)\s*(?:=|:)\s*([0-9.]+)"#,
            options: [.caseInsensitive]
        )

        report.avgDE = firstDouble(from: output, regex: avgRegex)
        report.maxDE = firstDouble(from: output, regex: maxRegex)
        report.rmsDE = firstDouble(from: output, regex: rmsRegex)

        guard report.avgDE != nil || report.maxDE != nil || report.rmsDE != nil else {
            return nil
        }

        if let avg = report.avgDE {
            report.status = VerificationStatus.from(avgDE: avg)
        }

        return report
    }

    private static func firstDouble(from output: String, regex: NSRegularExpression?) -> Double? {
        guard let regex = regex,
              let match = regex.firstMatch(
                in: output,
                options: [],
                range: NSRange(output.startIndex..., in: output)
              ),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return Double(output[range])
    }
}
