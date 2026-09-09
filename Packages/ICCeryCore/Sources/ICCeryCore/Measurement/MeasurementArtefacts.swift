import Foundation

/// Errors from pass-snapshot, promote, and discovery operations.
public enum MeasurementArtefactError: LocalizedError, Equatable, Sendable {
    case invalidBasename(String)
    case canonicalMissing(URL)
    case snapshotFailed(String)
    case promoteFailed(String)
    case noPassFiles

    public var errorDescription: String? {
        switch self {
        case .invalidBasename(let name):
            return "Invalid measurement basename: \(name)"
        case .canonicalMissing(let url):
            return "Canonical .ti3 not found: \(url.path)"
        case .snapshotFailed(let reason):
            return "Snapshot failed: \(reason)"
        case .promoteFailed(let reason):
            return "Promote failed: \(reason)"
        case .noPassFiles:
            return "No pass .ti3 snapshots are available."
        }
    }
}

/// Filesystem helpers for multi-pass measurement artefacts.
///
/// Pass snapshots use 1-based numbering and are tracked as
/// `<basename>_passN.ti3`. Canonical `<basename>.ti3` only appears after
/// Finish / Average (docs/24 #109, #110).
public enum MeasurementArtefacts {

    /// Find all existing pass snapshots in `cwd`, sorted numerically.
    public static func passSnapshots(
        basename: String,
        cwd: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: cwd,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let prefix = "\(basename)_pass"
        let suffix = "ti3"

        let passes: [(Int, URL)] = entries.compactMap { url in
            let name = url.lastPathComponent
            guard url.pathExtension.lowercased() == suffix,
                  name.hasPrefix(prefix)
            else { return nil }

            let numberPart = String(name.dropFirst(prefix.count).dropLast(4))
            guard let number = Int(numberPart), number > 0 else { return nil }
            return (number, url)
        }

        return passes
            .sorted { $0.0 < $1.0 }
            .map { $0.1 }
    }

    /// The next 1-based pass number.
    public static func nextPassNumber(
        basename: String,
        cwd: URL,
        fileManager: FileManager = .default
    ) -> Int {
        let existing = passSnapshots(basename: basename, cwd: cwd, fileManager: fileManager)
        guard let last = existing.last else { return 1 }
        let name = last.lastPathComponent
        let prefix = "\(basename)_pass"
        let numberPart = String(name.dropFirst(prefix.count).dropLast(4))
        return (Int(numberPart) ?? 0) + 1
    }

    /// Snapshot canonical `<basename>.ti3` to `<basename>_passN.ti3` and remove canonical.
    ///
    /// The copy is written to a temp sibling and atomically renamed before canonical is deleted.
    public static func snapshotPass(
        basename: String,
        cwd: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let cleanBasename = try PathSecurity.sanitizeBasename(basename)
        let canonical = cwd.appendingPathComponent("\(cleanBasename).ti3")
        guard fileManager.fileExists(atPath: canonical.path) else {
            throw MeasurementArtefactError.canonicalMissing(canonical)
        }

        let passNumber = nextPassNumber(basename: cleanBasename, cwd: cwd, fileManager: fileManager)
        let pass = cwd.appendingPathComponent("\(cleanBasename)_pass\(passNumber).ti3")
        let temp = cwd.appendingPathComponent(".\(cleanBasename)_pass\(passNumber).ti3.iccery-snap.tmp")

        if fileManager.fileExists(atPath: temp.path) {
            try? fileManager.removeItem(at: temp)
        }

        do {
            try fileManager.copyItem(at: canonical, to: temp)
        } catch {
            throw MeasurementArtefactError.snapshotFailed(error.localizedDescription)
        }

        if fileManager.fileExists(atPath: pass.path) {
            try? fileManager.removeItem(at: pass)
        }

        do {
            try fileManager.moveItem(at: temp, to: pass)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw MeasurementArtefactError.snapshotFailed(error.localizedDescription)
        }

        do {
            try fileManager.removeItem(at: canonical)
        } catch {
            // The pass file is durable; canonical removal failure is logged but not fatal.
            throw MeasurementArtefactError.snapshotFailed(error.localizedDescription)
        }

        return pass
    }

    /// Promote a single pass snapshot to canonical `<basename>.ti3`.
    public static func promotePass(
        pass: URL,
        basename: String,
        cwd: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let cleanBasename = try PathSecurity.sanitizeBasename(basename)
        let canonical = cwd.appendingPathComponent("\(cleanBasename).ti3")
        let temp = cwd.appendingPathComponent(".\(cleanBasename).ti3.iccery-promo.tmp")

        guard fileManager.fileExists(atPath: pass.path) else {
            throw MeasurementArtefactError.noPassFiles
        }

        if fileManager.fileExists(atPath: temp.path) {
            try? fileManager.removeItem(at: temp)
        }

        do {
            try fileManager.copyItem(at: pass, to: temp)
        } catch {
            throw MeasurementArtefactError.promoteFailed(error.localizedDescription)
        }

        if fileManager.fileExists(atPath: canonical.path) {
            try? fileManager.removeItem(at: canonical)
        }

        do {
            try fileManager.moveItem(at: temp, to: canonical)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw MeasurementArtefactError.promoteFailed(error.localizedDescription)
        }

        return canonical
    }

    /// Canonical `<basename>.ti3` URL, regardless of existence.
    public static func canonicalURL(basename: String, cwd: URL) throws -> URL {
        let cleanBasename = try PathSecurity.sanitizeBasename(basename)
        return cwd.appendingPathComponent("\(cleanBasename).ti3")
    }
}
