import Foundation

/// Errors from `instlist` output parsing.
public enum InstrumentParserError: Error, Sendable, Equatable {
    case malformedJSON
    case missingDevices
    case invalidPort
}

/// Parses the Argyll `instlist` stdout document.
///
/// Fork `instlist` emits pretty-printed JSON with the shape
/// `{ "event": "instruments", "devices": [ { "port": 1, "name": "...", "type": "..." } ] }`.
/// If JSON decoding fails, a constrained regex fallback is used.
/// Only lines accepted by the fallback must also match known instrument tokens.
public enum InstrumentParser {

    /// Known instrument tokens used by the regex fallback.
    public static let knownInstrumentPattern =
        #"i1|ColorMunki|Spyder|spectro|Display|Huey|DTP|SpectroScan|Smile|Klein"#

    /// Parse the complete `instlist` output.
    public static func parse(_ output: String) throws -> [InstrumentDevice] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let data = trimmed.data(using: .utf8),
           let decoded = try? decodeJSON(data) {
            return decoded
        }

        let regex = try? NSRegularExpression(
            pattern: #"^(\d+)[\s:=]+'?([^'\n]+)'?(?:\s+on\s+'?([^'\n]+)'?)?"#,
            options: [.caseInsensitive, .anchorsMatchLines]
        )
        var devices: [InstrumentDevice] = []
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex?.matches(in: trimmed, options: [], range: range) ?? []

        for match in matches {
            guard let portString = substring(trimmed, range: match.range(at: 1)),
                  let port = Int(portString), port > 0 else { continue }

            let name = substring(trimmed, range: match.range(at: 2))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let type = substring(trimmed, range: match.range(at: 3))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let combined = "\(name) \(type)".lowercased()
            guard combined.range(of: knownInstrumentPattern,
                                 options: [.regularExpression, .caseInsensitive]) != nil,
                  !name.isEmpty else { continue }

            devices.append(InstrumentDevice(port: port, name: name, type: type))
        }

        return devices
    }

    private static func decodeJSON(_ data: Data) throws -> [InstrumentDevice] {
        let output = try JSONDecoder().decode(InstlistOutput.self, from: data)
        return output.devices
    }

    private static func substring(_ source: String, range: NSRange) -> String? {
        guard range.location != NSNotFound, let r = Range(range, in: source) else { return nil }
        return String(source[r])
    }
}

private struct InstlistOutput: Decodable {
    let event: String
    let devices: [InstrumentDevice]
}
