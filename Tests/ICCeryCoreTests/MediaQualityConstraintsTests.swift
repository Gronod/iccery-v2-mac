import XCTest
import Foundation
@testable import ICCeryCore

/// #214 — media → allowed-quality resolution: generic PPD
/// `*UIConstraints`, Epson `PDEData.dat` `*EPIJUIConstraint` rules,
/// and the Canon `cnb_*.tbl` record scan. All fixtures inline /
/// injected — no installed drivers touched.
final class MediaQualityConstraintsTests: XCTestCase {

    /// Epson-flavoured `lpoptions -l` listings: the XP-55 advertises
    /// the conditional LHS keys (`EPIJ_PSrc`/`EPIJ_FdSo`/`EPIJ_Ink_`)
    /// with defaults 2/2/1.
    private var epsonListings: [CupsOptionListing] {
        CupsParsers.lpoptionsList("""
            PageSize/Media Size: 4x6 5x7 *A4 Letter
            EPIJ_Medi/Media Type: *0 92 13 15 145 12 2 75 26 76 93
            EPIJ_PSrc/Page Setup: *2 3 25
            EPIJ_FdSo/Paper Source: *2 3 12
            EPIJ_Ink_/Grayscale: *1 0
            EPIJ_Qual/Print Quality: 301 302 *303 308 304 305 307
            """)
    }

    private var epsonQualityIDs: Set<String> {
        ["301", "302", "303", "304", "305", "307", "308"]
    }

    // MARK: - ppdKeyword

    func testPPDKeywordQuotedAndBare() {
        let ppd = """
            *EPIJDriverBasePath: "/Library/Printers/EPSON/InkjetPrinter2"
            *EPIJMachineBundleName: "EP14C0605W.data"
            *CNIJTableID: 354
            *CNIJTableIDFoo: 999
            """
        XCTAssertEqual(
            MediaQualityConstraints.ppdKeyword(ppd, "EPIJDriverBasePath"),
            "/Library/Printers/EPSON/InkjetPrinter2")
        XCTAssertEqual(
            MediaQualityConstraints.ppdKeyword(ppd, "EPIJMachineBundleName"),
            "EP14C0605W.data")
        XCTAssertEqual(
            MediaQualityConstraints.ppdKeyword(ppd, "CNIJTableID"), "354")
        // Prefix-safety: CNIJTableIDFoo must not satisfy the lookup.
        XCTAssertNil(MediaQualityConstraints.ppdKeyword(ppd, "CNIJTableIDX"))
        XCTAssertNil(MediaQualityConstraints.ppdKeyword(ppd, "Missing"))
    }

    // MARK: - Path derivation

    func testEPIJPDEDataPath() {
        let ppd = """
            *EPIJDriverBasePath: "/Library/Printers/EPSON/InkjetPrinter2"
            *EPIJMachineBundleName: "EP14C0605W.data"
            """
        XCTAssertEqual(
            MediaQualityConstraints.epijPDEDataPath(ppd: ppd)?.path,
            "/Library/Printers/EPSON/InkjetPrinter2/Machine/"
                + "EP14C0605W.data/Contents/Resources/PDEData.dat")
        XCTAssertNil(MediaQualityConstraints.epijPDEDataPath(
            ppd: "*CNIJTableID: 354\n"))
    }

    func testCNIJTablePath() {
        let ppd = """
            *CNIJNameTblPath: "/Library/Printers/Canon/BJPrinter/Resources/Database/CIJPro9500IIseries.db/Contents/Resources"
            *CNIJTableID: 354
            """
        XCTAssertEqual(
            MediaQualityConstraints.cnijTablePath(ppd: ppd)?.path,
            "/Library/Printers/Canon/BJPrinter/Resources/Database/"
                + "CIJPro9500IIseries.db/Contents/Resources/cnb_3540.tbl")
        XCTAssertNil(MediaQualityConstraints.cnijTablePath(
            ppd: "*EPIJMachineBundleName: \"x\"\n"))
    }

    // MARK: - Generic PPD UIConstraints

