import Foundation

/// Policy when a JSON file exists but cannot be decoded.
public enum JSONCorruptPolicy: Sendable {
    /// Return `defaultValue` and leave the file untouched.
    case replaceWithDefault
    /// Throw the decode error. Callers must not overwrite the file.
    case throwCorrupt
}

/// Shared pretty-printed JSON file façade used by settings, wizard state,
/// and verification history.
public struct JSONFileStore<T: Codable & Sendable>: Sendable {
    public let fileURL: URL
    public let corrupt: JSONCorruptPolicy
    private let defaultValue: @Sendable () -> T
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL,
        corrupt: JSONCorruptPolicy,
        defaultValue: @escaping @Sendable () -> T,
        dateEncoding: JSONEncoder.DateEncodingStrategy = .deferredToDate,
        dateDecoding: JSONDecoder.DateDecodingStrategy = .deferredToDate
    ) {
        self.fileURL = fileURL
        self.corrupt = corrupt
        self.defaultValue = defaultValue
        self.encoder = JSONEncoder.icceryPretty(dateEncoding: dateEncoding)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecoding
        self.decoder = decoder
    }

    /// Encodes `value` with the shared pretty / sorted-keys encoder.
    public func encodePretty(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public func load() throws -> T {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return defaultValue()
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            switch corrupt {
            case .replaceWithDefault:
                return defaultValue()
            case .throwCorrupt:
                throw error
            }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            switch corrupt {
            case .replaceWithDefault:
                return defaultValue()
            case .throwCorrupt:
                throw error
            }
        }
    }

    public func save(_ value: T) throws {
        try AtomicFileWriter.write(try encodePretty(value), to: fileURL)
    }
}

extension JSONEncoder {
    /// Shared pretty-printed, sorted-keys encoder used by `JSONFileStore`
    /// and preset export.
    static func icceryPretty(
        dateEncoding: JSONEncoder.DateEncodingStrategy = .deferredToDate
    ) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = dateEncoding
        return encoder
    }
}
