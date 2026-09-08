import Testing
import Foundation
@testable import ICCeryCore
@testable import ICCery

/// Issue 13 — panel outcome mapping (cancel → nil, ok → result).
/// The real `NSPrintPanel` is never run in tests; these exercise the
/// `UITestHooks` seam the UI tests rely on.
@Suite("PrintPanelStub")
struct PrintPanelStubTests {

    private func withEnv(
        _ vars: [String: String?],
        _ body: () throws -> Void
    ) rethrows {
        var saved: [String: String?] = [:]
        for key in vars.keys {
            saved[key] = ProcessInfo.processInfo.environment[key]
        }
        for (key, value) in vars {
            if let value { setenv(key, value, 1) } else { unsetenv(key) }
        }
        defer {
            for (key, value) in saved {
                if let value { setenv(key, value, 1) } else { unsetenv(key) }
            }
        }
        try body()
    }

    @Test("Cancel returns nil — not an error")
    func cancelIsNil() throws {
        try withEnv([
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_PRINT_PANEL": "cancel",
        ]) {
            #expect(UITestHooks.printPanelStubbed)
            #expect(UITestHooks.printPanelResult(forQueue: "q") == nil)
        }
    }

    @Test("OK returns captured options + selected printer")
    func okResult() throws {
        try withEnv([
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_PRINT_PANEL": "ok",
            "ICCERY_TEST_PANEL_OPTIONS": "MediaType=Photo InputSlot=Rear",
            "ICCERY_TEST_PANEL_PRINTER": "Other_Queue",
        ]) {
            let result = UITestHooks.printPanelResult(forQueue: "q")
            #expect(result?.selectedPrinter == "Other_Queue")
            #expect(result?.options.cupsOptions == "MediaType=Photo InputSlot=Rear")
            #expect(result?.options.mediaType == "Photo")
            #expect(result?.options.ppdUncorrectedPassthrough == true)
        }
    }

    @Test("OK defaults selected printer to the opened queue")
    func okDefaultsPrinter() throws {
        try withEnv([
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_PRINT_PANEL": "ok",
            "ICCERY_TEST_PANEL_OPTIONS": nil,
            "ICCERY_TEST_PANEL_PRINTER": nil,
        ]) {
            let result = UITestHooks.printPanelResult(forQueue: "My_Queue")
            #expect(result?.selectedPrinter == "My_Queue")
            #expect(result?.options.cupsOptions == nil)
        }
    }
}
