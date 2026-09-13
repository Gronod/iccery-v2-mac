import SwiftUI
import SceneKit
import Metal
import ICCeryCore
import simd

/// Builds a SceneKit geometry from a `GamutMesh` while dropping faces whose
/// indices are not backed by a vertex in the source mesh.
@MainActor
internal struct GamutSceneGeometryBuilder {
    static func geometry(for mesh: GamutMesh) -> (SCNGeometry, SCNGeometryElement) {
        let positions = mesh.vertices.map { $0.position }
        let positionData = positions.withUnsafeBytes { Data($0) }
        let positionSource = SCNGeometrySource(
            data: positionData,
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let colors: [SIMD4<Float>] = mesh.vertices.map { v in
            SIMD4<Float>(Float(v.rgb.r), Float(v.rgb.g), Float(v.rgb.b), 1.0)
        }
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )

        let vcount = mesh.vertices.count
        var indices: [UInt32] = []
        var validFaces: [GamutTriangle] = []
        indices.reserveCapacity(mesh.faces.count * 3)
        for face in mesh.faces {
            guard Int(face.a) < vcount, Int(face.b) < vcount, Int(face.c) < vcount else {
                continue
            }
            indices.append(face.a)
            indices.append(face.b)
            indices.append(face.c)
            validFaces.append(face)
        }
        let data = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: data,
            primitiveType: .triangles,
            primitiveCount: validFaces.count,
            bytesPerIndex: 4
        )

        let geometry = SCNGeometry(sources: [positionSource, colorSource], elements: [element])
        return (geometry, element)
    }
}

/// Native SceneKit 3D gamut viewer (issues #28, #147).
///
/// Displays the bundled `sRGB.gam` reference plus up to two profile
/// meshes with independent visibility toggles, a status line, and an
/// inspect panel (click a mesh, type a Lab value, or sample a TIFF
/// pixel). Uses the CIELAB coordinate convention `x = a*`, `y = L*`,
/// `z = b*`.
struct GamutView: View {
    @StateObject private var viewModel: GamutViewModel
    @State private var pause: () -> Void = {}
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Binding var showingAllHelp: Bool

