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
    ///
    /// DEBUG only: `ICCERY_TEST_ROOT` or `ICCERY_TEST_WORKDIR` redirect app
    /// data so UI tests run against an isolated root and never touch the
    /// developer's state.
    public static var appDataDir: URL {
        #if DEBUG
        if let root = testRoot {
            return root.appendingPathComponent("AppData", isDirectory: true)
        }
        #endif
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    /// `~/Library/Logs/com.gronod.iccery2`
    public static var logDir: URL {
        #if DEBUG
        if let root = testRoot {
            return root.appendingPathComponent("Logs", isDirectory: true)
        }
        #endif
        return FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    #if DEBUG
    /// DEBUG-only root override. Order:
    /// 1. `ICCERY_TEST_ROOT` for an explicit test root.
    /// 2. `ICCERY_TEST_WORKDIR` so the app data and log files live next to
    ///    the current UI test's working directory.
    /// 3. `ICCERY_UI_TESTING=1` creates a per-process temp root so a UI test
    ///    that sets neither of the above still runs in isolation.
    ///
    /// Computed from `ProcessInfo` each call — no mutable static state.
    private static var testRoot: URL? {
        if let raw = ProcessInfo.processInfo.environment["ICCERY_TEST_ROOT"],
           !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        if let raw = ProcessInfo.processInfo.environment["ICCERY_TEST_WORKDIR"],
           !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        if ProcessInfo.processInfo.environment["ICCERY_UI_TESTING"] == "1" {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "iccery-ui-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
        }
        return nil
    }
    #endif

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
