import Foundation

/// Persists `AppSettings` to
/// `~/Library/Application Support/com.gronod.iccery2/settings.json`
/// (issue #5 — the v1 path is never read).
///
/// Writes are atomic (`AtomicFileWriter`). Invalid/corrupt JSON falls
/// back to defaults. Saving posts `settingsDidChange` so #20 can
/// reclassify swatches.
public final class SettingsStore: Sendable {

    /// Posted on `NotificationCenter.default` after every successful save.
    public static let settingsDidChange =
        Notification.Name("com.gronod.iccery2.settingsDidChange")

    public let fileURL: URL

    public init(fileURL: URL = AppPaths.appDataDir.appendingPathComponent("settings.json")) {
        self.fileURL = fileURL
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    /// Validates before persisting — throws `SettingsError` listing
    /// every violation; nothing is written on failure.
    public func save(_ settings: AppSettings) throws {
        let errors = settings.validate()
        guard errors.isEmpty else {
            throw SettingsError.validationFailed(errors)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFileWriter.write(encoder.encode(settings), to: fileURL)
        NotificationCenter.default.post(name: Self.settingsDidChange, object: nil)
    }

    public enum SettingsError: Error, Equatable {
        case validationFailed([String])
    }
}
