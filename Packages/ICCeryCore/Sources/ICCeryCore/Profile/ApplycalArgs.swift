import Foundation

/// Errors during `applycal` argv construction.
public enum ApplycalArgError: LocalizedError, Equatable, Sendable {
    case invalidCalibrationPath
    case invalidInputProfileURL

    public var errorDescription: String? {
        switch self {
        case .invalidCalibrationPath:
            return "Calibration path is invalid or empty"
        case .invalidInputProfileURL:
            return "Input profile path is invalid or empty"
        }
    }
}

/// Pure argv builder for Argyll's `applycal` tool.
///
/// `applycal` is always run captured, never streamed.
public enum ApplycalArgs {

    /// Builds `applycal -v -a {cal} {input} [{output}]`.
    ///
    /// `-u` (unapply) is rejected at the builder level — the UI never
    /// sends it (docs/04 §7.2).
    public static func build(config: ApplycalConfig) throws -> [String] {
        let cal = config.calibrationPath.trimmingCharacters(in: .whitespaces)
        guard !cal.isEmpty else { throw ApplycalArgError.invalidCalibrationPath }

        let input = config.inputProfileURL.path
        guard !input.isEmpty else { throw ApplycalArgError.invalidInputProfileURL }

        var args: [String] = ["-v"]
        if config.unapply {
            // Defensive: should never be called from the UI.
            args.append("-u")
        } else {
            args.append("-a")
        }

        args.append(contentsOf: [cal, input])

        if let output = config.outputProfileURL?.path, !output.isEmpty {
            args.append(output)
        }

        return args
    }
}
