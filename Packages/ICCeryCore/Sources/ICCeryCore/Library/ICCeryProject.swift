import Foundation

/// The `.icceryproj` file — a JSON **index** over a basename + working
/// directory + optional media recipe/preset binding + last verification
/// snapshot (issue #149, docs/06 §Project file).
///
/// The project is never a second source of truth: artefact gating stays
/// on disk (`ArtefactProbe`), and `wizard_state.json` continues to
/// persist the live session. snake_case keys match the v1 schema;
/// `schema_version != 1` is a hard decode error — v2 fields are never
/// partially decoded.
public struct ICCeryProject: Codable, Equatable, Sendable {

    /// The only schema version this build reads and writes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var name: String
    public var notes: String
    /// Run name without extension — never `CAL_`-persisted (#60/R11).
    public var basename: String
    /// Absolute working directory holding the artefacts (#59).
    public var cwd: String
    /// May differ from `basename` after a `.ti3` import (#94).
    public var profileBasename: String?
    /// CUPS queue id, when a printer was selected.
    public var printerID: String?
    public var printerDisplayName: String?
    /// `MediaRecipe.id` — optional; ignored when the library file is
    /// absent or the id is unknown (soft-dependency, #146).
    public var mediaRecipeID: String?
    public var presetID: String?
    /// Absolute `.cal` path stored verbatim; `nil` = none.
    public var calibrationURL: String?
    public var lastVerification: VerificationSnapshot?
    public var updated: Date

    public init(
        schemaVersion: Int = ICCeryProject.currentSchemaVersion,
        name: String = "",
        notes: String = "",
        basename: String,
        cwd: String,
        profileBasename: String? = nil,
        printerID: String? = nil,
        printerDisplayName: String? = nil,
        mediaRecipeID: String? = nil,
        presetID: String? = nil,
        calibrationURL: String? = nil,
        lastVerification: VerificationSnapshot? = nil,
        updated: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.notes = notes
        self.basename = basename
        self.cwd = cwd
        self.profileBasename = profileBasename
        self.printerID = printerID
        self.printerDisplayName = printerDisplayName
        self.mediaRecipeID = mediaRecipeID
        self.presetID = presetID
        self.calibrationURL = calibrationURL
        self.lastVerification = lastVerification
        self.updated = updated
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case name, notes, basename, cwd
        case profileBasename = "profile_basename"
        case printerID = "printer_id"
        case printerDisplayName = "printer_display_name"
        case mediaRecipeID = "media_recipe_id"
        case presetID = "preset_id"
        case calibrationURL = "calibration_url"
        case lastVerification = "last_verification"
        case updated
    }

    /// Strict decode: `schema_version` is required and must equal 1 —
    /// anything else throws before a single v2 field is read. Required
    /// strings (`basename`, `cwd`) must be present; optionals default.
    /// Unknown keys are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version == ICCeryProject.currentSchemaVersion else {
            throw ValidationError.unsupportedSchema(version)
        }
        schemaVersion = version
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        basename = try c.decode(String.self, forKey: .basename)
        cwd = try c.decode(String.self, forKey: .cwd)
        profileBasename = try c.decodeIfPresent(String.self, forKey: .profileBasename)
        printerID = try c.decodeIfPresent(String.self, forKey: .printerID)
        printerDisplayName = try c.decodeIfPresent(String.self, forKey: .printerDisplayName)
        mediaRecipeID = try c.decodeIfPresent(String.self, forKey: .mediaRecipeID)
        presetID = try c.decodeIfPresent(String.self, forKey: .presetID)
        calibrationURL = try c.decodeIfPresent(String.self, forKey: .calibrationURL)
        lastVerification = try c.decodeIfPresent(VerificationSnapshot.self, forKey: .lastVerification)
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? Date()
    }

    public enum ValidationError: LocalizedError, Equatable {
        case unsupportedSchema(Int)
        case emptyBasename
        case invalidBasename(String)
        case emptyCwd
        case unsafeCwd(String)
        case invalidCalibrationURL(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedSchema:
                return "This project file is not schema 1."
            case .emptyBasename:
                return "A project needs a target basename."
            case .invalidBasename(let v):
                return "Illegal project basename \"\(v)\"."
            case .emptyCwd:
                return "A project needs a working folder."
            case .unsafeCwd(let v):
                return "cwd must be an absolute path, got \"\(v)\"."
            case .invalidCalibrationURL(let v):
                return "calibration_url must be an absolute path without \"..\" or NUL, got \"\(v)\"."
            }
        }
    }

    /// Validates the index fields. Empty basename/cwd refuse (#59/#60);
    /// basename still rejects `/`, `\`, `..`; cwd must be absolute. An
    /// empty `name` falls back to the basename.
    @discardableResult
    public func validated() throws -> ICCeryProject {
        var p = self
        p.basename = basename.trimmingCharacters(in: .whitespacesAndNewlines)
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.basename.isEmpty else { throw ValidationError.emptyBasename }
        guard PathSecurity.isValidBasename(p.basename) else {
            throw ValidationError.invalidBasename(p.basename)
        }
        let trimmedCwd = p.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCwd.isEmpty else { throw ValidationError.emptyCwd }
        guard trimmedCwd.hasPrefix("/"), !trimmedCwd.contains("\0") else {
            throw ValidationError.unsafeCwd(p.cwd)
        }
        p.cwd = trimmedCwd
        if p.name.isEmpty { p.name = p.basename }
        if let cal = p.calibrationURL, !cal.isEmpty {
            guard cal.hasPrefix("/"), !cal.contains(".."), !cal.contains("\0") else {
                throw ValidationError.invalidCalibrationURL(cal)
            }
        }
        return p
    }

    /// Reads a `.icceryproj` file. Throws `unsupportedSchema` for
    /// `schema_version != 1` and the decode/validation error otherwise;
    /// callers must leave live state untouched on failure.
    public static func load(from url: URL) throws -> ICCeryProject {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ICCeryProject.self, from: data).validated()
    }

    /// Atomic `.tmp` + rename write via `AtomicFileWriter` (#213).
    /// Validation runs first — a refused project never touches disk.
    public func save(to url: URL) throws {
        let encoder = JSONEncoder.icceryPretty(dateEncoding: .iso8601)
        try AtomicFileWriter.write(try encoder.encode(validated()), to: url)
    }
}

/// The last `VerificationRecord` frozen into the project file — notes
/// only, never gating truth.
public struct VerificationSnapshot: Codable, Equatable, Sendable {
    public var date: Date
    public var avgDE00: Double
    public var maxDE00: Double
    /// `VerificationStatus.rawValue`.
    public var status: String
    public var profileFilename: String

    public init(
        date: Date,
        avgDE00: Double,
        maxDE00: Double,
        status: String,
        profileFilename: String
    ) {
        self.date = date
        self.avgDE00 = avgDE00
        self.maxDE00 = maxDE00
        self.status = status
        self.profileFilename = profileFilename
    }

    public init(record: VerificationRecord) {
        self.init(
            date: record.timestamp,
            avgDE00: record.avgDE,
            maxDE00: record.maxDE,
            status: record.status.rawValue,
            profileFilename: record.profileName
        )
    }

    enum CodingKeys: String, CodingKey {
        case date
        case avgDE00 = "avg_de00"
        case maxDE00 = "max_de00"
        case status
        case profileFilename = "profile_filename"
    }
}
