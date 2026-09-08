import Foundation

/// Measurement instrument for `printtarg -i` chart geometry
/// (docs/09, docs/04 §2.2). Raw values are the Argyll codes.
public enum PrintInstrument: String, Codable, Sendable, CaseIterable {
    case i1
    case p3
    case cm = "CM"
    case ss = "SS"
    case dtp20 = "20"
    case dtp22 = "22"
    case dtp41 = "41"
    case dtp51 = "51"

    public var displayName: String {
        switch self {
        case .i1:    return "X-Rite i1Pro / i1Pro 2"
        case .p3:    return "X-Rite i1Pro 3 / 3 Plus"
        case .cm:    return "ColorMunki"
        case .ss:    return "Specbos / Spectraval (XY table)"
        case .dtp20: return "Gretag i1Display 2"
        case .dtp22: return "X-Rite i1Display Pro / ColorMunki Display"
        case .dtp41: return "Datacolor Spyder 4/5"
        case .dtp51: return "Spyder X"
        }
    }
}

/// Page size for `printtarg -p` (docs/09). `.custom` emits `{W}x{H}` mm.
public enum PageSize: String, Codable, Sendable, CaseIterable {
    case a4 = "A4"
    case a4r = "A4R"
    case a3 = "A3"
    case a2 = "A2"
    case letter = "Letter"
    case letterR = "LetterR"
    case legal = "Legal"
    case fourBySix = "4x6"
    case elevenBySeventeen = "11x17"
    case custom = "custom"

    public var isCustom: Bool { self == .custom }
}

/// TIFF bit depth: `-t` (8-bit) or `-T` (16-bit).
public enum TiffBitDepth: Int, Codable, Sendable, CaseIterable {
    case eight = 8
    case sixteen = 16

    public var flag: String {
        switch self {
        case .eight:   return "-t"
        case .sixteen: return "-T"
        }
    }
}

/// Patch layout order (docs/09 §Randomisation, #163).
/// `.deterministic` is the default (`-R 1`); `.raster` emits `-r` and
/// supersedes any seed — never confuse with targen's `-r` algorithm.
public enum LayoutOrder: String, Codable, Sendable, CaseIterable {
    case deterministic
    case customSeed = "custom_seed"
    case raster

    public var displayName: String {
        switch self {
        case .deterministic: return "Deterministic (seed 1)"
        case .customSeed:    return "Custom seed"
        case .raster:        return "Raster order (no shuffle)"
        }
    }
}

/// Chart label metadata used to assemble the automatic `printtarg -d`
/// label. Any empty/missing component becomes `Unspecified` until real
/// printer metadata lands in M3.
public struct TargetLabelMetadata: Codable, Equatable, Sendable {
    public var printer: String
    public var inkSet: String
    public var driverPaper: String
    public var actualPaper: String

    public init(
        printer: String = "",
        inkSet: String = "",
        driverPaper: String = "",
        actualPaper: String = ""
    ) {
        self.printer = printer
        self.inkSet = inkSet
        self.driverPaper = driverPaper
        self.actualPaper = actualPaper
    }
}

/// Builds the chart legend for `printtarg -d` (fork argyllcms#19,
/// ICCery #119). `-d` here is a **label string** — not targen's colour
/// space, not iccgamut's density (docs/25).
public enum PrinttargLabel {

    public static let unspecified = "Unspecified"

    /// `ICCery - {basename} - {printer} - {ink} - {driverPaper} -
    /// {actualPaper} - DD/MM/YYYY HH:MM`
    ///
    /// `date` is injected for deterministic tests; production passes
    /// the current local time. A fixed POSIX locale keeps the format
    /// stable regardless of user locale.
    public static func automatic(
        basename: String,
        metadata: TargetLabelMetadata,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd/MM/yyyy HH:mm"

        return [
            "ICCery",
            basename,
            field(metadata.printer),
            field(metadata.inkSet),
            field(metadata.driverPaper),
            field(metadata.actualPaper),
            formatter.string(from: date),
        ].joined(separator: " - ")
    }

    /// Resolves the label to emit: an explicit non-empty manual label
    /// wins; otherwise the assembled automatic label.
    public static func resolved(
        customLabel: String?,
        basename: String,
        metadata: TargetLabelMetadata,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        if let label = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        return automatic(basename: basename, metadata: metadata, date: date, timeZone: timeZone)
    }

    private static func field(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unspecified : trimmed
    }
}

/// Configuration model for `printtarg` invocation (docs/09, docs/04 §2.2).
public struct PrinttargConfig: Codable, Equatable, Sendable {
    public var instrument: PrintInstrument
    public var pageSize: PageSize
    /// Custom page dimensions in millimetres; each must be ≥ 50 when
    /// `pageSize == .custom`.
    public var customPageWidth: Double
    public var customPageHeight: Double
    public var bitDepth: TiffBitDepth
    public var dpi: Int
    public var layoutOrder: LayoutOrder
    /// Seed for `.customSeed` layout (`-R N`, N ≥ 1). Ignored for
    /// `.deterministic` (fixed `-R 1`) and `.raster` (`-r`).
    public var customSeed: Int
    /// Resolved `-d` label. Callers usually compute this via
    /// `PrinttargLabel.resolved` so tests can inject the clock.
    public var label: String?
    /// `.cal` file applied to printed patches (`-K`), or embedded
    /// without applying (`-I` when `calibrationEmbedOnly`). Never
    /// emitted for `CAL_` basenames (Stage 0 protection).
    public var calibrationFile: String?
    public var calibrationEmbedOnly: Bool
    public var basename: String
    public var workingDirectory: URL?

    public init(
        instrument: PrintInstrument = .i1,
        pageSize: PageSize = .a4,
        customPageWidth: Double = 210,
        customPageHeight: Double = 297,
        bitDepth: TiffBitDepth = .eight,
        dpi: Int = 300,
        layoutOrder: LayoutOrder = .deterministic,
        customSeed: Int = 1,
        label: String? = nil,
        calibrationFile: String? = nil,
        calibrationEmbedOnly: Bool = false,
        basename: String = "",
        workingDirectory: URL? = nil
    ) {
        self.instrument = instrument
        self.pageSize = pageSize
        self.customPageWidth = customPageWidth
        self.customPageHeight = customPageHeight
        self.bitDepth = bitDepth
        self.dpi = dpi
        self.layoutOrder = layoutOrder
        self.customSeed = customSeed
        self.label = label
        self.calibrationFile = calibrationFile
        self.calibrationEmbedOnly = calibrationEmbedOnly
        self.basename = basename
        self.workingDirectory = workingDirectory
    }
}
