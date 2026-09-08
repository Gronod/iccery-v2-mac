import SwiftUI

/// Root layout: 270 pt sidebar + main stage area with the notification
/// banner pinned to the top (docs/21 §Shell).
struct RootView: View {
    @Bindable var model: WizardViewModel
    @State private var showingSettings = false
    @State private var showingAbout = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                model: model,
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
                StagePlaceholderView(stage: model.stage)
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Theme.background)
        .sheet(isPresented: $showingSettings) {
            // Full settings dialog lands in issue #5.
            VStack(spacing: 12) {
                Text("Settings").font(.headline)
                Text("Implemented in issue #5.")
                    .foregroundStyle(.secondary)
                Button("Close") { showingSettings = false }
            }
            .padding(24)
            .frame(width: 420)
        }
        .alert("ICCery 2.0.0", isPresented: $showingAbout) {
            Button("OK") {}
        } message: {
            Text("Native macOS printer profiling workstation.\nFull About dialog lands in issue #31.")
        }
    }
}
