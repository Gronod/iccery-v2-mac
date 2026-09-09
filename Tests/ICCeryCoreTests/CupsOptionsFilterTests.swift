import Testing
import Foundation
@testable import ICCeryCore
@testable import ICCery
import AppKit
import ApplicationServices

/// Issue 14 — PMPrintSettingsToOptions capture filter (docs/11 layer ⑥).
@Suite("CupsOptionsFilter")
struct CupsOptionsFilterTests {

    @Test("Drops com.apple.*, collate, copies, job-sheets, AP_* keys")
    func dropsReserved() {
        let raw = "AP_ColorMatchingMode=AP_ApplicationColorMatching "
            + "AP.ColorMatchingMode=AP_ApplicationColorMatching "
            + "com.apple.print.JobTicket.PMTotalSidesImaged=0 "
            + "collate=true copies=1 job-sheets=none,none "
            + "pserrorhandler-requested=standard "
            + "MediaType=PhotographicGlossy"
        #expect(CupsOptionsFilter.filter(raw) == "MediaType=PhotographicGlossy")
    }

    @Test("Keeps relevant driver keys, order preserved")
    func keepsRelevant() {
        let raw = "InputSlot=Rear PageSize=A4 CNIJIntent2=4 "
            + "Resolution=600x600dpi Duplex=None"
        #expect(CupsOptionsFilter.filter(raw) == raw)
    }

    @Test("Permissive: unknown non-com.* keys survive")
    func keepsUnknown() {
        let raw = "VendorFooBar=baz MediaType=Plain"
        #expect(CupsOptionsFilter.filter(raw) == raw)
    }

    @Test("Drops empty keys and values")
    func dropsEmpty() {
        let raw = "=noval MediaType= InputSlot=Rear"
        // "MediaType=" has an empty value → dropped; "=noval" empty key.
        #expect(CupsOptionsFilter.filter(raw) == "InputSlot=Rear")
    }

    @Test("extractMediaType prefers MediaType then EPIJ_Medi")
    func extractMedia() {
        #expect(CupsParsers.extractMediaType(
            fromOptionsString: "MediaType=Photo EPIJ_Medi=1") == "Photo")
        #expect(CupsParsers.extractMediaType(
            fromOptionsString: "EPIJ_Medi=7") == "7")
        #expect(CupsParsers.extractMediaType(
            fromOptionsString: "PageSize=A4") == nil)
    }
}

/// Issue 14 — the dlsym attempt order and first-success semantics.
/// `@convention(c)` closures can't capture, so recording goes through
/// a file-scope recorder keyed by global state; no private symbols are
/// touched.
@Suite("ColorSyncSuppressor")
@MainActor
struct ColorSyncSuppressorTests {

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
            return { _, modeArg in
                Self.recorded.append((Self.currentSymbol, modeArg as String))
                if let ok = Self.succeeding,
                   Self.currentSymbol == ok.0, (modeArg as String) == ok.1 {
                    return 0
                }
                return 1
            }
        }
        return s
    }

    @Test("Attempt order: Lock → Mode → NoLock, AP_ prefix first")
    func attemptOrder() {
        Self.recorded = []
        Self.succeeding = nil
        Self.missing = ["PMSessionSetColorMatchingModeLock"]
        let s = makeSuppressor()
        #expect(s.applySPIMode(to: fakeSession) == false)
        // Lock is unresolvable → skipped; the rest plays out in order.
        #expect(Self.recorded.map { "\($0.0)|\($0.1)" }
            == ColorMatchingAttempts.attempts
                .filter { $0.symbol != "PMSessionSetColorMatchingModeLock" }
                .map { "\($0.symbol)|\($0.mode)" })
    }

    @Test("First zero wins — later symbols/modes not called")
    func firstZeroWins() {
        Self.recorded = []
        Self.succeeding = ("PMSessionSetColorMatchingModeLock",
                           "AP_ApplicationColorMatching")
        Self.missing = []
        let s = makeSuppressor()
        #expect(s.applySPIMode(to: fakeSession))
        #expect(Self.recorded.map { "\($0.0)|\($0.1)" } == [
            "PMSessionSetColorMatchingModeLock|AP_ApplicationColorMatching",
        ])
    }

    @Test("Mode fallback: AP_ rejected → ApplicationColorMatching tried")
    func modeFallback() {
        Self.recorded = []
        Self.succeeding = ("PMSessionSetColorMatchingModeLock",
                           "ApplicationColorMatching")
        Self.missing = []
        let s = makeSuppressor()
        #expect(s.applySPIMode(to: fakeSession))
        #expect(Self.recorded[0].0 == "PMSessionSetColorMatchingModeLock")
        #expect(Self.recorded[0].1 == "AP_ApplicationColorMatching")
        #expect(Self.recorded[1].0 == "PMSessionSetColorMatchingModeLock")
        #expect(Self.recorded[1].1 == "ApplicationColorMatching")
        #expect(Self.recorded.count == 2)
    }

    @Test("All symbols missing → false, no calls")
    func allMissing() {
        Self.recorded = []
        Self.succeeding = nil
        Self.missing = Set(ColorMatchingAttempts.symbols)
        let s = makeSuppressor()
        #expect(s.applySPIMode(to: fakeSession) == false)
        #expect(Self.recorded.isEmpty)
    }
}
