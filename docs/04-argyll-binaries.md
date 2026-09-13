# 04 — Argyll binary invocations

> Line numbers refer to ICCery v0.8.5 (`/tmp/ICCery` at analysis time) and the Gronod ArgyllCMS 3.5.0 fork.

Source tree: `/tmp/ICCery` (v0.8.5). ICCery never links Argyll; every binary is spawned as an isolated subprocess (`calibration.rs:1–4`). Sidecars come from the ICCery-patched fork `gronod/argyllcms` (GitHub `Gronod/argyllcms`), not stock Graeme Gill builds.

Two spawn paths exist:

| Path | Used by | Streams | Events |
|---|---|---|---|
| `ProcessManager::spawn` | targen, printtarg, chartread, average, colprof, profcheck, iccgamut, instlist | piped stdin/stdout/stderr, line-by-line | `process:stdout`, `process:stderr`, `process:exit`, `process:error`, `process:json_row` |
| `calibration::run_captured` | printcal, applycal | `.output().await` (full capture) | none — returns `(exit_code, stdout, stderr)` to the Tauri command |

---

## 0. Shared infrastructure

### 0.1 Binary resolution — `resolve_binary`

`commands.rs:40–106`. Public Tauri command **and** internal helper.

Order of search:

1. Settings `argyll_binary_dir` (Settings dialog, `AppSettings.argyll_binary_dir`). If non-empty, join each candidate name; first existing path wins.
2. Bundled sidecar at `argyll/{platform}/{name}` under Tauri `BaseDirectory::Resource`.
3. If the resource path does not exist, **still return the constructed resource path** (does not search `$PATH`). Missing binaries surface later as spawn `process:error`.

`get_binary_candidates` (`commands.rs:40–46`):

- Windows: `["{name}.exe", "{name}"]` unless `name` already ends with `.exe`.
- Unix: `["{name}"]`.

Platform directory selection (`commands.rs:65–83`, mirrored in `build.rs:26–44`):

| OS / arch | Resource dir |
|---|---|
| linux x86_64 | `linux-x86_64` |
| windows x86_64 | `windows-x86_64` |
| macos aarch64 | `macos-universal` if `argyll/macos-universal/instlist` exists, else `macos-aarch64` |
| macos x86_64 | `macos-universal` if that marker exists, else `macos-x86_64` |
| anything else | `linux-x86_64` (fallback) |

`default_instrument` is stored in settings (`settings.rs:76`) and shown in the Settings dialog, but **is never read when building any Argyll argv**. Instrument comes from Stage 2 `#instrumentSelect`.

### 0.2 Working directory — `resolve_safe_cwd`

`commands.rs:203–217`. If `cwd_input` is a real directory, use it. Else: `document_dir` → `home_dir` → `app_data_dir`.

All specialised `run_*` commands pass `Some(resolve_safe_cwd(&app, &config.cwd))`. Exceptions:

- `detect_instruments` / `spawn_process`: `cwd = None` (inherit parent cwd).
- `extract_gamut`: parent of the ICC file, or default cwd if empty.
- `apply_calibration`: parent of the input profile.

### 0.3 Environment variables

Set on **every** spawn (ProcessManager **and** `run_captured`):

```
ARGYLL_NOT_INTERACTIVE=1
```

- ProcessManager: `process_manager.rs:97`
- `run_captured`: `calibration.rs:848`

This is the ICCery-side half of `gronod/argyllcms#24` (Windows anonymous-pipe deadlock). It forces Argyll's `check_if_not_interactive()` path so `con_char()` uses pipe I/O instead of a console. Added in ICCery#134 (`3d514b6`).

**Never set:**

- `ARGYLL_3D_DISP` — grep of the tree is empty. `iccgamut` is invoked without any 3D-display env; the `.gam` file is parsed in JS (`gamut_viewer.js`).
- `PATH` — not mutated. Binaries are always absolute paths from `resolve_binary`. Inherited PATH is whatever the OS/session provides (needed only if a user-supplied `argyll_binary_dir` binary dlopens something).

### 0.4 Windows `CREATE_NO_WINDOW`

Both spawn paths:

```rust
const CREATE_NO_WINDOW: u32 = 0x08000000; // 0x08000000
command.creation_flags(CREATE_NO_WINDOW);
```

- ProcessManager: `process_manager.rs:99–103`
- `run_captured`: `calibration.rs:849–853`

Fixes ICCery#46 (v0.1.6, `ec6205b`): Argyll tools are `IMAGE_SUBSYSTEM_WINDOWS_CUI`; without this flag a black console covers the UI.

`CommandExt` is pulled in via `tokio::process::Command::creation_flags` (tokio re-exports the Windows ext).

### 0.5 Event schema (ProcessManager only)

`events.rs`:

```rust
ProcessEventPayload { id: String, line: Option<String>, code: Option<i32>, error: Option<String> }
JsonRowPayload      { id: String, json: String }
```

| Event | When | Fields |
|---|---|---|
| `process:stdout` | every stdout line **except** those starting `ROW_COLORS_JSON: ` | `id`, `line` |
| `process:stderr` | every stderr line | `id`, `line` |
| `process:json_row` | stdout line prefixed `ROW_COLORS_JSON: ` (prefix stripped) | `id`, `json` (raw JSON string) |
| `process:exit` | child reaped | `id`, `code` (`status.code().unwrap_or(0)` on natural exit; `unwrap_or(1)` on kill) |
| `process:error` | `Command::spawn` failed | `id`, `error` |

Stdout reader (`process_manager.rs:128–139`):

```rust
const JSON_ROW_PREFIX: &str = "ROW_COLORS_JSON: ";
if line.starts_with(JSON_ROW_PREFIX) {
    emit_json_row(..., line[JSON_ROW_PREFIX.len()..]);
} else {
    emit_stdout(...);
}
```

JSON-row lines are **not** forwarded as `process:stdout` and are **not** written to the subprocess log as info lines.

Logging: spawn logs sanitised argv (`~` for `$HOME`/`%USERPROFILE%`) at info, raw argv at debug (`process_manager.rs:28–60, 105–119`). Each stdout line → `log::info!`, stderr → `log::warn!`, exit → `log::info!`.

