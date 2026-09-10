import Foundation
import Observation
import ICCeryCore

/// CUPS queue selection, bound print panel, and `lp` spool (issues 12–15, 17 / #85).
@MainActor
@Observable
final class PrintSessionViewModel {
    let wizard: WizardViewModel
    let environment: AppEnvironment

    var printers: [Printer] = []
    var selectedPrinter = ""
    var printerCaps = PrinterCapabilities()
    var selectedTray: Int?
    var selectedMediaType: String?
    var printOrientation = "portrait"
    var capturedCupsOptions: [String: String] = [:]
    var printNotice: Notice?
    var isPrinting = false
    private var printTask: Task<Void, Never>?

    init(wizard: WizardViewModel, environment: AppEnvironment) {
        self.wizard = wizard
        self.environment = environment
    }

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
                printNotice = Notice(
                    kind: .error,
                    text: "Could not list printers: \(error.localizedDescription)"
                )
            }
        }
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
            defer { self.printTask = nil }
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
                    return
                }
            }
            printNotice = Notice(
                kind: .info,
                text: "Sent \(printed) page(s) to \(selectedPrinter).",
                autoHideAfter: nil
            )
            isPrinting = false
        }
        printTask = task
    }

    func printPage(_ page: GalleryPage, pageSize: PageSize) {
        guard !isPrinting else { return }
        isPrinting = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.printTask = nil }
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
