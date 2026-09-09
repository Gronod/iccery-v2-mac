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

    // MARK: - Print panel (issue 17)

    /// CUPS destinations from `lpstat` (#printerSelect).
    var printers: [Printer] = []
    /// Selected queue name.
    var selectedPrinter = ""
    /// Capabilities of the selected queue (#printerTraySelect /
    /// #printerMediaTypeSelect / PageSize source).
    var printerCaps = PrinterCapabilities()
    var selectedTray: Int?
    var selectedMediaType: String?
    /// "portrait" | "landscape" (#btnOrientPortrait/#btnOrientLandscape).
    var printOrientation = "portrait"
    /// Per-queue captured `key=value` strings from Preferences — replayed
    /// on `lp` (session-only, docs/11 §capturedCupsOptions).
    var capturedCupsOptions: [String: String] = [:]
    /// In-panel notice (#printNotification) — cancel → info, not error.
    var printNotice: String?
    var printNoticeIsError = false
    var isPrinting = false

    // MARK: - Presets

    var presets: [ProfilingPreset] = []
    var selectedPresetID = "none"
    var showingSavePreset = false
    var showingManagePresets = false
    var savePresetName = ""
    var savePresetDesc = ""

    /// Stage 3 measurement workflow, owned at the app level so it persists
    /// across stage switches and can observe settings changes.
    var measurement: MeasurementWorkflowViewModel
    /// Stage 4/5 profile workflow, owned at the app level so it persists
    /// across stage switches and can apply preset values.
    var profile: ProfileWorkflowViewModel

    init(environment: AppEnvironment = .live()) {
        self.environment = environment
        self.wizard = WizardViewModel(stateStore: environment.stateStore)
        self.measurement = MeasurementWorkflowViewModel(
            wizard: wizard,
            environment: environment
        )
        self.profile = ProfileWorkflowViewModel(
            wizard: wizard,
            environment: environment
        )
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
        Task { @MainActor in
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

    /// `#btn-import-dataset` — open a measured dataset, write a canonical
    /// `.ti3` to the working directory, and set the target (issue #30).
    func importMeasurementDataset() {
        let url = UITestHooks.isEnabled
            ? UITestHooks.datasetImportURL
            : fileDialogs.selectDatasetFile()
        guard let url else { return }

        do {
            let dataset = try CGATSParser.parse(url: url)
            guard let directory = targetDirectory ?? wizard.effectiveWorkingDirectory else {
                wizard.showNotice("Choose a working directory before importing.", kind: .warning)
                return
            }

            let stem = url.deletingPathExtension().lastPathComponent
            let output = directory.appendingPathComponent("\(stem).ti3")
            try CGATSWriter.write(dataset, to: output)

            wizard.setTarget(basename: stem, workingDirectory: directory)
            wizard.refreshGating()
            wizard.showNotice("Imported \(dataset.samples.count) patches from \(url.lastPathComponent)")

            if wizard.isUnlocked(.verifyInstall) {
                wizard.go(to: .verifyInstall)
            } else if wizard.isUnlocked(.buildProfile) {
                wizard.go(to: .buildProfile)
            } else {
                wizard.showNotice("Imported dataset is not ready for profiling.", kind: .warning)
            }
        } catch let error as CGATSParseError {
            wizard.showNotice("Import failed: \(error.localizedDescription)", kind: .error)
        } catch {
            wizard.showNotice("Import failed: \(error.localizedDescription)", kind: .error)
        }
    }

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
            measurement.resumedFromTi2 = false
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
            measurement.resumedFromTi2 = true
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
        Task { @MainActor in
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

    // MARK: - Print panel actions (issue 17)

    /// `#btnRefreshPrinters` — re-enumerate CUPS destinations and load
    /// capabilities for the selection. Auto-runs when the panel first
    /// appears with a manifest.
    func refreshPrinters() {
        let cups = environment.cupsService
        Task { @MainActor in
            do {
                let list = try await cups.listPrinters()
                printers = list
                if !list.contains(where: { $0.name == selectedPrinter }) {
                    selectedPrinter = list.first { $0.isDefault }?.name
                        ?? list.first?.name ?? ""
                }
                await reloadSelectedCapabilities()
            } catch {
                printNotice = "Could not list printers: \(error.localizedDescription)"
                printNoticeIsError = true
            }
        }
    }

    /// Capabilities for `selectedPrinter` — trays / media / sizes feed
    /// the selects.
    func reloadSelectedCapabilities() async {
        guard !selectedPrinter.isEmpty else {
            printerCaps = PrinterCapabilities()
            return
        }
        do {
            printerCaps = try await environment.cupsService
                .capabilities(for: selectedPrinter)
            // Default selections only when the captured options didn't
            // already pin them (Preferences round-trip wins).
            if selectedMediaType == nil {
                selectedMediaType = printerCaps.mediaTypes.first?.id
            }
            if selectedTray == nil {
                selectedTray = printerCaps.trays.first?.id
            }
        } catch {
            printerCaps = PrinterCapabilities()
        }
    }

    /// `#btnPrinterProperties` — bound NSPrintPanel ("Use Settings").
    /// Cancel → info notice, never an error, cache untouched. On OK the
    /// captured options are stored per-queue; a panel-side queue switch
    /// updates `printerSelect` when the returned CUPS id is in the list.
    func openPrinterPreferences() {
        guard !selectedPrinter.isEmpty else { return }
        let queue = selectedPrinter
        let displayName = printers.first { $0.name == queue }?.displayName
        let cups = environment.cupsService
        Task { @MainActor in
            do {
                guard let result = try await PrintPanelService()
                    .showProperties(
                        queue: queue, displayName: displayName,
                        cupsService: cups)
                else {
                    printNotice = "Printer properties dialog cancelled."
                    printNoticeIsError = false
                    return
                }
                if let selected = result.selectedPrinter,
                   printers.contains(where: { $0.name == selected }),
                   selected != queue {
                    selectedPrinter = selected
                    await reloadSelectedCapabilities()
                }
                if let captured = result.options.cupsOptions {
                    capturedCupsOptions[selectedPrinter] = captured
                }
                if let media = result.options.mediaType {
                    selectedMediaType = media
                }
                printNotice = "Settings captured for \(selectedPrinter)."
                printNoticeIsError = false
            } catch {
                printNotice = error.localizedDescription
                printNoticeIsError = true
            }
        }
    }

    /// `#btnPrintAll` — spool every gallery TIFF, sequentially. Stops on
    /// the first failure so the user sees which page failed.
    func printAllPages() {
        guard let result = printtargResult, !isPrinting else { return }
        isPrinting = true
        Task { @MainActor in
            var printed = 0
            for page in result.pages {
                do {
                    try await spool(page, index: page.index)
                    printed += 1
                } catch {
                    printNotice = "Print failed on \(page.page.filename): "
                        + error.localizedDescription
                    printNoticeIsError = true
                    isPrinting = false
                    return
                }
            }
            printNotice = "Sent \(printed) page(s) to \(selectedPrinter)."
            printNoticeIsError = false
            isPrinting = false
        }
    }

    /// `#btnPrintPage-N` — one TIFF.
    func printPage(_ page: GalleryPage) {
        guard !isPrinting else { return }
        isPrinting = true
        Task { @MainActor in
            do {
                try await spool(page, index: page.index)
                printNotice = "Sent \(page.page.filename) to \(selectedPrinter)."
                printNoticeIsError = false
            } catch {
                printNotice = "Print failed: \(error.localizedDescription)"
                printNoticeIsError = true
            }
            isPrinting = false
        }
    }

    private func spool(_ page: GalleryPage, index: Int) async throws {
        guard !selectedPrinter.isEmpty else {
            throw CupsError.noPrinterSelected
        }
        let options = PrintOptions(
            orientation: printOrientation,
            paperSize: pageSize == .custom ? nil : pageSize.rawValue,
            mediaType: selectedMediaType,
            ppdUncorrectedPassthrough: true,
            cupsOptions: capturedCupsOptions[selectedPrinter])
        try await environment.cupsService.printTarget(
            queue: selectedPrinter,
            tiffPath: page.fileURL.path,
            options: options,
            page: index)
        // For Stage 5 history (#95): record which queue printed.
        wizard.printerName = selectedPrinter
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

        profile.applyPreset(preset)

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
            noRandomize: layoutOrder == .raster,
            calibrationFile: profile.calibrationFile.isEmpty ? nil : profile.calibrationFile,
            applyCalibration: profile.applyCalibration ? true : nil,
            colprofAlgorithm: profile.algorithm,
            colprofQuality: profile.quality,
            colprofIntent: profile.intent.isEmpty ? nil : profile.intent,
            colprofFwa: profile.fwaValue,
            colprofIlluminant: profile.illuminant.isEmpty ? nil : profile.illuminant,
            colprofObserver: profile.observer.isEmpty ? nil : profile.observer,
            colprofInputViewingCond: profile.inputViewingCond.isEmpty ? nil : profile.inputViewingCond,
            colprofOutputViewingCond: profile.outputViewingCond.isEmpty ? nil : profile.outputViewingCond
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
