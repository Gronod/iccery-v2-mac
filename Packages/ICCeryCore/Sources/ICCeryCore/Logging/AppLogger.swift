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

/// Central logger. For M1 PR2 this writes to `os.Logger` only;
/// issue #5 adds the rolling file sink and runtime `setLevel`.
public struct AppLogger: Sendable {
    public static let shared = AppLogger(category: "app")

    private let osLog: Logger
    public let category: String

    public init(category: String) {
        self.category = category
        self.osLog = Logger(
            subsystem: AppPaths.bundleIdentifier,
            category: category
        )
    }

    public func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        let text = LogSanitizer.sanitize(message())
        osLog.log(level: level.osType, "\(text, privacy: .public)")
    }

    public func error(_ message: @autoclosure () -> String) { log(.error, message()) }
    public func warn(_ message: @autoclosure () -> String) { log(.warn, message()) }
    public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    public func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    public func trace(_ message: @autoclosure () -> String) { log(.trace, message()) }
}
