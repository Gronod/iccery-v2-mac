# 13 — Linux CUPS printing

> Line numbers refer to ICCery v0.8.5 (`/tmp/ICCery` at analysis time) and the Gronod ArgyllCMS 3.5.0 fork.

## Linux (`src-tauri/src/print/unix.rs`)

No libcups FFI. Shell out to CUPS CLI: `lpstat`, `lpoptions`, `lp`. **`lpr` is never used.**

### Enumeration

| Command | Parser | Result |
|---------|--------|--------|
| `lpstat -e` | `parse_lpstat_e` | destination names, one per non-empty trimmed line |
| `lpstat -p` | `parse_lpstat_p` | `(name, status)` from lines `printer <name> …`. Status: idle → Idle; printing/now printing → Printing; disabled/stopped → Stopped; else Unknown |
| `lpstat -d` | `parse_lpstat_d` | `system default destination: <name>` |
| `lpoptions -p <name>` | `extract_printer_display_name` | `printer-info=` value, quotes stripped |

`merge_printer_info`: destinations first (status from `-p` or `"Idle"`), then any `-p` names not already seen. Each entry calls `lpoptions` for `display_name` (N printers = N extra processes).

If both `-e` fails and `-p` cannot even be spawned, error `"Failed to execute 'lpstat': …"`. Otherwise partial data is OK.

### Capabilities / PPD

`lpoptions -p <printer> -l` parsed by `parse_lpoptions_l` (unix.rs:181-229):

| PPD key (before `/`) | Destination |
|----------------------|-------------|
| `InputSlot`, `MediaSource` | trays (1-based index id, `*` stripped) |
| `PageSize`, `MediaSize` | paper_sizes |
| `CNIJMediaType`, `MediaType`, `StpMediaType`, `EPIJ_Medi` | media_types (id = name = token) |

Then, if `/etc/cups/ppd/<printer>.ppd` is readable, `parse_ppd_media_types` **replaces** media_types with id/name pairs from `*CNIJMediaType `, `*MediaType `, `*StpMediaType `, `*EPIJ_Medi ` lines (`id/Human Name:`).

macOS typically has PPDs under `~/Library/Printers` or a CUPS temp copy, **not** `/etc/cups/ppd/`, so the PPD-file enrichment is Linux-centric. macOS still gets media types from `lpoptions -l`.

### Driver color bypass detection (`detect_driver_color_bypass`, unix.rs:251-272)

First-match order:

| Probe substring | Key | Value | Meaning |
|-----------------|-----|-------|---------|
| `CNIJIntent2` | `CNIJIntent2` | `4` | Canon "Off (No Color Adjustment)" |
| `CNIJIntent` | `CNIJIntent` | `4` | older Canon |
| `EPIJ_CCor` | `EPIJ_CCor` | `0` | Epson Color Settings — 0 disables correction (preferred over CMat if both exist) |
| `EPIJ_CMat` | `EPIJ_CMat` | `3` | Epson "Off (No Color Adjustment)" |
| `StpColorCorrection` | `StpColorCorrection` | `Uncorrected` | Gutenprint |
| `ColorCorrection` | `ColorCorrection` | `Uncorrected` | generic |
| `EpsonColorMode` | `EpsonColorMode` | `Off` | Epson |

`EPIJ_OSColMat` is **not** auto-detected (but is forwarded if captured on macOS). `ColorModel` is forwarded if captured, not auto-set on Linux except the Gray fallback below.

### Media type key (`detect_media_type_key`, unix.rs:274-284)

`CNIJMediaType` > `EPIJ_Medi` > `StpMediaType` > `MediaType`.

### Linux `build_lp_args` / `print_target` (unix.rs:362-457)

```
lp -d <printer> -t "ICCery Target - <filename>"
   [-o raw]                            # default
   OR [-o ColorModel=Gray -o cm-calibration]   # ppd_uncorrected_passthrough == true
   [-o orientation-requested=3|4]
   [-o PageSize=<paper_size>]
   [-o MediaType=<media_type>]         # generic key only — does not call detect_media_type_key
   <tiff_path>
```

- **`raw` queue:** CUPS skips filters (no `cgpdftoraster`, no PPD color). The TIFF is sent as the job payload. Printers that cannot consume raw TIFF need the checkbox fallback.
- **Fallback `ColorModel=Gray` + `cm-calibration`:** documented as "uncorrected CUPS passthrough" for devices that reject raw TIFF. `Gray` is a surprising choice for color targets — it is the historical CUPS "don't color-manage" trick, not a conversion of the image to grayscale at the app layer. Still a rewrite risk: a color TIFF with `ColorModel=Gray` may be wrong on some drivers.
- **No ColorSync flags** (those are macOS-only).
- **No auto driver-bypass injection** on Linux (Canon/Epson PPD keys are **not** added unless the user typed them — and there is no Linux Preferences dialog to capture them).
- `paper_source` / `cups_options` ignored.
- `lp` failure: stderr, else stdout, else exit code, wrapped as `"CUPS print job failed: …"`.
- Missing file: `"Target TIFF file not found: …"`.

### Linux Preferences

`commands.rs:1364-1368` — `show_printer_properties` is a no-op `Ok(None)`. There is no CUPS web-UI (`http://localhost:631`) launcher, no `system-config-printer`, no `gtk-print-unix-dialog`. The `#btnPrinterProperties` click therefore always looks like a cancel on Linux.

### `lp` vs `lpr`

Always `lp` (`Command::new("lp")`). `lpr` is never invoked. `lp` is the CUPS System V client and is what `-o name=value` and `-d dest` are specified against. `lpr` BSD syntax (`-P`, `-o` still works on CUPS) was not used.

### CUPS options string parser (`parse_cups_options_string`, unix.rs:286-332)

Shared with macOS. Whitespace-separated `name=value`; double quotes toggle; quotes stripped from both sides; tokens without `=` skipped; `AP_D_InputSlot=` yields `("",)` empty value.

---

