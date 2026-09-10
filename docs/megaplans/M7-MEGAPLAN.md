# M7 megaplan — UAT-ready

## 0. Baseline SHA + Phase 0 shipped/missing table

**Baseline:** `origin/develop` at `c5fc89ec409c941c0bf619a851c12c8384afa204` (post-PR #66 M6 merge; workflows temporarily disabled by `c5fc89e`).

### Phase 0 shipped/missing audit

| Ref | Pre-UAT item | Status on `origin/develop` | Evidence |
|-----|--------------|----------------------------|----------|
| S0 | `ProcessManager` `waitUntilExit()` after `process.run()` in `runStreaming` / `runCaptured`; `TargetWorkflowViewModel.printTask` strong reference. | **SHIPPED** | Commit `1d9c6ae` (`fix: harden process termination and retain print task`), merged by `18767c2` / `bc5c038`. `ProcessManager.swift:185-189` and `288-291` contain the `Task.detached { process.waitUntilExit() … }` fallbacks. `TargetWorkflowViewModel.swift:114` declares `private var printTask` and assigns it in `printAllPages` / `printPage`. |
| S2 | Persisted `calibrationOriginalBasename`; refuse `.buildProfile` while basename has `CAL_` prefix. | **MISSING** | `CalibrationViewModel.swift:30` uses an in-memory `private var originalBasename`. `WizardViewModel.go(to:)` does not refuse `.buildProfile` / `.verifyInstall` / `.generate` for `CAL_` basenames. Open PR #69 (`fix/29-cal-basename-restore`, head `b527207`) contains the fix. |
| S3 | `GamutSceneView.dismantleNSView` `isPlaying = false`; OOB face guard. | **MISSING** | `GamutView.swift` has no `dismantleNSView` and no OOB face-index guard in `scnGeometry`. Open PR #70 (`fix/28-gamut-pause`, head `87e4f4f`) contains the fix. |
| S1/4 | `docs/PREUAT.md` tester kit. | **MISSING** | `git ls-tree -r origin/develop` has no `docs/PREUAT.md`. Open PR #71 (`docs/preuat-tester-kit`, head `f47b642`) adds it. |
| CI | `.gitea/workflows/macos.yml` uses `CODE_SIGNING_ALLOWED=YES` and `CODE_SIGN_IDENTITY='-'` on `xcodebuild test`; `pull_request`/`push` includes `develop`. | **CONTENT CORRECT, PATH DISABLED** | `.gitea/workflows.disabled/macos.yml` on `develop@c5fc89e` already contains `push`/`pull_request: [develop]`, `runs-on: macos-14`, `CODE_SIGNING_ALLOWED=YES`, `CODE_SIGN_IDENTITY='-'`, `CODE_SIGNING_REQUIRED=YES`, and the `xattr -cr` + `codesign --options runtime` post-build block. The file is under `.gitea/workflows.disabled/`, so Gitea will not run it. |

### Other Phase 0 findings

- **Open PRs into `develop` (Gitea):** #69 `fix/29-cal-basename-restore`, #70 `fix/28-gamut-pause`, #71 `docs/preuat-tester-kit`. All are `mergeable: true` against `develop@c5fc89e`.
- **Remote branches (`git ls-remote --heads origin`):** `develop`, `docs/preuat-tester-kit`, `fix/28-gamut-pause`, `fix/29-cal-basename-restore`, `fix/process-wait-and-print-task`, `main`.
- **Default branch:** `origin/HEAD` still points to `main`.
- **`docs/megaplans/` on `origin/develop`:** `M6-BRANCH-MAP.md`, `M6-MEGAPLAN.md`, `M6-RISK-REGISTER.md`.
- **Local-only planning docs:** `PREUAT-MEGAPLAN.md`, `PREUAT-BRANCH-MAP.md`, `PREUAT-RISK-REGISTER.md`, `M7_MEGAPLAN_PROMPT.md`. Per clarifying answer, these are **not** committed to `develop` in U4.

## 1. Decision log

| ID | Decision | Why |
|----|----------|-----|
| D1 | **#16 / `ICCeryPrintKit` / TargetPrint is v2.1**, not M7. | M7 is UAT-ready hardening of existing v2.0 paths; Quartz/AirPrint/ColorSync print dictionaries are a later milestone. |
| D2 | Keep **macOS 14.0 + Swift 6**; do not retarget to Monterey 12 / Xcode 14.2. | `project.yml` is already at `MACOSX_DEPLOYMENT_TARGET: "14.0"` and `SWIFT_VERSION: "6.0"`. |
| D3 | **App Sandbox OFF; Hardened Runtime ON; Debug `CODE_SIGN_IDENTITY` stays `"-"`**. | `project.yml` and `ICCery.entitlements` already reflect this; no `project.yml` change for a real Developer ID in Debug. |
| D4 | **Do not merge `main` (`d37dced`) into `develop`**. | `main` is stale and has a full README not on `develop`; useful text is hand-synced in a tiny `docs/readme-sync` commit. |
| D5 | **Re-use the three open Pre-UAT PRs (#69, #70, #71)** as M7 U2/U3 slices. | They already exist, target `develop`, and implement the exact `PREUAT-MEGAPLAN.md` contracts. |
| D6 | **Do not rebase `fix/29-cal-basename-restore` to drop its workflow-disabled rename; keep the workflow disabled in that branch.** | The rename results in the same `.gitea/workflows.disabled/macos.yml` path as `develop`, so PR #69 remains mergeable. U1 re-enables CI afterwards. |
| D7 | **U1 re-enables CI by moving the existing `.gitea/workflows.disabled/macos.yml` to `.gitea/workflows/macos.yml`, keeping `runs-on: macos-14` and the ad-hoc sign block.** | The disabled file content already matches the contract; the user confirmed `macos-14` should be kept. Do not use the local `fix/process-wait-and-print-task@3f09e69` `runs-on: macos` variant. |
| D8 | **U5 small UAT polish is split into three separate optional PRs**, each landed only if cheap and only after U1–U3 are green. | Per clarifying answer; each item must stay under ~4 files and is not bundled with process/calibration branches. |
| D9 | **Do not add `docs/megaplans/PREUAT-*.md` or the new `M7-*.md` files to `develop` in U4.** | Per clarifying answer; planning docs remain local planning deliverables. U4 still handles README sync and stale branch deletion. |
| D10 | **No `milestone/m7-*` integration branch; all PRs target `develop` directly.** | M7 is a small set of parallel fixes/docs; an umbrella branch adds unnecessary rebasing. |
| D11 | **Set Gitea default branch to `develop` and reset/delete `main`** as a human-owned U4 gate. | `origin/HEAD` is still `main`; `main` is stale and has unique README text that must be hand-synced first. |

## 2. Slices U1–U6

### U1 — CI re-enable (P0)

- **Branch:** `fix/32-ci-adhoc-sign` (new)
- **Base:** `develop` **after** U3b/#69 lands (avoids a workflow rename/rename conflict; see D6)
- **Files:** `.gitea/workflows/macos.yml` (moved from `.gitea/workflows.disabled/macos.yml`)
- **In:**
  - `git mv .gitea/workflows.disabled/macos.yml .gitea/workflows/macos.yml`
  - Keep existing content: `push`/`pull_request: [develop]`, `runs-on: macos-14`
  - `xcodebuild build-for-testing` and `xcodebuild test` with `CODE_SIGNING_ALLOWED=YES`, `CODE_SIGN_IDENTITY='-'`, `CODE_SIGNING_REQUIRED=YES`
  - `xattr -cr` + `codesign -f -s - --options runtime --entitlements Resources/ICCery.entitlements` on `ICCery.app` **only**; let `xcodebuild` sign `*Runner.app` with its generated `xctrunner` entitlements
  - `package` job runs only on `refs/heads/develop` or `refs/tags/v`
- **Out:** `CODE_SIGNING_ALLOWED=NO`; changing `project.yml` `CODE_SIGN_IDENTITY`; enabling App Sandbox; using `runs-on: macos`
- **PR:** target `develop`, labels `Project/ICCery-v2`, `Bug/CI`, `Priority/P0`
- **Verify:** after merge, a `push` to `develop` should trigger Gitea Actions and the `build-and-test` job should start. Follow up with a human if the runner label `macos-14` is not registered.

### U2 — Tester kit (P0)

- **Branch:** `docs/preuat-tester-kit` (already open as PR #71)
- **File:** `docs/PREUAT.md`
- **In:** existing PR body is correct; covers build instructions, paths A–H, #24 policy, `CAL_` vs profile name, Cancel vs Force Quit, Gatekeeper, `package-release.sh` secrets, CI ad-hoc sign note.
- **Out:** product code, `project.yml`, README, `BUILD-PLAN.md`, CI workflow edits
- **Action:** review/merge PR #71; add labels `Project/ICCery-v2`, `Feature/Docs`, `Priority/P0` if missing.
- **Verify:** `docs/PREUAT.md` exists on `develop` and paths A–H match the prompt wording.

### U3 — Pre-UAT code leftovers

#### U3a — Process wait / print task (already shipped)

No M7 branch. Verified in Phase 0.

#### U3b — `CAL_` basename restore (P0)

- **Branch:** `fix/29-cal-basename-restore` (already open as PR #69)
- **Base:** current `develop` (mergeable per Gitea)
- **Files:** `Packages/ICCeryCore/Sources/ICCeryCore/Wizard/WizardState.swift`, `Sources/ICCery/CalibrationViewModel.swift`, `Sources/ICCery/WizardViewModel.swift`, `Tests/ICCeryCoreTests/WizardCalibrationSessionTests.swift`, `Tests/ICCeryCoreTests/WizardGatingTests.swift`
- **In (per `PREUAT-MEGAPLAN.md` Slice 2):**
  - Add `calibrationOriginalBasename` to `WizardState` / `WizardViewModel`, persisted with the same store.
  - `enterCalibration()` sets `calibrationOriginalBasename = basename`.
  - Restore on cancel, successful `printcal`, relaunch, and before any `go(to:)` that is not `.calibrate`.
  - Refuse `.buildProfile` / `.verifyInstall` / `.generate` while `basename` has prefix `CAL_`.
  - Do not overload `profileBasename`.
- **Out:** `CapturedBuffer`/readabilityHandler rewrite; new calibration UI; `PrinttargArgs` guard changes.
- **Action:** merge PR #69; add labels `Project/ICCery-v2`, `Bug/Calibration`, `Priority/P0` if missing.
- **Verify:** `WizardCalibrationSessionTests` passes; the diff does not re-enable the workflow (remains `.gitea/workflows.disabled`).

#### U3c — Gamut pause (P1)

- **Branch:** `fix/28-gamut-pause` (already open as PR #70)
- **Base:** current `develop` (mergeable per Gitea)
- **Files:** `Sources/ICCery/GamutView.swift`, `Tests/ICCeryCoreTests/GamutGeometryBuilderTests.swift`
- **In (per `PREUAT-MEGAPLAN.md` Slice 3):**
  - `GamutSceneView.dismantleNSView` sets `scnView.isPlaying = false` on sheet dismiss.
  - `GamutSceneGeometryBuilder` drops faces whose indices are `>= vertices.count` before building `SCNGeometryElement`.
  - Edge-line construction filters OOB faces.
- **Out:** Scene cache, camera rewrite, Metal/WebGL.
- **Action:** merge PR #70; add labels `Project/ICCery-v2`, `Bug/Viewer`, `Priority/P1` if missing.
- **Verify:** `GamutGeometryBuilderTests` passes; gamut sheet opens/closes without GPU hang.

### U4 — Repo cleanup (required)

- **Branch:** `chore/m7-repo-hygiene` (new)
- **Base:** `develop` after U1–U3 have landed
- **In:**
  - **README sync:** `main` (`d37dced`) has a full product README; `develop` has only `# iccery-v2-mac`. Hand-port the useful sections (product summary, build/test instructions, architecture, instruments, docs index, licence) into `README.md` on `develop` in a single `docs/readme-sync` commit. Do **not** mention stale `milestone/m6-gamut-stage0-cgats-release` or `Default branch: main`; use `Default branch: develop`.
  - **Default branch gate (human-owned):** in the Gitea UI, set the repository default branch to `develop`. Then delete or force-reset `main` to `develop` (do not merge). Command: `git push origin +develop:main` to reset, or `git push origin --delete main` if deleting.
  - **Stale remote branches:** delete `fix/process-wait-and-print-task` (tip `196c51d` is an ancestor of `develop` and the branch is stale). After the PRs above land, also delete `fix/28-gamut-pause`, `fix/29-cal-basename-restore`, and `docs/preuat-tester-kit`.
  - **Local stale branches:** the user may optionally prune `[gone]` local `feat/*` and `milestone/*` branches with `git remote prune origin`.
- **Out:** `main` → `develop` merge; committing `docs/megaplans/PREUAT-*.md` or `M7-*.md` to `develop` (per D9); pushing `fix/process-wait-and-print-task` or old `e547585` riders.
- **Verify:** `git ls-remote --heads origin` shows only `develop` (and release tags); Gitea default branch is `develop`; `README.md` on `develop` is useful.

### U5 — Small UAT polish (optional, split per user choice)

Only if cheap; each branch ≤4 files. Do **not** put on process or calibration branches. Land last.

#### U5a — About accessibility identifiers

- **Branch:** `fix/m7-about-a11y`
- **Files:** `Sources/ICCery/AboutView.swift` (and any related test)
- **In:** restore accessibility identifiers dropped with `78b807d` if VoiceOver testing is scheduled in week 1.
- **Out:** full About rewrite.

#### U5b — `killAll` quit notice

- **Branch:** `fix/m7-killall-notice`
- **Files:** `Sources/ICCery/AppDelegate.swift` or `WizardViewModel`, small UI
- **In:** show an in-app notice "stopping instruments…" while `ProcessManager.killAll()` runs on app quit so testers do not Force Quit.
- **Out:** changing `killAll` semantics; blocking the main thread.

#### U5c — UITest `runningForeground` wait

- **Branch:** `fix/m7-uitest-foreground`
- **Files:** `Tests/ICCeryUITests/...` (≤4 files)
- **In:** add a `runningForeground` wait helper to the UI test launch path.
- **Out:** bundling with U1; large test refactor.
- **Gate:** only if CI still flakes after U1.

### U6 — Hardware / release gates (checklist, not code)

Human-owned gate table before UAT:

| # | Gate | Owner |
|---|------|-------|
| 1 | Unlocked Sonoma Mac; instrument plugged in before launch | Tester |
| 2 | Bundled `instlist` / `chartread` pass `codesign -dvv` (not `$PATH`) | CI / packager |
| 3 | Paths A–E green before F–H | Tester |
| 4 | Notarized DMG `spctl --assess` before any "clean Mac" tester | Release engineer |
| 5 | One real printer Stage 0 + one real profile `.gam` in SceneKit | Tester |

## 3. Tester paths A–H mapped to slices

| Path | Week | Action | Depends on | Pass criteria |
|------|------|--------|------------|---------------|
| A | 1 | Stage 1 generate → Stage 2 print one page → cancel | S0 (shipped), U1 | Print panel appears, app returns cleanly, `printTask` retained, CI green |
| B | 1 | Handheld chartread one sheet → Finish & Average | S0 (shipped) | `.ti3` produced |
| C | 1 | Create profile, Apply Calibration off | #24 policy (shipped) | `iccgamut` fail/info banner, still advances to Stage 5 |
| D | 1 | Create profile, Apply Calibration on, missing/bad `.cal` | #24 / `applycal` guard (shipped) | Does not advance to Stage 5 |
| E | 1 | Stage 5 profcheck + user vs system install / overwrite | develop (M5) | `profcheck` completes, profile installed in chosen scope, overwrite works |
| F | 2 | Stage 0 full loop; restore non-`CAL_` basename; `-K` only on profile `printtarg` | U3b (#69) | `CAL_` never bleeds into `colprof`; `CAL_*.ti3` not fed to `colprof` |
| G | 2 | Import Dataset open panel (`.ti3`/`.txt`/`.cgats`/`.csv`), not save-`.ti1` | #30 (shipped) | Imported `.ti3`/dataset accepted; wizard skips print/measure |
| H | 2 | View Gamut + sRGB overlay + reset camera | U3c (#70) | No GPU hang, camera resets, app responsive |

## 4. Cleanup command list

Commands to run after all M7 PRs are merged:

```bash
# 1. Confirm current remote heads
git ls-remote --heads origin

# 2. Delete the stale ancestor branch (do not push any new code from it)
git push origin --delete fix/process-wait-and-print-task

# 3. After PR #69, #70, #71 are merged, delete their remote branches
git push origin --delete fix/29-cal-basename-restore
git push origin --delete fix/28-gamut-pause
git push origin --delete docs/preuat-tester-kit

# 4. Human: in Gitea UI, set the repository default branch to `develop`.

# 5. Reset `main` to `develop` (or delete it) — do NOT merge
git fetch origin
git push origin +develop:main   # reset main to current develop
# OR
git push origin --delete main   # delete main entirely

# 6. Prune local [gone] tracking branches
git remote prune origin

# 7. Verify
git ls-remote --heads origin
git remote show origin | grep 'HEAD branch'
```

**Keep `develop`.** Never push `fix/process-wait-and-print-task` or old `e547585` riders.

## 5. Non-goals

- No #16 / `ICCeryPrintKit` / `TargetPrint` / Quartz / AirPrint detector in M7.
- No macOS 12 / Xcode 14.2 retarget; keep macOS 14 + Swift 6.
- No App Sandbox ON; no `$PATH` Argyll search; no `applycal -u`; no `CAL_` `printtarg -K`.
- No merging `main` into `develop`.
- No new M8 feature milestone inside this plan.
- No full `xcodebuild test` suite run during the planning step.
- No `CapturedBuffer` rewrite of `runCaptured`.
- No `project.yml` deployment target or `CODE_SIGN_IDENTITY` real-cert changes.