    func testPPDUIConstraintsBothOrders() {
        let ppd = """
            *UIConstraints: *MediaType Glossy *PrintQuality Draft
            *UIConstraints: *PrintQuality Draft *MediaType Matte
            *Constraints: *MediaType Glossy *PrintQuality Low
            *UIConstraints: *InputSlot Rear *PrintQuality Draft
            """
        let forbidden = MediaQualityConstraints.ppdUIConstraints(
            ppd, mediaKey: "MediaType", qualityKey: "PrintQuality",
            mediaIDs: ["Glossy", "Matte"],
            qualityIDs: ["Draft", "Low", "High"])
        XCTAssertEqual(forbidden["Glossy"], ["Draft", "Low"])
        XCTAssertEqual(forbidden["Matte"], ["Draft"])
    }

    // MARK: - Epson EPIJUIConstraint

    /// Realistic XP-55 fragment: pure-media rules plus conditional
    /// rules on `EPIJ_PSrc`/`EPIJ_Ink_` evaluated against defaults.
    func testEPIJConstraintsAgainstDefaults() {
        let dat = """
            *EPIJUIConstraint: *EPIJ_Medi 0|*EPIJ_Qual 305
            *EPIJUIConstraint: *EPIJ_Medi 0|*EPIJ_Qual 307
            *EPIJUIConstraint: *EPIJ_Medi 0|*EPIJ_Qual 308
            *EPIJUIConstraint: *EPIJ_Medi 15|*EPIJ_Qual 301
            *EPIJUIConstraint: *EPIJ_Medi 15|*EPIJ_Qual 302
            *EPIJUIConstraint: *EPIJ_Medi 15|*EPIJ_Qual 303
            *EPIJUIConstraint: *EPIJ_Medi 15|*EPIJ_Qual 304
            *EPIJUIConstraint: *EPIJ_PSrc 3 *EPIJ_Medi 0|*EPIJ_Qual 301
            *EPIJUIConstraint: *EPIJ_PSrc 2 *EPIJ_Medi 0 *EPIJ_Ink_ 0|*EPIJ_Qual 302
            *EPIJUIConstraint: *EPIJ_Medi 92|*EPIJ_Qual 301
            *EPIJUIConstraint: *EPIJ_PSrc 3 *EPIJ_Medi 92|*EPIJ_Qual 999
            """
        let forbidden = MediaQualityConstraints.epijUIConstraints(
            dat, mediaKey: "EPIJ_Medi", qualityKey: "EPIJ_Qual",
            mediaIDs: ["0", "15", "92"], qualityIDs: epsonQualityIDs,
            defaults: ["EPIJ_PSrc": "2", "EPIJ_Ink_": "1"])
        // Media 0: pure rules forbid 305/307/308; the PSrc=3 rule is
        // inert at default PSrc=2 (301 survives); the PSrc=2 rule
        // additionally requires Ink_=0 — default is 1, so inert too
        // (302 survives).
        XCTAssertEqual(forbidden["0"], ["305", "307", "308"])
        XCTAssertEqual(forbidden["15"], ["301", "302", "303", "304"])
        // 999 is not a listed quality id — ignored outright.
        XCTAssertEqual(forbidden["92"], ["301"])
    }

    /// A conditional rule whose extra terms all match the defaults
    /// fires like a pure-media rule.
    func testEPIJConditionalRuleFiresAtDefaults() {
        let dat = """
            *EPIJUIConstraint: *EPIJ_PSrc 2 *EPIJ_Medi 0|*EPIJ_Qual 304
            """
        let forbidden = MediaQualityConstraints.epijUIConstraints(
            dat, mediaKey: "EPIJ_Medi", qualityKey: "EPIJ_Qual",
            mediaIDs: ["0"], qualityIDs: epsonQualityIDs,
            defaults: ["EPIJ_PSrc": "2"])
        XCTAssertEqual(forbidden["0"], ["304"])
    }

    /// A rule with no media term applies to every listed media; a term
    /// on a key the queue does not advertise counts as satisfied
    /// (conservative-forbid — #214 semantics).
    func testEPIJGlobalAndUnknownKeyRules() {
        let dat = """
            *EPIJUIConstraint: *EPIJ_Ink_ 1|*EPIJ_Qual 305
            *EPIJUIConstraint: *EPIJ_Mode 9 *EPIJ_Medi 0|*EPIJ_Qual 307
            """
        let forbidden = MediaQualityConstraints.epijUIConstraints(
            dat, mediaKey: "EPIJ_Medi", qualityKey: "EPIJ_Qual",
            mediaIDs: ["0", "15"], qualityIDs: epsonQualityIDs,
            defaults: ["EPIJ_Ink_": "1"])
        // Global rule: Ink_=1 matches default → 305 forbidden on both.
        XCTAssertTrue(forbidden["0"]!.contains("305"))
        XCTAssertTrue(forbidden["15"]!.contains("305"))
        // EPIJ_Mode is unlisted → satisfied → (0, 307) forbidden too.
        XCTAssertTrue(forbidden["0"]!.contains("307"))
    }

