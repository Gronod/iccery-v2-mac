import Testing
import Foundation
@testable import ICCeryCore
@testable import ICCery

/// Issue #29 — `CAL_` basename must be restored on relaunch and on any
/// attempt to navigate to a non-calibration stage that would use it.
@Suite("WizardCalibrationSession")
@MainActor
struct WizardCalibrationSessionTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-cal-state-\(UUID().uuidString)")
            .appendingPathComponent("wizard_state.json")
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-cal-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }

    @Test("Persist and restore calibrationOriginalBasename across a relaunch")
    func relaunchRestoresOriginal() throws {
        let url = tempURL()
        let store = WizardStateStore(fileURL: url)
        var saved = WizardState(
            currentStage: WizardStage.calibrate.rawValue,
            basename: "CAL_DemoTarget",
            cwd: "/tmp/charts",
            sessionMode: .calibration,
            calibrationOriginalBasename: "DemoTarget"
        )
        try store.save(saved)

        let model = WizardViewModel(stateStore: store)

        #expect(model.basename == "DemoTarget")
        #expect(model.calibrationOriginalBasename == "")
        #expect(model.sessionMode == .profile)
        #expect(model.stage == .generate)
    }

    @Test("go(to: .buildProfile) while basename is CAL_ refuses and restores the original")
    func goToBuildProfileRefusesAndRestores() throws {
        let dir = try tempDir()
        let url = tempURL()
        let store = WizardStateStore(fileURL: url)
        let model = WizardViewModel(stateStore: store)

        model.setTarget(basename: "DemoTarget", workingDirectory: dir)
        model.calibrationOriginalBasename = "DemoTarget"
        model.basename = "CAL_DemoTarget"
        model.sessionMode = .calibration
        model.stage = .calibrate

        model.go(to: .buildProfile)

        #expect(model.basename == "DemoTarget")
        #expect(model.calibrationOriginalBasename == "")
        #expect(model.sessionMode == .profile)
        #expect(model.stage == .calibrate)
    }

    @Test("go(to: .layOutPrint) while basename is CAL_ stays in calibration")
    func goToLayoutStaysCal() throws {
        let dir = try tempDir()
        let url = tempURL()
        let store = WizardStateStore(fileURL: url)
        let model = WizardViewModel(stateStore: store)

        model.setTarget(basename: "DemoTarget", workingDirectory: dir)
        model.calibrationOriginalBasename = "DemoTarget"
        model.basename = "CAL_DemoTarget"
        model.sessionMode = .calibration
        model.stage = .calibrate

        model.go(to: .layOutPrint)

        #expect(model.basename == "CAL_DemoTarget")
        #expect(model.calibrationOriginalBasename == "DemoTarget")
        #expect(model.sessionMode == .calibration)
        #expect(model.stage == .layOutPrint)
    }
}