    init(
        environment: AppEnvironment,
        profileGamURL: URL? = nil,
        showingAllHelp: Binding<Bool>
    ) {
        _viewModel = StateObject(wrappedValue: GamutViewModel(
            environment: environment, profileGamURL: profileGamURL))
        _showingAllHelp = showingAllHelp
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Theme.border)
            sceneArea
            Divider().overlay(Theme.border)
            statusLine
            inspectPanel
            Divider().overlay(Theme.border)
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Theme.background)
        .onDisappear { pause() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gamutView")
        .sheet(isPresented: $viewModel.showingTiffPreview) {
            tiffPreviewSheet
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            layerToggle(id: GamutViewModel.srgbLayerID, fallback: "sRGB")
            layerToggle(id: GamutViewModel.profileLayerID, fallback: "Profile")
            layerToggle(id: GamutViewModel.compareLayerID, fallback: "Compare")
            Spacer()
            addCompareMenu
            Button("Remove compare") { viewModel.removeCompare() }
                .disabled(viewModel.layer(id: GamutViewModel.compareLayerID) == nil)
                .accessibilityIdentifier("btnGamutRemoveCompare")
            Button("Sample TIFF…") { viewModel.openTiffSample() }
                .accessibilityIdentifier("btnGamutSampleTiff")
                .helpOverlay(
                    "Sample a colour from a target TIFF page.",
                    showing: $showingAllHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func layerToggle(id: String, fallback: String) -> some View {
        let layer = viewModel.layer(id: id)
        return Toggle(isOn: Binding(
            get: { layer != nil && viewModel.visibleIDs.contains(id) },
            set: { on in
                if on {
                    viewModel.visibleIDs.insert(id)
                } else {
                    viewModel.visibleIDs.remove(id)
                }
            }
        )) {
            Text(layer?.displayName ?? fallback)
        }
        .toggleStyle(.checkbox)
        .disabled(layer == nil)
        .help(layer.map { $0.sourceURL.lastPathComponent } ?? "No profile .gam loaded")
        // macOS 12 puts the identifier on the Toggle's container, an
        // element that never reports isEnabled — combine so the a11y
        // leaf is the checkbox itself.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gamutLayer-\(id)")
    }

    private var addCompareMenu: some View {
        Menu("Add compare…") {
            Button("Open .gam…") { viewModel.openCompareGam() }
                .accessibilityIdentifier("btnGamutOpenGam")
            Button("Open profile…") { viewModel.openCompareProfile() }
                .accessibilityIdentifier("btnGamutOpenProfile")
        }
        .accessibilityIdentifier("btnGamutAddCompare")
        .helpOverlay(
            "Add a second profile or .gam mesh to compare against.",
            showing: $showingAllHelp)
    }

    // MARK: - Scene

    private var sceneArea: some View {
        ZStack(alignment: .topTrailing) {
            if viewModel.viewerUnavailable {
                Text("3D gamut viewer is unavailable on this Mac; the rest of ICCery still works.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("gamutViewerUnavailable")
            } else {
                GamutSceneView(
                    layers: viewModel.layers,
                    visibleIDs: viewModel.visibleIDs,
                    onReset: $viewModel.resetCamera,
                    onPause: $pause,
                    onUnavailable: { viewModel.viewerUnavailable = true },
                    onInspect: { point, layerID in
                        if let layerID {
                            viewModel.inspectSceneHit(world: point, layerID: layerID)
                        } else {
                            viewModel.clearInspect()
                        }
                    }
                )
                .focusable()
                .focused($isFocused)
                .onAppear { isFocused = true }
            }
            Button(action: { viewModel.resetCamera() }) {
                Text("Reset view")
            }
            .accessibilityIdentifier("btnResetGamutCamera")
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status

    private var statusLine: some View {
        HStack(spacing: 10) {
            Text(viewModel.status)
                .font(.caption)
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("gamutStatusText")
            if let notice = viewModel.noticeText {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("gamutNoticeText")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Inspect panel

    private var inspectPanel: some View {
        HStack(spacing: 12) {
            if let lab = viewModel.inspectLab {
                inspectSwatch
                labReadout(lab)
                containmentColumn
                if viewModel.inspectIsApproximate {
                    Text("approx. Lab, not ColorSync")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("gamutInspectApprox")
                }
            } else {
                Text("Click the mesh, or enter Lab, to inspect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("gamutInspectIdle")
            }
            Spacer()
            labEntryFields
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(Theme.panel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gamutInspectPanel")
        .helpOverlay(
            "Inspect a Lab point against each loaded gamut.",
            showing: $showingAllHelp)
    }

    @ViewBuilder
    private var inspectSwatch: some View {
        if let swatch = viewModel.inspectSwatch {
            Color(red: swatch.r, green: swatch.g, blue: swatch.b)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.border))
                .accessibilityIdentifier("gamutInspectSwatch")
        }
    }

    private func labReadout(_ lab: LabColor) -> some View {
        HStack(spacing: 10) {
            Text(String(format: "L %.1f", lab.l))
                .accessibilityIdentifier("gamutInspectL")
            Text(String(format: "a %.1f", lab.a))
                .accessibilityIdentifier("gamutInspectA")
            Text(String(format: "b %.1f", lab.b))
                .accessibilityIdentifier("gamutInspectB")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(Theme.text)
    }

    private var containmentColumn: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.inspectResults, id: \.id) { result in
                Text("\(result.name) \(containmentWord(result.containment))")
                    .font(.caption)
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("gamutInspect-\(result.id)")
            }
        }
    }

    private func containmentWord(_ containment: GamutContainment) -> String {
        switch containment {
        case .inside: return "in"
        case .outside: return "out"
        case .unknown: return "?"
        }
    }

    private var labEntryFields: some View {
        HStack(spacing: 6) {
            Text("Lab 0–100 · ±128")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("L", text: $viewModel.labEntryL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .accessibilityIdentifier("gamutLabEntryL")
            TextField("a", text: $viewModel.labEntryA)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .accessibilityIdentifier("gamutLabEntryA")
            TextField("b", text: $viewModel.labEntryB)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .accessibilityIdentifier("gamutLabEntryB")
            Button("Inspect") { viewModel.inspectEnteredLab() }
                .disabled(!viewModel.canInspectLab)
                .accessibilityIdentifier("btnGamutInspectLab")
        }
    }

    // MARK: - Footer

    /// Always-visible Close (#147) — the fallback banner keeps it
    /// reachable and Escape works via `.cancelAction` without SceneKit.
    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("btnCloseGamut")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - TIFF sample sheet

    private var tiffPreviewSheet: some View {
        VStack(spacing: 12) {
            Text("Click a pixel to sample its colour.")
                .font(.headline)
                .foregroundStyle(Theme.text)
            if let png = viewModel.tiffPreviewPNG {
                TiffSampleImageView(pngData: png) { r, g, b in
                    viewModel.sampleTiffPixel(r: r, g: g, b: b)
                }
                .frame(minWidth: 320, minHeight: 240)
            }
            HStack {
                Spacer()
                Button("Cancel") { viewModel.showingTiffPreview = false }
                    .accessibilityIdentifier("btnCloseGamutTiffPreview")
            }
        }
        .padding(16)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gamutTiffPreview")
    }
}

/// `NSViewRepresentable` wrapper around an `SCNView` rendering one node
/// per ``NamedGamut`` layer.
///
/// Layer toggles hide/show `SCNNode`s — the scene is built once and the
/// camera is only reset through the explicit reset path, never on a
/// mesh or visibility update.
private struct GamutSceneView: NSViewRepresentable {
    var layers: [NamedGamut]
    var visibleIDs: Set<String>
    var onReset: Binding<() -> Void>
    var onPause: Binding<() -> Void>
    var onUnavailable: () -> Void
    var onInspect: (SIMD3<Float>, String?) -> Void

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.078, alpha: 1)
        scnView.allowsCameraControl = true
        scnView.showsStatistics = false
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        scnView.scene = scene
        scnView.autoenablesDefaultLighting = false

        context.coordinator.scnView = scnView
        context.coordinator.scene = scene
        context.coordinator.onInspect = onInspect
        context.coordinator.buildSceneOnce()
        context.coordinator.syncLayers(layers, visibleIDs: visibleIDs)
        context.coordinator.installKeyMonitor()
        context.coordinator.installClickGesture()

        // Safety net only — the primary no-Metal check is
        // `GamutSceneAvailability.isAvailable`, evaluated before this
        // view is mounted. Never respawn the view in a loop.
        if MTLCreateSystemDefaultDevice() == nil {
            DispatchQueue.main.async { onUnavailable() }
        }

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.onInspect = onInspect
        context.coordinator.syncLayers(layers, visibleIDs: visibleIDs)
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        onReset.wrappedValue = { [weak coordinator] in
            coordinator?.resetCamera()
        }
        onPause.wrappedValue = { [weak coordinator] in
            coordinator?.pause()
        }
        return coordinator
    }

    static func dismantleNSView(_ nsView: SCNView, coordinator: Coordinator) {
        coordinator.removeKeyMonitor()
        if let click = coordinator.clickGesture {
            nsView.removeGestureRecognizer(click)
        }
        nsView.isPlaying = false
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var scnView: SCNView?
        weak var scene: SCNScene?
        var onInspect: (SIMD3<Float>, String?) -> Void = { _, _ in }
        private(set) var clickGesture: NSClickGestureRecognizer?
        private var keyMonitor: Any?

        /// One `SCNNode` per loaded layer, keyed by `NamedGamut.id`.
        private var layerNodes: [String: SCNNode] = [:]
        private let axisNode = SCNNode()
        private let layerGroup = SCNNode()
        private let cameraNode: SCNNode = {
            let node = SCNNode()
            node.camera = SCNCamera()
            node.camera?.zFar = 2000
            return node
        }()

        /// Builds the static scene furniture exactly once — axis
        /// scaffold, lights, camera home. Layer content lives under
        /// `layerGroup` and is managed by `syncLayers`.
        func buildSceneOnce() {
            guard let scene, scene.rootNode.childNodes.isEmpty else { return }

            scene.rootNode.addChildNode(axisNode)
            scene.rootNode.addChildNode(layerGroup)
            scene.rootNode.addChildNode(cameraNode)

            buildAxisScaffold()
            addLights(to: scene)
            resetCamera()
        }

        /// Reconciles the node set with `layers` and `visibleIDs`.
        ///
        /// New layers get a node; removed layers lose theirs; hidden
        /// layers keep their mesh (`isHidden` only). Never rebuilds the
        /// scene, so the camera is untouched by a checkbox toggle.
        func syncLayers(_ layers: [NamedGamut], visibleIDs: Set<String>) {
            guard scene != nil else { return }
            let wanted = Set(layers.map { $0.id })
            for (id, node) in layerNodes where !wanted.contains(id) {
                node.removeFromParentNode()
                layerNodes.removeValue(forKey: id)
            }
            for layer in layers {
                if layerNodes[layer.id] == nil {
                    let node = makeLayerNode(for: layer)
                    layerNodes[layer.id] = node
                    layerGroup.addChildNode(node)
                }
                layerNodes[layer.id]?.isHidden = !visibleIDs.contains(layer.id)
            }
        }

        private func makeLayerNode(for layer: NamedGamut) -> SCNNode {
            let node: SCNNode
            switch layer.role {
            case .reference:
                node = referenceMeshNode(layer.mesh)
            case .profileA:
                node = profileMeshNode(layer.mesh)
            case .profileB:
                node = compareMeshNode(layer.mesh)
            }
            node.name = layer.id
            return node
        }

        // MARK: - Click inspect (#147)

        /// Click (not drag) hit-tests the scene. `NSClickGestureRecognizer`
        /// only fires on a press+release in place, so orbit drags are
        /// untouched.
        func installClickGesture() {
            guard let scnView, clickGesture == nil else { return }
            let gesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            scnView.addGestureRecognizer(gesture)
            clickGesture = gesture
        }

        @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView else { return }
            let point = gesture.location(in: scnView)
            for hit in scnView.hitTest(point, options: nil) {
                if let layerID = layerID(for: hit.node) {
                    let world = hit.worldCoordinates
                    onInspect(
                        SIMD3<Float>(Float(world.x), Float(world.y), Float(world.z)),
                        layerID)
                    return
                }
            }
            // Axis scaffold / empty background → back to idle.
            onInspect(.zero, nil)
        }

        /// Walks the hit node's ancestor chain looking for a layer node.
        private func layerID(for node: SCNNode) -> String? {
            var current: SCNNode? = node
            while let node = current {
                if let name = node.name, layerNodes[name] != nil { return name }
                current = node.parent
            }
            return nil
        }

        // MARK: - Scene furniture (unchanged from #28)

        private func addLights(to scene: SCNScene) {
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = NSColor.white
            ambient.light?.intensity = 750
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.color = NSColor.white
            key.light?.intensity = 800
            key.position = SCNVector3(150, 250, 150)
            key.look(at: SCNVector3(0, 50, 0))
            scene.rootNode.addChildNode(key)

            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .directional
            fill.light?.color = NSColor.white
            fill.light?.intensity = 350
            fill.position = SCNVector3(-120, -80, -120)
            fill.look(at: SCNVector3(0, 50, 0))
            scene.rootNode.addChildNode(fill)
        }

        private func buildAxisScaffold() {
            axisNode.childNodes.forEach { $0.removeFromParentNode() }

            // Bounding box: a*,b* ±128, L* 0–100.
            let box = buildWireBox(size: SIMD3<Float>(256, 100, 256), color: NSColor(red: 0.137, green: 0.137, blue: 0.212, alpha: 0.9))
            box.position = SCNVector3(0, 50, 0)
            axisNode.addChildNode(box)

            // Ground grid at y=0.
            axisNode.addChildNode(buildGridNode())

            // Axis lines.
            axisNode.addChildNode(buildLineNode(
                from: SIMD3<Float>(0, 0, 0),
                to: SIMD3<Float>(0, 100, 0),
                color: NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
            ))
            let abAxisColor = NSColor(red: 0.6, green: 0.733, blue: 0.8, alpha: 1.0)
            axisNode.addChildNode(buildLineNode(
                from: SIMD3<Float>(-128, 0, 0),
                to: SIMD3<Float>(128, 0, 0),
                color: abAxisColor
            ))
            axisNode.addChildNode(buildLineNode(
                from: SIMD3<Float>(0, 0, -128),
                to: SIMD3<Float>(0, 0, 128),
                color: abAxisColor
            ))
        }

        private func buildWireBox(size: SIMD3<Float>, color: NSColor) -> SCNNode {
            let hx = size.x / 2
            let hy = size.y / 2
            let hz = size.z / 2

            let corners: [SIMD3<Float>] = [
                SIMD3(-hx, -hy, -hz), SIMD3(hx, -hy, -hz),
                SIMD3(hx, -hy, hz), SIMD3(-hx, -hy, hz),
                SIMD3(-hx, hy, -hz), SIMD3(hx, hy, -hz),
                SIMD3(hx, hy, hz), SIMD3(-hx, hy, hz),
            ]

            // 12 edges, two vertices each.
            let edges: [(Int, Int)] = [
                (0,1), (1,2), (2,3), (3,0),
                (4,5), (5,6), (6,7), (7,4),
                (0,4), (1,5), (2,6), (3,7),
            ]

            var points: [SIMD3<Float>] = []
            for (a, b) in edges {
                points.append(corners[a])
                points.append(corners[b])
            }

            return lineNode(points: points, color: color)
        }

        private func buildGridNode() -> SCNNode {
            let divisions = 16
            let half = Float(128)
            let step = (half * 2) / Float(divisions)

            var points: [SIMD3<Float>] = []
            for i in 0...divisions {
                let v = -half + step * Float(i)
                // X-aligned
                points.append(SIMD3(-half, 0, v))
                points.append(SIMD3(half, 0, v))
                // Z-aligned
                points.append(SIMD3(v, 0, -half))
                points.append(SIMD3(v, 0, half))
            }

            let gridColor = NSColor(red: 0.118, green: 0.118, blue: 0.157, alpha: 1.0)
            return lineNode(points: points, color: gridColor)
        }

        private func buildLineNode(from: SIMD3<Float>, to: SIMD3<Float>, color: NSColor) -> SCNNode {
            return lineNode(points: [from, to], color: color)
        }

        /// Builds a line-set from a flat list of point pairs.
        ///
        /// Uses data-backed `SCNGeometrySource` so it works with `simd` vectors
        /// and avoids the SceneKit convenience-initializer label mismatch.
        private func lineNode(points: [SIMD3<Float>], color: NSColor) -> SCNNode {
            let source = source(for: points)

            let count = points.count
            var indices: [UInt32] = []
            indices.reserveCapacity(count)
            for i in 0..<UInt32(count) {
                indices.append(i)
            }
            let data = indices.withUnsafeBytes { Data($0) }
            let element = SCNGeometryElement(
                data: data,
                primitiveType: .line,
                primitiveCount: count / 2,
                bytesPerIndex: 4
            )

            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            material.isDoubleSided = false
            geometry.materials = [material]

            return SCNNode(geometry: geometry)
        }

        /// Profile A: solid vertex-coloured surface.
        private func profileMeshNode(_ mesh: GamutMesh) -> SCNNode {
            let (geometry, _) = scnGeometry(for: mesh)

            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.diffuse.contents = NSColor.white
            material.transparency = 0.88
            material.isDoubleSided = true
            geometry.materials = [material]

            return SCNNode(geometry: geometry)
        }

        /// Compare profile B: same vertex colours at ~30 % opacity so
        /// overlaps with A and the sRGB reference stay readable.
        private func compareMeshNode(_ mesh: GamutMesh) -> SCNNode {
            let (geometry, _) = scnGeometry(for: mesh)

            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.diffuse.contents = NSColor.white
            material.transparency = 0.30
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            geometry.materials = [material]

            return SCNNode(geometry: geometry)
        }

        /// Bundled sRGB reference: faint fill + structural edge lines.
        private func referenceMeshNode(_ mesh: GamutMesh) -> SCNNode {
            let (geometry, _) = scnGeometry(for: mesh)

            // Faint fill.
            let fillMaterial = SCNMaterial()
            fillMaterial.lightingModel = .lambert
            fillMaterial.diffuse.contents = NSColor(red: 0.533, green: 0.6, blue: 0.733, alpha: 1.0)
            fillMaterial.transparency = 0.93
            fillMaterial.isDoubleSided = true
            fillMaterial.writesToDepthBuffer = false
            geometry.materials = [fillMaterial]

            let fillNode = SCNNode(geometry: geometry)

            // Structural outline: one line per triangle edge.
            var linePoints: [SIMD3<Float>] = []
            let vcount = mesh.vertices.count
            for face in mesh.faces
            where Int(face.a) < vcount && Int(face.b) < vcount && Int(face.c) < vcount {
                let va = mesh.vertices[Int(face.a)].position
                let vb = mesh.vertices[Int(face.b)].position
                let vc = mesh.vertices[Int(face.c)].position
                linePoints.append(va); linePoints.append(vb)
                linePoints.append(vb); linePoints.append(vc)
                linePoints.append(vc); linePoints.append(va)
            }

            let edgeColor = NSColor(red: 0.4, green: 0.533, blue: 0.667, alpha: 0.55)
            let edgeNode = lineNode(points: linePoints, color: edgeColor)

            let group = SCNNode()
            group.addChildNode(fillNode)
            group.addChildNode(edgeNode)
            return group
        }

        /// Returns an `SCNGeometry` with per-vertex positions and sRGB colours.
        ///
        /// Uses data-backed `SCNGeometrySource` initializers; this is the only
        /// path that supports vertex colours through the `.color` semantic.
        private func scnGeometry(for mesh: GamutMesh) -> (SCNGeometry, SCNGeometryElement) {
            GamutSceneGeometryBuilder.geometry(for: mesh)
        }

        /// Shared helper for data-backed position sources.
        private func source(for points: [SIMD3<Float>]) -> SCNGeometrySource {
            let data = points.withUnsafeBytes { Data($0) }
            return SCNGeometrySource(
                data: data,
                semantic: .vertex,
                vectorCount: points.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD3<Float>>.stride
            )
        }

        func pause() {
            scnView?.isPlaying = false
        }

        /// Local key-down monitor for the R camera-reset shortcut (the
        /// SwiftUI key-press modifier is unavailable on macOS 12). Only
        /// events aimed at this view's window are handled; everything
        /// else passes through untouched.
        func installKeyMonitor() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self,
                      let scnView = self.scnView,
                      event.window === scnView.window,
                      event.charactersIgnoringModifiers?.uppercased() == "R"
                else { return event }
                self.resetCamera()
                return nil
            }
        }

        func removeKeyMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        func resetCamera() {
            guard let scnView else { return }

            // Re-create the camera node so `allowsCameraControl` starts from the
            // canonical home position every time.
            let newCameraNode = SCNNode()
            newCameraNode.camera = SCNCamera()
            newCameraNode.camera?.zFar = 2000

            let eye = SIMD3<Float>(180, 120, 180)
            let target = SIMD3<Float>(0, 50, 0)
            newCameraNode.simdTransform = lookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))

            if let scene = scnView.scene, scene.rootNode.childNodes.contains(cameraNode) {
                cameraNode.removeFromParentNode()
            }
            scnView.scene?.rootNode.addChildNode(newCameraNode)
            scnView.pointOfView = newCameraNode
        }

        private func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
            let forward = normalize(target - eye)
            let right = normalize(cross(up, forward))
            let newUp = cross(forward, right)

            var matrix = simd_float4x4()
            matrix.columns.0 = SIMD4<Float>(right, 0)
            matrix.columns.1 = SIMD4<Float>(newUp, 0)
            matrix.columns.2 = SIMD4<Float>(-forward, 0)
            matrix.columns.3 = SIMD4<Float>(eye, 1)
            return matrix
        }
    }
}

