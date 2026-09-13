import SwiftUI
import ICCeryCore

/// File-menu commands for the project file (issue #149). Content of the
/// `CommandGroup(replacing: .newItem)` in `ICCeryApp` — split out so the
/// app body stays small (type-checker budget). Menu ids are distinct
/// from the sidebar chip ids (`menuProject*` vs `btnProject*`).
struct ProjectCommands: View {
    @ObservedObject private var project: ProjectSession

    init(workflow: TargetWorkflowViewModel) {
        self._project = ObservedObject(wrappedValue: workflow.project)
    }

    var body: some View {
        Button("New Project") { project.requestNew() }
            .keyboardShortcut("n")
            .accessibilityIdentifier("menuProjectNew")
        Button("Open Project…") { project.requestOpen() }
            .keyboardShortcut("o")
            .accessibilityIdentifier("menuProjectOpen")
        Menu("Open Recent") {
            ForEach(project.recents) { entry in
                // Names render via Text only (#114); never the raw path.
                Button(entry.name) { project.openRecent(entry) }
                    .accessibilityIdentifier("projectRecent-\(entry.bookmarkHash)")
            }
            Divider()
            Button("Clear Menu") { project.clearRecents() }
                .accessibilityIdentifier("menuProjectRecentsClear")
        }
        .disabled(project.recents.isEmpty)
        .accessibilityIdentifier("menuProjectRecents")
        Divider()
        Button("Save Project") { project.saveProject() }
            .keyboardShortcut("s")
            .disabled(!project.canSave)
            .accessibilityIdentifier("menuProjectSave")
        Button("Save Project As…") { project.saveProjectAs() }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!project.canSaveAs)
            .accessibilityIdentifier("menuProjectSaveAs")
        Button("Save Report…") { project.saveReport() }
            .disabled(!project.canReport)
            .accessibilityIdentifier("menuProjectReport")
        Divider()
        Button("Close Project") { project.requestClose() }
            .disabled(!project.isBound)
            .accessibilityIdentifier("menuProjectClose")
    }
}

/// Compact project footer at the bottom of the 270 pt sidebar (issue
/// #149) — never a fourth row of large buttons (R10).
struct ProjectChip: View {
    @ObservedObject var project: ProjectSession
    @Binding var showingAllHelp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let bound = project.project {
                Text(bound.name)
                    .font(.callout)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .accessibilityIdentifier("projectChipName")
                Text(URL(fileURLWithPath: bound.cwd).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // The raw path is a tooltip — never the window title.
                    .help(bound.cwd)
                    .accessibilityIdentifier("projectChipPath")
                if project.diskBehindNotes {
                    Text("Disk behind project notes")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("projectChipStale")
                }
                HStack(spacing: 8) {
                    Button("Show in Finder") { project.revealInFinder() }
                        .accessibilityIdentifier("btnProjectReveal")
                    Button("Save") { project.saveProject() }
                        .disabled(!project.canSave)
                        .accessibilityIdentifier("btnProjectSave")
                    Spacer()
                }
                .font(.caption)
                .controlSize(.small)
            } else {
                HStack(spacing: 8) {
                    Text("No project")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("projectChipName")
                    Spacer()
                    Button("Open…") { project.requestOpen() }
                        .controlSize(.small)
                        .accessibilityIdentifier("btnProjectOpen")
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerMedium)
                .stroke(Theme.border)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectChip")
        .helpOverlay(
            "A project remembers printer, preset and folder. The stepper still follows files on disk.",
            showing: $showingAllHelp)
    }
}

/// `projectRelocateSheet` — shown when an opened project's `cwd` no
/// longer exists (issue #149). Choosing a folder rewrites `cwd` in the
/// project file atomically, then continues Apply; Cancel aborts the
/// open with live state untouched.
struct ProjectRelocateSheet: View {
    @ObservedObject var project: ProjectSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Missing project folder")
                .font(.title3)
                .foregroundStyle(Theme.text)
            Text(
                "The folder for \(project.pendingRelocate?.project.name ?? "this project") is missing. Choose a new working folder."
            )
            .foregroundStyle(Theme.text)
            HStack {
                Spacer()
                Button("Cancel") { project.cancelRelocate() }
                    .accessibilityIdentifier("btnProjectRelocateCancel")
                Button("Choose Folder…") { project.chooseRelocateFolder() }
                    .accessibilityIdentifier("btnProjectRelocate")
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectRelocateSheet")
    }
}
