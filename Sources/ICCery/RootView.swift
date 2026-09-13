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
    @ObservedObject private var project: ProjectSession
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingAllHelp = false

    init(workflow: TargetWorkflowViewModel) {
        self.workflow = workflow
        self._model = ObservedObject(wrappedValue: workflow.wizard)
        self._project = ObservedObject(wrappedValue: workflow.project)
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
        // Media library sheets live on RootView, never inside the
        // 270 pt sidebar column (#146).
        .sheet(isPresented: $workflow.showingSaveMedia) {
            SaveMediaRecipeDialog(workflow: workflow)
        }
        .sheet(
            isPresented: $workflow.showingManageMedia,
            onDismiss: { workflow.media.manageDismissed() }
        ) {
            ManageMediaDialog(workflow: workflow)
        }
        // Spot-read console sheet (issue #148). Dismiss runs the same
        // `q\n` + ~500 ms + kill path as the sheet's Stop button.
        .sheet(
            isPresented: $workflow.showingSpotRead,
            onDismiss: { workflow.spotRead.sheetClosed() }
        ) {
            SpotReadView(model: workflow.spotRead)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView { showingAbout = false }
        }
        .sheet(isPresented: Binding(
            get: { workflow.wizard.showingGamutViewer },
            set: { workflow.wizard.showingGamutViewer = $0 }
        )) {
            GamutView(
                environment: workflow.environment,
                profileGamURL: workflow.wizard.gamutProfileURL,
                showingAllHelp: $showingAllHelp)
        }
        // Project file chrome (issue #149): window title, New confirm
        // alert, dirty alert, relocate sheet. Panels never appear from
        // a View — UITestHooks inject fixture paths instead.
        .onReceive(project.$windowTitle) { title in
            for window in NSApp.windows where !(window is NSPanel) {
                window.title = title
            }
        }
        .alert("Start a new project?", isPresented: $project.showingNewAlert) {
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("btnProjectNewCancel")
            Button("Start") { project.confirmNew() }
                .accessibilityIdentifier("btnProjectNewConfirm")
        } message: {
            Text("The working folder and targets on disk are not deleted.")
                .accessibilityIdentifier("projectNewAlert")
        }
        .alert(
            "Save the current project first?",
            isPresented: $project.showingDirtyAlert
        ) {
            Button("Save") { project.resolveDirty(save: true) }
                .accessibilityIdentifier("btnProjectDirtySave")
            Button("Don't Save") { project.resolveDirty(save: false) }
                .accessibilityIdentifier("btnProjectDirtyDiscard")
            Button("Cancel", role: .cancel) { project.cancelDirty() }
                .accessibilityIdentifier("btnProjectDirtyCancel")
        }
        .sheet(isPresented: $project.showingRelocateSheet) {
            ProjectRelocateSheet(project: project)
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
