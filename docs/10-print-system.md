# 10 — Print system (shared types & UI)

> Line numbers refer to ICCery v0.8.5 (`/tmp/ICCery` at analysis time) and the Gronod ArgyllCMS 3.5.0 fork.

## Architecture map

```
Stage 2 UI (src/js/printtarg.js + src/index.html #rawPrintPanel)
        │  invoke("get_printers")
        │  invoke("get_printer_capabilities", { printerName })
        │  invoke("show_printer_properties", { printerName })
        │  invoke("print_target_native", { printerName, tiffPath, options })
        ▼
src-tauri/src/commands.rs  (cfg-gated dispatch)
        │
        ├── windows  → print/windows.rs   GDI + DEVMODE + SetICMMode(ICM_OFF)
        ├── macos    → print/macos.rs     NSPrintPanel + private SPI + lp
        └── unix     → print/unix.rs      lpstat/lpoptions + lp -o raw
```

Shared types live in `src-tauri/src/print/mod.rs`. `PrinterDevModeStore` is a Tauri managed state (`lib.rs:53`). macOS re-exports Unix enumeration (`macos.rs:10`).

ICCery-CPU (`TargetPrint.app`) is a **separate** AppKit process that ICCery is specified to spawn fire-and-forget with `--job <json>`. It is **not yet wired** into the Tauri commands; the current ICCery print path is in-process / `lp`.

---

## Shared print types (`src-tauri/src/print/mod.rs`)

All structs derive `Debug, Clone, Serialize, Deserialize`. Frontend JS uses **snake_case** field names when building the `PrintOptions` payload (see `printtarg.js:268-275`), matching serde's default.

### `Printer` (mod.rs:6–13)

