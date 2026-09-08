import SwiftUI
import ICCeryCore

/// 270 pt sidebar (docs/21 §Shell): logo, settings/about buttons, preset
/// select, Calibrate Printer + status chip, and the 1–5 stepper.
struct SidebarView: View {
    @Bindable var model: WizardViewModel
    var onOpenSettings: () -> Void
    var onOpenAbout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image("ICCery-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")
                Button(action: onOpenAbout) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help("About ICCery")
            }
            .padding(12)

            Divider().overlay(Theme.border)

            // Preset select (`#presetSelect`). Disabled until the preset
            // engine lands in issue #11.
            Picker("Preset", selection: .constant("none")) {
                Text("No preset").tag("none")
            }
            .pickerStyle(.menu)
            .disabled(true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Calibrate Printer (`#btnCalibratePrinter`). Disabled until
            // Stage 0 lands in issue #29; `#calStatusChip` likewise.
            Button(action: { model.enterCalibration() }) {
                Label("Calibrate Printer", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(true)
            .padding(.horizontal, 12)

            Divider().overlay(Theme.border)
                .padding(.vertical, 8)

            // Stepper 1–5.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(WizardStage.stepperStages, id: \.self) { stage in
                    StepperRow(
                        stage: stage,
                        isActive: model.stage == stage,
                        // Only Stage 1 until artefact gating lands in #4.
                        isEnabled: stage == .generate
                    ) {
                        model.go(to: stage)
                    }
                }
            }
            .padding(.horizontal, 6)

            Spacer()
        }
        .frame(width: Theme.Metrics.sidebarWidth)
        .background(Theme.panel)
    }
}

private struct StepperRow: View {
    let stage: WizardStage
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isActive ? Theme.accent : Theme.border)
                        .frame(width: 26, height: 26)
                    Text("\(stage.stepperIndex ?? 0)")
                        .font(.callout.bold())
                        .foregroundStyle(isActive ? .white : Theme.text)
                }
                Label(stage.title, systemImage: stage.symbolName)
                    .font(.callout)
                    .foregroundStyle(isActive ? Theme.text : .secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium)
                .fill(isActive ? Theme.accent.opacity(0.15) : .clear)
        )
    }
}
