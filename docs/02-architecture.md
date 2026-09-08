# 02 — Architecture

## Host / child split

```
┌─ ICCery host (any stack) ─────────────────────────────────────┐
│  Wizard UI  ─►  WizardState (basename, cwd, printerName)      │
│       │                                                       │
│       ├─ ProcessManager (spawn / stdin / kill / kill_all)     │
│       ├─ Print subsystem (Win GDI / macOS NSPrint+lp / Linux) │
│       ├─ Settings + presets (settings.json)                   │
│       ├─ Quality store (verification_history.json)            │
│       ├─ Calibration library (.cal files)                     │
│       └─ Profile installer (OS colour stores)                 │
└──────────────┬────────────────────────────────────────────────┘
               │ stdin / stdout / stderr pipes
               │ env ARGYLL_NOT_INTERACTIVE=1
               ▼
┌─ ArgyllCMS sidecars (AGPLv3) ─────────────────────────────────┐
│  instlist  targen  printtarg  chartread  average              │
│  printcal  applycal  colprof  profcheck  iccgamut             │
└───────────────────────────────────────────────────────────────┘
```

Original implementation: Tauri v2 webview (`withGlobalTauri: true`) so the vanilla JS frontend calls `window.__TAURI__.core.invoke` and `window.__TAURI__.event.listen`. A rewrite may replace this with any IPC (HTTP local server, native bindings, gRPC, etc.) but **must keep the same command semantics**.

## Frontend modules (legacy)

| Module | Role |
|--------|------|
| `app.js` | Boot, safeInit per stage, `show_main_window` double-rAF + 1500 ms fallback |
| `state.js` | `wizardState`, artefact gating, stage DOM, gamut pause/ensure |
| `targen.js` | Stage 1 |
| `printtarg.js` | Stage 2 + native print UI |
| `chartread.js` | Stage 3 state machine |
| `swatch_grid.js` | Live ΔE₀₀ patches from `process:json_row` |
| `colprof.js` | Stage 4 |
| `profcheck.js` | Stage 5 metrics, drift SVG, CSV |
| `gamut_viewer.js` | Three.js CIELAB viewer (lazy) |
| `calibration.js` | Stage 0 |
| `profile_install.js` | Stage 5 install |
| `settings.js` / `presets.js` | Persistence |
| `cgats_interop.js` | Import/export datasets |
| `delta_e.js` | CIEDE2000 |
| `color_convert.js` | Lab/device → CSS |
| `logger.js` | Forwards console to `log_frontend_message` |

**Do not** create WebGL during boot. `ensureGamutViewer()` runs only when Stage 5 becomes visible (#225).

## Backend modules (legacy Rust)

| Module | Role |
|--------|------|
| `lib.rs` | Tauri builder, plugins, `generate_handler!`, RunEvent kill-all |
| `commands.rs` | Binary resolve, arg builders, dialogs, stage artefact verify |
| `process_manager.rs` | tokio spawn, JSON-row split, CREATE_NO_WINDOW |
| `events.rs` | `process:stdout|stderr|exit|error|json_row` |
| `print/*` | OS printing |
| `calibration.rs` | printcal/applycal + `.cal` parser |
| `profile_install.rs` | OS colour-store copy |
| `quality_store.rs` | verification history, atomic write |
| `settings.rs` | settings + presets |
| `cgats.rs` | CGATS/ti3 parser + canonical serializer |
| `macos_webview.rs` | Dark WKWebView backing |
| `window_lifecycle.rs` | Close vs Web Content death |

## Sidecar layout

`scripts/fetch-argyll.mjs` downloads Gronod/argyllcms GitHub (or Gitea) releases into:

```
src-tauri/argyll/
  linux-x86_64/instlist
  windows-x86_64/instlist.exe
  macos-x86_64/instlist
  macos-aarch64/instlist
  macos-universal/instlist
  mocks/          # chartread.mock, colprof.mock, profcheck.mock
  reference_gamuts/sRGB.gam
```

`resolve_binary(name)`:

1. If `settings.argyll_binary_dir` is set and the file exists, use it.
2. Else resource `argyll/<platform>/<name>[.exe]`.
3. On macOS, prefer `macos-universal` if that folder contains `instlist`.
4. Windows always tries `name.exe` first (#85).

Env override: `ARGYLL_RELEASE_TAG=vX.Y.Z npm run fetch-argyll`.

## Working directory

Every Argyll run is given an explicit cwd. Empty cwd falls back to Documents → Home → app data (`resolve_safe_cwd`, #59). Basename must not contain `/`, `\`, or `..`.

Default artefacts live next to each other:

```
<cwd>/<basename>.ti1
<cwd>/<basename>.ti2
<cwd>/<basename>.tif  (and .1.tif, .2.tif … for multi-page)
<cwd>/<basename>.ti3
<cwd>/<basename>_passN.ti3     # averaging snapshots (#109)
<cwd>/<basename>.icc | .icm
<cwd>/<basename>.gam
<cwd>/CAL_<basename>.ti1|.ti2|.ti3|.cal   # calibration, never collides
```

## Persistence locations

| File | Where | Notes |
|------|-------|-------|
| `settings.json` | app data dir | thresholds, argyll dir, presets, LED flag |
| `verification_history.json` | app data dir | max 1000 records, atomic `.tmp` + rename (#213) |
| `iccery.log` | app log dir | 5 MiB rotate, keep 5 historical segments |
| Calibration library | app data / user-chosen | `.cal` files |

macOS log path: `~/Library/Logs/com.gronod.iccery/iccery.log`.

## Event bus (must be replicated)

| Event | Payload | When |
|-------|---------|------|
| `process:stdout` | `{ id, line }` | Non-JSON stdout line |
| `process:stderr` | `{ id, line }` | stderr line |
| `process:exit` | `{ id, code }` | child exited (0 = success; killed may be 1) |
| `process:error` | `{ id, error }` | spawn failure |
| `process:json_row` | `{ id, json }` | stdout line starting `ROW_COLORS_JSON: ` — prefix **stripped** |

Process ids are deterministic strings, e.g. `targen_${basename}`, `chartread_${basename}`, `instlist`, `iccgamut_${stem}`. Duplicate spawn of a still-running id is rejected (#116).

Frontend listeners **must** filter on `payload.id`. A historical bug (#56) was process-id mismatch so UI never saw exit.

## Logging

- Host: `tauri-plugin-log` to log dir + stdout + webview. wry / tauri_runtime_wry at Info so Monterey "web content process terminated" is captured (#225).
- Subprocess stdout → `log::info!(target: "subprocess")`; stderr → warn.
- Paths in spawn logs are home-sanitized to `~` (`sanitize_arg_for_logging`).
- JS `logger.js` invokes `log_frontend_message`.
- Settings `log_level` is applied at startup **and** when saved (#158).

## Window / WebView contract (macOS especially)

See #225 and `macos_webview.rs`:

- Window `visible: false`, `backgroundColor: #1A1A22`.
- After CSS first paint: invoke `show_main_window` (double `requestAnimationFrame` + 1500 ms fallback).
- `paint_dark_webview`: `setBackgroundColor`, KVC `drawsBackground = NO`, `setUnderPageBackgroundColor:` on macOS 12+.
- Do **not** set `transparent: true` (hit-testing / titlebar).
- On `Exit` / `CloseRequested`: `kill_all` Argyll children (#147, #149) **before** teardown so `chartread` can park an XY head if the UI already sent `q\n`.