| Field | Type | Meaning |
|-------|------|---------|
| `name` | `String` | OS queue / destination name. Windows: `PRINTER_INFO_4W.pPrinterName`. Unix/macOS: CUPS destination from `lpstat -e` / `-p`. This is the value sent back as `printerName` to all subsequent commands. |
| `status` | `String` | Windows always `"Ready"`. Unix: `"Idle"` / `"Printing"` / `"Stopped"` / `"Unknown"` from `lpstat -p`. |
| `is_default` | `bool` | Windows: always `false` (default printer is **not** queried). Unix: true when name matches `lpstat -d` (`system default destination:`). |
| `display_name` | `Option<String>` | Human-readable CUPS `printer-info` from `lpoptions -p <name>`. Windows always `None`. Used on macOS as `NSPrinter::printerWithName` fallback when `PMPrinterCreateFromPrinterID` fails (#188). Serde `#[serde(default)]`. |

AGENTS.md warns: adding fields requires updating **every** platform constructor (`windows.rs`, `unix.rs`) or the other OS builds break.

### `PrinterTray` (mod.rs:16–19)

| Field | Type | Meaning |
|-------|------|---------|
| `id` | `u16` | Windows: Win32 bin ID from `DC_BINS`. Unix: 1-based index of the `InputSlot` / `MediaSource` value (not a PPD code). |
| `name` | `String` | Windows: 24-WCHAR `DC_BINNAMES` string, or `"Tray {id}"` if empty. Unix: PPD choice with leading `*` stripped (e.g. `Auto`, `Upper`). |

### `PrinterPaperSize` (mod.rs:22–25)

| Field | Type | Meaning |
|-------|------|---------|
| `id` | `u16` | Windows: `DC_PAPERS` DMPAPER_* id. Unix: 1-based index of `PageSize` / `MediaSize` choice. |
| `name` | `String` | Windows: 64-WCHAR `DC_PAPERNAMES`, or `"Paper Size {id}"`. Unix: PPD token (`A4`, `Letter`, …). |

**Gap:** the frontend never populates a paper-size `<select>` from `caps.paper_sizes`. Stage 2's `#pageSizeSelect` is the **printtarg layout** page size (mm), not the printer's PPD `PageSize`. `PrintOptions.paper_size` is set from that same `#pageSizeSelect` (`printtarg.js:271`) and forwarded to `lp -o PageSize=` on Unix/macOS. Windows `apply_print_options_to_devmode` **ignores** `paper_size`.

### `PrinterMediaType` (mod.rs:28–31)

| Field | Type | Meaning |
|-------|------|---------|
| `id` | `String` | Windows: `DC_MEDIATYPES` DWORD as decimal string (parsed back to `u32` for `dmMediaType`). Unix: PPD choice token (`92`, `13`, `Plain`, …). When a PPD file is readable, `id` is the machine token and `name` is the human label after `/`. |
| `name` | `String` | Display label. Unix `lpoptions -l` path uses the same token for both. Unix PPD path (`parse_ppd_media_types`) splits `*CNIJMediaType 42/Photo Paper Plus Semi-gloss:` into id=`42`, name=`Photo Paper Plus Semi-gloss`. |

### `PrinterCapabilities` (mod.rs:34–40)

| Field | Type | Meaning |
|-------|------|---------|
| `trays` | `Vec<PrinterTray>` | Paper sources. |
| `paper_sizes` | `Vec<PrinterPaperSize>` | Queried but unused by the Stage 2 UI. |
| `media_types` | `Vec<PrinterMediaType>` | `#[serde(default)]`. Frontend fills `#printerMediaTypeSelect`. |
| `supports_orientation` | `bool` | Always `true` on both Windows and Unix. |

### `PrintOptions` (mod.rs:42–55) — `Default` + `PartialEq + Eq` — historical v1

> The `lp`/`-o` columns below describe the v0.8.5 spool contract. v2.0
> replaced the macOS `lp` path with a headless `NSPrintOperation` (#201).

| Field | Type | Windows | Linux | macOS |
|-------|------|---------|-------|-------|
| `paper_source` | `Option<u16>` | `dmDefaultSource` (tray id) | **ignored** (unix `build_lp_args` never emits `InputSlot`) | **ignored** unless present in captured `cups_options` |
| `orientation` | `Option<String>` | `"landscape"` → `DMORIENT_LANDSCAPE` (2), else portrait (1) | `-o orientation-requested=4` (landscape) or `=3` (portrait) | same, skipped if `cups_options` already has the key |
| `paper_size` | `Option<String>` | **ignored** | `-o PageSize=<value>` | same, skipped if `pagesize` already added |
| `media_type` | `Option<String>` | parsed as `u32` → `dmMediaType` | `-o MediaType=<value>` (generic key only) | uses `detect_media_type_key` (`CNIJMediaType` / `EPIJ_Medi` / `StpMediaType` / `MediaType`); skipped if any of those keys already in `cups_options` |
| `ppd_uncorrected_passthrough` | `Option<bool>` | **ignored** | if true: `-o ColorModel=Gray -o cm-calibration` instead of `-o raw` | **ignored as a gate**; macOS always ColorSync-bypasses and always injects driver color-bypass. Native panel sets this to `Some(true)` on OK. |
| `cups_options` | `Option<String>` | **ignored** | **ignored** | space-separated `key=value` captured from `PMPrintSettingsToOptions`, filtered, then expanded to `-o key=value`. `#[serde(default)]`. |

### `PrintPropertiesResult` (mod.rs:57–61)

Returned by `show_printer_properties` on macOS only.

| Field | Type | Meaning |
|-------|------|---------|
| `selected_printer` | `Option<String>` | CUPS Printer ID from `PMPrinterGetID` after the panel, or the original `printer_name` if the session printer cannot be read but `PMPrinterCreateFromPrinterID` had succeeded. `None` if the panel was opened via the `NSPrinter::printerWithName(display_name)` fallback. |
| `options` | `PrintOptions` | Snapshot: `media_type` extracted from captured options, `cups_options` filtered string, `ppd_uncorrected_passthrough: Some(true)`, everything else `Default`. |

Windows `show_printer_properties` returns `Ok(None)` from the Tauri command after storing DEVMODE (the inner fn returns `Result<(), String>`). Linux returns `Ok(None)` with no dialog. Frontend treats `null` as **user cancelled** (`printtarg.js:390-393`) — so on Windows a successful Preferences OK **also** shows "Printer properties dialog cancelled." That is a known UX mismatch: Windows success and cancel both surface as `null`.

### `PrinterDevModeStore` (mod.rs:63–87)

```rust
pub struct PrinterDevModeStore {
    pub devmodes: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}
```

- Keyed by printer name.
- Stores the **full** `DocumentPropertiesW` output buffer (public `DEVMODEW` + `dmDriverExtra` private OEM bytes). This is the #36 fix.
- `get` clones; `set` inserts. Poisoned mutex → `get` returns `None`, `set` is a no-op.
- `#[allow(dead_code)]` because the type is compiled on all platforms; only Windows uses it.
- Constructed once in `lib.rs:53`: `.manage(print::PrinterDevModeStore::new())`.
- Session-only. Not persisted to disk.

### Module cfg gates (mod.rs:89–99)

```
#[cfg(windows)]                          pub mod windows;
#[cfg(any(target_os = "macos", test))]   pub mod macos;
#[cfg(any(unix, test))]                  pub mod unix;
#[cfg(test)]                             mod tests;
```

macOS **is** unix, so both `macos` and `unix` compile on macOS. Tests always compile both `macos` and `unix`. `macos.rs` `pub use`s `unix::{get_printer_capabilities, get_printers}`.

---

## Tauri command surface (`src-tauri/src/commands.rs:1304–1415`)

Registered in `lib.rs:92–95`.

| Command | Args | Windows | macOS | Linux |
|---------|------|---------|-------|-------|
| `get_printers` | none | `windows::get_printers` | `macos::get_printers` (= unix) | `unix::get_printers` |
| `get_printer_capabilities` | `printer_name: String` | DeviceCapabilitiesW | unix lpoptions/PPD | unix lpoptions/PPD |
| `show_printer_properties` | `printer_name: String` + `AppHandle` + `State<PrinterDevModeStore>` | `DocumentPropertiesW` modal; returns `Ok(None)` | `NSPrintPanel` on main thread; returns `Option<PrintPropertiesResult>` | **no-op** `Ok(None)` |
| `print_target_native` | `printer_name`, `tiff_path`, `options: Option<PrintOptions>` | GDI path, passes store | `macos::print_target` → `lp` | `unix::print_target` → `lp` |

IPC argument casing is camelCase at the Tauri boundary (`printerName`, `tiffPath`) and snake_case inside the nested `PrintOptions` struct because the frontend builds that object itself.

---

## Frontend (`src/js/printtarg.js` + `src/index.html`)

### Stage 2 print UI (`index.html:568–638`)

Hidden `#rawPrintPanel` revealed after `printtarg` succeeds and a JSON manifest is parsed.

- `#printerSelect` + `#btnRefreshPrinters` (↻) + `#btnPrinterProperties` (⚙️ Preferences, class `.btn-properties`) + `#printerStatusBadge`
- `#cupsOptionsGroup` / `#chkPpdFallback` — "PPD Uncorrected Passthrough (Fallback)". **Hidden on Windows** (#48, `printtarg.js:167-170`) via `navigator.userAgent` / `userAgentData.platform`.
- `#printerTraySelect`, `#printerMediaTypeSelect`
- Orientation toggle `#btnOrientPortrait` / `#btnOrientLandscape` (default portrait)
- `#btnPrintAll` — "Print All Pages (Bypass CM)"
- `#btnAdvanceToStage3`
- Per-page "Print Page" buttons on gallery cards (`printtarg.js:737-748`)

There is **no** printer paper-size dropdown in the raw-print panel. `#pageSizeSelect` above is printtarg's layout size and is reused as `PrintOptions.paper_size`.

### `capturedCupsOptions` (`printtarg.js:14–17, 266, 411-415`)

Module-level `{}` keyed by **printer name**. Populated only when macOS `show_printer_properties` returns a result with `options.cups_options`. Cleared for that printer if the result has no cups_options. Fed into every subsequent `print_target_native` via `getSelectedPrintOptions()`.

Cancellation: `result === null` → info toast, **no** map mutation.

If the user switched printer inside `NSPrintPanel`, the dropdown is updated when that CUPS id exists in the option list (`printtarg.js:402-409`). Captured media type is applied to `#printerMediaTypeSelect` when a matching option exists.

### Print payload (`printtarg.js:260-276`)

```js
{
  paper_source: trayVal ? parseInt(trayVal, 10) : null,  // NaN if unix tray name is non-numeric — Unix tray ids are 1-based indexes so this is OK
  orientation: selectedOrientation,                       // "portrait" | "landscape"
  paper_size: pageSizeSelect.value,                       // printtarg page size, not printer PageSize
  media_type: mediaType || null,
  ppd_uncorrected_passthrough: chkPpdFallback.checked,
  cups_options: capturedCupsOptions[activePrinter] || null,
}
```

### Wizard state

`wizardState.printerName` is set at spool time (`printtarg.js:579, 625`) so Stage 5 verification history (#95) can record the device.

---

