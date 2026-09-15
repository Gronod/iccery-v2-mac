import XCTest
import Foundation
@testable import ICCeryCore

/// Issue 12 — CUPS enumeration parsers on recorded fixtures
/// (docs/10–11). No live `lpstat`/`lpoptions` is spawned here.
final class CupsParserTests: XCTestCase {

    // Recorded on an Epson XP-55 + Canon Pro9500 host.
    private let lpstatE = """
        Canon_Pro9500_II_series_XPS
        Epson_XP_55_LPD
        EPSON_XP_55_Series
        """

    private let lpstatP = """
        printer Canon_Pro9500_II_series_XPS is idle.  enabled since Mon Sep  7 22:51:30 2026
        printer Epson_XP_55_LPD now printing Epson_XP_55_LPD-42.  enabled since Mon Sep  7 21:50:25 2026
        printer EPSON_XP_55_Series disabled since Tue Sep  8 09:00:00 2026 -
        	Paused
        """

    private let lpoptionsP = """
        device-uri=ipp://EPSON%20XP-55%20Series._ipp._tcp.local./ printer-info='EPSON XP-55 Series' printer-location printer-make-and-model='EPSON EPSON XP-55 Series' printer-type=16781340
        """

    private let lpoptionsL = """
        PageSize/Media Size: 3.5x5 4x6 5x7 8x10 *A4 A5 B5 Letter Legal Custom.WIDTHxHEIGHT
        InputSlot/Media Source: Auto *Main Photo Rear
        MediaType/Media Type: *Stationery PhotographicHighGloss Photographic PhotographicMatte Envelope
        ColorModel/Output Mode: *RGB Gray
        Duplex/Duplex: *None DuplexNoTumble DuplexTumble
        EPIJ_Qual/Print Quality: 301 302 *303 308 304 305 307
        """

    func testDestinations() {
        XCTAssertEqual(CupsParsers.lpstatDestinations(lpstatE), [
            "Canon_Pro9500_II_series_XPS",
            "Epson_XP_55_LPD",
            "EPSON_XP_55_Series",
        ])
        XCTAssertEqual(CupsParsers.lpstatDestinations(""), [])
    }

    func testStatuses() {
        let s = CupsParsers.lpstatStatuses(lpstatP)
        XCTAssertEqual(s["Canon_Pro9500_II_series_XPS"], .idle)
        XCTAssertEqual(s["Epson_XP_55_LPD"], .printing)
        XCTAssertEqual(s["EPSON_XP_55_Series"], .stopped)
    }

    func testDefaultDestination() {
        XCTAssertEqual(CupsParsers.lpstatDefault(
            "system default destination: Canon_Pro9500_II_series_XPS\n"), "Canon_Pro9500_II_series_XPS")
        XCTAssertNil(CupsParsers.lpstatDefault("no system default destination\n"))
    }

    func testDisplayName() {
        XCTAssertEqual(CupsParsers.lpoptionsDisplayName(lpoptionsP), "EPSON XP-55 Series")
        XCTAssertNil(CupsParsers.lpoptionsDisplayName("printer-type=42\n"))
    }

    func testOptionListings() {
        let listings = CupsParsers.lpoptionsList(lpoptionsL)
        XCTAssertEqual(listings.count, 6)

        let page = listings[0]
        XCTAssertEqual(page.key, "PageSize")
        XCTAssertEqual(page.label, "Media Size")
        XCTAssertEqual(page.defaultChoice, "A4")
        XCTAssertTrue(page.choices.contains("Custom.WIDTHxHEIGHT"))
        XCTAssertFalse(page.choices.contains("*A4"))

        let slot = listings[1]
        XCTAssertEqual(slot.key, "InputSlot")
        XCTAssertEqual(slot.choices, ["Auto", "Main", "Photo", "Rear"])
        XCTAssertEqual(slot.defaultChoice, "Main")
    }

