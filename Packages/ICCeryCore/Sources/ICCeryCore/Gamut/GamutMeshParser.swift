import Foundation

/// Errors thrown by ``GamutMeshParser``.
public enum GamutMeshParseError: LocalizedError, Equatable, Sendable {
    case missingFile
    case readFailed(underlying: String)
    case emptyFile
    case noDataBlock
    case malformedVertexLine(line: Int, content: String)
    case malformedFaceLine(line: Int, content: String)
    case outOfBoundsVertexIndex(UInt32, max: UInt32)
    case invalidLabPlausibility(line: Int, content: String)

    public var errorDescription: String? {
        switch self {
        case .missingFile:
            return "Gamut file not found."
        case .readFailed(let reason):
            return "Could not read gamut file: \(reason)"
        case .emptyFile:
            return "Gamut file is empty."
        case .noDataBlock:
            return "Gamut file contains no BEGIN_DATA blocks."
        case .malformedVertexLine(let line, let content):
            return "Malformed vertex on line \(line): \(content)"
        case .malformedFaceLine(let line, let content):
            return "Malformed face on line \(line): \(content)"
        case .outOfBoundsVertexIndex(let index, let max):
            return "Face references vertex \(index) but only \(max + 1) vertices exist."
        case .invalidLabPlausibility(let line, let content):
            return "Lab value outside plausible range on line \(line): \(content)"
        }
    }
}

/// Parses Argyll `.gam` ASCII files into ``GamutMesh``.
///
/// The parser recognises two `BEGIN_DATA` … `END_DATA` blocks:
///
/// 1. Vertices: `VERTEX_NO LAB_L LAB_A LAB_B`
/// 2. Faces:    `VERTEX_0 VERTEX_1 VERTEX_2` (0-based indices)
///
/// Lines beginning with `#` and blank lines are ignored.  `BEGIN_DATA` and
/// `END_DATA` are matched case-insensitively.  The `VERTEX_NO` column is
/// discarded; vertices are indexed in push order, matching Argyll's output.
public enum GamutMeshParser {

    /// Parse the file at `url`.
    public static func parse(url: URL) throws -> GamutMesh {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GamutMeshParseError.missingFile
        }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw GamutMeshParseError.readFailed(underlying: "contents(atPath:) returned nil")
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii),
              !text.isEmpty else {
            throw GamutMeshParseError.emptyFile
        }
        return try parse(text: text)
    }

    /// Parse raw `.gam` text.
    public static func parse(text: String) throws -> GamutMesh {
        var vertices: [GamutVertex] = []
        var faces: [GamutTriangle] = []

        var dataBlock = 0
        var inData = false
        var lineNumber = 0
        var warnings: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            lineNumber += 1

            // Strip inline `#` comments before any other processing.
            let uncommented = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let trimmed = uncommented.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let upper = trimmed.uppercased()

            if upper == "BEGIN_DATA" {
                dataBlock += 1
                inData = true
                continue
            }
            if upper == "END_DATA" {
                inData = false
                continue
            }

            if !inData { continue }

            let parts = trimmed.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .compactMap(Double.init)

            guard !parts.isEmpty else { continue }

            if dataBlock == 1 {
                // Vertex format: index L a b
                guard parts.count >= 4 else {
                    warnings.append("vertex arity \(parts.count) on line \(lineNumber)")
                    continue
                }
                let l = parts[1]
                let a = parts[2]
                let b = parts[3]

                if l < 0 || l > 100 || abs(a) > 128 || abs(b) > 128 {
                    warnings.append("Lab plausibility warning on line \(lineNumber): L=\(l) a=\(a) b=\(b)")
                    // We still keep the vertex; Argyll can exceed ±128.
                }

                let lab = LabColor(l: l, a: a, b: b)
                let rgb = LabColorMath.labToSRGB(lab)
                vertices.append(GamutVertex(lab: lab, rgb: rgb))
            } else {
                // Face format: v0 v1 v2 (can extend for future n-gons, take first 3)
                guard parts.count >= 3 else {
                    warnings.append("face arity \(parts.count) on line \(lineNumber)")
                    continue
                }
                let idx = parts.prefix(3).compactMap { UInt32(exactly: $0) }
                guard idx.count == 3 else {
                    warnings.append("non-integer face indices on line \(lineNumber)")
                    continue
                }
                faces.append(GamutTriangle(a: idx[0], b: idx[1], c: idx[2]))
            }
        }

        // Trim out-of-bounds face indices instead of throwing, so a slightly
        // malformed file still renders.  This matches the Web viewer's
        // forgiving posture while surfacing the obvious cases.
        let validFaces = faces.filter { face in
            let max = UInt32(vertices.count)
            guard face.a < max, face.b < max, face.c < max else {
                warnings.append("dropping face \(face) referencing missing vertex")
                return false
            }
            return true
        }

        if dataBlock == 0 {
            throw GamutMeshParseError.noDataBlock
        }

        return GamutMesh(vertices: vertices, faces: validFaces)
    }
}
