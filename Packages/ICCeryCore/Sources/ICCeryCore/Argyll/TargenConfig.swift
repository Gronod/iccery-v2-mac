import Foundation

/// Colour space for patch generation (docs/08, docs/04 §1.2).
public enum ColourSpace: String, Codable, Sendable, CaseIterable {
    case rgb
    case cmyk

    /// Argyll targen `-d` flag argument: 2 for RGB, 4 for CMYK.
    public var dFlagValue: String {
        switch self {
        case .rgb: return "2"
        case .cmyk: return "4"
        }
    }
}

/// Patch count preset for Stage 1.
public enum PatchCountPreset: String, Codable, Sendable, CaseIterable {
    case draft400 = "400"
    case standard800 = "800"
    case photo1500 = "1500"
    case custom = "custom"

    public var patchCount: Int? {
        switch self {
        case .draft400: return 400
        case .standard800: return 800
        case .photo1500: return 1500
        case .custom: return nil
        }
    }

    public var title: String {
        switch self {
        case .draft400: return "Draft (400)"
        case .standard800: return "Standard (800)"
        case .photo1500: return "Photo (1500)"
        case .custom: return "Custom"
        }
    }
}

/// Full spread patch distribution algorithm (docs/08).
/// Default is "ofps" (no flag emitted).
public enum FullSpreadAlgorithm: String, Codable, Sendable, CaseIterable {
    case ofps = "ofps"
    case target = "-t"
    case random = "-r"
    case uniformRandom = "-R"
    case quasiRandom = "-q"
    case uniformQuasiRandom = "-Q"
    case invertedQuasiRandom = "-i"
    case invertedUniformQuasiRandom = "-I"

    public var displayName: String {
        switch self {
        case .ofps: return "OFPS (Default)"
        case .target: return "Target (-t)"
        case .random: return "Random (-r)"
        case .uniformRandom: return "Uniform Random (-R)"
        case .quasiRandom: return "Quasi-random (-q)"
        case .uniformQuasiRandom: return "Uniform Quasi-random (-Q)"
        case .invertedQuasiRandom: return "Inverted Quasi-random (-i)"
        case .invertedUniformQuasiRandom: return "Inverted Uniform Quasi-random (-I)"
        }
    }

    public var flag: String? {
        switch self {
        case .ofps: return nil
        default: return rawValue
        }
    }

    /// Preset JSON value: `"ofps"` or the bare flag letter
    /// (`t`, `r`, `R`, `q`, `Q`, `i`, `I`) — docs/22.
    public var presetValue: String {
        switch self {
        case .ofps: return "ofps"
        default: return String(rawValue.dropFirst())
        }
    }

    public init?(presetValue: String) {
        if presetValue == "ofps" {
            self = .ofps
        } else {
            self.init(rawValue: "-" + presetValue)
        }
    }
}

/// Configuration model for `targen` invocation (docs/08, docs/04 §1.2).
public struct TargenConfig: Codable, Equatable, Sendable {
    public var colourSpace: ColourSpace
    public var patchCount: Int
    public var whitePatches: Int
    public var blackPatches: Int
    public var greySteps: Int?
    public var singleChannelSteps: Int?
    public var neutralSteps: Int?
    public var neutralConcentration: Double?
    public var preconditioningProfile: String?
    public var ofpsHighQuality: Bool?
    public var ofpsAdaptation: Double?
    public var fullSpreadAlgorithm: FullSpreadAlgorithm?
    public var totalInkLimit: Int?
    public var darkEmphasis: Double?
    public var devicePower: Double?
    public var basename: String
    public var workingDirectory: URL?

    public init(
        colourSpace: ColourSpace = .rgb,
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
        fullSpreadAlgorithm: FullSpreadAlgorithm? = nil,
        totalInkLimit: Int? = nil,
        darkEmphasis: Double? = nil,
        devicePower: Double? = nil,
        basename: String = "",
        workingDirectory: URL? = nil
    ) {
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
        self.basename = basename
        self.workingDirectory = workingDirectory
    }
}
