import Foundation

/// Incremental byte→line decoder for process pipes.
///
/// Splits raw `availableData` chunks at `0x0A`. A newline byte can never
/// appear inside a multi-byte UTF-8 sequence (continuation bytes are
/// ≥ 0x80), so splitting bytes at `\n` is always scalar-safe; each line
/// is then decoded with a lossy fallback for non-UTF-8 output.
public struct ProcessLineDecoder: Sendable {
    public private(set) var pending = Data()

    public init() {}

    /// Feeds a chunk; returns every complete line found (without `\n`).
    public mutating func feed(_ chunk: Data) -> [String] {
        guard !chunk.isEmpty else { return [] }
        pending.append(chunk)
        var lines: [String] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            var slice = pending.prefix(upTo: nl)
            pending = pending.suffix(from: pending.index(after: nl))
            // Tolerate CRLF output.
            if slice.last == 0x0D { slice = slice.dropLast() }
            lines.append(Self.decode(slice))
        }
        return lines
    }

    /// Flushes any unterminated remainder at EOF. Returns `nil` when empty.
    public mutating func finish() -> String? {
        guard !pending.isEmpty else { return nil }
        var rest = pending
        pending.removeAll(keepingCapacity: false)
        if rest.last == 0x0D { rest = rest.dropLast() }
        return rest.isEmpty ? nil : Self.decode(rest)
    }

    /// Emits the current unterminated tail as a single line and clears it.
    /// Used by `ProcessManager.flushPartialLine` for tools that emit
    /// progress dots without newlines.
    public mutating func flushPartial() -> String? {
        guard !pending.isEmpty else { return nil }
        var rest = pending
        pending.removeAll(keepingCapacity: false)
        if rest.last == 0x0D { rest = rest.dropLast() }
        let text = Self.decode(rest)
        return text.isEmpty ? nil : text
    }

    private static func decode(_ bytes: Data.SubSequence) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}
