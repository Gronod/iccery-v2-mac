import Foundation

/// A media recipe: a named binding of CUPS queue + paper + ink set +
/// optional `.cal` to a `ProfilingPreset` (issue #146, docs/22 §Media
/// library).
///
/// snake_case keys match the v1 JSON schema so `media_library.json`
/// stays import/export compatible. Identity + binding fields are
/// required; every other field is optional-defaulted. Unknown keys are
/// ignored on decode; missing required fields fail the whole array
/// decode (corrupt-file policy, never silently dropped).
public struct MediaRecipe: Codable, Equatable, Sendable, Identifiable {

    /// `"recipe-<uuid>"`, never user-typed.
    public var id: String
    public var name: String
    public var notes: String
    /// CUPS queue id (`Printer.name` — `Printer` has no `id` member).
    public var printerID: String
    /// Human label from `Printer.displayName`.
    public var printerDisplayName: String
    /// Library metadata only — never written to targen `-P`/`-I` flags.
    public var paperName: String
    /// Last captured CUPS `media_type`, read-only.
    public var driverMediaType: String?
    /// Free text: `"PK"`, `"MK"`, `"Photo Black"`, …
    public var inkSet: String
    /// `"rgb"` | `"cmyk"` — must match the bound preset.
    public var colourSpace: String
    /// `ProfilingPreset.id` (built-in or custom).
    public var presetID: String
    /// Absolute `.cal` path stored verbatim; `nil` = none.
    public var calibrationURL: String?
    public var applyCalibration: Bool
    public var created: Date
    public var updated: Date

    public init(
        id: String,
        name: String,
        notes: String = "",
        printerID: String,
        printerDisplayName: String = "",
        paperName: String = "",
        driverMediaType: String? = nil,
        inkSet: String = "",
        colourSpace: String,
        presetID: String,
        calibrationURL: String? = nil,
        applyCalibration: Bool = false,
        created: Date = Date(),
        updated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.printerID = printerID
        self.printerDisplayName = printerDisplayName
        self.paperName = paperName
        self.driverMediaType = driverMediaType
        self.inkSet = inkSet
        self.colourSpace = colourSpace
        self.presetID = presetID
        self.calibrationURL = calibrationURL
        self.applyCalibration = applyCalibration
        self.created = created
        self.updated = updated
    }

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case printerID = "printer_id"
        case printerDisplayName = "printer_display_name"
        case paperName = "paper_name"
        case driverMediaType = "driver_media_type"
        case inkSet = "ink_set"
        case colourSpace = "colour_space"
        case presetID = "preset_id"
        case calibrationURL = "calibration_url"
        case applyCalibration = "apply_calibration"
        case created, updated
    }

    /// Strict decode: required identity + binding fields must be
    /// present; optionals default. Unknown keys are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        printerID = try c.decode(String.self, forKey: .printerID)
        printerDisplayName = try c.decodeIfPresent(String.self, forKey: .printerDisplayName) ?? ""
        paperName = try c.decodeIfPresent(String.self, forKey: .paperName) ?? ""
        driverMediaType = try c.decodeIfPresent(String.self, forKey: .driverMediaType)
        inkSet = try c.decodeIfPresent(String.self, forKey: .inkSet) ?? ""
        colourSpace = try c.decode(String.self, forKey: .colourSpace)
        presetID = try c.decode(String.self, forKey: .presetID)
        calibrationURL = try c.decodeIfPresent(String.self, forKey: .calibrationURL)
        applyCalibration = try c.decodeIfPresent(Bool.self, forKey: .applyCalibration) ?? false
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? Date()
    }

    public enum ValidationError: LocalizedError, Equatable {
        case emptyName
        case emptyPrinterID
        case invalidColourSpace(String)
        case emptyPresetID
        case invalidCalibrationURL(String)

        public var errorDescription: String? {
            switch self {
            case .emptyName: return "Media recipe is missing a name."
            case .emptyPrinterID: return "Media recipe is missing a printer."
            case .invalidColourSpace(let v):
                return "colour_space must be \"rgb\" or \"cmyk\", got \"\(v)\"."
            case .emptyPresetID: return "Media recipe is missing a preset."
            case .invalidCalibrationURL(let v):
                return "calibration_url must be an absolute path without \"..\" or NUL, got \"\(v)\"."
            }
        }
    }

    /// Validates the binding fields. `colourSpace` is normalized to
    /// lowercase before comparison. `CAL_` cal names are **not**
    /// rejected — that is an apply-time policy, not schema.
    @discardableResult
    public func validated() throws -> MediaRecipe {
        var r = self
        r.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        r.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        r.colourSpace = colourSpace.lowercased()
        guard !r.name.isEmpty else { throw ValidationError.emptyName }
        guard !r.printerID.isEmpty else { throw ValidationError.emptyPrinterID }
        guard r.colourSpace == "rgb" || r.colourSpace == "cmyk" else {
            throw ValidationError.invalidColourSpace(colourSpace)
        }
        guard !r.presetID.isEmpty else { throw ValidationError.emptyPresetID }
        if let cal = r.calibrationURL, !cal.isEmpty {
            guard cal.hasPrefix("/"), !cal.contains(".."), !cal.contains("\0") else {
                throw ValidationError.invalidCalibrationURL(cal)
            }
        }
        return r
    }
}
