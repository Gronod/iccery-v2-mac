import Foundation

/// A single channel's calibration curve.
public struct CalibrationCurve: Sendable, Equatable {
    public let channel: Character
    public let input: [Double]
    public let output: [Double]

    public init(channel: Character, input: [Double], output: [Double]) {
        self.channel = channel
        self.input = input
        self.output = output
    }
}

/// Parsed Argyll `.cal` curve data.
public struct CalibrationData: Sendable, Equatable {
    public var colorRep: String
    public var descriptor: String?
    public var created: Date?
    public var maxTac: Double?
    public var inkLimits: [Character: Double]
    public var curves: [CalibrationCurve]

    public init(
        colorRep: String = "",
        descriptor: String? = nil,
        created: Date? = nil,
        maxTac: Double? = nil,
        inkLimits: [Character: Double] = [:],
        curves: [CalibrationCurve] = []
    ) {
        self.colorRep = colorRep
        self.descriptor = descriptor
        self.created = created
        self.maxTac = maxTac
        self.inkLimits = inkLimits
        self.curves = curves
    }
}

/// Errors from loading and parsing a `.cal` file.
public enum CalibrationStoreError: Error, Equatable {
    case unreadableFile
    case missingColorRep
    case missingCurveData
    case unsupportedFormat
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Could not read the calibration file."
        case .missingColorRep:
            return "The .cal file is missing its COLOR_REP header."
        case .missingCurveData:
            return "The .cal file contains no calibration curve data."
        case .unsupportedFormat:
            return "The .cal file format is not supported."
        case .parseFailed(let reason):
            return "Calibration parse failed: \(reason)"
        }
    }
}

/// Store for a calibration curve, its metadata, and staleness checks.
public actor CalibrationStore {

    public private(set) var data: CalibrationData?
    public private(set) var sourceURL: URL?
    public private(set) var storedPrinterName: String?

    /// Number of days after which a calibration is considered stale.
    public var staleDays: Int

    public init(staleDays: Int = 30) {
        self.staleDays = staleDays
    }

    /// Load and parse a `.cal` file.
    public func load(url: URL) async throws {
        let dataset = try CGATSParser.parse(url: url)

        guard let colorRep = dataset.colorRep, !colorRep.isEmpty else {
            throw CalibrationStoreError.missingColorRep
        }

        var data = CalibrationData()
        data.colorRep = colorRep
        data.descriptor = dataset.keywords["DESCRIPTOR"]

        if let createdString = dataset.keywords["CREATED"] {
            let formatter = ISO8601DateFormatter()
            data.created = formatter.date(from: createdString)
                ?? Date(timeIntervalSince1970: 0)
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            data.created = attrs?[.modificationDate] as? Date
        }

        let limitKeys = ["MAX_TAC", "TOTAL_INK_LIMIT", "INK_LIMIT"]
        for key in limitKeys {
            if let raw = dataset.keywords[key], let value = Double(raw) {
                data.maxTac = value
                break
            }
        }

        for (key, raw) in dataset.keywords where key.hasPrefix("INK_LIMIT_") {
            let suffix = key.dropFirst("INK_LIMIT_".count)
            guard let channel = suffix.first, let value = Double(raw) else { continue }
            data.inkLimits[channel] = value
        }

        data.curves = try Self.extractCurves(from: dataset)
        guard !data.curves.isEmpty else {
            throw CalibrationStoreError.missingCurveData
        }

        self.data = data
        self.sourceURL = url

        // Printer name may live in a sidecar JSON. For now, fall back to the
        // descriptor so callers have something to compare.
        self.storedPrinterName = data.descriptor
    }

    /// Store an explicit printer name (e.g. from a sidecar).
    public func setPrinterName(_ name: String?) {
        self.storedPrinterName = name
    }

    /// True if the loaded calibration is older than `staleDays` or the
    /// printer name does not match.
    public func isStale(comparedTo currentPrinter: String? = nil) -> Bool {
        guard let data else { return true }

        if let created = data.created,
           let threshold = Calendar.current.date(byAdding: .day, value: staleDays, to: created),
           Date() > threshold {
            return true
        }

        if let stored = storedPrinterName, !stored.isEmpty,
           let current = currentPrinter, !current.isEmpty,
           stored != current {
            return true
        }

        return false
    }

    // MARK: - Internals

    private static func extractCurves(from dataset: CGATSDataset) throws -> [CalibrationCurve] {
        // Argyll .cal files contain an INPUT_VALUE column and one or more
        // per-channel output columns. Field names vary by COLOR_REP.
        let outputFields = dataset.fieldNames.filter { $0 != "SAMPLE_ID" && $0 != "SAMPLE_LOC" && $0 != "INPUT_VALUE" }
        guard !outputFields.isEmpty else {
            // Older .cal files may only have one output column named OUTPUT_VALUE.
            if dataset.fieldNames.contains("OUTPUT_VALUE") {
                return [try buildCurve(channel: "K", field: "OUTPUT_VALUE", dataset: dataset)]
            }
            throw CalibrationStoreError.missingCurveData
        }

        var curves = [CalibrationCurve]()
        for field in outputFields {
            let channel = field.first ?? "?"
            let curve = try buildCurve(channel: channel, field: field, dataset: dataset)
            curves.append(curve)
        }
        return curves
    }

    private static func buildCurve(
        channel: Character,
        field: String,
        dataset: CGATSDataset
    ) throws -> CalibrationCurve {
        var input = [Double]()
        var output = [Double]()

        for sample in dataset.samples {
            guard let inRaw = sample.values["INPUT_VALUE"] ?? sample.values[field],
                  let inVal = parseNumber(inRaw),
                  let outRaw = sample.values[field],
                  let outVal = parseNumber(outRaw) else {
                throw CalibrationStoreError.parseFailed("Non-numeric curve value in \(field)")
            }
            input.append(inVal)
            output.append(outVal)
        }

        return CalibrationCurve(channel: channel, input: input, output: output)
    }

    private static func parseNumber(_ raw: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.number(from: raw)?.doubleValue
    }
}
