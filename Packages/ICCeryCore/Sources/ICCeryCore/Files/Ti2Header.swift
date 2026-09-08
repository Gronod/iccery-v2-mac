import Foundation

/// Parsed header of a `.ti2` chart-layout file (docs/06 §Resume).
/// `parse_ti2_header` reads only CGATS keyword lines — the data grid
/// itself belongs to issue #30.
public struct Ti2Header: Sendable, Equatable {
    /// `TARGET_INSTRUMENT` (e.g. `i1`, `i1iO`, `CM`).
    public var instrument: String?
    /// `NUMBER_OF_SETS` — the patch count. Note: `NUMBER_OF_FIELDS` is
    /// the CGATS column count, *not* the patch count.
    public var patchCount: Int?
    /// `NUMBER_OF_PAGES`.
    public var pageCount: Int?
    /// A sibling `<stem>.ti1` exists next to the parsed file.
    public var hasSiblingTi1 = false

    public static func parse(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Ti2Header {
        var header = Ti2Header()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return header
        }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("BEGIN_DATA_FORMAT") || line.hasPrefix("BEGIN_DATA") {
                break
            }
            // CGATS keyword lines: `KEYWORD "value"` or `KEYWORD value`.
            guard let space = line.firstIndex(of: " ") else { continue }
            let key = String(line[..<space])
            let value = String(line[line.index(after: space)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "TARGET_INSTRUMENT":
                header.instrument = value
            case "NUMBER_OF_SETS":
                header.patchCount = Int(value)
            case "NUMBER_OF_PAGES":
                header.pageCount = Int(value)
            default:
                continue
            }
        }
        let stem = url.deletingPathExtension()
        header.hasSiblingTi1 = fileManager.fileExists(
            atPath: stem.appendingPathExtension("ti1").path
        )
        return header
    }
}
