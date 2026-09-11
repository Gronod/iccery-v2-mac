import Foundation

/// Errors that can occur while parsing CGATS-like data.
public enum CGATSParseError: Error, Equatable {
    case emptyFile
    case missingBeginDataFormat
    case missingEndDataFormat
    case missingBeginData
    case missingEndData
    case missingNumberOfFields
    case missingNumberOfSets
    case unknownFieldName(String)
    case malformedRow(line: Int, reason: String)
    case nonNumericValue(field: String, value: String, line: Int)
    case outOfBoundsValue(field: String, value: Double, line: Int)
    case implausibleValue(field: String, value: Double, line: Int)
    case incorrectArity(line: Int, expected: Int, got: Int)
}

/// One row of a CGATS dataset, keyed by canonical field name.
public struct CGATSSample: Sendable, Equatable {
    public var id: String
    public var loc: String?
    public var values: [String: String]

    public init(id: String, loc: String? = nil, values: [String: String] = [:]) {
        self.id = id
        self.loc = loc
        self.values = values
    }
}

/// A parsed CGATS / CTI3 / CSV dataset.
public struct CGATSDataset: Sendable, Equatable {
    public var format: CGATSFormat
    public var keywords: [String: String]
    public var fieldNames: [String]
    public var samples: [CGATSSample]
    public var colorRep: String?
    public var deviceClass: String?
    public var targetInstrument: String?

    public init(
        format: CGATSFormat,
        keywords: [String: String] = [:],
        fieldNames: [String] = [],
        samples: [CGATSSample] = [],
        colorRep: String? = nil,
        deviceClass: String? = nil,
        targetInstrument: String? = nil
    ) {
        self.format = format
        self.keywords = keywords
        self.fieldNames = fieldNames
        self.samples = samples
        self.colorRep = colorRep
        self.deviceClass = deviceClass
        self.targetInstrument = targetInstrument
    }
}

public enum CGATSFormat: String, Sendable, Equatable {
    case cti3 = "CTI3"
    case cgats17 = "CGATS.17"
    case csv = "CSV"
}

/// Parser for CGATS.17, CTI3, ISO28178, and simple CSV datasets.
public enum CGATSParser {

