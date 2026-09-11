import Testing
import Foundation
@testable import ICCeryCore

@Suite("ProfilingPreset")
struct ProfilingPresetTests {

    @Test("snake_case keys round-trip through Codable")
    func roundTrip() throws {
        var p = PresetCatalog.highQualityCMYK
        p.colprofInputViewingCond = "D50_2"
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(ProfilingPreset.self, from: data)
        #expect(decoded == p)
        // Spot-check the wire format.
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["colour_space"] as? String == "cmyk")
        #expect(obj["patch_count"] as? Int == 1500)
        #expect(obj["total_ink_limit"] as? Int == 320)
        #expect(obj["bit_depth"] as? Int == 16)
        #expect(obj["colprof_input_viewing_cond"] as? String == "D50_2")
    }

    @Test("Unknown keys ignored; missing required field fails")
    func schemaTolerance() throws {
        let json = """
        {"id":"x","name":"N","colour_space":"rgb","patch_count":10,
         "white_patches":1,"black_patches":1,"instrument":"i1",
         "page_size":"A4","bit_depth":8,"dpi":300,"future_key":42}
        """.data(using: .utf8)!
        let ok = try JSONDecoder().decode(ProfilingPreset.self, from: json)
        #expect(ok.id == "x")

        let missing = """
        {"id":"x","name":"N","colour_space":"rgb"}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProfilingPreset.self, from: missing)
        }
    }

    @Test("Validation rejects bad colour space / dpi / bit depth")
    func validation() {
        #expect(throws: ProfilingPreset.ValidationError.self) {
            try ProfilingPreset(id: "a", name: "n", colourSpace: "lab").validated()
        }
        #expect(throws: ProfilingPreset.ValidationError.self) {
            try ProfilingPreset(id: "a", name: "n", dpi: 10).validated()
        }
        #expect(throws: ProfilingPreset.ValidationError.self) {
            try ProfilingPreset(id: "a", name: "n", bitDepth: 12).validated()
        }
        #expect(throws: ProfilingPreset.ValidationError.self) {
            try ProfilingPreset(id: "a", name: "n", patchCount: 0).validated()
        }
    }
}

@Suite("PresetCatalog")
struct PresetCatalogTests {

    @Test("Four built-ins with the documented values")
    func builtIns() {
        #expect(PresetCatalog.builtIns.count == 4)
        let byID = Dictionary(uniqueKeysWithValues: PresetCatalog.builtIns.map { ($0.id, $0) })

        let std = byID["preset-std-rgb"]!
        #expect(std.colourSpace == "rgb" && std.patchCount == 800
                && std.pageSize == "A4" && std.bitDepth == 8
                && std.dpi == 300 && std.colprofQuality == "m"
                && std.whitePatches == 4 && std.blackPatches == 4)

        let hq = byID["preset-hq-cmyk"]!
        #expect(hq.colourSpace == "cmyk" && hq.patchCount == 1500
                && hq.pageSize == "A3" && hq.bitDepth == 16
                && hq.dpi == 300 && hq.colprofQuality == "h"
                && hq.totalInkLimit == 320 && hq.blackPatches == 8)

        let draft = byID["preset-draft-rgb"]!
        #expect(draft.colourSpace == "rgb" && draft.patchCount == 400
                && draft.pageSize == "A4" && draft.bitDepth == 8
                && draft.dpi == 150 && draft.colprofQuality == "l")

        let ultra = byID["preset-ultra-rgb"]!
        #expect(ultra.colourSpace == "rgb" && ultra.patchCount == 2500
                && ultra.pageSize == "A3" && ultra.bitDepth == 16
                && ultra.dpi == 300 && ultra.colprofQuality == "u"
                && ultra.ofpsHighQuality == true
                && ultra.whitePatches == 6 && ultra.blackPatches == 6)

        for p in PresetCatalog.builtIns {
            #expect(p.instrument == "i1")
            #expect(p.colprofFwa == "D50")
            #expect(p.randomSeed == 1)
            #expect(p.noRandomize == false)
            #expect(p.colprofAlgorithm == "l")
        }
    }

    @Test("Custom presets overlay by id; built-ins are not deletable")
    func overlay() {
        let custom = ProfilingPreset(
            id: "preset-std-rgb", name: "Shadowed", patchCount: 42)
        let all = PresetCatalog.all(custom: [custom])
        #expect(all.count == 4)
        #expect(all.first { $0.id == "preset-std-rgb" }?.patchCount == 42)
        #expect(PresetCatalog.isBuiltIn("preset-std-rgb"))
        #expect(!PresetCatalog.isBuiltIn("custom-1"))
    }
}

@Suite("PresetStore")
struct PresetStoreTests {

    private func tempSettingsURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    @Test("CRUD + export/import round-trip")
    func crud() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PresetStore(settingsStore: SettingsStore(fileURL: url))

        var p = ProfilingPreset(id: "custom-x", name: "Mine", patchCount: 999, dpi: 150)
        try store.saveCustom(p)
        #expect(store.customs().count == 1)
        #expect(store.all().count == 5)

        p.name = "Renamed"
        try store.saveCustom(p)
        #expect(store.customs().count == 1)
        #expect(store.customs()[0].name == "Renamed")

        let data = try store.export(p)
        let imported = try store.import(data)
        #expect(imported.name == "Renamed")
        #expect(imported.dpi == 150)

        #expect(try store.deleteCustom(id: "custom-x"))
        #expect(store.customs().isEmpty)
        #expect(try !store.deleteCustom(id: "preset-std-rgb"))
    }

    @Test("Import rewrites a built-in id to a fresh custom id")
    func importBuiltinCollision() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PresetStore(settingsStore: SettingsStore(fileURL: url))
        let data = try store.export(PresetCatalog.standardRGB)
        let imported = try store.import(data)
        #expect(imported.id.hasPrefix("custom-"))
        #expect(!PresetCatalog.isBuiltIn(imported.id))
    }

    @Test("Built-ins are immutable through saveCustom")
    func builtInImmutable() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PresetStore(settingsStore: SettingsStore(fileURL: url))
        var shadowed = PresetCatalog.standardRGB
        shadowed.name = "Hacked"
        #expect(throws: PresetStore.PresetStoreError.self) {
            try store.saveCustom(shadowed)
        }
    }
}

@Suite("AppSettings preset migration")
struct PresetMigrationTests {

    private func tempSettingsURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    @Test("Legacy M1 custom_presets migrate to typed schema")
    func legacyMigration() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let legacy = """
        {"custom_presets":[
            {"name":"Old One","values":{"colour_space":"cmyk","patch_count":"900",
             "dpi":"150","bit_depth":"16","instrument":"p3","page_size":"A3"}},
            {"name":"","values":{}},
            42
        ]}
        """.data(using: .utf8)!
        try legacy.write(to: url)

        let settings = SettingsStore(fileURL: url).load()
        #expect(settings.customPresets.count == 1)
        let p = settings.customPresets[0]
        #expect(p.name == "Old One")
        #expect(p.id.hasPrefix("custom-0-"))
        #expect(p.colourSpace == "cmyk")
        #expect(p.patchCount == 900)
        #expect(p.dpi == 150)
        #expect(p.bitDepth == 16)
        #expect(p.instrument == "p3")
        #expect(p.pageSize == "A3")
    }

    @Test("Typed presets load and re-save as the typed schema")
    func typedRoundTrip() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SettingsStore(fileURL: url)
        var s = AppSettings()
        s.customPresets = [ProfilingPreset(id: "c1", name: "C1", patchCount: 700)]
        try store.save(s)
        let loaded = store.load()
        #expect(loaded.customPresets.first?.patchCount == 700)
    }

    @Test("Draft preset dpi=150 survives Codable + settings round-trip")
    func draftDPI() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PresetStore(settingsStore: SettingsStore(fileURL: url))
        let data = try store.export(PresetCatalog.draftRGB)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["dpi"] as? Int == 150)
        let back = try store.import(data)
        #expect(back.dpi == 150)
    }
}

@Suite("Preset mapping")
struct PresetMappingTests {
    @Test("Draft 150 DPI maps into PrinttargConfig")
    func draftDpi() {
        let cfg = PrinttargConfig(
            preset: PresetCatalog.draftRGB,
            basename: "t",
            workingDirectory: nil,
            calibrationFile: nil
        )
        #expect(cfg.dpi == 150)
        #expect(cfg.layoutOrder == .deterministic)
    }

    @Test("Nil optional targen fields stay nil")
    func optionalNil() {
        let preset = ProfilingPreset(id: "x", name: "n", patchCount: 800)
        let cfg = TargenConfig(preset: preset, basename: "t", workingDirectory: nil)
        #expect(cfg.greySteps == nil)
        #expect(cfg.singleChannelSteps == nil)
        #expect(cfg.neutralSteps == nil)
        #expect(cfg.totalInkLimit == nil)
        #expect(cfg.darkEmphasis == nil)
        #expect(cfg.devicePower == nil)
    }

    @Test("Custom page and FWA survive a config round-trip")
    func roundTripConfigs() {
        var preset = PresetCatalog.highQualityCMYK
        preset.pageSize = "210x297"
        preset.colprofFwa = "D50"
        preset.greySteps = nil
        let targen = TargenConfig(preset: preset, basename: "job", workingDirectory: nil)
        let printtarg = PrinttargConfig(
            preset: preset, basename: "job", workingDirectory: nil, calibrationFile: nil
        )
        let colprof = ColprofConfig(preset: preset, basename: "job", workingDirectory: nil)
        #expect(printtarg.pageSize == .custom)
        #expect(printtarg.customPageWidth == 210)
        #expect(colprof.fwa == "D50")
        let back = ProfilingPreset(
            id: preset.id,
            name: preset.name,
            description: preset.description,
            targen: targen,
            printtarg: printtarg,
            colprof: colprof,
            calibrationFile: preset.calibrationFile,
            applyCalibration: preset.applyCalibration
        )
        #expect(back.dpi == preset.dpi)
        #expect(back.colourSpace == "cmyk")
        #expect(back.pageSize == "210x297")
        #expect(back.colprofFwa == "D50")
        #expect(back.greySteps == nil)
    }

    @Test("Full preset round-trips through all three configs with every field asserted")
    func fullRoundTrip() {
        let preset = ProfilingPreset(
            id: "custom-full",
            name: "Full",
            description: "All fields",
            colourSpace: "cmyk",
            patchCount: 1500,
            whitePatches: 6,
            blackPatches: 8,
            greySteps: 9,
            singleChannelSteps: 7,
            neutralSteps: 4,
            neutralConcentration: 0.7,
            preconditioningProfile: "/tmp/pre.icm",
            ofpsHighQuality: true,
            ofpsAdaptation: 0.2,
            fullSpreadAlgorithm: "R",
            totalInkLimit: 280,
            darkEmphasis: 1.3,
            devicePower: 1.2,
            instrument: "p3",
            pageSize: "250x300",
            bitDepth: 16,
            dpi: 360,
            randomSeed: 42,
            noRandomize: false,
            calibrationFile: "/tmp/a.cal",
            applyCalibration: true,
            colprofAlgorithm: "x",
            colprofQuality: "u",
            colprofIntent: "p",
            colprofFwa: "D65",
            colprofIlluminant: "D65",
            colprofObserver: "1931_2",
            colprofInputViewingCond: "D50_2",
            colprofOutputViewingCond: "D65_2"
        )

        let targen = TargenConfig(preset: preset, basename: "j", workingDirectory: nil)
        #expect(targen.colourSpace == .cmyk)
        #expect(targen.patchCount == 1500)
        #expect(targen.whitePatches == 6)
        #expect(targen.blackPatches == 8)
        #expect(targen.greySteps == 9)
        #expect(targen.singleChannelSteps == 7)
        #expect(targen.neutralSteps == 4)
        #expect(targen.neutralConcentration == 0.7)
        #expect(targen.preconditioningProfile == "/tmp/pre.icm")
        #expect(targen.ofpsHighQuality == true)
        #expect(targen.ofpsAdaptation == 0.2)
        #expect(targen.fullSpreadAlgorithm == .uniformRandom)
        #expect(targen.totalInkLimit == 280)
        #expect(targen.darkEmphasis == 1.3)
        #expect(targen.devicePower == 1.2)

        let printtarg = PrinttargConfig(
            preset: preset,
            basename: "j",
            workingDirectory: nil,
            calibrationFile: preset.calibrationFile
        )
        #expect(printtarg.instrument == .p3)
        #expect(printtarg.pageSize == .custom)
        #expect(printtarg.customPageWidth == 250)
        #expect(printtarg.customPageHeight == 300)
        #expect(printtarg.bitDepth == .sixteen)
        #expect(printtarg.dpi == 360)
        #expect(printtarg.layoutOrder == .customSeed)
        #expect(printtarg.customSeed == 42)
        #expect(printtarg.calibrationFile == "/tmp/a.cal")

        let colprof = ColprofConfig(preset: preset, basename: "j", workingDirectory: nil)
        #expect(colprof.algorithm == "x")
        #expect(colprof.quality == "u")
        #expect(colprof.intent == "p")
        #expect(colprof.fwa == "D65")
        #expect(colprof.illuminant == "D65")
        #expect(colprof.observer == "1931_2")
        #expect(colprof.inputViewingCond == "D50_2")
        #expect(colprof.outputViewingCond == "D65_2")

        let back = ProfilingPreset(
            id: preset.id,
            name: preset.name,
            description: preset.description,
            targen: targen,
            printtarg: printtarg,
            colprof: colprof,
            calibrationFile: preset.calibrationFile,
            applyCalibration: preset.applyCalibration
        )
        #expect(back == preset)
    }

    @Test("Every full-spread algorithm round-trips", arguments: [
        ("ofps", FullSpreadAlgorithm.ofps),
        ("t", .target),
        ("r", .random),
        ("R", .uniformRandom),
        ("q", .quasiRandom),
        ("Q", .uniformQuasiRandom),
        ("i", .invertedQuasiRandom),
        ("I", .invertedUniformQuasiRandom)
    ])
    func fullSpreadAlgorithms(value: String, expected: FullSpreadAlgorithm) {
        var preset = ProfilingPreset(id: "x", name: "n", patchCount: 100)
        preset.fullSpreadAlgorithm = value
        let cfg = TargenConfig(preset: preset, basename: "t", workingDirectory: nil)
        if expected == .ofps {
            // ofps is the default — no flag emitted, stored value is nil.
            #expect(cfg.fullSpreadAlgorithm == nil)
        } else {
            #expect(cfg.fullSpreadAlgorithm == expected)
        }
        let back = ProfilingPreset(
            id: "x", name: "n", description: "",
            targen: cfg,
            printtarg: PrinttargConfig(
                preset: preset, basename: "t",
                workingDirectory: nil, calibrationFile: nil
            ),
            colprof: ColprofConfig(preset: preset, basename: "t", workingDirectory: nil),
            calibrationFile: nil,
            applyCalibration: nil
        )
        #expect(back.fullSpreadAlgorithm == value)
    }

    @Test("Explicit ofpsHighQuality=false is preserved, distinct from nil")
    func ofpsHighQualityFalse() {
        var preset = ProfilingPreset(id: "x", name: "n", patchCount: 100)
        preset.ofpsHighQuality = false
        let cfg = TargenConfig(preset: preset, basename: "t", workingDirectory: nil)
        #expect(cfg.ofpsHighQuality == false)

        preset.ofpsHighQuality = nil
        let nilCfg = TargenConfig(preset: preset, basename: "t", workingDirectory: nil)
        #expect(nilCfg.ofpsHighQuality == nil)
    }

    @Test("noRandomize/seed layout mapping rules", arguments: [
        (true, nil, LayoutOrder.raster, 1),
        (true, 7, .raster, 7),
        (false, nil, .deterministic, 1),
        (false, 1, .deterministic, 1),
        (nil, 1, .deterministic, 1),
        (false, 5, .customSeed, 5)
    ] as [(Bool?, Int?, LayoutOrder, Int)])
    func layoutMapping(noRandomize: Bool?, seed: Int?, layout: LayoutOrder, expectedSeed: Int) {
        var preset = ProfilingPreset(id: "x", name: "n", patchCount: 100)
        preset.noRandomize = noRandomize
        preset.randomSeed = seed
        let cfg = PrinttargConfig(
            preset: preset, basename: "t",
            workingDirectory: nil, calibrationFile: nil
        )
        #expect(cfg.layoutOrder == layout)
        #expect(cfg.customSeed == expectedSeed)
    }

    @Test("Custom page fallback matrix", arguments: [
        ("250x300", PageSize.custom, 250.0, 300.0),
        ("50x50", .custom, 50.0, 50.0),
        ("foo", .a4, 210.0, 297.0),
        ("30x40", .a4, 210.0, 297.0),
        ("210x", .a4, 210.0, 297.0)
    ] as [(String, PageSize, Double, Double)])
    func customPageFallback(raw: String, page: PageSize, w: Double, h: Double) {
        var preset = ProfilingPreset(id: "x", name: "n", patchCount: 100)
        preset.pageSize = raw
        let cfg = PrinttargConfig(
            preset: preset, basename: "t",
            workingDirectory: nil, calibrationFile: nil
        )
        #expect(cfg.pageSize == page)
        #expect(cfg.customPageWidth == w)
        #expect(cfg.customPageHeight == h)
    }

    @Test("FWA preset value → selection matrix", arguments: [
        (nil, ColprofFwaSelection.none),
        ("none", .none),
        ("NONE", .none),
        ("", .empty),
        ("D50", .D50),
        ("d50", .D50),
        ("D65", .D65),
        ("d65", .D65),
        ("/tmp/fwa.sp", .custom)
    ] as [(String?, ColprofFwaSelection)])
    func fwaToSelection(raw: String?, expected: ColprofFwaSelection) {
        #expect(ColprofFwaSelection(presetValue: raw) == expected)
    }

    @Test("FWA selection → preset value matrix", arguments: [
        (ColprofFwaSelection.none, nil),
        (.empty, ""),
        (.D50, "D50"),
        (.D65, "D65"),
        (.custom, "/tmp/fwa.sp")
    ] as [(ColprofFwaSelection, String?)])
    func fwaToPresetValue(selection: ColprofFwaSelection, expected: String?) {
        #expect(selection.presetValue(customPath: "/tmp/fwa.sp") == expected)
    }
}
