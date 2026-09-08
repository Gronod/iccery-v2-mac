import Foundation

/// Accumulates stdout lines into a complete JSON document.
///
/// Several Argyll tools (`instlist`, `profcheck`, `printtarg` manifest)
/// emit pretty-printed multi-line JSON on stdout. Individual lines are
/// *not* valid JSON — only the whole block is — so callers route stdout
/// lines here and get `Data` back once the buffer parses.
///
/// `ROW_COLORS_JSON: ` lines never reach this type; ProcessManager
/// diverts them to `jsonRow` events first.
public struct JSONAccumulator: Sendable {
    private var buffer = Data()

    public init() {}

    /// Appends one stdout line. Returns the complete document bytes when
    /// the accumulated buffer forms valid JSON, otherwise `nil`.
    public mutating func feed(line: String) -> Data? {
        buffer.append(Data(line.utf8))
        buffer.append(0x0A)
        return tryParse()
    }

    /// Attempts to decode the accumulated buffer; clears it on success.
    public mutating func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = tryParse() else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Raw buffer when it parses, `nil` while still incomplete.
    public var completeData: Data? {
        var copy = self
        return copy.tryParse()
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }

    public var isEmpty: Bool { buffer.isEmpty }

    private mutating func tryParse() -> Data? {
        // Cheap gate: JSON documents start with { or [.
        guard let first = buffer.first(where: { !$0.isJSONWhitespace }),
              first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
        else { return nil }
        guard (try? JSONSerialization.jsonObject(with: buffer)) != nil else { return nil }
        let out = buffer
        buffer.removeAll(keepingCapacity: false)
        return out
    }
}

private extension UInt8 {
    var isJSONWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}
