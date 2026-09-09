import Foundation

/// Collision policy for profile installation.
public enum ProfileCollisionPolicy: String, Sendable, Equatable, Codable, CaseIterable {
    case overwrite
    case rename
    case cancel
}

/// Options for installing a finished profile into the OS colour store.
public struct InstallProfileOptions: Sendable, Equatable, Codable {
    public var forceOverwrite: Bool
    public var preferSystem: Bool
    public var collisionPolicy: ProfileCollisionPolicy
    public var openColorPanel: Bool
    public var calibrationNote: String?

    public init(
        forceOverwrite: Bool = false,
        preferSystem: Bool = false,
        collisionPolicy: ProfileCollisionPolicy = .cancel,
        openColorPanel: Bool = false,
        calibrationNote: String? = nil
    ) {
        self.forceOverwrite = forceOverwrite
        self.preferSystem = preferSystem
        self.collisionPolicy = collisionPolicy
        self.openColorPanel = openColorPanel
        self.calibrationNote = calibrationNote
    }
}
