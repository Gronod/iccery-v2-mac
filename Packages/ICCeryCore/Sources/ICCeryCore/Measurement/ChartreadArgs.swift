import Foundation

/// Pure argv builder for Argyll's `chartread` tool.
public enum ChartreadArgs {

    /// Builds `chartread` argv per the Gronod fork protocol.
    ///
    /// - Always `-v -u`.
    /// - `-c N` is emitted only for `selectedPort != nil` and `N > 1`.
    /// - `-Y l` is emitted only when `enableLEDs` is `true`.
    /// - Basename is the last positional argument and is sanitized.
    public static func build(config: ChartreadConfig) throws -> [String] {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.basename)

        var args: [String] = ["-v", "-u"]

        if let port = config.selectedPort, port > 1 {
            args.append(contentsOf: ["-c", "\(port)"])
        }

        if config.enableLEDs {
            args.append(contentsOf: ["-Y", "l"])
        }

        args.append(cleanBasename)
        return args
    }
}
