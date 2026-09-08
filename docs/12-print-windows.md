# 12 — Windows GDI raw printing

> Line numbers refer to ICCery v0.8.5 (`/tmp/ICCery` at analysis time) and the Gronod ArgyllCMS 3.5.0 fork.

## Windows (`src-tauri/src/print/windows.rs`)

Direct Win32. No `lp`, no XPS, no `winprint` crate. Evaluated and rejected in #26.

### Exact Win32 APIs used

From `windows` crate 0.61 (`Cargo.toml:50-55`: `Win32_Foundation`, `Win32_Graphics_Gdi`, `Win32_Graphics_Printing`, `Win32_UI_WindowsAndMessaging`) plus a local `extern "system"` block for symbols the crate feature set does not expose.

| API | Header / crate | Where | Purpose |
|-----|----------------|-------|---------|
| `EnumPrintersW` | `Win32::Graphics::Printing` | `get_printers` | Level 4 (`PRINTER_INFO_4W`) first; fall back to Level 1 (`PRINTER_INFO_1W`) |
| `OpenPrinterW` | Printing | properties + print | `PRINTER_HANDLE` |
| `ClosePrinter` | Printing | both | |
| `DocumentPropertiesW` | Printing | properties + print | size query (`fMode=0`), `DM_OUT_BUFFER` init, `DM_IN_PROMPT\|DM_IN_BUFFER\|DM_OUT_BUFFER` dialog |
| `GetForegroundWindow` | `Win32::UI::WindowsAndMessaging` | properties | parent HWND of the modal |
| `DeviceCapabilitiesW` | **local extern** | capabilities | `DC_BINS`(6), `DC_BINNAMES`(12), `DC_PAPERS`(2), `DC_PAPERNAMES`(16), `DC_MEDIATYPES`(35), `DC_MEDIATYPENAMES`(34) |
| `CreateDCW` | `Win32::Graphics::Gdi` | print | printer DC with DEVMODE |
| `DeleteDC` | Gdi | print | |
| `GetDeviceCaps` | Gdi | print | `LOGPIXELSX/Y`, `HORZRES`, `VERTRES` |
| `SetICMMode` | **local extern** | print | `ICM_OFF = 1` |
| `StartDocW` / `StartPage` / `EndPage` / `EndDoc` | **local extern** | print | GDI job |
| `StretchDIBits` | Gdi | print | unmanaged 24-bit BGR DIB |

`DOCINFOW` is a **local** `#[repr(C)]` struct (windows.rs:24-31), not the crate type, because `StartDocW` is also local-extern.

Constants (windows.rs:48-66):

```
ICM_OFF            = 1
DM_IN_PROMPT       = 4
DM_IN_BUFFER       = 8
DM_OUT_BUFFER      = 2
DM_ORIENTATION     = 0x00000001
DM_DEFAULTSOURCE   = 0x00000200
DM_ICMMETHOD       = 0x00800000
DMICMMETHOD_NONE   = 1
DMORIENT_PORTRAIT  = 1
DMORIENT_LANDSCAPE = 2
DM_MEDIATYPE       = 0x02000000
DC_PAPERS=2, DC_BINS=6, DC_BINNAMES=12, DC_PAPERNAMES=16,
DC_MEDIATYPENAMES=34, DC_MEDIATYPES=35
IDOK = 1
```

### Enumeration (`get_printers`, windows.rs:78-168)

1. `EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 4, …)` to get byte count.
2. If `bytes_needed == 0`, retry at Level 1 (older/limited spooler).
3. Level 4: `pPrinterName`. Level 1: `pName`.
4. `is_default` always false, `display_name` always `None`, `status` always `"Ready"`.
5. Empty list is success, not error.

### Capabilities (`get_printer_capabilities`, windows.rs:171-326)

`DeviceCapabilitiesW(printer, NULL port, cap, …)`. Bin names are 24 WCHARs each; paper and media names 64 WCHARs. Media type IDs are read as `u32` via a `*mut u16` cast of a `Vec<u32>` (windows.rs:288-289) — the Win32 API writes DWORDs for `DC_MEDIATYPES`.

`supports_orientation: true` unconditionally.

### Driver preferences dialog (`show_printer_properties`, windows.rs:329-401) — #34 / #36

```
OpenPrinterW
DocumentPropertiesW(..., fMode=0)            → required buffer size
load cached DEVMODE or zeros
if all-zero: DocumentPropertiesW(DM_OUT_BUFFER) to populate defaults
DocumentPropertiesW(DM_IN_PROMPT | DM_IN_BUFFER | DM_OUT_BUFFER)
ClosePrinter
if res == IDOK (1): store out_buf, Ok(())
if res == 2:        user cancel, Ok(())      // IDCANCEL
else:               Err(...)
```

Parent window is `GetForegroundWindow()`, **not** the Tauri webview HWND. The dialog is modal to whatever is foreground.

The **entire** `out_buf` (header + `dmDriverExtra`) is stored. That is the #36 fix: Epson "Print Preview" and other OEM private flags live past `dmSize` and were previously dropped.

### ICM bypass + option overlay (`apply_print_options_to_devmode`, windows.rs:404-437)

Always:

```
dmFields |= DM_ICMMETHOD
dmICMMethod = DMICMMETHOD_NONE   // 1
```

Then, if options present:

- `paper_source` → `dmFields |= DM_DEFAULTSOURCE`; `dmDefaultSource = tray_id as i16`
- `orientation == "landscape"` (case-insensitive) → `DMORIENT_LANDSCAPE` else portrait
- `media_type` parsed as `u32` → `dmFields |= DM_MEDIATYPE`; `dmMediaType = id`

