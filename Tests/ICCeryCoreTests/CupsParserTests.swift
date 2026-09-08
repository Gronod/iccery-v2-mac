import Testing
import Foundation
@testable import ICCeryCore

/// Issue 12 — CUPS enumeration parsers on recorded fixtures
/// (docs/10–11). No live `lpstat`/`lpoptions` is spawned here.
@Suite("CupsParsers")
struct CupsParsersTests {

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
        cupsPrintQuality/cupsPrintQuality: Draft *Normal High
        """

    @Test("lpstat -e: one destination per line; empty = success")
    func destinations() {
        #expect(CupsParsers.lpstatDestinations(lpstatE) == [
            "Canon_Pro9500_II_series_XPS",
            "Epson_XP_55_LPD",
            "EPSON_XP_55_Series",
        ])
        #expect(CupsParsers.lpstatDestinations("") == [])
    }

    @Test("lpstat -p: idle / now-printing / disabled statuses")
    func statuses() {
        let s = CupsParsers.lpstatStatuses(lpstatP)
        #expect(s["Canon_Pro9500_II_series_XPS"] == .idle)
        #expect(s["Epson_XP_55_LPD"] == .printing)
        #expect(s["EPSON_XP_55_Series"] == .stopped)
    }

    @Test("lpstat -d: default destination or none")
    func defaultDestination() {
        #expect(CupsParsers.lpstatDefault(
            "system default destination: Canon_Pro9500_II_series_XPS\n")
            == "Canon_Pro9500_II_series_XPS")
        #expect(CupsParsers.lpstatDefault("no system default destination\n") == nil)
    }

    @Test("lpoptions -p: quoted printer-info, bare flags ignored")
    func displayName() {
        #expect(CupsParsers.lpoptionsDisplayName(lpoptionsP) == "EPSON XP-55 Series")
        #expect(CupsParsers.lpoptionsDisplayName("printer-type=42\n") == nil)
    }

    @Test("lpoptions -l: key/label split, * marks the default")
    func optionListings() {
        let listings = CupsParsers.lpoptionsList(lpoptionsL)
        #expect(listings.count == 6)

        let page = listings[0]
        #expect(page.key == "PageSize")
        #expect(page.label == "Media Size")
        #expect(page.defaultChoice == "A4")
        #expect(page.choices.contains("Custom.WIDTHxHEIGHT"))
        #expect(!page.choices.contains("*A4"))

        let slot = listings[1]
        #expect(slot.key == "InputSlot")
        #expect(slot.choices == ["Auto", "Main", "Photo", "Rear"])
        #expect(slot.defaultChoice == "Main")
    }

    @Test("capabilities: trays/sizes index 1-based, media uses detected key")
    func capabilities() {
        let service = CupsService()
        let listings = CupsParsers.lpoptionsList(lpoptionsL)
        let caps = service.capabilities(from: listings, ppd: nil)

        #expect(caps.trays == [
            PrinterTray(id: 1, name: "Auto"),
            PrinterTray(id: 2, name: "Main"),
            PrinterTray(id: 3, name: "Photo"),
            PrinterTray(id: 4, name: "Rear"),
        ])
        #expect(caps.paperSizes.first == PrinterPaperSize(id: 1, name: "3.5x5"))
        #expect(caps.paperSizes.count == 10)
        #expect(caps.mediaTypes.map(\.id) == [
            "Stationery", "PhotographicHighGloss", "Photographic",
            "PhotographicMatte", "Envelope",
        ])
        #expect(caps.supportsOrientation)
    }

    @Test("PPD enrichment maps id → human label")
    func ppdLabels() {
        let ppd = """
            *CNIJMediaType 42/Photo Paper Plus Semi-gloss: "<</MediaType(42)>>"
            *CNIJMediaType 0/Plain Paper: ""
            *en_US.CNIJMediaType 13/Envelope: ""
            """
        let labels = CupsParsers.ppdChoiceLabels(ppd, key: "CNIJMediaType")
        #expect(labels["42"] == "Photo Paper Plus Semi-gloss")
        #expect(labels["0"] == "Plain Paper")
        #expect(labels["13"] == "Envelope")
    }

    @Test("detectMediaTypeKey prefers vendor keys in order")
    func mediaTypeKey() {
        #expect(CupsParsers.detectMediaTypeKey(
            optionKeys: ["MediaType", "CNIJMediaType"]) == "CNIJMediaType")
        #expect(CupsParsers.detectMediaTypeKey(
            optionKeys: ["PageSize", "MediaType"]) == "MediaType")
        #expect(CupsParsers.detectMediaTypeKey(optionKeys: ["PageSize"]) == nil)
    }

    @Test("Driver bypass: Canon Intent2 > Intent; Epson CCor > CMat")
    func driverBypass() {
        #expect(CupsParsers.detectDriverColorBypass(
            optionKeys: ["CNIJIntent2", "CNIJIntent"])
            == ("CNIJIntent2", "4"))
        #expect(CupsParsers.detectDriverColorBypass(optionKeys: ["CNIJIntent"])
            == ("CNIJIntent", "4"))
        #expect(CupsParsers.detectDriverColorBypass(
            optionKeys: ["EPIJ_CCor", "EPIJ_CMat"]) == ("EPIJ_CCor", "0"))
        #expect(CupsParsers.detectDriverColorBypass(optionKeys: ["EPIJ_CMat"])
            == ("EPIJ_CMat", "3"))
        #expect(CupsParsers.detectDriverColorBypass(
            optionKeys: ["StpColorCorrection"]) == ("StpColorCorrection", "Uncorrected"))
        #expect(CupsParsers.detectDriverColorBypass(
            optionKeys: ["ColorCorrection"]) == ("ColorCorrection", "Uncorrected"))
        #expect(CupsParsers.detectDriverColorBypass(
            optionKeys: ["EpsonColorMode"]) == ("EpsonColorMode", "Off"))
        #expect(CupsParsers.detectDriverColorBypass(optionKeys: ["PageSize"]) == nil)
    }
}
