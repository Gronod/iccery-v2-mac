import Foundation

/// Errors during `average` argv construction.
public enum AverageArgError: LocalizedError, Equatable, Sendable {
    case invalidBasename(String)
    case invalidPassCount(Int)
    case outputCollidesWithInput
    case pathOutsideCwd(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidBasename(let name):
            return "Invalid basename for average: \(name)"
        case .invalidPassCount(let count):
            return "Average requires at least 2 pass files, got \(count)"
        case .outputCollidesWithInput:
            return "Average output filename collides with one of the inputs"
        case .pathOutsideCwd(let url):
            return "Pass or output file is outside the working directory: \(url.path)"
        }
    }
}

/// Configuration for an `average` run.
public struct AverageConfig: Sendable, Equatable {
    public let workingDirectory: URL
    public let basename: String
    public let passFiles: [URL]

    public init(
        workingDirectory: URL,
        basename: String,
        passFiles: [URL]
    ) {
        self.workingDirectory = workingDirectory
        self.basename = basename
        self.passFiles = passFiles
    }
}

/// Pure argv builder for Argyll's `average` tool.
public enum AverageArgs {

    /// Builds `average -v pass1 pass2 ... basename.ti3` with relative names.
    public static func build(config: AverageConfig) throws -> [String] {
        let cleanBasename = try PathSecurity.sanitizeBasename(config.basename)

        guard config.passFiles.count >= 2 else {
            throw AverageArgError.invalidPassCount(config.passFiles.count)
        }

        let output = config.workingDirectory
            .appendingPathComponent("\(cleanBasename).ti3")

        var inputNames: [String] = []
        for url in config.passFiles {
            try validate(url, isIn: config.workingDirectory)
            inputNames.append(url.lastPathComponent)
        }

        try validate(output, isIn: config.workingDirectory)
        let outputName = output.lastPathComponent

        guard !inputNames.contains(outputName) else {
            throw AverageArgError.outputCollidesWithInput
        }

        return ["-v"] + inputNames + [outputName]
    }

    private static func validate(_ url: URL, isIn cwd: URL) throws {
        let cwdPath = cwd.standardizedFileURL.path
        let urlPath = url.deletingLastPathComponent().standardizedFileURL.path
        guard urlPath == cwdPath else {
            throw AverageArgError.pathOutsideCwd(url)
        }
    }
}
