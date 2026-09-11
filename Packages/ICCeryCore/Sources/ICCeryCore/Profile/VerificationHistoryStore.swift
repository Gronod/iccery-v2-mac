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
    private let fileStore: JSONFileStore<[VerificationRecord]>

    public init(
        url: URL = AppPaths.appDataDir.appendingPathComponent("verification_history.json"),
        capacity: Int = defaultCapacity
    ) {
        self.url = url
        self.capacity = capacity
        self.fileStore = JSONFileStore(
            fileURL: url,
            corrupt: .throwCorrupt,
            defaultValue: { [] },
            dateEncoding: .iso8601,
            dateDecoding: .iso8601
        )
    }

    /// Loads records from disk. Returns the existing cache if already loaded.
    ///
    /// Throws when the file exists but cannot be parsed; the existing file
    /// is never overwritten in that case.
    public func load() throws -> [VerificationRecord] {
        guard records.isEmpty else { return records }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        records = try fileStore.load()
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
    /// Loads the existing history first and propagates any load error so an
    /// unparseable file is never overwritten.
    @discardableResult
    public func append(_ record: VerificationRecord) throws -> [VerificationRecord] {
        try load()

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
    ///
    /// Loads the existing history first and propagates any load error so an
    /// unparseable file is never overwritten.
    public func clear() throws {
        try load()
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
        try fileStore.save(records)
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
