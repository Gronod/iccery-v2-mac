import Foundation
import Observation
import ICCeryCore

/// Stage 1/2 form state, runner orchestration, resume flow, and preset
/// application (issues #7–#11).
///
/// `wizard` stays authoritative for persisted identity + disk gating;
/// this model owns the editable form, logs, gallery, and preset state.
/// All process work runs through `ArgyllRunner` off `@MainActor`; only
/// coalesced log batches and completion hop back.
@MainActor
@Observable
final class TargetWorkflowViewModel {

    let wizard: WizardViewModel
    let environment: AppEnvironment
    private let fileDialogs = FileDialogService.shared

    // MARK: - Stage 1 form (targen)

    var colourSpace: ColourSpace = .rgb {
        didSet {
            guard colourSpace != oldValue else { return }
            // CMYK black patches default to 0, RGB to 4 (docs/08).
            blackPatches = colourSpace == .cmyk ? 0 : 4
        }
    }
    var patchPreset: PatchCountPreset = .standard800
    /// `#patchCountCustom` — used when `patchPreset == .custom`.
    var customPatchCount = 2500
    var whitePatches = 4
    var blackPatches = 4

    // Advanced — each optional flag is enabled + value, so an untouched
    // control emits nothing (#advanced fields are opt-in).
    var greyStepsEnabled = false
    var greySteps = 5
    var singleChannelEnabled = false
    var singleChannelSteps = 5
    var neutralStepsEnabled = false
    var neutralSteps = 3
    var neutralConcEnabled = false
    var neutralConcentration = 0.50
    var preconditioningProfile: String?
    var highQuality = false
    var adaptationEnabled = false
    var adaptation = 0.10
    var algorithm: FullSpreadAlgorithm = .ofps
    var inkLimitEnabled = false
    var totalInkLimit = 320
    var darkEmphasisEnabled = false
    var darkEmphasis = 1.0
    var devicePowerEnabled = false
    var devicePower = 1.0

    /// `#targetBasename` — no placeholder is ever invented (#60).
    var targetBasename = ""
    /// `#selectedPathDisplay` / resolved cwd.
    var targetDirectory: URL?

    // MARK: - Stage 2 form (printtarg)

    var instrument: PrintInstrument = .i1
    var pageSize: PageSize = .a4
    var customPageW = 210.0
    var customPageH = 297.0
    var bitDepth: TiffBitDepth = .eight
    /// `#tiffDpi` — two-way bound; presets can change it (150-DPI draft
    /// regression must be visible here).
    var tiffDpi = 300
    var layoutOrder: LayoutOrder = .deterministic
    var customSeed = 1
    var labelIsCustom = false
    var customLabel = ""
    var metaPrinter = ""
    var metaInkSet = ""
    var metaDriverPaper = ""
    var metaActualPaper = ""

    // MARK: - Run state

    var targenRunning = false
    var targenLog: [String] = []
    var printtargRunning = false
    var printtargLog: [String] = []
    var printtargResult: PrinttargResult?
    /// Sticky until the target changes: `.ti2` resume landed us on
    /// Stage 3 (`#stage3LoadedTargetBanner` data).
    var resumedFromTi2 = false

    // MARK: - Presets

    var presets: [ProfilingPreset] = []
    var selectedPresetID = "none"
    var showingSavePreset = false
    var showingManagePresets = false
    var savePresetName = ""
    var savePresetDesc = ""

    init(environment: AppEnvironment = .live()) {
        self.environment = environment
        self.wizard = WizardViewModel(stateStore: environment.stateStore)
        reloadPresets()
    }

    // MARK: - Derived

    var effectivePatchCount: Int {
        patchPreset.patchCount ?? customPatchCount
    }

    var canGenerate: Bool {
        PathSecurity.isValidBasename(targetBasename) && targetDirectory != nil
    }

    var labelMetadata: TargetLabelMetadata {
        TargetLabelMetadata(
            printer: metaPrinter, inkSet: metaInkSet,
            driverPaper: metaDriverPaper, actualPaper: metaActualPaper)
    }

    /// `#targetLabelPreview` — live preview of the automatic label.
    var automaticLabel: String {
        PrinttargLabel.automatic(
            basename: wizard.basename.isEmpty ? "target" : wizard.basename,
            metadata: labelMetadata)
    }

