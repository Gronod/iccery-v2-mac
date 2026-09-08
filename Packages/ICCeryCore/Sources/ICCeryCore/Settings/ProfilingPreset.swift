import Foundation

/// A profiling preset: a complete snapshot of the Stage 1/2 form plus
/// the Stage 4 fields that are stored now and applied in issue 23
/// (docs/22 §ProfilingPreset).
///
/// snake_case keys match the v1 JSON schema so import/export stays
/// compatible. Identity + Stage 1/2 core fields are required; every
/// other field is optional-defaulted. Unknown keys are ignored on
/// decode; missing required fields fail.
public struct ProfilingPreset: Codable, Equatable, Sendable, Identifiable {

    // Identity
    public var id: String
    public var name: String
    public var description: String

    // Stage 1 (required core)
    public var colourSpace: String          // "rgb" | "cmyk"
    public var patchCount: Int
    public var whitePatches: Int
    public var blackPatches: Int

    // Stage 1 advanced (optional)
    public var greySteps: Int?
    public var singleChannelSteps: Int?
    public var neutralSteps: Int?
    public var neutralConcentration: Double?
    public var preconditioningProfile: String?
    public var ofpsHighQuality: Bool?
    public var ofpsAdaptation: Double?
    /// Stored as the flag letter: "ofps" or "t","r","R","q","Q","i","I".
    public var fullSpreadAlgorithm: String?
    public var totalInkLimit: Int?
    public var darkEmphasis: Double?
    public var devicePower: Double?

    // Stage 2 (required core)
    public var instrument: String
    public var pageSize: String
    public var bitDepth: Int
    public var dpi: Int
    public var randomSeed: Int?
    public var noRandomize: Bool?

    // Stage 0 / 2 calibration
    public var calibrationFile: String?
    public var applyCalibration: Bool?

    // Stage 4 (stored now, applied by issue 23)
    public var colprofAlgorithm: String?
    public var colprofQuality: String?
    public var colprofIntent: String?
    public var colprofFwa: String?
    public var colprofIlluminant: String?
    public var colprofObserver: String?
    public var colprofInputViewingCond: String?
    public var colprofOutputViewingCond: String?

    public init(
        id: String,
        name: String,
        description: String = "",
        colourSpace: String = "rgb",
        patchCount: Int = 800,
        whitePatches: Int = 4,
        blackPatches: Int = 4,
        greySteps: Int? = nil,
        singleChannelSteps: Int? = nil,
        neutralSteps: Int? = nil,
        neutralConcentration: Double? = nil,
        preconditioningProfile: String? = nil,
        ofpsHighQuality: Bool? = nil,
        ofpsAdaptation: Double? = nil,
        fullSpreadAlgorithm: String? = nil,
        totalInkLimit: Int? = nil,
        darkEmphasis: Double? = nil,
        devicePower: Double? = nil,
        instrument: String = "i1",
        pageSize: String = "A4",
        bitDepth: Int = 8,
        dpi: Int = 300,
        randomSeed: Int? = 1,
        noRandomize: Bool? = false,
        calibrationFile: String? = nil,
        applyCalibration: Bool? = nil,
        colprofAlgorithm: String? = nil,
        colprofQuality: String? = nil,
        colprofIntent: String? = nil,
        colprofFwa: String? = nil,
        colprofIlluminant: String? = nil,
        colprofObserver: String? = nil,
        colprofInputViewingCond: String? = nil,
        colprofOutputViewingCond: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.colourSpace = colourSpace
        self.patchCount = patchCount
        self.whitePatches = whitePatches
        self.blackPatches = blackPatches
        self.greySteps = greySteps
        self.singleChannelSteps = singleChannelSteps
        self.neutralSteps = neutralSteps
        self.neutralConcentration = neutralConcentration
        self.preconditioningProfile = preconditioningProfile
        self.ofpsHighQuality = ofpsHighQuality
        self.ofpsAdaptation = ofpsAdaptation
        self.fullSpreadAlgorithm = fullSpreadAlgorithm
        self.totalInkLimit = totalInkLimit
        self.darkEmphasis = darkEmphasis
        self.devicePower = devicePower
        self.instrument = instrument
        self.pageSize = pageSize
        self.bitDepth = bitDepth
        self.dpi = dpi
        self.randomSeed = randomSeed
        self.noRandomize = noRandomize
        self.calibrationFile = calibrationFile
        self.applyCalibration = applyCalibration
        self.colprofAlgorithm = colprofAlgorithm
        self.colprofQuality = colprofQuality
        self.colprofIntent = colprofIntent
        self.colprofFwa = colprofFwa
        self.colprofIlluminant = colprofIlluminant
        self.colprofObserver = colprofObserver
        self.colprofInputViewingCond = colprofInputViewingCond
        self.colprofOutputViewingCond = colprofOutputViewingCond
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case colourSpace = "colour_space"
        case patchCount = "patch_count"
        case whitePatches = "white_patches"
        case blackPatches = "black_patches"
        case greySteps = "grey_steps"
        case singleChannelSteps = "single_channel_steps"
        case neutralSteps = "neutral_steps"
        case neutralConcentration = "neutral_concentration"
        case preconditioningProfile = "preconditioning_profile"
        case ofpsHighQuality = "ofps_high_quality"
        case ofpsAdaptation = "ofps_adaptation"
        case fullSpreadAlgorithm = "full_spread_algorithm"
        case totalInkLimit = "total_ink_limit"
        case darkEmphasis = "dark_emphasis"
        case devicePower = "device_power"
        case instrument
        case pageSize = "page_size"
        case bitDepth = "bit_depth"
        case dpi
        case randomSeed = "random_seed"
        case noRandomize = "no_randomize"
        case calibrationFile = "calibration_file"
        case applyCalibration = "apply_calibration"
        case colprofAlgorithm = "colprof_algorithm"
        case colprofQuality = "colprof_quality"
        case colprofIntent = "colprof_intent"
        case colprofFwa = "colprof_fwa"
        case colprofIlluminant = "colprof_illuminant"
        case colprofObserver = "colprof_observer"
        case colprofInputViewingCond = "colprof_input_viewing_cond"
        case colprofOutputViewingCond = "colprof_output_viewing_cond"
    }

