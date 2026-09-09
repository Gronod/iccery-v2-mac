import Foundation

/// Errors thrown by `ProfileInstaller`.
public enum ProfileInstallError: LocalizedError, Equatable, Sendable {
    case unsafeStem(String)
    case sourceMissing
    case sourceNotProfile
    case sourceTooSmall
    case systemRequiresAdminRights
    case copyFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsafeStem(let stem):
            return "Profile name contains unsafe characters: \(stem)"
        case .sourceMissing:
            return "Source profile does not exist"
        case .sourceNotProfile:
            return "Source must be a .icc or .icm file"
        case .sourceTooSmall:
            return "Source file is too small to be a valid profile"
        case .systemRequiresAdminRights:
            return "Installing to /Library/ColorSync/Profiles requires administrator rights"
        case .copyFailed(let reason):
            return "Could not install profile: \(reason)"
        case .cancelled:
            return "Install cancelled"
        }
    }
}

/// Installs an ICC/ICM profile into the OS colour store.
public enum ProfileInstaller {

    /// Installs `sourceURL` into `~/Library/ColorSync/Profiles` or
    /// `/Library/ColorSync/Profiles`. Always copies, never moves.
    public static func install(config: InstallProfileConfig) throws -> InstallProfileResult {
        let fm = FileManager.default

        // Source validation.
        let sourceURL = config.sourceURL
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw ProfileInstallError.sourceMissing
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "icc" || ext == "icm" else {
            throw ProfileInstallError.sourceNotProfile
        }

        let attrs = try? fm.attributesOfItem(atPath: sourceURL.path)
        let size = attrs?[.size] as? UInt64 ?? 0
        guard size >= 128 else {
            throw ProfileInstallError.sourceTooSmall
        }

        // Stem security.
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        guard !stem.contains("..") && !stem.contains("/") && !stem.contains("\\") else {
            throw ProfileInstallError.unsafeStem(stem)
        }

        // Destination directory.
        let destDir: URL
        if config.options.preferSystem {
            destDir = URL(fileURLWithPath: "/Library/ColorSync/Profiles")
        } else {
            let home = fm.homeDirectoryForCurrentUser
            destDir = home.appendingPathComponent("Library/ColorSync/Profiles")
        }

        // Ensure parent exists.
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destURL = destDir.appendingPathComponent("\(stem).icc")

        // Collision resolution.
        let destExists = fm.fileExists(atPath: destURL.path)
        if destExists {
            if config.options.forceOverwrite {
                // Continue to overwrite path.
            } else if config.options.collisionPolicy == .rename {
                let epoch = Int(Date().timeIntervalSince1970)
                let renamedURL = destDir.appendingPathComponent("\(stem)-\(epoch).icc")
                return try performInstall(
                    from: sourceURL,
                    to: renamedURL,
                    options: config.options,
                    overwritten: false,
                    renamed: true
                )
            } else if config.options.collisionPolicy == .cancel {
                throw ProfileInstallError.cancelled
            } else {
                // Default with askBeforeOverwrite — the app must decide.
                throw ProfileInstallError.copyFailed("destination already exists")
            }
        }

        return try performInstall(
            from: sourceURL,
            to: destURL,
            options: config.options,
            overwritten: destExists,
            renamed: false
        )
    }

    private static func performInstall(
        from sourceURL: URL,
        to destURL: URL,
        options: InstallProfileOptions,
        overwritten: Bool,
        renamed: Bool
    ) throws -> InstallProfileResult {
        let fm = FileManager.default
        let tmpURL = destURL.appendingPathExtension("iccery-install.tmp")

        // Remove stale tmp.
        try? fm.removeItem(at: tmpURL)

        do {
            try fm.copyItem(at: sourceURL, to: tmpURL)

            if fm.fileExists(atPath: destURL.path) {
                _ = try fm.replaceItemAt(destURL, withItemAt: tmpURL)
            } else {
                try fm.moveItem(at: tmpURL, to: destURL)
            }
        } catch {
            try? fm.removeItem(at: tmpURL)

            // Surface a clear admin-rights hint when writing to system.
            if destURL.path.hasPrefix("/Library/") && !fm.fileExists(atPath: destURL.path) {
                throw ProfileInstallError.systemRequiresAdminRights
            }
            throw ProfileInstallError.copyFailed(error.localizedDescription)
        }

        let registered = fm.fileExists(atPath: destURL.path)

        var openedPanel = false
        if options.openColorPanel {
            openedPanel = openColorSyncUtility()
        }

        return InstallProfileResult(
            destPath: destURL.path,
            registered: registered,
            overwritten: overwritten,
            renamed: renamed,
            openedPanel: openedPanel,
            message: "Profile installed to \(destURL.path)",
            calibrationNote: options.calibrationNote
        )
    }

    private static func openColorSyncUtility() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "ColorSync Utility"]
        task.environment = ["ARGYLL_NOT_INTERACTIVE": "1"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        return true
    }
}
