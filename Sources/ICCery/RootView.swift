import AppKit
import SwiftUI
import ICCeryCore

/// Root layout: 270 pt sidebar + main stage area with the notification
/// banner pinned to the top (docs/21 §Shell).
struct RootView: View {
    @ObservedObject var workflow: TargetWorkflowViewModel
    /// Observed directly: nested ObservableObjects are not tracked
    /// through the parent's `objectWillChange`.
    @ObservedObject private var model: WizardViewModel
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingAllHelp = false

    init(workflow: TargetWorkflowViewModel) {
        self.workflow = workflow
        self._model = ObservedObject(wrappedValue: workflow.wizard)
    }

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
                WizardStageContent(model: model, workflow: workflow)
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
        .sheet(isPresented: Binding(
            get: { workflow.wizard.showingGamutViewer },
            set: { workflow.wizard.showingGamutViewer = $0 }
        )) {
            GamutView(profileGamURL: workflow.wizard.gamutProfileURL)
        }
    }

}

/// Content for the active wizard stage. Isolated into its own view so that
/// `WizardViewModel` is tracked via `@ObservedObject` instead of the parent's
/// `TargetWorkflowViewModel`, which does not observe nested `wizard` mutations.
private struct WizardStageContent: View {
    @ObservedObject var model: WizardViewModel
    @ObservedObject var workflow: TargetWorkflowViewModel

    var body: some View {
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
            CalibrationView(model: workflow.calibration, wizard: workflow.wizard)
        @unknown default:
            Stage1View(workflow: workflow)
        }
    }
}
