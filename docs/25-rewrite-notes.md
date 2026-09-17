# 25 — Rewrite notes and idiosyncrasies

The new ICCery is **not** Tauri. Keep the product name, cone artwork, unmanaged-print semantics, and Argyll process boundary.

## Four different meanings of `-d`

| Tool | `-d` means |
|------|------------|
| `targen` | colourant combination (`2` RGB, `4` CMYK) |
| `printtarg` | custom **label** string (fork) |
| `iccgamut` | surface **density** (number, e.g. `10`) |
| `colprof` | output viewing condition |

Passing the wrong `-d` is the #1 class of silent misconfiguration (#112).

## Flags that look similar

- printtarg `-r` = no randomize / raster layout; targen `-r` = full-spread algorithm
- printtarg `-R seed` vs targen `-R` algorithm
- applycal `-u` = **unapply** curves, **not** JSON
- chartread `-Y l` (letter L) = LEDs; original ticket proposed `-L`

## JSON prefixes are inconsistent (fork)

| Tool | `-u` stdout |
|------|-------------|
| `chartread` | **`ROW_COLORS_JSON: `** + compact JSON |
| `printtarg` | pretty-printed **bare** JSON manifest |
| `profcheck` | one compact **bare** JSON line |
| `targen` / `colprof` | compact JSON (fork) — ICCery currently **does not** pass `-u` |
| `instlist` | pretty JSON, no `-u` needed |

Only chartread lines are intercepted by ProcessManager. Manifest/profcheck JSON arrives as `process:stdout` and must be parsed from the accumulator.

## Windows musts

- `CREATE_NO_WINDOW` (`0x08000000`) on every Argyll spawn
- `.exe` candidate first (`resolve_binary`)
- `.icm` default extension
- GDI `SetICMMode(ICM_OFF)` + `DMICMMETHOD_NONE`
- Cache full DEVMODE bytes from DocumentProperties (#36) — applying fields onto a fresh DEVMODE drops driver extras
- Hide CUPS checkbox (`#cupsOptionsGroup`)
- PeekNamedPipe fork + `ARGYLL_NOT_INTERACTIVE=1`
- TIFF→PNG in host, not in the webview

## macOS musts

- Preferences = **NSPrintPanel on the AppKit main thread**, never System Settings URL, never cupsctl web UI (#188 comments 1–5)
- `PMPrinterCreateFromPrinterID(CUPS id)` then `display_name` → `NSPrinter::printerWithName`
- Private SPI via `dlsym`: **2-argument** `(PMPrintSession, *const CFString) -> i32`. Passing integer `1` as a lock flag **SIGSEGV**. Try Lock, then Mode, then NoLock. Modes: `AP_ApplicationColorMatching` then `ApplicationColorMatching` only
- Dual keys `AP_ColorMatchingMode` and dotted `AP.ColorMatchingMode`
- Mirror into `NSPrintInfo.printSettings` dictionary (PDEs read this)
- Pre-select Canon `CNIJIntent2=4`, Epson `EPIJ_CMat=3` (or `EPIJ_CCor=0`), Gutenprint `StpColorCorrection=Uncorrected`
- `lp` always includes both AP_* options + captured cups_options + bypass if missing
- Cancel = `Ok(None)`, not an error
- Dark WKWebView: `drawsBackground=NO`, under-page colour, window hidden until paint
- `minimumSystemVersion` 12.0
- Ad-hoc sign Argyll Mach-O sidecars on Apple Silicon (#165)
- TargetPrint companion uses **different** ColorSync keys (`APCustomColorMatching`). Do not mix the two dictionaries.

## Linux musts

- `lp` not `lpr`
- Default `-o raw`; fallback `ColorModel=Gray` + `cm-calibration` if `#chkPpdFallback`
- Enumerate `lpstat -e/-p/-d` + `lpoptions -p -l` + `/etc/cups/ppd/{name}.ppd`

## Frontend musts

- No WebGL until Stage 5 visible; pause rAF on leave; survive context lost
- `iccgamut -d 10` density
- Average snapshots delete canonical `.ti3`
- Open dialogs for import; save dialogs only when saving
- No `innerHTML` for user-supplied preset/dataset names
- Atomic history writes
- Deterministic printtarg `-R 1`
- Honour patch count `-f`

## Suggested characterisation tests (from tickets)

Lock these before rewriting UI:

1. `build_*_args` golden vectors (already in Rust unit tests — port them)
2. `classifyChartreadLine` 39 cases
3. `parseGamutFile` multi-`BEGIN_DATA`, comments, OOB vertices
4. `parseProfcheckReport` JSON + legacy + empty→warning
5. Color bypass detector: Canon/Epson/Gutenprint samples
6. `filter_cups_options_string` drops `com.apple.*`, keeps `EPIJ_CMat`
7. `build_lp_args` always emits both AP_* keys (**historical v1** — superseded by `TicketWriteResolverTests`, #201)
8. Threshold validation `good < warning`
9. `snapshot_ti3` 1-based and removes canonical
10. DEVMODE round-trip size

## Host command list (complete)

From `lib.rs` `generate_handler!` — a rewrite should provide equivalents with the **same argument names** (Tauri command arguments are `camelCase` at the IPC boundary, Rust fields `snake_case` inside structs).

### Process / platform

`spawn_process`, `send_stdin`, `kill_process`, `kill_all_processes`, `resolve_binary`, `get_app_info`, `get_os_info`, `show_main_window`, `get_default_working_dir`, `get_log_path`, `get_recent_log_excerpt`, `log_frontend_message`, `open_log_dir`

### Files / dialogs

`select_existing_target`, `select_profile_file`, `select_spectrum_file`, `select_dataset_file`, `select_target_file`, `select_directory`, `select_csv_save_path`, `read_file_base64`, `read_tiff_preview_png`, `parse_ti2_header`

### Wizard / Argyll

`detect_instruments`, `get_profile_path`, `verify_stage_artefacts`, `extract_gamut`, `run_targen`, `run_printtarg`, `run_chartread`, `snapshot_ti3`, `promote_ti3`, `run_average`, `run_colprof`, `run_profcheck`

### Print

`get_printers`, `get_printer_capabilities`, `show_printer_properties`, `print_target_native`

### Calibration (9)

`generate_calibration_target`, `compute_calibration_curves`, `apply_calibration`, `parse_cal_file_cmd`, `list_saved_calibrations`, `save_calibration_to_library`, `select_cal_file`, `load_project_calibration`, `save_project_calibration`

### Profile install

`install_profile_to_system`, `get_profile_install_dir`

### Quality store (4)

`save_verification_record`, `get_verification_history`, `clear_verification_history`, `export_verification_history_csv`

### Settings / presets (7)

`load_settings`, `save_settings`, `get_all_presets`, `save_preset`, `delete_preset`, `export_preset_json`, `import_preset_json`

### CGATS

`import_measurement_dataset`, `export_measurement_dataset`, `inspect_dataset_preview`

## Licence / AGPL

GUI: proprietary EULA (`LICENCE.md`). Argyll sidecars: AGPLv3, subprocess-only. Third-party: Three.js r128 MIT, OrbitControls, CSS2DRenderer, quickhull. Rewrite may swap the renderer but must not link Argyll.
