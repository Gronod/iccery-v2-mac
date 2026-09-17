import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue #201 Phase 4 — the resolved ticket-write list that replaces
/// the `lp` argv goldens: locked order 1–10, D6 (Stage 2 always
/// wins), `raw` can never appear.
final class TicketWriteResolverTests: XCTestCase {

    private func resolve(
        overrides: TargetPrintOverrides = TargetPrintOverrides(),
        optionKeys: Set<String> = []
    ) -> ResolvedTicketWrites {
        TicketWriteResolver.resolve(
            overrides: overrides, optionKeys: optionKeys)
    }

    private func keys(_ r: ResolvedTicketWrites) -> [String] {
        r.writes.map(\.key)
    }

    private func value(
        _ key: String, in r: ResolvedTicketWrites
    ) -> String? {
        r.writes.first { $0.key == key }?.value
    }

    /// Both AP_* spellings are always present and locked; all three
    /// Quartz keys are always present (D2 dual vocabulary).
    func testColourKeysAlwaysPresent() {
        let r = resolve()
        let ap = r.writes.filter {
            ColorMatchingAttempts.printSettingsKeys.contains($0.key)
        }
        XCTAssertEqual(ap.count, 2)
        XCTAssertTrue(ap.allSatisfy {
            $0.locked
                && $0.value == "AP_ApplicationColorMatching"
        })
        XCTAssertEqual(value("PMColorMatchingMode", in: r),
            "APCustomColorMatching")
        XCTAssertEqual(value("PMCustomColorMatchingProfile", in: r), "")
        XCTAssertEqual(
            value("com.apple.print.PrintSettings.PMColorMatchingMode",
                  in: r),
            "APCustomColorMatching")
        // The Quartz mode key is locked; profile + legacy key are not.
        XCTAssertTrue(r.writes.first { $0.key == "PMColorMatchingMode" }!
            .locked)
        XCTAssertFalse(r.writes.first {
            $0.key == "PMCustomColorMatchingProfile" }!.locked)
        XCTAssertFalse(r.writes.first {
            $0.key == "com.apple.print.PrintSettings.PMColorMatchingMode"
        }!.locked)
    }

    /// `raw` can never appear — there is no `lp` and the resolver has
    /// no captured-options input that could smuggle it in (#92).
    func testRawNeverAppears() {
        for optionKeys in [Set<String>(), ["raw"],
                           ["MediaType", "raw"]] {
            let r = resolve(
                overrides: TargetPrintOverrides(
                    paperSize: "raw", mediaType: "raw",
                    qualityKey: "raw", quality: "raw",
                    orientation: "raw"),
                optionKeys: optionKeys)
            XCTAssertFalse(r.writes.contains {
                $0.key.lowercased() == "raw"
            })
        }
    }

    /// D6 inversion — the deleted argv builder suppressed the Stage 2
    /// value when the captured string already carried the key (the old
    /// media branch at `build`'s line 81). There is no captured-wins
    /// path any more:
    /// the explicit Stage 2 value is emitted unconditionally.
    func testStage2MediaTypeAlwaysWins() {
        let r = resolve(
            overrides: TargetPrintOverrides(mediaType: "Matte"),
            optionKeys: ["MediaType"])
        XCTAssertEqual(value("MediaType", in: r), "Matte")
        // …and likewise for a vendor key — nothing consults captured
        // options before writing.
        let epson = resolve(
            overrides: TargetPrintOverrides(mediaType: "Matte"),
            optionKeys: ["EPIJ_Medi"])
        XCTAssertEqual(value("EPIJ_Medi", in: epson), "Matte")
    }

    /// Vendor media-key selection follows `CupsParsers.mediaTypeKeys`:
    /// `EPIJ_Medi` is picked when present; `CNIJMediaType` beats
    /// `MediaType`.
    func testVendorMediaKeySelection() {
        let epson = resolve(
            overrides: TargetPrintOverrides(mediaType: "Photo"),
            optionKeys: ["EPIJ_Medi", "MediaType"])
        XCTAssertEqual(value("EPIJ_Medi", in: epson), "Photo")
        XCTAssertNil(value("MediaType", in: epson))

        let canon = resolve(
            overrides: TargetPrintOverrides(mediaType: "Photo"),
            optionKeys: ["CNIJMediaType", "MediaType"])
        XCTAssertEqual(value("CNIJMediaType", in: canon), "Photo")
        XCTAssertNil(value("MediaType", in: canon))
    }