**Not applied:** `paper_size`, `ppd_uncorrected_passthrough`, `cups_options`. Private OEM bytes after the public header are **not** touched (verified by `tests.rs:219-276`).

### GDI raw print path (`print_target`, windows.rs:440-643)

1. `image::open` TIFF → `to_rgb8()`. Crate features: `png`, `tiff` (`Cargo.toml:40`).
2. Pack **24-bit BGR** DIB, 4-byte row stride: `row_stride = ((w*3+3)/4)*4`. Top-down (`biHeight` negative).
3. `OpenPrinterW` → `DocumentPropertiesW` size → reuse cached DEVMODE (resized up if needed) or `DM_OUT_BUFFER` defaults → `apply_print_options_to_devmode`.
4. `CreateDCW(NULL, printer, NULL, pDevMode)`.
5. **`SetICMMode(hdc, ICM_OFF)`** — "STRICT ICM BYPASS".
6. `StartDocW` with title `ICCery Target - <filename>`. `lpszDatatype` null (driver default, not `"RAW"`).
7. `StartPage`.
8. Auto-fit scaler (#34):

```
dpi_x/y  = GetDeviceCaps(LOGPIXELSX/Y)   // used only for BITMAPINFO biX/YPelsPerMeter
page_w/h = GetDeviceCaps(HORZRES/VERTRES)
scale    = min(page_w/img_w, page_h/img_h)
dest     = floor(img * scale), centered
```

   Physical offsets (`PHYSICALOFFSETX/Y`) from #34's wish-list are **not** queried. Fit is to the printable DC area (`HORZRES`/`VERTRES`), which already excludes hardware margins.

9. `StretchDIBits(..., DIB_RGB_COLORS, SRCCOPY)`. This **can resample** if dest ≠ source pixels. Color is unmanaged (ICM off, BI_RGB) but geometric interpolation is GDI's. Contrast with ICCery-CPU, which forbids interpolation.

10. `EndPage` / `EndDoc` / `DeleteDC` / `ClosePrinter`.

Zero-dimension images error out before GDI. Missing TIFF: `"Target TIFF file not found: …"`.

### CREATE_NO_WINDOW vs print

`CREATE_NO_WINDOW` (`0x08000000`) is **not used on the print path**. Windows printing is in-process GDI; no child process is spawned.

`CREATE_NO_WINDOW` **is** applied to ArgyllCMS console-subsystem children so a black `cmd` window does not flash (#46):

- `src-tauri/src/process_manager.rs:99-103` — every `ProcessManager::spawn` (`targen`, `printtarg`, `chartread`, `colprof`, `profcheck`, `instlist`, …)
- `src-tauri/src/calibration.rs:849-853` — `printcal` / `applycal` captured runs

`printtarg` itself only **generates** TIFFs; it does not print. Native print is a separate IPC command.

### NSIS USB drivers (#127) — not printer drivers

USB install is for **spectrophotometer** libusb-win32 drivers (i1Pro, ColorMunki, SpyderPrint), **not** printer OEM drivers.

- Fetch: `scripts/fetch-argyll.mjs` copies `Argyll_V*/usb/` → `src-tauri/argyll/usb/` from the Windows zip (`ArgyllCMS_install_USB.exe`, `.inf`, `.cat`, `libusb0.sys` for x86/amd64/arm64).
- Bundle: `tauri.conf.json` `resources: ["argyll/**/*"]` + NSIS `installMode: "both"` + `installerHooks: "windows/hooks.nsh"`.
- `hooks.nsh` `NSIS_HOOK_PREINSTALL`: if elevated, `MessageBox` Yes/No "Install ArgyllCMS USB instrument drivers?".
- `NSIS_HOOK_POSTINSTALL`: `ExecWait` `$INSTDIR\argyll\usb\ArgyllCMS_install_USB.exe` or `$INSTDIR\resources\argyll\usb\...`. Not silent. Missing file → exclamation box.
- Uninstall does **not** run `ArgyllCMS_uninstall_USB.exe` (would break other Argyll apps).
- Also maps missing HKCU shell-folder drive letters via `DefineDosDevice` to avoid "Invalid Drive" on domain profiles.

WiX/MSI has no equivalent prompt.

### Windows idiosyncrasies / bugs fixed

| Issue | Symptom | Fix |
|-------|---------|-----|
| #25/#26 | Need ACPU-equivalent raw print | GDI + `SetICMMode(ICM_OFF)` + `DMICMMETHOD_NONE` + 24-bit BGR DIB |
| #34 | No driver dialog / trays / orientation / scaler | `DocumentPropertiesW` modal, `DeviceCapabilitiesW`, auto-fit `StretchDIBits` dest |
| #36 | Preferences (Epson Print Preview, private OEM) ignored | Cache **full** DEVMODE buffer including `dmDriverExtra`; pass that pointer to `CreateDCW` |
| #48 | "PPD Uncorrected Passthrough" shown on Windows | Hide `#cupsOptionsGroup` |
| #46 | Argyll console windows cover UI | `CREATE_NO_WINDOW` on subprocess spawn **only** — not on print |
| #67 | Duplicate `get_windows_printers` / `print_target_windows` | Collapsed to `get_printers` / `print_target_native` |

Remaining gaps:

- Default printer never flagged.
- `paper_size` not applied to `DEVMODE` (`DM_PAPERSIZE` unused).
- `PHYSICALOFFSET*` not used; scaler uses `HORZRES`/`VERTRES` only.
- `StretchDIBits` may interpolate when scaling.
- `show_printer_properties` Tauri result is always `None`, so the frontend reports cancel even on OK.
- No `PrinterProperties` / `AdvancedDocumentProperties` alternative; only `DocumentPropertiesW`.
- `GetForegroundWindow` can attach the modal to the wrong top-level window.

---

