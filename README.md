# ICCery

Native macOS frontend for printer ICC/ICM profiling. ICCery walks a user from chart generation through measurement, `colprof`, verification, and ColorSync install. It is **not** a colour engine.

All measurement, chart generation, and profile mathematics live in the [Gronod ArgyllCMS 3.5.0 fork](https://git.i3omb.com/gronod/argyllcms), spawned as AGPLv3 child processes. The GUI never `dlopen`s or links Argyll.

| | |
|---|---|
| Product | ICCery v2 for macOS |
| Bundle | `com.gronod.iccery2` |
| Floor | macOS 14 Sonoma, universal `arm64` + `x86_64` |
| Default branch | `develop` |
| M6 | Stage 0 calibration, CGATS import, SceneKit gamut viewer, packaging — shipped on `develop` |
| M7 | Pre-UAT hardening & baseline consolidation — shipped on `develop` |
| M8 | Deduplication/consolidation contracts & UAT-ready hardening (#79–#86) — shipped on `develop` |
| M9 | macOS 12 / Xcode 14.2 retarget — shipped on `develop` (PR #145) |
| M10 | Studio workflow (#146–#149) — in flight on `milestone/m10-studio` |
| Licence | Proprietary source in [`LICENCE.md`](LICENCE.md); bundled Argyll sidecars remain AGPLv3 |

## What it does

The wizard is artefact-gated:

1. **Stage 0** — printer calibration: `printcal` / `applycal` session, `CAL_` basename restore
2. **Stage 1** — `targen` → `.ti1`
3. **Stage 2** — `printtarg` → `.ti2` + TIFF, unmanaged `lp` spool, bound `NSPrintPanel`
4. **Stage 3** — `instlist` + streaming `chartread` (strip / XY / handheld) → `.ti3`, multi-pass average, CIEDE2000
5. **Stage 4** — `colprof` → `.icc` / `.icm`; optional `applycal`; `iccgamut` next to the profile
6. **Stage 5** — `profcheck`, verification history, ColorSync user/system install

Plus CGATS dataset import (`.ti3` / `.txt` / `.cgats` / `.csv`), SceneKit gamut preview with sRGB overlay, and signed `.dmg` packaging.

**Not this product:** display calibration (`dispwin` / `dispread`), i18n, Windows/Linux print trees, in-process Argyll, App Sandbox.

## Requirements

- macOS 14+
- Xcode 15.4+ with the macOS 14 SDK and Swift 6.0
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Network once, to fetch Argyll sidecars

App Sandbox is **off**. Hardened Runtime is **on**. Entitlements live in `ICCery.entitlements`.

## Build

```bash
git clone https://git.i3omb.com/gronod/iccery-v2-mac.git
cd iccery-v2-mac
git checkout develop

make fetch-argyll          # Vendor/Argyll/macos-universal/, ad-hoc signed
make test                  # xcodegen + xcodebuild build test
make universal             # ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
```

Equivalent without Make:

```bash
xcodegen generate
xcodebuild test -scheme ICCery \
  -destination 'platform=macOS' \
  ARCHS="$(uname -m)"
```

`project.yml` sets `ARCHS: "$(ARCHS_STANDARD)"`, so a plain `xcodebuild test` (and `make test`) builds universal; the `ARCHS="$(uname -m)"` override narrows it to the host slice.

Sidecars are **not** in git. `scripts/fetch-argyll.sh` pulls the latest (or `ARGYLL_RELEASE_TAG`) macOS-universal release from `gronod/argyllcms`, extracts to `Vendor/Argyll/macos-universal/`, ad-hoc signs every Mach-O, and fails if `codesign -dvv` or the `instlist` marker is missing.

```bash
# optional
export ARGYLL_SERVER_URL=https://git.i3omb.com
export ARGYLL_REPO=gronod/argyllcms
export ARGYLL_RELEASE_TAG=…    # default: latest
export GITEA_TOKEN=…           # private releases
```

`make clean` drops `ICCery.xcodeproj`, `DerivedData`, and `Packages/ICCeryCore/.build`.

Do not open the generated xcodeproj as the source of truth. Edit `project.yml` and regenerate.

## Release packaging

```bash
scripts/package-release.sh    # fetch → sign → universal build → verify → DMG
```

The script builds with a fixed derived data path (`build/DerivedData`),
locates `Release/ICCery.app` from it, signs the bundle, recursively verifies
every bundled Mach-O sidecar (`scripts/verify-sidecar-signatures.sh`), and
writes `ICCery-${VERSION}-${BUILD_NUM}.dmg` via `dmgbuild`. Sidecars stay
ad-hoc signed inside the bundle — the app is never `codesign --deep`ed.

Environment variables read by the pipeline:

| Variable | Purpose |
|---|---|
| `GITEA_TOKEN` | private `gronod/argyllcms` release downloads |
| `ARGYLL_SERVER_URL` / `ARGYLL_REPO` / `ARGYLL_RELEASE_TAG` | sidecar release override |
| `CODESIGN_IDENTITY` | Developer ID identity for the outer `.app`; unset or `-` = ad-hoc |
| `DEVELOPMENT_TEAM` | team ID passed to `xcodebuild` when signing |
| `NOTARIZE_APPLE_ID` / `NOTARIZE_PASSWORD` / `APPLE_TEAM_ID` | `notarytool` + staple when all three are set |

## Layout

```
Sources/ICCery/            SwiftUI + AppKit shell, stage views, workflow VMs
Packages/ICCeryCore/       wizard state, ProcessManager, argv builders,
                           settings, CGATS, ΔE₀₀ — no NSPrintPanel
Resources/                 assets; Argyll reference files (not the tools)
Vendor/Argyll/             fetched sidecars (gitignored)
Tests/ICCeryCoreTests/     argv goldens, parsers, stores
Tests/ICCeryUITests/       fixture / mock-binary UI tests
scripts/fetch-argyll.sh
docs/                      functional spec + v2 ticket plan
```

`ICCeryPrintKit` (issue #16, Quartz / AirPrint / TargetPrint) is v2.1 and is not in this tree.

## Architecture

- **Spawn, never link.** Tools resolve through `BinaryResolver` inside the bundle / `Vendor` tree. `$PATH` is not searched. `ARGYLL_NOT_INTERACTIVE=1` is always set.
- **`ProcessManager` actor** owns child lifetime. Streaming tools (`chartread`, `printcal`, etc.) use the event bus; one-shot tools use `runCaptured`. Exclusive `ProcessID` leases. Quit path: `q\n`, ~500 ms, kill; `killAll` on terminate.
- **Argv builders** in ICCeryCore (`TargenArgs`, `PrinttargArgs`, `ChartreadArgs`, `ColprofArgs`, `ApplycalArgs`, `IccgamutArgs`, `ProfcheckArgs`, `LpArgs`, …). UI must not concatenate flags.
- **Atomic artefacts.** Writes go to `*.tmp` then `replaceItemAt`. `applycal` must not replace the input profile on cancel or non-zero exit.
- **Concurrency.** View models are `@MainActor`. No blocking I/O on the main actor. SwiftUI `@Observable` for new state.
- **Print.** Unmanaged `lp` with ColorSync suppression (`AP_ColorMatchingMode` / `AP.ColorMatchingMode`). Captured `NSPrintPanel` options win over derived CUPS keys. Never `lp -o raw`.

## Tests

```bash
# full suite (host arch)
xcodebuild test -scheme ICCery \
  -destination 'platform=macOS' \
  ARCHS="$(uname -m)"

# to compile-check both slices instead:
#   ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO

# examples
xcodebuild test -scheme ICCery -destination 'platform=macOS' \
  -only-testing:ICCeryCoreTests/ChartreadClassifierTests
xcodebuild test -scheme ICCery -destination 'platform=macOS' \
  -only-testing:ICCeryUITests/Milestone5UITests
```

UI tests need an unlocked console (`IOConsoleLocked=false`). Mock Argyll / CUPS fixtures live under the test bundles; they must not be treated as proof that a real `.gam` / `.icc` was extracted.

Hardware gates (real instrument, real printer, Gatekeeper-open `.dmg`) are manual and block release, not compile.

## Instruments

Detected via bundled `instlist`:

- i1 Pro / i1 Pro 2 (`i1`)
- ColorMunki (`CM`)
- SpyderPrint (`p3`)
- SpectroScan (`SS`)
- DTP20 / 22 / 41 / 51
- XY tables (SpectroScan, i1iO) when the `instlist` name matches `/spectro\s?scan|i1io/i`

## Docs

Normative spec is [`docs/`](docs/README.md). Implementation order:

| Doc | Topic |
|---|---|
| [`docs/01-overview.md`](docs/01-overview.md) | Product and wizard |
| [`docs/03-ipc-and-process-manager.md`](docs/03-ipc-and-process-manager.md) | Spawn / stdin / kill |
| [`docs/04-argyll-binaries.md`](docs/04-argyll-binaries.md) | CLI argv |
| [`docs/06-wizard-and-artefacts.md`](docs/06-wizard-and-artefacts.md) | Gating |
| [`docs/24-issues-invariants.md`](docs/24-issues-invariants.md) | Bugs that must not return |
| [`docs/26-v2-mac-ticket-plan.md`](docs/26-v2-mac-ticket-plan.md) | Gitea tickets |
| [`docs/PREUAT.md`](docs/PREUAT.md) | Pre-UAT tester kit |

Agent / branch rules: [`AGENTS.md`](AGENTS.md), [`BUILD-PLAN.md`](BUILD-PLAN.md).

## Git

```
develop
  └── milestone/m10-studio   # M10 integration branch
        └── feat/<issue>-<slug>    # one issue per branch
```

Feature PRs target the current milestone branch, not `develop`. The milestone branch merges to `develop` when its issues are green. Completion PRs for issues #146–#149 target `milestone/m10-studio`; `milestone/m10-studio` merges into `develop` once all milestone gates pass. Do not open umbrella "bugfix" branches that mix tickets.

## Licence

GUI source: © 2026 Gordon Bolton — see [`LICENCE.md`](LICENCE.md). Viewing and personal evaluation only unless a separate grant says otherwise.

ArgyllCMS binaries fetched into `Vendor/Argyll/` are **AGPLv3**. They stay subprocess-isolated (stdin / stdout / stderr only). Linking them, or spawning via `$PATH`, is a licence break.

## Related

- [gronod/argyllcms](https://git.i3omb.com/gronod/argyllcms) — Argyll 3.5.0 fork (`-u` JSON, `instlist`)
- [gronod/ICCery](https://git.i3omb.com/gronod/ICCery) — v1 Tauri application (spec source, not this tree)
