import Foundation

/// Basename sanitisation and safe working-directory resolution
/// (docs/02 §Working directory, docs/06 §Empty cwd).
public enum PathSecurity {

    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidBasename(String)
    }

    /// Basenames must not contain `/`, `\`, or `..` and must be
    /// non-empty. Never invent a default basename (#60).
    public static func isValidBasename(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return !name.contains("/") && !name.contains("\\") && !name.contains("..")
    }

    @discardableResult
    public static func sanitizeBasename(_ name: String) throws -> String {
        guard isValidBasename(name) else {
            throw Error.invalidBasename(name)
        }
        return name
    }

    /// `resolve_safe_cwd` (docs/04 §0.2): explicit real directory →
    /// Documents → Home → app-data. Never returns an empty/nil cwd.
    public static func resolveSafeCwd(
        _ explicit: URL?,
        fileManager: FileManager = .default
    ) -> URL {
        if let explicit,
           fileManager.fileExists(atPath: explicit.path, isDirectory: nil) {
            return explicit
        }
        let candidates: [URL?] = [
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.homeDirectoryForCurrentUser,
            AppPaths.appDataDir,
        ]
        for candidate in candidates {
            guard let url = candidate else { continue }
            if !fileManager.fileExists(atPath: url.path) {
                try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: url.path, isDirectory: nil) {
                return url
            }
        }
        // Last resort: app-data, created unconditionally.
        try? fileManager.createDirectory(at: AppPaths.appDataDir, withIntermediateDirectories: true)
        return AppPaths.appDataDir
    }
}
