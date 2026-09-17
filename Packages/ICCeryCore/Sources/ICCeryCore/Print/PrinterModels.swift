import Foundation

/// Queue status reported by `lpstat -p` (docs/10 §Printer).
public enum PrinterStatus: String, Codable, Sendable, CaseIterable {
    case idle = "Idle"
    case printing = "Printing"
    case stopped = "Stopped"
    case unknown = "Unknown"
}

/// A CUPS destination. `name` is the queue id sent back to every
/// subsequent print command; `displayName` is the human label from
/// `printer-info` (used as the `NSPrinter` fallback when PM binding
/// fails — #188).
public struct Printer: Codable, Equatable, Sendable {
    public var name: String
    public var status: PrinterStatus
    public var isDefault: Bool
    public var displayName: String?
    /// AirPrint queue (#202, docs/14 §10.2) — the URF pipeline is always
    /// colour-managed, so Stage 2 shows a persistent warning badge.
    public var isAirPrint: Bool = false

    public init(
        name: String,
        status: PrinterStatus = .unknown,
        isDefault: Bool = false,
        displayName: String? = nil,
        isAirPrint: Bool = false
    ) {
        self.name = name
        self.status = status
        self.isDefault = isDefault
        self.displayName = displayName
        self.isAirPrint = isAirPrint
    }

    /// `isAirPrint` predates #202 payloads — a missing key decodes as
    /// `false` instead of failing the whole decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        status = try c.decode(PrinterStatus.self, forKey: .status)
        isDefault = try c.decode(Bool.self, forKey: .isDefault)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        isAirPrint = try c.decodeIfPresent(Bool.self, forKey: .isAirPrint) ?? false
    }
}

/// Paper source. `id` is the 1-based index of the `InputSlot` /
/// `MediaSource` choice (not a PPD code) — docs/10.
public struct PrinterTray: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// Media size from `PageSize` / `MediaSize` choices (1-based index).
public struct PrinterPaperSize: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// Media type: `id` is the PPD machine token, `name` the human label
/// after `/` when a readable PPD enriches it (docs/10 §PPD id/Human).
public struct PrinterMediaType: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Print quality: `id` is the option token (e.g. `"303"`), `name` the
/// human label after PPD enrichment (mirrors `PrinterMediaType`, #183).
public struct PrinterQuality: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct PrinterCapabilities: Codable, Equatable, Sendable {
    public var trays: [PrinterTray]
    public var paperSizes: [PrinterPaperSize]
    public var mediaTypes: [PrinterMediaType]
    /// Always `true` on macOS (spec parity — CUPS honours
    /// `orientation-requested`).
    public var supportsOrientation: Bool
    /// The queue's detected quality enumeration key
    /// (`CupsParsers.detectQualityKey`), e.g. `EPIJ_Qual` (#183).
    public var qualityKey: String?
    public var qualities: [PrinterQuality]
    /// The `*`-marked default choice from `lpoptions -l`, if any.
    public var qualityDefault: String?
    /// Media-type id → the quality ids the driver accepts for it
    /// (#214 — `MediaQualityConstraints`). Empty when the driver
    /// exposes no per-media quality matrix; a missing entry means
    /// "unconstrained" — show everything.
    public var qualityIDsByMediaType: [String: Set<String>]

    public init(
        trays: [PrinterTray] = [],
        paperSizes: [PrinterPaperSize] = [],
        mediaTypes: [PrinterMediaType] = [],
        supportsOrientation: Bool = true,
        qualityKey: String? = nil,
        qualities: [PrinterQuality] = [],
        qualityDefault: String? = nil,
        qualityIDsByMediaType: [String: Set<String>] = [:]
    ) {
        self.trays = trays
        self.paperSizes = paperSizes
        self.mediaTypes = mediaTypes
        self.supportsOrientation = supportsOrientation
        self.qualityKey = qualityKey
        self.qualities = qualities
        self.qualityDefault = qualityDefault
        self.qualityIDsByMediaType = qualityIDsByMediaType
    }

    /// Qualities valid for `mediaID`, preserving the driver's listing
    /// order (#180). Falls back to the full list when the driver has
    /// no per-media data, the media is absent from the map, or the
    /// filter would empty the picker (#214).
    public func qualities(forMediaType mediaID: String?) -> [PrinterQuality] {
        guard let mediaID,
              let allowed = qualityIDsByMediaType[mediaID],
              !allowed.isEmpty
        else { return qualities }
        let filtered = qualities.filter { allowed.contains($0.id) }
        return filtered.isEmpty ? qualities : filtered
    }

    /// Whether `qualityID` is usable with `mediaID` — `true` whenever
    /// the driver exposes no constraint for that media (#214). A
    /// quality absent from `qualities` entirely is still allowed: a
    /// driver-captured token can be legitimate even when `lpoptions`
    /// never listed it.
    public func allowsQuality(
        _ qualityID: String, forMediaType mediaID: String?
    ) -> Bool {
        guard let mediaID,
              let allowed = qualityIDsByMediaType[mediaID],
              !allowed.isEmpty
        else { return true }
        return allowed.contains(qualityID)
    }
}

/// The Stage 2 mirror — panel selections and the captured `k=v`
/// string (docs/10 §PrintOptions). Since #201 removed the `lp` path
/// these fields feed `TargetPrintOverrides` (Stage 2 always wins, D6)
/// and the mirror apply-back; the opaque vendor state now travels
/// inside the `PrintTicket`, not a flattened option string.
public struct PrintOptions: Codable, Equatable, Sendable {
    public var paperSource: Int?
    /// `"portrait"` / `"landscape"` → `orientation-requested=3|4`.
    public var orientation: String?
    /// Stage 2 paper token → `PageSize=` ticket write + `PMPaper`.
    public var paperSize: String?
    public var mediaType: String?
    /// Print-quality token → `<detectedQualityKey>=` ticket write.
    public var quality: String?
    public var ppdUncorrectedPassthrough: Bool?
    /// Space-separated `key=value` captured from
    /// `PMPrintSettingsToOptions` and filtered (docs/11 layer ⑥) —
    /// the Stage 2 mirror only, never an `lp` payload.
    public var cupsOptions: String?

    public init(
        paperSource: Int? = nil,
        orientation: String? = nil,
        paperSize: String? = nil,
        mediaType: String? = nil,
        quality: String? = nil,
        ppdUncorrectedPassthrough: Bool? = nil,
        cupsOptions: String? = nil
    ) {
        self.paperSource = paperSource
        self.orientation = orientation
        self.paperSize = paperSize
        self.mediaType = mediaType
        self.quality = quality
        self.ppdUncorrectedPassthrough = ppdUncorrectedPassthrough
        self.cupsOptions = cupsOptions
    }
}

/// Returned by the printer-properties panel (docs/10 §PrintPropertiesResult).
/// `nil` from the service means the user cancelled — never an error.
public struct PrintPropertiesResult: Codable, Equatable, Sendable {
    /// CUPS printer id the panel ended on (`PMPrinterGetID`), or `nil`
    /// when the `NSPrinter` fallback ran.
    public var selectedPrinter: String?
    public var options: PrintOptions

    public init(selectedPrinter: String?, options: PrintOptions) {
        self.selectedPrinter = selectedPrinter
        self.options = options
    }
}
