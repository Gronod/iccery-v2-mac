# M6 Risk Register

| ID | Risk | Mitigation |
|----|------|------------|
| R1 | **#24 AC not updated in tracker** before the milestone branch is cut. | **Resolved** — Gitea #24 updated at 2026-09-09T16:02:25Z. Record the policy in the milestone PR body. |
| R2 | **Real `sRGB.gam` asset missing or stubbed**. | Confirmed on `develop@629a1fce`: `Resources/Argyll/reference_gamuts/sRGB.gam` is the real Argyll mesh (448 vertices / 892 faces). `feat/28` slice 28a adds a `GamutParser` fixture against this file. Viewer AC against 8 vertices is a failed AC. |
| R3 | **Apple Developer ID / notary secrets not provisioned**, so #32 cannot produce a Gatekeeper-clean release. | `project.yml` `Release` config uses a configurable `CODE_SIGN_IDENTITY`; CI notarization/staple runs only when `APPLE_DEVELOPER_ID`, `NOTARY_KEY`, and related secrets are set. |
| R4 | **#28 and #29 both touch `ProfileWorkflowViewModel` or `Stage5View`** and create merge conflicts. | `#28` adds only a single load hook in `ProfileWorkflowViewModel` (Stage 5 appear + post-`iccgamut` / post-`profcheck` success). Scene state lives in `GamutSceneController`. `#29` owns Apply-toggle / `CAL_` wiring. If both land the same week, rebase the second onto the milestone tip. |
| R5 | **AGPL boundary violation** — linking Argyll or spawning via `$PATH`. | All new tool invocations go through `BinaryResolver.resolve` and `ProcessManager`; no `dlopen`/linking; no `$PATH` search. |
| R6 | **Stage 0 `printtarg -K` leaked onto a `CAL_` target** or `applycal -u` exposed in the UI. | Golden argv tests assert `CAL_` basenames never see `-K` and `ApplycalConfig.unapply` is never `true` from UI code. |
| R7 | **SceneKit performance / context loss on Intel Monterey** or at app launch. | Lazy init only when Stage 5 appears; pause the render loop on leave; keep a fallback banner matching `docs/18-gamut-viewer.md`. |
| R8 | **CI `make universal` fails because `Vendor/Argyll` is unsigned or missing**. | Workflow always runs `scripts/fetch-argyll.sh` before build and fails if `codesign -dvv` or the `instlist` marker check fails. |
| R9 | **CGATS import writes an invalid canonical `.ti3`** that `colprof` later rejects. | Round-trip `CGATSParser` test plus a fixture that a mock `colprof` can consume. |
| R10 | **Milestone branch becomes a catch-all** for unrelated fixes. | Any new post-cut residual gets a single `fix/<issue#>-<slug>` branch off `milestone/m6-gamut-stage0-cgats-release` (or `develop` if not yet cut). Do not reopen `feat/52-m5-bugfixes`. |
| R11 | **#30 import dialog regression** (save-`.ti1` panel) if slice 30c test is omitted. | Mandatory UI test `Milestone6CGATSUITests.importUsesOpenPanelNotSaveTi1`; fails if import presents a save panel or `.ti1` filter. |
| R12 | **Phase 0 FIXED table is wrong because M5 UI tests may still skip Stage 3**. | Pre-cut human spot-checks of `Milestone4UITests.testHandheldFixtureChartreadAndAverage` and `ProfileWorkflowViewModel.resolveInstallCollision` (see `M6-MEGAPLAN.md` §0). |
