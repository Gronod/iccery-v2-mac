import Foundation

/// Resolves Argyll sidecar binaries (docs/04 §0.1 `resolve_binary`).
///
/// Order:
/// 1. Settings `argyll_binary_dir` override — only if `<dir>/<name>`
///    exists there.
/// 2. Bundled `<bundle>/Resources/Argyll/<platform>/<name>`.
///    On macOS, `macos-universal` wins whenever it contains the `instlist`
///    marker; otherwise `macos-arm64` / `macos-x86_64` by host arch.
/// 3. If nothing exists the *constructed* bundled path is still returned
///    — a missing binary surfaces later as `process:error` on spawn,
///    matching v1 semantics.
public struct BinaryResolver: Sendable {

    /// Root that contains the platform dirs — `Bundle.resource/Argyll` in
    /// the app, a fixture dir in tests.
    public let bundledRoot: URL
    /// `settings.argyll_binary_dir`, already expanded to a URL.
    public let overrideDir: URL?
    /// Host architecture directory names, universal preferred.
    public let archDirs: [String]

    public init(
        bundledRoot: URL = AppPaths.bundledArgyllDir,
        overrideDir: URL? = nil,
        archDirs: [String]? = nil
    ) {
        self.bundledRoot = bundledRoot
        self.overrideDir = overrideDir
        #if arch(arm64)
        let fallback = ["macos-arm64", "macos-aarch64"]
        #else
        let fallback = ["macos-x86_64"]
        #endif
        self.archDirs = archDirs ?? ["macos-universal"] + fallback
    }

    /// Marker used to decide whether `macos-universal` is usable.
    public static let markerBinary = "instlist"

    /// Resolves a tool name to an absolute URL (never throws — see type
    /// docs). `name` is the bare tool name, e.g. `"targen"`.
    public func resolve(_ name: String) -> URL {
        let fm = FileManager.default

        if let dir = overrideDir {
            let candidate = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return bundledRoot
            .appendingPathComponent(platformDir(), isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
    }

    /// The bundled platform directory that resolution will use.
    public func platformDir() -> String {
        let fm = FileManager.default
        let universal = bundledRoot.appendingPathComponent("macos-universal")
        if fm.fileExists(
            atPath: universal.appendingPathComponent(Self.markerBinary).path
        ) {
            return "macos-universal"
        }
        for dir in archDirs where dir != "macos-universal" {
            if fm.fileExists(
                atPath: bundledRoot
                    .appendingPathComponent(dir)
                    .appendingPathComponent(Self.markerBinary).path
            ) {
                return dir
            }
        }
        // Nothing present — still return the preferred dir so the error
        // message points at where the user should drop binaries.
        return archDirs.first ?? "macos-universal"
    }

    /// Bundled mock tool (tracked in git under `Resources/Argyll/mocks/`).
    public func mock(_ name: String) -> URL {
        bundledRoot
            .appendingPathComponent("mocks", isDirectory: true)
            .appendingPathComponent("\(name).mock", isDirectory: false)
    }

    /// Bundled reference gamut (`Resources/Argyll/reference_gamuts/`).
    public func referenceGamut(_ name: String) -> URL {
        let stem = name.hasSuffix(".gam") ? name : "\(name).gam"
        return bundledRoot
            .appendingPathComponent("reference_gamuts", isDirectory: true)
            .appendingPathComponent(stem, isDirectory: false)
    }

    /// Whether the resolved path exists and is executable.
    public func exists(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}
