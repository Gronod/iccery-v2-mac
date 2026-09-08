import AppKit
import SwiftUI

@main
struct ICCeryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = WizardViewModel()

    var body: some Scene {
        // Single fixed window (docs/21 §Shell: 1280×800, min 1100×700).
        Window("ICCery", id: "main") {
            RootView(model: model)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
    }
}

/// AppDelegate: quit when the single window closes, and give later
/// milestones a hook to `killAll` Argyll children before teardown
/// (#147/#149 — wired once ProcessManager exists in #2).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Issue #2+: ProcessManager.shared.killAll()
    }
}
