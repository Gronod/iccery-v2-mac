import Foundation

/// Errors during `profcheck` argv construction.
public enum ProfcheckArgError: LocalizedError, Equatable, Sendable {
    case missingTi3
    case missingIcc
    case invalidTi3Path

    public var errorDescription: String? {
        switch self {
        case .missingTi3:
            return "profcheck requires a .ti3 file"
        case .missingIcc:
            return "profcheck requires a profile (.icc/.icm)"
        case .invalidTi3Path:
            return "profcheck .ti3 path is invalid"
        }
    }
}

/// Pure argv builder for Argyll's `profcheck` tool.
public enum ProfcheckArgs {

    /// Builds `profcheck -v -k -s -u {ti3Path} {iccPath}`.
    ///
    /// The `-u` here is the Gronod fork JSON report flag, not the
    /// generic `-u` auto-fix that some Argyll builds use.
    public static func build(config: ProfcheckConfig) throws -> [String] {
        let ti3Path = config.ti3URL.path
        let iccPath = config.iccURL.path

        guard !ti3Path.isEmpty else { throw ProfcheckArgError.missingTi3 }
        guard !iccPath.isEmpty else { throw ProfcheckArgError.missingIcc }

        return ["-v", "-k", "-s", "-u", ti3Path, iccPath]
    }
}
