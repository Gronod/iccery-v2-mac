# ICCery

Native macOS frontend for printer ICC/ICM profiling. ICCery walks a user from
chart generation through measurement, `colprof`, verification, and ColorSync
install. It is **not** a colour engine.

**End-user guide:** the [repository wiki](https://git.i3omb.com/gronod/iccery-v2-mac/wiki)
covers every screen (Getting Started through Troubleshooting). This README is
for building, packaging, and contributing.

All measurement, chart generation, and profile mathematics live in the
[Gronod ArgyllCMS 3.5.0 fork](https://git.i3omb.com/gronod/argyllcms), spawned
as AGPLv3 child processes. The GUI never `dlopen`s or links Argyll.

| | |
|---|---|
| Product | ICCery v2 for macOS |
| Bundle | `com.gronod.iccery2` |
| Version | 2.0.0 |
| Floor | macOS 12.0 Monterey, universal `arm64` + `x86_64` |
| Toolchain | Xcode 14.2 / Swift 5.7 (project `SWIFT_VERSION` is 5.0) |
| CI | Gitea Actions `macos-12` runner |
| Default branch | `develop` |
| M6 | Stage 0 calibration, CGATS import, SceneKit gamut viewer, packaging — shipped |
| M7 | Pre-UAT hardening — shipped |
| M8 | Deduplication contracts & UAT-ready hardening (#79–#86) — shipped |
| M9 | macOS 12 / Xcode 14.2 retarget (PR #145) — shipped |
| M10 | Studio workflow: media library (#146), gamut compare (#147), Spot Read (#148), project files (#149) — shipped on `develop` |
| M11 | Printer settings completeness & dialog binding (#183, #180, #181, #186) — in flight on `milestone/m11-print-settings` |
| Licence | Proprietary source in [`LICENCE.md`](LICENCE.md); bundled Argyll sidecars remain AGPLv3 |

## What it does

The wizard is artefact-gated:

1. **Stage 1** — `targen` → `.ti1`
2. **Stage 2** — `printtarg` → `.ti2` + TIFF, unmanaged `lp` spool, bound `NSPrintPanel`
3. **Stage 3** — `instlist` + streaming `chartread` (strip / XY / handheld) → `.ti3`, multi-pass average, CIEDE2000
4. **Stage 4** — `colprof` → `.icc` / `.icm`; optional `applycal`; `iccgamut` next to the profile
5. **Stage 5** — `profcheck`, verification history, ColorSync user/system install

Plus:

- **Calibrate Printer** — optional `printcal` / `applycal` session under a `CAL_` basename
- **CGATS import** — `.ti3` / `.txt` / `.cgats` / `.csv`
- **Media recipes and presets** — printer + paper + ink bound to a preset and optional `.cal`
- **Spot Read** — live one-patch Lab/XYZ from the instrument
- **Project files** — `.icceryproj` bookmark over folder, basename, recipe, last ΔE
- **Gamut viewer** — SceneKit Lab hull, sRGB overlay, second-profile compare, click-inspect
- **Settings** — default instrument, ΔE good/warning cutoffs, install location, logging
- Signed `.dmg` packaging with a HiDPI Finder background (Monterey through Sonoma)

**Not this product:** display calibration (`dispwin` / `dispread`), i18n,
Windows/Linux print trees, in-process Argyll, App Sandbox.

## Requirements

To **run** a packaged build:

- macOS 12.0 Monterey or later (Intel or Apple silicon)

To **build** on the supported CI/host floor:

- macOS 12 with **Xcode 14.2** (macOS 12 SDK, Swift 5.7)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) **2.38.0** (Homebrew’s current
  formula needs Xcode 15.3; CI installs the pinned zip via
  `scripts/ensure-host-tools.sh`)
- Network once, to fetch Argyll sidecars
- For DMGs: Python 3.9+ and `dmgbuild==1.6.7` in `build/.venv-dmgbuild`
  (`INSTALL_DMGBUILD=1 scripts/ensure-host-tools.sh`)

App Sandbox is **off**. Hardened Runtime is **on**. Entitlements live in
`ICCery.entitlements`.

## Build

```bash
git clone https://git.i3omb.com/gronod/iccery-v2-mac.git
cd iccery-v2-mac
git checkout develop

make fetch-argyll          # Vendor/Argyll/macos-universal/, ad-hoc signed
make test                  # xcodegen + xcodebuild build test (host arch)
make universal             # ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
```

Equivalent without Make:

```bash
xcodegen generate
xcodebuild test -scheme ICCery \
  -destination 'platform=macOS' \
  ARCHS="$(uname -m)"
```

`project.yml` sets `ARCHS: "$(ARCHS_STANDARD)"`. CI and `make test` override
that with `ARCHS="$(uname -m)"` so unit/UI tests build the host slice only.
Fat binaries are `make universal` / `scripts/package-release.sh`.

Sidecars are **not** in git. `scripts/fetch-argyll.sh` pulls the latest (or
`ARGYLL_RELEASE_TAG`) macOS-universal release from `gronod/argyllcms`, extracts
to `Vendor/Argyll/macos-universal/`, ad-hoc signs every Mach-O, and fails if
`codesign -dvv` or the `instlist` marker is missing.

```bash
# optional
export ARGYLL_SERVER_URL=https://git.i3omb.com
export ARGYLL_REPO=gronod/argyllcms
export ARGYLL_RELEASE_TAG=…    # default: latest
export GITEA_TOKEN=…           # private releases
```

`make clean` drops `ICCery.xcodeproj`, `DerivedData`, and
`Packages/ICCeryCore/.build`.

Do not open the generated xcodeproj as the source of truth. Edit `project.yml`
and regenerate.

## Release packaging

```bash
scripts/package-release.sh    # fetch → sign → universal build → verify → DMG
```

The script builds with a fixed derived data path (`build/DerivedData`), locates
`Release/ICCery.app` from it, signs the bundle, recursively verifies every
bundled Mach-O sidecar (`scripts/verify-sidecar-signatures.sh`), builds a
HiDPI TIFF from `Resources/dmg-background.png` (+ `@2x`) via `tiffutil`, and
writes the DMG with `dmgbuild==1.6.7`.

### Versioning

`scripts/version.sh` resolves the version triple and is the single source for
packaging and CI:

- **`ICCERY_RELEASE_TAG`** — `RELEASE_TAG` env when it matches `v[0-9]*` (CI
  tag builds), else `git describe --tags --always --dirty --match 'v[0-9]*'`.
  Stamped into the bundle's `ICCeryReleaseTag` resource (a generated
  Info.plist cannot carry custom keys); the About dialog shows
  `tag (marketing)` — e.g. `v2.0.0-pre2-grok (2.0.0)` — falling back to the
  plain version when untagged.
- **`MARKETING_VERSION`** (`CFBundleShortVersionString`) — first three numeric
  components of the tag core. Must equal `project.yml`'s
  `MARKETING_VERSION` on tag builds — packaging hard-fails on mismatch, so
  bump `project.yml` on `develop` *before* tagging.
- **`CURRENT_PROJECT_VERSION`** (`CFBundleVersion`) — `BUILD_NUMBER` env
  override, else `git rev-list --count HEAD`. A single monotonically
  increasing integer per Apple's macOS convention (Mac build numbers never
  reset per version, unlike iOS).

Tagged/described DMGs carry the tag: `ICCery-2.0.0-pre2-grok-<build>.dmg`;
plain releases keep `ICCery-<ver>-<build>.dmg`.

Release procedure: bump `MARKETING_VERSION` in `project.yml` on `develop` →
merge `develop` → `main` → tag the release commit `vX.Y.Z[-suffix]` → push
the tag. CI builds, signs, notarizes (when secrets exist) and attaches the
DMG to the release.

Sidecars stay ad-hoc signed inside the bundle — the app is never
`codesign --deep`ed.

`dmgbuild` is **not** a test-job dependency. The package job sets
`INSTALL_DMGBUILD=1` so `scripts/ensure-host-tools.sh` creates
`build/.venv-dmgbuild`. On the Monterey runner (Python 3.9) that install uses
`PIP_IGNORE_REQUIRES_PYTHON=1` and pins `pip>=24.3,<26.1` (pip 26.1+ needs
3.10). Missing background art is a hard fail (#95).

Environment variables read by the pipeline:

| Variable | Purpose |
|---|---|
| `GITEA_TOKEN` | private `gronod/argyllcms` release downloads |
| `ARGYLL_SERVER_URL` / `ARGYLL_REPO` / `ARGYLL_RELEASE_TAG` | sidecar release override |
| `CODESIGN_IDENTITY` | Developer ID identity for the outer `.app`; unset or `-` = ad-hoc |
| `DEVELOPMENT_TEAM` | team ID passed to `xcodebuild` when signing |
| `NOTARIZE_APPLE_ID` / `NOTARIZE_PASSWORD` / `APPLE_TEAM_ID` | `notarytool` + staple when all three are set |
| `RELEASE_TAG` | release tag string (CI sets `github.ref_name`); stamped into the bundle + DMG name |
| `BUILD_NUMBER` | `CFBundleVersion` override; default `git rev-list --count HEAD` |

## Layout

```
Sources/ICCery/            SwiftUI + AppKit shell, stage views, workflow VMs
Packages/ICCeryCore/       wizard state, ProcessManager, argv builders,
                           settings, CGATS, ΔE₀₀ — no NSPrintPanel
Resources/                 assets; Argyll reference files (not the tools)
Vendor/Argyll/             fetched sidecars (gitignored)
Tests/ICCeryCoreTests/     argv goldens, parsers, stores
Tests/ICCeryUITests/       fixture / mock-binary UI tests
scripts/ensure-host-tools.sh
scripts/fetch-argyll.sh
scripts/package-release.sh
docs/                      functional spec + v2 ticket plan
```

`ICCeryPrintKit` (issue #16, Quartz / AirPrint / TargetPrint) is v2.1 and is
not in this tree.

## Architecture

- **Spawn, never link.** Tools resolve through `BinaryResolver` inside the
  bundle / `Vendor` tree. `$PATH` is not searched. `ARGYLL_NOT_INTERACTIVE=1`
  is always set.
- **`ProcessManager` actor** owns child lifetime. Streaming tools
  (`chartread`, `printtarg`, `colprof`, …) use the event bus; one-shot tools
  (`printcal`, `applycal`, CUPS) use `runCaptured`. Exclusive `ProcessID`
  leases. Quit path: `q\n`, ~500 ms, kill; `killAll` on terminate.
- **Argv builders** in ICCeryCore (`TargenArgs`, `PrinttargArgs`,
  `ChartreadArgs`, `ColprofArgs`, `ApplycalArgs`, `IccgamutArgs`,
  `ProfcheckArgs`, `LpArgs`, `SpotReadArgs`, …). UI must not concatenate flags.
- **Atomic artefacts.** Writes go to `*.tmp` then `replaceItemAt`. `applycal`
  must not replace the input profile on cancel or non-zero exit.
- **Concurrency.** View models are `@MainActor`. No blocking I/O on the main
  actor. Swift 5.7 / macOS 12: `ObservableObject`, not Observation
  `@Observable`.
- **Print.** Unmanaged `lp` with ColorSync suppression
  (`AP_ColorMatchingMode` / `AP.ColorMatchingMode`). Captured `NSPrintPanel`
  options win over derived CUPS keys. Never `lp -o raw`.
- **SwiftUI ViewBuilder.** Xcode 14.2 / Swift 5.7 still has the ten-child
  limit. Split large `VStack`/`Group` trees (#146).

## Tests

```bash
# full suite (host arch) — same as CI
xcodebuild test -scheme ICCery \
  -destination 'platform=macOS' \
  ARCHS="$(uname -m)"

# fat compile-check (not the default test path):
#   ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO

# examples
xcodebuild test -scheme ICCery -destination 'platform=macOS' \
  -only-testing:ICCeryCoreTests/ChartreadClassifierTests
xcodebuild test -scheme ICCery -destination 'platform=macOS' \
  -only-testing:ICCeryUITests/Milestone5UITests
```

CI (`.gitea/workflows/macos.yml` on Gitea, `.github/workflows/macos.yml` on
GitHub) runs `build-and-test` then `package` on
`develop` and on `v*` tags. Tags whose name contains `prerelease` skip the
test job and still package. `pull_request` is wired for **`develop` only**.
The GitHub file is the same pipeline on `macos-14` (github.com retired
`macos-12`), `actions/upload-artifact@v4`, and `gh release upload` for tag
DMGs.

UI tests need an unlocked console (`IOConsoleLocked=false`). Mock Argyll /
CUPS fixtures live under the test bundles; they must not be treated as proof
that a real `.gam` / `.icc` was extracted.

Hardware gates (real instrument, real printer, Gatekeeper-open `.dmg`) are
manual and block release, not compile.

`ArgyllRunnerPrinttargTests.testSuccess` can flake if streaming stdout is
dropped on a fast mock exit; that is a `ProcessManager` drain race, not a
missing fixture.

## Instruments

Detected via bundled `instlist`:

- i1 Pro / i1 Pro 2 (`i1`)
- ColorMunki (`CM`)
- SpyderPrint (`p3`)
- SpectroScan (`SS`)
- DTP20 / 22 / 41 / 51
- XY tables (SpectroScan, i1iO) when the `instlist` name matches
  `/spectro\s?scan|i1io/i`

## Docs

| Where | Audience |
|---|---|
| [Wiki](https://git.i3omb.com/gronod/iccery-v2-mac/wiki) | End users — screens, workflow, troubleshooting |
| [`docs/`](docs/README.md) | Functional spec (normative for implementers) |
| [`AGENTS.md`](AGENTS.md), [`BUILD-PLAN.md`](BUILD-PLAN.md) | Agent / branch rules |

Implementation order in `docs/`:

| Doc | Topic |
|---|---|
| [`docs/01-overview.md`](docs/01-overview.md) | Product and wizard |
| [`docs/03-ipc-and-process-manager.md`](docs/03-ipc-and-process-manager.md) | Spawn / stdin / kill |
| [`docs/04-argyll-binaries.md`](docs/04-argyll-binaries.md) | CLI argv |
| [`docs/06-wizard-and-artefacts.md`](docs/06-wizard-and-artefacts.md) | Gating |
| [`docs/23-assets.md`](docs/23-assets.md) | Icons, DMG chrome |
| [`docs/24-issues-invariants.md`](docs/24-issues-invariants.md) | Bugs that must not return |
| [`docs/26-v2-mac-ticket-plan.md`](docs/26-v2-mac-ticket-plan.md) | Gitea tickets |
| [`docs/PREUAT.md`](docs/PREUAT.md) | Pre-UAT tester kit |

## Git

```
develop          # integration; PRs land here unless a milestone branch is announced
main             # protected release line (PR from develop)
feat/<issue>-<slug>
fix/<issue>-<slug>
```

Open feature/fix PRs against **`develop`**. A `milestone/m…` integration
branch is used only while that milestone is assembling — currently
`milestone/m11-print-settings` (`milestone/m10-studio` was merged and
deleted). Do not open umbrella “bugfix” branches that mix tickets.

`main` is push-protected and requires status check
`macOS CI / build-and-test (push)`. Protected **file** patterns on `main`
block PR merges that touch matching paths — do not set that field to `*`.

## Licence

GUI source: © 2026 Gordon Bolton — see [`LICENCE.md`](LICENCE.md). Viewing
and personal evaluation only unless a separate grant says otherwise.

ArgyllCMS binaries fetched into `Vendor/Argyll/` are **AGPLv3**. They stay
subprocess-isolated (stdin / stdout / stderr only). Linking them, or spawning
via `$PATH`, is a licence break.

## Related

- [User wiki](https://git.i3omb.com/gronod/iccery-v2-mac/wiki)
- [gronod/argyllcms](https://git.i3omb.com/gronod/argyllcms) — Argyll 3.5.0 fork (`-u` JSON, `instlist`)
- [gronod/ICCery](https://git.i3omb.com/gronod/ICCery) — v1 Tauri application (spec source, not this tree)
