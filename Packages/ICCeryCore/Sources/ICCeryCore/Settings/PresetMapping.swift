import Foundation

extension TargenConfig {
    /// Stage 1 fields of a profiling preset. Optional advanced flags stay
    /// `nil` when the preset omitted them so argv builders skip the flag.
    public init(preset: ProfilingPreset, basename: String, workingDirectory: URL?) {
        self.init(
            colourSpace: preset.colourSpace.lowercased() == "cmyk" ? .cmyk : .rgb,
            patchCount: preset.patchCount,
            whitePatches: preset.whitePatches,
            blackPatches: preset.blackPatches,
            greySteps: preset.greySteps,
            singleChannelSteps: preset.singleChannelSteps,
            neutralSteps: preset.neutralSteps,
            neutralConcentration: preset.neutralConcentration,
            preconditioningProfile: preset.preconditioningProfile,
            // An explicit `false` is preserved — distinguishable from a
            // missing key; `-G` is only emitted for `true` (#82).
            ofpsHighQuality: preset.ofpsHighQuality,
            ofpsAdaptation: preset.ofpsAdaptation,
            fullSpreadAlgorithm: preset.fullSpreadAlgorithm.flatMap { FullSpreadAlgorithm(presetValue: $0) }.flatMap { $0 == .ofps ? nil : $0 },
            totalInkLimit: preset.totalInkLimit,
            darkEmphasis: preset.darkEmphasis,
            devicePower: preset.devicePower,
            basename: basename,
            workingDirectory: workingDirectory
        )
    }
}

extension PrinttargConfig {
    public init(
        preset: ProfilingPreset,
        basename: String,
        workingDirectory: URL?,
        calibrationFile: String?,
        label: String? = nil
    ) {
        let page: PageSize
        let customW: Double
        let customH: Double
        if let size = PageSize(rawValue: preset.pageSize) {
            page = size
            customW = 210
            customH = 297
        } else if let (w, h) = PageSize.parseCustom(preset.pageSize) {
            page = .custom
            customW = w
            customH = h
        } else {
            page = .a4
            customW = 210
            customH = 297
        }

        let layout: LayoutOrder
        let seed = preset.randomSeed ?? 1
        if preset.noRandomize == true {
            layout = .raster
        } else if seed == 1 {
            layout = .deterministic
        } else {
            layout = .customSeed
        }

        self.init(
            instrument: PrintInstrument(rawValue: preset.instrument) ?? .i1,
            pageSize: page,
            customPageWidth: customW,
            customPageHeight: customH,
            bitDepth: preset.bitDepth == 16 ? .sixteen : .eight,
            dpi: preset.dpi,
            layoutOrder: layout,
            customSeed: seed,
            label: label,
            calibrationFile: calibrationFile,
            calibrationEmbedOnly: false,
            basename: basename,
            workingDirectory: workingDirectory
        )
    }
}

extension ColprofConfig {
    public init(
        preset: ProfilingPreset,
        basename: String,
        workingDirectory: URL?,
        description: String? = nil,
        copyright: String? = nil
    ) {
        self.init(
            algorithm: preset.colprofAlgorithm ?? "l",
            quality: preset.colprofQuality ?? "m",
            intent: Self.nilIfEmpty(preset.colprofIntent),
            fwa: preset.colprofFwa,
            illuminant: Self.nilIfEmpty(preset.colprofIlluminant),
            observer: Self.nilIfEmpty(preset.colprofObserver),
            inputViewingCond: Self.nilIfEmpty(preset.colprofInputViewingCond),
            outputViewingCond: Self.nilIfEmpty(preset.colprofOutputViewingCond),
            description: description,
            copyright: copyright,
            basename: basename,
            workingDirectory: workingDirectory
        )
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

/// User-facing FWA selection for the Stage 4 form, plus the two
/// directions of `colprof_fwa` conversion centralised here so the view
/// models carry no mapping switches of their own (#82).
public enum ColprofFwaSelection: String, CaseIterable, Sendable, Equatable {
    case none = "none"
    case empty = ""
    case D50 = "D50"
    case D65 = "D65"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .empty: return "Bare (-f)"
        case .D50: return "D50"
        case .D65: return "D65"
        case .custom: return "Custom .sp"
        }
    }

    /// Preset `colprof_fwa` → selection. `nil`/`"none"` map to `.none`,
    /// `""` to `.empty`, `D50`/`D65` case-insensitively, and any other
    /// string is a custom `.sp` path.
    public init(presetValue: String?) {
        switch presetValue?.lowercased() {
        case nil, "none": self = .none
        case "": self = .empty
        case "d50": self = .D50
        case "d65": self = .D65
        default: self = .custom
        }
    }

    /// Selection → `colprof_fwa` value. `.custom` returns `customPath`.
    public func presetValue(customPath: String) -> String? {
        switch self {
        case .none: return nil
        case .empty: return ""
        case .D50: return "D50"
        case .D65: return "D65"
        case .custom: return customPath
        }
    }
}

extension PageSize {
    /// `"210x297"` custom page parse used by presets (issue #82).
    public static func parseCustom(_ raw: String) -> (Double, Double)? {
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2,
              let w = Double(parts[0]), let h = Double(parts[1]),
              w >= 50, h >= 50 else { return nil }
        return (w, h)
    }
}

extension ProfilingPreset {
    /// Snapshot of the three live configs plus calibration toggles.
    public init(
        id: String,
        name: String,
        description: String,
        targen: TargenConfig,
        printtarg: PrinttargConfig,
        colprof: ColprofConfig,
        calibrationFile: String?,
        applyCalibration: Bool?
    ) {
        let pageSize: String
        if printtarg.pageSize == .custom {
            pageSize = "\(Int(printtarg.customPageWidth))x\(Int(printtarg.customPageHeight))"
        } else {
            pageSize = printtarg.pageSize.rawValue
        }
        self.init(
            id: id,
            name: name,
            description: description,
            colourSpace: targen.colourSpace == .cmyk ? "cmyk" : "rgb",
            patchCount: targen.patchCount,
            whitePatches: targen.whitePatches,
            blackPatches: targen.blackPatches,
            greySteps: targen.greySteps,
            singleChannelSteps: targen.singleChannelSteps,
            neutralSteps: targen.neutralSteps,
            neutralConcentration: targen.neutralConcentration,
            preconditioningProfile: targen.preconditioningProfile,
            ofpsHighQuality: targen.ofpsHighQuality,
            ofpsAdaptation: targen.ofpsAdaptation,
            fullSpreadAlgorithm: (targen.fullSpreadAlgorithm ?? .ofps).presetValue,
            totalInkLimit: targen.totalInkLimit,
            darkEmphasis: targen.darkEmphasis,
            devicePower: targen.devicePower,
            instrument: printtarg.instrument.rawValue,
            pageSize: pageSize,
            bitDepth: printtarg.bitDepth.rawValue,
            dpi: printtarg.dpi,
            randomSeed: printtarg.layoutOrder == .deterministic ? 1 : printtarg.customSeed,
            noRandomize: printtarg.layoutOrder == .raster,
            calibrationFile: calibrationFile,
            applyCalibration: applyCalibration,
            colprofAlgorithm: colprof.algorithm,
            colprofQuality: colprof.quality,
            colprofIntent: colprof.intent,
            colprofFwa: colprof.fwa,
            colprofIlluminant: colprof.illuminant,
            colprofObserver: colprof.observer,
            colprofInputViewingCond: colprof.inputViewingCond,
            colprofOutputViewingCond: colprof.outputViewingCond
        )
    }
}
