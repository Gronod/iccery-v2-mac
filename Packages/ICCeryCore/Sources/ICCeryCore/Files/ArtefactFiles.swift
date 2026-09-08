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

    /// `get_app_info` — version + build for the About dialog.
    public static func appInfo(
        bundle: Bundle = .main
    ) -> (version: String, build: String) {
        let info = bundle.infoDictionary ?? [:]
        return (
            info["CFBundleShortVersionString"] as? String ?? "0.0.0",
            info["CFBundleVersion"] as? String ?? "0"
        )
    }
}
