import Foundation

/// Parsed result from a `profcheck -u` run.
public struct ProfcheckReport: Sendable, Equatable, Codable {
    public var patchCount: Int?
    public var avgDE: Double?
    public var maxDE: Double?
    public var rmsDE: Double?
    public var status: VerificationStatus?
    public var warning: String?

    public var isValid: Bool {
        avgDE != nil && maxDE != nil && rmsDE != nil
    }

    public init(
        patchCount: Int? = nil,
        avgDE: Double? = nil,
        maxDE: Double? = nil,
        rmsDE: Double? = nil,
        status: VerificationStatus? = nil,
        warning: String? = nil
    ) {
        self.patchCount = patchCount
        self.avgDE = avgDE
        self.maxDE = maxDE
        self.rmsDE = rmsDE
        self.status = status
        self.warning = warning
    }
}
