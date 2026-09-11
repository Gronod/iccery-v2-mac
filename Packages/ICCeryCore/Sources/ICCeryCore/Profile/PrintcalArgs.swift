import Foundation

/// Errors during `printcal` argv construction.
public enum PrintcalArgError: LocalizedError, Equatable, Sendable {
    case invalidBasename(String)
    case invalidTotalInkLimit(Double)
    case invalidPerChannelLimit(Character, Double)
    case invalidOutputPath

    public var errorDescription: String? {
        switch self {
        case .invalidBasename(let name):
            return "Invalid calibration basename: \(name)"
        case .invalidTotalInkLimit(let limit):
            return "Total ink limit must be positive, got: \(limit)"
        case .invalidPerChannelLimit(let channel, let limit):
            return "\(channel) channel limit must be 0–100, got: \(limit)"
        case .invalidOutputPath:
            return "Invalid .cal output path"
        }
    }
}

/// Per-channel ink limit for `printcal -x{C|M|Y|K} pct`.
public struct PrintcalChannelLimit: Sendable, Equatable {
    public let channel: Character
    public let percent: Double

    public init(channel: Character, percent: Double) {
        self.channel = channel
        self.percent = percent
    }
}

/// Configuration for an Argyll `printcal` run.
public struct PrintcalConfig: Sendable, Equatable {
    public var ti3Basename: String
    public var workingDirectory: URL?
    public var outputURL: URL
    public var noInkLimit: Bool
    public var verify: Bool
    public var previousCalPath: String?
    public var totalInkLimit: Double?
    public var channelLimits: [PrintcalChannelLimit]

    public init(
        ti3Basename: String,
        workingDirectory: URL? = nil,
        outputURL: URL,
        noInkLimit: Bool = false,
        verify: Bool = false,
        previousCalPath: String? = nil,
        totalInkLimit: Double? = nil,
        channelLimits: [PrintcalChannelLimit] = []
    ) {
        self.ti3Basename = ti3Basename
        self.workingDirectory = workingDirectory
        self.outputURL = outputURL
        self.noInkLimit = noInkLimit
        self.verify = verify
        self.previousCalPath = previousCalPath
        self.totalInkLimit = totalInkLimit
        self.channelLimits = channelLimits
    }
}

/// Pure argv builder for Argyll's `printcal` tool.
///
/// `printcal` is captured, not streamed. JS never sends `-u` (unapply).
public enum PrintcalArgs {

    /// Builds `printcal -v -e [-I] [-z] [-a previous.cal] [-m TAC]
    /// [-xC pct]... -o out.cal CAL_basename`.
    public static func build(config: PrintcalConfig) throws -> [String] {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.ti3Basename)
        guard !cleanBasename.isEmpty else {
            throw PrintcalArgError.invalidBasename(config.ti3Basename)
        }

        var args: [String] = ["-v", "-e"]

        args.append(contentsOf: ArgsBuilder.flag("-I", when: config.noInkLimit))
        args.append(contentsOf: ArgsBuilder.flag("-z", when: config.verify))
        args.append(contentsOf: ArgsBuilder.optionIfNonEmpty("-a", config.previousCalPath))
        if let tac = config.totalInkLimit, tac > 0 {
            args.append(contentsOf: ["-m", String(format: "%.1f", tac)])
        } else if let tac = config.totalInkLimit {
            throw PrintcalArgError.invalidTotalInkLimit(tac)
        }

        for limit in config.channelLimits {
            guard (0...100).contains(limit.percent) else {
                throw PrintcalArgError.invalidPerChannelLimit(limit.channel, limit.percent)
            }
            args.append(contentsOf: ["-x\(limit.channel)", String(format: "%.1f", limit.percent)])
        }

        guard !config.outputURL.path.isEmpty else {
            throw PrintcalArgError.invalidOutputPath
        }
        args.append(contentsOf: ["-o", config.outputURL.path])

        let calBasename = CalibrationIdentity.prefix(cleanBasename)
        args.append(calBasename)
        return args
    }
}
