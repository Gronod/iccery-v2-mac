import Foundation

/// Errors during `iccgamut` argv construction.
public enum IccgamutArgError: LocalizedError, Equatable, Sendable {
    case invalidProfileURL

    public var errorDescription: String? {
        switch self {
        case .invalidProfileURL:
            return "iccgamut requires a valid profile path"
        }
    }
}

/// Pure argv builder for Argyll's `iccgamut` tool.
public enum IccgamutArgs {

    /// Builds `iccgamut -v -d {density} {profilePath}`.
    ///
    /// The caller is responsible for ensuring `density` is a positive
    /// integer. `-d` here is surface **density**, not a directory.
    public static func build(config: IccgamutConfig) throws -> [String] {
        let path = config.profileURL.path
        guard !path.isEmpty else { throw IccgamutArgError.invalidProfileURL }

        let density = max(1, config.density)
        return ["-v", "-d", "\(density)", path]
    }
}
