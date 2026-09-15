import XCTest
import Foundation
@testable import ICCeryCore
@testable import ICCery
import AppKit
import ApplicationServices

/// Issue 14 — PMPrintSettingsToOptions capture filter (docs/11 layer ⑥).
final class CupsOptionsFilterTests: XCTestCase {

    func testDropsReserved() {
        let raw = "AP_ColorMatchingMode=AP_ApplicationColorMatching "
            + "AP.ColorMatchingMode=AP_ApplicationColorMatching "
            + "com.apple.print.JobTicket.PMTotalSidesImaged=0 "
            + "collate=true copies=1 job-sheets=none,none "
            + "pserrorhandler-requested=standard "
            + "MediaType=PhotographicGlossy"
        XCTAssertEqual(CupsOptionsFilter.filter(raw), "MediaType=PhotographicGlossy")
    }

    func testKeepsRelevant() {
        let raw = "InputSlot=Rear PageSize=A4 CNIJIntent2=4 "
            + "Resolution=600x600dpi Duplex=None"
        XCTAssertEqual(CupsOptionsFilter.filter(raw), raw)
    }

    /// #180 — a captured `EPIJ_Qual` (and the other canonical quality
    /// keys) survives the filter so it wins over the Stage 2 explicit
    /// quality in `LpArgs`.
    func testKeepsQualityKeys() {
        let raw = "EPIJ_Qual=304 CNIJPrintQuality=3 PrintQuality=2 "
            + "cupsPrintQuality=High Quality=Best "
            + "com.apple.print.JobTicket.PMTotalSidesImaged=0"
        XCTAssertEqual(CupsOptionsFilter.filter(raw),
            "EPIJ_Qual=304 CNIJPrintQuality=3 PrintQuality=2 "
            + "cupsPrintQuality=High Quality=Best")
    }

    func testKeepsUnknown() {
        let raw = "VendorFooBar=baz MediaType=Plain"
        XCTAssertEqual(CupsOptionsFilter.filter(raw), raw)
    }

    func testDropsEmpty() {
        let raw = "=noval MediaType= InputSlot=Rear"
        // "MediaType=" has an empty value → dropped; "=noval" empty key.
        XCTAssertEqual(CupsOptionsFilter.filter(raw), "InputSlot=Rear")
    }

    func testExtractMedia() {
        XCTAssertEqual(CupsParsers.extractMediaType(
            fromOptionsString: "MediaType=Photo EPIJ_Medi=1"), "Photo")
        XCTAssertEqual(CupsParsers.extractMediaType(
            fromOptionsString: "EPIJ_Medi=7"), "7")
        XCTAssertNil(CupsParsers.extractMediaType(
            fromOptionsString: "PageSize=A4"))
    }
}

/// Issue 14 — the dlsym attempt order and first-success semantics.
/// `@convention(c)` closures can't capture, so recording goes through
/// a file-scope recorder keyed by global state; no private symbols are
/// touched.
@MainActor
final class ColorSyncSuppressorTests: XCTestCase {

    /// Fake PMPrintSession — the injected resolver never dereferences it.
    private var fakeSession: PMPrintSession {
        unsafeBitCast(UnsafeMutableRawPointer(bitPattern: 0xdead)!, to: PMPrintSession.self)
    }

    /// Call log — static since `@convention(c)` can't capture. The
    /// resolver sets `currentSymbol` right before each call, so the C
    /// function records (symbol, mode) without capturing `name`.
    private static var recorded: [(String, String)] = []
    private static var currentSymbol = ""
    private static var succeeding: (String, String)?
    private static var missing: Set<String> = []

    private func makeSuppressor() -> ColorSyncSuppressor {
        var s = ColorSyncSuppressor()
        s.log = { _ in }
        s.modeResolver = { name in
            if Self.missing.contains(name) { return nil }
            Self.currentSymbol = name
            // `Self` inside a @convention(c) closure is a dynamic-Self
            // capture — spell the (final) class name instead.
            return { _, modeArg in
                ColorSyncSuppressorTests.recorded.append(
                    (ColorSyncSuppressorTests.currentSymbol, modeArg as String))
                if let ok = ColorSyncSuppressorTests.succeeding,
                   ColorSyncSuppressorTests.currentSymbol == ok.0,
                   (modeArg as String) == ok.1 {
                    return 0
                }
                return 1
            }
        }
        return s
    }

    func testAttemptOrder() {
        Self.recorded = []
        Self.succeeding = nil
        Self.missing = ["PMSessionSetColorMatchingModeLock"]
        let s = makeSuppressor()
        XCTAssertEqual(s.applySPIMode(to: fakeSession), false)
        // Lock is unresolvable → skipped; the rest plays out in order.
        XCTAssertEqual(Self.recorded.map { "\($0.0)|\($0.1)" }, ColorMatchingAttempts.attempts
                .filter { $0.symbol != "PMSessionSetColorMatchingModeLock" }
                .map { "\($0.symbol)|\($0.mode)" })
    }

    func testFirstZeroWins() {
        Self.recorded = []
        Self.succeeding = ("PMSessionSetColorMatchingModeLock",
                           "AP_ApplicationColorMatching")
        Self.missing = []
        let s = makeSuppressor()
        XCTAssertTrue(s.applySPIMode(to: fakeSession))
        XCTAssertEqual(Self.recorded.map { "\($0.0)|\($0.1)" }, [
            "PMSessionSetColorMatchingModeLock|AP_ApplicationColorMatching",
        ])
    }

    func testModeFallback() {
        Self.recorded = []
        Self.succeeding = ("PMSessionSetColorMatchingModeLock",
                           "ApplicationColorMatching")
        Self.missing = []
        let s = makeSuppressor()
        XCTAssertTrue(s.applySPIMode(to: fakeSession))
        XCTAssertEqual(Self.recorded[0].0, "PMSessionSetColorMatchingModeLock")
        XCTAssertEqual(Self.recorded[0].1, "AP_ApplicationColorMatching")
        XCTAssertEqual(Self.recorded[1].0, "PMSessionSetColorMatchingModeLock")
        XCTAssertEqual(Self.recorded[1].1, "ApplicationColorMatching")
        XCTAssertEqual(Self.recorded.count, 2)
    }

    func testAllMissing() {
        Self.recorded = []
        Self.succeeding = nil
        Self.missing = Set(ColorMatchingAttempts.symbols)
        let s = makeSuppressor()
        XCTAssertEqual(s.applySPIMode(to: fakeSession), false)
        XCTAssertTrue(Self.recorded.isEmpty)
    }
}
