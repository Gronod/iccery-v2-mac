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

    // MARK: - #186 capture-return

    /// A captured `k=v` string maps to all four `PrintOptions`
    /// fields — `PageSize`, the detected quality key,
    /// `orientation-requested`, and a vendor media key (#186).
    func testCapturedStringMapsAllFields() {
        let captured =
            "PageSize=A4 EPIJ_Qual=305 orientation-requested=4 CNIJMediaType=Photo"
        XCTAssertEqual(CupsParsers.extractOption(
            named: "PageSize", fromOptionsString: captured), "A4")
        XCTAssertEqual(CupsParsers.extractQuality(
            fromOptionsString: captured), "305")
        XCTAssertEqual(CupsParsers.extractOrientation(
            fromOptionsString: captured), "landscape")
        XCTAssertEqual(CupsParsers.extractMediaType(
            fromOptionsString: captured), "Photo")
    }

    /// Vendor media keys beyond `MediaType`/`EPIJ_Medi` extract via
    /// the detection roster — `CNIJMediaType`/`StpMediaType` included
    /// (#186). `MediaType` still wins when present alongside them.
    func testExtractMediaTypeRosterFallback() {
        XCTAssertEqual(CupsParsers.extractMediaType(
            fromOptionsString: "CNIJMediaType=PhotoPlus"), "PhotoPlus")
        XCTAssertEqual(CupsParsers.extractMediaType(
            fromOptionsString: "StpMediaType=Glossy"), "Glossy")
        XCTAssertEqual(CupsParsers.extractMediaType(
            fromOptionsString: "EPIJ_Medi=Photo"), "Photo")
        // `MediaType` keeps first precedence (docs/11 §tests).
        XCTAssertEqual(CupsParsers.extractMediaType(
            fromOptionsString: "CNIJMediaType=PhotoPlus MediaType=Plain"),
            "Plain")
        XCTAssertNil(CupsParsers.extractMediaType(
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

    // MARK: - #181 Canon media locale precedence + PPD encoding

    /// The 18 Canon Pro9500 media types named in the issue — the ids
    /// are the numeric codes the driver enumerates via `lpoptions -l`.
    private let canonMedia: [(id: String, label: String)] = [
        ("0", "Plain Paper"),
        ("1", "Photo Paper Plus Glossy II"),
        ("2", "Photo Paper Pro Platinum N"),
        ("3", "Photo Paper Pro Platinum"),
        ("4", "Photo Paper Pro Luster"),
        ("5", "Photo Paper Plus Semi-gloss"),
        ("6", "Matte Photo Paper"),
        ("7", "Fine Art \"Photo Rag\""),
        ("8", "Fine Art \"Museum Etching\""),
        ("9", "Photo Paper Pro Premium Matte"),
        ("10", "Fine Art Premium Matte"),
        ("11", "Other Fine Art Paper"),
        ("12", "Canvas"),
        ("13", "Board Paper"),
        ("14", "Ink Jet Hagaki"),
        ("15", "Hagaki"),
        ("16", "Printable disc"),
        ("17", "Printable disc (bleed-proof)"),
    ]

    /// Canon Pro9500-shaped fragment: the unqualified base block comes
    /// early and the `th.` block trails at the end — the ordering that
    /// let Thai overwrite English under last-write-wins (#181).
    private var canonPPD: String {
        var lines = [
            "*OpenUI *CNIJMediaType/Media Type: PickOne",
            "*DefaultCNIJMediaType: 0",
        ]
        for media in canonMedia {
            lines.append(
                "*CNIJMediaType \(media.id)/\(media.label): \"\"")
        }
        lines.append("*CloseUI: *CNIJMediaType")
        for media in canonMedia {
            lines.append(
                "*th.CNIJMediaType \(media.id)/กระดาษ\(media.id): \"\"")
        }
        return lines.joined(separator: "\n")
    }

    func testPpdLabelsUnqualifiedSurvivesTrailingThai() {
        let labels = CupsParsers.ppdChoiceLabels(
            canonPPD, key: "CNIJMediaType")
        XCTAssertEqual(labels["0"], "Plain Paper")
        XCTAssertEqual(labels["17"], "Printable disc (bleed-proof)")
    }

    func testPpdLabelsUnqualifiedWinsRegardlessOfOrder() {
        // `th.` block first — precedence is deterministic, not
        // positional (#181, E3).
        let ppd = """
            *th.CNIJMediaType 0/กระดาษธรรมดา: ""
            *CNIJMediaType 0/Plain Paper: ""
            """
        let labels = CupsParsers.ppdChoiceLabels(ppd, key: "CNIJMediaType")
        XCTAssertEqual(labels["0"], "Plain Paper")
    }

    func testPpdLabelsQualifiedFallbackOrder() {
        // en_US > en > first-qualified-seen (#181, E3).
        let ppd = """
            *en.CNIJMediaType 1/English Label: ""
            *en_US.CNIJMediaType 1/US English Label: ""
            *th.CNIJMediaType 1/กระดาษ: ""
            *fr.CNIJMediaType 2/Français: ""
            *de.CNIJMediaType 2/Deutsch: ""
            """
        let labels = CupsParsers.ppdChoiceLabels(ppd, key: "CNIJMediaType")
        XCTAssertEqual(labels["1"], "US English Label")
        // A qualified-only id still gets its first-seen qualified
        // label — never left unlabeled (R9).
        XCTAssertEqual(labels["2"], "Français")
    }

    func testPpdLabelsHexEscapeDecoding() {
        let ppd = """
            *CNIJMediaType 3/Photo Paper Plus Glossy<2F>Matte: ""
            *CNIJMediaType 4/Plain<20>Paper: ""
            *CNIJMediaType 5/Bad<ZZ>Escape: ""
            """
        let labels = CupsParsers.ppdChoiceLabels(ppd, key: "CNIJMediaType")
        XCTAssertEqual(labels["3"], "Photo Paper Plus Glossy/Matte")
        XCTAssertEqual(labels["4"], "Plain Paper")
        XCTAssertEqual(labels["5"], "Bad<ZZ>Escape")
    }

    /// Every `CNIJMediaType` choice enumerated by `lpoptions -l` gets a
    /// non-Thai label (E1 — the true count is the hardware gate's, so
    /// no count is hardcoded here); the 18 named AC labels are
    /// spot-checked.
    func testCapabilitiesCanonMediaAllNonThai() {
        var choices = canonMedia.map(\.id)
        choices[0] = "*\(choices[0])"
        let listings = CupsParsers.lpoptionsList(
            "CNIJMediaType/Media Type: \(choices.joined(separator: " "))\n")
        let caps = CupsService().capabilities(from: listings, ppd: canonPPD)

        XCTAssertEqual(caps.mediaTypes.count, canonMedia.count)
        for type in caps.mediaTypes {
            XCTAssertFalse(type.name.unicodeScalars.contains {
                (0x0E00...0x0E7F).contains($0.value)
            }, "Thai label leaked into \(type.id): \(type.name)")
        }
        for media in canonMedia {
            XCTAssertEqual(
                caps.mediaTypes.first { $0.id == media.id }?.name,
                media.label)
        }
    }

    /// UTF-8 PPD carrying Thai labels decodes intact — the English
    /// base block wins precedence and no mojibake leaks through (#181,
    /// R10). Exercises `loadPPD` through `capabilities(for:)`.
    func testLoadPPDUtf8ThaiSurvivesDecode() async throws {
        let (service, root) = try makeCupsService(
            ppdData: Data(canonPPD.utf8),
            listing: "CNIJMediaType/Media Type: *0 1")
        defer { try? FileManager.default.removeItem(at: root) }

        let caps = try await service.capabilities(for: "Canon_Test")
        XCTAssertEqual(caps.mediaTypes.map(\.name),
            ["Plain Paper", "Photo Paper Plus Glossy II"])
    }

    /// A PPD that is not valid UTF-8 (lone `0xE9` for `é`) falls back
    /// to ISO-Latin-1 instead of yielding nil → raw ids (#181, R10).
    func testLoadPPDLatin1Fallback() async throws {
        let ppd = "*CNIJMediaType 0/Papier Couché: \"\"\n"
        let (service, root) = try makeCupsService(
            ppdData: ppd.data(using: .isoLatin1)!,
            listing: "CNIJMediaType/Media Type: *0")
        defer { try? FileManager.default.removeItem(at: root) }

        let caps = try await service.capabilities(for: "Canon_Test")
        XCTAssertEqual(caps.mediaTypes,
            [PrinterMediaType(id: "0", name: "Papier Couché")])
    }

    /// Fixture `lpoptions` + `ppdDir` so `capabilities(for:)` reaches
    /// the private `loadPPD` — same mock style as
    /// `MediaLibraryViewModelTests.installMockCups`.
    private func makeCupsService(
        ppdData: Data,
        listing: String,
        queue: String = "Canon_Test"
    ) throws -> (CupsService, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-ppd-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        let ppdDir = root.appendingPathComponent("ppd")
        for dir in [bin, ppdDir] {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
        }
        let lpoptions = """
            #!/bin/sh
            printf '%s\\n' '\(listing)'
            """
        let scriptURL = bin.appendingPathComponent("lpoptions")
        try lpoptions.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try ppdData.write(to: ppdDir.appendingPathComponent("\(queue).ppd"))
        return (CupsService(
            processManager: ProcessManager(),
            binaryDir: bin, ppdDir: ppdDir), root)
    }

    // MARK: - #202 AirPrint detection

    /// `lpstat -v` — `device for <name>: <uri>` lines; a `network`
    /// remote stub carries no URI and is skipped.
    private let lpstatV = """
        device for Canon_Pro9500_II_series_XPS: usb://Canon/PRO-9500%20II%20series?serial=1234AB
        device for Epson_XP_55_LPD: lpd://192.168.1.50/queue
        device for EPSON_XP_55_Series: ipp://EPSON%20XP-55%20Series._universal._sub._ipp._tcp.local./
        device for Office_IPPS: ipps://print.example.com/ipp/print
        network Remote_Queue
        """

    func testLpstatDeviceURIs() {
        let uris = CupsParsers.lpstatDeviceURIs(output: lpstatV)
        XCTAssertEqual(uris.count, 4)
        XCTAssertEqual(uris["Canon_Pro9500_II_series_XPS"],
            "usb://Canon/PRO-9500%20II%20series?serial=1234AB")
        XCTAssertEqual(uris["Epson_XP_55_LPD"], "lpd://192.168.1.50/queue")
        XCTAssertEqual(uris["EPSON_XP_55_Series"],
            "ipp://EPSON%20XP-55%20Series._universal._sub._ipp._tcp.local./")
        XCTAssertEqual(uris["Office_IPPS"],
            "ipps://print.example.com/ipp/print")
        XCTAssertNil(uris["Remote_Queue"])
        XCTAssertEqual(CupsParsers.lpstatDeviceURIs(output: ""), [:])
    }

    func testLpoptionsMakeAndModel() {
        XCTAssertEqual(CupsParsers.lpoptionsMakeAndModel(
            output: lpoptionsP), "EPSON EPSON XP-55 Series")
        XCTAssertNil(CupsParsers.lpoptionsMakeAndModel(
            output: "printer-type=42\n"))
    }

    /// Rule 1 — an `apple-airprint://` device URI is AirPrint on its
    /// own; PPD and make-and-model are irrelevant.
    func testAirPrintRuleAppleAirPrintScheme() {
        XCTAssertTrue(CupsParsers.detectAirPrint(
            deviceURI: "apple-airprint://DeskJet._ipps._tcp.local./",
            makeAndModel: nil, ppd: ""))
    }

    /// Rule 2 — the PPD declares `*APAirPrint: True`.
    func testAirPrintRulePPDFlag() {
        let ppd = """
            *PPD-Adobe: "4.3"
            *APAirPrint: True
            *OpenUI *PageSize/Media Size: PickOne
            """
        XCTAssertTrue(CupsParsers.detectAirPrint(
            deviceURI: "socket://10.0.0.9/", makeAndModel: nil, ppd: ppd))
    }

    /// Rule 3 — make-and-model contains "Apple" and "AirPrint".
    func testAirPrintRuleMakeAndModel() {
        XCTAssertTrue(CupsParsers.detectAirPrint(
            deviceURI: "socket://10.0.0.9/",
            makeAndModel: "Apple AirPrint", ppd: ""))
        // Both tokens are required.
        XCTAssertFalse(CupsParsers.detectAirPrint(
            deviceURI: "socket://10.0.0.9/",
            makeAndModel: "Apple LaserWriter", ppd: ""))
        XCTAssertFalse(CupsParsers.detectAirPrint(
            deviceURI: "socket://10.0.0.9/",
            makeAndModel: "HP AirPrint-Ready", ppd: ""))
    }

    /// Rule 4 — `ipps://` URI **and** the PPD text mentions "airprint"
    /// case-insensitively. `ipps://` alone is not enough.
    func testAirPrintRuleIPPSWithPPDMention() {
        XCTAssertTrue(CupsParsers.detectAirPrint(
            deviceURI: "ipps://print.example.com/ipp/print",
            makeAndModel: nil,
            ppd: "*Foo: \"AIRPRINT enabled\"\n"))
        XCTAssertFalse(CupsParsers.detectAirPrint(
            deviceURI: "ipps://print.example.com/ipp/print",
            makeAndModel: nil, ppd: "*PPD-Adobe: \"4.3\"\n"))
        // An unencrypted ipp:// URI does not satisfy rule 4.
        XCTAssertFalse(CupsParsers.detectAirPrint(
            deviceURI: "ipp://print.example.com/ipp/print",
            makeAndModel: nil,
            ppd: "*Foo: \"airprint enabled\"\n"))
    }

    /// Rule 5 — unencrypted `ipp://` resolved via the AirPrint mDNS
    /// subtype `_universal._sub._ipp._tcp`. A plain `ipp://` mDNS name
    /// without the subtype is not AirPrint.
    func testAirPrintRuleMDNSSubtype() {
        XCTAssertTrue(CupsParsers.detectAirPrint(
            deviceURI: "ipp://EPSON%20XP-55._universal._sub._ipp._tcp.local./",
            makeAndModel: nil, ppd: ""))
        XCTAssertFalse(CupsParsers.detectAirPrint(
            deviceURI: "ipp://EPSON%20XP-55._ipp._tcp.local./",
            makeAndModel: nil, ppd: ""))
    }

    /// Rule 6 — a `*cupsFilter2` rule whose destination MIME is
    /// `image/urf` (the AirPrint-only raster). A PWG-raster filter is
    /// not AirPrint.
    func testAirPrintRuleCupsFilter2URF() {
        let ppd = """
            *cupsFilter2: "application/pdf image/urf 0 -"
            *cupsFilter2: "image/urf image/urf 100 -"
            """
        XCTAssertTrue(CupsParsers.detectAirPrint(
            deviceURI: nil, makeAndModel: nil, ppd: ppd))
        XCTAssertFalse(CupsParsers.detectAirPrint(
            deviceURI: nil, makeAndModel: nil,
            ppd: "*cupsFilter2: \"application/pdf image/pwg-raster 0 -\"\n"))
    }

    /// Negative — a standard USB raster-driver queue (Epson XP-55)
    /// matches none of the six rules.
    func testAirPrintNegativeUSBRaster() {
        let ppd = """
            *PPD-Adobe: "4.3"
            *EPIJ_Qual 303/Normal: ""
            *cupsFilter: "application/vnd.cups-raster 0 rastertoepson"
            """
        XCTAssertFalse(CupsParsers.detectAirPrint(
            deviceURI: "usb://EPSON/XP-55%20Series?serial=ABC123",
            makeAndModel: "EPSON XP-55 Series", ppd: ppd))
    }

    /// `listPrinters` survives a failing `lpstat -v` — the failure is
    /// tolerated, enumeration proceeds, every queue reports
    /// `isAirPrint == false`, and there is **no** fallback respawn
    /// (exactly one `-v` invocation, #202).
    func testListPrintersToleratesLpstatVFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-airprint-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("lpstat.log")

        let lpstat = """
            #!/bin/sh
            printf '%s\\n' "$1" >> '\(log.path)'
            case "$1" in
              -e) printf 'Mock_Epson\\n' ;;
              -p) printf 'printer Mock_Epson is idle.\\n' ;;
              -d) printf 'no system default destination\\n' ;;
              -v) exit 1 ;;
            esac
            exit 0
            """
        let lpoptions = """
            #!/bin/sh
            printf "printer-info='Mock'\\n"
            """
        for (name, body) in [("lpstat", lpstat), ("lpoptions", lpoptions)] {
            let url = bin.appendingPathComponent(name)
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let service = CupsService(
            processManager: ProcessManager(), binaryDir: bin,
            ppdDir: root.appendingPathComponent("ppd"))
        let printers = try await service.listPrinters()
        XCTAssertEqual(printers.map(\.name), ["Mock_Epson"])
        XCTAssertFalse(printers[0].isAirPrint)

        let calls = ((try? String(contentsOf: log, encoding: .utf8)) ?? "")
            .split(separator: "\n")
        XCTAssertEqual(calls.filter { $0 == "-v" }.count, 1,
            "lpstat -v must be spawned exactly once: \(calls)")
    }
}