    /// Driver "no colour adjustment" bypass — Canon, Epson (CCor
    /// preferred over CMat), Gutenprint — always unlocked and never
    /// gated on `ppdUncorrectedPassthrough`.
    func testDriverBypass() {
        let canon = resolve(optionKeys: ["CNIJIntent2"])
        XCTAssertEqual(value("CNIJIntent2", in: canon), "4")
        XCTAssertFalse(canon.writes.first { $0.key == "CNIJIntent2" }!
            .locked)

        let epson = resolve(optionKeys: ["EPIJ_CCor", "EPIJ_CMat"])
        XCTAssertEqual(value("EPIJ_CCor", in: epson), "0")
        XCTAssertNil(value("EPIJ_CMat", in: epson))

        let epsonMat = resolve(optionKeys: ["EPIJ_CMat"])
        XCTAssertEqual(value("EPIJ_CMat", in: epsonMat), "3")

        let gutenprint = resolve(optionKeys: ["StpColorCorrection"])
        XCTAssertEqual(value("StpColorCorrection", in: gutenprint),
            "Uncorrected")

        XCTAssertNil(value("EPIJ_CMat", in: resolve()))
    }

    /// Orientation: landscape → 4, portrait → 3, nil → no write.
    func testOrientation() {
        XCTAssertEqual(
            value("orientation-requested", in: resolve(
                overrides: TargetPrintOverrides(
                    orientation: "landscape"))),
            "4")
        XCTAssertEqual(
            value("orientation-requested", in: resolve(
                overrides: TargetPrintOverrides(
                    orientation: "portrait"))),
            "3")
        XCTAssertNil(value("orientation-requested", in: resolve()))
    }

    /// A `nil` override emits no write for that key; quality needs
    /// **both** the detected key and the value.
    func testNilOverridesEmitNoWrite() {
        let r = resolve(optionKeys: ["MediaType", "EPIJ_Qual"])
        XCTAssertNil(value("PageSize", in: r))
        XCTAssertNil(value("MediaType", in: r))
        XCTAssertNil(value("EPIJ_Qual", in: r))
        XCTAssertNil(value("orientation-requested", in: r))
        XCTAssertNil(r.paperToken)
        XCTAssertNil(r.orientation)

        let keyOnly = resolve(
            overrides: TargetPrintOverrides(qualityKey: "EPIJ_Qual"),
            optionKeys: ["EPIJ_Qual"])
        XCTAssertNil(value("EPIJ_Qual", in: keyOnly))
        let valueOnly = resolve(
            overrides: TargetPrintOverrides(quality: "305"),
            optionKeys: ["EPIJ_Qual"])
        XCTAssertNil(value("EPIJ_Qual", in: valueOnly))
        // An empty paper token emits no write and no paperToken.
        let emptyPaper = resolve(
            overrides: TargetPrintOverrides(paperSize: ""))
        XCTAssertNil(value("PageSize", in: emptyPaper))
        XCTAssertNil(emptyPaper.paperToken)
    }

    /// The write list equals the locked 1–10 order, exactly.
    func testLockedWriteOrder() {
        let r = resolve(
            overrides: TargetPrintOverrides(
                paperSize: "A4", mediaType: "Photo",
                qualityKey: "EPIJ_Qual", quality: "305",
                orientation: "landscape"),
            optionKeys: ["MediaType", "EPIJ_Qual", "EPIJ_CMat"])
        XCTAssertEqual(keys(r), [
            "AP_ColorMatchingMode",
            "AP.ColorMatchingMode",
            "PMColorMatchingMode",
            "PMCustomColorMatchingProfile",
            "com.apple.print.PrintSettings.PMColorMatchingMode",
            "PageSize",
            "MediaType",
            "EPIJ_Qual",
            "EPIJ_CMat",
            "orientation-requested",
        ])
        XCTAssertEqual(r.paperToken, "A4")
        XCTAssertEqual(r.orientation, "landscape")
    }
}
