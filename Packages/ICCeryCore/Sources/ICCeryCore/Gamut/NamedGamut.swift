import Foundation

/// A parsed gamut mesh plus the display metadata the compare viewer
/// needs (issue #147).
///
/// `displayName` is user-derived (a file name); views must render it
/// through `Text` only (#114).
public struct NamedGamut: Sendable, Equatable, Identifiable {

    /// What the layer is used for in the compare UI.
    public enum Role: String, Sendable, Equatable {
        /// Bundled reference space (sRGB). Cannot be removed, only hidden.
        case reference
        /// The workflow's own profile gamut.
        case profileA
        /// The user-added compare gamut. Replaced, never stacked.
        case profileB
    }

    public var id: String
    public var displayName: String
    public var role: Role
    public var mesh: GamutMesh
    public var sourceURL: URL

    public init(
        id: String,
        displayName: String,
        role: Role,
        mesh: GamutMesh,
        sourceURL: URL
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.mesh = mesh
        self.sourceURL = sourceURL
    }
}