    var selectedPreset: ProfilingPreset? {
        presets.first { $0.id == selectedPresetID }
    }

    // MARK: - Stage 1: generate

    func buildTargenConfig() -> TargenConfig {
        TargenConfig(
            colourSpace: colourSpace,
            patchCount: effectivePatchCount,
            whitePatches: whitePatches,
            blackPatches: blackPatches,
            greySteps: greyStepsEnabled ? greySteps : nil,
            singleChannelSteps: singleChannelEnabled ? singleChannelSteps : nil,
            neutralSteps: neutralStepsEnabled ? neutralSteps : nil,
            neutralConcentration: neutralConcEnabled ? neutralConcentration : nil,
            preconditioningProfile: preconditioningProfile,
            ofpsHighQuality: highQuality ? true : nil,
            ofpsAdaptation: adaptationEnabled ? adaptation : nil,
            fullSpreadAlgorithm: algorithm == .ofps ? nil : algorithm,
            totalInkLimit: inkLimitEnabled ? totalInkLimit : nil,
            darkEmphasis: darkEmphasisEnabled ? darkEmphasis : nil,
            devicePower: devicePowerEnabled ? devicePower : nil,
            basename: targetBasename,
            workingDirectory: targetDirectory
        )
    }

    func browseForTargetFile() {
        let url = UITestHooks.isEnabled
            ? UITestHooks.saveTargetURL
            : fileDialogs.selectTargetFile()
        guard let url else { return }
        targetBasename = url.deletingPathExtension().lastPathComponent
        targetDirectory = url.deletingLastPathComponent()
    }

    func browseForWorkingDirectory() {
        let url = UITestHooks.isEnabled
            ? UITestHooks.workDirURL
            : fileDialogs.selectDirectory()
        if let url { targetDirectory = url }
    }

    func browseForPreconditioningProfile() {
        if let url = fileDialogs.selectProfileFile() {
            preconditioningProfile = url.path
        }
    }

    func generateTarget() {
        guard canGenerate, !targenRunning else { return }
        let config = buildTargenConfig()
        targenRunning = true
        targenLog = []
        resumedFromTi2 = false
        let runner = environment.runner
        Task {
            do {
                let url = try await runner.runTargen(config: config) { [weak self] batch in
                    Task { @MainActor [weak self] in
                        self?.targenLog.append(contentsOf: batch)
                    }
                }
                wizard.setTarget(
                    basename: config.basename,
                    workingDirectory: config.workingDirectory)
                wizard.refreshGating()
                wizard.showNotice("Target generated: \(url.lastPathComponent)")
                wizard.go(to: .layOutPrint)
            } catch {
                wizard.showNotice(
                    "targen failed: \(error.localizedDescription)", kind: .error)
            }
            targenRunning = false
        }
    }

    // MARK: - Issue 8: resume an existing target

    /// `#btnOpenExisting` — open `.ti1`/`.ti2` (open dialog, #103).
    /// `.ti1` → Stage 2; `.ti2` → Stage 3 with the resume notice, but
    /// only when the sibling `.ti1` exists so the artefact gate holds.
    func openExistingTarget() {
        let url = UITestHooks.isEnabled
            ? UITestHooks.existingTargetURL
            : fileDialogs.selectExistingTarget()
        guard let url else { return }

        let stem = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        guard PathSecurity.isValidBasename(stem) else {
            wizard.showNotice("Invalid target name.", kind: .error)
            return
        }

        switch url.pathExtension.lowercased() {
        case "ti1":
            wizard.setTarget(basename: stem, workingDirectory: dir)
            wizard.refreshGating()
            resumedFromTi2 = false
            wizard.go(to: .layOutPrint)
        case "ti2":
            let header = Ti2Header.parse(url)
            guard header.hasSiblingTi1 else {
                wizard.showNotice(
                    "Cannot resume \(stem).ti2 — the sibling \(stem).ti1 is missing.",
                    kind: .error)
                return
            }
            wizard.setTarget(basename: stem, workingDirectory: dir)
            wizard.refreshGating()
            resumedFromTi2 = true
            wizard.showNotice("Resumed from .ti2", kind: .info, autoHideAfter: nil)
            wizard.go(to: .measure)
        default:
            wizard.showNotice(
                "Not a target file — choose a .ti1 or .ti2.", kind: .error)
        }
    }