/// Click-to-sample image view for the TIFF preview sheet (#147).
///
/// The TIFF is already decoded to PNG on the host side (#58); the view
/// reports 8-bit sRGB pixel values at the clicked point — the Lab
/// conversion is the documented approximate matrix helper, not a CMM.
private struct TiffSampleImageView: NSViewRepresentable {
    let pngData: Data
    var onSample: (Int, Int, Int) -> Void

    func makeNSView(context: Context) -> TiffSampleNSView {
        let view = TiffSampleNSView()
        view.image = NSImage(data: pngData)
        view.onSample = onSample
        return view
    }

    func updateNSView(_ nsView: TiffSampleNSView, context: Context) {
        nsView.onSample = onSample
    }
}

private final class TiffSampleNSView: NSView {
    var image: NSImage? {
        didSet {
            bitmapRep = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                .flatMap { NSBitmapImageRep(cgImage: $0) }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var onSample: ((Int, Int, Int) -> Void)?
    private var bitmapRep: NSBitmapImageRep?

    override var intrinsicContentSize: NSSize {
        image?.size ?? NSSize(width: 320, height: 240)
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 0.055, green: 0.055, blue: 0.078, alpha: 1).setFill()
        dirtyRect.fill()
        guard let image else { return }
        image.draw(in: imageRect())
    }

    override func mouseUp(with event: NSEvent) {
        guard let rep = bitmapRep else { return }
        let rect = imageRect()
        let location = convert(event.locationInWindow, from: nil)
        guard rect.contains(location), rect.width > 0, rect.height > 0 else { return }

        let x = Int((location.x - rect.minX) / rect.width * CGFloat(rep.pixelsWide))
        // This view is not flipped: y grows up, bitmap rows grow down.
        let y = rep.pixelsHigh - 1
            - Int((location.y - rect.minY) / rect.height * CGFloat(rep.pixelsHigh))
        guard x >= 0, x < rep.pixelsWide, y >= 0, y < rep.pixelsHigh else { return }

        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return }
        onSample?(
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded()))
    }

    /// Aspect-fit rect of the image inside `bounds`.
    private func imageRect() -> NSRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height)
    }
}
