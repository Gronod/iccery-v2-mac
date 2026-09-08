import Foundation
import OSLog

/// Severity levels, matching the v1 `log_level` setting values.
public enum LogLevel: String, Codable, Sendable, CaseIterable {
    case error, warn, info, debug, trace

    var osType: OSLogType {
        switch self {
        case .error: return .error
        case .warn:  return .default
        case .info:  return .info
        case .debug: return .debug
        case .trace: return .debug
        }
    }

    /// Lower rank = more severe. `shouldLog` keeps `rank <= min`.
    var rank: Int {
        switch self {
        case .error: return 0
        case .warn:  return 1
        case .info:  return 2
        case .debug: return 3
        case .trace: return 4
        }
    }
}

/// Central logger: `os.Logger` + rolling file sink (`LogSink`), level
/// gated at write time so a settings save takes effect immediately
/// (#158).
public struct AppLogger: Sendable {
    public static let shared = AppLogger(category: "app")

    private let osLog: Logger
    private let sink: LogSink
    public let category: String

    public init(category: String, sink: LogSink = .shared) {
        self.category = category
        self.sink = sink
        self.osLog = Logger(
            subsystem: AppPaths.bundleIdentifier,
            category: category
        )
    }

    public func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        let text = LogSanitizer.sanitize(message())
        if level.rank <= sink.level.rank {
            osLog.log(level: level.osType, "\(text, privacy: .public)")
        }
        sink.write(level: level, category: category, message: text)
    }

    public func error(_ message: @autoclosure () -> String) { log(.error, message()) }
    public func warn(_ message: @autoclosure () -> String) { log(.warn, message()) }
    public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    public func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    public func trace(_ message: @autoclosure () -> String) { log(.trace, message()) }
}
