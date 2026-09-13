import Foundation

/// `Save Report…` — a one-page UTF-8 Markdown summary written next to
/// the artefacts as `{basename}-report.md` (issue #149). Generated
/// output, safe to overwrite. Filenames only — never absolute paths —
/// and no HTML.
public enum ProjectReport {

    /// `{cwd}/{basename}-report.md`.
    public static func url(for project: ICCeryProject) -> URL {
        URL(fileURLWithPath: project.cwd, isDirectory: true)
            .appendingPathComponent("\(project.basename)-report.md")
    }

    /// Renders the report. `artefacts` is the live probe result so the
    /// checklist shows what is actually on disk, not what the project
    /// JSON claims (R18).
    public static func markdown(
        project: ICCeryProject,
        recipeName: String?,
        artefacts: StageArtefacts
    ) -> String {
        var lines: [String] = []
        lines.append("# \(project.name)")
        lines.append("")
        if let printer = project.printerDisplayName ?? project.printerID,
           !printer.isEmpty {
            lines.append("- **Printer:** \(printer)")
        }
        if let recipeName, !recipeName.isEmpty {
            lines.append("- **Media recipe:** \(recipeName)")
        }
        if let preset = project.presetID, !preset.isEmpty {
            lines.append("- **Preset:** \(preset)")
        }
        lines.append("")

        lines.append("## Artefacts")
        lines.append("")
        lines.append("| File | Status |")
        lines.append("|------|--------|")
        lines.append(row("\(project.basename).ti1", exists: artefacts.stage1Complete))
        lines.append(row("\(project.basename).ti2", exists: artefacts.stage2Complete))
        lines.append(row("\(project.basename).ti3", exists: artefacts.stage3Complete))
        let profileName = artefacts.profilePath?.lastPathComponent
            ?? "\(project.basename).\(ArtefactProbe.defaultProfileExtension)"
        lines.append(row(profileName, exists: artefacts.stage4Complete))
        if let gam = artefacts.gamPath {
            lines.append(row(gam.lastPathComponent, exists: true))
        }
        lines.append("")

        if let verification = project.lastVerification {
            lines.append("## Last verification")
            lines.append("")
            lines.append(
                "- avg ΔE₀₀ \(f(verification.avgDE00)), max ΔE₀₀ \(f(verification.maxDE00))"
                    + " (\(verification.status))")
            lines.append("- Profile: \(verification.profileFilename)")
            lines.append("- Date: \(ISO8601DateFormatter().string(from: verification.date))")
            lines.append("")
        }

        if !project.notes.isEmpty {
            lines.append("## Notes")
            lines.append("")
            lines.append(project.notes)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes `{cwd}/{basename}-report.md` atomically, overwriting an
    /// existing generated report.
    @discardableResult
    public static func write(
        project: ICCeryProject,
        recipeName: String?,
        artefacts: StageArtefacts
    ) throws -> URL {
        let destination = url(for: project)
        try AtomicFileWriter.write(
            markdown(project: project, recipeName: recipeName, artefacts: artefacts),
            to: destination)
        return destination
    }

    private static func row(_ filename: String, exists: Bool) -> String {
        "| \(filename) | \(exists ? "exists" : "missing") |"
    }

    private static func f(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