    // MARK: - Stage 2: create layout

    func buildPrinttargConfig() -> PrinttargConfig {
        PrinttargConfig(
            instrument: instrument,
            pageSize: pageSize,
            customPageWidth: customPageW,
            customPageHeight: customPageH,
            bitDepth: bitDepth,
            dpi: tiffDpi,
            layoutOrder: layoutOrder,
            customSeed: customSeed,
            label: PrinttargLabel.resolved(
                customLabel: labelIsCustom ? customLabel : nil,
                basename: wizard.basename,
                metadata: labelMetadata),
            basename: wizard.basename,
            workingDirectory: wizard.effectiveWorkingDirectory
        )
    }

    func createLayout() {
        guard wizard.isUnlocked(.layOutPrint), !printtargRunning else { return }
        let config = buildPrinttargConfig()
        printtargRunning = true
        printtargLog = []
        printtargResult = nil
        let runner = environment.runner
        Task {
            do {
                let result = try await runner.runPrinttarg(config: config) { [weak self] batch in
                    Task { @MainActor [weak self] in
                        self?.printtargLog.append(contentsOf: batch)
                    }
                }
                printtargResult = result
                wizard.refreshGating()
                wizard.showNotice(
                    "Layout created — \(result.manifest.pages.count) page(s) ready.")
            } catch {
                // Stay on Stage 2: non-zero exit, malformed manifest, or
                // missing .ti2 must never advance the wizard (#156).
                wizard.showNotice(
                    "printtarg failed: \(error.localizedDescription)", kind: .error)
            }
            printtargRunning = false
        }
    }

    /// `#btnAdvanceToStage3` — manual advance once `.ti2` exists.
    func advanceToStage3() {
        wizard.refreshGating()
        wizard.go(to: .measure)
    }

    // MARK: - Presets

    func reloadPresets() {
        presets = environment.presetStore.all()
    }

    /// Applies every Stage 1/2 field of the preset to the live form
    /// (bidirectional — the draft preset's dpi=150 must be visible).
    func applyPreset(_ preset: ProfilingPreset) {
        colourSpace = preset.colourSpace == "cmyk" ? .cmyk : .rgb
        patchPreset = PatchCountPreset(rawValue: "\(preset.patchCount)") ?? .custom
        customPatchCount = preset.patchCount
        whitePatches = preset.whitePatches
        blackPatches = preset.blackPatches
        greySteps = preset.greySteps ?? 5; greyStepsEnabled = preset.greySteps != nil
        singleChannelSteps = preset.singleChannelSteps ?? 5
        singleChannelEnabled = preset.singleChannelSteps != nil
        neutralSteps = preset.neutralSteps ?? 3
        neutralStepsEnabled = preset.neutralSteps != nil
        neutralConcentration = preset.neutralConcentration ?? 0.50
        neutralConcEnabled = preset.neutralConcentration != nil
        preconditioningProfile = preset.preconditioningProfile
        highQuality = preset.ofpsHighQuality == true
        adaptation = preset.ofpsAdaptation ?? 0.10
        adaptationEnabled = preset.ofpsAdaptation != nil
        algorithm = preset.fullSpreadAlgorithm
            .flatMap { FullSpreadAlgorithm(presetValue: $0) } ?? .ofps
        totalInkLimit = preset.totalInkLimit ?? 320
        inkLimitEnabled = preset.totalInkLimit != nil
        darkEmphasis = preset.darkEmphasis ?? 1.0
        darkEmphasisEnabled = preset.darkEmphasis != nil
        devicePower = preset.devicePower ?? 1.0
        devicePowerEnabled = preset.devicePower != nil

        instrument = PrintInstrument(rawValue: preset.instrument) ?? .i1
        if let size = PageSize(rawValue: preset.pageSize) {
            pageSize = size
        } else if let (w, h) = Self.parseCustomPage(preset.pageSize) {
            pageSize = .custom; customPageW = w; customPageH = h
        } else {
            pageSize = .a4
        }
        bitDepth = preset.bitDepth == 16 ? .sixteen : .eight
        tiffDpi = preset.dpi
        if preset.noRandomize == true {
            layoutOrder = .raster
        } else if (preset.randomSeed ?? 1) == 1 {
            layoutOrder = .deterministic
        } else {
            layoutOrder = .customSeed
        }
        customSeed = preset.randomSeed ?? 1

        selectedPresetID = preset.id
    }

