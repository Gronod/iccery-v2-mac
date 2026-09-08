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

    public init(
        name: String,
        status: PrinterStatus = .unknown,
        isDefault: Bool = false,
        displayName: String? = nil
    ) {
        self.name = name
        self.status = status
        self.isDefault = isDefault
        self.displayName = displayName
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

public struct PrinterCapabilities: Codable, Equatable, Sendable {
    public var trays: [PrinterTray]
    public var paperSizes: [PrinterPaperSize]
    public var mediaTypes: [PrinterMediaType]
    /// Always `true` on macOS (spec parity — CUPS honours
    /// `orientation-requested`).
    public var supportsOrientation: Bool

    public init(
        trays: [PrinterTray] = [],
        paperSizes: [PrinterPaperSize] = [],
        mediaTypes: [PrinterMediaType] = [],
        supportsOrientation: Bool = true
    ) {
        self.trays = trays
        self.paperSizes = paperSizes
        self.mediaTypes = mediaTypes
        self.supportsOrientation = supportsOrientation
    }
}

/// Options carried into `lp` (docs/10 §PrintOptions). On macOS
/// `paperSource` is ignored unless already present inside captured
/// `cupsOptions`; `ppdUncorrectedPassthrough` is stored (the panel sets
/// it on OK) but never gates the argv — macOS always bypasses driver
/// colour management.
public struct PrintOptions: Codable, Equatable, Sendable {
    public var paperSource: Int?
    /// `"portrait"` / `"landscape"` → `orientation-requested=3|4`.
    public var orientation: String?
    /// printtarg layout page size → `PageSize=` (skipped if captured).
    public var paperSize: String?
    public var mediaType: String?
    public var ppdUncorrectedPassthrough: Bool?
    /// Space-separated `key=value` captured from
    /// `PMPrintSettingsToOptions` and filtered (docs/11 layer ⑥).
    public var cupsOptions: String?

    public init(
        paperSource: Int? = nil,
        orientation: String? = nil,
        paperSize: String? = nil,
        mediaType: String? = nil,
        ppdUncorrectedPassthrough: Bool? = nil,
        cupsOptions: String? = nil
    ) {
        self.paperSource = paperSource
        self.orientation = orientation
        self.paperSize = paperSize
        self.mediaType = mediaType
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
