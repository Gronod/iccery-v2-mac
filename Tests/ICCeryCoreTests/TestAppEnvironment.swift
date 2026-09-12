import Foundation
@testable import ICCeryCore
@testable import ICCery

/// Shared app-test dependency factory (issue #82).
///
/// Every store is pointed at a unique temporary directory so tests never
/// read or write the user's real Application Support tree, and a fresh
/// `ProcessManager` keeps child-process state isolated per test. The
/// global process environment is never mutated.
struct TestAppEnvironment {

    /// Root temp directory holding all per-test state files.
    let root: URL
    let environment: AppEnvironment

    var settingsURL: URL { root.appendingPathComponent("settings.json") }
    var stateURL: URL { root.appendingPathComponent("wizard_state.json") }
    var historyURL: URL {
        root.appendingPathComponent("verification_history.json")
    }
    var mediaLibraryURL: URL {
        root.appendingPathComponent("media_library.json")
    }

    /// Creates an isolated environment under `NSTemporaryDirectory()`.
    /// Call `cleanup()` when finished.
    static func make() throws -> TestAppEnvironment {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-test-env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )

        let processManager = ProcessManager()
        let settingsStore = SettingsStore(
            fileURL: root.appendingPathComponent("settings.json")
        )
        let environment = AppEnvironment(
            stateStore: WizardStateStore(
                fileURL: root.appendingPathComponent("wizard_state.json")
            ),
            settingsStore: settingsStore,
            presetStore: PresetStore(settingsStore: settingsStore),
            runner: ArgyllRunner(
                processManager: processManager,
                binaryResolver: BinaryResolver(overrideDir: nil)
            ),
            cupsService: CupsService(
                processManager: processManager,
                binaryDir: root.appendingPathComponent("cups-bin")
            ),
            historyStore: VerificationHistoryStore(
                url: root.appendingPathComponent("verification_history.json")
            ),
            mediaStore: MediaLibraryStore(
                url: root.appendingPathComponent("media_library.json")
            )
        )
        return TestAppEnvironment(root: root, environment: environment)
    }

    /// Removes the temporary root directory.
    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
