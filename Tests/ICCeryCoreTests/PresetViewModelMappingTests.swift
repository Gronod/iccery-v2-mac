import Testing
import Foundation
@testable import ICCeryCore
@testable import ICCery

/// Issue #82 — preset application through the live view models, under an
/// isolated `TestAppEnvironment` (temp stores, fresh ProcessManager).
@Suite("PresetViewModelMapping")
@MainActor
struct PresetViewModelMappingTests {

    private func makeWorkflow() throws -> (TestAppEnvironment, TargetWorkflowViewModel) {
        let env = try TestAppEnvironment.make()
        return (env, TargetWorkflowViewModel(environment: env.environment))
    }

    @Test("Applying a nil-FWA preset after a custom FWA clears the stale path")
    func nilFwaClearsCustomPath() throws {
        let (env, vm) = try makeWorkflow()
        defer { env.cleanup() }

        var customPreset = ProfilingPreset(
            id: "c-fwa", name: "FWA", patchCount: 800,
            colprofFwa: "/tmp/fwa.sp"
        )
        vm.applyPreset(customPreset)
        #expect(vm.profile.fwaSelection == .custom)
        #expect(vm.profile.fwaCustomPath == "/tmp/fwa.sp")

        customPreset.colprofFwa = nil
        vm.applyPreset(customPreset)
        #expect(vm.profile.fwaSelection == .none)
        #expect(vm.profile.fwaCustomPath == "")
        #expect(vm.profile.fwaValue == nil)
    }

    @Test("Custom FWA preset path survives the round-trip to colprof_fwa")
    func customFwaRoundTrip() throws {
        let (env, vm) = try makeWorkflow()
        defer { env.cleanup() }

        let preset = ProfilingPreset(
            id: "c-fwa2", name: "FWA2", patchCount: 800,
            colprofFwa: "/tmp/other.sp"
        )
        vm.applyPreset(preset)
        #expect(vm.profile.fwaSelection == .custom)
        #expect(vm.profile.fwaCustomPath == "/tmp/other.sp")
        #expect(vm.profile.fwaValue == "/tmp/other.sp")
    }

    @Test("Preset calibration reaches Stage 2 instead of stale live state")
    func presetCalibrationReachesStage2() throws {
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

        #expect(vm.profile.applyCalibration)
        #expect(vm.profile.calibrationFile == "/tmp/preset.cal")
        #expect(vm.buildPrinttargConfig().calibrationFile == "/tmp/preset.cal")
    }

    @Test("Preset with calibration disabled clears Stage 2 calibration")
    func disabledCalibrationClearsStage2() throws {
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

        #expect(!vm.profile.applyCalibration)
        #expect(vm.buildPrinttargConfig().calibrationFile == nil)
    }

    @Test("Preset Stage 1/2 form fields apply to the live form")
    func formFieldsApply() throws {
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

        #expect(vm.colourSpace == .cmyk)
        #expect(vm.effectivePatchCount == 1500)
        #expect(vm.whitePatches == 6)
        #expect(vm.blackPatches == 8)
        #expect(vm.greyStepsEnabled && vm.greySteps == 9)
        #expect(vm.algorithm == .random)
        #expect(vm.tiffDpi == 150)
        #expect(vm.pageSize == .custom)
        #expect(vm.customPageW == 250 && vm.customPageH == 300)
        #expect(vm.selectedPresetID == "c-form")

        // Disabled advanced controls stay nil in the snapshot, not
        // numeric sentinels.
        preset.greySteps = nil
        vm.applyPreset(preset)
        #expect(!vm.greyStepsEnabled)
        #expect(vm.buildTargenConfig().greySteps == nil)
    }
}
