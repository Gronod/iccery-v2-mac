import Foundation

/// Configuration for a profile installation.
public struct InstallProfileConfig: Sendable, Equatable {
    public var sourceURL: URL
    public var options: InstallProfileOptions

    public init(sourceURL: URL, options: InstallProfileOptions = InstallProfileOptions()) {
        self.sourceURL = sourceURL
        self.options = options
    }
}
