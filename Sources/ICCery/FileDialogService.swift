import AppKit
import UniformTypeIdentifiers

/// NSOpenPanel / NSSavePanel wrappers (issue #6). All CGATS/ICC file
/// picking in the app goes through this service — the v1 equivalent of
/// the `select_*` Tauri commands (docs/21 §Dialogs).
@MainActor
final class FileDialogService {

    static let shared = FileDialogService()
    private init() {}

    // MARK: - Directory

    /// `#btnBrowse` — working directory for Argyll artefacts.
    /// Defaults to Documents (docs/06 §Empty cwd).
    func chooseDirectory(startingAt start: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        panel.prompt = "Choose"
        return run(panel)
    }

    // MARK: - Open files

    func chooseTI1(startingAt start: URL? = nil) -> URL? {
        chooseFile(extensions: ["ti1"], startingAt: start)
    }

    func chooseTI2(startingAt start: URL? = nil) -> URL? {
        chooseFile(extensions: ["ti2"], startingAt: start)
    }

    /// Stage 1 "Open Existing" — `.ti1` or `.ti2` (docs/06 §Resume).
    func chooseExistingTarget(startingAt start: URL? = nil) -> URL? {
        chooseFile(extensions: ["ti1", "ti2"], startingAt: start)
    }

    func chooseTI3(startingAt start: URL? = nil) -> URL? {
        chooseFile(extensions: ["ti3"], startingAt: start)
    }

    /// ICC/ICM picker (profiles, preconditioning, calibration `.cal`).
    func chooseProfile(startingAt start: URL? = nil) -> URL? {
        chooseFile(extensions: ["icc", "icm"], startingAt: start)
    }

    func chooseCalibration(startingAt start: URL? = nil) -> URL? {
        chooseFile(extensions: ["cal"], startingAt: start)
    }

    func chooseFile(
        extensions: [String],
        startingAt start: URL? = nil,
        message: String? = nil
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        panel.directoryURL = start
        if let message { panel.message = message }
        return run(panel)
    }

    // MARK: - Save

    func saveFile(
        defaultName: String,
        extensions: [String],
        startingAt start: URL? = nil,
        message: String? = nil
    ) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        panel.directoryURL = start
        if let message { panel.message = message }
        return run(panel)
    }

    // MARK: - Internals

    private func run(_ panel: NSOpenPanel) -> URL? {
        panel.runModal() == .OK ? panel.url : nil
    }

    private func run(_ panel: NSSavePanel) -> URL? {
        panel.runModal() == .OK ? panel.url : nil
    }
}
