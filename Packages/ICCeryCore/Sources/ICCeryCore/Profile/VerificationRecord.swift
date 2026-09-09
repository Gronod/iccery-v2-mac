import Foundation

/// A single entry in the verification history store.
public struct VerificationRecord: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var profileName: String
    public var printerName: String
    public var avgDE: Double
    public var maxDE: Double
    public var rmsDE: Double
    public var patchCount: Int
    public var status: VerificationStatus
    public var timestamp: Date

    public init(
        id: String,
        profileName: String,
        printerName: String,
        avgDE: Double,
        maxDE: Double,
        rmsDE: Double,
        patchCount: Int,
        status: VerificationStatus,
        timestamp: Date
    ) {
        self.id = id
        self.profileName = profileName
        self.printerName = printerName
        self.avgDE = avgDE
        self.maxDE = maxDE
        self.rmsDE = rmsDE
        self.patchCount = patchCount
        self.status = status
        self.timestamp = timestamp
    }
}
