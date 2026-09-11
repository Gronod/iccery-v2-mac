import AppKit
import Combine
import Foundation
import ICCeryCore

/// Backs the Settings sheet (issue #5). Load → edit → save with
/// validation; the log level is applied live via `LogSink` (#158) and a
/// `settingsDidChange` notification fans out to #20.
@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var settings: AppSettings
    @Published var validationErrors: [String] = []
    @Published var savedFlash = false

    private let store: SettingsStore
    private let sink: LogSink

    init(store: SettingsStore = SettingsStore(), sink: LogSink = .shared) {
        self.store = store
        self.sink = sink
        self.settings = store.load()
    }

    /// Persists after validation. Returns false (and shows inline
    /// errors) when the form is invalid.
    @discardableResult
    func save() -> Bool {
        validationErrors = settings.validate()
        guard validationErrors.isEmpty else { return false }
        do {
            try store.save(settings)
            sink.applySettings(settings)
            savedFlash = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                savedFlash = false
            }
            return true
        } catch {
            validationErrors = ["Could not save settings: \(error.localizedDescription)"]
            return false
        }
    }

    // MARK: - Log helpers

    var logFileURL: URL { AppPaths.logFile }

    func openLogFolder() {
        try? FileManager.default.createDirectory(
            at: AppPaths.logDir, withIntermediateDirectories: true
        )
        NSWorkspace.shared.selectFile(
            AppPaths.logFile.path, inFileViewerRootedAtPath: AppPaths.logDir.path
        )
    }

    func copyLogPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppPaths.logFile.path, forType: .string)
    }

    func copyLogExcerpt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sink.tailExcerpt(), forType: .string)
    }
}
