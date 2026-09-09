import SwiftUI
import ICCeryCore

/// Stage 5 — verify the generated profile, track drift, and install.
struct Stage5View: View {
    @Bindable var model: ProfileWorkflowViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    verifySection
                    if let report = model.profcheckReport {
                        resultSection(report: report)
                    }
                    historySection
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear {
            model.restoreCreatedProfileURL()
            model.loadHistory()
        }
        .alert("Install profile", isPresented: $model.showingInstallCollision) {
            Button("Overwrite", role: .destructive) {
                model.resolveInstallCollision(policy: .overwrite)
            }
            .accessibilityIdentifier("profileOverwriteBtn")
            Button("Rename") {
                model.resolveInstallCollision(policy: .rename)
            }
            .accessibilityIdentifier("profileRenameBtn")
            Button("Cancel", role: .cancel) {
                model.resolveInstallCollision(policy: .cancel)
            }
            .accessibilityIdentifier("profileCancelCollisionBtn")
        } message: {
            Text(model.installCollisionMessage)
                .accessibilityIdentifier("profileInstallCollisionMessage")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.wizard.basename)
                    .font(.title3)
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("stage5TargetBasename")
                Text("Verify the profile and compare against historical results.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("stage5TargetMeta")
            }

            Spacer()

            if let alert = model.driftAlert {
                Text(alert)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(4)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("driftAlert")
            }

            if let warning = model.profcheckWarning, !warning.isEmpty {
                Text("⚠ \(warning)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(4)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("profcheckWarningBanner")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    // MARK: - Verify

    @ViewBuilder
    private var verifySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Verify Profile") {
                    model.verifyProfile()
                }
                .disabled(!model.canVerify)
                .accessibilityIdentifier("btnVerifyProfile")

                if model.isProfcheckRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                        .accessibilityIdentifier("profcheckProgressIndicator")
                }

                Spacer()

                if let profileURL = model.createdProfileURL {
                    Text(profileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("stage5ProfilePath")
                }
            }

            if !model.colprofLog.isEmpty {
                DisclosureGroup("Log") {
                    VStack(alignment: .leading) {
                        ForEach(model.colprofLog, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("profcheckLogContainer")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    // MARK: - Result cards

    @ViewBuilder
    private func resultSection(report: ProfcheckReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Verification result")
                    .font(.headline)
                    .foregroundStyle(Theme.text)

                Spacer()

                Button("Install Profile") { model.beginInstallProfile() }
                    .disabled(model.createdProfileURL == nil)
                    .accessibilityIdentifier("btnInstallProfile")
            }

            HStack(spacing: 16) {
                metricCard(title: "Avg ΔE", value: report.avgDE)
                metricCard(title: "Max ΔE", value: report.maxDE)
                metricCard(title: "RMS", value: report.rmsDE)
                metricCard(title: "Patches", value: report.patchCount.map(Double.init))
            }

            if let status = report.status {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(status.displayName)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor(status))
                        .accessibilityIdentifier("profcheckStatus")
                }
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    @ViewBuilder
    private func metricCard(title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.title3)
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History & drift")
                .font(.headline)
                .foregroundStyle(Theme.text)

            HStack {
                Picker("Printer", selection: Binding(
                    get: { model.driftPrinterFilter ?? "" },
                    set: { model.driftPrinterFilter = $0.isEmpty ? nil : $0 }
                )) {
                    Text("All").tag("")
                    ForEach(model.knownPrinters, id: \.self) { printer in
                        Text(printer.isEmpty ? "Unknown" : printer).tag(printer)
                    }
                }
                .accessibilityIdentifier("driftPrinterFilter")
                .frame(width: 200)

                Spacer()

                Button("Export CSV") { model.exportHistory() }
                    .accessibilityIdentifier("btnExportHistory")

                Button("Clear") { model.clearHistory() }
                    .accessibilityIdentifier("btnClearHistory")
            }

            driftChart

            if !model.filteredHistory.isEmpty {
                Table(of: VerificationRecord.self) {
                    TableColumn("Date") { record in
                        Text(record.timestamp.formatted(date: .numeric, time: .shortened))
                    }
                    TableColumn("Profile") { record in
                        Text(record.profileName)
                    }
                    TableColumn("Avg") { record in
                        Text(String(format: "%.2f", record.avgDE))
                    }
                    TableColumn("Max") { record in
                        Text(String(format: "%.2f", record.maxDE))
                    }
                    TableColumn("RMS") { record in
                        Text(String(format: "%.2f", record.rmsDE))
                    }
                    TableColumn("Status") { record in
                        Text(record.status.displayName)
                            .foregroundStyle(statusColor(record.status))
                    }
                } rows: {
                    ForEach(model.filteredHistory) { record in
                        TableRow(record)
                    }
                }
                .frame(minHeight: 120)
                .accessibilityIdentifier("verificationHistoryTable")
            } else {
                Text("No verification records yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    @ViewBuilder
    private var driftChart: some View {
        let records = model.filteredHistory.sorted { $0.timestamp < $1.timestamp }
        DriftChartView(records: records)
            .frame(height: 160)
            .accessibilityIdentifier("driftChart")
    }

    private func statusColor(_ status: VerificationStatus) -> Color {
        switch status {
        case .excellent, .good: return .green
        case .acceptable: return .yellow
        case .poor: return .red
        }
    }
}
