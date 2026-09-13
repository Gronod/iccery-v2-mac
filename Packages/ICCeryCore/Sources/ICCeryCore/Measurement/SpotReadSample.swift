import Foundation

/// One patch measurement emitted by a running `spotread` child (#148).
public struct SpotReadSample: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    /// D50 Lab (always present — derived from XYZ when needed).
    public var lab: LabColor
    /// XYZ on the 0–100 scale used by the fork, when the line carried it.
    public var xyz: XYZColor?
    public var instrumentName: String
    public var port: Int?
    /// Diagnostics only — never rendered as HTML or shown in the table.
    public var rawLine: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        lab: LabColor,
        xyz: XYZColor? = nil,
        instrumentName: String = "",
        port: Int? = nil,
        rawLine: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.lab = lab
        self.xyz = xyz
        self.instrumentName = instrumentName
        self.port = port
        self.rawLine = rawLine
    }
}

/// Parses `spotread` result lines into Lab / XYZ triples.
///
/// The fork's line shape is the upstream
/// `Result is XYZ: <x> <y> <z>, D50 Lab: <L> <a> <b>`; a Lab-only line
/// also parses, and an XYZ-only line derives Lab via
/// `LabColorMath.xyzToLab` (D50).
public enum SpotReadParser {

    public static func parse(line: String) -> (xyz: XYZColor?, lab: LabColor)? {
        guard line.range(of: "result is", options: .caseInsensitive) != nil
            || line.range(of: #"\bLab\b"#, options: .regularExpression) != nil
            || line.range(of: #"\bXYZ\b"#, options: .regularExpression) != nil
        else { return nil }

        var xyz: XYZColor?
        var lab: LabColor?

        if let m = triple(#"\bXYZ\b[:\s]"#, in: line) {
            xyz = XYZColor(x: m.0, y: m.1, z: m.2)
        }
        if let m = triple(#"\bLab\b[:\s]"#, in: line) {
            lab = LabColor(l: m.0, a: m.1, b: m.2)
        }
        if lab == nil, let xyz {
            lab = LabColorMath.xyzToLab(xyz)
        }
        guard let lab else { return nil }
        return (xyz, lab)
    }

    private static func triple(_ marker: String, in line: String) -> (Double, Double, Double)? {
        let pattern = marker + #"\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 4,
              let r1 = Range(match.range(at: 1), in: line),
              let r2 = Range(match.range(at: 2), in: line),
              let r3 = Range(match.range(at: 3), in: line),
              let a = Double(line[r1]),
              let b = Double(line[r2]),
              let c = Double(line[r3])
        else { return nil }
        return (a, b, c)
    }
}
