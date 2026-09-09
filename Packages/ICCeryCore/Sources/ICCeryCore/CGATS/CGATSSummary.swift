import Foundation

/// Human-readable summary of an imported CGATS dataset.
public struct CGATSSummary: Sendable, Equatable {
    public let patchCount: Int
    public let colorSpace: String?
    public let deviceClass: String?
    public let hasSpectral: Bool
    public let previewRows: [String]

    public init(dataset: CGATSDataset, previewRowCount: Int = 4) {
        self.patchCount = dataset.samples.count
        self.colorSpace = dataset.colorRep
        self.deviceClass = dataset.deviceClass
        self.hasSpectral = dataset.fieldNames.contains { $0.hasPrefix("SPECTRAL_") }
        self.previewRows = Array(dataset.samples.prefix(previewRowCount).map { sample in
            "\(sample.id)" + (sample.loc.map { " \($0)" } ?? "")
        })
    }
}
