import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue 13 — panel outcome mapping (cancel → nil, ok → result).
/// The real `NSPrintPanel` is never run in tests; these exercise the
/// `UITestHooks` seam the UI tests rely on.
final class PrintPanelStubTests: XCTestCase {

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

    func testCancelIsNil() throws {
        try withEnv([
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_PRINT_PANEL": "cancel",
        ]) {
            XCTAssertTrue(UITestHooks.printPanelStubbed)
            XCTAssertNil(UITestHooks.printPanelResult(forQueue: "q"))
        }
    }

    func testOkResult() throws {
        try withEnv([
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_PRINT_PANEL": "ok",
            "ICCERY_TEST_PANEL_OPTIONS": "MediaType=Photo InputSlot=Rear",
            "ICCERY_TEST_PANEL_PRINTER": "Other_Queue",
        ]) {
            let result = UITestHooks.printPanelResult(forQueue: "q")
            XCTAssertEqual(result?.selectedPrinter, "Other_Queue")
            XCTAssertEqual(result?.options.cupsOptions, "MediaType=Photo InputSlot=Rear")
            XCTAssertEqual(result?.options.mediaType, "Photo")
            XCTAssertEqual(result?.options.ppdUncorrectedPassthrough, true)
        }
    }

    /// #183 — the stub parses paper size / quality / orientation out of
    /// `ICCERY_TEST_PANEL_OPTIONS` so UI tests can verify apply-back.
    func testOkResultExtractsNewFields() throws {
        try withEnv([
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_PRINT_PANEL": "ok",
            "ICCERY_TEST_PANEL_OPTIONS":
                "PageSize=Letter EPIJ_Qual=305 orientation-requested=4",
            "ICCERY_TEST_PANEL_PRINTER": nil,
        ]) {
            let result = UITestHooks.printPanelResult(forQueue: "q")
            XCTAssertEqual(result?.options.paperSize, "Letter")
            XCTAssertEqual(result?.options.quality, "305")
            XCTAssertEqual(result?.options.orientation, "landscape")
        }
    }

    func testOkDefaultsPrinter() throws {
        try withEnv([
            "ICCERY_UI_TESTING": "1",
            "ICCERY_TEST_PRINT_PANEL": "ok",
            "ICCERY_TEST_PANEL_OPTIONS": nil,
            "ICCERY_TEST_PANEL_PRINTER": nil,
        ]) {
            let result = UITestHooks.printPanelResult(forQueue: "My_Queue")
            XCTAssertEqual(result?.selectedPrinter, "My_Queue")
            XCTAssertNil(result?.options.cupsOptions)
        }
    }
}
