import Combine
import Foundation
import ICCeryCore

/// CUPS queue selection, bound print panel, and `lp` spool (issues 12–15, 17 / #85).
@MainActor
final class PrintSessionViewModel: ObservableObject {
    let wizard: WizardViewModel
    let environment: AppEnvironment
    /// Stage 1/2 form state — read for paper seeding/mirroring only;
    /// `workflow.pageSize` is the printtarg layout and is never written
    /// back from the print side (#183).
    weak var workflow: TargetWorkflowViewModel?

    @Published var printers: [Printer] = []
    @Published var selectedPrinter = ""
    @Published var printerCaps = PrinterCapabilities()
    @Published var selectedTray: Int?
    @Published var selectedMediaType: String?
    /// `PrinterPaperSize.id` — `0` is the synthetic custom entry (#183).
    @Published var selectedPaperSize: Int?
    /// Print-quality option token, e.g. `"303"` (#183).
    @Published var selectedQuality: String?
    @Published var printOrientation = "portrait"
    @Published var capturedCupsOptions: [String: String] = [:]
    /// Native print tickets per queue — the spool payload (#201).
    /// Session-only; cleared whenever the queue's mirror is.
    @Published var capturedTickets: [String: PrintTicket] = [:]
    @Published var printNotice: Notice?
    @Published var isPrinting = false
    private var printTask: Task<Void, Never>?

    init(wizard: WizardViewModel, environment: AppEnvironment) {
        self.wizard = wizard
        self.environment = environment
    }

    private var printerEnumTask: Task<[Printer]?, Never>?

    func refreshPrinters() {
        Task { @MainActor in _ = await enumeratePrinters() }
    }

    /// Serialized queue enumeration — `listPrinters` uses fixed process
    /// ids, so overlapping calls would throw `duplicateID`. Concurrent
    /// callers coalesce onto the in-flight task (#146).
    @discardableResult
    func enumeratePrinters() async -> [Printer]? {
        if let pending = printerEnumTask { return await pending.value }
        let task = Task { @MainActor [weak self] () -> [Printer]? in
            guard let self else { return nil }
            do {
                let list = try await self.environment.cupsService.listPrinters()
                self.printers = list
                if !list.contains(where: { $0.name == self.selectedPrinter }) {
                    self.selectedPrinter = list.first { $0.isDefault }?.name
                        ?? list.first?.name ?? ""
                }
                await self.reloadSelectedCapabilities()
                return list
            } catch {
                self.printNotice = Notice(
                    kind: .error,
                    text: "Could not list printers: \(error.localizedDescription)"
                )
                return nil
            }
        }
        printerEnumTask = task
        let result = await task.value
        printerEnumTask = nil
        return result
    }

    func reloadSelectedCapabilities() async {
        guard !selectedPrinter.isEmpty else {
            printerCaps = PrinterCapabilities()
            return
        }
        do {
            printerCaps = try await environment.cupsService
                .capabilities(for: selectedPrinter)
            if selectedMediaType == nil {
                selectedMediaType = printerCaps.mediaTypes.first?.id
            }
            if selectedTray == nil {
                selectedTray = printerCaps.trays.first?.id
            }
            if selectedQuality == nil {
                selectedQuality = printerCaps.qualityDefault
                    ?? printerCaps.qualities.first?.id
            }
            // Caps reload is a re-mirror trigger for the paper picker
            // (#183 E4) — pageSize + printer changes route here too.
            seedPaperSelection()
        } catch {
            printerCaps = PrinterCapabilities()
        }
    }

    // MARK: - Paper / quality selection (#183)

    /// Seed `selectedPaperSize` from Stage 1's `workflow.pageSize`:
    /// a capability whose name matches `pageSize.rawValue` → its id;
    /// `.custom` → the synthetic `Custom.<pt>x<pt>` entry (`id: 0`);
    /// no match → nil (never guess). Called only on pageSize / printer /
    /// caps triggers — never on unrelated publishes (R14).
    func seedPaperSelection() {
        guard let pageSize = workflow?.pageSize else { return }
        if pageSize == .custom {
            let token = customPaperToken()
            if let index = printerCaps.paperSizes.firstIndex(where: { $0.id == 0 }) {
                printerCaps.paperSizes[index].name = token
            } else {
                printerCaps.paperSizes.append(
                    PrinterPaperSize(id: 0, name: token))
            }
            selectedPaperSize = 0
            return
        }
        selectedPaperSize = printerCaps.paperSizes
            .first { $0.name == pageSize.rawValue }?.id
    }

    /// `Custom.<w>x<h>` in **points** — mm × 72/25.4 (#183 E5/R8). The
    /// PPD template token `Custom.WIDTHxHEIGHT` is never emitted verbatim.
    func customPaperToken() -> String {
        let w = workflow?.customPageW ?? 0
        let h = workflow?.customPageH ?? 0
        let wPt = (w * 72.0 / 25.4).rounded()
        let hPt = (h * 72.0 / 25.4).rounded()
        return "Custom.\(Int(wPt))x\(Int(hPt))"
    }

