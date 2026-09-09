import AppKit
import SwiftUI
import ICCeryCore

/// Root layout: 270 pt sidebar + main stage area with the notification
/// banner pinned to the top (docs/21 §Shell).
struct RootView: View {
    @Bindable var workflow: TargetWorkflowViewModel
    @State private var showingSettings = false
    @State private var showingAbout = false

    private var model: WizardViewModel { workflow.wizard }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                workflow: workflow,
                onOpenSettings: { showingSettings = true },
                onOpenAbout: { showingAbout = true }
            )

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)

            VStack(spacing: 0) {
                if let notice = model.notice {
                    NoticeBanner(notice: notice, onClose: model.dismissNotice)
                }
                stageContent
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Theme.background)
        // #151: re-probe artefacts when the window regains focus —
        // files deleted in Finder must re-lock stages.
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSWindow.didBecomeKeyNotification
            )
        ) { _ in model.windowDidBecomeKey() }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $workflow.showingSavePreset) {
            SavePresetDialog(workflow: workflow)
        }
        .sheet(isPresented: $workflow.showingManagePresets) {
            ManagePresetsDialog(workflow: workflow)
        }
        .alert("ICCery 2.0.0", isPresented: $showingAbout) {
            Button("OK") {}
        } message: {
            Text("Native macOS printer profiling workstation.\nFull About dialog lands in issue #31.")
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch model.stage {
        case .generate:
            Stage1View(workflow: workflow)
        case .layOutPrint:
            Stage2View(workflow: workflow)
        case .measure:
            Stage3View(model: workflow.measurement)
        case .buildProfile:
            Stage4View(model: workflow.profile)
        case .verifyInstall:
            Stage5View(model: workflow.profile)
        default:
            StagePlaceholderView(stage: model.stage)
        }
    }
}
