import AppKit
import ICCeryCore
import SwiftUI

@main
struct ICCeryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workflow: TargetWorkflowViewModel

    init() {
        let environment = AppEnvironment.live()
        _workflow = StateObject(wrappedValue: TargetWorkflowViewModel(environment: environment))
        try? AppPaths.ensureDirectories()
        // Log level is runtime state — apply persisted settings at
        // startup (#158); the Settings sheet re-applies on save.
        LogSink.shared.applySettings(environment.settingsStore.load())
    }

    var body: some Scene {
        // Single fixed window (docs/21 §Shell: 1280×800, min 1100×700);
        // metrics are applied by AppDelegate once the window exists.
        WindowGroup("ICCery") {
            RootView(workflow: workflow)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .commands {
            // Single-window app: the File menu carries the project
            // commands (issue #149). Replacing `.newItem` keeps
            // SwiftUI's empty default New from stacking (R19 — the
            // group is filled, so no second New appears).
            CommandGroup(replacing: .newItem) {
                ProjectCommands(workflow: workflow)
            }
        }
    }
}

/// AppDelegate: quit when the single window closes, and `killAll` Argyll
/// children before teardown (#147/#149). Termination is deferred until
/// `killAll` has signaled every child so `chartread` can park an XY head
/// when the UI already sent `q\n`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI scenes launched by XCTest stay `.runningBackground`
        // unless the app takes regular activation and orders the window
        // front (CI run 29804).
        NSApp.setActivationPolicy(.regular)
        for window in NSApp.windows {
            configureMainWindow(window)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// docs/21 §Shell: 1280×800 content, min 1100×700, centred.
    private func configureMainWindow(_ window: NSWindow) {
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.contentMinSize = NSSize(width: 1100, height: 700)
        window.center()
    }

    /// Dock-click reopen: let the WindowGroup re-show or recreate the
    /// main window when none are visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationRequested else { return .terminateNow }
        terminationRequested = true
        Task {
            await ProcessManager.shared.killAll()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
