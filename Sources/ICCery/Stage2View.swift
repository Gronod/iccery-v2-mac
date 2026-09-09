import SwiftUI
import ICCeryCore

/// Stage 2 — `#stage-2` Lay Out & Print (`printtarg` → `.ti2` + TIFFs,
/// issues #9/#10, docs/09). Print controls are visible but inert —
/// real spooling lands in M3.
struct Stage2View: View {
    @Bindable var workflow: TargetWorkflowViewModel

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
        DisclosureGroup("Process log") {
            ScrollView {
                Text(workflow.printtargLog.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 100, maxHeight: 180)
            .accessibilityIdentifier("printtargLog")
        }
        .foregroundStyle(Theme.text)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("printtargLogContainer")
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

    // MARK: - Raw print panel (#rawPrintPanel) — unmanaged lp path

    private var printPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Print").font(.headline).foregroundStyle(Theme.text)
                if let notice = workflow.printNotice {
                    Image(systemName: workflow.printNoticeIsError
                          ? "xmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(workflow.printNoticeIsError
                                         ? .red : .blue)
                        .accessibilityIdentifier("printNotificationIcon")
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(workflow.printNoticeIsError
                                         ? .red : .secondary)
                        .accessibilityIdentifier("printNotificationText")
                }
                Spacer()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("printNotification")

            // Printer row: select + status + refresh + Preferences.
            HStack(spacing: 10) {
                Picker("Printer", selection: $workflow.selectedPrinter) {
                    ForEach(workflow.printers, id: \.name) { printer in
                        Text(printer.displayName ?? printer.name)
                            .tag(printer.name)
                    }
                }
                .frame(maxWidth: 320)
                .accessibilityIdentifier("printerSelect")
                .onChange(of: workflow.selectedPrinter) { _, _ in
                    workflow.selectedTray = nil
                    workflow.selectedMediaType = nil
                    Task { await workflow.reloadSelectedCapabilities() }
                }
                if let selected = workflow.printers
                    .first(where: { $0.name == workflow.selectedPrinter }) {
                    Text(selected.status.rawValue)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.background)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("printerStatusBadge")
                }
                Button(action: workflow.refreshPrinters) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh printer list")
                .accessibilityIdentifier("btnRefreshPrinters")
                Button(action: workflow.openPrinterPreferences) {
                    Image(systemName: "gearshape")
                }
                .help("Printer properties — bound NSPrintPanel")
                .disabled(workflow.selectedPrinter.isEmpty)
                .accessibilityIdentifier("btnPrinterProperties")
            }

            // Tray / media / orientation — from queue capabilities.
            HStack(spacing: 14) {
                if !workflow.printerCaps.trays.isEmpty {
                    Picker("Tray", selection: $workflow.selectedTray) {
                        ForEach(workflow.printerCaps.trays, id: \.id) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                    .frame(maxWidth: 200)
                    .accessibilityIdentifier("printerTraySelect")
                }
                if !workflow.printerCaps.mediaTypes.isEmpty {
                    Picker("Media", selection: $workflow.selectedMediaType) {
                        ForEach(workflow.printerCaps.mediaTypes, id: \.id) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                    .frame(maxWidth: 240)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("mediaTypeGroup")
                    .accessibilityIdentifier("printerMediaTypeSelect")
                }
                HStack(spacing: 0) {
                    Button("Portrait") { workflow.printOrientation = "portrait" }
                        .buttonStyle(.bordered)
                        .tint(workflow.printOrientation == "portrait" ? .accentColor : .gray)
                        .accessibilityIdentifier("btnOrientPortrait")
                    Button("Landscape") { workflow.printOrientation = "landscape" }
                        .buttonStyle(.bordered)
                        .tint(workflow.printOrientation == "landscape" ? .accentColor : .gray)
                        .accessibilityIdentifier("btnOrientLandscape")
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button(action: workflow.printAllPages) {
                    Label(workflow.isPrinting ? "Printing…" : "Print All",
                          systemImage: "printer")
                }
                .controlSize(.large)
                .disabled(workflow.isPrinting
                          || workflow.printtargResult == nil
                          || workflow.selectedPrinter.isEmpty)
                .accessibilityIdentifier("btnPrintAll")
                Spacer()
                Button("Advance to Stage 3") { workflow.advanceToStage3() }
                    .accessibilityIdentifier("btnAdvanceToStage3")
                    .disabled(workflow.printtargResult == nil
                              || !workflow.wizard.isUnlocked(.measure))
            }
        }
        .padding(12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rawPrintPanel")
        .task {
            // Auto-enumerate when the panel appears with a manifest.
            if workflow.printers.isEmpty, workflow.printtargResult != nil {
                workflow.refreshPrinters()
            }
        }
    }
}

/// One gallery cell: PNG preview + per-page Print button.
private struct GalleryPageView: View {
    let page: GalleryPage
    let workflow: TargetWorkflowViewModel

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
            Button("Print") { workflow.printPage(page) }
                .disabled(workflow.isPrinting
                          || workflow.selectedPrinter.isEmpty)
                .accessibilityIdentifier("btnPrintPage-\(page.index)")
        }
        .padding(8)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("galleryPage-\(page.index)")
    }
}