    func testCapabilities() {
        let service = CupsService()
        let listings = CupsParsers.lpoptionsList(lpoptionsL)
        let caps = service.capabilities(from: listings, ppd: nil)

        XCTAssertEqual(caps.trays, [
            PrinterTray(id: 1, name: "Auto"),
            PrinterTray(id: 2, name: "Main"),
            PrinterTray(id: 3, name: "Photo"),
            PrinterTray(id: 4, name: "Rear"),
        ])
        XCTAssertEqual(caps.paperSizes.first, PrinterPaperSize(id: 1, name: "3.5x5"))
        XCTAssertEqual(caps.paperSizes.count, 10)
        XCTAssertEqual(caps.mediaTypes.map(\.id), [
            "Stationery", "PhotographicHighGloss", "Photographic",
            "PhotographicMatte", "Envelope",
        ])
        XCTAssertTrue(caps.supportsOrientation)
    }

    func testPpdLabels() {
        let ppd = """
            *CNIJMediaType 42/Photo Paper Plus Semi-gloss: "<</MediaType(42)>>"
            *CNIJMediaType 0/Plain Paper: ""
            *en_US.CNIJMediaType 13/Envelope: ""
            """
        let labels = CupsParsers.ppdChoiceLabels(ppd, key: "CNIJMediaType")
        XCTAssertEqual(labels["42"], "Photo Paper Plus Semi-gloss")
        XCTAssertEqual(labels["0"], "Plain Paper")
        XCTAssertEqual(labels["13"], "Envelope")
    }

    func testMediaTypeKey() {
        XCTAssertEqual(CupsParsers.detectMediaTypeKey(
            optionKeys: ["MediaType", "CNIJMediaType"]), "CNIJMediaType")
        XCTAssertEqual(CupsParsers.detectMediaTypeKey(
            optionKeys: ["PageSize", "MediaType"]), "MediaType")
        XCTAssertNil(CupsParsers.detectMediaTypeKey(optionKeys: ["PageSize"]))
    }

    // MARK: - #183 quality key + option extraction

    func testQualityKeyRosterOrder() {
        // Vendor keys beat the generic ones; OutputMode/Resolution sit
        // last (they are colour-ish keys on some drivers — #183/#180).
        XCTAssertEqual(CupsParsers.detectQualityKey(
            optionKeys: ["EPIJ_Qual", "Quality", "OutputMode"]), "EPIJ_Qual")
        // A full Epson key set — EPIJ_Qual wins over the colour-mode
        // key, the generic keys, and Resolution (#180, R11).
        XCTAssertEqual(CupsParsers.detectQualityKey(
            optionKeys: ["EPIJ_Qual", "OutputMode", "Resolution",
                         "cupsPrintQuality", "PrintQuality",
                         "ColorModel"]), "EPIJ_Qual")
        XCTAssertEqual(CupsParsers.detectQualityKey(
            optionKeys: ["Quality", "OutputMode", "Resolution"]), "Quality")
        XCTAssertEqual(CupsParsers.detectQualityKey(
            optionKeys: ["cupsPrintQuality", "CNIJQuality"]),
            "CNIJQuality")
        XCTAssertEqual(CupsParsers.detectQualityKey(
            optionKeys: ["OutputMode", "Resolution"]), "OutputMode")
        XCTAssertEqual(CupsParsers.detectQualityKey(
            optionKeys: ["Resolution"]), "Resolution")
        XCTAssertNil(CupsParsers.detectQualityKey(optionKeys: ["PageSize"]))
    }

    func testCapabilitiesQuality() {
        let service = CupsService()
        let listings = CupsParsers.lpoptionsList(lpoptionsL)
        let caps = service.capabilities(from: listings, ppd: nil)

        // EPIJ_Qual is the roster member — all seven Epson codes
        // enumerate in the driver's own (non-sorted) order (#180).
        XCTAssertEqual(caps.qualityKey, "EPIJ_Qual")
        XCTAssertEqual(caps.qualities.map(\.id),
            ["301", "302", "303", "308", "304", "305", "307"])
        XCTAssertEqual(caps.qualityDefault, "303")
    }