    /// Strict decode: required identity + Stage 1/2 core fields must be
    /// present; optionals default to nil. Unknown keys are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        colourSpace = try c.decode(String.self, forKey: .colourSpace)
        patchCount = try c.decode(Int.self, forKey: .patchCount)
        whitePatches = try c.decode(Int.self, forKey: .whitePatches)
        blackPatches = try c.decode(Int.self, forKey: .blackPatches)
        greySteps = try c.decodeIfPresent(Int.self, forKey: .greySteps)
        singleChannelSteps = try c.decodeIfPresent(Int.self, forKey: .singleChannelSteps)
        neutralSteps = try c.decodeIfPresent(Int.self, forKey: .neutralSteps)
        neutralConcentration = try c.decodeIfPresent(Double.self, forKey: .neutralConcentration)
        preconditioningProfile = try c.decodeIfPresent(String.self, forKey: .preconditioningProfile)
        ofpsHighQuality = try c.decodeIfPresent(Bool.self, forKey: .ofpsHighQuality)
        ofpsAdaptation = try c.decodeIfPresent(Double.self, forKey: .ofpsAdaptation)
        fullSpreadAlgorithm = try c.decodeIfPresent(String.self, forKey: .fullSpreadAlgorithm)
        totalInkLimit = try c.decodeIfPresent(Int.self, forKey: .totalInkLimit)
        darkEmphasis = try c.decodeIfPresent(Double.self, forKey: .darkEmphasis)
        devicePower = try c.decodeIfPresent(Double.self, forKey: .devicePower)
        instrument = try c.decode(String.self, forKey: .instrument)
        pageSize = try c.decode(String.self, forKey: .pageSize)
        bitDepth = try c.decode(Int.self, forKey: .bitDepth)
        dpi = try c.decode(Int.self, forKey: .dpi)
        randomSeed = try c.decodeIfPresent(Int.self, forKey: .randomSeed)
        noRandomize = try c.decodeIfPresent(Bool.self, forKey: .noRandomize)
        calibrationFile = try c.decodeIfPresent(String.self, forKey: .calibrationFile)
        applyCalibration = try c.decodeIfPresent(Bool.self, forKey: .applyCalibration)
        colprofAlgorithm = try c.decodeIfPresent(String.self, forKey: .colprofAlgorithm)
        colprofQuality = try c.decodeIfPresent(String.self, forKey: .colprofQuality)
        colprofIntent = try c.decodeIfPresent(String.self, forKey: .colprofIntent)
        colprofFwa = try c.decodeIfPresent(String.self, forKey: .colprofFwa)
        colprofIlluminant = try c.decodeIfPresent(String.self, forKey: .colprofIlluminant)
        colprofObserver = try c.decodeIfPresent(String.self, forKey: .colprofObserver)
        colprofInputViewingCond = try c.decodeIfPresent(String.self, forKey: .colprofInputViewingCond)
        colprofOutputViewingCond = try c.decodeIfPresent(String.self, forKey: .colprofOutputViewingCond)
    }

    // MARK: - Validation (import path)

    public enum ValidationError: LocalizedError, Equatable {
        case emptyID
        case emptyName
        case invalidColourSpace(String)
        case invalidPatchCount(Int)
        case invalidBitDepth(Int)
        case invalidDPI(Int)
        case emptyPageSize
        case emptyInstrument

        public var errorDescription: String? {
            switch self {
            case .emptyID: return "Preset is missing an id."
            case .emptyName: return "Preset is missing a name."
            case .invalidColourSpace(let v):
                return "colour_space must be \"rgb\" or \"cmyk\", got \"\(v)\"."
            case .invalidPatchCount(let v):
                return "patch_count must be positive, got \(v)."
            case .invalidBitDepth(let v):
                return "bit_depth must be 8 or 16, got \(v)."
            case .invalidDPI(let v):
                return "dpi must be between 72 and 600, got \(v)."
            case .emptyPageSize: return "page_size is empty."
            case .emptyInstrument: return "instrument is empty."
            }
        }
    }

    /// Validates the required fields for import / catalog use.
    /// `colourSpace` is normalized to lowercase before comparison.
    @discardableResult
    public func validated() throws -> ProfilingPreset {
        var p = self
        p.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.colourSpace = colourSpace.lowercased()
        guard !p.id.isEmpty else { throw ValidationError.emptyID }
        guard !p.name.isEmpty else { throw ValidationError.emptyName }
        guard p.colourSpace == "rgb" || p.colourSpace == "cmyk" else {
            throw ValidationError.invalidColourSpace(colourSpace)
        }
        guard p.patchCount > 0 else { throw ValidationError.invalidPatchCount(patchCount) }
        guard p.bitDepth == 8 || p.bitDepth == 16 else {
            throw ValidationError.invalidBitDepth(bitDepth)
        }
        guard (72...600).contains(p.dpi) else { throw ValidationError.invalidDPI(dpi) }
        guard !p.pageSize.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError.emptyPageSize
        }
        guard !p.instrument.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError.emptyInstrument
        }
        return p
    }
}

/// Per-element non-throwing decode wrapper — one malformed preset entry
/// must not drop the whole `custom_presets` array during migration.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
