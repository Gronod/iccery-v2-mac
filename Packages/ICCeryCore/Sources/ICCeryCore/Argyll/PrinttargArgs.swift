import Foundation

/// Errors during `buildPrinttargArgs` validation (docs/04 §2.2).
public enum PrinttargArgError: LocalizedError, Equatable {
    case invalidCustomPageDimension(Double)
    case invalidDPI(Int)
    case invalidSeed(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidCustomPageDimension(let mm):
            return "Custom page dimensions must be at least 50 mm, got: \(mm)"
        case .invalidDPI(let dpi):
            return "TIFF DPI must be between 72 and 600, got: \(dpi)"
        case .invalidSeed(let seed):
            return "Custom layout seed must be ≥ 1, got: \(seed)"
        }
    }
}

/// Pure argv builder for Argyll's `printtarg` tool (docs/09, docs/04 §2.2).
///
/// Contract:
/// ```
/// -v -u -i {instrument} -p {page} [-r | -R seed] [-d label] {-t|-T} {dpi} [-K|-I cal] basename
/// ```
public enum PrinttargArgs {

    /// Builds the exact command-line arguments for `printtarg`.
    ///
    /// Invariants:
    /// - Always `-v -u` (the fork's `-u` emits the JSON page manifest).
    /// - Default layout is deterministic `-R 1` (#163) — a missing seed
    ///   reshuffles patches on every re-run and desyncs print vs `.ti2`.
    /// - `.raster` emits `-r` and supersedes any seed. This is NOT
    ///   targen's `-r` full-spread algorithm (docs/25).
    /// - `-d` is the chart **label** string, not colour space.
    /// - `-K`/`-I` are never emitted for `CAL_` basenames — the
    ///   calibration chart must not embed its own curves.
    /// - Basename is the last positional argument.
    public static func build(config: PrinttargConfig) throws -> [String] {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.basename)

        var args: [String] = [
            "-v", "-u",
            "-i", config.instrument.rawValue,
            "-p", try pageSizeValue(config),
        ]

        switch config.layoutOrder {
        case .deterministic:
            args.append(contentsOf: ["-R", "1"])
        case .customSeed:
            guard config.customSeed >= 1 else {
                throw PrinttargArgError.invalidSeed(config.customSeed)
            }
            args.append(contentsOf: ["-R", "\(config.customSeed)"])
        case .raster:
            args.append("-r")
        }

        if let label = config.label?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            args.append(contentsOf: ["-d", label])
        }

        guard (72...600).contains(config.dpi) else {
            throw PrinttargArgError.invalidDPI(config.dpi)
        }
        args.append(contentsOf: [config.bitDepth.flag, "\(config.dpi)"])

        if !cleanBasename.hasPrefix("CAL_"),
           let cal = config.calibrationFile?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cal.isEmpty {
            args.append(contentsOf: [config.calibrationEmbedOnly ? "-I" : "-K", cal])
        }

        args.append(cleanBasename)
        return args
    }

    private static func pageSizeValue(_ config: PrinttargConfig) throws -> String {
        guard config.pageSize == .custom else { return config.pageSize.rawValue }
        for dim in [config.customPageWidth, config.customPageHeight] {
            guard dim >= 50 else {
                throw PrinttargArgError.invalidCustomPageDimension(dim)
            }
        }
        return "\(formatMM(config.customPageWidth))x\(formatMM(config.customPageHeight))"
    }

    /// Formats millimetres as an integer when exact, else decimal.
    private static func formatMM(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return "\(Int(value))"
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
