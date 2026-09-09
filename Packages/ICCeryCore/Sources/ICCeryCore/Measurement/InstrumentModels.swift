import Foundation

/// A device discovered by the Argyll `instlist` fork.
public struct InstrumentDevice: Codable, Sendable, Equatable, Identifiable {
    public let port: Int
    public let name: String
    public let type: String

    public init(port: Int, name: String, type: String) {
        self.port = port
        self.name = name
        self.type = type
    }

    public var id: Int { port }

    /// XY tables are identified by name or type matching the fork pattern.
    public var isXY: Bool {
        let combined = "\(name) \(type)".lowercased()
        let pattern = #"/spectro\s?scan|i1io/"#
        return combined.range(of: pattern, options: .regularExpression) != nil
    }

    /// Human-readable label shown in the picker.
    public var displayName: String {
        let xyTag = isXY ? " · XY Table" : ""
        return "\(name) [\(type)]\(xyTag)"
    }
}

/// The user’s choice for a chartread session.
public enum InstrumentSelection: Sendable, Equatable {
    /// Auto / first available port — `chartread` omits `-c`.
    case auto
    /// A concrete instrument.
    case device(InstrumentDevice)

    /// The value to pass to `chartread -c`.
    /// `nil` means omit `-c` (port 1 and Auto both map to no flag).
    public var chartreadPort: Int? {
        switch self {
        case .auto:
            return nil
        case .device(let device):
            return device.port == 1 ? nil : device.port
        }
    }

    /// Whether the current selection implies an XY table workflow.
    public var isXY: Bool {
        switch self {
        case .auto:
            return false
        case .device(let device):
            return device.isXY
        }
    }
}
