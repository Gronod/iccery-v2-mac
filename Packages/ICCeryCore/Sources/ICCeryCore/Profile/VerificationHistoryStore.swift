import Foundation

/// Persistence for `VerificationRecord` entries.
public actor VerificationHistoryStore {

    /// Default cap.
    public static let defaultCapacity = 1000

    /// Path to the JSON store.
    public let url: URL

    /// In-memory cache, kept in sync with disk.
    private var records: [VerificationRecord] = []

    private let capacity: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        url: URL = AppPaths.appDataDir.appendingPathComponent("verification_history.json"),
        capacity: Int = defaultCapacity
    ) {
        self.url = url
        self.capacity = capacity

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Loads records from disk. Returns the existing cache if already loaded.
    ///
    /// Throws when the file exists but cannot be parsed; the existing file
    /// is never overwritten in that case.
    public func load() throws -> [VerificationRecord] {
        guard records.isEmpty else { return records }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return [] }
        records = try decoder.decode([VerificationRecord].self, from: data)
        return records
    }

    /// Returns all records.
    public func all() -> [VerificationRecord] {
        records
    }

    /// Records matching the optional printer filter.
    public func filtered(by printer: String?) -> [VerificationRecord] {
        guard let printer = printer, !printer.isEmpty else { return records }
        return records.filter { $0.printerName == printer }
    }

    /// Appends a record, trims to capacity, and writes atomically.
    ///
    /// Returns the trimmed list, or `nil` if a write error occurs so the
    /// caller can surface the failure without replacing the in-memory list.
    @discardableResult
    public func append(_ record: VerificationRecord) throws -> [VerificationRecord] {
        var updated = records
        updated.append(record)
        if updated.count > capacity {
            updated.sort { $0.timestamp < $1.timestamp }
            updated = Array(updated.suffix(capacity))
        }

        try write(updated)
        records = updated
        return updated
    }

    /// Removes all history and updates disk.
    public func clear() throws {
        try write([])
        records = []
    }

    /// RFC-4180 CSV export.
    public func exportCSV() -> String {
        var lines: [String] = [
            csvRow(["id", "profile_name", "printer_name", "avg_de", "max_de", "rms_de", "patch_count", "status", "timestamp"])
        ]

        for record in records {
            lines.append(csvRow([
                record.id,
                record.profileName,
                record.printerName,
                String(record.avgDE),
                String(record.maxDE),
                String(record.rmsDE),
                String(record.patchCount),
                record.status.rawValue,
                ISO8601DateFormatter().string(from: record.timestamp)
            ]))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes `records` through a temp file and rename.
    private func write(_ records: [VerificationRecord]) throws {
        let data = try encoder.encode(records)
        try AtomicFileWriter.write(data, to: url)
    }

    private func csvRow(_ fields: [String]) -> String {
        fields.map { field in
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
                return "\"\(escaped)\""
            }
            return escaped
        }.joined(separator: ",")
    }
}
