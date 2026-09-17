import SwiftUI
import ICCeryCore

/// Stage 2 — `#stage-2` Lay Out & Print (`printtarg` → `.ti2` + TIFFs,
/// issues #9/#10, docs/09). Print controls are visible but inert —
/// real spooling lands in M3.
struct Stage2View: View {
    @ObservedObject var workflow: TargetWorkflowViewModel
    /// Observed directly: nested ObservableObjects are not tracked
    /// through the parent's `objectWillChange`.
    @ObservedObject private var printSession: PrintSessionViewModel
    @ObservedObject private var wizard: WizardViewModel

    @State private var printGenerationTask: Task<Void, Never>?

    init(workflow: TargetWorkflowViewModel) {
        self.workflow = workflow
        self._printSession = ObservedObject(wrappedValue: workflow.print)
        self._wizard = ObservedObject(wrappedValue: workflow.wizard)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cmWarning
                formSection
                labelSection
                actionRow
                logSection
                gallerySection
                printPanel
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .accessibilityIdentifier("stage-2")
    }

    // MARK: - Colour-management warning (#cmWarningBanner)

    private var cmWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Set your printer driver to “No Colour Adjustment” " +
                 "(Epson) / “Off (No Colour Adjustment)” (Canon) before printing. " +
                 "Any driver colour management corrupts the target.")
                .font(.callout)
                .foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium)
                .stroke(Color.orange.opacity(0.4))
        )
        .accessibilityIdentifier("cmWarningBanner")
    }

    // MARK: - Layout form

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Picker("Instrument", selection: $workflow.instrument) {
                    ForEach(PrintInstrument.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .accessibilityIdentifier("instrumentSelect")
                Picker("Page size", selection: $workflow.pageSize) {
                    ForEach(PageSize.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .accessibilityIdentifier("pageSizeSelect")
            }
            if workflow.pageSize == .custom {
                HStack(spacing: 8) {
                    Text("Custom size (mm):")
                    TextField("W", value: $workflow.customPageW, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 70)
                        .accessibilityIdentifier("customPageW")
                    Text("×")
                    TextField("H", value: $workflow.customPageH, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 70)
                        .accessibilityIdentifier("customPageH")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("customPageSizeRow")
            }
            HStack(spacing: 16) {
                Picker("Bit depth", selection: $workflow.bitDepth) {
                    Text("8-bit TIFF").tag(TiffBitDepth.eight)
                    Text("16-bit TIFF").tag(TiffBitDepth.sixteen)
                }
                Stepper("DPI: \(workflow.tiffDpi)",
                        value: $workflow.tiffDpi, in: 72...600, step: 1)
                    .accessibilityIdentifier("tiffDpi")
            }
            HStack(spacing: 16) {
                Picker("Layout order", selection: $workflow.layoutOrder) {
                    ForEach(LayoutOrder.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .accessibilityIdentifier("printtargLayoutOrder")
                if workflow.layoutOrder == .customSeed {
                    HStack {
                        Text("Seed:")
                        TextField("", value: $workflow.customSeed, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                            .accessibilityIdentifier("printtargCustomSeed")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("printtargCustomSeedGroup")
                }
            }
        }
        .foregroundStyle(Theme.text)
    }

    // MARK: - Label (#btnToggleLabelEdit / #targetLabelPreview)

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chart label").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button(workflow.labelIsCustom ? "Use automatic label" : "Edit label…") {
                    workflow.labelIsCustom.toggle()
                }
                .accessibilityIdentifier("btnToggleLabelEdit")
            }
            HStack(spacing: 12) {
                TextField("Printer", text: $workflow.metaPrinter)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("targetMetadataPrinter")
                TextField("Ink set", text: $workflow.metaInkSet)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("targetMetadataInkSet")
            }
            HStack(spacing: 12) {
                TextField("Driver paper", text: $workflow.metaDriverPaper)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("targetMetadataDriverPaper")
                TextField("Actual paper", text: $workflow.metaActualPaper)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("targetMetadataActualPaper")
            }
            if workflow.labelIsCustom {
                TextField("Custom label", text: $workflow.customLabel)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("targetLabelPreview")
            } else {
                Text(workflow.automaticLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("targetLabelPreview")
            }
        }
    }

    // MARK: - Actions + log

    private var actionRow: some View {
        HStack {
            Button(action: workflow.createLayout) {
                Label(workflow.printtargRunning ? "Creating layout…" : "Create Layout",
                      systemImage: "rectangle.grid.2x2")
            }
            .controlSize(.large)
            .disabled(workflow.printtargRunning || workflow.wizard.basename.isEmpty)
            .accessibilityIdentifier("btnCreateLayout")
            if workflow.printtargRunning {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
    }

    private var logSection: some View {
        ProcessLogView(
            lines: workflow.printtargLog,
            minHeight: 100,
            maxHeight: 180,
            containerId: "printtargLogContainer",
            logId: "printtargLog"
        )
    }

    // MARK: - TIFF gallery (#tiffGallery) — host-side PNG only (#58)

    @ViewBuilder
    private var gallerySection: some View {
        if let result = workflow.printtargResult {
            VStack(alignment: .leading, spacing: 8) {
                Text("Target pages — \(result.manifest.pages.count) page(s), " +
                     "\(result.manifest.pages.reduce(0) { $0 + $1.patches }) patches")
                    .font(.headline).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("galleryInfo")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220))],
                    spacing: 12
                ) {
                    ForEach(result.pages) { page in
                        GalleryPageView(page: page, workflow: workflow)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("galleryGrid")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tiffGallery")
        }
    }

    // MARK: - Raw print panel (#rawPrintPanel) — native spool path (#201)

    private var printPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Print").font(.headline).foregroundStyle(Theme.text)
                if let notice = workflow.print.printNotice {
                    Image(systemName: notice.kind == .error
                          ? "xmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(notice.kind == .error
                                         ? .red : .blue)
                        .accessibilityIdentifier("printNotificationIcon")
                        .accessibilityValue(notice.kind.accessibilityValue)
                    Text(notice.text)
                        .font(.caption)
                        .foregroundStyle(notice.kind == .error
                                         ? .red : .secondary)
                        .accessibilityIdentifier("printNotificationText")
                        .accessibilityValue(notice.text)
                }
                Spacer()
            }
            .accessibilityElement(children: .contain)

            // Printer row: select + status + refresh + Preferences.
            HStack(spacing: 10) {
                Picker("Printer", selection: $workflow.print.selectedPrinter) {
                    ForEach(workflow.print.printers, id: \.name) { printer in
                        Text(printer.displayName ?? printer.name)
                            .tag(printer.name)
                    }
                }
                .frame(maxWidth: 320)
                .accessibilityIdentifier("printerSelect")
                .onChange(of: workflow.print.selectedPrinter) { _ in
                    workflow.print.selectedTray = nil
                    workflow.print.selectedMediaType = nil
                    workflow.print.selectedQuality = nil
                    Task { @MainActor in await workflow.print.reloadSelectedCapabilities() }
                }
                if let selected = workflow.print.printers
                    .first(where: { $0.name == workflow.print.selectedPrinter }) {
                    Text(selected.status.rawValue)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.background)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("printerStatusBadge")
                }
                // Placeholder — Phase 5 (AirPrint detection, M12)
                // replaces this with the live unmanaged-colour
                // warning badge for AirPrint queues.
                EmptyView()
                    .accessibilityIdentifier("airPrintWarningBadge")
                Button(action: workflow.print.refreshPrinters) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh printer list")
                .accessibilityIdentifier("btnRefreshPrinters")
                Button(action: workflow.print.openPrinterPreferences) {
                    Image(systemName: "gearshape")
                }
                .help("Printer properties — bound NSPrintPanel")
                .disabled(workflow.print.selectedPrinter.isEmpty)
                .accessibilityIdentifier("btnPrinterProperties")
            }

            // Tray / media / paper / quality / orientation — from
            // queue capabilities. Extracted subviews keep every
            // ViewBuilder ≤10 children (R13).
            HStack(spacing: 14) {
                if !workflow.print.printerCaps.trays.isEmpty {
                    Picker("Tray", selection: $workflow.print.selectedTray) {
                        ForEach(workflow.print.printerCaps.trays, id: \.id) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                    .frame(maxWidth: 200)
                    .accessibilityIdentifier("printerTraySelect")
                }
                if !workflow.print.printerCaps.mediaTypes.isEmpty {
                    Picker("Media", selection: $workflow.print.selectedMediaType) {
                        ForEach(workflow.print.printerCaps.mediaTypes, id: \.id) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                    .frame(maxWidth: 240)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("mediaTypeGroup")
                    .accessibilityIdentifier("printerMediaTypeSelect")
                }
                if !workflow.print.printerCaps.paperSizes.isEmpty {
                    paperSizeGroup
                }
                if !workflow.print.printerCaps.qualities.isEmpty {
                    qualityGroup
                }
                HStack(spacing: 0) {
                    Button("Portrait") { workflow.print.printOrientation = "portrait" }
                        .buttonStyle(.bordered)
                        .tint(workflow.print.printOrientation == "portrait" ? .accentColor : .gray)
                        .accessibilityIdentifier("btnOrientPortrait")
                    Button("Landscape") { workflow.print.printOrientation = "landscape" }
                        .buttonStyle(.bordered)
                        .tint(workflow.print.printOrientation == "landscape" ? .accentColor : .gray)
                        .accessibilityIdentifier("btnOrientLandscape")
                }
                Spacer()
            }
            // Stage 1 owns the custom dimensions — the caption lives
            // inside `paperSizeGroup` (#183).

            printAllRow
        }
        .padding(12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rawPrintPanel")
        .onAppear { schedulePrinterRefresh() }
        .onChange(of: workflow.printtargResult?.pages.count) { _ in
            schedulePrinterRefresh()
        }
        // Editable picker that re-mirrors Stage 1's pageSize (#183 E4).
        .onChange(of: workflow.pageSize) { _ in
            workflow.print.seedPaperSelection()
        }
    }

    /// Print All + single-job granularity (#201 D5) + advance.
    /// Extracted so every ViewBuilder body stays ≤10 children (R13 —
    /// Xcode 14.2 has no `buildPartialBlock`).
    private var printAllRow: some View {
        HStack(spacing: 8) {
            Button(action: {
                if let result = workflow.printtargResult {
                    workflow.print.printAllPages(from: result)
                }
            }) {
                Label(workflow.print.isPrinting ? "Printing…" : "Print All",
                      systemImage: "printer")
            }
            .controlSize(.large)
            .disabled(workflow.print.isPrinting
                      || workflow.printtargResult == nil
                      || workflow.print.selectedPrinter.isEmpty)
            .accessibilityIdentifier("btnPrintAll")
            Toggle("Single spool job",
                   isOn: $workflow.print.singleJobForAllPages)
                .help("Send all pages as one print job instead of "
                      + "one job per page")
                .accessibilityIdentifier("chkSingleSpoolJob")
            Spacer()
            Button("Advance to Stage 3") { workflow.advanceToStage3() }
                .accessibilityIdentifier("btnAdvanceToStage3")
                .disabled(workflow.printtargResult == nil
                          || !workflow.wizard.isUnlocked(.measure))
        }
    }

    /// Paper picker + custom-size caption under the `paperSizeGroup`
    /// container (#183). `caps.paperSizes` plus the synthetic custom
    /// entry (`id: 0`, shown as `Custom (W×H mm)`).
    private var paperSizeGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Paper", selection: $workflow.print.selectedPaperSize) {
                ForEach(workflow.print.printerCaps.paperSizes, id: \.id) { size in
                    Text(size.id == 0
                         ? "Custom (\(Int(workflow.customPageW))×\(Int(workflow.customPageH)) mm)"
                         : size.name)
                        .tag(Optional(size.id))
                }
            }
            .frame(maxWidth: 200)
            .accessibilityIdentifier("printerPaperSizeSelect")
            if workflow.print.selectedPaperSize == 0 {
                Text("Custom (\(Int(workflow.customPageW))×\(Int(workflow.customPageH)) mm)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paperSizeGroup")
    }

    /// Quality picker — driver tokens with PPD-enriched labels (#183).
    private var qualityGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Quality", selection: $workflow.print.selectedQuality) {
                ForEach(workflow.print.printerCaps.qualities, id: \.id) {
                    Text($0.name).tag(Optional($0.id))
                }
            }
            .frame(maxWidth: 200)
            .accessibilityIdentifier("printerQualitySelect")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qualityGroup")
    }

    /// Auto-enumerates printers once a manifest exists and whenever it
    /// changes (e.g. resume from .ti2). The explicit task handle keeps
    /// a superseded run from racing the next one.
    private func schedulePrinterRefresh() {
        printGenerationTask?.cancel()
        printGenerationTask = Task { @MainActor in
            if workflow.print.printers.isEmpty, workflow.printtargResult != nil {
                workflow.print.refreshPrinters()
            }
        }
    }
}

