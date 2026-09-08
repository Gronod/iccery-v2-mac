import Foundation

/// Built-in presets shipped with the app (docs/22 §Built-in presets).
/// All four: instrument `i1`, FWA `D50`, random seed `1`,
/// `no_randomize == false`, colprof algorithm `l`.
///
/// Built-ins cannot be deleted; custom presets overlay by `id`.
public enum PresetCatalog {

    /// `preset-std-rgb` — Standard RGB Photo (800 patches).
    public static let standardRGB = ProfilingPreset(
        id: "preset-std-rgb",
        name: "Standard RGB Photo (800 patches)",
        description: "Everyday RGB driver printing — 800 patches on A4 at 300 dpi.",
        colourSpace: "rgb",
        patchCount: 800,
        whitePatches: 4,
        blackPatches: 4,
        instrument: "i1",
        pageSize: "A4",
        bitDepth: 8,
        dpi: 300,
        randomSeed: 1,
        noRandomize: false,
        colprofAlgorithm: "l",
        colprofQuality: "m",
        colprofFwa: "D50"
    )

    /// `preset-hq-cmyk` — High-Gamut CMYK Proofing (1500 patches).
    public static let highQualityCMYK = ProfilingPreset(
        id: "preset-hq-cmyk",
        name: "High-Gamut CMYK Proofing (1500 patches)",
        description: "RIP-driven CMYK output — 1500 patches on A3, 16-bit, 320% ink limit.",
        colourSpace: "cmyk",
        patchCount: 1500,
        whitePatches: 4,
        blackPatches: 8,
        totalInkLimit: 320,
        instrument: "i1",
        pageSize: "A3",
        bitDepth: 16,
        dpi: 300,
        randomSeed: 1,
        noRandomize: false,
        colprofAlgorithm: "l",
        colprofQuality: "h",
        colprofFwa: "D50"
    )

    /// `preset-draft-rgb` — Fast RGB Draft (400 patches, **150 dpi**).
    public static let draftRGB = ProfilingPreset(
        id: "preset-draft-rgb",
        name: "Fast RGB Draft (400 patches)",
        description: "Quick sanity check — 400 patches on A4 at 150 dpi.",
        colourSpace: "rgb",
        patchCount: 400,
        whitePatches: 4,
        blackPatches: 4,
        instrument: "i1",
        pageSize: "A4",
        bitDepth: 8,
        dpi: 150,
        randomSeed: 1,
        noRandomize: false,
        colprofAlgorithm: "l",
        colprofQuality: "l",
        colprofFwa: "D50"
    )

    /// `preset-ultra-rgb` — Ultra Precision RGB (2500 patches, `-G`).
    public static let ultraRGB = ProfilingPreset(
        id: "preset-ultra-rgb",
        name: "Ultra Precision RGB (2500 patches)",
        description: "Maximum coverage — 2500 patches on A3, 16-bit, OFPS high quality.",
        colourSpace: "rgb",
        patchCount: 2500,
        whitePatches: 6,
        blackPatches: 6,
        ofpsHighQuality: true,
        instrument: "i1",
        pageSize: "A3",
        bitDepth: 16,
        dpi: 300,
        randomSeed: 1,
        noRandomize: false,
        colprofAlgorithm: "l",
        colprofQuality: "u",
        colprofFwa: "D50"
    )

    public static let builtIns: [ProfilingPreset] = [
        standardRGB, highQualityCMYK, draftRGB, ultraRGB,
    ]

    public static let builtInIDs: Set<String> = Set(builtIns.map(\.id))

    public static func isBuiltIn(_ id: String) -> Bool {
        builtInIDs.contains(id)
    }

    /// Built-ins plus custom presets, with custom entries overlaying by
    /// `id` (a custom preset with a built-in id replaces that entry in
    /// place — the built-in is still not deletable).
    public static func all(custom: [ProfilingPreset]) -> [ProfilingPreset] {
        var result = builtIns
        var seen = builtInIDs
        for custom in custom {
            if let idx = result.firstIndex(where: { $0.id == custom.id }) {
                result[idx] = custom
            } else if !seen.contains(custom.id) {
                result.append(custom)
                seen.insert(custom.id)
            }
        }
        return result
    }
}
