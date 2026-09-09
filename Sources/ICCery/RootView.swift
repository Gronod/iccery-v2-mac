import AppKit
import SwiftUI
import ICCeryCore

/// Root layout: 270 pt sidebar + main stage area with the notification
/// banner pinned to the top (docs/21 §Shell).
struct RootView: View {
    @Bindable var workflow: TargetWorkflowViewModel
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingAllHelp = false

    private var model: WizardViewModel { workflow.wizard }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                workflow: workflow,
                onOpenSettings: { showingSettings = true },
                onOpenAbout: { showingAbout = true },
                showingAllHelp: $showingAllHelp
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
        .sheet(isPresented: $showingAbout) {
            AboutView { showingAbout = false }
        }
        .sheet(isPresented: $workflow.wizard.showingGamutViewer) {
            GamutView(profileGamURL: workflow.wizard.gamutProfileURL)
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
        case .calibrate:
            CalibrationView(model: workflow.calibration)
        @unknown default:
            StagePlaceholderView(stage: model.stage)
        }
    }
}
