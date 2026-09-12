import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue #82 — preset application through the live view models, under an
/// isolated `TestAppEnvironment` (temp stores, fresh ProcessManager).
@MainActor
final class PresetViewModelMappingTests: XCTestCase {

    private func makeWorkflow() throws -> (TestAppEnvironment, TargetWorkflowViewModel) {
        let env = try TestAppEnvironment.make()
        return (env, TargetWorkflowViewModel(environment: env.environment))
    }

    func testNilFwaClearsCustomPath() throws {
        let (env, vm) = try makeWorkflow()
        defer { env.cleanup() }

        var customPreset = ProfilingPreset(
            id: "c-fwa", name: "FWA", patchCount: 800,
            colprofFwa: "/tmp/fwa.sp"
        )
        vm.applyPreset(customPreset)
        XCTAssertEqual(vm.profile.fwaSelection, .custom)
        XCTAssertEqual(vm.profile.fwaCustomPath, "/tmp/fwa.sp")

        customPreset.colprofFwa = nil
        vm.applyPreset(customPreset)
        XCTAssertEqual(vm.profile.fwaSelection, .none)
        XCTAssertEqual(vm.profile.fwaCustomPath, "")
        XCTAssertNil(vm.profile.fwaValue)
    }

    func testCustomFwaRoundTrip() throws {
        let (env, vm) = try makeWorkflow()
        defer { env.cleanup() }

        let preset = ProfilingPreset(
            id: "c-fwa2", name: "FWA2", patchCount: 800,
            colprofFwa: "/tmp/other.sp"
        )
        vm.applyPreset(preset)
        XCTAssertEqual(vm.profile.fwaSelection, .custom)
        XCTAssertEqual(vm.profile.fwaCustomPath, "/tmp/other.sp")
        XCTAssertEqual(vm.profile.fwaValue, "/tmp/other.sp")
    }

    func testPresetCalibrationReachesStage2() throws {
        let (env, vm) = try makeWorkflow()
        defer { env.cleanup() }

        // Stale live state must not leak into the preset-applied layout.
        vm.profile.applyCalibration = true
        vm.profile.calibrationFile = "/tmp/stale.cal"

        let preset = ProfilingPreset(
            id: "c-cal", name: "Cal", patchCount: 800,
            calibrationFile: "/tmp/preset.cal",
            applyCalibration: true
        )
        vm.applyPreset(preset)

        XCTAssertTrue(vm.profile.applyCalibration)
        XCTAssertEqual(vm.profile.calibrationFile, "/tmp/preset.cal")
        XCTAssertEqual(vm.buildPrinttargConfig().calibrationFile, "/tmp/preset.cal")
    }

    func testDisabledCalibrationClearsStage2() throws {
        let (env, vm) = try makeWorkflow()
        defer { env.cleanup() }

        vm.profile.applyCalibration = true
        vm.profile.calibrationFile = "/tmp/stale.cal"

        let preset = ProfilingPreset(
            id: "c-nocal", name: "NoCal", patchCount: 800,
            calibrationFile: "/tmp/preset.cal",
            applyCalibration: nil
        )
        vm.applyPreset(preset)

        XCTAssertFalse(vm.profile.applyCalibration)
        XCTAssertNil(vm.buildPrinttargConfig().calibrationFile)
    }

    func testFormFieldsApply() throws {
        let (env, vm) = try makeWorkflow()
        defer { env.cleanup() }

        var preset = ProfilingPreset(
            id: "c-form", name: "Form",
            colourSpace: "cmyk", patchCount: 1500,
            whitePatches: 6,
            blackPatches: 8,
            greySteps: 9,
            fullSpreadAlgorithm: "r",
            pageSize: "250x300",
            dpi: 150
        )
        vm.applyPreset(preset)

        XCTAssertEqual(vm.colourSpace, .cmyk)
        XCTAssertEqual(vm.effectivePatchCount, 1500)
        XCTAssertEqual(vm.whitePatches, 6)
        XCTAssertEqual(vm.blackPatches, 8)
        XCTAssertTrue(vm.greyStepsEnabled && vm.greySteps == 9)
        XCTAssertEqual(vm.algorithm, .random)
        XCTAssertEqual(vm.tiffDpi, 150)
        XCTAssertEqual(vm.pageSize, .custom)
        XCTAssertTrue(vm.customPageW == 250 && vm.customPageH == 300)
        XCTAssertEqual(vm.selectedPresetID, "c-form")

        // Disabled advanced controls stay nil in the snapshot, not
        // numeric sentinels.
        preset.greySteps = nil
        vm.applyPreset(preset)
        XCTAssertFalse(vm.greyStepsEnabled)
        XCTAssertNil(vm.buildTargenConfig().greySteps)
    }
}
