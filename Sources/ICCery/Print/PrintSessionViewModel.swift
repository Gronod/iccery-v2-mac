import Combine
import Foundation
import ICCeryCore

/// CUPS queue selection, bound print panel, and `lp` spool (issues 12–15, 17 / #85).
@MainActor
final class PrintSessionViewModel: ObservableObject {
    let wizard: WizardViewModel
    let environment: AppEnvironment

    @Published var printers: [Printer] = []
    @Published var selectedPrinter = ""
    @Published var printerCaps = PrinterCapabilities()
    @Published var selectedTray: Int?
    @Published var selectedMediaType: String?
    @Published var printOrientation = "portrait"
    @Published var capturedCupsOptions: [String: String] = [:]
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
        } catch {
            printerCaps = PrinterCapabilities()
        }
    }

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
                    printNotice = Notice(
                        kind: .info,
                        text: "Printer properties dialog cancelled.",
                        autoHideAfter: nil
                    )
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

    func printAllPages(from result: PrinttargResult, pageSize: PageSize) {
        guard !isPrinting else { return }
        isPrinting = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            // `defer` cannot mutate isolated state under Swift 5.7
            // (Xcode 14.2 / macOS 12 runner), so clear explicitly (#113).
            var printed = 0
            for page in result.pages {
                do {
                    try await spool(page, index: page.index, pageSize: pageSize)
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

    func printPage(_ page: GalleryPage, pageSize: PageSize) {
        guard !isPrinting else { return }
        isPrinting = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await spool(page, index: page.index, pageSize: pageSize)
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

    private func spool(_ page: GalleryPage, index: Int, pageSize: PageSize) async throws {
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
        wizard.printerName = selectedPrinter
    }
}
