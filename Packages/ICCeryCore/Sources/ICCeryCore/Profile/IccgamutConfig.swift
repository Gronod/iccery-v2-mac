import Foundation

/// Configuration for an Argyll `iccgamut` run.
public struct IccgamutConfig: Sendable, Equatable {
    public var profileURL: URL
    public var density: Int

    public init(profileURL: URL, density: Int = 10) {
        self.profileURL = profileURL
        self.density = density
    }
}
