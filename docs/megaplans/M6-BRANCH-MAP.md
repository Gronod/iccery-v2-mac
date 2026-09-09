# M6 Branch Map

## Milestone topology

```
develop@629a1fce
  └── milestone/m6-gamut-stage0-cgats-release   # cut AFTER Gitea #24 AC update (done 2026-09-09T16:02:25Z)
        ├── feat/31-about-help-chrome          → resolves issue #31
        ├── feat/30-cgats-interop              → resolves issue #30
        ├── feat/29-stage0-calibration         → resolves issue #29
        ├── feat/28-scenekit-gamut             → resolves issue #28
        └── feat/32-packaging-ci               → resolves issue #32 (rebase last)
```

- All feature branches are parallel children of `milestone/m6-gamut-stage0-cgats-release`.
- No nested feature branches. `feat/28` does **not** depend on `feat/29` or `feat/30`; it depends only on `develop` (#3, #24).
- If two feature branches are ready in the same week, the second one rebases onto the current milestone tip before PR; the milestone branch is the only integration branch.
- Final merge: `milestone/m6-gamut-stage0-cgats-release` → `develop` after the full CI gate is green.

## PR convention

- Each PR title uses the feature branch name and states it **resolves** the tracked issue:  
  `feat/31-about-help-chrome → PR targeting milestone/m6-gamut-stage0-cgats-release, resolves issue #31`
- Same pattern for `feat/30` (resolves #30), `feat/29` (resolves #29), `feat/28` (resolves #28), `feat/32` (resolves #32).
- Gitea PR numbers will **not** be #28–#32; those are issue numbers. Use the next available PR numbers (current tip is #54).
- Every PR carries labels: `Project/ICCery-v2`, a `Feature/*` or `Bug/*` label, and a `Priority/*` label.

## Slice commit order inside each feature branch

| Branch | Slice order | Rationale |
|--------|-------------|-----------|
| `feat/30-cgats-interop` | 30a parser → 30b writer → 30c open-dialog import | Lower layers first; UI only after parser/writer green. |
| `feat/29-stage0-calibration` | 29a argv goldens → 29b store/curve → 29c dashboard → 29d apply toggle | Args contracts first; UI last. |
| `feat/28-scenekit-gamut` | 28a asset confirm + real-file fixture → 28b parser → 28c SceneKit view | Confirm real `sRGB.gam` before any `SCNView` type exists. |
| `feat/31-about-help-chrome` | Single slice | UI chrome only; no lower layers. |
| `feat/32-packaging-ci` | Single slice, last | Rebase on milestone tip after all other branches land. |

## Merge rules

1. `milestone/m6-gamut-stage0-cgats-release` is created only after the Phase 0 cut checklist passes. Gitea #24 was updated at 2026-09-09T16:02:25Z.
2. #31, #30, #29, #28 may merge into the milestone branch in any order once green.
3. #32 merges into the milestone branch **last** and only after a successful rebase.
4. No `feat/52-*` / `feat/m6-bugfixes` umbrella branches.
5. Any new M5 residual discovered after the cut gets a single `fix/<issue#>-<slug>` branch off `milestone/m6-gamut-stage0-cgats-release` (or `develop` if the cut has not happened yet).
