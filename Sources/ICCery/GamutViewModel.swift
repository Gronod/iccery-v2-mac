import Combine
import Foundation
import ICCeryCore
import simd

/// View model for the native SceneKit gamut viewer (issues #28, #147).
///
/// Loads the bundled `sRGB.gam` reference immediately, the workflow's own
/// profile `.gam` when one exists, and an optional compare mesh the user
/// adds from the sheet toolbar. `iccgamut` failure is an in-sheet info
/// notice, never fatal (#24).
@MainActor
final class GamutViewModel: ObservableObject {

    /// Stable layer ids — also the `gamutLayer-<id>` a11y suffixes.
    static let srgbLayerID = "sRGB"
    static let profileLayerID = "profile"
    static let compareLayerID = "compare"

    /// Loaded meshes: bundled sRGB plus up to two profiles.
    @Published var layers: [NamedGamut] = []

    /// Layer ids currently shown in the scene. Toggling never unloads
    /// the mesh — the `SCNNode` is hidden only.
    @Published var visibleIDs: Set<String> = [srgbLayerID]

    /// User-facing status line (`gamutStatusText`). Always non-empty
    /// once set — `Milestone6GamutUITests` asserts it.
    @Published var status = "Loading gamut…"

    /// In-sheet info line (`gamutNoticeText`). The main `NoticeBanner`
    /// sits behind the sheet, so notices surface here instead.
    @Published var noticeText: String?

    /// Set when `SCNView` cannot create a render context; the scene is
    /// replaced by the docs/18 fallback text (`gamutViewerUnavailable`).
    @Published var viewerUnavailable = false

    /// Closure injected into the SceneKit view to request a camera reset.
    @Published var resetCamera: () -> Void = {}

    // MARK: - Inspect panel

    /// Lab point currently inspected, or `nil` for the idle state.
    @Published var inspectLab: LabColor?

    /// Swatch colour: the hit vertex's `rgb`, or the approximate sRGB of
    /// the inspected Lab.
    @Published var inspectSwatch: DisplayRGB?

    /// `true` when the swatch/Lab came from the approximate helper or a
    /// typed value — drives the "approx. Lab, not ColorSync" caption.
    @Published var inspectIsApproximate = false

    /// Per-layer containment for `inspectLab`, in layer order.
    @Published var inspectResults: [(id: String, name: String, containment: GamutContainment)] = []

    /// Manual Lab entry fields (`gamutLabEntry*`).
    @Published var labEntryL = ""
    @Published var labEntryA = ""
    @Published var labEntryB = ""

    // MARK: - TIFF sampling

    /// PNG bytes for the preview sheet (`gamutTiffPreview`).
    @Published var tiffPreviewPNG: Data?
    @Published var showingTiffPreview = false

    private let environment: AppEnvironment
    private let profileGamURL: URL?
    private let fileDialogs = FileDialogService.shared

    init(environment: AppEnvironment, profileGamURL: URL? = nil) {
        self.environment = environment
        self.profileGamURL = profileGamURL
        loadTask = Task { await load() }
    }

    private var loadTask: Task<Void, Never>?

    /// Awaits the initial sRGB/profile load — used by tests.
    func awaitInitialLoad() async {
        await loadTask?.value
    }

    func layer(id: String) -> NamedGamut? {
        layers.first { $0.id == id }
    }

    // MARK: - Initial load

    private func load() async {
        do {
            let referenceURL = environment.runner.binaryResolver.referenceGamut("sRGB")
            let reference = try await parse(url: referenceURL)
            layers.append(NamedGamut(
                id: Self.srgbLayerID,
                displayName: "sRGB",
                role: .reference,
                mesh: reference,
                sourceURL: referenceURL))
            visibleIDs.insert(Self.srgbLayerID)
        } catch {
            status = "Could not load gamut: \(error.localizedDescription)"
            return
        }

        if let profileGamURL {
            do {
                let profile = try await parse(url: profileGamURL)
                layers.append(NamedGamut(
                    id: Self.profileLayerID,
                    displayName: profileGamURL.deletingPathExtension().lastPathComponent,
                    role: .profileA,
                    mesh: profile,
                    sourceURL: profileGamURL))
                visibleIDs.insert(Self.profileLayerID)
            } catch {
                // #24 — a missing/unparseable profile mesh is info, not fatal.
                noticeText = "Profile gamut could not be loaded: \(error.localizedDescription)"
            }
        }
        refreshStatus()
    }

    // MARK: - Compare slot (profile B)

    /// `btnGamutOpenGam` — pick an existing `.gam` for the compare slot.
    func openCompareGam() {
        let url = UITestHooks.isEnabled
            ? UITestHooks.gamutFileURL
            : fileDialogs.selectGamutFile()
        guard let url else { return }
        Task { await loadCompareGam(url: url) }
    }

    /// `btnGamutOpenProfile` — pick `.icc/.icm`; uses a sibling `.gam`
    /// when present, otherwise runs bundled `iccgamut -v -d 10` (#24).
    func openCompareProfile() {
        let url = UITestHooks.isEnabled
            ? UITestHooks.gamutProfileURL
            : fileDialogs.selectProfileFile()
        guard let url else { return }
        Task { await loadCompareProfile(url: url) }
    }

    /// `btnGamutRemoveCompare` — drops layer B, leaves sRGB + A.
    func removeCompare() {
        layers.removeAll { $0.id == Self.compareLayerID }
        visibleIDs.remove(Self.compareLayerID)
        refreshStatus()
    }

