import Foundation

/// Atomic `.tmp`-then-rename file writes — the convention used by
/// settings.json, verification_history.json and wizard_state.json
/// (docs/02 §Persistence, #213).
public enum AtomicFileWriter {

    /// Writes `data` to `url` atomically: sibling `<name>.tmp`, then a
    /// rename (which is atomic on APFS/HFS+). Parent dirs are created.
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: [])
            // replaceItemAt handles same-volume atomic swap and removes
            // the destination cleanly; fall back to remove+move.
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    public static func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }
}
