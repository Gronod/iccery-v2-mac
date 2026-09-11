import Foundation
import XCTest
@testable import ICCeryCore

final class ProfilingPresetTests: XCTestCase {

    func testRoundTrip() throws {
        var p = PresetCatalog.highQualityCMYK
        p.colprofInputViewingCond = "D50_2"
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(ProfilingPreset.self, from: data)
        XCTAssertEqual(decoded, p)
        // Spot-check the wire format.
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["colour_space"] as? String, "cmyk")
        XCTAssertEqual(obj["patch_count"] as? Int, 1500)
        XCTAssertEqual(obj["total_ink_limit"] as? Int, 320)
        XCTAssertEqual(obj["bit_depth"] as? Int, 16)
        XCTAssertEqual(obj["colprof_input_viewing_cond"] as? String, "D50_2")
    }

    func testSchemaTolerance() throws {
        let json = """
        {"id":"x","name":"N","colour_space":"rgb","patch_count":10,
         "white_patches":1,"black_patches":1,"instrument":"i1",
         "page_size":"A4","bit_depth":8,"dpi":300,"future_key":42}
        """.data(using: .utf8)!
        let ok = try JSONDecoder().decode(ProfilingPreset.self, from: json)
        XCTAssertEqual(ok.id, "x")

        let missing = """
        {"id":"x","name":"N","colour_space":"rgb"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ProfilingPreset.self, from: missing)) { error in XCTAssertTrue(error is DecodingError) }
    }

    func testValidation() {
        XCTAssertThrowsError(try ProfilingPreset(id: "a", name: "n", colourSpace: "lab").validated()) { error in XCTAssertTrue(error is ProfilingPreset.ValidationError) }
        XCTAssertThrowsError(try ProfilingPreset(id: "a", name: "n", dpi: 10).validated()) { error in XCTAssertTrue(error is ProfilingPreset.ValidationError) }
        XCTAssertThrowsError(try ProfilingPreset(id: "a", name: "n", bitDepth: 12).validated()) { error in XCTAssertTrue(error is ProfilingPreset.ValidationError) }
        XCTAssertThrowsError(try ProfilingPreset(id: "a", name: "n", patchCount: 0).validated()) { error in XCTAssertTrue(error is ProfilingPreset.ValidationError) }
    }
}

final class PresetCatalogTests: XCTestCase {

    func testBuiltIns() {
        XCTAssertEqual(PresetCatalog.builtIns.count, 4)
        let byID = Dictionary(uniqueKeysWithValues: PresetCatalog.builtIns.map { ($0.id, $0) })

        let std = byID["preset-std-rgb"]!
        XCTAssertTrue(std.colourSpace == "rgb" && std.patchCount == 800
                && std.pageSize == "A4" && std.bitDepth == 8
                && std.dpi == 300 && std.colprofQuality == "m"
                && std.whitePatches == 4 && std.blackPatches == 4)

        let hq = byID["preset-hq-cmyk"]!
        XCTAssertTrue(hq.colourSpace == "cmyk" && hq.patchCount == 1500
                && hq.pageSize == "A3" && hq.bitDepth == 16
                && hq.dpi == 300 && hq.colprofQuality == "h"
                && hq.totalInkLimit == 320 && hq.blackPatches == 8)

        let draft = byID["preset-draft-rgb"]!
        XCTAssertTrue(draft.colourSpace == "rgb" && draft.patchCount == 400
                && draft.pageSize == "A4" && draft.bitDepth == 8
                && draft.dpi == 150 && draft.colprofQuality == "l")

        let ultra = byID["preset-ultra-rgb"]!
        XCTAssertTrue(ultra.colourSpace == "rgb" && ultra.patchCount == 2500
                && ultra.pageSize == "A3" && ultra.bitDepth == 16
                && ultra.dpi == 300 && ultra.colprofQuality == "u"
                && ultra.ofpsHighQuality == true
                && ultra.whitePatches == 6 && ultra.blackPatches == 6)

        for p in PresetCatalog.builtIns {
            XCTAssertEqual(p.instrument, "i1")
            XCTAssertEqual(p.colprofFwa, "D50")
            XCTAssertEqual(p.randomSeed, 1)
            XCTAssertEqual(p.noRandomize, false)
            XCTAssertEqual(p.colprofAlgorithm, "l")
        }
    }

    func testOverlay() {
        let custom = ProfilingPreset(
            id: "preset-std-rgb", name: "Shadowed", patchCount: 42)
        let all = PresetCatalog.all(custom: [custom])
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(all.first { $0.id == "preset-std-rgb" }?.patchCount, 42)
        XCTAssertTrue(PresetCatalog.isBuiltIn("preset-std-rgb"))
        XCTAssertFalse(PresetCatalog.isBuiltIn("custom-1"))
    }
}

final class PresetStoreTests: XCTestCase {

    private func tempSettingsURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    func testCrud() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PresetStore(settingsStore: SettingsStore(fileURL: url))

        var p = ProfilingPreset(id: "custom-x", name: "Mine", patchCount: 999, dpi: 150)
        try store.saveCustom(p)
        XCTAssertEqual(store.customs().count, 1)
        XCTAssertEqual(store.all().count, 5)

        p.name = "Renamed"
        try store.saveCustom(p)
        XCTAssertEqual(store.customs().count, 1)
        XCTAssertEqual(store.customs()[0].name, "Renamed")

        let data = try store.export(p)
        let imported = try store.import(data)
        XCTAssertEqual(imported.name, "Renamed")
        XCTAssertEqual(imported.dpi, 150)

        XCTAssertTrue(try store.deleteCustom(id: "custom-x"))
        XCTAssertTrue(store.customs().isEmpty)
        XCTAssertFalse(try store.deleteCustom(id: "preset-std-rgb"))
    }

    func testImportBuiltinCollision() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PresetStore(settingsStore: SettingsStore(fileURL: url))
        let data = try store.export(PresetCatalog.standardRGB)
        let imported = try store.import(data)
        XCTAssertTrue(imported.id.hasPrefix("custom-"))
        XCTAssertFalse(PresetCatalog.isBuiltIn(imported.id))
    }

    func testBuiltInImmutable() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PresetStore(settingsStore: SettingsStore(fileURL: url))
        var shadowed = PresetCatalog.standardRGB
        shadowed.name = "Hacked"
        XCTAssertThrowsError(try store.saveCustom(shadowed)) { error in XCTAssertTrue(error is PresetStore.PresetStoreError) }
    }
}

final class PresetMigrationTests: XCTestCase {

    private func tempSettingsURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    func testLegacyMigration() throws {
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
        XCTAssertEqual(settings.customPresets.count, 1)
        let p = settings.customPresets[0]
        XCTAssertEqual(p.name, "Old One")
        XCTAssertTrue(p.id.hasPrefix("custom-0-"))
        XCTAssertEqual(p.colourSpace, "cmyk")
        XCTAssertEqual(p.patchCount, 900)
        XCTAssertEqual(p.dpi, 150)
        XCTAssertEqual(p.bitDepth, 16)
        XCTAssertEqual(p.instrument, "p3")
        XCTAssertEqual(p.pageSize, "A3")
    }

    func testTypedRoundTrip() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SettingsStore(fileURL: url)
        var s = AppSettings()
        s.customPresets = [ProfilingPreset(id: "c1", name: "C1", patchCount: 700)]
        try store.save(s)
        let loaded = store.load()
        XCTAssertEqual(loaded.customPresets.first?.patchCount, 700)
    }

    func testDraftDPI() throws {
        let url = try tempSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PresetStore(settingsStore: SettingsStore(fileURL: url))
        let data = try store.export(PresetCatalog.draftRGB)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["dpi"] as? Int, 150)
        let back = try store.import(data)
        XCTAssertEqual(back.dpi, 150)
    }
}

final class PresetMappingTests: XCTestCase {
    func testDraftDpi() {
        let cfg = PrinttargConfig(
            preset: PresetCatalog.draftRGB,
            basename: "t",
            workingDirectory: nil,
            calibrationFile: nil
        )
        XCTAssertEqual(cfg.dpi, 150)
        XCTAssertEqual(cfg.layoutOrder, .deterministic)
    }

    func testOptionalNil() {
        let preset = ProfilingPreset(id: "x", name: "n", patchCount: 800)
        let cfg = TargenConfig(preset: preset, basename: "t", workingDirectory: nil)
        XCTAssertNil(cfg.greySteps)
        XCTAssertNil(cfg.singleChannelSteps)
        XCTAssertNil(cfg.neutralSteps)
        XCTAssertNil(cfg.totalInkLimit)
        XCTAssertNil(cfg.darkEmphasis)
        XCTAssertNil(cfg.devicePower)
    }

    func testRoundTripConfigs() {
        var preset = PresetCatalog.highQualityCMYK
        preset.pageSize = "210x297"
        preset.colprofFwa = "D50"
        preset.greySteps = nil
        let targen = TargenConfig(preset: preset, basename: "job", workingDirectory: nil)
        let printtarg = PrinttargConfig(
            preset: preset, basename: "job", workingDirectory: nil, calibrationFile: nil
        )
        let colprof = ColprofConfig(preset: preset, basename: "job", workingDirectory: nil)
        XCTAssertEqual(printtarg.pageSize, .custom)
        XCTAssertEqual(printtarg.customPageWidth, 210)
        XCTAssertEqual(colprof.fwa, "D50")
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
        XCTAssertEqual(back.dpi, preset.dpi)
        XCTAssertEqual(back.colourSpace, "cmyk")
        XCTAssertEqual(back.pageSize, "210x297")
        XCTAssertEqual(back.colprofFwa, "D50")
        XCTAssertNil(back.greySteps)
    }

    func testFullRoundTrip() {
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
        XCTAssertEqual(targen.colourSpace, .cmyk)
        XCTAssertEqual(targen.patchCount, 1500)
        XCTAssertEqual(targen.whitePatches, 6)
        XCTAssertEqual(targen.blackPatches, 8)
        XCTAssertEqual(targen.greySteps, 9)
        XCTAssertEqual(targen.singleChannelSteps, 7)
        XCTAssertEqual(targen.neutralSteps, 4)
        XCTAssertEqual(targen.neutralConcentration, 0.7)
        XCTAssertEqual(targen.preconditioningProfile, "/tmp/pre.icm")
        XCTAssertEqual(targen.ofpsHighQuality, true)
        XCTAssertEqual(targen.ofpsAdaptation, 0.2)
        XCTAssertEqual(targen.fullSpreadAlgorithm, .uniformRandom)
        XCTAssertEqual(targen.totalInkLimit, 280)
        XCTAssertEqual(targen.darkEmphasis, 1.3)
        XCTAssertEqual(targen.devicePower, 1.2)

        let printtarg = PrinttargConfig(
            preset: preset,
            basename: "j",
            workingDirectory: nil,
            calibrationFile: preset.calibrationFile
        )
        XCTAssertEqual(printtarg.instrument, .p3)
        XCTAssertEqual(printtarg.pageSize, .custom)
        XCTAssertEqual(printtarg.customPageWidth, 250)
        XCTAssertEqual(printtarg.customPageHeight, 300)
        XCTAssertEqual(printtarg.bitDepth, .sixteen)
        XCTAssertEqual(printtarg.dpi, 360)
        XCTAssertEqual(printtarg.layoutOrder, .customSeed)
        XCTAssertEqual(printtarg.customSeed, 42)
        XCTAssertEqual(printtarg.calibrationFile, "/tmp/a.cal")

        let colprof = ColprofConfig(preset: preset, basename: "j", workingDirectory: nil)
        XCTAssertEqual(colprof.algorithm, "x")
        XCTAssertEqual(colprof.quality, "u")
        XCTAssertEqual(colprof.intent, "p")
        XCTAssertEqual(colprof.fwa, "D65")
        XCTAssertEqual(colprof.illuminant, "D65")
        XCTAssertEqual(colprof.observer, "1931_2")
        XCTAssertEqual(colprof.inputViewingCond, "D50_2")
        XCTAssertEqual(colprof.outputViewingCond, "D65_2")

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
        XCTAssertEqual(back, preset)
    }

    func testFullSpreadAlgorithms() {
        let cases: [(String, FullSpreadAlgorithm)] = [
            ("ofps", .ofps),
            ("t", .target),
            ("r", .random),
            ("R", .uniformRandom),
            ("q", .quasiRandom),
            ("Q", .uniformQuasiRandom),
            ("i", .invertedQuasiRandom),
            ("I", .invertedUniformQuasiRandom)
        ]
        for (value, expected) in cases {
            var preset = ProfilingPreset(id: "x", name: "n", patchCount: 100)
            preset.fullSpreadAlgorithm = value
            let cfg = TargenConfig(preset: preset, basename: "t", workingDirectory: nil)
            if expected == .ofps {
                // ofps is the default — no flag emitted, stored value is nil.
                XCTAssertNil(cfg.fullSpreadAlgorithm)
            } else {
                XCTAssertEqual(cfg.fullSpreadAlgorithm, expected)
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
            XCTAssertEqual(back.fullSpreadAlgorithm, value)
        }
    }

    func testOfpsHighQualityFalse() {
        var preset = ProfilingPreset(id: "x", name: "n", patchCount: 100)
        preset.ofpsHighQuality = false
        let cfg = TargenConfig(preset: preset, basename: "t", workingDirectory: nil)
        XCTAssertEqual(cfg.ofpsHighQuality, false)

        preset.ofpsHighQuality = nil
        let nilCfg = TargenConfig(preset: preset, basename: "t", workingDirectory: nil)
        XCTAssertNil(nilCfg.ofpsHighQuality)
    }

    func testLayoutMapping() {
        let cases: [(Bool?, Int?, LayoutOrder, Int)] = [
            (true, nil, .raster, 1),
            (true, 7, .raster, 7),
            (false, nil, .deterministic, 1),
            (false, 1, .deterministic, 1),
            (nil, 1, .deterministic, 1),
            (false, 5, .customSeed, 5)
        ]
        for (noRandomize, seed, layout, expectedSeed) in cases {
            var preset = ProfilingPreset(id: "x", name: "n", patchCount: 100)
            preset.noRandomize = noRandomize
            preset.randomSeed = seed
            let cfg = PrinttargConfig(
                preset: preset, basename: "t",
                workingDirectory: nil, calibrationFile: nil
            )
            XCTAssertEqual(cfg.layoutOrder, layout)
            XCTAssertEqual(cfg.customSeed, expectedSeed)
        }
    }

    func testCustomPageFallback() {
        let cases: [(String, PageSize, Double, Double)] = [
            ("250x300", .custom, 250.0, 300.0),
            ("50x50", .custom, 50.0, 50.0),
            ("foo", .a4, 210.0, 297.0),
            ("30x40", .a4, 210.0, 297.0),
            ("210x", .a4, 210.0, 297.0)
        ]
        for (raw, page, w, h) in cases {
            var preset = ProfilingPreset(id: "x", name: "n", patchCount: 100)
            preset.pageSize = raw
            let cfg = PrinttargConfig(
                preset: preset, basename: "t",
                workingDirectory: nil, calibrationFile: nil
            )
            XCTAssertEqual(cfg.pageSize, page)
            XCTAssertEqual(cfg.customPageWidth, w)
            XCTAssertEqual(cfg.customPageHeight, h)
        }
    }

    func testFwaToSelection() {
        let cases: [(String?, ColprofFwaSelection)] = [
            (nil, .none),
            ("none", .none),
            ("NONE", .none),
            ("", .empty),
            ("D50", .D50),
            ("d50", .D50),
            ("D65", .D65),
            ("d65", .D65),
            ("/tmp/fwa.sp", .custom)
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(ColprofFwaSelection(presetValue: raw), expected)
        }
    }

    func testFwaToPresetValue() {
        let cases: [(ColprofFwaSelection, String?)] = [
            (.none, nil),
            (.empty, ""),
            (.D50, "D50"),
            (.D65, "D65"),
            (.custom, "/tmp/fwa.sp")
        ]
        for (selection, expected) in cases {
            XCTAssertEqual(selection.presetValue(customPath: "/tmp/fwa.sp"), expected)
        }
    }
}
