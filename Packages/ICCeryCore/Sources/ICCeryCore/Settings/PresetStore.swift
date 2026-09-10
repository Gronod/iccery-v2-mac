import Foundation

/// CRUD + import/export for profiling presets on top of `SettingsStore`
/// (docs/22 §Built-in presets, issue #11).
///
/// - `all()` = built-ins overlaid by custom presets (by `id`).
/// - Built-ins are never written to `settings.json` and cannot be
///   deleted or overwritten by `saveCustom` (a custom id that collides
///   with a built-in still overlays at read time, per spec).
/// - Import/export is single-preset JSON with schema validation.
/// - Imported names/descriptions are untrusted: callers must render
///   them with `Text`, never HTML (#114).
public final class PresetStore: Sendable {

    public let settingsStore: SettingsStore

    public init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
    }

    /// All presets: built-ins overlaid by customs, catalog order.
    public func all() -> [ProfilingPreset] {
        PresetCatalog.all(custom: settingsStore.load().customPresets)
    }

    /// Custom presets only, as persisted.
    public func customs() -> [ProfilingPreset] {
        settingsStore.load().customPresets
    }

    /// Insert or replace a custom preset (matched by `id`). Throws
    /// `PresetStoreError.builtIn` when the id belongs to a built-in —
    /// built-ins are immutable. Validates before persisting.
    public func saveCustom(_ preset: ProfilingPreset) throws {
        let validated = try preset.validated()
        guard !PresetCatalog.isBuiltIn(validated.id) else {
            throw PresetStoreError.builtInImmutable(validated.id)
        }
        var settings = settingsStore.load()
        if let idx = settings.customPresets.firstIndex(where: { $0.id == validated.id }) {
            settings.customPresets[idx] = validated
        } else {
            settings.customPresets.append(validated)
        }
        try settingsStore.save(settings)
    }

    /// Deletes a custom preset by id. Returns false when the id is a
    /// built-in (undeletable) or no custom preset with that id exists.
    @discardableResult
    public func deleteCustom(id: String) throws -> Bool {
        guard !PresetCatalog.isBuiltIn(id) else { return false }
        var settings = settingsStore.load()
        let before = settings.customPresets.count
        settings.customPresets.removeAll { $0.id == id }
        guard settings.customPresets.count != before else { return false }
        try settingsStore.save(settings)
        return true
    }

    /// Single-preset pretty JSON export.
    public func export(_ preset: ProfilingPreset) throws -> Data {
        return try JSONEncoder.icceryPretty().encode(preset)
    }

    /// Parses + validates a preset from JSON. The preset is assigned a
    /// fresh custom id when its id is empty or collides with a built-in.
    /// Does **not** persist — call `saveCustom` to keep it.
    public func `import`(_ data: Data) throws -> ProfilingPreset {
        let decoded: ProfilingPreset
        do {
            decoded = try JSONDecoder().decode(ProfilingPreset.self, from: data)
        } catch {
            throw PresetStoreError.invalidJSON(error.localizedDescription)
        }
        var preset = try decoded.validated()
        if preset.id.isEmpty || PresetCatalog.isBuiltIn(preset.id) {
            preset.id = "custom-\(UUID().uuidString.lowercased())"
        }
        return preset
    }

    public enum PresetStoreError: LocalizedError, Equatable {
        case builtInImmutable(String)
        case invalidJSON(String)

        public var errorDescription: String? {
            switch self {
            case .builtInImmutable(let id):
                return "Built-in preset \"\(id)\" cannot be modified or deleted."
            case .invalidJSON(let reason):
                return "Not a valid preset file: \(reason)"
            }
        }
    }
}