### 0.6 Sidecar fetch / bundle

`scripts/fetch-argyll.mjs` downloads from `https://github.com/Gronod/argyllcms/releases` (override: `ARGYLL_SERVER_URL`, `ARGYLL_REPO`, `ARGYLL_RELEASE_TAG`). Marker binary is `instlist` / `instlist.exe`. Windows also copies `usb/` (`ArgyllCMS_install_USB.exe`, `ArgyllCMS.inf`) to `src-tauri/argyll/usb/`.

`tauri.conf.json:38–40`: `"resources": ["argyll/**/*"]`.

`build.rs:19–64` panics the compile if the platform marker is missing (`npm run fetch-argyll` required).

NSIS (`windows/hooks.nsh:133–158`): admin install prompts “Install ArgyllCMS USB instrument drivers?” and `ExecWait`s `ArgyllCMS_install_USB.exe`. Uninstall does **not** run `ArgyllCMS_uninstall_USB.exe`.

---

## 1. `targen` — Stage 1 patch generation **and** Stage 0 calibration chart

### 1.1 When

| UI | Command | Process id |
|---|---|---|
| Stage 1 **Generate** (`#btnGenerate`) | `run_targen` | `targen_{basename}` |
| Stage 0 **Generate Calibration Target** (`#btnCalGenerate`) | `generate_calibration_target` | `targen_{CAL_basename}` |

`run_targen`: `commands.rs:952–964`. `generate_calibration_target`: `calibration.rs:598–613`. Both go through ProcessManager.

Stage 0 prefixes the basename with `CAL_` (`calibration_basename`, never double-prefix). Calibration charts must not collide with the profiling `.ti1`.

### 1.2 Profiling argv — `build_targen_args` (`commands.rs:788–905`)

Always starts `-v -d {2|4}`. Colour space is the only discriminator for `-d`: RGB → `2`, CMYK → `4`. No other colourant counts.

| UI field (`#id` / config) | Flag | Condition |
|---|---|---|
| `#colourSpace` radio (`colour_space`) | `-d 2` or `-d 4` | always |
| `#patchCountPreset` / `#patchCountCustom` (`patch_count`, else `total_patches`) | `-f N` | N > 0; JS default 800 |
| `#whitePatches` (`white_patches`) | `-e N` | Some |
| `#blackPatches` (`black_patches`) | `-B N` | Some. JS: RGB default 4, CMYK default 0 on colour-space change |
| `#targenGreySteps` (`grey_steps`) | `-g N` | Some and N > 0 |
| `#targenSingleChannelSteps` (`single_channel_steps`) | `-s N` | Some and N > 0 |
| `#targenPrecondProfile` (`preconditioning_profile`) | `-c PATH` | non-empty trim |
| `#targenNeutralSteps` (`neutral_steps`) | `-n N` | Some and N > 0 |
| `#targenNeutralConcentration` (`neutral_concentration`) | `-N x.xx` | Some and `|x-0.50| > 0.001` (slider default 0.50 → omitted) |
| `#targenHighQuality` (`ofps_high_quality`) | `-G` | `Some(true)` |
| `#targenAdaptation` (`ofps_adaptation`) | `-A x.xx` | Some (even 0.10 — **no** default-skip) |
| `#targenAlgorithm` (`full_spread_algorithm`) | `-t` `-r` `-R` `-q` `-Q` `-i` `-I` | value in that set; `"ofps"` / default → no flag |
| `#targenInkLimit` (`total_ink_limit`) | `-l N` | **CMYK only**, 1..=400 |
| `#targenDarkEmphasis` (`dark_emphasis`) | `-V x.xx` | Some and `|x-1.0| > 0.001` |
| `#targenDevicePower` (`device_power`) | `-p x.xx` | Some and `|x-1.0| > 0.001` and `x > 0` |
| `#targetBasename` | positional | last arg, no extension |

**Not passed:** `-u` (Argyll fork has `targen -u` JSON progress — ICCery never enables it). `-v` always.

JS config construction: `targen.js:295–314`. On success (`code === 0`) advances to Stage 2 via `setStage1Result` + `wizardState.navigateToStage(2)`.

### 1.3 Calibration argv — `build_calibration_targen_args` (`calibration.rs:146–189`)

Hard-wired for a short per-channel wedge, **not** a full-spread profile chart:

```
-v -d {2|4} -s {steps} -g {steps} [-n {steps}] -e {white|4} [-l TAC] -f 0 {CAL_basename}
```

| UI / config | Flag | Condition |
|---|---|---|
| `#calColourSpace` | `-d 2` / `-d 4` | rgb / cmyk |
| `#calSteps` (`steps_per_channel`) | `-s N` and `-g N` | clamped 11..=51 (`DEFAULT_STEPS=21`) |
| `#calNeutralEmphasis` | `-n N` (same N) | checked |
| `#cal` white_patches (JS always sends `4`) | `-e 4` | if `None`, code also defaults to `-e 4` |
| `#calInkExplore` | `-l N` | CMYK only, 200..=400 |
| (hardcoded) | `-f 0` | always — “Full-spread patches are not useful on a calibration wedge” |
| `channels` field | — | **unused** in the builder |

Basename is sanitised (no `/` `\\` `..`). JS: `calibration.js:399–410`.

### 1.4 Env / cwd / stdin

- cwd = `resolve_safe_cwd(config.cwd)` (Stage 1 browse dir / wizard cwd).
- `ARGYLL_NOT_INTERACTIVE=1`, Windows `CREATE_NO_WINDOW`.
- **No stdin protocol.** targen is batch.

### 1.5 stdout / exit

Frontend appends every `process:stdout`/`stderr` line into `#targenLog` / `#calLog`. Success = `code === 0`. No regex parsing.

### 1.6 Artefacts

Consumes: nothing required (optional `-c` ICC/ICM/MPP).

Produces in cwd:

- `{basename}.ti1` (always) — Stage 1 complete gate (`verify_stage_artefacts`).
- Calibration: `CAL_{name}.ti1`.

### 1.7 Tests