    func testCapabilitiesQualityPpdLabels() {
        // Epson XP-55 PPD fragment — the seven `*EPIJ_Qual id/Label`
        // lines in the driver's own order (#180).
        let ppd = """
            *OpenUI *EPIJ_Qual/Print Quality: PickOne
            *DefaultEPIJ_Qual: 303
            *EPIJ_Qual 301/Fast Economy: ""
            *EPIJ_Qual 302/Economy: ""
            *EPIJ_Qual 303/Normal: ""
            *EPIJ_Qual 308/Draft: ""
            *EPIJ_Qual 304/Fine: ""
            *EPIJ_Qual 305/Quality: ""
            *EPIJ_Qual 307/Best Quality: ""
            *CloseUI: *EPIJ_Qual
            """
        let service = CupsService()
        let listings = CupsParsers.lpoptionsList(
            "EPIJ_Qual/Print Quality: 301 302 *303 308 304 305 307\n")
        let caps = service.capabilities(from: listings, ppd: ppd)

        XCTAssertEqual(caps.qualityKey, "EPIJ_Qual")
        XCTAssertEqual(caps.qualities, [
            PrinterQuality(id: "301", name: "Fast Economy"),
            PrinterQuality(id: "302", name: "Economy"),
            PrinterQuality(id: "303", name: "Normal"),
            PrinterQuality(id: "308", name: "Draft"),
            PrinterQuality(id: "304", name: "Fine"),
            PrinterQuality(id: "305", name: "Quality"),
            PrinterQuality(id: "307", name: "Best Quality"),
        ])
        XCTAssertEqual(caps.qualityDefault, "303")
    }

    /// #180 — the Epson listing also carries `OutputMode` (a colour
    /// mode) and `Resolution`; detection must still pick `EPIJ_Qual`.
    func testCapabilitiesQualityEpsonDetection() {
        let service = CupsService()
        let listings = CupsParsers.lpoptionsList("""
            PageSize/Media Size: *A4 Letter
            EPIJ_Qual/Print Quality: 301 302 *303 308 304 305 307
            OutputMode/Color Mode: *Color Mono
            Resolution/Resolution: *360dpi 720dpi
            """)
        let caps = service.capabilities(from: listings, ppd: nil)

        XCTAssertEqual(caps.qualityKey, "EPIJ_Qual")
        XCTAssertEqual(caps.qualities.count, 7)
        XCTAssertEqual(caps.qualityDefault, "303")
        XCTAssertFalse(caps.qualities.contains { $0.id == "Color" })
    }

    func testExtractOption() {
        let options = "PageSize=A4 EPIJ_Qual=303 printer-info='EPSON XP-55'"
        XCTAssertEqual(CupsParsers.extractOption(
            named: "PageSize", fromOptionsString: options), "A4")
        // Case-insensitive key match.
        XCTAssertEqual(CupsParsers.extractOption(
            named: "epij_qual", fromOptionsString: options), "303")
        // Quoted values come back unquoted.
        XCTAssertEqual(CupsParsers.extractOption(
            named: "printer-info", fromOptionsString: options), "EPSON XP-55")
        XCTAssertNil(CupsParsers.extractOption(
            named: "InputSlot", fromOptionsString: options))
    }

    func testExtractQualityAndOrientation() {
        let options = "orientation-requested=4 OutputMode=Gray EPIJ_Qual=305"
        XCTAssertEqual(CupsParsers.extractQuality(
            fromOptionsString: options), "305")
        XCTAssertEqual(CupsParsers.extractOrientation(
            fromOptionsString: options), "landscape")
        XCTAssertNil(CupsParsers.extractQuality(
            fromOptionsString: "PageSize=A4"))
        XCTAssertNil(CupsParsers.extractOrientation(
            fromOptionsString: "PageSize=A4"))
    }

    func testDriverBypass() {
        func pair(_ keys: Set<String>) -> String? {
            CupsParsers.detectDriverColorBypass(optionKeys: keys)
                .map { "\($0.key)=\($0.value)" }
        }
        XCTAssertEqual(pair(["CNIJIntent2", "CNIJIntent"]), "CNIJIntent2=4")
        XCTAssertEqual(pair(["CNIJIntent"]), "CNIJIntent=4")
        XCTAssertEqual(pair(["EPIJ_CCor", "EPIJ_CMat"]), "EPIJ_CCor=0")
        XCTAssertEqual(pair(["EPIJ_CMat"]), "EPIJ_CMat=3")
        XCTAssertEqual(pair(["StpColorCorrection"]), "StpColorCorrection=Uncorrected")
        XCTAssertEqual(pair(["ColorCorrection"]), "ColorCorrection=Uncorrected")
        XCTAssertEqual(pair(["EpsonColorMode"]), "EpsonColorMode=Off")
        XCTAssertNil(pair(["PageSize"]))
    }
}
