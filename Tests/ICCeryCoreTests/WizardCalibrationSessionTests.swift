import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue #29 — `CAL_` basename must be restored on relaunch and on any
/// attempt to navigate to a non-calibration stage that would use it.
@MainActor
final class WizardCalibrationSessionTests: XCTestCase {

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

    func testRelaunchRestoresOriginal() throws {
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

        XCTAssertEqual(model.basename, "DemoTarget")
        XCTAssertEqual(model.calibrationOriginalBasename, "")
        XCTAssertEqual(model.sessionMode, .profile)
        XCTAssertEqual(model.stage, .generate)
    }

    func testGoToBuildProfileRefusesAndRestores() throws {
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

        XCTAssertEqual(model.basename, "DemoTarget")
        XCTAssertEqual(model.calibrationOriginalBasename, "")
        XCTAssertEqual(model.sessionMode, .profile)
        XCTAssertEqual(model.stage, .calibrate)
    }

    func testGoToLayoutStaysCal() throws {
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

        XCTAssertEqual(model.basename, "CAL_DemoTarget")
        XCTAssertEqual(model.calibrationOriginalBasename, "DemoTarget")
        XCTAssertEqual(model.sessionMode, .calibration)
        XCTAssertEqual(model.stage, .layOutPrint)
    }
}
