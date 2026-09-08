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
                        GalleryPageView(page: page)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("galleryGrid")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tiffGallery")
        }
    }

    // MARK: - Raw print panel (#rawPrintPanel) — stubbed until M3

    private var printPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Print").font(.headline).foregroundStyle(Theme.text)
            Text("Unmanaged printing (lp) lands in Milestone 3.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("printNotification")
            HStack(spacing: 8) {
                Button("Print All") {}
                    .accessibilityIdentifier("btnPrintAll")
                    .disabled(true)
                Button("Refresh Printers") {}
                    .accessibilityIdentifier("btnRefreshPrinters")
                    .disabled(true)
                Button("Printer Properties") {}
                    .accessibilityIdentifier("btnPrinterProperties")
                    .disabled(true)
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
    }
}

/// One gallery cell: PNG preview + per-page stubbed Print button.
private struct GalleryPageView: View {
    let page: GalleryPage

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
            Button("Print") {}
                .disabled(true)
                .accessibilityIdentifier("btnPrintPage-\(page.index)")
        }
        .padding(8)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("galleryPage-\(page.index)")
    }
}
