# 01 — Product overview

ICCery is a native desktop GUI that walks a user through creating a printer ICC/ICM profile with ArgyllCMS. It is **not** a colour engine. All measurement, chart generation, and profile mathematics live in AGPLv3 Argyll binaries spawned as children. ICCery owns UI, artefact gating, unmanaged printing, and visualisation.

Version analysed: **0.8.5** (`com.gronod.iccery`).

## Platforms

| OS | Packaged as | Floor | Notes |
|----|-------------|-------|-------|
| Windows x86_64 | NSIS `.exe` + WiX `.msi` | WebView2 | `.icm` profiles; GDI ICM-off printing; optional Argyll USB driver install |
| macOS Intel + Apple Silicon | `.dmg` / `.app` | **12.0 Monterey** (`LSMinimumSystemVersion`) | Universal binary preferred; WKWebView; NSPrintPanel ColorSync suppression |
| Linux x86_64 | `.AppImage` / `.deb` | Ubuntu 22.04 glibc | CUPS `lp -o raw`; `libcups` |

macOS 11 and 10.15 are **not** supported after #225. Monterey Intel is best-effort: Stages 1–4 work if WebGL dies.

## User-facing workflow

```
[optional Stage 0] printcal / applycal linearization
        │
        ▼
Stage 1  targen          →  basename.ti1
Stage 2  printtarg + OS print →  basename.ti2 + page TIFFs
Stage 3  chartread (+ average) →  basename.ti3
Stage 4  colprof (+ applycal)  →  basename.icc|.icm
Stage 5  profcheck + iccgamut + install →  verification, 3D gamut, OS profile store
```

Navigation is a left stepper. Forward motion is **artefact-gated on disk**, not on in-memory flags (#60, #151). Backward motion is always allowed.

## Colour spaces

- **RGB (Printer Driver)** — `targen -d 2`. Host/driver colour management is expected to be **turned off** at print time; ICCery prints unmanaged.
- **CMYK (RIP)** — `targen -d 4`. Typical for RIP-driven presses. Calibration (Stage 0) is recommended; Stage 1 shows a reminder when no `.cal` is applied.

## Instruments (Stage 2 layout + Stage 3 read)

`printtarg -i` codes used in the UI:

| UI | `-i` | Hardware |
|----|------|----------|
| i1 Pro / i1 Pro 2 | `i1` | Handheld strip (optional `-Y l` LEDs on i1Pro 2 Rev E) |
| ColorMunki | `CM` | Handheld |
| SpyderPrint | `p3` | Handheld (PrintFix Pro) |
| SpectroScan | `SS` | XY table |
| DTP20 / 22 / 41 / 51 | `20` `22` `41` `51` | Legacy X-Rite |

XY tables (SpectroScan, i1iO) are auto-detected from `instlist` names matching `/spectro\s?scan|i1io/i` and from `chartread` prompts (#93).

## AGPL boundary (non-negotiable)

ArgyllCMS is AGPLv3. ICCery is proprietary. The original design **never** `dlopen`s or statically links Argyll. Communication is:

- spawn with piped stdin/stdout/stderr
- `ARGYLL_NOT_INTERACTIVE=1` in the child environment
- structured JSON on stdout for tools compiled with the Gronod fork `-u` switch
- keystrokes on stdin for interactive `chartread`

A rewrite that in-process-links Argyll **contaminates the GUI with AGPL**. Keep the process boundary.

## Identity & assets

- Wordmark: waffle cone + CMY scoops (C `#00BCEB`, M `#EC008C`, Y `#FFED00`) + K cherry, text `ICC` white + `ery` cyan→blue. File: `src/assets/ICCery-logo.svg`.
- App icon: `src/assets/app-icon.svg` and raster set under `src-tauri/icons/`.
- Accent in UI CSS is VS Code blue `#007acc` on dark `#1e1e1e` / `#252526`.
- Window: 1280×800, min 1100×700, starts **hidden** until first paint (#225).

## What the rewrite must preserve

Everything in this spec is behavioural, not Tauri-specific: CLI flags, JSON prefixes, stdin bytes, PPD keys, ColorSync SPI, artefact names, ΔE bands, collision dialogs, and the bugs listed in [24-issues-invariants.md](24-issues-invariants.md).
