import Foundation

/// A single patch read by `chartread`.
public struct ChartreadPatch: Codable, Sendable, Equatable {
    public let id: String
    public let loc: String
    public let isPad: Bool
    public let device: [Double]
    public let expected: PatchColor?
    public let measured: PatchColor

    public init(
        id: String,
        loc: String,
        isPad: Bool,
        device: [Double],
        expected: PatchColor?,
        measured: PatchColor
    ) {
        self.id = id
        self.loc = loc
        self.isPad = isPad
        self.device = device
        self.expected = expected
        self.measured = measured
    }

    enum CodingKeys: String, CodingKey {
        case id, loc
        case isPad = "is_pad"
        case device, expected, measured
    }
}

/// Colour payload carried by `expected` or `measured`.
public struct PatchColor: Codable, Sendable, Equatable {
    public let xyz: CIEXYZ?
    public let lab: CIELab?
    public let spectral: SpectralData?

    public init(xyz: CIEXYZ? = nil, lab: CIELab? = nil, spectral: SpectralData? = nil) {
        self.xyz = xyz
        self.lab = lab
        self.spectral = spectral
    }

    enum CodingKeys: String, CodingKey {
        case xyz = "XYZ"
        case lab = "Lab"
        case spectral = "spectral"
    }
}

public struct CIEXYZ: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.x = try container.decode(Double.self)
        self.y = try container.decode(Double.self)
        self.z = try container.decode(Double.self)
    }

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}

public struct CIELab: Codable, Sendable, Equatable {
    public let l: Double
    public let a: Double
    public let b: Double

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.l = try container.decode(Double.self)
        self.a = try container.decode(Double.self)
        self.b = try container.decode(Double.self)
    }

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(l)
        try container.encode(a)
        try container.encode(b)
    }
}

public struct SpectralData: Codable, Sendable, Equatable {
    public let bands: Int
    public let startNM: Double
    public let endNM: Double
    public let norm: Double
    public let values: [Double]

    enum CodingKeys: String, CodingKey {
        case bands
        case startNM = "start_nm"
        case endNM = "end_nm"
        case norm
        case values
    }
}

/// A complete row emitted by `chartread -u`.
public struct ChartreadRow: Codable, Sendable, Equatable {
    public let event: String
    public let rowId: String
    public let rowIndex: Int
    public let totalRows: Int
    public let patchCount: Int
    public let patches: [ChartreadPatch]

    enum CodingKeys: String, CodingKey {
        case event
        case rowId = "row_id"
        case rowIndex = "row_index"
        case totalRows = "total_rows"
        case patchCount = "patch_count"
        case patches
    }

    public var isFinalRow: Bool {
        rowIndex + 1 >= totalRows
    }
}
