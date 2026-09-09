import Foundation

/// Errors from writing a canonical `.ti3` dataset.
public enum CGATSWriterError: Error, Equatable {
    case noSamples
    case missingRequiredField(String)
    case invalidValue(field: String, value: String)
}

/// Write a `CGATSDataset` to Argyll-consumable `.ti3` text.
public enum CGATSWriter {

    public static func write(_ dataset: CGATSDataset) throws -> String {
        guard !dataset.samples.isEmpty, !dataset.fieldNames.isEmpty else {
            throw CGATSWriterError.noSamples
        }

        var lines = [String]()

        // Header
        lines.append(dataset.format.rawValue)
        lines.append("")

        lines.append("DESCRIPTOR \"ICCery CGATS export\"")
        if let colorRep = dataset.colorRep {
            lines.append("COLOR_REP \"\(colorRep)\"")
        }
        if let deviceClass = dataset.deviceClass {
            lines.append("DEVICE_CLASS \"\(deviceClass)\"")
        }
        if let instrument = dataset.targetInstrument {
            lines.append("TARGET_INSTRUMENT \"\(instrument)\"")
        }

        lines.append("NUMBER_OF_FIELDS \(dataset.fieldNames.count)")
        lines.append("NUMBER_OF_SETS \(dataset.samples.count)")
        lines.append("")

        lines.append("BEGIN_DATA_FORMAT")
        lines.append(dataset.fieldNames.joined(separator: "\t"))
        lines.append("END_DATA_FORMAT")
        lines.append("")

        lines.append("BEGIN_DATA")
        for sample in dataset.samples {
            let row = try dataset.fieldNames.map { field in
                guard let raw = sample.values[field], !raw.isEmpty else {
                    throw CGATSWriterError.missingRequiredField(field)
                }
                // Normalize numeric fields to a compact decimal.
                if isNumeric(field) {
                    return normalizedNumber(raw)
                }
                return raw
            }
            lines.append(row.joined(separator: "\t"))
        }
        lines.append("END_DATA")

        return lines.joined(separator: "\n") + "\n"
    }

    public static func write(_ dataset: CGATSDataset, to url: URL) throws {
        let text = try write(dataset)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Internals

    private static func isNumeric(_ field: String) -> Bool {
        let nonNumeric: Set = ["SAMPLE_ID", "SAMPLE_LOC", "SAMPLE_NAME"]
        return !nonNumeric.contains(field)
    }

    private static func normalizedNumber(_ raw: String) -> String {
        guard let number = Double(raw) else { return raw }
        if number == floor(number) {
            return String(format: "%.0f", number)
        }
        return String(format: "%.4f", number)
    }
}