    /// The end-to-end XP-55 expectation through `resolve` — the exact
    /// sets the user reported from the driver PDE.
    func testResolveEpsonProducesDriverSets() {
        let dat = """
            *EPIJUIConstraint: *EPIJ_Medi 0|*EPIJ_Qual 305
            *EPIJUIConstraint: *EPIJ_Medi 0|*EPIJ_Qual 307
            *EPIJUIConstraint: *EPIJ_Medi 0|*EPIJ_Qual 308
            *EPIJUIConstraint: *EPIJ_Medi 92|*EPIJ_Qual 301
            *EPIJUIConstraint: *EPIJ_Medi 92|*EPIJ_Qual 302
            *EPIJUIConstraint: *EPIJ_Medi 92|*EPIJ_Qual 303
            *EPIJUIConstraint: *EPIJ_Medi 92|*EPIJ_Qual 304
            *EPIJUIConstraint: *EPIJ_Medi 92|*EPIJ_Qual 308
            *EPIJUIConstraint: *EPIJ_Medi 15|*EPIJ_Qual 301
            *EPIJUIConstraint: *EPIJ_Medi 15|*EPIJ_Qual 302
            *EPIJUIConstraint: *EPIJ_Medi 15|*EPIJ_Qual 303
            *EPIJUIConstraint: *EPIJ_Medi 15|*EPIJ_Qual 304
            """
        let ppd = """
            *EPIJDriverBasePath: "/drivers/epson"
            *EPIJMachineBundleName: "EP14C0605W.data"
            """
        let datURL = URL(fileURLWithPath:
            "/drivers/epson/Machine/EP14C0605W.data/"
                + "Contents/Resources/PDEData.dat")
        let map = MediaQualityConstraints.resolve(
            listings: epsonListings, ppd: ppd,
            readFile: { $0 == datURL ? dat.data(using: .utf8) : nil })
        // Plain paper: Fast Economy / Economy / Normal / Fine.
        XCTAssertEqual(map["0"], ["301", "302", "303", "304"])
        // Premium Semigloss: Quality / Best Quality / Draft.
        XCTAssertEqual(map["15"], ["305", "307", "308"])
        // Ultra Glossy drops Fast Economy…Fine and Draft.
        XCTAssertEqual(map["92"], ["305", "307"])
        // Unconstrained media (no rules) produce no entry.
        XCTAssertNil(map["13"])
    }

    // MARK: - Canon cnb table

    /// Builds one 20-byte Canon record: `30 00 01 00 00 00 00 00`,
    /// `family:u16`, `flag:u16`, `media:u32`, `pad:u16`, `quality:u16`.
    private func canonRecord(
        family: UInt16 = 3, flag: UInt16 = 0,
        media: UInt32, pad: UInt16 = 0, quality: UInt16
    ) -> Data {
        var d = Data([0x30, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])
        d.append(contentsOf: [UInt8(family & 0xFF), UInt8(family >> 8)])
        d.append(contentsOf: [UInt8(flag & 0xFF), UInt8(flag >> 8)])
        d.append(contentsOf: [
            UInt8(media & 0xFF), UInt8((media >> 8) & 0xFF),
            UInt8((media >> 16) & 0xFF), UInt8((media >> 24) & 0xFF)])
        d.append(contentsOf: [UInt8(pad & 0xFF), UInt8(pad >> 8)])
        d.append(contentsOf: [UInt8(quality & 0xFF), UInt8(quality >> 8)])
        return d
    }