Rust: `commands.rs:1481–1628` (RGB, CMYK, total_patches fallback, all-advanced, RGB ignores `-l`). Calibration: `calibration.rs:903–936` (RGB no `-l`, CMYK `-l 320` + `-n`, path-separator reject). JS: `calibration.test.js` basename prefix only (no argv).

---

## 2. `printtarg` — Stage 2 layout (also used by Stage 0 “Create Layout”)

### 2.1 When

Stage 2 **Create Layout** (`#btnCreateLayout`) → `run_printtarg` (`commands.rs:966–978`). Process id `printtarg_{basename}`.

Stage 0 **Create Layout & Print** (`#btnCalLayout`) does **not** spawn printtarg itself: it sets `wizardState.sessionMode = 'calibration'`, copies the `CAL_` basename into Stage 2 via `setStage1Result`, and navigates to Stage 2. The user then hits Create Layout. `getPrinttargCalibrationFields('CAL_…')` returns `{calibration_file: null}` so `-K` is **never** applied to the calibration chart itself (`calibration.js:108–116`, `AGENTS.md:7`).

### 2.2 argv — `build_printtarg_args` (`commands.rs:907–950`)

Always:

```
-v -u -i {instrument} -p {page_size} [ -r | -R {seed} ] [-d {label}] {-t|-T} {dpi} [-K|-I {cal}] {basename}
```

| UI field | Flag | Notes |
|---|---|---|
| `#instrumentSelect` | `-i {code}` | `i1` (default), `p3`, `CM`, `SS`, `20`, `22`, `41`, `51` (`PrinttargConfig` comment `commands.rs:768`) |
| `#pageSizeSelect` / custom W×H | `-p {size}` | A4, A4R, A3, A2, Letter, LetterR, Legal, 4x6, 11x17, or `{W}x{H}` mm (JS requires ≥50) |
| `#printtargLayoutOrder` | `-R 1` (default), `-R {seed}`, or `-r` | `no_randomize` **supersedes** seed (`commands.rs:917–922`). Default `random_seed: Some(1)` (`commands.rs:762–764`) for ICCery#163 determinism |
| `#targetLabelPreview` (`custom_label`) | `-d {string}` | assembled `ICCery - {run} - {printer} - {ink} - {driver paper} - {actual paper} - DD/MM/YYYY HH:MM`. Argyll fork `argyllcms#19` |
| bit-depth radios | `-t {dpi}` (8-bit) or `-T {dpi}` (16-bit) | dpi from `#tiffDpi`, default 300 |
| calibration (`getPrinttargCalibrationFields`) | `-K {cal}` apply, or `-I {cal}` embed-only | only if Apply Calibration on **and** basename is **not** `CAL_*` |
| Stage 1 basename | positional | last |

**`-u` is always on.** That is the ICCery-patched JSON manifest (`argyllcms#3`).

### 2.3 JSON event schema (`-u` manifest)

Parsed in JS from the **accumulated stdout** after exit, not via `process:json_row` (`printtarg.js:680–691`):

```js
stdout.match(/\{[\s\S]*?"event"\s*:\s*"manifest"[\s\S]*?\n\}/)
```

