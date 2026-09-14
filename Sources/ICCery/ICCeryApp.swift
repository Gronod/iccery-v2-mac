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
    /// GitHub-hosted Macs (and any display smaller than 1280×800) must
    /// not get a window that hangs off-screen — XCTest then reports
    /// sidebar controls at negative x as not hittable (run 34864198118).
    private func configureMainWindow(_ window: NSWindow) {
        let desired = NSSize(width: 1280, height: 800)
        let minimum = NSSize(width: 1100, height: 700)
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(origin: .zero, size: desired)

        window.contentMinSize = NSSize(
            width: min(minimum.width, visible.width),
            height: min(minimum.height, visible.height)
        )
        window.setContentSize(NSSize(
            width: min(desired.width, visible.width),
            height: min(desired.height, max(minimum.height, visible.height - 40))
        ))
        window.center()

        var frame = window.frame
        if frame.width > visible.width {
            frame.size.width = visible.width
        }
        if frame.height > visible.height {
            frame.size.height = visible.height
        }
        frame.origin.x = min(
            max(frame.origin.x, visible.minX),
            visible.maxX - frame.width
        )
        frame.origin.y = min(
            max(frame.origin.y, visible.minY),
            visible.maxY - frame.height
        )
        window.setFrame(frame, display: true)
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
