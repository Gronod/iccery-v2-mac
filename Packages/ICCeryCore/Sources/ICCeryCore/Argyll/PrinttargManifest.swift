import Foundation

/// One page of a `printtarg -u` manifest (docs/05 §2.3).
/// `patches` is a page-assigned count including TID/padding cells,
/// not strictly user patches.
public struct PrinttargPage: Codable, Equatable, Sendable {
    public var filename: String
    public var patches: Int
    public var widthMm: Double
    public var heightMm: Double

    public init(filename: String, patches: Int, widthMm: Double, heightMm: Double) {
        self.filename = filename
        self.patches = patches
        self.widthMm = widthMm
        self.heightMm = heightMm
    }

    enum CodingKeys: String, CodingKey {
        case filename, patches
        case widthMm = "width_mm"
        case heightMm = "height_mm"
    }
}

/// The final-only, pretty-printed, **unprefixed** JSON object emitted
/// by fork `printtarg -u` after all pages are written (docs/05 §2.3).
public struct PrinttargManifest: Codable, Equatable, Sendable {
    public var event: String
    public var pages: [PrinttargPage]

    public init(event: String = "manifest", pages: [PrinttargPage]) {
        self.event = event
        self.pages = pages
    }
}

/// A manifest page resolved against the working directory, with its
/// host-side PNG preview (#58 — TIFF is never fed to the UI directly).
public struct GalleryPage: Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let page: PrinttargPage
    public let fileURL: URL
    public let previewPNG: Data?
    public let previewError: String?

    public init(index: Int, page: PrinttargPage, fileURL: URL, previewPNG: Data?, previewError: String?) {
        self.index = index
        self.page = page
        self.fileURL = fileURL
        self.previewPNG = previewPNG
        self.previewError = previewError
    }
}

public enum ManifestError: LocalizedError, Equatable {
    case noJSONDocument
    case wrongEvent(String)
    case decodeFailed(String)
    case invalidPage(String)

    public var errorDescription: String? {
        switch self {
        case .noJSONDocument:
            return "No JSON document found in printtarg stdout."
        case .wrongEvent(let event):
            return "Unexpected JSON event \"\(event)\" — expected \"manifest\"."
        case .decodeFailed(let reason):
            return "printtarg manifest JSON failed to decode: \(reason)"
        case .invalidPage(let reason):
            return "printtarg manifest page is invalid: \(reason)"
        }
    }
}

/// Extracts and decodes the `printtarg -u` manifest from the complete
/// accumulated stdout (docs/04 §2.3, docs/09 §JSON manifest).
///
/// #68 invariant: the JSON is a structured document, not a brace-hunt.
/// Extraction is string/escape-aware — a `{` or `}` inside a quoted
/// filename can never corrupt the scan — and starts only at a `{` that
/// begins a trimmed stdout line.
public enum PrinttargManifestExtractor {

    /// Finds the manifest object in accumulated stdout.
    public static func manifest(from stdout: String) throws -> PrinttargManifest {
        for block in jsonObjects(in: stdout) {
            let data = Data(block.utf8)
            guard let manifest = try? JSONDecoder().decode(PrinttargManifest.self, from: data) else {
                continue
            }
            guard manifest.event == "manifest" else {
                throw ManifestError.wrongEvent(manifest.event)
            }
            try validate(manifest)
            return manifest
        }
        if let first = jsonObjects(in: stdout).first,
           let obj = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any],
           let event = obj["event"] as? String {
            throw ManifestError.wrongEvent(event)
        }
        throw ManifestError.noJSONDocument
    }

    private static func validate(_ manifest: PrinttargManifest) throws {
        for page in manifest.pages {
            guard page.patches >= 0 else {
                throw ManifestError.invalidPage("negative patch count \(page.patches)")
            }
            guard page.widthMm > 0, page.heightMm > 0 else {
                throw ManifestError.invalidPage("non-positive page size \(page.widthMm)x\(page.heightMm)")
            }
            let name = page.filename
            guard !name.isEmpty,
                  !name.hasPrefix("/"),
                  !name.contains("/"),
                  !name.contains("\\"),
                  !name.contains("..") else {
                throw ManifestError.invalidPage("unsafe filename \"\(name)\"")
            }
            let ext = (name as NSString).pathExtension.lowercased()
            guard ext == "tif" || ext == "tiff" else {
                throw ManifestError.invalidPage("non-TIFF filename \"\(name)\"")
            }
        }
    }

    /// Yields every complete top-level JSON object `{...}` found at a
    /// trimmed line boundary, in document order. Depth tracking respects
    /// quoted strings and backslash escapes.
    static func jsonObjects(in text: String) -> [String] {
        var out: [String] = []
        let scalars = Array(text.unicodeScalars)
        var i = 0

        func isLineStart(_ idx: Int) -> Bool {
            var j = idx - 1
            while j >= 0 && scalars[j] != "\n" {
                if scalars[j] != " " && scalars[j] != "\t" && scalars[j] != "\r" {
                    return false
                }
                j -= 1
            }
            return true
        }

        while i < scalars.count {
            if scalars[i] == "{", isLineStart(i) {
                var depth = 0
                var inString = false
                var escaped = false
                var j = i
                while j < scalars.count {
                    let c = scalars[j]
                    if inString {
                        if escaped { escaped = false }
                        else if c == "\\" { escaped = true }
                        else if c == "\"" { inString = false }
                    } else {
                        if c == "\"" { inString = true }
                        else if c == "{" { depth += 1 }
                        else if c == "}" {
                            depth -= 1
                            if depth == 0 {
                                out.append(String(String.UnicodeScalarView(scalars[i...j])))
                                i = j
                                break
                            }
                        }
                    }
                    j += 1
                }
            }
            i += 1
        }
        return out
    }
}
