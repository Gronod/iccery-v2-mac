import Foundation
import OSLog

/// Rolling file sink for `AppLogger` — `~/Library/Logs/<bundle>/
/// iccery.log`, rotated at 5 MiB, keeping 5 historical segments
/// (`iccery.log.1` … `iccery.log.5`).
///
/// The minimum level is **runtime state** (#158): `setLevel` takes
/// effect immediately — at startup and on every settings save.
public final class LogSink: @unchecked Sendable {

    public static let shared = LogSink(fileURL: AppPaths.logFile)

    private let lock = NSLock()
    private let fileURL: URL
    private var minimumLevel: LogLevel
    private var handle: FileHandle?

    /// 5 MiB per segment, 5 historical segments kept.
    public static let maxSegmentBytes: UInt64 = 5 * 1024 * 1024
    public static let keptSegments = 5

    public init(
        fileURL: URL = AppPaths.logFile,
        minimumLevel: LogLevel? = nil
    ) {
        self.fileURL = fileURL
        #if DEBUG
        self.minimumLevel = minimumLevel ?? .debug
        #else
        self.minimumLevel = minimumLevel ?? .info
        #endif
    }

    public var level: LogLevel {
        lock.lock()
        defer { lock.unlock() }
        return minimumLevel
    }

    /// Applied at startup AND on every settings save (issue #5, #158).
    public func setLevel(_ level: LogLevel) {
        lock.lock()
        minimumLevel = level
        lock.unlock()
    }

    /// `nil` → DEBUG-build default (.debug) / release (.info).
    public func applySettings(_ settings: AppSettings) {
        setLevel(settings.effectiveLogLevel)
    }

    public func shouldLog(_ level: LogLevel) -> Bool {
        level.rank <= { lock.lock(); defer { lock.unlock() }; return minimumLevel }().rank
    }

    // MARK: - Writing

    /// Appends a `YYYY-MM-DD HH:mm:ss.SSS [LEVEL] category: msg` line,
    /// rotating first when the active segment exceeds 5 MiB.
    public func write(level: LogLevel, category: String, message: String) {
        guard shouldLog(level) else { return }
        lock.lock()
        defer { lock.unlock() }
        rotateIfNeeded()
        openIfNeeded()
        let stamp = Self.timestamp()
        let line = "\(stamp) [\(level.rawValue.uppercased())] \(category): \(message)\n"
        if let data = line.data(using: .utf8) {
            handle?.write(data)
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func timestamp() -> String {
        formatter.string(from: Date())
    }

    private func openIfNeeded() {
        guard handle == nil else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        try? handle?.seekToEnd()
    }

    /// Shifts `iccery.log.4→.5`, `.3→.4`, …, `.log→.1` and resets the
    /// writer. Oldest segment is deleted.
    private func rotateIfNeeded() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64,
              size >= Self.maxSegmentBytes
        else { return }

        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        let oldest = fileURL.appendingPathExtension("\(Self.keptSegments)")
        try? fm.removeItem(at: oldest)
        for i in stride(from: Self.keptSegments - 1, through: 1, by: -1) {
            let src = fileURL.appendingPathExtension("\(i)")
            let dst = fileURL.appendingPathExtension("\(i + 1)")
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dst)
            }
        }
        try? fm.moveItem(at: fileURL, to: fileURL.appendingPathExtension("1"))
    }

    /// Tail of the active log for the settings dialog's "copy excerpt".
    public func tailExcerpt(maxBytes: Int = 32 * 1024) -> String {
        guard let data = try? Data(contentsOf: fileURL) else { return "" }
        let slice = data.suffix(maxBytes)
        return String(decoding: slice, as: UTF8.self)
    }
}
