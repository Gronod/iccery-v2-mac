import Foundation
import ICCeryCore

/// App dependency container (docs/02). Production builds resolve the
/// user's `argyll_binary_dir` override or bundled sidecars; DEBUG UI
/// tests inject fixture binaries via `ICCERY_ARGYLL_BINARY_DIR` and
/// redirect `AppPaths` via `ICCERY_TEST_ROOT`, so tests never touch the
/// developer's settings, wizard state, or real Argyll install.
struct AppEnvironment: Sendable {
    let stateStore: WizardStateStore
    let settingsStore: SettingsStore
    let presetStore: PresetStore
    let runner: ArgyllRunner

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppEnvironment {
        let settingsStore = SettingsStore()
        var overrideDir = settingsStore.load().argyllBinaryDir
            .map { URL(fileURLWithPath: $0) }
        #if DEBUG
        if let dir = environment["ICCERY_ARGYLL_BINARY_DIR"], !dir.isEmpty {
            overrideDir = URL(fileURLWithPath: dir)
        }
        #endif
        return AppEnvironment(
            stateStore: WizardStateStore(),
            settingsStore: settingsStore,
            presetStore: PresetStore(settingsStore: settingsStore),
            runner: ArgyllRunner(
                processManager: .shared,
                binaryResolver: BinaryResolver(overrideDir: overrideDir)
            )
        )
    }
}

/// DEBUG-only UI-test hooks. When `ICCERY_UI_TESTING=1` the workflow
/// honours these env-provided paths instead of presenting modal panels
/// (XCUITest cannot drive NSOpenPanel/NSSavePanel reliably). These are
/// compiled out of release builds.
enum UITestHooks {
    private static var env: [String: String] {
        ProcessInfo.processInfo.environment
    }

    static var isEnabled: Bool {
        #if DEBUG
        return env["ICCERY_UI_TESTING"] == "1"
        #else
        return false
        #endif
    }

    /// `select_target_file` result (Stage 1 save picker).
    static var saveTargetURL: URL? { url("ICCERY_TEST_SAVE_TARGET") }
    /// `select_existing_target` result (`.ti1`/`.ti2` resume).
    static var existingTargetURL: URL? { url("ICCERY_TEST_EXISTING_TARGET") }
    /// `select_directory` result (working-directory browse).
    static var workDirURL: URL? { url("ICCERY_TEST_WORKDIR") }
    /// Preset import file.
    static var presetImportURL: URL? { url("ICCERY_TEST_PRESET_IMPORT") }
    /// Preset export destination.
    static var presetExportURL: URL? { url("ICCERY_TEST_PRESET_EXPORT") }

    private static func url(_ key: String) -> URL? {
        guard let raw = env[key], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw)
    }
}