    /// Parse the contents of a CGATS-like file.
    public static func parse(
        _ contents: String,
        sourceURL: URL? = nil
    ) throws -> CGATSDataset {
        guard !contents.isEmpty else { throw CGATSParseError.emptyFile }

        let ext = sourceURL?.pathExtension.lowercased() ?? ""
        let isCSV = ext == "csv" || contents.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("SAMPLE_ID,")

        let (format, lines) = try preprocess(contents, isCSV: isCSV)

        var formatStart: Int?
        var formatEnd: Int?
        var dataStart: Int?
        var dataEnd: Int?
        var keywords = [String: String]()

        for (index, line) in lines.enumerated() {
            switch Self.normalizedKeyword(line) {
            case "BEGIN_DATA_FORMAT": formatStart = index
            case "END_DATA_FORMAT":   formatEnd = index
            case "BEGIN_DATA":        dataStart = index
            case "END_DATA":          dataEnd = index
            default:
                if let (key, value) = parseKeyword(line) {
                    keywords[key] = value
                }
            }
        }

        guard let formatStart, let formatEnd, formatEnd > formatStart + 1 else {
            throw CGATSParseError.missingBeginDataFormat
        }
        guard let dataStart, let dataEnd, dataEnd > dataStart + 1 else {
            throw CGATSParseError.missingBeginData
        }

        let rawFieldNames = splitFields(lines[formatStart + 1])
        let fieldNames = rawFieldNames.map { canonicalFieldName($0) }

        if let numberOfFields = keywords["NUMBER_OF_FIELDS"].flatMap(Int.init),
           numberOfFields != fieldNames.count {
            // Warn only; the data format line is the source of truth.
        } else if keywords["NUMBER_OF_FIELDS"] == nil {
            // Optional header; do not fail.
        }

        if let numberOfSets = keywords["NUMBER_OF_SETS"].flatMap(Int.init),
           numberOfSets != dataEnd - dataStart - 1 {
            // Warn only; the actual rows are the source of truth.
        } else if keywords["NUMBER_OF_SETS"] == nil {
            // Optional header; do not fail.
        }

        struct RawSample {
            var id: String
            var loc: String?
            var numbers: [String: Double] = [:]
            var strings: [String: String] = [:]
            var lineIndex: Int
        }

        var rawSamples = [RawSample]()
        var groupMax: [String: Double] = [:]

        for offset in 1...(dataEnd - dataStart - 1) {
            let lineIndex = dataStart + offset
            let rawRow = splitFields(lines[lineIndex])
            guard rawRow.count == fieldNames.count else {
                throw CGATSParseError.incorrectArity(line: lineIndex + 1, expected: fieldNames.count, got: rawRow.count)
            }

            var sample = RawSample(id: String(offset), lineIndex: lineIndex)
            for (i, name) in fieldNames.enumerated() {
                let raw = stripInlineComment(rawRow[i])
                if isNumericField(name) {
                    let cleaned = raw.trimmingCharacters(in: .whitespaces)
                    if let number = parseNumber(cleaned) {
                        sample.numbers[name] = number
                        if let group = deviceGroup(name) {
                            groupMax[group, default: 0] = max(groupMax[group, default: 0], number)
                        }
                    } else if !cleaned.isEmpty {
                        throw CGATSParseError.nonNumericValue(field: name, value: raw, line: lineIndex + 1)
                    }
                } else {
                    sample.strings[name] = raw
                }
            }

            sample.id = sample.strings["SAMPLE_ID"] ?? sample.numbers["SAMPLE_ID"].map { String(format: "%.0f", $0) } ?? String(offset)
            sample.loc = sample.strings["SAMPLE_LOC"]
            rawSamples.append(sample)
        }

        var samples = [CGATSSample]()
        for raw in rawSamples {
            var values = raw.strings
            for (name, number) in raw.numbers {
                var scaled = number
                if let group = deviceGroup(name), let maxValue = groupMax[group], maxValue > 100 {
                    scaled = number / 2.55
                }
                values[name] = validateValue(scaled, field: name, line: raw.lineIndex + 1)
            }

            var sample = CGATSSample(id: raw.id, loc: raw.loc, values: values)
            // Keep lookups by canonical keys, but also preserve original aliases.
            let rawRow = splitFields(lines[raw.lineIndex])
            for (i, rawName) in rawFieldNames.enumerated() {
                let canonical = canonicalFieldName(rawName)
                if canonical != rawName {
                    sample.values[rawName] = rawRow[i]
                }
            }
            samples.append(sample)
        }

        let colorRep = keywords["COLOR_REP"] ?? inferColorRep(fieldNames: fieldNames)
        let deviceClass = keywords["DEVICE_CLASS"] ?? inferDeviceClass(fieldNames: fieldNames)

        return CGATSDataset(
            format: format,
            keywords: keywords,
            fieldNames: fieldNames,
            samples: samples,
            colorRep: colorRep,
            deviceClass: deviceClass,
            targetInstrument: keywords["TARGET_INSTRUMENT"]
        )
    }

    /// Parse from a URL (throws as `Error` for public callers).
    public static func parse(url: URL) throws -> CGATSDataset {
        let contents = try String(contentsOf: url)
        return try parse(contents, sourceURL: url)
    }

    // MARK: - Internals

    private static func preprocess(
        _ contents: String,
        isCSV: Bool
    ) throws -> (CGATSFormat, [String]) {
        let allLines = contents.components(separatedBy: .newlines)
        var lines = [String]()

        var format: CGATSFormat?
        for var line in allLines {
            line = stripComment(line)
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if format == nil {
                if line.hasPrefix("CTI3") { format = .cti3 }
                else if line.hasPrefix("CGATS.17") { format = .cgats17 }
                else if isCSV { format = .csv }
            }

            if line == "BEGIN_DATA_FORMAT" || line == "END_DATA_FORMAT" ||
               line == "BEGIN_DATA" || line == "END_DATA" ||
               (line.hasPrefix("BEGIN_DATA_FORMAT") || line.hasPrefix("END_DATA_FORMAT") ||
                line.hasPrefix("BEGIN_DATA") || line.hasPrefix("END_DATA")) {
                // These are exact keywords; keep them intact.
            }

            lines.append(line)
        }

        guard !lines.isEmpty else { throw CGATSParseError.emptyFile }

        // Wrap a bare CSV / ISO28178 file in the canonical CGATS block
        // structure so the boundary-based parser below can handle it.
        if let format, format == .csv,
           !lines.contains(where: { Self.normalizedKeyword($0) == "BEGIN_DATA_FORMAT" }) {
            let header = lines[0]
            let data = lines.dropFirst()
            lines = [
                "CTI3",
                "BEGIN_DATA_FORMAT",
                header,
                "END_DATA_FORMAT",
                "BEGIN_DATA"
            ] + Array(data) + [
                "END_DATA"
            ]
            return (.csv, lines)
        }

        return (format ?? .cti3, lines)
    }

