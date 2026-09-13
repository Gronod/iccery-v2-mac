import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue #147 — `GamutViewModel` compare-slot behaviour: failed or
/// missing compare meshes are info, never fatal (#24); sRGB always stays.
@MainActor
final class GamutViewModelTests: XCTestCase {

    /// Bundled root that has `reference_gamuts/sRGB.gam` but **no** tool
    /// binaries, so `iccgamut` spawns deterministically fail.
    private func bundledRootWithoutTools() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-gamut-vm-\(UUID().uuidString)")
        let gamutDir = root.appendingPathComponent("reference_gamuts")
        try FileManager.default.createDirectory(
            at: gamutDir, withIntermediateDirectories: true)
        let bundle = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        try FileManager.default.copyItem(
            at: bundle.appendingPathComponent("Argyll/reference_gamuts/sRGB.gam"),
            to: gamutDir.appendingPathComponent("sRGB.gam"))
        return root
    }

    private func makeViewModel(root: URL? = nil) throws -> GamutViewModel {
        let env = try TestAppEnvironment.make(bundledArgyllRoot: root)
        return GamutViewModel(environment: env.environment)
    }

    func testInitialLoadHasSRGBAndFacesStatus() async throws {
        let vm = try makeViewModel()
        await vm.awaitInitialLoad()

        XCTAssertNotNil(vm.layer(id: GamutViewModel.srgbLayerID))
        XCTAssertTrue(vm.status.contains("faces"), "status: \(vm.status)")
    }

    func testMissingCompareGamLeavesSRGBAndSetsNotice() async throws {
        let vm = try makeViewModel()
        await vm.awaitInitialLoad()

        await vm.loadCompareGam(
            url: URL(fileURLWithPath: "/nonexistent/compare.gam"))

        XCTAssertNotNil(vm.layer(id: GamutViewModel.srgbLayerID))
        XCTAssertNil(vm.layer(id: GamutViewModel.compareLayerID))
        XCTAssertNotNil(vm.noticeText)
    }

    func testFailedIccgamutLeavesSRGBAndSetsNotice() async throws {
        // bundledRootWithoutTools has no macos-universal/iccgamut.
        let vm = try makeViewModel(root: bundledRootWithoutTools())
        await vm.awaitInitialLoad()
        XCTAssertNotNil(vm.layer(id: GamutViewModel.srgbLayerID))

        let profile = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-gamut-icc-\(UUID().uuidString).icc")
        try Data("MOCK_ICC".utf8).write(to: profile)
        defer { try? FileManager.default.removeItem(at: profile) }

        await vm.loadCompareProfile(url: profile)

        XCTAssertNotNil(vm.layer(id: GamutViewModel.srgbLayerID))
        XCTAssertNil(vm.layer(id: GamutViewModel.compareLayerID))
        XCTAssertNotNil(vm.noticeText)
    }

    func testThirdProfileReplacesCompareSlot() async throws {
        let vm = try makeViewModel()
        await vm.awaitInitialLoad()

        let bundle = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let srgb = bundle.appendingPathComponent("Argyll/reference_gamuts/sRGB.gam")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-gamut-cmp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let first = dir.appendingPathComponent("first.gam")
        let second = dir.appendingPathComponent("second.gam")
        try FileManager.default.copyItem(at: srgb, to: first)
        try FileManager.default.copyItem(at: srgb, to: second)
        defer { try? FileManager.default.removeItem(at: dir) }

        await vm.loadCompareGam(url: first)
        XCTAssertNil(vm.noticeText)
        XCTAssertEqual(vm.layer(id: GamutViewModel.compareLayerID)?.displayName, "first")

        await vm.loadCompareGam(url: second)
        XCTAssertEqual(vm.layer(id: GamutViewModel.compareLayerID)?.displayName, "second")
        XCTAssertEqual(
            vm.layers.filter { $0.role == .profileB }.count, 1,
            "compare slot holds one profile")
        XCTAssertNotNil(vm.noticeText)
        XCTAssertNotNil(vm.layer(id: GamutViewModel.srgbLayerID))
    }

    func testRemoveCompareLeavesSRGB() async throws {
        let vm = try makeViewModel()
        await vm.awaitInitialLoad()

        let bundle = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        await vm.loadCompareGam(
            url: bundle.appendingPathComponent("Argyll/reference_gamuts/sRGB.gam"))
        XCTAssertNotNil(vm.layer(id: GamutViewModel.compareLayerID))

        vm.removeCompare()
        XCTAssertNil(vm.layer(id: GamutViewModel.compareLayerID))
        XCTAssertNotNil(vm.layer(id: GamutViewModel.srgbLayerID))
    }

    func testInspectLabRunsContainmentPerLayer() async throws {
        let vm = try makeViewModel()
        await vm.awaitInitialLoad()

        vm.labEntryL = "50"
        vm.labEntryA = "0"
        vm.labEntryB = "0"
        XCTAssertTrue(vm.canInspectLab)
        vm.inspectEnteredLab()

        let srgb = vm.inspectResults.first { $0.id == GamutViewModel.srgbLayerID }
        XCTAssertEqual(srgb?.containment, .inside)
        XCTAssertTrue(vm.inspectIsApproximate)
        XCTAssertNotNil(vm.inspectSwatch)
    }
}
