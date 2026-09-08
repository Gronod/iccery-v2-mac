import Foundation

/// Legacy M1 preset shape (`name` + opaque string dictionary). Retained
/// solely to decode and migrate pre-M2 `settings.json`; new code uses
/// `ProfilingPreset` (docs/22 §ProfilingPreset).
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
///
/// Decoding is tolerant: missing keys take documented defaults and each
/// `custom_presets` element is tried as a typed `ProfilingPreset` first
/// and as a legacy M1 `CustomPreset` second — a malformed entry never
/// drops the rest of the array (preset migration, issue #11).
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
    public var customPresets: [ProfilingPreset]
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
        customPresets: [ProfilingPreset] = [],
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

    /// One element of `custom_presets`: typed first, legacy M1 second.
    private enum AnyPreset: Decodable {
        case typed(ProfilingPreset)
        case legacy(CustomPreset)

        init(from decoder: Decoder) throws {
            if let p = try? ProfilingPreset(from: decoder) {
                self = .typed(p)
                return
            }
            self = .legacy(try CustomPreset(from: decoder))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        argyllBinaryDir = try c.decodeIfPresent(String.self, forKey: .argyllBinaryDir) ?? d.argyllBinaryDir
        defaultInstrument = try c.decodeIfPresent(String.self, forKey: .defaultInstrument) ?? d.defaultInstrument
        logLevel = try c.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? d.logLevel
        deltaEGoodMax = try c.decodeIfPresent(Double.self, forKey: .deltaEGoodMax) ?? d.deltaEGoodMax
        deltaEWarningMax = try c.decodeIfPresent(Double.self, forKey: .deltaEWarningMax) ?? d.deltaEWarningMax
        enableI1Pro2Leds = try c.decodeIfPresent(Bool.self, forKey: .enableI1Pro2Leds) ?? d.enableI1Pro2Leds
        calibrationStaleDays = try c.decodeIfPresent(Int.self, forKey: .calibrationStaleDays) ?? d.calibrationStaleDays
        defaultInstallLocation = try c.decodeIfPresent(InstallLocation.self, forKey: .defaultInstallLocation) ?? d.defaultInstallLocation
        askBeforeOverwriteProfile = try c.decodeIfPresent(Bool.self, forKey: .askBeforeOverwriteProfile) ?? d.askBeforeOverwriteProfile
        openColorPanelAfterInstall = try c.decodeIfPresent(Bool.self, forKey: .openColorPanelAfterInstall) ?? d.openColorPanelAfterInstall

        // Per-element decode: typed presets win; a legacy M1 shape
        // ({"name","values"}) migrates; unconvertible entries are
        // skipped so one bad record never drops the array.
        let elements = (try? c.decodeIfPresent(
            [FailableDecodable<AnyPreset>].self, forKey: .customPresets
        )) ?? nil
        var migrated: [ProfilingPreset] = []
        for (index, element) in (elements ?? []).enumerated() {
            switch element.value {
            case .typed(let preset):
                migrated.append(preset)
            case .legacy(let legacy):
                if let converted = ProfilingPreset(migrating: legacy, index: index) {
                    migrated.append(converted)
                } else {
                    AppLogger(category: "settings").warn(
                        "Skipped unmigratable legacy preset: \(legacy.name)"
                    )
                }
            case .none:
                AppLogger(category: "settings").warn(
                    "Skipped malformed preset entry at index \(index)"
                )
            }
        }
        customPresets = migrated
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

extension ProfilingPreset {

    /// Migrates a legacy M1 `CustomPreset` (`name` + string values) to
    /// the typed schema. Known keys are coerced; anything else is
    /// ignored. Returns `nil` only when the name is unusable — a
    /// deterministic `custom-{index}-{slug}` id is always produced.
    init?(migrating legacy: CustomPreset, index: Int) {
        let trimmedName = legacy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let v = legacy.values
        func int(_ key: String) -> Int? {
            v[key].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        func double(_ key: String) -> Double? {
            v[key].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        func bool(_ key: String) -> Bool? {
            v[key].flatMap { s in
                switch s.trimmingCharacters(in: .whitespaces).lowercased() {
                case "true", "1", "yes": return true
                case "false", "0", "no": return false
                default: return nil
                }
            }
        }
        func string(_ key: String) -> String? {
            v[key].map { $0.trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        let slug = trimmedName.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { $0.append($1) }

        self.init(
            id: "custom-\(index)-\(slug)",
            name: trimmedName,
            description: string("description") ?? "",
            colourSpace: string("colour_space")?.lowercased() ?? "rgb",
            patchCount: int("patch_count") ?? 800,
            whitePatches: int("white_patches") ?? 4,
            blackPatches: int("black_patches") ?? 4,
            greySteps: int("grey_steps"),
            singleChannelSteps: int("single_channel_steps"),
            neutralSteps: int("neutral_steps"),
            neutralConcentration: double("neutral_concentration"),
            preconditioningProfile: string("preconditioning_profile"),
            ofpsHighQuality: bool("ofps_high_quality"),
            ofpsAdaptation: double("ofps_adaptation"),
            fullSpreadAlgorithm: string("full_spread_algorithm"),
            totalInkLimit: int("total_ink_limit"),
            darkEmphasis: double("dark_emphasis"),
            devicePower: double("device_power"),
            instrument: string("instrument") ?? "i1",
            pageSize: string("page_size") ?? "A4",
            bitDepth: int("bit_depth") ?? 8,
            dpi: int("dpi") ?? 300,
            randomSeed: int("random_seed"),
            noRandomize: bool("no_randomize"),
            calibrationFile: string("calibration_file"),
            applyCalibration: bool("apply_calibration"),
            colprofAlgorithm: string("colprof_algorithm"),
            colprofQuality: string("colprof_quality"),
            colprofIntent: string("colprof_intent"),
            colprofFwa: string("colprof_fwa"),
            colprofIlluminant: string("colprof_illuminant"),
            colprofObserver: string("colprof_observer"),
            colprofInputViewingCond: string("colprof_input_viewing_cond"),
            colprofOutputViewingCond: string("colprof_output_viewing_cond")
        )
    }
}
