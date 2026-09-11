import Foundation
import XCTest
@testable import ICCeryCore

private func artefacts(
    ti1: Bool = false, ti2: Bool = false, ti3: Bool = false, profile: Bool = false
) -> StageArtefacts {
    var a = StageArtefacts()
    a.stage1Complete = ti1
    a.stage2Complete = ti2
    a.stage3Complete = ti3
    a.stage4Complete = profile
    if profile {
        a.profilePath = URL(fileURLWithPath: "/x/t.icc")
    }
    return a
}

final class WizardGatingTests: XCTestCase {

    func testEmptyProjectOnlyStage1() {
        let a = artefacts()
        XCTAssertTrue(WizardGating.isUnlocked(.generate, artefacts: a))
        XCTAssertTrue(WizardGating.isUnlocked(.calibrate, artefacts: a))
        for s in [WizardStage.layOutPrint, .measure, .buildProfile, .verifyInstall] {
            XCTAssertFalse(WizardGating.isUnlocked(s, artefacts: a), "\(s) should be locked")
        }
    }

    func testTi1UnlocksStage2Only() {
        let a = artefacts(ti1: true)
        XCTAssertTrue(WizardGating.isUnlocked(.layOutPrint, artefacts: a))
        XCTAssertFalse(WizardGating.isUnlocked(.measure, artefacts: a))
        XCTAssertFalse(WizardGating.isUnlocked(.buildProfile, artefacts: a))
        XCTAssertFalse(WizardGating.isUnlocked(.verifyInstall, artefacts: a))
    }

    func testStage3NeedsTi1AndTi2() {
        XCTAssertFalse(WizardGating.isUnlocked(.measure, artefacts: artefacts(ti2: true)))
        XCTAssertTrue(WizardGating.isUnlocked(.measure, artefacts: artefacts(ti1: true, ti2: true)))
    }

    func testStage4NeedsTi3NotTi2() {
        // #109/#110: .ti2 alone must never unlock Stage 4.
        let a = artefacts(ti1: true, ti2: true)
        XCTAssertFalse(WizardGating.isUnlocked(.buildProfile, artefacts: a))
        XCTAssertTrue(WizardGating.isUnlocked(.buildProfile, artefacts: artefacts(ti3: true)))
    }

    func testStage5NeedsTi3AndProfile() {
        XCTAssertFalse(WizardGating.isUnlocked(.verifyInstall, artefacts: artefacts(ti3: true)))
        XCTAssertFalse(WizardGating.isUnlocked(.verifyInstall, artefacts: artefacts(profile: true)))
        XCTAssertTrue(WizardGating.isUnlocked(
            .verifyInstall, artefacts: artefacts(ti3: true, profile: true)
        ))
    }

    func testForwardGatedBackwardFree() {
        let a = artefacts()
        XCTAssertFalse(WizardGating.canNavigate(to: .layOutPrint, from: .generate, artefacts: a))
        // Backward always allowed even when artefacts vanished.
        XCTAssertTrue(WizardGating.canNavigate(to: .generate, from: .measure, artefacts: a))
        // Same stage is a no-op.
        XCTAssertTrue(WizardGating.canNavigate(to: .measure, from: .measure, artefacts: a))
        // Stage 0 is a side-trip, never gated.
        XCTAssertTrue(WizardGating.canNavigate(to: .calibrate, from: .generate, artefacts: a))
    }

    func testDeepestUnlocked() {
        XCTAssertEqual(WizardGating.deepestUnlocked(artefacts: artefacts()), .generate)
        XCTAssertEqual(WizardGating.deepestUnlocked(
            artefacts: artefacts(ti1: true, ti2: true)
        ), .measure)
        XCTAssertEqual(WizardGating.deepestUnlocked(
            artefacts: artefacts(ti3: true, profile: true)
        ), .verifyInstall)
    }
}

final class WizardStateStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-wiz-\(UUID().uuidString)")
            .appendingPathComponent("wizard_state.json")
    }

    func testRoundTrip() throws {
        let url = tempURL()
        let store = WizardStateStore(fileURL: url)
        var s = WizardState()
        s.currentStage = 3
        s.basename = "run-42"
        s.cwd = "/tmp/charts"
        s.sessionMode = .calibration
        s.profileBasename = "imported"
        s.calibrationOriginalBasename = "pre-cal"
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testMissingFileDefaults() {
        let s = WizardStateStore(fileURL: tempURL()).load()
        XCTAssertEqual(s, .default)
        XCTAssertEqual(s.stage, .generate)
        XCTAssertEqual(s.sessionMode, .profile)
    }

    func testCorruptStageFallsBackToGenerate() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try #"{"current_stage": 99, "basename": "", "cwd": "", "session_mode": "profile"}"#
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(WizardStateStore(fileURL: url).load().stage, .generate)
    }

    func testCorruptJsonReturnsDefaultAndKeepsBytes() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(WizardStateStore(fileURL: url).load(), .default)
        let kept = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(kept, "not json")
    }

    func testSessionModeCalibrationRoundTrips() throws {
        var s = WizardState(sessionMode: .calibration)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(WizardState.self, from: data)
        XCTAssertEqual(decoded.sessionMode, .calibration)
        s.sessionMode = .profile
        XCTAssertEqual(s.sessionMode, .profile)
    }
}