/// One gallery cell: PNG preview + per-page Print button.
private struct GalleryPageView: View {
    let page: GalleryPage
    @ObservedObject var workflow: TargetWorkflowViewModel
    /// Observed directly: `print` is a nested ObservableObject and its
    /// `isPrinting`/`selectedPrinter` changes drive this cell's button.
    @ObservedObject private var printSession: PrintSessionViewModel

    init(page: GalleryPage, workflow: TargetWorkflowViewModel) {
        self.page = page
        self.workflow = workflow
        self._printSession = ObservedObject(wrappedValue: workflow.print)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let png = page.previewPNG, let image = NSImage(data: png) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
            } else {
                ZStack {
                    Rectangle().fill(Theme.panel).frame(height: 160)
                    Text(page.previewError ?? "No preview")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(page.page.filename)
                .font(.caption).foregroundStyle(Theme.text)
            Text("\(page.page.patches) patches · " +
                 "\(Int(page.page.widthMm))×\(Int(page.page.heightMm)) mm")
                .font(.caption2).foregroundStyle(.secondary)
            Button("Print") { workflow.print.printPage(page) }
                .disabled(workflow.print.isPrinting
                          || workflow.print.selectedPrinter.isEmpty)
                .accessibilityIdentifier("btnPrintPage-\(page.index)")
        }
        .padding(8)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("galleryPage-\(page.index)")
    }
}
