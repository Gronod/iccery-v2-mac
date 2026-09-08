import AppKit
import UniformTypeIdentifiers

/// Dedicated NSOpenPanel / NSSavePanel wrappers (issue #6) — one method
/// per purpose, matching the v1 `select_*` commands (docs/21 §Dialogs).
/// No call site shares a generic picker (#103/#210/#211).
@MainActor
final class FileDialogService {

    static let shared = FileDialogService()
    private init() {}

    // MARK: - selectDirectory

    /// `#btnBrowse` — working directory for Argyll artefacts.
    /// Defaults to Documents (docs/06 §Empty cwd).
    func selectDirectory(startingAt start: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        panel.prompt = "Choose"
        return run(panel)
    }

    // MARK: - Dedicated open pickers

    /// `selectTargetFile` — **save** panel for the new `.ti1` target.
    func selectTargetFile(startingAt start: URL? = nil) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "target.ti1"
        panel.allowedContentTypes = utTypes(["ti1"])
        panel.allowsOtherFileTypes = false
        panel.directoryURL = start
        panel.message = "Choose the .ti1 target file to create"
        return run(panel)
    }

    /// `selectExistingTarget` — open `.ti1`/`.ti2` (docs/06 §Resume, #140).
    func selectExistingTarget(startingAt start: URL? = nil) -> URL? {
        open(extensions: ["ti1", "ti2"], startingAt: start,
             message: "Open an existing target (.ti1 or .ti2)")
    }

    /// `selectProfileFile` — `.icc`/`.icm`/`.mpp` only — **never** `.ti*`
    /// (#172: the profile filter must not accept datasets).
    func selectProfileFile(startingAt start: URL? = nil) -> URL? {
        open(extensions: ["icc", "icm", "mpp"], startingAt: start,
             message: "Choose an ICC/ICM profile or measurement preconditioning file")
    }

    /// `selectSpectrumFile` — `.sp` illuminant spectrum (colprof -i).
    func selectSpectrumFile(startingAt start: URL? = nil) -> URL? {
        open(extensions: ["sp"], startingAt: start,
             message: "Choose a custom illuminant spectrum (.sp)")
    }

    /// `selectDatasetFile` — open a measured dataset (`.ti3`, `.txt`,
    /// `.cgats`, `.csv`). Always an *open* dialog, never save (#211).
    func selectDatasetFile(startingAt start: URL? = nil) -> URL? {
        open(extensions: ["ti3", "txt", "cgats", "csv"], startingAt: start,
             message: "Import a measured dataset")
    }

    /// `selectCsvSavePath` — verification-history CSV export.
    func selectCsvSavePath(startingAt start: URL? = nil) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "verification-history.csv"
        panel.allowedContentTypes = utTypes(["csv"])
        panel.allowsOtherFileTypes = false
        panel.directoryURL = start
        return run(panel)
    }

    /// `selectCalFile` — `.cal` calibration curves.
    func selectCalFile(startingAt start: URL? = nil) -> URL? {
        open(extensions: ["cal"], startingAt: start,
             message: "Choose a calibration file (.cal)")
    }

    /// `btnImportPreset` — open a `.json` preset file.
    func selectPresetFile(startingAt start: URL? = nil) -> URL? {
        open(extensions: ["json"], startingAt: start,
             message: "Import a profiling preset (.json)")
    }

    /// `btnExportActivePreset` — save a `.json` preset file.
    func selectPresetSavePath(name: String, startingAt start: URL? = nil) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).json"
        panel.allowedContentTypes = utTypes(["json"])
        panel.allowsOtherFileTypes = false
        panel.directoryURL = start
        panel.message = "Export this preset as JSON"
        return run(panel)
    }

    // MARK: - Internals (private — not a shared public picker API)

    private func open(
        extensions: [String],
        startingAt start: URL?,
        message: String?
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = utTypes(extensions)
        panel.allowsOtherFileTypes = true
        panel.directoryURL = start
        if let message { panel.message = message }
        return run(panel)
    }

    private func utTypes(_ extensions: [String]) -> [UTType] {
        extensions.compactMap { UTType(filenameExtension: $0) }
    }

    private func run(_ panel: NSOpenPanel) -> URL? {
        panel.runModal() == .OK ? panel.url : nil
    }

    private func run(_ panel: NSSavePanel) -> URL? {
        panel.runModal() == .OK ? panel.url : nil
    }
}
