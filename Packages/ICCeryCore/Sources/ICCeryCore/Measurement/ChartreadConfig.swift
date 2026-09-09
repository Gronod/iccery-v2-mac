import Foundation

/// Errors during `ChartreadArgs` validation.
public enum ChartreadArgError: LocalizedError, Equatable {
    case invalidBasename(String)
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBasename(let name):
            return "Invalid chart basename: \(name)"
        case .invalidPort(let port):
            return "Invalid chartread port: \(port)"
        }
    }
}

/// Configuration for a `chartread` invocation.
public struct ChartreadConfig: Codable, Equatable, Sendable {
    public var basename: String
    public var workingDirectory: URL?
    /// Communication port to pass to `chartread -c`.
    /// `nil` means omit `-c` (Auto or port 1).
    public var selectedPort: Int?
    /// Enable i1Pro 2 visual LEDs (`-Y l`).
    public var enableLEDs: Bool

    public init(
        basename: String,
        workingDirectory: URL? = nil,
        selectedPort: Int? = nil,
        enableLEDs: Bool = false,
        isXY: Bool = false
    ) {
        self.basename = basename
        self.workingDirectory = workingDirectory
        self.selectedPort = selectedPort
        self.enableLEDs = enableLEDs
        self.isXY = isXY
    }

    /// Whether the current config implies an XY-table workflow.
    /// This is normally supplied by the view model from the selected instrument.
    public var isXY: Bool = false
}
