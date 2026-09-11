import Combine
import Foundation
import ICCeryCore

/// View model for the native SceneKit gamut viewer.
///
/// Loads the bundled `sRGB.gam` reference immediately and, optionally, a
/// printer/profile `.gam` from the current working directory.
@MainActor
final class GamutViewModel: ObservableObject {

    /// Parsed reference sRGB gamut mesh.
    @Published var sRGBMesh: GamutMesh?

    /// Parsed printer/profile gamut mesh.
    @Published var profileMesh: GamutMesh?

    /// User-facing status line.
    @Published var status = "Loading gamut…"

    /// Closure injected into the SceneKit view to request a camera reset.
    @Published var resetCamera: () -> Void = {}

    private let profileGamURL: URL?

    init(profileGamURL: URL? = nil) {
        self.profileGamURL = profileGamURL
        Task { await load() }
    }

    private func load() async {
        do {
            let referenceURL = BinaryResolver().referenceGamut("sRGB")
            let reference = try await parse(url: referenceURL)
            sRGBMesh = reference

            if let profileGamURL {
                let profile = try await parse(url: profileGamURL)
                profileMesh = profile
                status = "Profile gamut (\(profile.faces.count) faces) vs sRGB reference"
            } else {
                status = "sRGB reference gamut (\(reference.faces.count) faces)"
            }
        } catch {
            status = "Could not load gamut: \(error.localizedDescription)"
        }
    }

    /// Parses a `.gam` file off the main actor so large meshes do not stall
    /// the UI.
    private func parse(url: URL) async throws -> GamutMesh {
        try await Task.detached {
            try GamutMeshParser.parse(url: url)
        }.value
    }
}
