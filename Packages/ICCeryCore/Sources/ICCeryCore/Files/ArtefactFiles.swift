import Foundation

/// Small host-side file helpers (issue #6).
public enum ArtefactFiles {

    /// `get_default_working_dir` — `resolveSafeCwd(nil)`.
    public static func defaultWorkingDirectory() -> URL {
        PathSecurity.resolveSafeCwd(nil)
    }

    /// `read_file_base64` — for **text artefacts** the UI needs verbatim
    /// (ti1/ti2 previews, CGATS datasets, logs). Binary payloads (TIFF)
    /// go through `TiffPreview` instead.
    public static func readBase64(_ url: URL) throws -> String {
        try Data(contentsOf: url).base64EncodedString()
    }

    /// `get_app_info` — version, build, and build date for the About dialog.
    public static func appInfo(
        bundle: Bundle = .main
    ) -> (version: String, build: String, buildDate: String) {
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info["CFBundleVersion"] as? String ?? "0"

        let url = bundle.executableURL ?? bundle.bundleURL
        let buildDate: String
        if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
           let date = values.contentModificationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            buildDate = formatter.string(from: date)
        } else {
            buildDate = "Unknown"
        }

        return (version, build, buildDate)
    }
}