Expected object (from Argyll issue #3 and gallery use):

```json
{
  "event": "manifest",
  "pages": [
    { "filename": "target_01.tif", "patches": 800, "width_mm": 210, "height_mm": 297 }
  ]
}
```

`renderTiffGallery` uses `page.filename`, `page.patches`, `pages[0].width_mm/height_mm`. TIFF is previewed via `read_tiff_preview_png` (decode TIFF → PNG ≤1200px, base64).

### 2.4 stdin / env / cwd

No stdin. cwd = Stage 1 working dir. `ARGYLL_NOT_INTERACTIVE=1`, `CREATE_NO_WINDOW`.

### 2.5 Exit

`code === 0` → parse manifest, show gallery + raw-print panel, `setStage2Result`. Non-zero → log error, stay on Stage 2. Native print (`print_target_native`) is **not** an Argyll call (GDI / CUPS / NSPrintPanel).

### 2.6 Artefacts

Consumes: `{basename}.ti1` in cwd.

Produces:

- `{basename}.ti2` — Stage 2 gate.
- One or more TIFF pages named in the manifest (typically `{basename}.tif` or `{basename}_NN.tif`). 8-bit (`-t`) vs 16-bit (`-T`).
- If `-K`/`-I`: calibration is applied to / embedded in the printed patches; `.cal` is not copied.

### 2.7 Tests

`commands.rs:1631–1802`: i1/A4/8-bit, CM/Letter/16-bit, custom `200x400`, custom label, custom seed 42, raster `-r` (seed ignored), `-K`, `-I` embed-only. JS: `calibration.test.js` asserts CAL_ charts skip `-K`.

---

## 3. `chartread` — Stage 3 measurement (and Stage 0 “Measure Chart”)

### 3.1 When

Stage 3 **Start Measurement** (`#btnStartRead`) → `run_chartread` (`commands.rs:1045–1061`). Process id `chartread_{basename}`.

Stage 0 **Measure Chart** navigates to Stage 3 with the `CAL_` basename; the same `run_chartread` path is used.

`enable_i1pro2_leds` is **not** sent by JS. If the config field is `None`, the command loads `AppSettings.enable_i1pro2_leds` (`commands.rs:1051–1054`). Default `false` (stock Argyll compatibility; ICCery#204 / Argyll#37). The fork flag is `-Y l` (not the earlier proposed `-L`).

### 3.2 argv — `build_chartread_args` (`commands.rs:1023–1043`)

```
-v -u [-c {port}] [-Y l] {basename}
```

| UI / state | Flag | Condition |
|---|---|---|
| (always) | `-v -u` | `-u` = `ROW_COLORS_JSON` stream (`argyllcms#1`) |
| `#chartreadInstrumentSelect` (`port`) | `-c {port}` | non-empty. Port `"1"` is stored as `""` by the detector so default port is used (`chartread.js:488–489`). ICCery#111: do **not** pass instlist device index as `-c`. |
| Settings `enable_i1pro2_leds` | `-Y l` | true. LEDs: white=cal, blue=ready, red=error, green=capture. Unpatched binaries reject `-Y l`; frontend captures `lastStderrLine` and opens the log. |

No `-p` (spot), `-t` (transmissive), `-N` (skip cal), `-H`, `-F`, `-r` resume, `-n`.

### 3.3 JSON event schema (`-u` / `ROW_COLORS_JSON`)

Intercepted in ProcessManager, emitted as `process:json_row`. Frontend: `swatch_grid.js:95–116`. Ignored unless `data.event === "row_complete"`.

```json
{
  "event": "row_complete",
  "row_id": "A",
  "row_index": 0,
  "total_rows": 12,
  "patch_count": 21,
  "patches": [
    {
      "id": "1",
      "loc": "A1",
      "is_pad": false,
      "device": [0.0, 50.0, 100.0],
      "expected": { "XYZ": [18.42, 20.12, 15.68], "Lab": [51.98, -8.45, 12.32] },
      "measured": { "XYZ": [...], "Lab": [...], "spectral": { "bands": 36, "start_nm": 380, "end_nm": 730, "norm": 100, "values": [...] } }
    }
  ]
}
```

`is_pad` patches are skipped only when they have no `measured` **and** all-zero `device` (`swatch_grid.js:137–141`) so white-reference pads from targen `-e` still render.

On `row_index + 1 >= total_rows` the swatch listener forces `STATE.ALL_STRIPS_READ`.

Mock: `src-tauri/argyll/mocks/chartread.mock` (handheld + `--xy` / `MOCK_XY_TABLE=1`).

### 3.4 stdin protocol

All via `send_stdin` (`commands.rs:16–23` → `ProcessManager::send_stdin`). Bytes are written **as-is** and flushed. No extra newline is added by Rust — JS includes `\n`.

| Button | State(s) | Bytes | Why |
|---|---|---|---|
| `#btnCalibrate` | `CALIBRATING` | `" \n"` (space + LF) | Argyll “hit any key / space to calibrate” |
| `#btnAccept` | `WARNING`, `PROMPT_CONTINUE`, `TABLE_PLACE_SHEET`, `TABLE_ALIGN` | `"\n"` | Continue / accept strip / sheet placed / fiducial aligned. TABLE_* does **not** force `READING` |
| `#btnRetry` | `AWAITING_STRIP`, `ALL_STRIPS_READ`, `WARNING`, `ERROR` | `" \n"` | Re-read strip |
| `#btnDoneRead` | `AWAITING_STRIP`, `ALL_STRIPS_READ` | `"d\n"` | Write `.ti3` and exit (ICCery#175) |
| `#btnUndo` | strip states | `"u\n"` | Undo last strip |
| `#btnSkip` | `AWAITING_STRIP`, `ERROR` | `"s\n"` | Skip current strip |
| `#btnCancel` | any; XY extra | `"q\n"` then 500 ms then `kill_process` | Park XY head (`AGENTS.md:170`) then SIGKILL-equivalent |

`send_stdin` errors with `"Process not found or stdin not available"` if the id is not in `stdins`.

### 3.5 stdout state machine — `classifyChartreadLine` (`chartread.js:70–286`)

Pure function. Priority order:

1. “remove last sheet” → info, `isRemoveSheetNotice`, **state unchanged** (Argyll emits this just before writing `.ti3`).
2. `/sheet\s+(\d+)\s+of\s+(\d+)\s+read\s+ok/i` → `sheetOk` meta.
3. `/locate\s+patch\s+([A-Za-z0-9_]+)\s+with\s+(?:the\s+)?sight/i` → `TABLE_ALIGN`.
4. `/place\s+sheet\s+(\d+)\s+of\s+(\d+)/i` or “place sheet” / “remove previous sheet” → `TABLE_PLACE_SHEET`.
5. “hit return to continue” (and not “use it anyway”) → sticky `TABLE_*` if already there, else `PROMPT_CONTINUE`.
6. `'d' if/when done`, “all strips/patches read”, “done reading” → `ALL_STRIPS_READ`.
7. “(warning)”, “use it anyway”, “seem to have read strip pass”, “unexpected response” → `WARNING`.
8. place + (reference|white|calibrat|standard) **or** “hit any key to continue” **or** “calibration”, excluding place-sheet/locate-patch → `CALIBRATING`.
9. “hit … read … strip”, “ready to read”, “read … strip … key” → `AWAITING_STRIP`.
10. “reading strip/sheet”, “processing”, “scanning” → `READING`.
11. “error”, “too fast/slow”, “misread”, “failed to read” → `ERROR`.

XY table is auto-detected from these prompts **or** from instlist `data-xy="1"` (`/spectro\s?scan|i1io/i`).

### 3.6 Exit / snapshot

`code === 0` → `snapshot_ti3` copies `{basename}.ti3` → `{basename}_pass{N}.ti3` and **deletes** the canonical `.ti3` so Stage 4 stays locked (ICCery#109/#110, `commands.rs:1112–1131`). `setStage3Result` is **not** called until Finish.

`code !== 0` → prompt shows last stderr line; log `<details>` opened.

Single pass Finish → `promote_ti3` restores `{basename}.ti3` from `*_pass1.ti3` (average is **not** invoked). Multi-pass → `run_average`.

Cancel: `kill_process` after optional `q\n`.

### 3.7 Artefacts

Consumes: `{basename}.ti2` (and the printed chart).

Produces: `{basename}.ti3` (ephemeral) then `{basename}_passN.ti3`. Canonical `.ti3` only after Finish/average.

### 3.8 Tests

Rust argv: `commands.rs:1805–1874` (auto, empty port, `-c 1`, `-Y l`, both, leds disabled). Snapshot roundtrip: `1898–1934`. JS classifier: `chartread.test.js` (39 cases, XY sticky continuation, strip mode, warnings). Mock script as above.

---

## 4. `instlist` — instrument detection

### 4.1 When

Stage 3 **Detect** (`#btnDetectInstruments`) → `detect_instruments` (`commands.rs:615–619`).

```rust
let binary = resolve_binary(..., "instlist")?;
state.spawn(app, "instlist".to_string(), binary, vec![], None).await
```

**Empty argv. cwd = None.** Process id is the literal `"instlist"` (not namespaced). Duplicate Detect clicks while running → `"Process 'instlist' is still running"` (#116).

This is the Argyll fork USB enumeration API (`argyllcms#6`). ICCery does **not** pass `-u`; the fork’s `instlist` prints JSON on stdout by default (or ICCery treats the whole stdout as JSON).

### 4.2 stdout parsing (`chartread.js:438–503`)

Accumulate stdout. On exit:

1. `JSON.parse(trimmed)` looking for `{ devices: [ { port, name, type } ] }`.
2. Fallback regex: `/^(\d+)[\s:=]+'?([^'\n]+)'?(?:\s+on\s+'?([^'\n]+)'?)?/i` plus `KNOWN_INST_TOKENS = /i1|ColorMunki|Spyder|spectro|Display|Huey|DTP|SpectroScan|Smile|Klein/i`.

Each device → `<option value="{port if port!=='1' else ''}">`. SpectroScan / i1iO get `data-xy="1"` and ` · XY Table`.

Default option: `"Auto (First available port)"` with empty value → no `-c`.

### 4.3 stdin / artefacts

None. No files.

---

## 5. `average` — multi-pass ti3 merge

### 5.1 When

Stage 3 **Finish & Average** with ≥2 recorded passes (`chartread.js:864–947`) → `run_average` (`commands.rs:1079–1091`). Process id `average_{output}` e.g. `average_job.ti3`.

### 5.2 argv — `build_average_args` (`commands.rs:1070–1077`)

```
-v {input1} {input2} ... {output}
```

JS:

```js
{ inputs: recordedPasses.map(p => p.filename),  // "job_pass1.ti3", ...
  output: `${basename}.ti3`,
  cwd }
```

No other flags. Inputs are **relative names** (cwd is the project dir).

### 5.3 Exit

`code === 0` → `setStage3Result`, Stage 4. Else fallback `promote_ti3` of pass 1.

No stdin. `ARGYLL_NOT_INTERACTIVE=1`.

### 5.4 Artefacts

Consumes: `{basename}_passN.ti3`. Produces: `{basename}.ti3` (Stage 3 gate).

### 5.5 Tests

`commands.rs:1877–1896`.

---

## 6. `colprof` — Stage 4 profile calculation

### 6.1 When

Stage 4 **Calculate Profile** (`#btnCreateProfile`) → `run_colprof` (`commands.rs:1243–1255`). Process id `colprof_{basename}`.

**`-u` is NOT passed** even though the fork has `colprof -u` progress JSON (`argyllcms#4`). Progress is guessed from plaintext stdout.

### 6.2 argv — `build_colprof_args` (`commands.rs:1176–1241`)

Always `-v -a {algorithm} -q {quality}`.

| UI | Flag | Condition |
|---|---|---|
| `#colprofAlgorithm` | `-a l\|x\|X\|m` | `l` Lab cLUT (default), `x` XYZ cLUT, `X` Display XYZ+matrix, `m` matrix |
| `#colprofQuality` | `-q l\|m\|h\|u` | `m` Medium default. `u` = Ultra |
| `intent` (preset field only) | `-t {intent}` | **no Stage 4 control**. Presets leave it `None`. Tests use `"p"` / `"a"` |
| `#colprofFwa` / custom `.sp` | `-f {val}` | `"none"` → omit; `"D50"`/`"D65"`/`path.sp` → `-f VAL`; empty string → bare `-f` |
| `#colprofIlluminant` | `-i A\|C\|D50M2\|D65\|F5\|F8\|F10` | empty = default D50, omit flag |
| `#colprofObserver` | `-o 1964_10\|2015_2\|2015_10` | empty = 1931 2°, omit |
| `#colprofInputViewCond` | `-c pc\|pp\|pe\|pm` | `"none"` omit |
| `#colprofOutputViewCond` | `-d mt\|mb\|md\|jm\|jd\|tv` | `"none"` omit |
| `#colprofDescription` | `-D {text}` | non-empty; JS falls back to basename |
| `#colprofCopyright` | `-C {text}` | non-empty |
| basename | positional | last |

JS config: `colprof.js:95–107`. Custom FWA: `fwa: colprofCustomSpPath.value \|\| "none"`.

### 6.3 stdout “progress”

`colprof.js:119–126` (case-insensitive):

- contains `"gamut mapping"` → “Gamut mapping calculation in progress...”
- `"fitting"` or `"clut"` → “Fitting cLUT grid points...”
- `"writing"` or `"icc profile"` → “Writing ICC profile header & tags...”

Mock (`colprof.mock`) emits exactly those phrases.

### 6.4 Exit / follow-on

`code === 0` → `get_profile_path` (`.icm` if it exists and `.icc` does not; else `.icc`; Windows default extension `.icm` if neither exists, Unix `.icc` — `commands.rs:621–639`). Then if Apply Calibration: `apply_calibration` (see §8) in-place. Then `extract_gamut`.

`intent` is in `ColprofConfig` and presets but the Stage 4 form never sets it.

### 6.5 Artefacts

Consumes: `{basename}.ti3`. Produces: `{basename}.icc` (Unix/macOS) or `{basename}.icm` (Windows). Stage 4 gate.

### 6.6 Tests

`commands.rs:1937–2099` (base, FWA D50/none/custom .sp, illuminant+observer, viewing conditions, combined).

---

## 7. `applycal` — embed/unembed calibration curves

### 7.1 When

Not ProcessManager. `apply_calibration` (`calibration.rs:703–762`) uses `run_captured`.

Callers:

1. Automatically after successful colprof (`colprof.js:163–171`) if `cal.applyEnabled && cal.calPath`. `output_path: null` → in-place replace via `{input}.applycal.tmp` then `rename`.
2. Any future caller of the Tauri command.

### 7.2 argv — `build_applycal_args` (`calibration.rs:237–261`)

```
-v {-a|-u} {cal_path} {input_path} [{output_path}]
```

| Config | Flag |
|---|---|
| always | `-v` |
| `unapply: false` (JS always) | `-a` (apply) |
| `unapply: true` | `-u` (**unapply**, NOT JSON) |
| `cal_path`, `input_path` | required; empty → Err |
| `output_path` | optional positional |

Note: applycal `-u` conflicts in meaning with every other tool’s `-u` (JSON). ICCery never sends `unapply: true` from JS.

cwd = parent of input profile. `ARGYLL_NOT_INTERACTIVE=1`, `CREATE_NO_WINDOW`. Exit ≠ 0 → delete tmp, return last stderr line.

### 7.3 Artefacts

Consumes: `.cal` + `.icc`/`.icm`. Produces: same path (in-place) or `output_path`. Temp extension `.applycal.tmp`.

### 7.4 Tests

`calibration.rs:987–1015`.

---

## 8. `printcal` — compute `.cal` from measured calibration chart

### 8.1 When

Stage 0 **Compute Curves** (`#btnCalCompute`) → `compute_calibration_curves` (`calibration.rs:615–701`). **Captured**, not streamed. Requires `{ti3_basename}.ti3` already on disk.

Collision: if `{basename}.cal` exists and `force_overwrite` is false → error string containing `"already exists"`; JS dialog Overwrite / Rename / Cancel (`calibration.js:418–437, 485–492`). Rename uses `{basename}_{ISO-stamp}.cal`.

### 8.2 argv — `build_printcal_args` (`calibration.rs:191–235`)

Always `-v -e`. Then:

| Config / UI | Flag | Condition |
|---|---|---|
| `no_ink_limit` (JS always false) | `-I` | true |
| `verify` (JS always false) | `-z` | true |
| `previous_cal` (current `calState.calPath`) | `-a {path}` | non-empty |
| `#calTacOverride` (`total_ink_limit`) | `-m x.x` | Some and > 0 |
| `#calInkLimitControls` (`channel_limits`) | `-x{C} {percent}` | first char of channel, e.g. `-xC 95.0` |
| `output_cal` | `-o {file.cal}` | default `{basename}.cal` |
| `ti3_basename` | positional | last |

`-e` here is printcal’s even/estimate switch (always on), **not** targen white patches.

### 8.3 stdout parsing — `parse_printcal_stdout` (`calibration.rs:274–307`)

Line-oriented, not JSON:

- line matching `ideal power` / `device power` / `power value` → first number → `recommended_power` (feeds Stage 1 targen `-p` hint in the dashboard).
- line containing `total` and (`ink`|`tac`|`limit`) → TAC.
- line starting Cyan/Magenta/Yellow/Black/Red/Green/Blue or `C:`/`C ` etc. → per-channel limit.

Then `parse_cal_file` on the written `.cal` (CGATS: `COLOR_REP`, `CREATED`, `DESCRIPTOR`, `MAX_TAC`/`TOTAL_INK_LIMIT`/`INK_LIMIT`, `INK_LIMIT_*`, `BEGIN_DATA_FORMAT` / `BEGIN_DATA` curves). If stdout limits empty, infer from curve max×100.

### 8.4 Artefacts

Consumes: `CAL_*.ti3`. Produces: `{basename}.cal` (or override). Also `iccery-calibration.json` project state and optional library copy under `app_data_dir/calibrations/`.

### 8.5 Tests

`calibration.rs:939–984, 1018–1072`.

---

## 9. `profcheck` — Stage 5 verification

### 9.1 When

Stage 5 **Verify** (`#btnVerify`) → `run_profcheck` (`commands.rs:1275–1302`). Process id `profcheck_{ti3_path}` (full path, not basename — `colprof.js` uses basename; these must not be confused; #56 was exactly that class of bug for colprof).

ICC path auto-flips `.icc` ↔ `.icm` if the requested file is missing (`commands.rs:1283–1295`).

### 9.2 argv — `build_profcheck_args` (`commands.rs:1264–1273`)

Hard-coded:

```
-v -k -s -u {ti3_path} {icc_path}
```

| Flag | Meaning in this fork |
|---|---|
| `-v` | verbose |
| `-k` | CIEDE2000 |
| `-s` | (Argyll: “standard” / summary — kept for the text line parser) |
| `-u` | JSON report (`argyllcms#5`) |

No UI toggles. Paths may be absolute (JS builds `cwd + sep + basename.ti3` / `get_profile_path`).

### 9.3 JSON + text parsing — `parseProfcheckReport` (`profcheck.js:27–139`)

Order:

1. `No of test patches = (\d+)`.
2. All `{...}` objects in stdout; keep those with `event==="report"` or any of `avg_de`, `avg_de2000`, `peak_de`, `peak_de2000`, `rms`, `rms_de`. Prefer object with `*de2000` keys.
3. Else text: `Profile check complete, errors…: max. = X, avg. = Y, RMS = Z`.
4. Else regex families for avg/max/rms. Missing metrics → `warnings[]` and cards show 0.00 (`AGENTS.md:23–24`).

JSON schema (mock + tests):

```json
{"event": "report", "peak_de2000": 2.41, "avg_de2000": 0.85, "rms": 1.02}
```

Also accepted: `peak_de` / `avg_de` / `max_de` / `rms_de`.

Quality bands (ICCery#95, **not** Argyll): `<1` Excellent, `<2` Good, `<3.5` Acceptable, else Poor. Saved via `save_verification_record`.

### 9.4 stdin / artefacts

No stdin. Consumes `.ti3` + `.icc`/`.icm`. Produces no new Argyll files (verification_history.json is ICCery). Attempts to load `{basename}.gam` into the 3D viewer (created earlier by iccgamut).

### 9.5 Tests

Rust argv: `commands.rs:2102–2110`. JS: `profcheck.test.js` (real `-u` JSON, de2000 preference, text summary, legacy regex, breach alert). Mock: `profcheck.mock`.

---

## 10. `iccgamut` — 3D gamut mesh

### 10.1 When

Automatically after colprof success (`colprof.js:197–214`) → `extract_gamut` (`commands.rs:693–731`). Process id `iccgamut_{stem}`.

### 10.2 argv — `build_iccgamut_args` (`commands.rs:684–691`)

```
-v -d 10 {resolved_icc_path}
```

`-d 10` is **surface density**, not a directory (ICCery#112). Path is the real `.icc`/`.icm` (auto-flip if missing). cwd = parent of the profile.

**No `ARGYLL_3D_DISP`.** The GUI never launches Argyll’s 3D viewer; it reads the `.gam` file in-process.

### 10.3 Exit

`code === 0` → `loadGamutMesh("{cwd}/{basename}.gam")`. Failures are `console.warn` only.

### 10.4 Artefacts

Consumes ICC/ICM. Produces `{stem}.gam` next to the profile (Argyll default). Bundled reference: `src/assets/sRGB.gam` and `src-tauri/argyll/reference_gamuts/sRGB.gam`.

### 10.5 Tests

`commands.rs:1475–1478`.

---

## 11. Binaries that are **not** invoked

| Binary | Status |
|---|---|
| `dispwin` | Never spawned. ICCery#90 “Emissive display calibration (dispwin & dispread)” = Won't Fix |
| `dispread` | Same |
| `dispcal`, `collink`, `cctiff`, `spec2cie`, `illumread`, `synthacc` | Not referenced |
| Generic `spawn_process` | **Registered** (`lib.rs:55`, `commands.rs:6–14`) but **no JS caller**. Always `cwd=None`. Exists as an escape hatch |

---

## 12. ProcessManager internals

File: `src-tauri/src/process_manager.rs`.

### 12.1 Maps

```rust
stdins:  Arc<Mutex<HashMap<String, Arc<Mutex<ChildStdin>>>>>
killers: Arc<Mutex<HashMap<String, oneshot::Sender<()>>>>
```

The `Child` itself lives only in the wait task (not in a map) so `wait()` cannot hold a mutex that `send_stdin` needs.

### 12.2 Spawn ids (complete list)

| Pattern | Binary |
|---|---|
| `targen_{basename}` | targen (profile + CAL_) |
| `printtarg_{basename}` | printtarg |
| `chartread_{basename}` | chartread |
| `average_{output}` | average (`output` includes `.ti3`) |
| `colprof_{basename}` | colprof |
| `profcheck_{ti3_path}` | profcheck (full path) |
| `iccgamut_{stem}` | iccgamut |
| `instlist` | instlist (literal) |
| `spotread` | spotread (literal, issue #148) |
| caller-supplied | unused `spawn_process` |

### 12.3 Duplicate rejection (ICCery#116, `07d28eb`)

Before spawn, if `stdins.contains_key(&id)` → `Err("Process '{id}' is still running")`. Prevents a second `chartread_{basename}` from replacing map entries while the old wait task still `remove()`s that id on exit (which would orphan the live stdin).

Frontend also sets `measurementInProgress` to disable Start / Measure Another / Finish.

### 12.4 Wait / reap

Wait task (`process_manager.rs:166–194`):

```rust
let exit_code = tokio::select! {
    res = child.wait() => status.code().unwrap_or(0),
    _ = kill_rx => { child.start_kill(); child.wait().await; code.unwrap_or(1) }
};
stdins.remove(id); killers.remove(id);
emit_exit(id, exit_code);
```

Natural exit also reaps, so `send_stdin` after the child dies returns “Process not found”.

v0.1.16 (`90012e4`, ICCery#63) originally awaited `child.wait()` **inside** `Mutex<Child>` — that is the bug #84 fixed.

### 12.5 stdin write

```rust
stdin.write_all(input.as_bytes()).await?;
stdin.flush().await?;
```

No encoding transform. JS is responsible for `\n`.

`kill` first `stdins.remove(id)` (drops/closes the pipe, which is what Argyll sees as EOF) then fires the oneshot so the wait task `start_kill()`s.

### 12.6 `kill_all`

`process_manager.rs:237–267`:

1. `stdins.clear()` (close every pipe).
2. Drain `killers` and `send(())` each.
3. Sleep 50 ms so wait tasks can `start_kill()`.
4. Return count.

Invoked:

- Tauri command `kill_all_processes` (`commands.rs:33–38`) — **no JS caller**.
- `RunEvent::Exit` / `ExitRequested` (`lib.rs:124–129`).
- `WindowEvent::CloseRequested` (`lib.rs:136–141`).

This is ICCery#147/#149: closing the window during chartread used to leave the instrument locked.

### 12.7 Windows pipe deadlock history

Two layers, two repos:

**ICCery#84 (host, v0.2.1, PR #83, `d6118a1`)** — Tokio `Child::wait()` deadlock:

- PR #77 / #63 replaced `try_wait` polling with `child.wait().await` while holding `Mutex<Child>`.
- Effect 1: `send_stdin` / `kill` blocked until the child exited (Calibrate/Retry/Skip/Cancel dead).
- Effect 2: Tokio’s `wait()` **drops stdin** to avoid parent/child pipe deadlock, so the pipe closed immediately after spawn — chartread never received keystrokes.
- Fix: `take()` all three stdio handles; store only `ChildStdin` in the map; `select!` wait vs oneshot kill.

**gronod/argyllcms#24 (child, Windows anonymous pipes)** — `ReadFile` deadlock inside Argyll:

- `SetNamedPipeHandleState(PIPE_NOWAIT)` **fails on anonymous pipes** (`CreatePipe` / Rust `Stdio::piped()`).
- `con_char(wait=0)` then `ReadFile()`s a blocking pipe → `poll_con_char` never returns → instrument switch (USB EP `0x84`) is never polled → lamp never lights after calibration.
- Fix in the fork: `PeekNamedPipe` before `ReadFile` (`spectro/conv.c`).
- ICCery-side companion: `ARGYLL_NOT_INTERACTIVE=1` (#134) so Argyll takes the pipe path at all. **Stock Graeme Gill binaries will still hang on Windows interactive chartread.**

ROADMAP.md:59: “Resolved P0 process manager deadlock and premature stdin pipe closure affecting interactive `chartread` instrument workflows.” / “Decoupled `ChildStdin` mutex management from child process wait/reap tasks.”

### 12.8 ProcessManager tests

`process_manager.rs:270–325`: occupancy helper (does not actually spawn), `kill_all` drains 2 fake killers, path sanitise. No integration test that execs a real binary.

---

## 13. Every Tauri command related to processes

From `lib.rs:54–119` plus the command bodies:

### Direct process control

| Command | File:line | Role |
|---|---|---|
| `spawn_process(id, binary, args)` | `commands.rs:6–14` | Generic spawn, **cwd=None**, unused by UI |
| `send_stdin(id, input)` | `commands.rs:16–23` | Write bytes to ChildStdin |
| `kill_process(id)` | `commands.rs:25–31` | Close stdin + start_kill one id |
| `kill_all_processes()` | `commands.rs:33–38` | Kill all; returns count |
| `resolve_binary(binary_name)` | `commands.rs:48–106` | Path lookup |

### Argyll runners (ProcessManager)

| Command | Binary | id |
|---|---|---|
| `run_targen` | targen | `targen_{basename}` |
| `run_printtarg` | printtarg | `printtarg_{basename}` |
| `run_chartread` | chartread | `chartread_{basename}` |
| `run_average` | average | `average_{output}` |
| `run_colprof` | colprof | `colprof_{basename}` |
| `run_profcheck` | profcheck | `profcheck_{ti3_path}` |
| `extract_gamut` | iccgamut | `iccgamut_{stem}` |
| `detect_instruments` | instlist | `instlist` |
| `run_spotread` | spotread (`-v -e [-c port] [-Y l]`, no `-u`) | `spotread` |
| `generate_calibration_target` | targen | `targen_{CAL_basename}` |

### Argyll runners (captured, no events)

| Command | Binary |
|---|---|
| `compute_calibration_curves` | printcal |
| `apply_calibration` | applycal |

### Artefact helpers used around those processes

`parse_ti2_header`, `snapshot_ti3`, `promote_ti3`, `verify_stage_artefacts`, `get_profile_path`, `read_tiff_preview_png`, `read_file_base64`, `select_*` dialogs, `parse_cal_file_cmd`, `list_saved_calibrations`, `save_calibration_to_library`, `select_cal_file`, `load/save_project_calibration`.

---

## 14. File artefacts by OS / stage

| Stage | Consumes | Produces | Gate |
|---|---|---|---|
| 0 cal chart | — | `CAL_*.ti1` | — |
| 0 print | `CAL_*.ti1` | `CAL_*.ti2`, `CAL_*.tif` | — |
| 0 measure | `CAL_*.ti2` | `CAL_*_passN.ti3` → `CAL_*.ti3` | — |
| 0 compute | `CAL_*.ti3` | `CAL_*.cal`, `iccery-calibration.json` | — |
| 1 | optional `-c` ICC | `{base}.ti1` | `stage1_complete` |
| 2 | `.ti1` | `.ti2`, `.tif`/`.tiff` pages | `stage2_complete` |
| 3 | `.ti2` | `_passN.ti3` then `.ti3` | `stage3_complete` = `.ti3` exists |
| 4 | `.ti3` | `.icc` (macOS/Linux) or `.icm` (Windows); optional in-place applycal | `stage4_complete` |
| 4b | ICC | `{stem}.gam` | not a gate |
| 5 | `.ti3` + ICC | none (history JSON is ICCery) | — |

`verify_stage_artefacts` (`commands.rs:650–676`) checks existence only (no content). `.ti2` missing while `.ti3` present still reports `stage2_complete: false`.

`parse_ti2_header` (`commands.rs:366–424`) reads `TARGET_INSTRUMENT`, `NUMBER_OF_FIELDS` (stored as `colorant_count` — this is CGATS field count, not ink count), `NUMBER_OF_SETS` → `patch_count`, `NUMBER_OF_PAGES`/`PAGES`.

---

## 15. Flag cheat-sheet (`-u`, `-Y`, `-K`, `-f`, `-c`, `-d`)

| Flag | Binary | Meaning in ICCery |
|---|---|---|
| `-u` | printtarg | JSON page manifest (always) |
| `-u` | chartread | `ROW_COLORS_JSON` per row (always) |
| `-u` | profcheck | JSON ΔE report (always) |
| `-u` | applycal | **unapply** curves (never sent from JS) |
| `-u` | targen / colprof | **not used** (fork supports JSON progress) |
| `-Y l` | chartread | i1Pro2 LED feedback (settings, default off) |
| `-K` | printtarg | apply `.cal` to printed patches (profiling only) |
| `-I` | printtarg | embed `.cal` without applying (builder supports; UI always `calibration_embed_only: false`) |
| `-I` | printcal | no ink limit (UI never sets) |
| `-f N` | targen | full-spread patch count; cal charts force `-f 0` |
| `-f VAL` | colprof | FWA/OBA (`D50`/`D65`/`.sp`/bare) |
| `-c PATH` | targen | preconditioning profile |
| `-c PORT` | chartread | comm port |
| `-c COND` | colprof | input viewing condition |
| `-d 2\|4` | targen | RGB / CMYK |
| `-d 10` | iccgamut | surface density |
| `-d STR` | printtarg | custom chart label |
| `-d COND` | colprof | output viewing condition |

---

## 16. Tests covering arg builders (index)

| Builder | Tests |
|---|---|
| `build_targen_args` | `commands.rs` `test_build_targen_args_{rgb,cmyk,total_patches_fallback,all_advanced_flags,rgb_ignores_ink_limit}` |
| `build_calibration_targen_args` | `calibration.rs` `test_build_calibration_targen_{rgb,cmyk_ink_limit,rejects_path}` |
| `build_printtarg_args` | `commands.rs` i1/A4/8bit, CM/Letter/16bit, custom page, label, seed, raster, `-K`, `-I` |
| `build_chartread_args` | auto, empty port, with port, leds on/off, port+leds |
| `build_average_args` | two-input, pass-file names |
| `build_colprof_args` | base, FWA D50/none/sp, illuminant+observer, viewing, combined |
| `build_profcheck_args` | `-v -k -s -u` + paths |
| `build_iccgamut_args` | `-v -d 10 path` |
| `build_printcal_args` | defaults, overrides+prev |
| `build_applycal_args` | apply+out, unapply+empty-err |
| `get_binary_candidates` | exe on Windows |
| JS parsers | `chartread.test.js`, `profcheck.test.js`, `calibration.test.js` |
| ProcessManager | duplicate-id occupancy, `kill_all`, path sanitise |

`npm test` runs the JS suites. Rust: `cd src-tauri && CARGO_INCREMENTAL=0 cargo test`.
