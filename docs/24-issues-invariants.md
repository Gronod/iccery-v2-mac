# 24 — Issue tickets and rewrite invariants

> Line numbers refer to ICCery v0.8.5 (`/tmp/ICCery` at analysis time) and the Gronod ArgyllCMS 3.5.0 fork.

Source corpus: Gitea issues `#1`–`#225` (`/tmp/iccery-research/issues/`), `issues-index.md`, `ROADMAP.md`, `git log` on `/tmp/ICCery` (main @ `e12ef41`, tag `v0.8.5`), PR titles pages 1–2, plus sibling issue dumps `argyll-issues.json` and `cpu-issues.json`.

This is a rewrite-invariants document. Every closed bug gets a **root cause → fix → invariant**. Features are traced so a rewrite does not re-invent the same CLI/IPC contracts.

Open tickets `#223` and `#224` are **implemented on main** (see § Open issues). Won't-fix `#90` / `#96` are documented in § Won't-fix.

---

## 1. Feature genealogy (issue → ship)

The product is a **printer-profiling workstation**: vanilla JS + Tauri v2 wrapping ArgyllCMS sidecars over stdin/stdout JSON (`-u`) with a disk-artefact wizard.

| Era | Version | Issues | What landed |
|---|---|---|---|
| Scaffold | `v0.1.0` | `#1`, `#2` | Tauri v2 shell, AGPLv3 isolation, `ProcessManager` with `process:stdout/stderr/exit` events |
| Stage 1–2 | `v0.1.3` | `#3`, `#4` | `targen` patch sets; `printtarg` layout + instrument geometry |
| Stage 3 | `v0.1.6` | `#5`, `#6` | `chartread -u` state machine + live swatch grid + ΔE₀₀ |
| Stage 4–5 | `v0.1.9` | `#7`, `#8` | `colprof` cLUT; `profcheck` peak/avg/RMS |
| Print + UI | `v0.1.10`–`0.1.13` | `#21`, `#23`, `#25`–`#28`, `#34`, `#54`, `#61` | Logo; raw GDI/CUPS print; DEVMODE prefs; collapsible logs; 1280×800 window |
| Gamut + ship | `v0.1.14`–`0.2.0` | `#9`, `#10`, `#57`, `#58`, `#60`, `#69` | `iccgamut` + Three.js; settings/packaging; artefact-gated wizard |
| Hotfix | `v0.2.1` | `#84` (from `#63` regression) | Stdin decoupled from `Child::wait()` |
| M8 | `v0.3.0` | `#86`, `#87`, `#88`, `#89` | `instlist`; multi-pass `average`; presets; 3D hull |
| Hotfixes | `v0.3.1`–`0.3.6` | `#103`, `#108`–`#116`, `#119`, `#127`, `#134`, `#137` | Browse dialogs, GLIBC, averaging snapshots, comm-port vs index, density vs dir, XSS/DPI, fetch-argyll, `ARGYLL_NOT_INTERACTIVE`, Accept/Override |
| macOS print | `v0.4.0` | `#91`, `#92` | Universal dmg path + CUPS raw spooler |
| Production | `v0.5.0`–`0.5.5` | `#139`–`#141`, `#147`/`#149`, `#151`, `#158`–`#165` | Logging, Stage 3 resume from `.ti2`, advanced `targen`, `kill_all` on exit, deterministic `-R 1`, universal sidecars |
| Enterprise colour | `v0.6.0`–`0.7.4` | `#94`, `#171`, `#172`, `#175`–`#179`, `#184`, `#185`, `#188`, `#189` | CGATS import, overlay tooltips, profile picker, `d`/`u` chartread keys, OBA/FWA, button system, swatch split, `.gam` dual-table parse, ΔE thresholds, ColorSync/vendor bypass, DMG background |
| Hardware + analytics | `v0.8.1`–`0.8.2` | `#204`, `#93`, `#95` | i1Pro2 `-Y l`; XY tables; drift history |
| Reliability | `v0.8.3`–`0.8.4` | `#210`–`#215`, `#225` | Native file pickers, Node-safe gamut tests, atomic history, frontend CI, Monterey WKWebView survival |
| Cal + install | `v0.8.5` | `#224`, `#223` (tickets still *open*) | Stage 0 `printcal`/`applycal`; OS profile install |