    func testCNBTableScan() {
        var data = Data()
        // Junk prefix — even length keeps the records 2-byte aligned.
        data.append(contentsOf: [0xFF, 0x00])
        // media 0 → {0, 10, 15, 20} across flag 0/1 variants.
        for q: UInt16 in [10, 15, 20, 0] {
            data.append(canonRecord(media: 0, quality: q))
        }
        data.append(canonRecord(flag: 1, media: 0, quality: 10))
        // media 50 → {0, 5, 10}; plus its borderless variant 0x10032.
        for q: UInt16 in [0, 5, 10] {
            data.append(canonRecord(media: 50, quality: q))
        }
        data.append(canonRecord(media: 0x10032, quality: 0))
        // Noise: unknown media, unknown quality, nonzero pad, and a
        // different record family that must lose the modal vote.
        data.append(canonRecord(media: 999, quality: 5))
        data.append(canonRecord(media: 50, quality: 7))
        data.append(canonRecord(media: 50, pad: 1, quality: 15))
        data.append(canonRecord(family: 9, media: 50, quality: 15))
        data.append(Data([0x11, 0x22, 0x33]))

        let map = MediaQualityConstraints.cnijMediaQualityTable(
            data,
            mediaIDs: ["0", "50", "42"],
            qualityIDs: ["0", "5", "10", "15", "20"])
        XCTAssertEqual(map["0"], ["0", "10", "15", "20"])
        XCTAssertEqual(map["50"], ["0", "5", "10"])
        XCTAssertNil(map["42"])
    }

    func testCNBGarbageFailsOpen() {
        let map = MediaQualityConstraints.cnijMediaQualityTable(
            Data((0..<4096).map { _ in UInt8.random(in: 0...255) }),
            mediaIDs: ["0", "50"], qualityIDs: ["0", "5", "10"])
        XCTAssertTrue(map.isEmpty)
    }

    // MARK: - resolve ordering / fallback

    func testResolvePrefersPPDConstraints() {
        let ppd = """
            *UIConstraints: *EPIJ_Medi 0 *EPIJ_Qual 305
            *EPIJDriverBasePath: "/should/not/be/read"
            *EPIJMachineBundleName: "x.data"
            """
        var reads = 0
        let map = MediaQualityConstraints.resolve(
            listings: epsonListings, ppd: ppd,
            readFile: { _ in reads += 1; return nil })
        XCTAssertEqual(map["0"], epsonQualityIDs.subtracting(["305"]))
        // The Epson path is never touched once PPD constraints hit.
        XCTAssertEqual(reads, 0)
    }

    func testResolveNoPPDOrKeysFailsOpen() {
        XCTAssertTrue(MediaQualityConstraints.resolve(
            listings: epsonListings, ppd: nil).isEmpty)
        // No media key in the roster → no map.
        XCTAssertTrue(MediaQualityConstraints.resolve(
            listings: CupsParsers.lpoptionsList(
                "PageSize/Media Size: *A4 Letter\n"),
            ppd: "*CNIJTableID: 354\n").isEmpty)
    }

    // MARK: - PrinterCapabilities accessors

    func testCapabilitiesAccessorFallbacks() {
        var caps = PrinterCapabilities(
            mediaTypes: [
                PrinterMediaType(id: "0", name: "Plain"),
                PrinterMediaType(id: "15", name: "Semigloss"),
            ],
            qualities: ["301", "302", "303", "308", "304", "305", "307"]
                .map { PrinterQuality(id: $0, name: "Q\($0)") })
        // No map → everything, in driver order (#180).
        XCTAssertEqual(caps.qualities(forMediaType: "0").map(\.id),
            ["301", "302", "303", "308", "304", "305", "307"])
        XCTAssertTrue(caps.allowsQuality("305", forMediaType: "0"))

        caps.qualityIDsByMediaType = [
            "0": ["301", "302", "303", "304"],
            "15": ["305", "307", "308"],
        ]
        XCTAssertEqual(caps.qualities(forMediaType: "0").map(\.id),
            ["301", "302", "303", "304"])
        // Driver order preserved — 308 sits before 304 in lpoptions.
        XCTAssertEqual(caps.qualities(forMediaType: "15").map(\.id),
            ["308", "305", "307"])
        XCTAssertTrue(caps.allowsQuality("308", forMediaType: "15"))
        XCTAssertFalse(caps.allowsQuality("308", forMediaType: "0"))
        // Unknown media → unconstrained.
        XCTAssertEqual(caps.qualities(forMediaType: "99").count, 7)
        XCTAssertTrue(caps.allowsQuality("305", forMediaType: nil))
    }
}