    /// The CUPS `PageSize` token for the current Stage 2 pick — live
    /// `Custom.<pt>x<pt>` for the synthetic entry, else the capability
    /// name. This is what `lp -o PageSize=` sees.
    var selectedPaperSizeToken: String? {
        guard let id = selectedPaperSize else { return nil }
        if id == 0 { return customPaperToken() }
        return printerCaps.paperSizes.first { $0.id == id }?.name
    }

    func openPrinterPreferences() {
        guard !selectedPrinter.isEmpty else { return }
        let queue = selectedPrinter
        let displayName = printers.first { $0.name == queue }?.displayName
        let cups = environment.cupsService
        let selections = PrintPanelInitialSelections(
            paperSize: selectedPaperSizeToken,
            qualityKey: printerCaps.qualityKey,
            quality: selectedQuality,
            mediaType: selectedMediaType,
            orientation: printOrientation)
        Task { @MainActor in
            do {
                guard let result = try await PrintPanelService()
                    .showProperties(
                        queue: queue, displayName: displayName,
                        cupsService: cups,
                        initialSelections: selections)
                else {
                    printNotice = Notice(
                        kind: .info,
                        text: "Printer properties dialog cancelled.",
                        autoHideAfter: nil
                    )
                    return
                }
                if let selected = result.properties.selectedPrinter,
                   printers.contains(where: { $0.name == selected }),
                   selected != queue {
                    selectedPrinter = selected
                    await reloadSelectedCapabilities()
                }
                if let captured = result.properties.options.cupsOptions {
                    capturedCupsOptions[selectedPrinter] = captured
                }
                // The native ticket rides alongside the mirror (#201).
                if let ticket = result.ticket {
                    capturedTickets[ticket.queue] = ticket
                }
                if let media = result.properties.options.mediaType {
                    selectedMediaType = media
                }
                // Capture-return (#183/#186): a dialog paper/quality/
                // orientation change updates the Stage 2 selections —
                // never `workflow.pageSize` (printtarg layout is
                // sacred).
                if let paper = result.properties.options.paperSize,
                   let match = printerCaps.paperSizes
                       .first(where: { $0.name == paper }) {
                    selectedPaperSize = match.id
                }
                if let quality = result.properties.options.quality {
                    selectedQuality = quality
                }
                if let orientation = result.properties.options.orientation {
                    printOrientation = orientation
                }
                printNotice = Notice(
                    kind: .info,
                    text: "Settings captured for \(selectedPrinter).",
                    autoHideAfter: nil
                )
            } catch {
                printNotice = Notice(kind: .error, text: error.localizedDescription)
            }
        }
    }

    func printAllPages(from result: PrinttargResult) {
        guard !isPrinting else { return }
        isPrinting = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            // `defer` cannot mutate isolated state under Swift 5.7
            // (Xcode 14.2 / macOS 12 runner), so clear explicitly (#113).
            var printed = 0
            for page in result.pages {
                do {
                    try await spool(page, index: page.index)
                    printed += 1
                } catch {
                    printNotice = Notice(
                        kind: .error,
                        text: "Print failed on \(page.page.filename): "
                            + error.localizedDescription
                    )
                    isPrinting = false
                    self.printTask = nil
                    return
                }
            }
            printNotice = Notice(
                kind: .info,
                text: "Sent \(printed) page(s) to \(selectedPrinter).",
                autoHideAfter: nil
            )
            isPrinting = false
            self.printTask = nil
        }
        printTask = task
    }

    func printPage(_ page: GalleryPage) {
        guard !isPrinting else { return }
        isPrinting = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await spool(page, index: page.index)
                printNotice = Notice(
                    kind: .info,
                    text: "Sent \(page.page.filename) to \(selectedPrinter).",
                    autoHideAfter: nil
                )
            } catch {
                printNotice = Notice(
                    kind: .error,
                    text: "Print failed: \(error.localizedDescription)"
                )
            }
            isPrinting = false
            self.printTask = nil
        }
        printTask = task
    }

    private func spool(_ page: GalleryPage, index: Int) async throws {
        guard !selectedPrinter.isEmpty else {
            throw CupsError.noPrinterSelected
        }
        // The Stage 2 paper token is what `lp -o PageSize=` sees;
        // `workflow.pageSize` remains the printtarg layout input only
        // (#183).
        let options = PrintOptions(
            orientation: printOrientation,
            paperSize: selectedPaperSizeToken,
            mediaType: selectedMediaType,
            quality: selectedQuality,
            ppdUncorrectedPassthrough: true,
            cupsOptions: capturedCupsOptions[selectedPrinter])
        try await environment.cupsService.printTarget(
            queue: selectedPrinter,
            tiffPath: page.fileURL.path,
            options: options,
            page: index)
        wizard.printerName = selectedPrinter
    }
}
