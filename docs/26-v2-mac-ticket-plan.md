# 26 — ICCery v2 Mac: reviewed Gitea ticket plan

**Status:** reviewed, executable. This is the plan to file — not the draft reviewed in chat.  
**Product:** ICCery v2, macOS-only SwiftUI/AppKit rewrite.  
**Repo:** `gronod/iccery-v2-mac` on git.i3omb.com.  
**Spec:** chapters [01](01-overview.md)–[25](25-rewrite-notes.md) (vendor these into the new repo; do not treat the live spec site as archival).  
**Agent:** Devin (`gitea` MCP: `label_write`, `milestone_write`, `issue_write`). Local git for bootstrap files.

---

## Changes from the 2026-09-08 draft

| Draft | Reviewed plan |
|-------|----------------|
| macOS 12.0 + `@Observable` | **macOS 14.0 Sonoma.** `@Observable` is 14+; SwiftUI 12 is not a viable wizard shell. v0.8.5’s 12.0 floor was WKWebView/#225, which is gone. |
| Bundle id `com.gronod.iccery` | **`com.gronod.iccery2`** until v1 is retired (settings, logs, Launch Services collide). |
| M3 exit = `lp` **and** Quartz/TargetPrint | **M3 = v0.8.5 `lp` path only** (issues 12–15, 17). TargetPrint is **v2.1** (issue 16, milestone Later). Do not mix ColorSync dictionaries. |
| Issue 2 = streaming spawn only | Issue 2 also ships **`runCaptured`** (`printcal`/`applycal`). |
| Settings dialog in M6 (issue 31) | **Settings UI in M1 (issue 5).** Issue 31 is About + help overlays only. |
| Calibrate Printer live in issue 1 | **Disabled/hidden** until issue 29. |
| `colprof -u` / `targen -u` “document later” | **Do not pass `-u` in v2.0** (parity; `colprof -u` collides with upstream white-point `-u`). |
| Skip/Undo `s`/`u` “verify later” | **Drop mock keys.** Real strip mode treats unknown letters as trigger. |
| Issue 3 refuses unsigned sidecars | Fetch script **ad-hoc signs** (`codesign -s -`) then `codesign -dvv` must succeed (#165). |
| Gitea-hosted `macos-latest` | **Self-hosted Mac runner** (or GitHub Actions mirror). `xcodebuild -destination macOS` is host-arch, not universal. |
| Gamut “SceneKit or Metal” | **SceneKit.** |
| Bootstrap via MCP `create_or_update_file` | **Git commit locally, then push.** Do not also MCP-write the same files. |

---

## Locked product decisions

> **Errata (M12, #201):** item 4's `lp` spool was replaced in v2.0 by a
> headless `NSPrintOperation` replaying the captured `PMPrintSettings`
> ticket, and the Quartz vocabulary of item 5 is now written **alongside**
> AP_* on the single native path (D2). "Never mix" no longer applies inside
> ICCery proper; it still governs the future `ICCeryPrintKit` boundary.

1. **Stack:** SwiftUI (`@Observable`, `@MainActor` view models) + AppKit for printing/panels. No Tauri, no Rust, no WebView.
2. **Floor:** macOS 14.0, universal `arm64` + `x86_64`.
3. **AGPL:** never link Argyll. Spawn with piped stdio + `ARGYLL_NOT_INTERACTIVE=1` on **every** child (streaming and captured).
4. **Print v2.0:** NSPrintPanel (settings capture, “Use Settings”) → `lp` with **both** `-o AP_ColorMatchingMode=AP_ApplicationColorMatching` and `-o AP.ColorMatchingMode=AP_ApplicationColorMatching`. **Never `-o raw` on macOS.**
5. **Print v2.1:** `ICCeryPrintKit` (TargetPrint folded), own ColorSync vocabulary (`PMColorMatchingMode=APCustomColorMatching`). Public API remains `TargetJob` JSON + `--job`.
6. **Identity:** product name ICCery, original cone SVG/app icon. Bundle `com.gronod.iccery2`.
7. **App Sandbox: OFF.** USB instruments, CUPS/`lp`, ColorSync install, `dlsym` of private PrintCore SPI. Hardened Runtime on; entitlements documented in issues 1 and 32.
8. **No Windows/Linux. No display cal (#90). No i18n (#96).**

---

## Execution sequence

1. In `~/Projects/iccery-v2-mac`: `git push -u origin main` (existing root commit).
2. Create `develop` from `main`. Commit `AGENTS.md`, `BUILD-PLAN.md`, `LICENCE.md`, vendored `docs/` (this spec set), `brand/ICCery-logo.svg` + `app-icon.svg`. Push `develop`.
3. MCP `label_write` → create every label. **Save ids.**
4. MCP `milestone_write` → create M1–M6 + **Later**. No `due_on`. **Save ids.**
5. MCP `issue_write` → create issues **in the order below**. Pass `milestone` id + `labels` ids. `issue_read` uses `issue_number`, not `index`.
6. If Gitea numbering does not start at 1, patch `BUILD-PLAN.md` dependency numbers to match.
7. Verify: `milestone_read list` (7 milestones), spot-check 3 issue bodies.

Do not create issues until labels and milestones exist.

---

## Repo bootstrap

### `AGENTS.md`

- SwiftUI + AppKit; min **14.0**; universal; bundle `com.gronod.iccery2`.
- **AGPL boundary:** never link Argyll; spawn only; `ARGYLL_NOT_INTERACTIVE=1`.
- Two spawn APIs: streaming `ProcessManager` (actor) and `runCaptured` (printcal/applycal only).
- No blocking subprocess I/O on `@MainActor`. Do not hop to main per stdout line (colprof dots).
- Argyll flag cheat-sheet: spec [25](25-rewrite-notes.md) (`-d`/`-r`/`-R`/`-u`/`-Y` differ per tool).
- Artefact gating on disk; atomic writes (`.tmp` + rename); user strings via SwiftUI `Text` only.
- Branching: `develop` ← `milestone/mN-<name>` ← `feat/<issue#>-<slug>`; PRs via Gitea MCP.
- Labels: every issue/PR has `Project/ICCery-v2` + one `Feature/*` or `Bug/*` + `Priority/*`.
- Verify: `xcodebuild test -scheme ICCery -destination 'platform=macOS' ARCHS="$(uname -m)"` (host arch; universal reserved for release packaging); sidecar `codesign -dvv`.
- Private ColorSync SPI: 2-arg `(PMPrintSession, CFStringRef) -> OSStatus`. Never pass integer `1`.

### `BUILD-PLAN.md`

- Milestone map below + mermaid branch taxonomy (quoted node labels).
- Pointer to vendored `docs/`.
- Each milestone: **CI/mock gate** and **hardware gate** listed separately.

### `LICENCE.md`

- GUI: proprietary EULA (copy from v0.8.5).
- Bundled Argyll sidecars: AGPLv3, subprocess-only, `License.txt` shipped beside binaries.

---

## Labels

Create exactly these (MacMonitor taxonomy):

| Name | Color | Notes |
|------|-------|-------|
| `Project/ICCery-v2` | `#007acc` | every issue/PR |
| `Feature/Architecture` | `#7057ff` | |
| `Feature/Backend` | `#008672` | |
| `Feature/UI` | `#d73a49` | |
| `Feature/DevOps` | `#fbca04` | |
| `Bug/Architecture` | `#b60205` | future |
| `Bug/Backend` | `#b60205` | future |
| `Bug/UI` | `#b60205` | future |
| `Bug/DevOps` | `#b60205` | future |
| `Priority/Critical` | `#d73a49` | |
| `Priority/High` | `#e99695` | |
| `Priority/Medium` | `#fef2c0` | |
| `Priority/Low` | `#c2e0c6` | |

---

## Milestones

Each milestone has an **interactive test gate**. Split **CI/mock** vs **hardware**. Do not start the next milestone until both gates for the current one pass (hardware may be “N/A” only for M1).

### M1 — Foundation & process core

**CI/mock:** app launches; wizard shell; ProcessManager spawn `instlist` (mock or real) with live log; artefact gating unit tests; settings persist + dialog.  
**Hardware:** none required.  
Issues 1–6.

### M2 — Target generation & layout (Stages 1–2)

**CI/mock:** targen → `.ti1`; printtarg → `.ti2` + TIFFs; manifest + gallery; resume; presets. Printing stubbed.  
**Hardware:** none.  
Issues 7–11.

### M3 — macOS unmanaged printing (`lp` path) — historical v1, superseded by #201

**CI/mock:** `lpstat`/`lpoptions` parsers; `build_lp_args` golden vectors (both `AP_*` always present); option filter; cancel → nil.  
**Hardware:** Preferences opens **driver PDE** on a real Epson or Canon queue; colour matching off/grayed; printed TIFF measures unmanaged (no ColorSync transform).  
Issues 12–15, 17. **Not issue 16.**

### M4 — Measurement (Stage 3)

**CI/mock:** `chartread.mock` end-to-end; classifier 39+ fixtures; swatch ΔE₀₀; snapshot/average.  
**Hardware:** Detect real instrument; one strip (or XY) through Done & Save → `.ti3`.  
Issues 18–22.

### M5 — Profile, verification & install (Stages 4–5)

**CI/mock:** colprof → `.icc`; profcheck JSON parse; history atomic write; install copy into a temp ColorSync-like dir.  
**Hardware:** full `.ti1`→`.icc` on a real chart; profile visible in ColorSync Utility.  
Issues 23–27.

### M6 — Gamut, Stage 0, CGATS, polish & release

**CI/mock:** `.gam` parser fixtures; cal argv builders; CGATS round-trip; `xcodebuild test`; fetch-argyll + ad-hoc sign; dmgbuild.  
**Hardware:** Stage 0 on a real printer; gamut view of a real profile.  
Issues 28–32.

### Later — Quartz / TargetPrint (v2.1)

Not a v2.0 exit gate. Issue 16 only.

---

## Ticket body template

Every issue body uses this structure (fill all sections):

```
## Summary
## Spec refs
## Scope
## Implementation notes
## Rewrite invariants
## Dependencies
## Test
- CI/mock:
- Hardware:
## Acceptance criteria
```

---

## Issue tickets

Create in this order. Titles are the Gitea titles.

### M1

**Issue 1 — App scaffold & wizard shell**  
Labels: `Project/ICCery-v2`, `Feature/Architecture`, `Feature/UI`, `Priority/Critical`  
Milestone: M1

- Xcode project `ICCery`, bundle id **`com.gronod.iccery2`**, SwiftUI App lifecycle, **macOS 14.0**, universal `arm64`+`x86_64`.
- Dark tokens from v0.8.5: bg `#1e1e1e`, panel `#252526`, text `#d4d4d4`, accent `#007acc`, border `#333`. Window 1280×800, min 1100×700.
- **App Sandbox OFF.** Hardened Runtime ON. Entitlements: USB (`com.apple.security.device.usb`), Apple Events / `open` for ColorSync Utility later, no network client required at M1. Document in `TargetPrint.entitlements`-style file `ICCery.entitlements`.
- Sidebar 270px: original `ICCery-logo.svg` (do not redraw), settings/about buttons, **disabled** preset select, **disabled** Calibrate Printer + cal chip (enable in 11 / 29), stepper 1–5.
- Main: notification banner + one visible stage. Stage 0 is not in the stepper.
- First paint: native dark `NSAppearance` — hidden-until-paint is not required (no WebView).
- Spec: [01](01-overview.md), [02](02-architecture.md), [21](21-ui-reference.md), [23](23-assets.md).
- Invariants: none of #225 WebView workarounds.
- Deps: none.
- Test CI: `xcodebuild build`; window min-size; only Stage 1 enabled. Hardware: N/A.
- AC: launches dark; stepper 5 stages; logo matches v0.8.5 SVG; Calibrate Printer disabled; sandbox disabled in entitlements plist.

**Issue 2 — ProcessManager: spawn / stdin / kill / captured / event bus**  
Labels: `Feature/Architecture`, `Feature/Backend`, `Priority/Critical`  
Milestone: M1

- `ProcessManager` **actor**.
- **Streaming:** `spawn(id, binary, args, cwd)` — reject duplicate live ids; pipe stdin/stdout/stderr; `ARGYLL_NOT_INTERACTIVE=1`; take handles at spawn; line-split stdout; lines starting **`ROW_COLORS_JSON: `** (17 chars, space after colon) → `jsonRow` (prefix stripped), never also as `stdout`; `sendStdin(id, Data)` exact bytes + flush; `kill(id)` close stdin then terminate; `killAll()`; reap → `exit(id, code)` with natural `unwrap_or(0)` / killed `unwrap_or(1)`.
- **Captured:** `runCaptured(binary, args, cwd) -> (code, stdout, stderr)` — same env, same `resolve_binary`, same `killAll` coverage. Used **only** by `printcal` / `applycal` (issue 29 / 24). No event bus.
- Events: `AsyncStream` — `stdout`, `stderr`, `jsonRow`, `exit`, `error`. Do **not** hop to `@MainActor` per line.
- ProcessManager does **not** JSON.parse pretty-printed `instlist` / `printtarg` / `profcheck` output. Callers accumulate stdout.
- `killAll` on `NSApplication.willTerminate` and last-window close (#147, #149).
- Log argv with home rewritten to `~`.
- Spec: [03](03-ipc-and-process-manager.md), [04](04-argyll-binaries.md) §0.3–0.5.
- Invariants: **#84** stdin independent of wait; **#116** exclusive ids; **#134** env var; **#147/#149** killAll on quit.
- Deps: 1 (app target), 3 (resolve — may stub paths in tests).
- Test CI: duplicate-id; stdin survives while wait runs; json-row isolation; killAll N children; captured returns full stdout. Hardware: N/A.
- AC: unit tests listed above pass.

**Issue 3 — Argyll sidecar fetch & binary resolution**  
Labels: `Feature/DevOps`, `Feature/Backend`, `Priority/Critical`  
Milestone: M1

- `fetch-argyll` pulls Gronod tag `v3.5.0-ICCery.1.x` into `Resources/argyll/{macos-universal,macos-x86_64,macos-aarch64}/` + `mocks/` + `reference_gamuts/` + `License.txt`. **Not git blobs** (#127).
- After fetch: **`codesign -s -` every Mach-O**, then `codesign -dvv` must succeed. Fail the script if still unsigned (#165 `Killed: 9`).
- `resolve_binary(name)`: settings `argyll_binary_dir` if the file exists → bundled dir; prefer `macos-universal` **only when that folder contains `instlist`**. Do not search `$PATH`.
- Ship **real** `sRGB.gam` from v0.8.5 `src/assets/sRGB.gam` as an app resource (not the 8-cusp stub in `reference_gamuts/`) — consumed by issue 28 (#185).
- Mocks (`chartread.mock`, `colprof.mock`, `profcheck.mock`) are first-class; M4/M5 CI must run them.
- Spec: [04](04-argyll-binaries.md) §0.1/§0.6, [05](05-argyll-fork.md) §8–10.
- Deps: 1.
- Test CI: fetch (or fixture) + resolve override + unsigned binary fails check. Hardware: N/A.

**Issue 4 — Wizard state machine & artefact gating**  
Labels: `Feature/Architecture`, `Feature/Backend`, `Priority/Critical`  
Milestone: M1

- `WizardState`: `currentStage`, `basename`, `cwd`, `printerName`, `sessionMode`, `profileBasename`.
- `verifyStageArtefacts` from disk: `.ti1` / `.ti2` / `.ti3` / `.icc|.icm`. Forward gated; back always; re-validate on window focus + stage entry (#151).
- Basename: no `/`, `\`, `..`. Empty cwd illegal → Documents → Home → app-data (#59). No placeholder basenames (#60).
- Stage 4 is **not** unlocked by `.ti2`. Canonical `.ti3` means **accepted** measurement only (#109/#110).
- Spec: [06](06-wizard-and-artefacts.md), [02](02-architecture.md).
- Deps: 1.
- Test CI: gating matrix; focus re-lock. Hardware: N/A.

**Issue 5 — Settings store, logging & settings dialog**  
Labels: `Feature/Backend`, `Feature/UI`, `Priority/High`  
Milestone: M1

- `settings.json` under app-data for `com.gronod.iccery2` (do not read v1’s folder unless a future migration ticket says so).
- `AppSettings` defaults: `argyll_binary_dir` nil, `default_instrument` nil (**stored, never applied to argv**), `log_level` nil, `delta_e_good_max` 2.0, `delta_e_warning_max` 5.0 (`good < warning`, both ≥ 0), `custom_presets` [], `enable_i1pro2_leds` **false**, `calibration_stale_days` 30, `default_install_location` `user`, `ask_before_overwrite_profile` true, `open_color_panel_after_install` false. Invalid JSON → defaults.
- Logger: `~/Library/Logs/com.gronod.iccery2/iccery.log`, 5 MiB × 5. Level applied at startup **and** on save (#158).
- **Settings dialog in this ticket** (not M6): argyll dir picker, default instrument (display-only caveat), i1Pro2 LEDs, ΔE fields + inline error, stale days, install location, log level, open-log-folder / copy-path / copy-excerpt.
- Spec: [22](22-settings-presets.md), [02](02-architecture.md) logging, [21](21-ui-reference.md) settings ids.
- Deps: 1, 6 (directory picker — 6 may land in parallel; stub if needed).
- Test CI: validation strings; live log-level change; dialog bindings persist. Hardware: N/A.

**Issue 6 — File dialogs & artefact helpers**  
Labels: `Feature/Backend`, `Priority/High`  
Milestone: M1

- **One NSOpenPanel/NSSavePanel wrapper per purpose** — never a shared picker:
  - `selectTargetFile` save `.ti1`
  - `selectExistingTarget` open `.ti1/.ti2`
  - `selectProfileFile` `.icc/.icm/.mpp` (**not** `.ti*`, #172)
  - `selectSpectrumFile` `.sp`
  - `selectDatasetFile` **open** `.ti3/.txt/.cgats/.csv` (#211)
  - `selectDirectory`, `selectCsvSavePath`, `selectCalFile`
- `readTiffPreviewPng`: host-side TIFF→PNG, max edge 1200, high-quality. **Never** feed TIFF to `NSImageView` as the gallery source (#58).
- `parseTi2Header`: `TARGET_INSTRUMENT`, `NUMBER_OF_SETS`, `NUMBER_OF_PAGES`, sibling `.ti1`.
- `resolveSafeCwd`, `getDefaultWorkingDir`, `getAppInfo`, `getProfilePath` (existing `.icm` else `.icc`, macOS default `.icc`, #69).
- Spec: [04](04-argyll-binaries.md) §0.2/§13, [24](24-issues-invariants.md) #103/#210/#211.
- Deps: 1.
- Test CI: filter + mode per picker; TIFF→PNG; ti2 fixtures. Hardware: N/A.

---

### M2

**Issue 7 — Stage 1: targen UI & argv builder**  
Labels: `Feature/UI`, `Feature/Backend`, `Priority/Critical`  
Milestone: M2

- Always `-v -d {2|4}`. RGB `-d 2`, CMYK `-d 4`. **Do not pass `targen -u`.**
- Patch presets 400 / **800 default** / 1500 / custom; honour `-f N` (#44 — omitting yields Argyll 836).
- White `-e`, black `-B` (RGB default 4, CMYK 0 on colour-space switch).
- Advanced: `-g` `-s` `-n`; `-N` skip if ≈0.50; `-c` profile picker; `-G`; `-A` **even at 0.10** (no default-skip); algorithm `-t|-r|-R|-q|-Q|-i|-I` with **`ofps` / default = no extra flag**; CMYK-only `-l` 1–400; `-V` skip ≈1.0; `-p` skip ≈1.0 and >0.
- Basename + cwd required. Process id `targen_{basename}`.
- Spec: [08](08-stage1-targen.md), [04](04-argyll-binaries.md) §1.2.
- Deps: 2, 3, 4, 6.
- Test CI: argv golden vectors every flag combo. Hardware: N/A.
- AC: exit 0 → `.ti1` → Stage 2 unlocks.

**Issue 8 — Stage 1: resume existing target**  
Labels: `Feature/Backend`, `Priority/High`  
Milestone: M2

- Open dialog `.ti1/.ti2` (#103, #140). Jump: `.ti1`→Stage 2, `.ti2`→Stage 3 + “Resumed from .ti2”.
- Spec: [06](06-wizard-and-artefacts.md), [08](08-stage1-targen.md).
- Deps: 4, 6, 7.
- Test CI: resume fixtures. Hardware: N/A.

**Issue 9 — Stage 2: printtarg UI & argv builder**  
Labels: `Feature/UI`, `Feature/Backend`, `Priority/Critical`  
Milestone: M2

```
-v -u -i {instrument} -p {page} [-r | -R seed] [-d label] {-t|-T} {dpi} [-K|-I cal] basename
```

- Always `-v -u`. Default layout **`-R 1`** (#163). Raster is `-r` (not `-R`). Custom seed `-R N` N≥1.
- `-d` is the **label** (fork #19 / ICCery #119), not colour space, not density. Auto: `ICCery - {basename} - {printer} - {ink} - {driverPaper} - {actualPaper} - DD/MM/YYYY HH:MM`.
- `-K`/`-I` **must exist on the builder in M2** (Stage 0 reuses it). UI toggle may wait for 29. **Never `-K` a `CAL_` basename.**
- Process id `printtarg_{basename}`. CM warning banner.
- Spec: [09](09-stage2-printtarg.md), [04](04-argyll-binaries.md) §2.2, [05](05-argyll-fork.md) §2.3.
- Deps: 2, 4, 7.
- Test CI: argv goldens including deterministic re-run identical `.ti2`. Hardware: N/A.

**Issue 10 — Stage 2: JSON manifest & TIFF gallery**  
Labels: `Feature/Backend`, `Feature/UI`, `Priority/High`  
Milestone: M2

- Accumulate **all** stdout; `JSON.parse` the pretty-printed object (not brace-hunting, #68):

```json
{"event":"manifest","pages":[{"filename":"target.tif","patches":800,"width_mm":210,"height_mm":297}]}
```

- Gallery: `readTiffPreviewPng` per page. Per-page Print buttons **stubbed** until M3.
- Spec: [09](09-stage2-printtarg.md), [05](05-argyll-fork.md) §2.3.
- Deps: 6, 9.
- Test CI: single + multi-page fixtures; non-zero exit stays on Stage 2. Hardware: N/A.

**Issue 11 — Presets engine & built-ins**  
Labels: `Feature/Backend`, `Feature/UI`, `Priority/Medium`  
Milestone: M2

- `ProfilingPreset` Codable: all Stage 1/2/4 fields in [22](22-settings-presets.md).
- Built-ins (all i1, FWA D50, seed 1, algorithm `l`):
  1. `preset-std-rgb` — 800, A4, 8-bit, 300 dpi, quality `m`
  2. `preset-hq-cmyk` — 1500, A3, 16-bit, quality `h`, ink 320, black 8
  3. `preset-draft-rgb` — 400, A4, 8-bit, **150 dpi**, quality `l`
  4. `preset-ultra-rgb` — 2500, A3, 16-bit, quality `u`, `-G`, white/black 6
- Apply/save/manage/delete-custom/import/export. Built-ins undeletable. Names via `Text` only (#114). DPI must bind (#113). Enable the M1 preset select.
- Deps: 5, 7, 9 (Stage 4 fields stored now, applied in 23).
- Test CI: round-trip; draft → 150 dpi; import schema. Hardware: N/A.

---

### M3

**Issue 12 — Printer enumeration & capabilities**  
Labels: `Feature/Backend`, `Priority/Critical`  
Milestone: M3

- `lpstat -e` / `-p` / `-d`; `lpoptions -p` display name (`printer-info`); `lpoptions -p -l` trays/sizes/media; PPD `*Key id/Human:` enrichment.
- Models as draft (`Printer`, `PrinterTray`, `PrinterPaperSize`, `PrinterMediaType`, `PrinterCapabilities`).
- **Cite spec [10](10-print-system.md) + [11](11-print-macos.md).** Doc [13](13-print-linux.md) is Linux `lp -o raw` — **enumeration only, do not copy `print_target`.**
- Deps: 2 (optional CLI spawn) or Foundation `Process`.
- Test CI: recorded `lpstat`/`lpoptions` fixtures; empty list = success. Hardware: optional live queue list.

**Issue 13 — Native NSPrintPanel bound to selected queue**  
Labels: `Feature/Backend`, `Feature/UI`, `Priority/Critical`  
Milestone: M3

- Preferences → **`NSPrintPanel` on the AppKit main thread**, bound with `PMPrinterCreateFromPrinterID(CUPS queue id)` → `PMSessionSetCurrentPMPrinter` → default settings/page format. Fallback `NSPrinter(name: displayName)`.
- Default button **"Use Settings"** (capture, not print). Cancel → `nil`, not error. `PMRelease` on every path.
- **Never** System Settings, CUPS web UI, or `NSWorkspace` open of the printer (#188).
- Spec: [11](11-print-macos.md).
- Deps: 12.
- Test CI: cancel path. Hardware: panel shows Epson/Canon **driver PDE**.

**Issue 14 — ColorSync suppression engine**  
Labels: `Feature/Backend`, `Priority/Critical`  
Milestone: M3

Six layers (spec [11](11-print-macos.md) roster):

1. Session binding (issue 13).
2. `dlsym(RTLD_DEFAULT)`: `PMSessionSetColorMatchingModeLock` → `PMSessionSetColorMatchingMode` → `…NoLock`. **Signature `(PMPrintSession, CFStringRef) -> OSStatus`.** Modes `AP_ApplicationColorMatching` then `ApplicationColorMatching`. First `(symbol, mode)` returning 0 wins. **Never pass integer `1` (SIGSEGV).** Forbidden: `AP_ColorSyncMatching`, `AP_VendorColorMatching`.
3. `PMPrintSettingsSetValue` both `AP_ColorMatchingMode` and `AP.ColorMatchingMode` = `AP_ApplicationColorMatching`, **locked**.
4. Driver bypass from `lpoptions -l`, **unlocked**: Canon `CNIJIntent2=4` else `CNIJIntent=4`; Epson `EPIJ_CCor=0` **if that key exists** else `EPIJ_CMat=3`; Gutenprint `StpColorCorrection=Uncorrected`; generic `ColorCorrection=Uncorrected`; `EpsonColorMode=Off`.
5. Mirror into `NSPrintInfo.printSettings`.
6. After OK: `PMPrintSettingsToOptions` → filter (drop `com.apple.*`, collate/copies/job-sheets, empty values, **both AP_* keys** — issue 15 always re-adds them) → `capturedCupsOptions` + media type.

- Deps: 12, 13.
- Test CI: injectable dlsym order; filter fixtures. Hardware: PDE colour grayed/off on Epson **and** Canon.

**Issue 15 — `lp` spool path — historical v1, superseded by #201 native spool**  
Labels: `Feature/Backend`, `Priority/High`  
Milestone: M3

```
lp -d <queue> -t "ICCery Target - <file>"
   -o AP_ColorMatchingMode=AP_ApplicationColorMatching
   -o AP.ColorMatchingMode=AP_ApplicationColorMatching
   … captured options …
   <tiff>
```

- **Never `-o raw`.** Raw skips the raster filter that honours `AP_*`.
- Then captured cups_options (sanitise keys/values — no `;`, newlines, or shell metacharacters; pass as `Process` args, never a shell string). Then media_type if absent, then driver bypass if no bypass key yet (**not** gated on a checkbox), then `orientation-requested=3|4`, then `PageSize`.
- Last argv is the TIFF path.
- Spec: [11](11-print-macos.md) `build_lp_args`.
- Deps: 14.
- Test CI: argv goldens — both AP_* always present; captured wins; sanitise rejects `;`. Hardware: one unmanaged page.

**Issue 17 — Stage 2 print panel UI**  
Labels: `Feature/UI`, `Priority/High`  
Milestone: M3

- After manifest: printer select + refresh, status badge, Preferences, tray, media type, orientation, Print All + per-page, CM banner, per-printer `capturedCupsOptions` cache. Cancel → info, not error. No CUPS “PPD fallback” checkbox (Windows/Linux only, #48).
- Spec: [09](09-stage2-printtarg.md), [10](10-print-system.md).
- Deps: 10, 12, 13, 15.
- Test CI: captured options replayed in argv. Hardware: layout→Preferences→Print All.

---

### M4

**Issue 18 — Instrument detection (`instlist`)**  
Labels: `Feature/Backend`, `Priority/Critical`  
Milestone: M4

- Spawn `instlist` no args, id `instlist`, cwd inherited. Accumulate stdout; parse pretty JSON `{event:"instruments",devices:[{port,name,type}]}`. Regex fallback requiring known-instrument tokens.
- `port` is **1-based comm port** for `chartread -c`. Port `1` / Auto → **omit `-c`** (#111). Never pass array index. XY if name/type matches `/spectro\s?scan|i1io/i`.
- Duplicate Detect while running → exclusive-id error (#116).
- Spec: [15](15-stage3-chartread.md), [05](05-argyll-fork.md) §4.
- Deps: 2, 3.
- Test CI: JSON + regex fixtures; empty list. Hardware: Detect finds a real device.

**Issue 19 — chartread session & prompt classifier**  
Labels: `Feature/Backend`, `Priority/Critical`  
Milestone: M4

```
-v -u [-c port] [-Y l] basename
```

- Process id `chartread_{basename}`. **Do not pass `chartread -u` omission — `-u` is required** (JSON rows).
- `-Y l` only when settings `enable_i1pro2_leds` (default **false**, #204). Letter L, not `-L`.
- Classifier: 11 states, priority matchers on **real C prompt strings** (spec [05](05-argyll-fork.md) §12.4). Sticky `TABLE_*` (#93). “Remove last sheet” info-only.
- stdin: `" \n"` / `"\n"` trigger/accept; `"d\n"` done+save (#175, **not EOF**); `"q\n"` abort. **No Skip/Undo sending `s`/`u`.** If a back-strip control is needed, map to real keys (`f`/`b`/`n`) after reading fork `chartread.c`.
- XY cancel: `q\n`, ~500ms, then kill (#147).
- CI must run `chartread.mock`.
- Spec: [15](15-stage3-chartread.md), [03](03-ipc-and-process-manager.md) stdin table.
- Deps: 2, 4, 18, 5 (LED flag).
- Test CI: port 39 classifier cases + real-prompt fixtures; Done → `.ti3`. Hardware: one real strip.

**Issue 20 — Live swatch grid & ΔE₀₀**  
Labels: `Feature/UI`, `Feature/Backend`, `Priority/High`  
Milestone: M4

- `jsonRow` `event:row_complete`. Grid A→Z, 1→N LTR. 135° split TL intended / BR measured (#178). `is_pad` skip only if no measured **and** all-zero device (white `-e` still renders). XYZ 0–100 → /100 before Lab. Traffic lights from settings 2.0 / 5.0; reclassify on settings change. Distinct from Stage 5 bands (#95).
- Spec: [15](15-stage3-chartread.md), [05](05-argyll-fork.md) §3.
- Deps: 19, 5.
- Test CI: ΔE₀₀ vectors; pad/white cases. Hardware: N/A (uses json rows).

**Issue 21 — Multi-pass averaging**  
Labels: `Feature/Backend`, `Priority/High`  
Milestone: M4

- After chartread exit 0: `snapshot_ti3` copies to `{basename}_passN.ti3` (1-based) and **deletes** canonical (#109). Stage 4 stays locked (#110). Finish: 1 pass `promote_ti3`; ≥2 `average -v` relative names in project cwd then canonical `.ti3`.
- Deps: 2, 4, 19.
- Test CI: snapshot/promote; average argv; gating locked between passes. Hardware: N/A.

**Issue 22 — XY-table flow UI**  
Labels: `Feature/UI`, `Priority/Medium`  
Milestone: M4

- Badges Place → Align → Scan → Remove from classifier. Cancel parks head (`q\n` then kill).
- Spec: [15](15-stage3-chartread.md) #93.
- Deps: 19.
- Test CI: simulated prompt script. Hardware: optional i1iO / SpectroScan.

---

### M5

**Issue 23 — Stage 4: colprof UI & argv builder**  
Labels: `Feature/UI`, `Feature/Backend`, `Priority/Critical`  
Milestone: M5

```
-v -a {l|x|X|m} -q {l|m|h|u} [-t intent] [-f [D50|D65|path.sp]] [-i] [-o] [-c inView] [-d outView] [-D] [-C] basename
```

- Default `-a l` (Lab cLUT), `-q m`. FWA: none omit / empty → bare `-f` / D50 / D65 / custom `.sp` via `selectSpectrumFile` (#210, #176). Viewing `-c`/`-d` skip `"none"` — these are **not** directories/labels.
- **Do not pass `colprof -u`.** Progress from stdout text. If someone later adds `-u`, it must be a **bare** flag (upstream `-u <token>` is white-point).
- Process id `colprof_{basename}` — payload/id parity (#56). Then `getProfilePath` (#69).
- Spec: [16](16-stage4-colprof.md), [04](04-argyll-binaries.md) §6.
- Deps: 2, 4, 6, 11.
- Test CI: argv goldens; mock colprof; exit 0 → Stage 5. Hardware: N/A (or full pipe).

**Issue 24 — Post-profile chain: applycal + iccgamut**  
Labels: `Feature/Backend`, `Priority/High`  
Milestone: M5

- If Apply Calibration + `.cal`: `runCaptured` `applycal -v -a {cal} {icc}` via `{input}.applycal.tmp` + rename. **`applycal -u` means unapply — never send.**
- Then `iccgamut -v -d 10 {resolvedProfile}` (density, **not** a directory, #112). cwd = profile parent, id `iccgamut_{stem}` → `{stem}.gam`.
- Spec: [04](04-argyll-binaries.md) §7/§10, [17](17-stage5-verification.md).
- Deps: 2 (captured), 23.
- Test CI: applycal argv + tmp; iccgamut `-d 10`. Hardware: N/A.

**Issue 25 — Stage 5: profcheck verification**  
Labels: `Feature/Backend`, `Feature/UI`, `Priority/Critical`  
Milestone: M5

- `profcheck -v -k -s -u {ti3} {icc}`, id `profcheck_{ti3_path}`. Prefer JSON `event:report` / `*_de2000`; legacy text fallback; **unparseable → warning, never silent 0.00** (#179).
- Bands on **avg** ΔE₀₀: <1 Excellent, <2 Good, <3.5 Acceptable, ≥3.5 Warning — **not** swatch 2.0/5.0 (#95).
- Spec: [17](17-stage5-verification.md), [05](05-argyll-fork.md) §2.5.
- Deps: 2, 23.
- Test CI: JSON/text/garbage fixtures. Hardware: N/A.

**Issue 26 — Verification history & drift analytics**  
Labels: `Feature/Backend`, `Feature/UI`, `Priority/High`  
Milestone: M5

- `verification_history.json`, cap 1000, **atomic `.tmp`+rename** (#213). Record fields as spec [17](17-stage5-verification.md). Consecutive-breach: ≥2 Warning on distinct days or ≥1h apart. RFC-4180 CSV.
- Deps: 25, 5.
- Test CI: crash-during-write keeps prior file; cap; CSV quotes; alert logic. Hardware: N/A.

**Issue 27 — System profile installation**  
Labels: `Feature/Backend`, `Feature/UI`, `Priority/High`  
Milestone: M5

- **Copy, never move.** User `~/Library/ColorSync/Profiles`; system `/Library/ColorSync/Profiles` (error text must mention admin rights). Filename `{stem}.icc`; reject stem `.. / \`. Source file, `.icc/.icm`, ≥128 bytes. Collision overwrite | rename `{stem}-{epoch}.icc` | cancel. Atomic `{dest}.iccery-install.tmp`+rename. `open -a "ColorSync Utility"` if requested. `InstallResult` as spec [19](19-profile-install.md).
- Deps: 6, 5, 23.
- Test CI: dest matrix in temp dirs; collision; failed copy does not register. Hardware: profile appears in ColorSync Utility.

---

### M6

**Issue 28 — 3D gamut viewer (SceneKit)**  
Labels: `Feature/UI`, `Feature/Backend`, `Priority/High`  
Milestone: M6

- Parser: two CGATS `BEGIN_DATA` blocks — vertices `VERTEX_NO L a b` (discard index, push-order), then faces 0-based. `#` comments; native faces **>** convex hull; vertex-only → hull fallback. ASCII only.
- SceneKit (not Metal, not Three.js): X=a* ±128, Y=L* 0–100, Z=b* ±128; camera home (180,120,180) lookAt (0,50,0). Bundled **real** `sRGB.gam`. R resets camera on a **focusable** container (do not port dead-key / opacity-inference traps — spec [18](18-gamut-viewer.md) §10: **fix**, don’t clone).
- Load on Stage 5 entry + post-verify. No WebGL at boot (#225 class).
- Spec: [18](18-gamut-viewer.md), [23](23-assets.md) #185.
- Deps: 3 (asset), 24 (`.gam`).
- Test CI: dual-table / comments / OOB / stub→hull fixtures. Hardware: N/A.

**Issue 29 — Stage 0: printer calibration**  
Labels: `Feature/Backend`, `Feature/UI`, `Priority/High`  
Milestone: M6

- Enable Calibrate Printer. Basename `CAL_{run}` (never double-prefix). Flow: cal `targen` (`-f 0`, steps 11–51 default 21, `-e 4`, CMYK `-l` 200–400 default 320) → Stage 2 layout/print (**never `-K` the cal chart**) → Stage 3 measure → `runCaptured` `printcal -v -e [-I] [-z] [-a] [-m] [-xC…] -o out.cal CAL_{basename}` → Apply toggle drives profiling `printtarg -K` and post-colprof `applycal -a`.
- Collision Overwrite / Rename `{base}_{ISO}.cal` / Cancel. Stale: `calibration_stale_days` or printer mismatch. Curve SVG solid vs dashed identity.
- Spec: [07](07-stage0-calibration.md), [04](04-argyll-binaries.md) §1.3/§7/§8. Invariant **#224**.
- Deps: 2 (captured), 5, 7, 9, 15, 17, 19, 23, 24.
- Test CI: argv builders; `.cal` parse; toggle gates `-K`. Hardware: one cal loop on a real printer.

**Issue 30 — CGATS dataset interop**  
Labels: `Feature/Backend`, `Priority/Medium`  
Milestone: M6

- Import = **open** dialog + `setTarget` before jump (#211). Write canonical `.ti3` Argyll-strict. Device 0–255→0–100. Jump Stage 4/5; Stages 1–2 stay locked without `.ti1/.ti2`. User strings via `Text` only.
- Spec: [20](20-cgats-interop.md) #94/#211.
- Deps: 4, 6.
- Test CI: parse→write→reparse. Hardware: N/A.

**Issue 31 — About & help chrome**  
Labels: `Feature/UI`, `Priority/Medium`  
Milestone: M6

- About: version + build date from `getAppInfo`. Global help: **overlay** tooltips that do not reflow (#171). Notification banner auto-hide. Settings dialog already shipped in issue 5.
- Spec: [21](21-ui-reference.md), [22](22-settings-presets.md).
- Deps: 1, 5.
- Test CI: tooltips do not change layout height. Hardware: N/A.

**Issue 32 — Packaging, signing & CI**  
Labels: `Feature/DevOps`, `Priority/High`  
Milestone: M6

- **Self-hosted Mac runner** (Gitea has no `macos-latest` unless you attach one). Optional GitHub Actions mirror.
- Pipeline: `fetch-argyll` → ad-hoc `codesign -s -` + `codesign -dvv` on every sidecar Mach-O (hard fail) → `xcodebuild build test -scheme ICCery ARCHS="$(uname -m)"` (host arch; the dmgbuild leg still builds universal) → unit + mock fixtures (#215) → **dmgbuild** with background art (**not** Finder AppleScript, #189) → upload artefact.
- App signing: Developer ID + **notarize/staple** for the `.app` / `.dmg`. Sidecars remain **ad-hoc** inside the bundle (#165). These are two different gates — do not conflate.
- Confirm entitlements: sandbox **false**.
- Spec: [04](04-argyll-binaries.md) §0.6, [05](05-argyll-fork.md) §8–9, [23](23-assets.md), [24](24-issues-invariants.md).
- Deps: all v2.0 issues 1–15, 17–31.
- Test CI: unsigned sidecar fails; tests run; dmg produced. Hardware: Gatekeeper-open the notarized dmg on a clean Mac.

---

### Later (v2.1) — do not put on M3

**Issue 16 — Quartz print module (folded TargetPrint)**  
Labels: `Feature/Backend`, `Feature/UI`, `Priority/High`  
Milestone: **Later**

- Separate Swift package `ICCeryPrintKit`. **Zero** deps on wizard types.
- Public API: `TargetJob` v1 JSON + `--job` CLI (fire-and-forget) **and** in-process `NSPrintOperation`. Preserve extractability to a standalone app.
- ColorSync vocabulary is **not** the `lp` path: `PMColorMatchingMode=APCustomColorMatching`, `PMCustomColorMatchingProfile=""`, legacy `com.apple.print.PrintSettings.PMColorMatchingMode`. **Never mix with `AP_ApplicationColorMatching`** — amended by #201 (D2): with `lp` gone, ICCery's single native path writes **both** vocabularies; this constraint now governs only the future `ICCeryPrintKit` boundary.
- Vendor keys (separate table from issue 14): Epson `ColorModel=RGB` + `EPSONColorControls=Off`; Canon `CNColorMatching=None`; HP `ColorModel=RGB` + `HPColorControl=Off`.
- Geometry: 72pt=1in, no `backingScaleFactor`, interpolation `.none`, antialias off, pixel-integrity seam test. Resolve SPEC contradiction: job JSON `"centered": true` vs draw “no centering” — **lock “no centering, scale 1.0” for profiling targets.**
- AirPrint detection → persistent warning.
- Spec: [14](14-iccery-cpu-targetprint.md).
- Deps: 13, 17 (UI hook). Not required for M3 or M6 exit.
- Test CI: seam-integrity; module compiles standalone. Hardware: 1:1 on paper vs TIFF.

---

## Dependency graph (issue numbers)

```
1
├─ 2 ─ 3
│   └─ 4 ─ 6 ─ 5
│         ├─ 7 ─ 8
│         │   └─ 9 ─ 10 ─ 11
│         │         └─ 12 ─ 13 ─ 14 ─ 15 ─ 17
│         └─ 18 ─ 19 ─ 20
│                   ├─ 21, 22
│                   └─ 23 ─ 24 ─ 25 ─ 26
│                             └─ 27
├─ 28 ← 24
├─ 29 ← 7, 9, 15, 17, 19, 23, 24
├─ 30 ← 4, 6
├─ 31 ← 5
└─ 32 ← 1–15, 17–31

16 (Later) ← 13, 17
```

---

## Out of scope

- Windows GDI / DEVMODE / `CREATE_NO_WINDOW`; Linux `lp -o raw` / udev; NSIS/WiX.
- Display calibration (#90), i18n (#96).
- Linking Argyll. WKWebView/WebGL.
- Shipping TargetPrint as the v2.0 spooler.
- Migrating v0.8.5 `settings.json` / history (new bundle id on purpose). Add a ticket later if needed.

---

## Verification after filing

1. 7 milestones (M1–M6 + Later), all open.
2. 32 issues, all with `Project/ICCery-v2` + Feature + Priority + a milestone.
3. Issue 16 is on **Later**, not M3.
4. Issue 2 body contains `runCaptured`.
5. Issue 5 body contains the settings **dialog**.
6. Issue 1 min OS is **14.0** and bundle id is **`com.gronod.iccery2`**.
7. Spot-check issues 14, 15, 19, 24 for ColorSync SPI arity, no `-o raw`, no `s`/`u`, `iccgamut -d 10`.
