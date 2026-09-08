import Foundation

/// A saved wizard preset slot (docs/22 §Presets). The preset *engine*
/// lands in issue #11; for M1 the store only needs a Codable container.
public struct CustomPreset: Codable, Equatable, Sendable {
    public var name: String
    /// Opaque per-stage form values — keyed by field id.
    public var values: [String: String]

    public init(name: String, values: [String: String] = [:]) {
        self.name = name
        self.values = values
    }
}

/// Where `install_profile` drops finished profiles (docs/22).
public enum InstallLocation: String, Codable, Sendable, CaseIterable {
    case user
    case system
}

/// `settings.json` model (docs/22). snake_case keys match the v1 file
/// so field names stay identical across rewrites.
public struct AppSettings: Codable, Equatable, Sendable {

    /// User override for Argyll binaries; `nil` → bundled sidecars.
    public var argyllBinaryDir: String?

    /// Stored but **never applied to argv** — Stage 2's own instrument
    /// select is the live source (docs/04 §0.1).
    public var defaultInstrument: String?

    /// `nil` → `.debug` in debug builds, `.info` in release (#158).
    public var logLevel: LogLevel?

    public var deltaEGoodMax: Double
    public var deltaEWarningMax: Double
    public var customPresets: [CustomPreset]
    public var enableI1Pro2Leds: Bool
    public var calibrationStaleDays: Int
    public var defaultInstallLocation: InstallLocation
    public var askBeforeOverwriteProfile: Bool
    public var openColorPanelAfterInstall: Bool

    public init(
        argyllBinaryDir: String? = nil,
        defaultInstrument: String? = nil,
        logLevel: LogLevel? = nil,
        deltaEGoodMax: Double = 2.0,
        deltaEWarningMax: Double = 5.0,
        customPresets: [CustomPreset] = [],
        enableI1Pro2Leds: Bool = false,
        calibrationStaleDays: Int = 30,
        defaultInstallLocation: InstallLocation = .user,
        askBeforeOverwriteProfile: Bool = true,
        openColorPanelAfterInstall: Bool = false
    ) {
        self.argyllBinaryDir = argyllBinaryDir
        self.defaultInstrument = defaultInstrument
        self.logLevel = logLevel
        self.deltaEGoodMax = deltaEGoodMax
        self.deltaEWarningMax = deltaEWarningMax
        self.customPresets = customPresets
        self.enableI1Pro2Leds = enableI1Pro2Leds
        self.calibrationStaleDays = calibrationStaleDays
        self.defaultInstallLocation = defaultInstallLocation
        self.askBeforeOverwriteProfile = askBeforeOverwriteProfile
        self.openColorPanelAfterInstall = openColorPanelAfterInstall
    }

    public static let `default` = AppSettings()

    /// Effective log level — runtime state, not just persistence (#158).
    public var effectiveLogLevel: LogLevel {
        if let logLevel { return logLevel }
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }

    enum CodingKeys: String, CodingKey {
        case argyllBinaryDir = "argyll_binary_dir"
        case defaultInstrument = "default_instrument"
        case logLevel = "log_level"
        case deltaEGoodMax = "delta_e_good_max"
        case deltaEWarningMax = "delta_e_warning_max"
        case customPresets = "custom_presets"
        case enableI1Pro2Leds = "enable_i1pro2_leds"
        case calibrationStaleDays = "calibration_stale_days"
        case defaultInstallLocation = "default_install_location"
        case askBeforeOverwriteProfile = "ask_before_overwrite_profile"
        case openColorPanelAfterInstall = "open_color_panel_after_install"
    }

    /// UI-facing validation. Strings are part of the contract (issue #5).
    public static let errorNegativeDeltaE = "ΔE thresholds cannot be negative."
    public static let errorThresholdOrder =
        "Good ΔE threshold must be strictly less than the warning threshold."

    /// All validation errors, in declaration order. Empty = valid.
    public func validate() -> [String] {
        var errors: [String] = []
        if deltaEGoodMax < 0 || deltaEWarningMax < 0 {
            errors.append(Self.errorNegativeDeltaE)
        }
        if deltaEGoodMax >= deltaEWarningMax {
            errors.append(Self.errorThresholdOrder)
        }
        return errors
    }

    public var isValid: Bool { validate().isEmpty }
}
