# M6 megaplan

## 0. Baseline + Phase 0 audit table + cut checklist

**Baseline:** `develop` at `629a1fce` (PR #54, includes `ef56cdd7` from PR #53).  
**Milestone issues:** #28, #29, #30, #31, #32.  
**Out of scope:** #16 (`ICCeryPrintKit`), Windows/Linux-specific print/INF paths, Metal/WebGL/Three.js rewrites, `WKWebView`, linking Argyll.

### Phase 0 audit table

| Ref | Item | Status | Evidence |
|-----|------|--------|----------|
| #50.1 | `ArgyllRunner.runChartread` yields `.prompt` for handheld calibrate → trigger → done | **FIXED** | `ArgyllRunner.swift` compares `previous` and `classified.state`; `Milestone4UITests.testHandheldFixtureChartreadAndAverage` is unskipped and green. |
| #50.2 | `ChartreadClassifier` matcher order: error strings not misclassified as `awaitingStrip` | **FIXED** | Priority table in `ChartreadClassifier.swift`; 39+ fixture tests. |
| #50.3 | Stage 3 control matrix: one visible primary action per state, no Skip/Undo | **FIXED** | `Stage3View.swift` buttons `btnCalibrate`, `btnTrigger`, `btnDoneRead`, `btnRetry`, `btnFinishAndAverage`. |
| #50.4 | `btnFinishAndAverage` gated on a non-empty `passSnapshots` | **FIXED** | `MeasurementWorkflowViewModel.canFinish`. |
| #50.5 | Chartread child lifetime: cancel previous session, park XY on quit | **FIXED** | `ProcessManager.runChartread` preKill hook sends `q\n`, waits ~500ms, then kills; `AppDelegate.applicationShouldTerminate` calls `ProcessManager.killAll()`. |
| #50.6 | `collect()` returns even if a pipe EOF never arrives after process exit | **FIXED** | `ProcessManager` two-second watchdog after `didTerminate` plus `forceKill`/`forceFinalize`. |
| #50.7 | Killing captured `applycal` never replaces the input profile | **FIXED** | `ArgyllRunner.runApplycal` writes to `{input}.applycal.tmp` and only `replaceItemAt` on success; cancellation removes the temp. |
| #50.8 | `killAll` on quit covers `colprof_*`, `iccgamut_*`, `profcheck_*`, `applycal_*`, `chartread_*` | **FIXED** | `ProcessManager.children`/`captured` keyed by `ProcessID`; `killAll()` iterates all. |
| #52.1 | Profile installer **Overwrite** from the collision alert works | **FIXED** | `ProfileWorkflowViewModel.resolveInstallCollision(policy: .overwrite)` sets `options.forceOverwrite = true`. |
| #52.2 | `VerificationHistoryStore.append` no longer wipes the file | **FIXED** | `append()` calls `load()` first; tests in `VerificationHistoryStoreTests.swift`. |
| #52.3 | `createdProfileURL` restored from disk after relaunch | **FIXED** | `ProfileWorkflowViewModel.restoreCreatedProfileURL()` uses `ArtefactProbe.resolveProfile`; `Stage4View.onAppear` calls it. |
| #52.4 | Drift alert is consecutive and profcheck warning is not hidden | **FIXED** | `DriftAlert.compute` builds the longest suffix run of `.poor` records; `Stage5View` displays both `driftAlert` and `profcheckWarningBanner`. |
| #52.5 | Empty `printerName` rendered as "Unknown" everywhere | **FIXED** | `makeVerificationRecord` uses `wizard.printerName?.isEmpty == false ? … : "Unknown"`. |
| #52.6 | `ApplycalArgsTests.unapplyNotEmitted` renamed / guarded | **FIXED** | `ApplycalArgsTests` includes `unapplyNeverEmittedByUI`; `ProfileWorkflowViewModel` never passes `unapply: true`. |
| #52.7 | Profile installer preserves `.icm` and allows `foo..bar` stems | **FIXED** | `ProfileInstaller` uses `sourceURL.lastPathComponent`; stem validation rejects only literal `.`/`..` components. |
| #52.8 / #24 | `iccgamut` failure vs. issue #24 "`.gam` produced next to profile" | **FIXED-BY-POLICY** | Update Gitea issue #24 acceptance criteria **before `milestone/m6-gamut-stage0-cgats-release` is cut** (no code branch). See §1. |

### Pre-cut checklist

Must pass **before** `milestone/m6-gamut-stage0-cgats-release` is created:

- [x] Confirmed 2026-09-09T16:02:25Z — Gitea #24 body contains the FIXED-BY-POLICY failure-path paragraph from §1.
- [ ] Human confirms `Tests/ICCeryUITests/Milestone4UITests.swift` line 95 `testHandheldFixtureChartreadAndAverage` is **not** wrapped in `XCTSkip` or `XCTExpectFailure`.
- [ ] Human confirms `Sources/ICCery/ProfileWorkflowViewModel.swift` `resolveInstallCollision(policy: .overwrite)` (around line 442) sets `options.forceOverwrite = true`.

If either spot-check fails, Phase 0 is not empty. Record a residual row and open a single `fix/50-chartread-prompt-stream` or `fix/27-install-overwrite` branch off `develop` (or off the milestone branch if already cut). Do **not** reopen `feat/52-m5-bugfixes` and do not file a new umbrella issue.

---

## 1. #24 FIXED-BY-POLICY wording (unchanged)

The following text is now in the Gitea #24 acceptance criteria (confirmed 2026-09-09T16:02:25Z):

> - **Happy path unchanged:** `iccgamut -v -d 10 {resolvedProfile}` writes `{stem}.gam` next to the resolved profile after `colprof` (and `applycal` if Apply Calibration is on) succeeds.
> - **Failure path:** if `iccgamut` exits non-zero or the `.gam` file is missing, show an info banner, but `Create Profile` still advances to Stage 5. The Stage 5 gamut pane falls back to the docs/18 empty state (axes + bundled `sRGB.gam` only, no profile mesh).
> - Do not treat a mock `.gam` in `Milestone5UITests` as proof of extraction.
> - `applycal` is different: if **Apply Calibration** is on and `applycal` fails, `Create Profile` fails and does not advance, because `applycal` mutates the ICC.

This is a tracker-only policy change; there is no `fix/24-gamut-failure` branch.

---

## 2. Feature slices

One feature branch per issue. Work inside each branch is split into **named slices** that can each be a commit (or stacked PR into the same feat branch), each with its own test command and ≤4 files / ≤200 added lines.

### 2.1 #31 — About & Help Chrome

- **Branch:** `feat/31-about-help-chrome`
- **Base:** `milestone/m6-gamut-stage0-cgats-release`
- **Depends on:** #1, #5 (already on `develop`)
- **Files**
  - `Sources/ICCery/AboutView.swift` (new)
  - `Sources/ICCery/HelpOverlayView.swift` (new)
  - `Sources/ICCery/RootView.swift` (mod: replace `Alert` with sheet, wire `openAboutBtn`)
  - `Sources/ICCery/SidebarView.swift` (mod: enable `openAboutBtn`, help toggle)
- **In:** About sheet with version/build date from `getAppInfo`; overlay-positioned tooltips that never reflow layout (`#171`); banner auto-hide (uses existing `Notice.autoHideAfter`).
- **Out:** Settings dialog rebuild.
- **Slice / test:** `xcodebuild test -scheme ICCery -only-testing:ICCeryUITests/AboutHelpUITests -destination 'platform=macOS'`.

### 2.2 #30 — CGATS Dataset Interop

- **Branch:** `feat/30-cgats-interop`
- **Base:** `milestone/m6-gamut-stage0-cgats-release`
- **Depends on:** #4, #6 (already on `develop`)
- **30a — Parser + typed dataset + fixtures**
  - Files: `Packages/ICCeryCore/Sources/ICCeryCore/CGATS/CGATSParser.swift` (parser + `CGATSDataset` types), plus `Tests/ICCeryCoreTests/CGATSParserTests.swift`.
  - Test: `xcodebuild test -scheme ICCery -only-testing:ICCeryCoreTests/CGATSParserTests`.
- **30b — Canonical `.ti3` writer + parse→write→reparse**
  - Files: `Packages/ICCeryCore/Sources/ICCeryCore/CGATS/CGATSWriter.swift`, plus `Tests/ICCeryCoreTests/CGATSWriterTests.swift`.
  - Test: `xcodebuild test -scheme ICCery -only-testing:ICCeryCoreTests/CGATSWriterTests`; must include a fixture that a mock `colprof` can consume.
- **30c — Open-dialog import + `setTarget` before stage jump**
  - Files: `Sources/ICCery/TargetWorkflowViewModel.swift`, `Sources/ICCery/Stage1View.swift`, `Sources/ICCery/FileDialogService.swift` (filter only).
  - Test: `xcodebuild test -scheme ICCery -only-testing:ICCeryUITests/Milestone6CGATSUITests/importUsesOpenPanelNotSaveTi1`.
- **In:** Open dialog (never save) for `.ti3`, `.txt`, `.cgats`, `.csv`; parse CGATS.17 / CTI3 / ISO28178 / CSV; canonical `.ti3` writer with field aliases, 0–255→0–100 device scaling, synthesized `COLOR_REP`/`DEVICE_CLASS`; write imported `.ti3` to cwd and call `setTarget(basename:)` before jumping to Stage 4/5.
- **Out:** Unlocking Stages 1–2 without `.ti1`/`.ti2`; reusing `select_existing_target` / save-`.ti1` picker.
- **What not to touch:** `ProcessManager`, `PrinttargArgs`, `ChartreadClassifier`.

### 2.3 #29 — Stage 0: Printer Calibration

- **Branch:** `feat/29-stage0-calibration`
- **Base:** `milestone/m6-gamut-stage0-cgats-release`
- **Depends on:** #2, #5, #7, #9, #15, #17, #19, #23, #24 (all on `develop` or M5)
- **29a — Argv goldens only**
  - Files: `Packages/ICCeryCore/Sources/ICCeryCore/Argyll/PrintcalArgs.swift`, `Packages/ICCeryCore/Sources/ICCeryCore/Argyll/CalibrationTargenArgs.swift`, plus tests.
  - Test: `xcodebuild test -scheme ICCery -only-testing:ICCeryCoreTests/PrintcalArgsTests -only-testing:ICCeryCoreTests/CalibrationTargenArgsTests`; assert `CAL_` printtarg argv has **no** `-K`.
- **29b — `.cal` parse + `CalibrationStore` + Overwrite/Rename/Cancel**
  - Files: `Packages/ICCeryCore/Sources/ICCeryCore/Calibration/CalibrationStore.swift` (store + curve types), plus `Tests/ICCeryCoreTests/CalibrationStoreTests.swift`.
  - Test: `xcodebuild test -scheme ICCery -only-testing:ICCeryCoreTests/CalibrationStoreTests`.
- **29c — Dashboard + reuse Stage 2/3 with `CAL_` basename**
  - Files: `Sources/ICCery/CalibrationView.swift`, `Sources/ICCery/CalibrationViewModel.swift`, plus small touches to `Sources/ICCery/SidebarView.swift` and `Sources/ICCery/RootView.swift` for the `.calibrate` stage.
  - Test: `xcodebuild test -scheme ICCery -only-testing:ICCeryUITests/Milestone6CalibrationUITests` (walk to `btnCalCompute`).
- **29d — Apply toggle on the profiling basename only**
  - Files: `Sources/ICCery/ProfileWorkflowViewModel.swift` (toggle wiring), `Sources/ICCery/Stage4View.swift` (existing toggle).
  - Test: golden argv tests in `Tests/ICCeryCoreTests/PrinttargArgsTests` (profiling `printtarg` gets `-K`) and `Tests/ICCeryCoreTests/ApplycalArgsTests` (post-`colprof` `applycal -a`; `unapply` never true).
- **In:** `CAL_<run>` dashboard; calibration `targen`; re-use Stage 2 `printtarg` and Stage 3 `chartread`; `printcal` captured; `.cal` CGATS parse + stdout parse; collision; library (`iccery-calibration.json`); Apply Calibration toggle on profiling printtarg (`-K`) and post-colprof `applycal -a`; staleness; curve view.
- **Out:** Display calibration; forking `ChartreadClassifier` / `ProcessManager`; `$PATH` search; `applycal -u`; emitting `-K` for `CAL_` basenames.

### 2.4 #28 — 3D Gamut Viewer (SceneKit)

- **Branch:** `feat/28-scenekit-gamut`
- **Base:** `milestone/m6-gamut-stage0-cgats-release`
- **Depends on:** #3 (real `sRGB.gam` asset), #24 (`.gam` output + updated AC policy)
- **28a — Asset confirm + real-file fixture**
  - Confirmed on `develop@629a1fce`: `Resources/Argyll/reference_gamuts/sRGB.gam` is tracked and contains `NUMBER_OF_SETS 448` vertices and `NUMBER_OF_SETS 892` face rows; it is the real Argyll mesh, not the 8-cusp stub.
  - Add `Tests/ICCeryCoreTests/GamutParserTests.swift` fixture that parses this exact file and asserts the vertex/face counts.
- **28b — `.gam` parser + fixtures**
  - Files: `Packages/ICCeryCore/Sources/ICCeryCore/Profile/GamutParser.swift`, plus tests.
  - Test: `xcodebuild test -scheme ICCery -only-testing:ICCeryCoreTests/GamutParserTests` (dual `BEGIN_DATA`, `#` comments, OOB, vertex-only hull fallback).
- **28c — `GamutView` / `GamutSceneController`, lazy init on Stage 5 appear only**
  - Files: `Sources/ICCery/GamutSceneController.swift`, `Sources/ICCery/GamutView.swift`.
  - Mod: `Sources/ICCery/Stage5View.swift` (embed viewer, trigger load on appear and post-verify).
  - Mod: `Sources/ICCery/ProfileWorkflowViewModel.swift` — **only** a single load hook (Stage 5 appear + post-`iccgamut` / post-`profcheck` success). Scene state lives in `GamutSceneController`.
  - Test: `xcodebuild test -scheme ICCery -only-testing:ICCeryUITests/GamutViewerUITests` (existence of `gamutViewerContainer` and `btnGamutResetCamera`).
- **In:** `.gam` parser (two `BEGIN_DATA` blocks, `#` comments, OOB warnings, native faces, vertex-only → convex-hull fallback); SceneKit with `X=a*`, `Y=L*`, `Z=b*`; axis scaffold; profile mesh with per-vertex Lab→sRGB; sRGB reference overlay; controls; reset camera; lazy init only when Stage 5 visible.
- **Out:** Metal, Three.js, WebGL, Adobe RGB, eager 3D at launch, `ConvexGeometry`/QuickHull for native `.gam` files.
- **What not to touch:** `ProcessManager`, `IccgamutArgs` (density stays `10`), `colprof` argv, `SettingsView`.

### 2.5 #32 — Packaging, Signing & CI

- **Branch:** `feat/32-packaging-ci`
- **Base:** `milestone/m6-gamut-stage0-cgats-release`
- **Depends on:** all v2.0 issues 1–15, 17–31; does **not** block on #16
- **Files**
  - New: `.gitea/workflows/ci.yml`, `scripts/dmgbuild-settings.py`, `scripts/notarize-dmg.sh`
  - Mod: `project.yml` (add `Release` config with configurable `CODE_SIGN_IDENTITY`; keep `Debug` ad-hoc), `Makefile` (add `release-dmg`), `.gitignore`
- **In:** Gitea Actions on self-hosted macOS runner; `scripts/fetch-argyll.sh` before build; universal `xcodebuild build test`; unit and mock fixture tests; `dmgbuild`; notarization/staple gate; signed sidecars (`codesign -dvv` hard fail); artifact upload.
- **Out:** Finder AppleScript DMG, committing `Vendor/Argyll/` binaries, linking Argyll, Windows INF/Linux trees.
- **What not to touch:** App Sandbox, Debug `CODE_SIGN_IDENTITY` real cert, entitlements.
- **Test:** `xcodebuild test -scheme ICCery -destination 'platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO`; `make universal`; `make release-dmg`; `codesign -dvv` on each bundled Mach-O.

---

## 3. Branch topology (parallel feats)

```
develop@629a1fce
  └── milestone/m6-gamut-stage0-cgats-release   # cut AFTER Gitea #24 AC update (done 2026-09-09T16:02:25Z)
        ├── feat/31-about-help-chrome          → resolves issue #31
        ├── feat/30-cgats-interop              → resolves issue #30
        ├── feat/29-stage0-calibration         → resolves issue #29
        ├── feat/28-scenekit-gamut             → resolves issue #28
        └── feat/32-packaging-ci               → resolves issue #32 (rebase last)
```

- All five feature branches are **parallel children** of `milestone/m6-gamut-stage0-cgats-release`.
- Merge order into the milestone branch: #31, #30, #29, #28 may merge independently as each goes green; #32 is rebased on the milestone tip and merged last.
- Final merge: `milestone/m6-gamut-stage0-cgats-release` → `develop` only after the full CI gate is green on the milestone branch.
- If two feat branches land in the same week, the second rebases onto milestone tip; **do not nest feat branches** (e.g. `feat/28` is not a child of `feat/29`).
- Every PR gets labels `Project/ICCery-v2`, a `Feature/*` or `Bug/*` label, and a `Priority/*` label.

---

## 4. Risks

| ID | Risk | Mitigation |
|----|------|------------|
| R1 | **#24 AC not updated in tracker** before the milestone branch is cut. | **Resolved** — Gitea #24 updated at 2026-09-09T16:02:25Z. Record the policy in the milestone PR body. |
| R2 | **Real `sRGB.gam` asset missing or stubbed**. | Confirmed 448/892 in `Resources/Argyll/reference_gamuts/sRGB.gam` on `develop@629a1fce`; 28a adds a fixture against this file. Viewer AC against 8 vertices is a failed AC. |
| R3 | **Apple Developer ID / notary secrets not provisioned**, so #32 cannot produce a Gatekeeper-clean release. | `Release` config uses configurable `CODE_SIGN_IDENTITY`; CI notarization is conditional on `APPLE_DEVELOPER_ID` and notary key secrets. |
| R4 | **#28 and #29 both touch `ProfileWorkflowViewModel` or `Stage5View`**. | #28 must add only a single load hook in `ProfileWorkflowViewModel`; scene state lives in `GamutSceneController`; #29 owns Apply-toggle / `CAL_` wiring. If both land the same week, rebase the second onto milestone tip. |
| R5 | **AGPL boundary violation** — linking Argyll or `$PATH` spawn. | All new tools go through `BinaryResolver.resolve` and `ProcessManager`; no `dlopen`/linking; no `$PATH` search. |
| R6 | **Stage 0 `printtarg -K` leaked onto a `CAL_` target** or `applycal -u` exposed. | Golden argv tests assert `CAL_` basenames never see `-K` and `ApplycalConfig.unapply` is never `true` from UI code. |
| R7 | **SceneKit performance / context loss on Intel Monterey** or at app launch. | Lazy init only when Stage 5 appears; pause render loop on leave; keep a fallback banner matching docs/18. |
| R8 | **CI `make universal` fails because `Vendor/Argyll` is unsigned or missing**. | Workflow always runs `scripts/fetch-argyll.sh` first and fails on `codesign -dvv` or `instlist` marker failure. |
| R9 | **CGATS import writes an invalid canonical `.ti3`** that `colprof` rejects. | Round-trip `CGATSParser` test plus a fixture that a mock `colprof` can consume. |
| R10 | **Milestone branch becomes a catch-all** for unrelated fixes. | New post-cut residuals get a single `fix/<issue#>-<slug>` branch off the milestone branch or a new issue; do not reopen `feat/52-m5-bugfixes`. |
| R11 | **#30 import dialog regression** (save-`.ti1` panel) if 30c test is omitted. | Mandatory UI test `Milestone6CGATSUITests.importUsesOpenPanelNotSaveTi1`; fail if the import path uses a save panel or `.ti1` filter. |
| R12 | **Phase 0 FIXED table is wrong because M5 UI tests skip Stage 3**. | Pre-cut human spot-check of `Milestone4UITests.testHandheldFixtureChartreadAndAverage` and `ProfileWorkflowViewModel.resolveInstallCollision` (see §0). |

---

## 5. Gates

### CI / mock (every PR)

- `xcodebuild test -scheme ICCery -destination 'platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO`
- Per-slice: `xcodebuild test -scheme ICCery -only-testing:<Suite>/<Test>`
- `make universal`
- `scripts/fetch-argyll.sh` followed by `codesign -dvv` on each bundled Mach-O sidecar
- `make release-dmg` (ad-hoc if notary secrets absent; notarized/stapled if present)

### Hardware / manual (blocks release)

- **Stage 0:** one real printer calibration loop; `CAL_*.cal` produced and Stage 1 reminder cleared.
- **Gamut:** real profile `.gam` renders with sRGB overlay and axis scaffold.
- **Release:** Gatekeeper-open the notarized `.dmg` on a clean Mac; app launches without `Killed: 9`.

---

## 6. Non-goals

- Do **not** implement product code, entitlements, `project.yml` changes, or tests in this planning step.
- Do **not** create a second M6 plan file.
- Do **not** reopen `feat/52-m5-bugfixes` or any M5 umbrella branch.
- Preserve all M5 invariants: no `$PATH` lookup; no AGPL linking; `applycal -u` is never sent from the UI; `iccgamut -d 10`; atomic `applycal` temp-then-replace; `CAL_` namespace protected; artefact-driven stage gating; safe-path validation; process cancellation and `killAll`.