    /// Snapshot of the live Stage 1/2 form as a custom preset.
    func saveCurrentAsPreset() {
        let name = savePresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            wizard.showNotice("Preset needs a name.", kind: .warning)
            return
        }
        let preset = ProfilingPreset(
            id: "custom-\(UUID().uuidString.lowercased())",
            name: name,
            description: savePresetDesc.trimmingCharacters(in: .whitespacesAndNewlines),
            colourSpace: colourSpace == .cmyk ? "cmyk" : "rgb",
            patchCount: effectivePatchCount,
            whitePatches: whitePatches,
            blackPatches: blackPatches,
            greySteps: greyStepsEnabled ? greySteps : nil,
            singleChannelSteps: singleChannelEnabled ? singleChannelSteps : nil,
            neutralSteps: neutralStepsEnabled ? neutralSteps : nil,
            neutralConcentration: neutralConcEnabled ? neutralConcentration : nil,
            preconditioningProfile: preconditioningProfile,
            ofpsHighQuality: highQuality ? true : nil,
            ofpsAdaptation: adaptationEnabled ? adaptation : nil,
            fullSpreadAlgorithm: algorithm.presetValue,
            totalInkLimit: inkLimitEnabled ? totalInkLimit : nil,
            darkEmphasis: darkEmphasisEnabled ? darkEmphasis : nil,
            devicePower: devicePowerEnabled ? devicePower : nil,
            instrument: instrument.rawValue,
            pageSize: pageSize == .custom
                ? "\(Int(customPageW))x\(Int(customPageH))"
                : pageSize.rawValue,
            bitDepth: bitDepth.rawValue,
            dpi: tiffDpi,
            randomSeed: layoutOrder == .deterministic ? 1 : customSeed,
            noRandomize: layoutOrder == .raster
        )
        do {
            try environment.presetStore.saveCustom(preset)
            reloadPresets()
            selectedPresetID = preset.id
            showingSavePreset = false
            savePresetName = ""
            savePresetDesc = ""
            wizard.showNotice("Preset saved: \(preset.name)")
        } catch {
            wizard.showNotice(
                "Could not save preset: \(error.localizedDescription)", kind: .error)
        }
    }

    func deletePreset(_ preset: ProfilingPreset) {
        do {
            if try environment.presetStore.deleteCustom(id: preset.id) {
                if selectedPresetID == preset.id { selectedPresetID = "none" }
                reloadPresets()
            } else {
                wizard.showNotice("Built-in presets cannot be deleted.", kind: .warning)
            }
        } catch {
            wizard.showNotice(
                "Could not delete preset: \(error.localizedDescription)", kind: .error)
        }
    }

    func importPreset() {
        let url = UITestHooks.isEnabled
            ? UITestHooks.presetImportURL
            : fileDialogs.selectPresetFile()
        guard let url else { return }
        do {
            let data = try Data(contentsOf: url)
            let preset = try environment.presetStore.import(data)
            try environment.presetStore.saveCustom(preset)
            reloadPresets()
            selectedPresetID = preset.id
            wizard.showNotice("Preset imported: \(preset.name)")
        } catch {
            wizard.showNotice(
                "Import failed: \(error.localizedDescription)", kind: .error)
        }
    }

    func exportPreset(_ preset: ProfilingPreset) {
        let url = UITestHooks.isEnabled
            ? UITestHooks.presetExportURL
            : fileDialogs.selectPresetSavePath(name: preset.id)
        guard let url else { return }
        do {
            try environment.presetStore.export(preset)
                .write(to: url, options: .atomic)
            wizard.showNotice("Preset exported: \(url.lastPathComponent)")
        } catch {
            wizard.showNotice(
                "Export failed: \(error.localizedDescription)", kind: .error)
        }
    }

    static func parseCustomPage(_ raw: String) -> (Double, Double)? {
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2,
              let w = Double(parts[0]), let h = Double(parts[1]),
              w >= 50, h >= 50 else { return nil }
        return (w, h)
    }
}
