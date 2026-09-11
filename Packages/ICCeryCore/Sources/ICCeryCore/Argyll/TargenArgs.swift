import Foundation

/// Errors during `buildTargenArgs` validation (docs/04 §1.2).
public enum TargenArgError: LocalizedError, Equatable {
    case invalidBasename(String)
    case invalidPatchCount(Int)
    case invalidWhitePatches(Int)
    case invalidBlackPatches(Int)
    case invalidInkLimit(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBasename(let name):
            return "Invalid target basename: \(name)"
        case .invalidPatchCount(let count):
            return "Patch count must be positive, got: \(count)"
        case .invalidWhitePatches(let count):
            return "White patches cannot be negative, got: \(count)"
        case .invalidBlackPatches(let count):
            return "Black patches cannot be negative, got: \(count)"
        case .invalidInkLimit(let limit):
            return "Ink limit must be between 1 and 400, got: \(limit)"
        }
    }
}

/// Pure argv builder for Argyll's `targen` tool (docs/08, docs/04 §1.2).
public enum TargenArgs {

    /// Builds the exact command-line arguments for `targen`.
    ///
    /// Invariants:
    /// - Always starts `-v -d {2|4}` (RGB=2, CMYK=4).
    /// - Never emits `-u` (Argyll fork progress is not enabled for targen).
    /// - Always emits `-f N` when patchCount > 0 (#44).
    /// - White `-e`, Black `-B`.
    /// - `-N` omitted when approximately 0.50.
    /// - `-A` is emitted even at 0.10 (no default-skip).
    /// - `-l` is CMYK only (1...400).
    /// - `-V` omitted when approximately 1.0.
    /// - `-p` omitted when non-positive or approximately 1.0.
    /// - Basename is the last positional argument.
    public static func build(config: TargenConfig) throws -> [String] {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.basename)

        guard config.patchCount > 0 else {
            throw TargenArgError.invalidPatchCount(config.patchCount)
        }
        guard config.whitePatches >= 0 else {
            throw TargenArgError.invalidWhitePatches(config.whitePatches)
        }
        guard config.blackPatches >= 0 else {
            throw TargenArgError.invalidBlackPatches(config.blackPatches)
        }

        var args: [String] = [
            "-v",
            "-d", config.colourSpace.dFlagValue,
            "-f", "\(config.patchCount)",
            "-e", "\(config.whitePatches)",
            "-B", "\(config.blackPatches)"
        ]

        if let g = config.greySteps, g > 0 {
            args.append(contentsOf: ["-g", "\(g)"])
        }
        if let s = config.singleChannelSteps, s > 0 {
            args.append(contentsOf: ["-s", "\(s)"])
        }
        if let n = config.neutralSteps, n > 0 {
            args.append(contentsOf: ["-n", "\(n)"])
        }
        args.append(contentsOf: ArgsBuilder.optionUnlessApprox("-N", config.neutralConcentration, skip: 0.50))
        args.append(contentsOf: ArgsBuilder.optionIfNonEmpty("-c", config.preconditioningProfile))
        args.append(contentsOf: ArgsBuilder.flag("-G", when: config.ofpsHighQuality == true))
        args.append(contentsOf: ArgsBuilder.option("-A", config.ofpsAdaptation.map {
            String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0)
        }))
        if let algFlag = config.fullSpreadAlgorithm?.flag {
            args.append(algFlag)
        }
        if config.colourSpace == .cmyk, let inkLimit = config.totalInkLimit {
            guard (1...400).contains(inkLimit) else {
                throw TargenArgError.invalidInkLimit(inkLimit)
            }
            args.append(contentsOf: ["-l", "\(inkLimit)"])
        }
        args.append(contentsOf: ArgsBuilder.optionUnlessApprox("-V", config.darkEmphasis, skip: 1.0))
        if let p = config.devicePower, p > 0 {
            args.append(contentsOf: ArgsBuilder.optionUnlessApprox("-p", p, skip: 1.0))
        }

        args.append(cleanBasename)
        return args
    }
}
