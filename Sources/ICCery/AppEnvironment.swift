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
    let cupsService: CupsService
    let historyStore: VerificationHistoryStore
    let mediaStore: MediaLibraryStore

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppEnvironment {
        let settingsStore = SettingsStore()
        var overrideDir = settingsStore.load().argyllBinaryDir
            .map { URL(fileURLWithPath: $0) }
        var bundledRoot = AppPaths.bundledArgyllDir
        var cupsDir = URL(fileURLWithPath: "/usr/bin")
        #if DEBUG
        if let dir = environment["ICCERY_ARGYLL_BINARY_DIR"], !dir.isEmpty {
            overrideDir = URL(fileURLWithPath: dir)
        }
        if let dir = environment["ICCERY_ARGYLL_BUNDLED_ROOT"], !dir.isEmpty {
            bundledRoot = URL(fileURLWithPath: dir)
        }
        if let dir = environment["ICCERY_CUPS_BIN_DIR"], !dir.isEmpty {
            cupsDir = URL(fileURLWithPath: dir)
        }
        #endif
        return AppEnvironment(
            stateStore: WizardStateStore(),
            settingsStore: settingsStore,
            presetStore: PresetStore(settingsStore: settingsStore),
            runner: ArgyllRunner(
                processManager: .shared,
                binaryResolver: BinaryResolver(
                    bundledRoot: bundledRoot, overrideDir: overrideDir)
            ),
            cupsService: CupsService(
                processManager: .shared,
                binaryDir: cupsDir),
            historyStore: VerificationHistoryStore(),
            mediaStore: MediaLibraryStore()
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
    /// Dataset import file (`.ti3`, `.txt`, `.cgats`, `.csv`).
    static var datasetImportURL: URL? { url("ICCERY_TEST_DATASET_IMPORT") }
    /// Preset import file.
    static var presetImportURL: URL? { url("ICCERY_TEST_PRESET_IMPORT") }
    /// Preset export destination.
    static var presetExportURL: URL? { url("ICCERY_TEST_PRESET_EXPORT") }
    /// Spot-read CSV export destination (`selectCsvSavePath`, #148).
    static var csvExportURL: URL? { url("ICCERY_TEST_CSV_EXPORT") }

    // MARK: - Print panel / CUPS stubs (issue 13/17)

    /// Directory of mock `lp`/`lpstat`/`lpoptions` fixture scripts —
    /// `CupsService.binaryDir` under UI tests.
    static var cupsBinaryDir: URL? { url("ICCERY_CUPS_BIN_DIR") }

    /// Path the mock `lp` script appends its argv to, for assertions.
    static var lpArgvOutURL: URL? { url("ICCERY_TEST_LP_ARGV") }

    /// Whether the `NSPrintPanel` should be stubbed under UI testing —
    /// separate from the stub's *result* so "cancel" (`nil`) does not
    /// fall through to the real modal.
    static var printPanelStubbed: Bool { isEnabled }

    /// Canned `NSPrintPanel` outcome — XCUITest cannot drive the
    /// system modal. `ICCERY_TEST_PRINT_PANEL`:
    /// - `cancel` (or unset while testing) → user cancelled → `nil`
    /// - `ok` → `PrintPropertiesResult` with
    ///   `ICCERY_TEST_PANEL_OPTIONS` (captured `k=v` string) and
    ///   `ICCERY_TEST_PANEL_PRINTER` (selected queue; default = the
    ///   queue the panel was opened for).
    static func printPanelResult(forQueue queue: String) -> PrintPropertiesResult? {
        switch env["ICCERY_TEST_PRINT_PANEL"] {
        case "ok":
            let options = env["ICCERY_TEST_PANEL_OPTIONS"].flatMap {
                $0.isEmpty ? nil : $0
            }
            return PrintPropertiesResult(
                selectedPrinter: env["ICCERY_TEST_PANEL_PRINTER"].flatMap {
                    $0.isEmpty ? nil : $0
                } ?? queue,
                options: PrintOptions(
                    mediaType: options.flatMap {
                        CupsParsers.extractMediaType(fromOptionsString: $0)
                    },
                    ppdUncorrectedPassthrough: true,
                    cupsOptions: options))
        default:
            return nil
        }
    }

    private static func url(_ key: String) -> URL? {
        guard let raw = env[key], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw)
    }
}
