import Foundation

/// Events on the process bus — the v2 equivalent of the v1 Tauri events
/// `process:stdout|stderr|exit|error|json_row` (docs/02 §Event bus).
public enum ProcessEvent: Sendable, Equatable {
    /// Non-JSON stdout line. (`process:stdout`)
    case stdout(id: String, line: String)
    /// stderr line. (`process:stderr`)
    case stderr(id: String, line: String)
    /// Child exited; 0 = success. (`process:exit`)
    case exit(id: String, code: Int32)
    /// Spawn failure. (`process:error`)
    case error(id: String, message: String)
    /// Stdout line began with `ROW_COLORS_JSON: ` — prefix stripped,
    /// payload is the remaining raw bytes. (`process:json_row`)
    case jsonRow(id: String, payload: Data)

    public var id: String {
        switch self {
        case .stdout(let id, _), .stderr(let id, _), .exit(let id, _),
             .error(let id, _), .jsonRow(let id, _):
            return id
        }
    }
}

public enum ProcessError: Error, Equatable, Sendable {
    /// A child with this id is still running (#116).
    case duplicateID(String)
    /// No child registered under this id.
    case unknownID(String)
    /// Process refused to launch.
    case spawnFailed(String)
    /// stdin write failed (pipe closed / process gone).
    case stdinFailed(String)
}

extension ProcessError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .duplicateID(let id):
            return "Process already running: \(id)"
        case .unknownID(let id):
            return "Unknown process: \(id)"
        case .spawnFailed(let detail):
            return "Could not launch \(detail)"
        case .stdinFailed(let detail):
            return "stdin failed: \(detail)"
        }
    }
}
