import Foundation

/// Configuration for a `spotread` invocation (issue #148).
///
/// `spotread` writes no artefact; `workingDirectory` is still required
/// for the spawn (#59 — empty cwd is illegal).
public struct SpotReadConfig: Codable, Equatable, Sendable {
    public var workingDirectory: URL?
    /// Communication port for `spotread -c`.
    /// `nil` means omit `-c` (Auto or port 1, #111). Never an array index.
    public var selectedPort: Int?
    /// Enable i1Pro 2 visual LEDs (`-Y l`, #204).
    public var enableLEDs: Bool
    /// Whether the selected instrument is an XY table — controls the
    /// `q\n` + ~500 ms park before kill on cancel.
    public var isXY: Bool
    /// Display name stamped onto each `SpotReadSample`.
    public var instrumentName: String
    /// Instrument port stamped onto each sample (nil for Auto).
    public var instrumentPort: Int?

    public init(
        workingDirectory: URL? = nil,
        selectedPort: Int? = nil,
        enableLEDs: Bool = false,
        isXY: Bool = false,
        instrumentName: String = "",
        instrumentPort: Int? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.selectedPort = selectedPort
        self.enableLEDs = enableLEDs
        self.isXY = isXY
        self.instrumentName = instrumentName
        self.instrumentPort = instrumentPort
    }
}