    /// Parses `url` into the compare slot. Internal for tests — the UI
    /// reaches it through `openCompareGam` / `openCompareProfile`.
    func loadCompareGam(url: URL) async {
        do {
            let mesh = try await parse(url: url)
            installCompare(NamedGamut(
                id: Self.compareLayerID,
                displayName: url.deletingPathExtension().lastPathComponent,
                role: .profileB,
                mesh: mesh,
                sourceURL: url))
        } catch {
            noticeText = "Could not load compare gamut: \(error.localizedDescription)"
        }
    }

    /// `.icc/.icm` → sibling `.gam` or `iccgamut` → compare slot.
    /// Internal for tests.
    func loadCompareProfile(url: URL) async {
        let gamURL = url.deletingPathExtension().appendingPathExtension("gam")
        do {
            if !FileManager.default.fileExists(atPath: gamURL.path) {
                _ = try await environment.runner.runIccgamut(
                    config: IccgamutConfig(profileURL: url))
            }
            await loadCompareGam(url: gamURL)
        } catch {
            noticeText = "Gamut extraction failed: \(error.localizedDescription)"
        }
    }

    /// A third profile replaces B — the compare slot never stacks and
    /// sRGB is never touched.
    private func installCompare(_ gamut: NamedGamut) {
        if layers.contains(where: { $0.id == gamut.id }) {
            noticeText = "Compare slot holds one profile. The previous compare mesh was replaced."
        }
        layers.removeAll { $0.id == gamut.id }
        layers.append(gamut)
        visibleIDs.insert(gamut.id)
        refreshStatus()
    }

    // MARK: - Status line

    /// `sRGB 448v / 892 faces · Profile 1024v / 2048 faces · vol 62% of sRGB`.
    /// Unloaded layers are omitted; the volume clause appears only when
    /// both volumes are finite and positive.
    private func refreshStatus() {
        var clauses = layers.map {
            "\($0.displayName) \($0.mesh.vertices.count)v / \($0.mesh.faces.count) faces"
        }
        if let srgb = layer(id: Self.srgbLayerID),
           let profile = layer(id: Self.profileLayerID) {
            let srgbVolume = GamutGeometry.volume(of: srgb.mesh)
            let profileVolume = GamutGeometry.volume(of: profile.mesh)
            if srgbVolume.isFinite, srgbVolume > 0,
               profileVolume.isFinite, profileVolume > 0 {
                clauses.append("vol \(Int((profileVolume / srgbVolume * 100).rounded()))% of sRGB")
            }
        }
        status = clauses.isEmpty ? "No gamut loaded" : clauses.joined(separator: " · ")
    }

    // MARK: - Inspect

    /// Whether every manual Lab field parses as a number; the Inspect
    /// button is disabled while this is false.
    var canInspectLab: Bool {
        [labEntryL, labEntryA, labEntryB].allSatisfy { Double($0) != nil }
    }

    /// Runs containment for a Lab point and publishes the inspect row.
    func inspect(lab: LabColor, swatch: DisplayRGB?, isApproximate: Bool) {
        inspectLab = lab
        inspectSwatch = swatch ?? LabColorMath.labToSRGB(lab)
        inspectIsApproximate = isApproximate
        inspectResults = layers.map {
            ($0.id, $0.displayName, GamutGeometry.containment(of: lab, in: $0.mesh))
        }
    }

    /// Click on the axis scaffold or empty background returns the panel
    /// to idle.
    func clearInspect() {
        inspectLab = nil
        inspectSwatch = nil
        inspectIsApproximate = false
        inspectResults = []
    }

    /// SceneKit hit callback: world `(x, y, z)` → Lab `(x→a*, y→L*, z→b*)`.
    /// The swatch is the nearest vertex colour of the hit layer's mesh.
    func inspectSceneHit(world: SIMD3<Float>, layerID: String) {
        let lab = LabColor(l: Double(world.y), a: Double(world.x), b: Double(world.z))
        var swatch: DisplayRGB?
        var approximate = true
        if let mesh = layer(id: layerID)?.mesh,
           let nearest = mesh.vertices.min(by: {
               simd_distance($0.position, world) < simd_distance($1.position, world)
           }) {
            swatch = nearest.rgb
            approximate = false
        }
        inspect(lab: lab, swatch: swatch, isApproximate: approximate)
    }

    /// `btnGamutInspectLab` — typed L*a*b* path. No clamping; out-of-axis
    /// values still run containment and report `?` outside every hull.
    func inspectEnteredLab() {
        guard let l = Double(labEntryL),
              let a = Double(labEntryA),
              let b = Double(labEntryB) else { return }
        inspect(lab: LabColor(l: l, a: a, b: b), swatch: nil, isApproximate: true)
    }

    // MARK: - TIFF sampling

    /// `btnGamutSampleTiff` — pick a target TIFF, decode a host-side PNG
    /// preview (#58), and open the click-to-sample sheet.
    func openTiffSample() {
        let url = UITestHooks.isEnabled
            ? UITestHooks.gamutTiffURL
            : fileDialogs.selectTiffFile()
        guard let url else { return }
        guard let png = TiffPreview.previewPNG(tiff: url) else {
            noticeText = "Could not decode TIFF preview."
            return
        }
        tiffPreviewPNG = png
        showingTiffPreview = true
    }

    /// Pixel tap inside the preview sheet: sRGB8 → approximate Lab D50.
    func sampleTiffPixel(r: Int, g: Int, b: Int) {
        inspect(
            lab: ApproximateLab.srgb8ToLab(r: r, g: g, b: b),
            swatch: DisplayRGB(
                r: Double(r) / 255.0,
                g: Double(g) / 255.0,
                b: Double(b) / 255.0),
            isApproximate: true)
        showingTiffPreview = false
    }

    /// Parses a `.gam` file off the main actor so large meshes do not
    /// stall the UI.
    private func parse(url: URL) async throws -> GamutMesh {
        try await Task.detached {
            try GamutMeshParser.parse(url: url)
        }.value
    }
}
