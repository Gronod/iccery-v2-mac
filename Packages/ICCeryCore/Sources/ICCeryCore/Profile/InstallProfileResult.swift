import Foundation

/// Result of installing a profile into the OS colour store.
public struct InstallProfileResult: Sendable, Equatable, Codable {
    public var destPath: String
    public var registered: Bool
    public var overwritten: Bool
    public var renamed: Bool
    public var openedPanel: Bool
    public var message: String
    public var calibrationNote: String?

    public init(
        destPath: String,
        registered: Bool,
        overwritten: Bool,
        renamed: Bool,
        openedPanel: Bool,
        message: String,
        calibrationNote: String? = nil
    ) {
        self.destPath = destPath
        self.registered = registered
        self.overwritten = overwritten
        self.renamed = renamed
        self.openedPanel = openedPanel
        self.message = message
        self.calibrationNote = calibrationNote
    }
}
