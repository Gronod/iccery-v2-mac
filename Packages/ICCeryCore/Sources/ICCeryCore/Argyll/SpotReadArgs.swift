import Foundation

/// Pure argv builder for Argyll's `spotread` tool (issue #148).
public enum SpotReadArgs {

    /// Builds `spotread` argv per the Gronod fork protocol.
    ///
    /// - Always `-v -e` (paper / reflective; never display `-d`).
    /// - `-c N` is emitted only for `selectedPort != nil` and `N > 1`
    ///   (Auto and port 1 omit it, #111).
    /// - `-Y l` (letter L) is emitted only when `enableLEDs` is `true` (#204).
    /// - Never `-u`: the v2.0 `-u` policy covers printtarg + chartread +
    ///   profcheck only.
    /// - No basename — `spotread` writes no artefact.
    public static func build(config: SpotReadConfig) -> [String] {
        var args: [String] = ["-v", "-e"]

        if let port = config.selectedPort, port > 1 {
            args.append(contentsOf: ["-c", "\(port)"])
        }

        if config.enableLEDs {
            args.append(contentsOf: ["-Y", "l"])
        }

        return args
    }
}
