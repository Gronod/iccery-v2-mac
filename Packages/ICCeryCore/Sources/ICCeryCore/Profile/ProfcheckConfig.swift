import Foundation

/// Configuration for an Argyll `profcheck` run.
public struct ProfcheckConfig: Sendable, Equatable {
    public var ti3URL: URL
    public var iccURL: URL

    public init(ti3URL: URL, iccURL: URL) {
        self.ti3URL = ti3URL
        self.iccURL = iccURL
    }
}
