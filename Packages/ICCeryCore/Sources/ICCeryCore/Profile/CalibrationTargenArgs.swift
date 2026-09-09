import Foundation

/// Errors during calibration `targen` argv construction.
public enum CalibrationTargenArgError: LocalizedError, Equatable, Sendable {
    case invalidBasename(String)
    case invalidSteps(Int)
    case invalidInkLimit(Int)
    case invalidWhitePatches(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBasename(let name):
            return "Invalid calibration basename: \(name)"
        case .invalidSteps(let steps):
            return "Calibration steps must be 11–51, got: \(steps)"
        case .invalidInkLimit(let limit):
            return "Calibration ink limit must be 200–400, got: \(limit)"
        case .invalidWhitePatches(let count):
            return "Calibration white patches cannot be negative, got: \(count)"
        }
    }
}

/// Configuration for a calibration wedge `targen` run.
public struct CalibrationTargenConfig: Sendable, Equatable {
    public var colourSpace: ColourSpace
    public var steps: Int
    public var whitePatches: Int
    public var includeNeutralEmphasis: Bool
    public var inkLimit: Int?
    public var basename: String
    public var workingDirectory: URL?

    public init(
        colourSpace: ColourSpace = .rgb,
        steps: Int = 21,
        whitePatches: Int = 4,
        includeNeutralEmphasis: Bool = false,
        inkLimit: Int? = nil,
        basename: String = "",
        workingDirectory: URL? = nil
    ) {
        self.colourSpace = colourSpace
        self.steps = steps
        self.whitePatches = whitePatches
        self.includeNeutralEmphasis = includeNeutralEmphasis
        self.inkLimit = inkLimit
        self.basename = basename
        self.workingDirectory = workingDirectory
    }
}

/// Pure argv builder for the Stage 0 calibration `targen` chart.
///
/// Produces a per-channel wedge with `-f 0` (no full-spread patches).
public enum CalibrationTargenArgs {

    /// Builds `targen -v -d {2|4} -s N -g N [-n N] -e W [-l TAC] -f 0 CAL_basename`.
    public static func build(config: CalibrationTargenConfig) throws -> [String] {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.basename)

        guard (11...51).contains(config.steps) else {
            throw CalibrationTargenArgError.invalidSteps(config.steps)
        }
        guard config.whitePatches >= 0 else {
            throw CalibrationTargenArgError.invalidWhitePatches(config.whitePatches)
        }

        var args: [String] = [
            "-v",
            "-d", config.colourSpace.dFlagValue,
            "-s", "\(config.steps)",
            "-g", "\(config.steps)",
            "-e", "\(config.whitePatches)",
            "-f", "0"
        ]

        if config.includeNeutralEmphasis {
            args.append(contentsOf: ["-n", "\(config.steps)"])
        }

        if config.colourSpace == .cmyk, let inkLimit = config.inkLimit {
            guard (200...400).contains(inkLimit) else {
                throw CalibrationTargenArgError.invalidInkLimit(inkLimit)
            }
            args.append(contentsOf: ["-l", "\(inkLimit)"])
        }

        let calBasename = cleanBasename.hasPrefix("CAL_") ? cleanBasename : "CAL_\(cleanBasename)"
        args.append(calBasename)
        return args
    }
}
