import Foundation

/// Well-known filesystem locations for the ICCery host process.
///
/// macOS paths (docs/02 §Persistence):
/// - App data: `~/Library/Application Support/<bundle-id>/`
/// - Log file: `~/Library/Logs/<bundle-id>/iccery.log`
/// - Bundled Argyll tools: `<bundle>/Contents/Resources/Argyll/`
public enum AppPaths {

    /// `com.gronod.iccery2` — read from the main bundle so tests can override.
    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.gronod.iccery2"
    }

    /// `~/Library/Application Support/com.gronod.iccery2`
    public static var appDataDir: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    /// `~/Library/Logs/com.gronod.iccery2`
    public static var logDir: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    /// `~/Library/Logs/com.gronod.iccery2/iccery.log`
    public static var logFile: URL {
        logDir.appendingPathComponent("iccery.log", isDirectory: false)
    }

    /// `<app>/Contents/Resources/Argyll` — bundled sidecar root.
    public static var bundledArgyllDir: URL {
        Bundle.main.resourceURL?
            .appendingPathComponent("Argyll", isDirectory: true)
            ?? URL(fileURLWithPath: "/nonexistent")
    }

    /// Creates the app data and log directories if missing.
    @discardableResult
    public static func ensureDirectories() throws -> (appData: URL, logs: URL) {
        let fm = FileManager.default
        try fm.createDirectory(at: appDataDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        return (appDataDir, logDir)
    }
}
