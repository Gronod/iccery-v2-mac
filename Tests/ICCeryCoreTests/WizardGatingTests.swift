import Testing
import Foundation
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

@Suite("WizardGating matrix")
struct WizardGatingTests {

    @Test func emptyProjectOnlyStage1() {
        let a = artefacts()
        #expect(WizardGating.isUnlocked(.generate, artefacts: a))
        #expect(WizardGating.isUnlocked(.calibrate, artefacts: a))
        for s in [WizardStage.layOutPrint, .measure, .buildProfile, .verifyInstall] {
            #expect(!WizardGating.isUnlocked(s, artefacts: a), "\(s) should be locked")
        }
    }

    @Test func ti1UnlocksStage2Only() {
        let a = artefacts(ti1: true)
        #expect(WizardGating.isUnlocked(.layOutPrint, artefacts: a))
        #expect(!WizardGating.isUnlocked(.measure, artefacts: a))
        #expect(!WizardGating.isUnlocked(.buildProfile, artefacts: a))
        #expect(!WizardGating.isUnlocked(.verifyInstall, artefacts: a))
    }

    @Test func stage3NeedsTi1AndTi2() {
        #expect(!WizardGating.isUnlocked(.measure, artefacts: artefacts(ti2: true)))
        #expect(WizardGating.isUnlocked(.measure, artefacts: artefacts(ti1: true, ti2: true)))
    }

    @Test func stage4NeedsTi3NotTi2() {
        // #109/#110: .ti2 alone must never unlock Stage 4.
        let a = artefacts(ti1: true, ti2: true)
        #expect(!WizardGating.isUnlocked(.buildProfile, artefacts: a))
        #expect(WizardGating.isUnlocked(.buildProfile, artefacts: artefacts(ti3: true)))
    }

    @Test func stage5NeedsTi3AndProfile() {
        #expect(!WizardGating.isUnlocked(.verifyInstall, artefacts: artefacts(ti3: true)))
        #expect(!WizardGating.isUnlocked(.verifyInstall, artefacts: artefacts(profile: true)))
        #expect(WizardGating.isUnlocked(
            .verifyInstall, artefacts: artefacts(ti3: true, profile: true)
        ))
    }

    @Test func forwardGatedBackwardFree() {
        let a = artefacts()
        #expect(!WizardGating.canNavigate(to: .layOutPrint, from: .generate, artefacts: a))
        // Backward always allowed even when artefacts vanished.
        #expect(WizardGating.canNavigate(to: .generate, from: .measure, artefacts: a))
        // Same stage is a no-op.
        #expect(WizardGating.canNavigate(to: .measure, from: .measure, artefacts: a))
        // Stage 0 is a side-trip, never gated.
        #expect(WizardGating.canNavigate(to: .calibrate, from: .generate, artefacts: a))
    }

    @Test func deepestUnlocked() {
        #expect(WizardGating.deepestUnlocked(artefacts: artefacts()) == .generate)
        #expect(WizardGating.deepestUnlocked(
            artefacts: artefacts(ti1: true, ti2: true)
        ) == .measure)
        #expect(WizardGating.deepestUnlocked(
            artefacts: artefacts(ti3: true, profile: true)
        ) == .verifyInstall)
    }
}

@Suite("WizardStateStore")
struct WizardStateStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-wiz-\(UUID().uuidString)")
            .appendingPathComponent("wizard_state.json")
    }

    @Test func roundTrip() throws {
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
        #expect(store.load() == s)
    }

    @Test func missingFileDefaults() {
        let s = WizardStateStore(fileURL: tempURL()).load()
        #expect(s == .default)
        #expect(s.stage == .generate)
        #expect(s.sessionMode == .profile)
    }

    @Test func corruptStageFallsBackToGenerate() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try #"{"current_stage": 99, "basename": "", "cwd": "", "session_mode": "profile"}"#
            .write(to: url, atomically: true, encoding: .utf8)
        #expect(WizardStateStore(fileURL: url).load().stage == .generate)
    }

    @Test func sessionModeCalibrationRoundTrips() throws {
        var s = WizardState(sessionMode: .calibration)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(WizardState.self, from: data)
        #expect(decoded.sessionMode == .calibration)
        s.sessionMode = .profile
        #expect(s.sessionMode == .profile)
    }
}
