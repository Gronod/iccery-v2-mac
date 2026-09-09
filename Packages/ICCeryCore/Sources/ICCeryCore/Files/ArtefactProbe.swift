import Foundation

/// Result of `verify_stage_artefacts(cwd, basename)` (docs/06).
public struct StageArtefacts: Sendable, Equatable {
    /// `<basename>.ti1` exists (Stage 1 done → unlocks Stage 2).
    public var stage1Complete = false
    /// `<basename>.ti2` exists (Stage 2 done → with ti1, unlocks Stage 3).
    public var stage2Complete = false
    /// `<basename>.ti3` exists (Stage 3 done → unlocks Stage 4).
    public var stage3Complete = false
    /// `.icc`/`.icm` exists (Stage 4 done → with ti3, unlocks Stage 5).
    public var stage4Complete = false
    /// Absolute path of the profile file when present.
    public var profilePath: URL?
    /// Absolute path of the `.gam` gamut mesh when present (issue #28).
    public var gamPath: URL?

    public init(
        stage1Complete: Bool = false,
        stage2Complete: Bool = false,
        stage3Complete: Bool = false,
        stage4Complete: Bool = false,
        profilePath: URL? = nil,
        gamPath: URL? = nil
    ) {
        self.stage1Complete = stage1Complete
        self.stage2Complete = stage2Complete
        self.stage3Complete = stage3Complete
        self.stage4Complete = stage4Complete
        self.profilePath = profilePath
        self.gamPath = gamPath
    }
}

/// Filesystem probing for wizard artefacts (docs/02 §Working directory,
/// docs/06 §Stages). All artefacts live next to each other in `cwd`.
public enum ArtefactProbe {

    /// `verify_stage_artefacts` — the gating truth source.
    public static func verify(
        basename: String,
        cwd: URL,
        fileManager: FileManager = .default
    ) -> StageArtefacts {
        var out = StageArtefacts()
        out.stage1Complete = exists(artefact(basename, "ti1", cwd), fm: fileManager)
        out.stage2Complete = exists(artefact(basename, "ti2", cwd), fm: fileManager)
        out.stage3Complete = exists(artefact(basename, "ti3", cwd), fm: fileManager)
        if let profile = resolveProfile(basename: basename, cwd: cwd, fileManager: fileManager) {
            out.stage4Complete = true
            out.profilePath = profile
            let gam = artefact(basename, "gam", cwd)
            if exists(gam, fm: fileManager) {
                out.gamPath = gam
            }
        }
        return out
    }

    /// `<cwd>/<basename>.<ext>` — the canonical artefact URL.
    public static func artefact(_ basename: String, _ ext: String, _ cwd: URL) -> URL {
        cwd.appendingPathComponent("\(basename).\(ext)", isDirectory: false)
    }

    /// Profile extension resolution (#69): existing `.icm` wins over
    /// `.icc`; when neither exists the macOS default is `.icc`.
    /// (`profcheck`/`iccgamut` swap extension when the requested path is
    /// missing.)
    public static func resolveProfile(
        basename: String,
        cwd: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let icm = artefact(basename, "icm", cwd)
        if exists(icm, fm: fileManager) { return icm }
        let icc = artefact(basename, "icc", cwd)
        if exists(icc, fm: fileManager) { return icc }
        return nil
    }

    /// Default extension for a *new* profile on macOS (#69).
    public static let defaultProfileExtension = "icc"

    /// Every artefact path for a basename: `.ti1 .ti2 .tif .N.tif
    /// .ti3 _passN.ti3 .icc .icm .gam` plus the `CAL_<basename>` namespace.
    /// Multi-page TIFFs match `<basename>.tif`, `<basename>.1.tif` … and
    /// `<basename>_NN.tif` (manifest naming).
    public static func existingArtefacts(
        basename: String,
        cwd: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: cwd,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let prefixes = [basename + ".", "CAL_" + basename + "."]
        let suffixes: Set<String> = ["ti1", "ti2", "tif", "ti3", "icc", "icm", "gam", "cal"]
        let passPrefix = basename + "_pass"
        let tifStemPrefix = basename + "_"
        let calPrefix = "CAL_" + basename

        return entries.filter { url in
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            guard suffixes.contains(ext) else { return false }
            if prefixes.contains(where: { name.hasPrefix($0) }) { return true }
            if name.hasPrefix(passPrefix), ext == "ti3" { return true }
            if name.hasPrefix(tifStemPrefix), ext == "tif" { return true }
            if name.hasPrefix(calPrefix) { return true }
            return false
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func exists(_ url: URL, fm: FileManager) -> Bool {
        fm.fileExists(atPath: url.path)
    }
}
