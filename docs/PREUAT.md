# Pre-UAT tester kit

This document is the canonical pre-UAT runbook. It is a **docs-only** slice; it does not change product code, `project.yml`, the build plan, or CI workflows.

## Builds that can be used for UAT

Only two artefacts are valid test builds:

1. **Debug built from this repository** (`xcodegen` → Debug → `xcodebuild test`/run).
2. **A notarized release DMG** produced by `scripts/package-release.sh`.

Unsigned CI artefacts (e.g. a `.zip` from a non-notarized workflow run) are **not** test builds. Do not run them on a clean Mac or Gatekeeper will kill them (`Killed: 9`).

## Local Debug build & unit tests

```
scripts/fetch-argyll.sh          # populates Vendor/Argyll and signs sidecars
xcodegen generate --project .
xcodebuild test -scheme ICCery -destination 'platform=macOS' \
    ARCHS="$(uname -m)" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY='-'
```

Use `CODE_SIGNING_ALLOWED=YES` and `CODE_SIGN_IDENTITY='-'` (ad-hoc). `CODE_SIGNING_ALLOWED=NO` is wrong: the app and test bundles will not be signed and `xctest` cannot be injected into the test host.

After `fetch-argyll.sh`, verify that sidecars are signed:

```
codesign -dvv Vendor/Argyll/macos-universal/instlist
codesign -dvv Vendor/Argyll/macos-universal/chartread
```

Do not install Argyll to `$PATH`. ICCery never searches `$PATH` for binaries.

## Release build / notarized DMG

`scripts/package-release.sh` reads these environment variables:

| Variable | Purpose |
|---|---|
| `CODESIGN_IDENTITY` | Developer ID Application identity name (omit or `-` for ad-hoc) |
| `DEVELOPMENT_TEAM` | Apple development team ID, passed through to `xcodebuild` |
| `NOTARIZE_APPLE_ID` | Apple ID for `notarytool` |
| `NOTARIZE_PASSWORD` | App-specific password for `notarytool` |
| `APPLE_TEAM_ID` | Team ID for `notarytool` |

Invocation for a signed, notarized DMG:

```
export CODESIGN_IDENTITY="Developer ID Application: Gronod (TEAMID)"
export DEVELOPMENT_TEAM="TEAMID"
export NOTARIZE_APPLE_ID="apple-id@example.com"
export NOTARIZE_PASSWORD="abcd-efgh-ijkl-mnop"
export APPLE_TEAM_ID="TEAMID"

scripts/package-release.sh
```

The script will emit `ICCery-<version>-<build>.dmg`. After mounting, verify Gatekeeper acceptance:

```
spctl -a -t open --context context:primary-signature -v ICCery-*.dmg
```

And inside the mounted app bundle:

```
codesign -dvv --strict ICCery.app
```

## Tester paths

### Week 1

Run these in order. Do not remap letters to “run unit tests”.

#### A — Stage 1 generate → Stage 2 print one page → cancel

1. Launch Debug build or notarized DMG.
2. Choose a target basename and working directory.
3. Stage 1: press **Generate target** (`targen`).
4. Stage 2: press **Print one page**.
5. Cancel the print panel.

**Pass:** the print panel appears and the app returns cleanly. The `printTask` is retained and not dropped.

#### B — Handheld chartread one sheet → Finish & Average

1. From Stage 2, press **Print chart pages** (or print the full target).
2. Stage 3: choose **Handheld read**.
3. Read one full sheet, then press **Finish & Average**.

**Pass:** a `.ti3` file is produced in the working directory.

#### C — Create profile, Apply Calibration off

1. Stage 4: turn **Apply Calibration** off.
2. Press **Create profile**.
3. If `iccgamut` fails or the `.gam` is missing, an info banner appears.

**Pass:** the app advances to Stage 5 regardless of the `iccgamut` outcome. This is issue #24: `.gam` failure is informational, not fatal.

#### D — Create profile, Apply Calibration on, missing/bad .cal

1. Stage 0: enter a printer calibration and let it complete (or hand-create a `CAL_<something>.cal`).
2. Stage 4: turn **Apply Calibration** on.
3. Rename or delete the `.cal` file so it is missing or unreadable.
4. Press **Create profile**.

**Pass:** the app **does not** advance to Stage 5; `applycal` failure blocks the profile creation.

#### E — Stage 5 profcheck + user vs system install / overwrite

1. Stage 5: press **Run profcheck**.
2. Press **Install profile** and choose **User install**.
3. Re-run **Install profile** and choose **System install** (or vice-versa).
4. When prompted, confirm overwrite.

**Pass:** `profcheck` completes, and the profile is installed/updated in the chosen scope.

### Week 2

#### F — Stage 0 full loop; return to profile basename; printtarg -K only on non-CAL_ name

1. Enter Stage 0 (printer calibration) and complete the full loop.
2. Verify that the live basename returns to the original profile basename (not `CAL_*`).
3. Stage 2 print options: `printtarg -K`/`-I` must **not** be present for any `CAL_*` basename.

**Pass:** `CAL_` never bleeds into `colprof`; `CAL_*.ti3` is not fed to `colprof`.

#### G — Import Dataset open panel

1. From any unlocked point where **Import dataset** is available, open the panel.
2. Select a file with one of: `.ti3`, `.txt`, `.cgats`, `.csv`.

**Pass:** the imported `.ti3`/dataset is accepted; the wizard skips the print and measure stages for the imported file. Do not use a `.ti1` file for “save” import here.

#### H — View Gamut + sRGB overlay + reset camera

1. Stage 5: press **View gamut**.
2. Verify the sRGB reference mesh is overlaid.
3. Click **Reset view** (or press `R`) to reset the camera.
4. Close the gamut sheet.

**Pass:** no GPU hang, the camera resets to the default home position, and the app remains responsive.

## Known behaviours / policies

### #24 — `.gam` failure is an info banner

- `iccgamut` missing or failing after `colprof` does **not** fail `Create profile`.
- The Stage 5 gamut pane falls back to the bundled `sRGB.gam` with no profile mesh.
- `applycal` failing **does** fail `Create profile` when **Apply Calibration** is on.

### `CAL_` vs profile basename; Cancel vs Force Quit

- Entering Stage 0 from a non-`CAL_` basename stores the original profile basename.
- **Cancel** in the calibration sheet returns to the original basename.
- A **Force Quit** mid-calibration leaves `CAL_*` behind; on relaunch the app restores the original profile basename.
- `CAL_` basenames cannot move to `generate`, `buildProfile`, or `verifyInstall`.

### Import skips print and measure

When a dataset is imported via the open panel, the wizard treats it as already measured. It must not re-print or re-measure the imported data.

## What is out of scope for pre-UAT

- No new product features (no #16 or M7 work).
- No `milestone/pre-uat` integration branch.
- No `project.yml` signing, sandbox, or deployment-target changes.
- No README or BUILD-PLAN rewrite.
- No CI workflow edits; this document is the single source of truth for the pre-UAT runbook.
