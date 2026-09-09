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

    /// Resolves the destination URL that `install` would write to for the
    /// given source and options, without copying anything. Useful for
    /// collision previews in the UI.
    public static func resolveDestinationURL(
        for config: InstallProfileConfig,
        fileManager: FileManager = .default
    ) throws -> URL {
        let sourceURL = config.sourceURL
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "icc" || ext == "icm" else {
            throw ProfileInstallError.sourceNotProfile
        }

        try validateSourceURL(sourceURL)

        let destDir = destinationDirectory(for: config.options, fileManager: fileManager)
        return destDir.appendingPathComponent(sourceURL.lastPathComponent)
    }

    /// Installs `sourceURL` into `~/Library/ColorSync/Profiles` or
    /// `/Library/ColorSync/Profiles`. Always copies, never moves.
    public static func install(
        config: InstallProfileConfig,
        fileManager: FileManager = .default
    ) throws -> InstallProfileResult {
        let fm = fileManager

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

        try validateSourceURL(sourceURL)

        // Destination directory.
        let destURL = try resolveDestinationURL(for: config, fileManager: fm)
        try? fm.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Collision resolution.
        let destExists = fm.fileExists(atPath: destURL.path)
        if destExists {
            if config.options.forceOverwrite {
                return try performInstall(
                    from: sourceURL,
                    to: destURL,
                    options: config.options,
                    fileManager: fm,
                    overwritten: true,
                    renamed: false
                )
            } else if config.options.collisionPolicy == .rename {
                let epoch = Int(Date().timeIntervalSince1970)
                let stem = sourceURL.deletingPathExtension().lastPathComponent
                let renamedURL = destURL.deletingLastPathComponent()
                    .appendingPathComponent("\(stem)-\(epoch).\(ext)")
                return try performInstall(
                    from: sourceURL,
                    to: renamedURL,
                    options: config.options,
                    fileManager: fm,
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
            fileManager: fm,
            overwritten: false,
            renamed: false
        )
    }

    // MARK: - Private helpers

    private static func validateSourceURL(_ sourceURL: URL) throws {
        let path = sourceURL.path
        let stem = sourceURL.deletingPathExtension().lastPathComponent

        // Reject backslashes anywhere in the path.
        guard !path.contains("\\") else {
            throw ProfileInstallError.unsafeStem(stem)
        }

        // Reject any path component that is literally "." or "..".
        // This allows names like "foo..bar" while blocking real traversal.
        for component in sourceURL.pathComponents {
            if component == "." || component == ".." {
                throw ProfileInstallError.unsafeStem(stem)
            }
        }
    }

    private static func destinationDirectory(
        for options: InstallProfileOptions,
        fileManager: FileManager
    ) -> URL {
        if options.preferSystem {
            return URL(fileURLWithPath: "/Library/ColorSync/Profiles")
        } else {
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/ColorSync/Profiles")
        }
    }

    private static func performInstall(
        from sourceURL: URL,
        to destURL: URL,
        options: InstallProfileOptions,
        fileManager: FileManager,
        overwritten: Bool,
        renamed: Bool
    ) throws -> InstallProfileResult {
        let fm = fileManager
        let tmpURL = destURL.appendingPathExtension("iccery-install.tmp")

        // Remove stale tmp.
        try? fm.removeItem(at: tmpURL)

        do {
            try fm.copyItem(at: sourceURL, to: tmpURL)

            let attrs = try? fm.attributesOfItem(atPath: tmpURL.path)
            let tmpSize = attrs?[.size] as? UInt64 ?? 0
            guard tmpSize >= 128 else {
                try? fm.removeItem(at: tmpURL)
                throw ProfileInstallError.sourceTooSmall
            }

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

            if let installError = error as? ProfileInstallError {
                throw installError
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