    private static func stripComment(_ line: String) -> String {
        if let range = line.range(of: "#") {
            return String(line[..<range.lowerBound])
        }
        return line
    }

    private static func stripInlineComment(_ token: String) -> String {
        if let range = token.range(of: "#") {
            return String(token[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return token
    }

    private static func splitFields(_ line: String) -> [String] {
        // CTI3/CGATS.17 use whitespace/tabs; CSV uses commas.
        if line.contains(",") {
            return line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    private static func parseKeyword(_ line: String) -> (key: String, value: String)? {
        // KEYWORD value  or  KEYWORD "value"
        let tokens = splitFields(line)
        guard let key = tokens.first else { return nil }

        // Data-boundary keywords are not value keywords.
        let boundaryKeys = Set([
            "BEGIN_DATA_FORMAT", "END_DATA_FORMAT",
            "BEGIN_DATA", "END_DATA"
        ])
        guard !boundaryKeys.contains(key) else { return nil }

        let rawValue = tokens.dropFirst().joined(separator: " ")
        let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (key, value)
    }

    private static func normalizedKeyword(_ line: String) -> String {
        line.uppercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Field name normalization

    private static func canonicalFieldName(_ raw: String) -> String {
        let upper = raw.uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        switch upper {
        case "SAMPLE_ID", "ID": return "SAMPLE_ID"
        case "SAMPLE_LOC", "LOC": return "SAMPLE_LOC"
        case "SAMPLE_NAME": return "SAMPLE_ID"
        case "LAB_L", "L*", "L_AB": return "LAB_L"
        case "LAB_A", "A*", "A_AB": return "LAB_A"
        case "LAB_B", "B*", "B_AB": return "LAB_B"
        case "XYZ_X", "X": return "XYZ_X"
        case "XYZ_Y", "Y": return "XYZ_Y"
        case "XYZ_Z", "Z": return "XYZ_Z"
        default: return upper
        }
    }

    private static func isNumericField(_ name: String) -> Bool {
        let numericNames: Set = [
            "SAMPLE_ID", "SAMPLE_LOC", "SAMPLE_NAME"
        ]
        return !numericNames.contains(name)
    }

    private static func parseNumber(_ raw: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.number(from: raw)?.doubleValue
    }

    private static func validateValue(_ value: Double, field: String, line: Int) -> String {
        var number = value

        // Plausibility checks for Lab and XYZ.
        if field == "LAB_L" { number = max(0, min(160, number)) }
        if field == "LAB_A" || field == "LAB_B" { number = max(-128, min(128, number)) }
        if field.hasPrefix("XYZ_") { number = max(0, min(200, number)) }

        return String(format: "%.4f", number)
    }

    private static func deviceGroup(_ name: String) -> String? {
        if name.hasPrefix("RGB_") { return "RGB" }
        if name.hasPrefix("CMYK_") { return "CMYK" }
        if name.hasPrefix("DEVICE_") { return "DEVICE" }
        return nil
    }

    private static func inferColorRep(fieldNames: [String]) -> String? {
        if fieldNames.contains(where: { $0.hasPrefix("CMYK_") }) { return "CMYK" }
        if fieldNames.contains(where: { $0.hasPrefix("RGB_") }) { return "RGB" }
        if fieldNames.contains(where: { $0.hasPrefix("LAB_") }) { return "LAB" }
        if fieldNames.contains(where: { $0.hasPrefix("XYZ_") }) { return "XYZ" }
        return nil
    }

    private static func inferDeviceClass(fieldNames: [String]) -> String? {
        if fieldNames.contains(where: { $0.hasPrefix("CMYK_") }) { return "PRINTER" }
        if fieldNames.contains(where: { $0.hasPrefix("RGB_") }) { return "DISPLAY" }
        return "OUTPUT"
    }
}
