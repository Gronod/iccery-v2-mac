import SwiftUI
import SceneKit
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

/// Native SceneKit 3D gamut viewer.
///
/// Displays a profile gamut mesh and the bundled `sRGB.gam` reference.  Uses
/// the CIELAB coordinate convention `x = a*`, `y = L*`, `z = b*` so that the
/// a* (green-red) axis is horizontal, L* (lightness) is vertical, and b*
/// (blue-yellow) is depth.
struct GamutView: View {
    @StateObject private var viewModel: GamutViewModel
    @State private var pause: () -> Void = {}
    @FocusState private var isFocused: Bool

    init(profileGamURL: URL? = nil) {
        _viewModel = StateObject(wrappedValue: GamutViewModel(profileGamURL: profileGamURL))
    }

    var body: some View {
        ZStack {
            GamutSceneView(
                profileMesh: viewModel.profileMesh,
                referenceMesh: viewModel.sRGBMesh,
                onReset: $viewModel.resetCamera,
                onPause: $pause
            )
            .focusable()
            .focused($isFocused)
            .onAppear { isFocused = true }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { viewModel.resetCamera() }) {
                        Text("Reset view")
                    }
                    .accessibilityIdentifier("btnResetGamutCamera")
                    .padding(8)
                }
                Spacer()
                HStack {
                    Text(viewModel.status)
                        .font(.caption)
                        .padding(8)
                        .background(.thinMaterial)
                        .cornerRadius(6)
                        .accessibilityIdentifier("gamutStatusText")
                    Spacer()
                }
                .padding(8)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onDisappear { pause() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gamutView")
    }
}

/// `NSViewRepresentable` wrapper around an `SCNView` that builds the scene from
/// one or two ``GamutMesh`` values.
///
/// Scene construction and camera reset are coordinated through a typed callback
/// binding owned by the view model.
private struct GamutSceneView: NSViewRepresentable {
    var profileMesh: GamutMesh?
    var referenceMesh: GamutMesh?
    var onReset: Binding<() -> Void>
    var onPause: Binding<() -> Void>

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
        context.coordinator.buildScene(profile: profileMesh, reference: referenceMesh)
        context.coordinator.installKeyMonitor()

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.buildScene(profile: profileMesh, reference: referenceMesh)
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
        nsView.isPlaying = false
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var scnView: SCNView?
        weak var scene: SCNScene?
        private var keyMonitor: Any?

        private let profileNode = SCNNode()
        private let referenceGroup = SCNNode()
        private let axisNode = SCNNode()
        private let cameraNode: SCNNode = {
            let node = SCNNode()
            node.camera = SCNCamera()
            node.camera?.zFar = 2000
            return node
        }()

        func buildScene(profile: GamutMesh?, reference: GamutMesh?) {
            guard let scene else { return }

            // Rebuild from scratch on every mesh change to avoid stale geometry.
            scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
            scene.rootNode.addChildNode(axisNode)
            scene.rootNode.addChildNode(profileNode)
            scene.rootNode.addChildNode(referenceGroup)
            scene.rootNode.addChildNode(cameraNode)

            buildAxisScaffold()

            if let profile {
                profileNode.addChildNode(profileMeshNode(profile, name: "profile"))
            } else {
                profileNode.childNodes.forEach { $0.removeFromParentNode() }
            }

            if let reference {
                referenceGroup.childNodes.forEach { $0.removeFromParentNode() }
                referenceGroup.addChildNode(referenceMeshNode(reference))
            }

            addLights(to: scene)
            resetCamera()
        }

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

        private func profileMeshNode(_ mesh: GamutMesh, name: String) -> SCNNode {
            let (geometry, _) = scnGeometry(for: mesh)

            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.diffuse.contents = NSColor.white
            material.transparency = 0.88
            material.isDoubleSided = true
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.name = name
            return node
        }

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