ArgyllCMS fork genealogy (why ICCery's CLI looks the way it does):

| Argyll issue | Flag / contract ICCery depends on |
|---|---|
| argyll `#1` | `chartread -u` → `ROW_COLORS_JSON:` per row |
| argyll `#2` | `targen -u` JSON progress |
| argyll `#3` | `printtarg -u` page manifest JSON |
| argyll `#4` | `colprof -u` JSON progress |
| argyll `#5` | `profcheck -u` JSON ΔE report |
| argyll `#6` | `instlist` JSON `{event:"instruments", devices:[{port,name,type}]}` |
| argyll `#19` | `printtarg -d "<label>"` custom chart legend (ICCery `#119`) |
| argyll `#24` | Windows anonymous-pipe `PeekNamedPipe` so `chartread` does not deadlock on `ReadFile` |
| argyll `#32` | ad-hoc `codesign -s -` of Mach-O sidecars (ICCery `#165`) |
| argyll `#37` | i1Pro2 LED — ICCery shipped as `chartread -Y l` (`#204`), **not** the originally proposed `-L` |

---

## 2. Closed bugs — root cause → fix → rewrite invariant

Grouped by subsystem. Issue numbers are always cited.

### 2.1 Process manager / IPC

**`#21` Process logs spill horizontally**
- **Root cause:** `#colprofLog` / `#profcheckLog` had no CSS; even stages with `white-space: pre-wrap` could not wrap Argyll's space-less progress dots.
- **Fix:** Class selector `.log-container pre { white-space: pre-wrap; overflow-wrap: anywhere; overflow-y: auto; max-height: 200px; }` (PR `#22`). Later `#54` made boxes collapsible.
- **Invariant:** All subprocess consoles share one CSS class. Never style per-stage IDs. Argyll stdout is not English prose; it is long runs of `.` and must wrap *anywhere*.

**`#46` Visible cmd.exe on every Argyll spawn (Windows)**
- **Root cause:** Sidecars are `IMAGE_SUBSYSTEM_WINDOWS_CUI`. `tokio::process::Command` without creation flags allocates a console.
- **Fix:** `command.creation_flags(0x08000000)` (`CREATE_NO_WINDOW`) in `ProcessManager::spawn` (`#[cfg(windows)]`).
- **Invariant:** Every Windows spawn of an Argyll CUI binary **must** set `CREATE_NO_WINDOW`. Do not "fix" this by rebuilding Argyll as WINDOWS_GUI — that would also kill stdin/stdout.

**`#63` Zombie children (enhancement that caused `#84`)**
- **Root cause:** 100 ms `try_wait` polling never removed finished `Child` handles.
- **Fix (PR `#77`):** `child.wait().await` and reap from the map.
- **Invariant:** Reap is required. But **never** `wait()` while still holding the `Mutex<Child>` that `send_stdin` needs — see `#84`.

**`#84` P0: `Child::wait()` deadlocks `send_stdin` and closes stdin (v0.2.1)**
- **Root cause:** PR `#77` awaited `c.wait()` under `Arc<Mutex<Child>>`. Tokio's `Child::wait` **drops stdin** to avoid parent/child deadlock. Interactive `chartread` therefore (1) could not acquire the mutex for Calibrate/Retry/Skip/Cancel, and (2) had its pipe closed immediately after spawn.
- **Fix (PR `#83`, v0.2.1):** `take()` stdin/stdout/stderr at spawn; store `ChildStdin` in a separate `stdins: HashMap<String, Arc<Mutex<ChildStdin>>>`; `tokio::select!` between `child.wait()` and a oneshot `kill_rx`.
- **Invariant:** Interactive subprocess lifetime has **three** independent handles: wait task, stdin mutex, kill oneshot. `send_stdin` must never take the `Child` lock. Never call `wait()` before `take()`-ing stdin.

**`#85` `resolve_binary` ignores `.exe`**
- **Root cause:** Path joins used `"targen"`; on disk the file is `targen.exe`. `exists()` returned false for custom dirs and bundled resources.
- **Fix (PR `#97`):** On Windows, try `{name}` and `{name}.exe` for both settings dir and resource resolution. Unit-test both.
- **Invariant:** Windows binary lookup is always a two-candidate search. Do not assume Unix names in `tauri.conf.json` resources.

**`#116` Duplicate spawn ids steal the live child's maps**
- **Root cause:** `stdins.insert(id)` / `killers.insert(id)` with no occupancy check. Averaging reuses `chartread_${basename}`. Old wait-task `remove()`s the **new** child's entries → "Process not found" on Calibrate.
- **Fix (PR `#123`):** Hard-error if `id` is occupied; disable Start / Measure Another Sheet until `process:exit`. Tokio test: spawn, reject duplicate, stdin still works, kill, reuse.
- **Invariant:** Process IDs are exclusive leases. Prefer a loud error over silently replacing the occupant. After exit, the id is reusable.

**`#134` Calibrate button does nothing; `instlist` shows nothing**
- **Root cause:** (1) Without `ARGYLL_NOT_INTERACTIVE=1`, Argyll on Windows uses `_getch()` / `ReadConsoleInput()`, ignoring piped stdin — especially combined with `#46`'s hidden console. (2) Forked `instlist` emits JSON; frontend only had a text regex.
- **Fix (PR `#135`, v0.3.5):** `command.env("ARGYLL_NOT_INTERACTIVE", "1")` on every spawn; parse `event === "instruments"` JSON with text fallback.
- **Invariant:** All Argyll children get `ARGYLL_NOT_INTERACTIVE=1`. Frontend instrument lists parse JSON first. Related upstream: argyll `#24` (`PeekNamedPipe` before `ReadFile` on anonymous pipes) — the env var is necessary but not sufficient on Windows.

**`#147` / `#149` Orphan `chartread` after window close**
- **Root cause:** Only Stage 3 Cancel called `kill_process`. `lib.rs` used bare `.run(...)` with no `RunEvent::Exit` / `CloseRequested`. Spectrophotometer stays USB-locked.
- **Fix:** `ProcessManager::kill_all` (drop stdins, signal killers, `start_kill`); hook app/window exit.
- **Invariant:** Host exit **always** drains the process table. Interactive instruments are the scary case, but `colprof`/`printtarg` must die too.

**`#158` Settings log level is decorative**
- **Root cause:** `tauri-plugin-log` filter hardcoded `Debug` vs `Info` from `cfg!(debug_assertions)`. `AppSettings.log_level` was persisted and ignored.
- **Fix:** Map stored string → `LevelFilter` at startup and on Save.
- **Invariant:** A settings control that does not change observable behaviour is a bug. Log level is runtime state, not a compile-time constant.

---

### 2.2 Print (Win / Mac / Linux)

**`#33` Windows CI: unresolved GDI imports**
- **Root cause:** `windows` crate 0.58 does not export `SetICMMode` / `ICM_OFF` under `Win32::Graphics::Gdi` as used in `print/windows.rs`. GitHub `windows-2025` runner compiled the print backend and died with `error[E0432]`.
- **Fix:** Declare the GDI printing functions/structs used (`CreateDCW`, ICM off, `StretchDIBits`, …) directly rather than depending on incomplete crate bindings (`a9802ad`, `c9e16ab`). Later also: runner label, native rustup, `shell: powershell`.
- **Invariant:** Colour-management bypass (`SetICMMode(ICM_OFF)`) is a **link-time** contract. Pin/vend the FFI; do not assume `windows` crate surface area. CI on the real Windows target is the only proof.

**`#36` DEVMODE preferences not applied**
- **Root cause:** OEM dialog (`DocumentPropertiesW`) writes public `DEVMODEW` **plus** `dmDriverExtra` private bytes. The print path was not forwarding the full buffer (and mishandled the anonymous union for `dmDefaultSource` / `dmOrientation`) into `CreateDCW`/`StartDocW`. Epson "Print Preview" etc. therefore vanished.
- **Fix:** Retain the entire DEVMODE allocation including `dmDriverExtra`; fix union field access (`19449e3`).
- **Invariant:** Windows driver settings are a **blob**, not a parsed struct. Never memcpy only `dmSize` bytes. Never reconstruct DEVMODE from a handful of public fields.

**`#48` CUPS/PPD "Uncorrected Passthrough" shown on Windows**
- **Root cause:** `#cupsOptionsGroup` rendered unconditionally.
- **Fix:** Hide on `navigator.userAgent` Windows (v0.1.7).
- **Invariant:** Print UI is per-backend. Windows = DEVMODE; Unix = PPD/CUPS. Do not show controls the active spooler cannot honour.

**`#67` Duplicate print IPC (cleanup, not a user bug)**
- **Fix:** Collapse `get_windows_printers`/`get_cups_printers`/`print_target_*` into `get_printers` / `print_target`.
- **Invariant:** One IPC surface, platform switch inside Rust.

**`#188` macOS: Preferences opens System Settings; no way to disable driver CM (Epson XP-55, Canon Pro 9500 II)**
- **Root cause:** "Preferences" deep-linked to the OS Printers & Scanners pane, not the selected queue's driver panel. ColorSync plus vendor filters (`CNIJIntent2`, Epson `ColorCorrection`) re-managed the raw target. Follow-on: `PMSessionSetColorMatchingMode` 3-arg SPI **crashed**.
- **Fix (v0.7.2–0.7.3):** Native `NSPrintPanel` bound to the current `PMPrinter`; PPD/`lpoptions` media-type extraction; vendor uncorrected-color keys; `AP_ColorMatchingMode=AP_ApplicationColorMatching`; **remove** the crashing 3-arg SPI and use the validated 2-arg / lock sequence (`8b01c98`). Windows media_types added in the same stack so CI still built.
- **Invariant:** Raw print means **three** layers must all be off: OS ColorSync, driver colour, and ICM/CUPS filters. Opening the generic Printers pane is not a preferences dialog. Never call private Core Printing SPIs whose arity is guessed.

**Sister-product traps (ICCery-CPU `#1`, `#2`, `#5`) that also apply to any CUPS rewrite:**
- PPD `ChoiceName/TranslationString` — UI must show the title, send the code (`MediaType=13` not `MediaType=Epson Premium Glossy`).
- Tray keywords are vendor-specific (`InputSlot` vs Epson `EPIJ_FdSo` vs Canon `CNIJMediaSupply`). Empty arrays are not `nil` — coalescing `?? ["Auto"]` does not fire.
- Canon Super Fine is three coordinated keys (`CNIJPrintQuality=0`, `CNIJPrintMode2=5`, `CNIJPQualitySlider=5`), not `cupsPrintQuality=High`.

---

### 2.3 Stage 1 — targen

**`#44` Patch count ignored → always 836**
- **Root cause:** Frontend sent `patch_count`; Rust `build_targen_args` only read `total_patches`. `-f` omitted → Argyll's built-in default **836** RGB patches.
- **Fix (v0.1.5, PR `#45`):** Honour `patch_count` (fallback `total_patches`); unit-test argv.
- **Invariant:** `targen` without `-f` is not "use the UI value". Default 836 is an Argyll formula, not an ICCery default. Serde field names must match across JS and Rust **and** be tested.

**`#59` Empty working directory**
- **Root cause:** Basename typed without Browse → `cwd: ""` → process launch dir (read-only / undefined). Same hole in later stages.
- **Fix (v0.1.12):** Init `currentWorkingDir` to `document_dir`/`home_dir`; disable Generate until both basename and cwd exist; backend also refuses empty cwd.
- **Invariant:** Empty cwd is illegal. Frontend guard **and** backend fallback. Never spawn Argyll in the install/resource directory.

**`#103` Stage 1 Browse does nothing; Generate stays disabled**
- **Root cause:** Frontend called `window.__TAURI__.dialog` (Tauri v1 API). With `withGlobalTauri: true` on Tauri v2, `window.__TAURI__.dialog` is **undefined**. Same class of bug as `#210`/`#211`.
- **Fix (v0.3.1, PR `#104`):** Backend command `select_target_file` using `app.dialog()`.
- **Invariant:** **Never** use `window.__TAURI__.dialog`. All file pickers are Rust commands with explicit filters. See also `#172`, `#210`, `#211`.

**`#162` Advanced options misaligned**
- **Root cause:** Mixed control heights (number vs range vs checkbox-without-label) plus a full-width `-c` row breaking the 2-col grid; flex-end hacks.
- **Fix (v0.5.5 / v0.6.1):** Semantic sub-groups, normalized row heights, flexbox auto-margins.
- **Invariant:** Advanced `targen` controls are a 2-column grid of equal-height rows. Checkboxes get a label column. Do not use `justify-content: flex-end` to fake alignment.

**`#172` Preconditioning browse filters `.ti1/.ti2/.ti3` instead of `.icc/.icm/.mpp`**
- **Root cause:** Reused `select_target_file` (target artefacts) for `targen -c`.
- **Fix:** Dedicated `select_profile_file`.
- **Invariant:** Each browse button has its **own** backend command and extension filter. Sharing "the dialog command" is how you open a Save-`.ti1` dialog for an ICC.

**`#211` CGATS Import opens a Save `.ti1` dialog and jumps to Stage 4 with empty basename**
- **Root cause:** `handleImport` invoked `select_target_file` (`save_file`, filter `ti1`). Empty `cwd`/`basename` were forwarded into `import_measurement_dataset`; `wizardState.setTarget` never ran.
- **Fix (v0.8.3):** `select_dataset_file` (open, filters `ti3/txt/cgats/csv`); sync wizard target dir+basename from the imported artefact.
- **Invariant:** Import = **open** dialog. After import, `basename`/`cwd` are initialized from the dataset before any stage jump. Do not reuse the target-save picker.

---

### 2.4 Stage 2 — printtarg

**`#50` Redundant Stage 2 badges (cleanup)**
- **Fix:** Remove duplicate status text. Not a functional invariant beyond "one source of layout truth".

**`#58` / `#70` TIFF previews fail in WebView; `image` crate Windows-only**
- **Root cause:** Browsers/WKWebView/WebView2 do not decode TIFF. `img.src = base64(tiff)` is a blank. `image` was under `[target.'cfg(windows)'.dependencies]` (GDI print), so Linux/macOS could not even compile a converter.
- **Fix:** Move `image` (png+tiff features) to common deps; `read_tiff_preview_png` decodes, caps ~1200 px, returns PNG base64. Keep `read_file_base64` for **text** artefacts (`.gam`).
- **Invariant:** Never feed TIFF to `<img>`. Preview pipeline is always TIFF→PNG in Rust. The `image` crate is a **common** dependency, not Windows-only.

**`#68` printtarg JSON parsed by hunting for a brace**
- **Root cause:** String-index search for `{\n  "event": "manifest"` instead of a structured object.
- **Fix:** Parse a single JSON event (Argyll `#3` `-u` manifest).
- **Invariant:** `-u` tools emit one JSON object per event. Accumulate stdout, `JSON.parse` whole objects; do not `indexOf` pretty-printed fragments.

**`#163` Regenerating Stage 2 shuffles patches (printed sheet ≠ `.ti2`)**
- **Root cause:** `printtarg` randomizes layout unless `-R <seed>` or `-r`. `build_printtarg_args` passed neither.
- **Fix (v0.5.5):** Default `-R 1`; optional custom seed and raster-order `-r`.
- **Invariant:** Printed charts are not reproducible without an explicit seed. Default is **deterministic**. Re-running Stage 2 on the same `.ti1` must produce the same `.ti2`/`.tif` or `chartread` will score the wrong patches.

**`#119` (feature, not bug) `printtarg -d` is a *label*, not a directory**
- See idiosyncrasies. Do not confuse with `iccgamut -d` (`#112`).

---

### 2.5 Stage 3 — chartread / averaging / XY

**`#109` Multi-pass averaging overwrites the same `.ti3`**
- **Root cause:** `#87` UI shipped, but every `chartread` wrote `{basename}.ti3`. Pass 2 clobbered pass 1. `average` was invoked as `foo.ti3 foo.ti3 foo.ti3`.
- **Fix:** After each successful exit, snapshot `{basename}.ti3` → `{basename}_pass{N}.ti3`. Canonical `{basename}.ti3` is written only at Finish (copy of pass1, or `average -v pass1 pass2 … basename.ti3`). Do **not** change the `chartread` inoutfile (still must match `.ti2` basename).
- **Invariant:** Measurement identity ≠ averaging identity. `chartread` always uses the chart basename. Pass files are snapshots. Stage 4 never sees a pass file unless Finish has run.

**`#110` Stage 4 unlocks on first pass, before Average**
- **Root cause:** `process:exit` of pass 1 called `wizardState.setStage3Result`. `verify_stage_artefacts` saw `{basename}.ti3` and enabled Stage 4 while "Measure Another Sheet" was still offered.
- **Fix:** Same PR as `#109`. `setStage3Result` only from **Finish and Average** / Accept-single-pass. Prefer the canonical-file rule over a new `stage3_accepted` flag.
- **Invariant:** Wizard gates on **disk artefacts with defined meaning**. `{basename}.ti3` means "accepted measurement", not "a pass happened".

**`#111` `instlist` ordinal passed as `chartread -c`**
- **Root cause:** Dropdown `value = inst.index` (1-based instrument list). `build_chartread_args` emitted `-c {index}`. Argyll `-c` is a **communication port** list (`chartread -??`), a different enumeration. Works by coincidence for a single USB i1Pro on port 1.
- **Fix:** Do not assume ordinal equality. Use `instlist` as presence/health; pass `-c` only when the value is a documented comm-port. Tighten regex to require instrument tokens.
- **Invariant:** `instlist` index ≠ `-c` port. After JSON `instlist` (argyll `#6` / ICCery `#134`), the field to pass is `device.port`, never the array index, and only if it is a real comm port.

**`#137` (feature) Accept/Override + multi-sheet prompts**
- Chartread emits multi-key warnings. UI must send the exact key (`n`/`y`/…) the prompt asks for, not just Enter.

**`#175` Stage 3 cannot complete — never sends `d`**
- **Root cause:** After the last strip, `chartread` waits for `d` (Done) before writing `.ti3`. ICCery never sent it. Follow-on: `snapshot_ti3` IPC used `passIndex` vs the deserializer's expected key.
- **Fix (v0.6.7–0.6.8):** Explicit **Done & Save .ti3** → `d\n`; **Undo Strip** → `u\n`; completion state machine; `invoke("snapshot_ti3", { passIndex })` camelCase to match Tauri v2 serde rename.
- **Invariant:** `chartread` is not finished when the last row JSON arrives. Done is a **keystroke**. Tauri v2 IPC argument names are camelCase on the JS side. Always add a completion control rather than inferring EOF.

**`#93` XY tables (SpectroScan / i1iO)** — feature, but its invariants are bug-shaped: classify **multi-line** prompts; fiducial alignment is a 4-step checklist; cancel must **park the head**.

**`#204` i1Pro2 LEDs** — pass `-Y l` (not `-L`). Silent no-op on instruments without LEDs.

---

### 2.6 Stage 4 — colprof

**`#56` Stage 4 is broken (IPC schema / process-id mismatch)**
- **Root cause:** `colprof.js` sent `{ basename, cwd }`. Rust expected `{ ti3_path, icc_path }`. Process IDs disagreed (`colprof_${basename}` vs `colprof_{icc_path}`), so UI listeners never fired even on a successful spawn.
- **Fix (PR `#64`, v0.1.11):** Align struct, argv builder, and process id with the frontend.
- **Invariant:** Spawn id is a **protocol**. Frontend listen-filters and backend spawn ids are the same string. Serde structs are tested against the JS payload, not against a parallel imagined schema.

**`#69` Profile extension `.icm` (Windows) vs `.icc` (Unix)**
- **Root cause:** Hardcoded `${basename}.icc`. Argyll `colprof` writes `.icm` on Windows. `profcheck` / `iccgamut` then "cannot find profile".
- **Fix:** Platform-aware resolver, or existence-check both extensions. Used by Stage 5 and gamut (`#57`).
- **Invariant:** Never hardcode `.icc`. Resolve `{icc, icm}` on disk. This also applies to install (`#223`) and preconditioning (`#172`).

**`#176` OBA/FWA + viewing conditions** — feature. `colprof -c` / `-d` here are **illuminant / viewing condition**, not directories and not `printtarg -d` labels.

**`#210` Custom `.sp` Browse: `window.__TAURI__.dialog` TypeError**
- **Root cause:** Identical to `#103`. No `select_spectrum_file` command.
- **Fix (v0.8.3):** Native `select_spectrum_file` (filter `.sp`).
- **Invariant:** Same as `#103`. Third time this class of bug shipped (`#103`, `#210`, `#211`). A rewrite should have a single `pick_file { filters }` command and never touch `window.__TAURI__.dialog`.

---

### 2.7 Stage 5 — gamut / profcheck / history

**`#57` 3D gamut is a dead panel**
- **Root cause:** `extract_gamut` / `loadGamutMesh` existed but nothing called them after `colprof`. `initGamutViewer` never stored meshes. Blocked by `#56` and `#69`.
- **Fix (v0.1.14):** Run `iccgamut` after successful profile; load printer `.gam` + bundled `sRGB.gam`; dispose previous geometries; `ResizeObserver` on the hidden Stage 5 canvas.
- **Invariant:** Gamut is a **post-colprof artefact**, not a demo mesh. Viewer must not allocate WebGL until the stage is shown (`#225`).

**`#112` `iccgamut -d 50.0` is surface density, not a directory**
- **Root cause:** `extract_gamut` passed `-d 50.0`. In Argyll, `iccgamut -d s` is **surface point density** (useful ~1–10). Density 50 yields thousands of vertices and freezes the O(n²) hull filter. Cwd is already set on the spawn.
- **Fix (PR `#121`):** `-d 10`; extract `build_iccgamut_args`; unit-test argv. Do not pass `-w` (VRML) unless required.
- **Invariant:** `-d` is **not** "directory" on `iccgamut`. Cwd is a ProcessManager concern. Density default is 10. Argv builders exist so this cannot silently regress.

**`#179` Mesh empty; profcheck cards show 0.00**
- **Root cause:** `.gam` has **two** CGATS tables (vertices `VERTEX_NO LAB_L LAB_A LAB_B`, then faces `VERTEX_0 VERTEX_1 VERTEX_2`). Parser kept only the first `BEGIN_DATA` and produced `{L,a,b}`. QuickHull indexed `p.x/p.y/p.z` → all undefined → empty hull. Profcheck regex expected one wording of `errors(CIEDE2000): max. =`; real output variants yielded 0.
- **Fix (v0.7.0):** Dual-table parse; map `x=a*, y=L*, z=b*`; use file faces when present; broader max/avg/rms regexes + user-visible parse warnings.
- **Invariant:** `.gam` is two tables. Lab is not XYZ-style `{x,y,z}` until remapped. Profcheck text is not a stable API — prefer `profcheck -u` JSON (argyll `#5`) and keep regex as fallback only.

**`#117` Inlined QuickHull** — modularize under `src/js/vendor/quickhull.js` (and later prefer file faces over recomputing hulls).

**`#185` Gamut rework** — CIELAB axes + CSS2D labels, `EdgesGeometry` sRGB reference, per-vertex `labToSrgb()`, layer toggles. Invariant: reference overlay is edges, not a competing solid that hides the profile.

**`#212` `gamut_viewer.test.js` : `window is not defined`**
- **Root cause:** Module top-level `const { invoke } = window.__TAURI__.core`. Node test import evaluates that before any polyfill. Unlike `profcheck.test.js` / `chartread.test.js`, no `globalThis.window` mock and no CLI auto-run.
- **Fix:** Guard `typeof window !== 'undefined'`; polyfill in the test; `node src/js/gamut_viewer.test.js` must exit non-zero on failure. Later `#215` runs this in CI.
- **Invariant:** Frontend modules that `import` in Node tests cannot touch `window` at load time. Tests are first-class; if AGENTS.md documents `node src/js/….test.js`, CI must run it (`#215`).

**`#213` `verification_history.json` non-atomic write**
- **Root cause:** `fs::write` in place. Crash ⇒ truncated JSON. `load_history_file` treats parse failure as **empty vec**, so the next save wipes the archive. Contradicted AGENTS.md's own atomic-write rule.
- **Fix (v0.8.4):** Write `.tmp`, flush/sync, `rename`.
- **Invariant:** History files are append-only user data. Write temp+rename. Parse failure must **not** be indistinguishable from "no history".

**`#95` Drift analytics** — 1,000-record cap, SVG dual-series, consecutive-breach card, RFC-4180 CSV. Relies on `#213`.

---

### 2.8 macOS window / WebKit

**`#61` Default window 800×600**
- **Fix:** 1280×800 default, min 1100×700.
- **Invariant:** The wizard + TIFF cards + WebGL viewer are not a mobile layout. Set min bounds in `tauri.conf.json`.

**`#148` Align `minimumSystemVersion` with Argyll**
- Argyll macOS builds and Tauri 2 / WebGL do not support 10.15 in practice.

**`#165` Unsigned Argyll sidecars `SIGKILL` on Apple Silicon**
- **Root cause:** arm64 requires at least ad-hoc signature. `fetch-argyll.mjs` staged Jam-built unsigned Mach-Os into Resources. Kernel kills with `Killed: 9`, no useful error.
- **Fix:** Upstream argyll `#32` (`v3.5.0-ICCery.1.5`) `codesign -f -s -` in `makepackagebin.sh` + CI `codesign -dvv`, including `lipo` fat binaries.
- **Invariant:** Every shipped Mach-O sidecar is signed (ad-hoc at minimum). Fetch pipeline must verify signatures, not assume "it ran on Intel".

**`#164` Universal binary (Intel + arm64)**
- Need universal Argyll archive (argyll `#27`), runtime fallback if a slice is missing, CI `--no-run` when cross-compiling tests for the other arch.

**`#225` Monterey white-flash loop then silent exit (v0.8.4)**
- **Root cause:** Main window `visible: true` with no dark backing. `initGamutViewer()` created `THREE.WebGLRenderer({ antialias: true, alpha: true })` and started rAF at `DOMContentLoaded` **while Stage 5 was hidden**. On macOS 12 (esp. Intel GPU) the Web Content/GPU helper died; WKWebView respawned its **white** default store; after a few cycles the host tore the window down. No Crash Reporter on `ICCery.app`. `minimumSystemVersion` still claimed 10.15.
- **Fix:** Defer WebGL until the gamut viewer is shown; survive context-lost; hide window until first paint; dark WKWebView `backgroundColor`; log unexpected window destroy / Web Content death; raise `minimumSystemVersion` to **12.0**.
- **Invariant:** Do not create a WebGL context at startup. Do not show a window before first paint on macOS. Helper-process death ≠ app crash — log it. Support matrix must match WKWebView/WebGL reality.

---

### 2.9 Packaging / CI

**`#38` Unused / duplicated crates** — audit deps; don't let Windows-only crates leak (inverse of `#70`).

**`#40` Linux CI too slow**
- **Fix (PR `#41`):** Allow strip (`NO_STRIP` off), rust-cache `workspaces: "src-tauri -> target"`, apt archive cache, `--bundles deb,appimage` (skip rpm), upload-artifact v4.

**`#42` Windows MSI/NSIS branding.**

**`#52` Strip foreign-platform Argyll binaries from each OS bundle.**
- **Invariant:** A Windows installer must not ship `linux-x86_64/` and `macOS/` trees. Fetch-at-build (`#127`) makes this a packaging filter, not a git-lfs problem.

**`#80` Mermaid diagram does not render**
- **Root cause:** Node label `Raw Print Subsystem (GDI / CUPS)` — parentheses parsed as shape syntax.
- **Fix:** Quote / drop parens.
- **Invariant:** Mermaid node text with `()` must be quoted.

**`#91` Universal `.dmg` + codesign pipeline (still evolving through `#189`).**

**`#108` `.deb` requires GLIBC_2.39 (won't run on Ubuntu 22.04)**
- **Root cause:** Linux CI runner newer than the support target. Binary linked against glibc 2.39; 22.04 ships 2.35.
- **Fix (v0.3.2):** Build on **Ubuntu 22.04 LTS**.
- **Invariant:** The CI image **is** the minimum glibc. If you support 22.04, you build on 22.04 (or older), not `ubuntu-latest`.

**`#127` Fetch Argyll at build time + Windows USB driver offer**
- Removed vendored binaries. NSIS hook for `ArgyllCMS_install_USB.exe`. Follow-on Windows NSIS bugs in the same train: LogicLib admin check, domain-user install path must be a local fixed disk, shell-folder drive mapping, skip WebView2 bootstrapper `msiexec` invalid-drive.
- **Invariant:** Sidecars are release artefacts of `gronod/argyllcms`, not git blobs. Windows USB instruments need the libusb0 INF. Packaging scripts must `tr -d '\r'` manifest lists (argyll `#21` — CRLF in `binfiles` dropped drivers/docs from the zip).

**`#189` DMG has no background image**
- AppleScript Finder decoration does not run headlessly. Multiple CI attempts (`#196`, `#208`, `#219`) then **dmgbuild** (`#222`, commit `6976ced`).
- **Invariant:** Do not use Finder AppleScript to style a DMG on a headless runner. Use `dmgbuild`.

**`#215` Frontend tests not in CI**
- Added `npm test` (profcheck, chartread, gamut_viewer) to macOS/Linux/Windows workflows. Prevents `#212`-class breakage.

**`#214` Docs drift** — AGENTS/README/licenses vs code. Keep ROADMAP version = Cargo version (`#115`, `#152`).

---

### 2.10 Security (innerHTML presets)

**`#114` Preset manager XSS via `innerHTML`**
- **Root cause:** `renderManagePresetsList` interpolated `p.name` / `p.description` into `innerHTML`. Imported JSON is attacker-controlled. Tauri WebView is a privileged surface (`<img src=x onerror=…>` runs with backend IPC).
- **Fix (PR `#122`, with `#113`):** `createElement` + `textContent`. Optional Rust reject of `<` / control chars. **No** HTML sanitizer.
- **Invariant:** Untrusted strings (preset import, CGATS descriptors, chart labels, log excerpts) never go through `innerHTML`. `textContent` only.

---

### 2.11 Settings / presets / wizard chrome

**`#113` `applyPreset` never applies TIFF DPI**
- **Root cause:** Schema had `dpi`; Fast RGB Draft is 150. `applyPreset` skipped `#tiffDpi`; `collectCurrentSettingsAsPreset` hardcoded `dpi: 300`.
- **Fix:** Round-trip `#tiffDpi` (72–600); show DPI in manage-presets subtitle.
- **Invariant:** Every `ProfilingPreset` field that exists on disk has a DOM binding in both directions. Adding a Stage 1/2/4 control without a preset field (or vice versa) is a bug. (v0.7.0 also broke the build by adding fields without updating the struct — `c917f05`.)

**`#60` Wizard is not a wizard**
- **Root cause:** Stepper allowed clicking Stage 5 with no files. Modules fell back to `"test_target"`.
- **Fix (v0.1.15 / v0.2.0):** Gate `.ti1` → `.ti2`+`.tif` → `.ti3` → `.icc`/`.icm`. Remove every `|| "test_target"`. Completed stages remain clickable backwards.
- **Invariant:** No placeholder basenames. Navigation = disk. `#151` re-validates artefacts on stage entry and app start (deleted files must re-lock).

**`#171` Tooltips reflow the layout**
- **Root cause:** Tooltip content inserted in-flow.
- **Fix (v0.6.2):** Absolute overlay on hover/focus; in-flow hints only when the global "show tooltip hints" toggle is on.
- **Invariant:** Hover must not change document flow.

**`#184` Configurable ΔE₀₀ thresholds** — settings persistence applied to the Stage 3 traffic lights. Same "settings must actually apply" rule as `#158`.

---

### 2.12 UI leftovers that still encode invariants

**`#178` Swatch grid:** honour `is_pad` (padding patches, `id == "0"`); render white patches; diagonal split intended vs measured; `printtarg` row/column order is canonical after bi-directional reverse. Device channels are 0–100%; XYZ in JSON is 0–100 and **must be /100** before `icmXYZ2Lab`.

**`#177` Buttons:** `.btn-sm/.btn-md/.btn-lg/.btn-icon-sq` only. No inline sizes. `#223` install button must use this hierarchy.

**`#140` Resume:** opening a `.ti2` jumps to Stage 3; `.ti1` to Stage 2. Parse header (instrument, patch count, colorants, pages). Do not regenerate `#163`-style random layouts over a chart that was already printed.

---

## 3. Open issues — implemented on main (`v0.8.5`)

Gitea still shows these as **open**. Git on `main` (merge `e12ef41`, tag `v0.8.5`) already contains the work. ROADMAP "Printer Calibration Release (`v0.8.5`)" matches.

| Ticket | State in tracker | Evidence on `main` | What shipped |
|---|---|---|---|
| **`#223` System-wide ICC/ICM install** | open | `980b44b` `feat(stage5): install generated ICC/ICM profiles into the OS (#223)` ; PR `#228` → development; PR `#229` → main | Stage 5 "Install Profile to System": copy into OS colour store (user or system), overwrite/rename/cancel, elevation guidance, note when printcal curves were applied |
| **`#224` printcal / applycal** | open | `24318bc` `feat(cal): printer linearization via printcal / applycal (#224)` ; PR `#227` → development; PR `#229` → main | Optional Stage 0: `CAL_` artefacts, Apply Calibration toggle → `printtarg -K` + `applycal`, channel-response plots, stale-cal warnings, project/library persistence |

Rewrite must treat Stage 0 calibration and Stage 5 install as **shipped** contracts, not backlog. Close the tickets when convenient.

---

## 4. Won't-fix

### `#90` Display wizard (`dispwin` / `dispread`) — Reviewed/Won't Fix

Asked for a second wizard mode: emissive monitor profiling (white point, gamma, cd/m², colorimeter loop, `dispwin -I` install).

**Why not:**
- ICCery's architecture, print engine, artefact chain (`.ti1`→`.tif`→`.ti3`→`.icc`), and raw-print colour-bypass work are **reflective printer** problems. Display calibration is a different product (full-screen test patches, VCGT, per-monitor ColorSync/ICC install).
- `dispwin`/`dispread` already *are* interactive GUIs; wrapping them duplicates Argyll's own display tools and DisplayCAL without sharing the print pipeline.
- Hardware, prompts, and OS install APIs do not reuse Stage 3's strip-reader state machine.
- Priority/Low, closed the same day it was filed during M8 triage. Printer-only scope is the product.

Do not quietly add a "Print vs Display" toggle in a rewrite. If display profiling happens, it is a separate app.

### `#96` i18n (en/de/fr/ja) — Reviewed/Won't Fix

ROADMAP: *Closed — Won't Fix (English UI retained as standard color-management terminology).*

**Why not:**
- The domain language **is** English: ΔE₀₀, cLUT, CGATS, Lab, FWA, OFPS, `targen -f`. Translating chrome without translating Argyll's English prompts (`Place the instrument on its reflective white reference…`) produces a mixed UI. Translating prompt matchers (`#137`, `#93`, `#175`) is how Stage 3 silently deadlocks.
- Argyll itself is English-only; `ARGYLL_NOT_INTERACTIVE` keystroke protocol is letter keys (`d`, `u`, `n`), not localized buttons.
- Cost of four complete dictionaries + locale-aware regex across every prompt classifier exceeded the value for a specialist tool.

Keep the UI English. Do not introduce `t()` until prompt classification is table-driven **and** Argyll grows locale support — which it will not.

---

## 5. Idiosyncrasies (do not rediscover)

These are the sharp edges issues burned in. A rewrite that "simplifies" any of them will re-open the ticket.

### 5.1 Argyll CLI is a minefield of one-letter flags

| Tool | Flag | Means | Ticket |
|---|---|---|---|
| `targen` | `-f N` | patch count; omit ⇒ **836** RGB | `#44` |
| `targen` | `-c file` | preconditioning **profile** (`.icc/.icm/.mpp`) | `#172` |
| `targen` | `-u` | JSON progress | argyll `#2` |
| `printtarg` | `-d "str"` | **custom label** on the chart | `#119` / argyll `#19` |
| `printtarg` | `-D` | 8-bit TIFF dither (different letter) | argyll `#19` |
| `printtarg` | `-R N` | PRNG seed; omit ⇒ non-deterministic layout | `#163` |
| `printtarg` | `-r` | raster order, no randomize | `#163` |
| `printtarg` | `-K` | apply calibration (Stage 0) | `#224` |
| `printtarg` | `-u` | JSON page manifest | `#68` / argyll `#3` |
| `chartread` | `-u` | `ROW_COLORS_JSON:` stream | `#5` / argyll `#1` |
| `chartread` | `-c N` | **comm port**, not instlist index | `#111` |
| `chartread` | `-d` | **display** read mode (not a directory, not a label) | argyll `#37` audit |
| `chartread` | `-Y l` | i1Pro2 LED (not `-L`) | `#204` |
| `chartread` | stdin `d` | **Done**, write `.ti3` | `#175` |
| `chartread` | stdin `u` | undo last strip | `#175` |
| `iccgamut` | `-d s` | **surface density** (use 10, not 50, not a path) | `#112` |
| `colprof` | `-d` | viewing condition | `#176` |
| `colprof` | `-c` | illuminant / FWA | `#176` |
| `colprof` | `-u` | JSON progress | argyll `#4` |
| `profcheck` | `-u` | JSON ΔE report | argyll `#5` |
| `instlist` | stdout JSON | `{event:"instruments", devices:[{port,name,type}]}` | `#134` / argyll `#6` |

**Same letter, four meanings of `-d`:** printtarg label, iccgamut density, chartread display mode, colprof viewing condition. Never name a helper `dash_d` without the tool.

### 5.2 Process / Windows / stdin

- Argyll binaries are **console** subsystem → `CREATE_NO_WINDOW` (`0x08000000`) (`#46`).
- `ARGYLL_NOT_INTERACTIVE=1` is mandatory or Windows ignores pipes (`#134`).
- Even then, Argyll's `SetNamedPipeHandleState(PIPE_NOWAIT)` **fails on anonymous pipes**; upstream `PeekNamedPipe` (argyll `#24`) is required or the instrument trigger never fires.
- `Child::wait()` drops stdin (`#84`). Take streams first; store stdin separately; kill via oneshot.
- Spawn ids are exclusive (`#116`).
- App exit must `kill_all` (`#147`, `#149`) or the spectro stays locked.
- Windows resolve: `targen` **and** `targen.exe` (`#85`).
- `tokio::process` + GDI print FFI: don't trust `windows` crate completeness (`#33`).

### 5.3 Files, extensions, artefacts

- `colprof` writes **`.icm` on Windows, `.icc` on Unix** (`#69`). Always probe both.
- Wizard chain: `.ti1` → `.ti2` + `.tif` → `.ti3` → `.icc`/`.icm` (+ `.gam`) (`#60`, `#151`).
- `{basename}.ti3` is the **accepted** measurement; passes live in `{basename}_passN.ti3` (`#109`, `#110`).
- Calibration artefacts use `CAL_` prefix and `.cal` (`#224`).
- TIFF is not a web image (`#58`). Convert in Rust.
- `.gam` = vertex table **plus** face table (`#179`).
- History JSON: atomic rename or you delete the user's drift archive (`#213`).
- Empty cwd is forbidden (`#59`).

### 5.4 Frontend / Tauri v2

- `window.__TAURI__.dialog` **does not exist**. Three tickets (`#103`, `#210`, `#211`). File dialogs are Rust commands with dedicated filters.
- Tauri v2 invoke args are **camelCase** (`passIndex`, not `pass_index`) (`#175`).
- JS payload field names must match Rust (`patch_count` vs `total_patches` — `#44`; `basename/cwd` vs `ti3_path/icc_path` — `#56`).
- Spawn id strings are part of the UI protocol (`colprof_${basename}`).
- Do not `innerHTML` untrusted preset/CGATS text (`#114`).
- Do not read `window` at module top-level if Node tests import the file (`#212`).
- Do not create WebGL on `DOMContentLoaded` (`#225`).
- Tooltips are overlays (`#171`).

### 5.5 Colour / print pipeline

- Raw print = unmanaged raster. Bypass **OS + driver + ICM** (`#25`–`#28`, `#36`, `#188`).
- Windows: full DEVMODE blob including `dmDriverExtra` (`#36`); `SetICMMode(ICM_OFF)` (`#33`).
- macOS: `AP_ApplicationColorMatching` + vendor keys (`CNIJIntent2`, Epson `ColorCorrection`); never crash-call 3-arg `PMSessionSetColorMatchingMode` (`#188`).
- PPD: send **choice codes**, display **titles**; vendor keywords differ (`InputSlot` / `EPIJ_FdSo` / `CNIJMediaSupply`; `MediaType` / `CNIJMediaType`) — CPU `#1`/`#2`.
- Hide CUPS widgets on Windows (`#48`).
- Default printtarg seed `-R 1` (`#163`).
- Device JSON is 0–100%; XYZ 0–100 must be divided by 100 before Lab (`ROW_COLORS_JSON` contract, argyll `#1`).
- Padding patches: `is_pad` / `id == "0"` (`#178`).

### 5.6 Packaging

- Linux: build on the oldest glibc you support (`#108` = Ubuntu 22.04).
- Strip foreign Argyll trees (`#52`).
- Fetch sidecars from `gronod/argyllcms` releases (`#127`); verify macOS ad-hoc signatures (`#165`).
- Manifest copy loops: strip CR (`\r`) or Windows zips silently omit USB drivers (argyll `#21`).
- Headless DMG: `dmgbuild`, not Finder AppleScript (`#189`).
- `minimumSystemVersion` is 12.0 after Monterey WebKit reality (`#225`), not 10.15.

### 5.7 Defaults people will hardcode wrong

- Patch count default if `-f` missing: **836**, not 0, not 1000 (`#44`).
- TIFF DPI built-in Standard = 300; Fast RGB Draft preset = **150** (`#113`).
- `iccgamut -d` = **10** (`#112`).
- Window 1280×800, min 1100×700 (`#61`).
- Log level is a setting, not `cfg!(debug_assertions)` (`#158`).
- LED flag is `-Y l` (`#204`).

---

## 6. Suggested rewrite test locks (from the tickets)

If the rewrite has tests, these are the ones the history says you will regret omitting:

1. `build_targen_args` includes `-f` from `patch_count` (`#44`).
2. `build_printtarg_args` includes `-R 1` (or explicit seed) (`#163`).
3. `build_iccgamut_args` is `-v -d 10 {profile}` — never a path, never 50 (`#112`).
4. `build_chartread_args` does not pass instlist ordinal as `-c` (`#111`).
5. Windows `resolve_binary("targen")` finds `targen.exe` (`#85`).
6. ProcessManager: duplicate id errors; stdin works during wait; kill_all on drop (`#84`, `#116`, `#149`).
7. Averaging: two snapshots, `average` argv unique files, Stage 4 locked until Finish (`#109`, `#110`).
8. Preset round-trip includes DPI; imported `<img onerror>` is text (`#113`, `#114`).
9. Profile resolver accepts `.icc` and `.icm` (`#69`).
10. `.gam` dual-table parse; profcheck JSON then regex fallback (`#179`).
11. History write is temp+rename (`#213`).
12. Node can `import` gamut/profcheck/chartread modules (`#212`, `#215`).

---

## 7. PR title index (page 2, remaining)

Page 2 of `pulls?state=all&limit=50&page=2` (older half of the genealogy):

`#144` Stage 1 advanced targen (`#141`) · `#143` resume `.ti2` (`#140`) · `#142` logging (`#139`) · `#138` Accept/Override (`#137`) · `#136`/`#135` v0.3.5 `ARGYLL_NOT_INTERACTIVE` (`#134`) · `#133` v0.3.4 · `#132` printtarg `-d` (`#119`) · `#131` v0.4.0 · `#130` macOS CUPS (`#92`) · `#129`/`#128` fetch-argyll (`#127`) · `#126` v0.3.3 · `#125` QuickHull module (`#117`) · `#124` docs v0.3.2 (`#115`) · `#123` duplicate spawn (`#116`) · `#122` preset DPI+XSS (`#113`,`#114`) · `#121` iccgamut density (`#112`) · `#120` comm port (`#111`) · `#118` averaging unique ti3 (`#109`,`#110`) · `#107` release asset naming · `#105`/`#104` Stage 1 browse (`#103`) · `#102` v0.3.0 · `#101` 3D hull (`#89`) · `#100` presets (`#88`) · `#99` averaging (`#87`) · `#98` instlist (`#86`) · `#97` `.exe` (`#85`) · `#83` process deadlock v0.2.1 (`#84`) · `#81` mermaid (`#80`) · `#79` print IPC consolidate (`#67`,`#68`) · `#77` wait/reap (`#63`) · `#75` wizard gating (`#60`) · `#74` gamut+extension (`#57`,`#69`) · `#73` TIFF PNG + window (`#58`,`#61`) · `#72` default cwd (`#59`) · `#64` colprof IPC (`#56`) · `#55` collapsible logs (`#54`) · `#53` strip foreign binaries (`#52`) · `#51` Stage 2 cleanup (`#50`) · `#49` hide CUPS on Windows (`#48`) · `#47` `CREATE_NO_WINDOW` (`#46`) · `#45` targen `-f` (`#44`) · `#43` installer art (`#42`) · `#41` Linux CI (`#40`)

Recent page-1 merges of note: `#229` v0.8.5 (`#223`+`#224`) · `#228` install · `#227` printcal · `#226` Monterey (`#225`) · `#222` dmgbuild (`#189`).
