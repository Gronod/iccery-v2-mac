import Foundation

/// Errors during `colprof` argv construction.
public enum ColprofArgError: LocalizedError, Equatable, Sendable {
    case invalidBasename(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBasename(let name):
            return "Invalid colprof basename: \(name)"
        }
    }
}

/// Pure argv builder for Argyll's `colprof` tool.
public enum ColprofArgs {

    /// Builds `colprof` argv per the Gronod fork protocol.
    ///
    /// Always `-v -a {algorithm} -q {quality}`. Optional flags are added
    /// only when their fields are non-empty and meaningful. `-f` has
    /// special handling for "none" (omit), "" (bare flag), and a custom
    /// `.sp` path (passed through). `-c`/`-d` viewing conditions are
    /// skipped when set to "none".
    public static func build(config: ColprofConfig) throws -> [String] {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.basename)

        var args: [String] = ["-v"]

        args.append(contentsOf: ["-a", config.algorithm])
        args.append(contentsOf: ["-q", config.quality])

        if let intent = config.intent?.trimmingCharacters(in: .whitespaces), !intent.isEmpty {
            args.append(contentsOf: ["-t", intent])
        }

        if let fwa = config.fwa?.trimmingCharacters(in: .whitespaces) {
            switch fwa.lowercased() {
            case "none", "":
                // "none" omits the flag; an explicit empty string means bare -f.
                if fwa.isEmpty {
                    args.append("-f")
                }
            default:
                args.append(contentsOf: ["-f", fwa])
            }
        }

        if let illuminant = config.illuminant?.trimmingCharacters(in: .whitespaces), !illuminant.isEmpty {
            args.append(contentsOf: ["-i", illuminant])
        }

        if let observer = config.observer?.trimmingCharacters(in: .whitespaces), !observer.isEmpty {
            args.append(contentsOf: ["-o", observer])
        }

        if let inputCond = config.inputViewingCond?.trimmingCharacters(in: .whitespaces),
           !inputCond.isEmpty, inputCond.lowercased() != "none" {
            args.append(contentsOf: ["-c", inputCond])
        }

        if let outputCond = config.outputViewingCond?.trimmingCharacters(in: .whitespaces),
           !outputCond.isEmpty, outputCond.lowercased() != "none" {
            args.append(contentsOf: ["-d", outputCond])
        }

        let profileDescription = config.description?.trimmingCharacters(in: .whitespaces)
        if let description = profileDescription, !description.isEmpty {
            args.append(contentsOf: ["-D", description])
        }

        if let copyright = config.copyright?.trimmingCharacters(in: .whitespaces), !copyright.isEmpty {
            args.append(contentsOf: ["-C", copyright])
        }

        args.append(cleanBasename)
        return args
    }
}
