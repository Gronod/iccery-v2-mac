import SwiftUI
import ICCeryCore

/// About dialog for ICCery (issue #31, docs/21 §Modals).
struct AboutView: View {
    let onClose: () -> Void

    private let info = ArtefactFiles.appInfo()

    var body: some View {
        VStack(spacing: 20) {
            Image("ICCery-logo")
                .resizable()
                .scaledToFit()
                .frame(height: 64)

            Text("ICCery")
                .font(.title)
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Version:")
                        .foregroundStyle(.secondary)
                    Text(info.version)
                        .foregroundStyle(Theme.text)
                        .accessibilityIdentifier("aboutVersion")
                }
                HStack {
                    Text("Build:")
                        .foregroundStyle(.secondary)
                    Text(info.build)
                        .foregroundStyle(Theme.text)
                }
                HStack {
                    Text("Build date:")
                        .foregroundStyle(.secondary)
                    Text(info.buildDate)
                        .foregroundStyle(Theme.text)
                        .accessibilityIdentifier("aboutBuildDate")
                }
            }
            .font(.callout)

            Text("Native macOS printer profiling workstation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") {
                onClose()
            }
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("closeAboutBtn")
        }
        .padding(32)
        .frame(width: 360)
        .background(Theme.panel)
        .accessibilityIdentifier("aboutDialog")
    }
}
