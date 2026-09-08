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
/// A fake resolver records every call; no private symbols are touched.
@Suite("ColorSyncSuppressor")
@MainActor
struct ColorSyncSuppressorTests {

    /// Fake PMPrintSession — the injected resolver never dereferences it.
    private var fakeSession: PMPrintSession {
        unsafeBitCast(UnsafeMutableRawPointer(bitPattern: 0xdead)!, to: PMPrintSession.self)
    }

    private func suppressor(
        succeeding symbol: String? = nil,
        mode: String = "AP_ApplicationColorMatching",
        calls: UnsafeMutablePointer<[(String, String)]>
    ) -> ColorSyncSuppressor {
        var s = ColorSyncSuppressor()
        s.log = { _ in }
        s.modeResolver = { name in
            // Missing symbol → nil (older macOS path).
            if name == "PMSessionSetColorMatchingModeLock" && symbol == nil {
                return nil
            }
            return { _, modeArg in
                calls.pointee.append((name, modeArg as String))
                return (name == symbol && (modeArg as String) == mode) ? 0 : 1
            }
        }
        return s
    }

    @Test("Attempt order: Lock → Mode → NoLock, AP_ prefix first")
    func attemptOrder() {
        let calls = UnsafeMutablePointer<[(String, String)]>.allocate(capacity: 1)
        calls.initialize(to: [])
        defer { calls.deallocate() }

        let s = suppressor(succeeding: nil, calls: calls)
        #expect(s.applySPIMode(to: fakeSession) == false)
        #expect(calls.pointee == ColorMatchingAttempts.attempts
            .map { ($0.symbol, $0.mode) }
            .filter { $0.0 != "PMSessionSetColorMatchingModeLock" })
    }

    @Test("First zero wins — later symbols not called")
    func firstZeroWins() {
        let calls = UnsafeMutablePointer<[(String, String)]>.allocate(capacity: 1)
        calls.initialize(to: [])
        defer { calls.deallocate() }

        let s = suppressor(
            succeeding: "PMSessionSetColorMatchingMode", calls: calls)
        #expect(s.applySPIMode(to: fakeSession))
        // Lock symbol missing → skipped; Mode tried AP_ then plain? No —
        // Mode succeeds on the first mode → 2 calls total.
        #expect(calls.pointee == [
            ("PMSessionSetColorMatchingMode", "AP_ApplicationColorMatching"),
        ])
        // NoLock never attempted.
        #expect(!calls.pointee.contains { $0.0 == "PMSessionSetColorMatchingModeNoLock" })
    }

    @Test("Mode fallback: AP_ rejected → ApplicationColorMatching tried")
    func modeFallback() {
        let calls = UnsafeMutablePointer<[(String, String)]>.allocate(capacity: 1)
        calls.initialize(to: [])
        defer { calls.deallocate() }

        var s = suppressor(
            succeeding: "PMSessionSetColorMatchingModeLock",
            mode: "ApplicationColorMatching",
            calls: calls)
        // Make the Lock symbol resolvable this time.
        let record: (String) -> ColorMatchingModeFunction? = { name in
            { _, modeArg in
                calls.pointee.append((name, modeArg as String))
                return (modeArg as String) == "ApplicationColorMatching" ? 0 : 1
            }
        }
        s.modeResolver = record
        #expect(s.applySPIMode(to: fakeSession))
        #expect(calls.pointee.first
            == ("PMSessionSetColorMatchingModeLock", "AP_ApplicationColorMatching"))
        #expect(calls.pointee.last
            == ("PMSessionSetColorMatchingModeLock", "ApplicationColorMatching"))
    }

    @Test("All symbols missing → false, no calls")
    func allMissing() {
        let calls = UnsafeMutablePointer<[(String, String)]>.allocate(capacity: 1)
        calls.initialize(to: [])
        defer { calls.deallocate() }
        var s = suppressor(succeeding: nil, calls: calls)
        s.modeResolver = { _ in nil }
        #expect(s.applySPIMode(to: fakeSession) == false)
        #expect(calls.pointee.isEmpty)
    }
}
