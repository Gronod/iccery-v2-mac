import Foundation

/// Configuration for an Argyll `applycal` run.
public struct ApplycalConfig: Sendable, Equatable {
    public var calibrationPath: String
    public var inputProfileURL: URL
    public var outputProfileURL: URL?
    public var unapply: Bool

    /// In-place when `outputProfileURL` is `nil`.
    public init(
        calibrationPath: String,
        inputProfileURL: URL,
        outputProfileURL: URL? = nil,
        unapply: Bool = false
    ) {
        self.calibrationPath = calibrationPath
        self.inputProfileURL = inputProfileURL
        self.outputProfileURL = outputProfileURL
        self.unapply = unapply
    }
}
