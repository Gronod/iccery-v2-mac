import Foundation

/// Configuration for an Argyll `colprof` run (issue #23, docs/16).
public struct ColprofConfig: Sendable, Equatable {
    public var algorithm: String
    public var quality: String
    public var intent: String?
    public var fwa: String?
    public var illuminant: String?
    public var observer: String?
    public var inputViewingCond: String?
    public var outputViewingCond: String?
    public var description: String?
    public var copyright: String?
    public var basename: String
    public var workingDirectory: URL?

    public init(
        algorithm: String = "l",
        quality: String = "m",
        intent: String? = nil,
        fwa: String? = nil,
        illuminant: String? = nil,
        observer: String? = nil,
        inputViewingCond: String? = nil,
        outputViewingCond: String? = nil,
        description: String? = nil,
        copyright: String? = nil,
        basename: String,
        workingDirectory: URL? = nil
    ) {
        self.algorithm = algorithm
        self.quality = quality
        self.intent = intent
        self.fwa = fwa
        self.illuminant = illuminant
        self.observer = observer
        self.inputViewingCond = inputViewingCond
        self.outputViewingCond = outputViewingCond
        self.description = description
        self.copyright = copyright
        self.basename = basename
        self.workingDirectory = workingDirectory
    }
}
