import Foundation

/// Artefact-driven stage gating (issue #4, docs/06 §Stages).
///
/// Navigation is *disk*, not buttons: a stage unlocks only when its
/// predecessor artefacts exist. Forward moves are gated; backward is
/// always allowed. Gating is re-evaluated on window focus and on stage
/// entry (#151 — files can disappear in Finder).
public enum WizardGating {

    /// Whether `stage` is reachable given the probed artefacts.
    ///
    /// - Stage 0 (calibrate): always — it is out-of-band, not gated.
    /// - Stage 1: always.
    /// - Stage 2: `.ti1` exists.
    /// - Stage 3: `.ti1` **and** `.ti2`.
    /// - Stage 4: `.ti3` exists (accepted measurement only — a `.ti2`
    ///   alone never unlocks it; #109/#110).
    /// - Stage 5: `.ti3` **and** `.icc`/`.icm`.
    public static func isUnlocked(
        _ stage: WizardStage,
        artefacts: StageArtefacts
    ) -> Bool {
        switch stage {
        case .calibrate:     return true
        case .generate:      return true
        case .layOutPrint:   return artefacts.stage1Complete
        case .measure:       return artefacts.stage1Complete && artefacts.stage2Complete
        case .buildProfile:  return artefacts.stage3Complete
        case .verifyInstall: return artefacts.stage3Complete && artefacts.stage4Complete
        }
    }

    /// Whether `go(to:)` may proceed. Backward moves and the current
    /// stage are always allowed; forward moves must be unlocked.
    public static func canNavigate(
        to target: WizardStage,
        from current: WizardStage,
        artefacts: StageArtefacts
    ) -> Bool {
        if target == current { return true }
        if target == .calibrate || current == .calibrate {
            // Stage 0 is a side-trip, not stepper navigation.
            return true
        }
        if target.rawValue < current.rawValue { return true }
        return isUnlocked(target, artefacts: artefacts)
    }

    /// The deepest unlocked stepper stage — used when revalidation
    /// locks the current stage (#151).
    public static func deepestUnlocked(artefacts: StageArtefacts) -> WizardStage {
        for stage in WizardStage.stepperStages.reversed()
        where isUnlocked(stage, artefacts: artefacts) {
            return stage
        }
        return .generate
    }
}
