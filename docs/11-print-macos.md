# 11 — macOS printing and ColorSync suppression

> Line numbers refer to ICCery v0.8.5 (`/tmp/ICCery` at analysis time) and the Gronod ArgyllCMS 3.5.0 fork.

This is the most implementation-sensitive chapter. A rewrite that opens System Settings or the CUPS web UI instead of `NSPrintPanel` will regress #188.

## macOS (`src-tauri/src/print/macos.rs`) — MOST DETAIL

864 lines. This is the ColorSync-suppression engine built for #92 and rewritten for #188.

### What Preferences opens — NSPrintPanel vs CUPS web UI vs System Settings

**Issue #188 (user report):** clicking Preferences opened **System Settings → Printers & Scanners** and did not bind the selected Epson/Canon queue. No driver PDE, so no "Off (No Color Adjustment)".

**Current code (AGENTS.md:105-118, macos.rs:245-516, 679-710):** Preferences opens a **native AppKit `NSPrintPanel`**, pre-bound to the selected CUPS destination via Core Printing. It is **not**:

- CUPS web UI (`http://localhost:631/printers/…`)
- System Settings → Printers & Scanners
- `NSWorkspace` open of the printer
- `lpoptions` GUI

Linux/Windows do not share this panel. Default button title is **"Use Settings"** (macos.rs:439) — this is a settings-capture dialog, not a print-now dialog. Actual spooling is a later, separate step — in v2.0 a headless `NSPrintOperation` (#201; v1 used `lp`).

Must run on the Cocoa main thread. `show_printer_properties` (macos.rs:689-710):

1. Resolve `display_name` **off** the main thread via `unix::get_printer_display_name` (`lpoptions -p`).
2. `app.run_on_main_thread` → `run_native_print_panel`.
3. `tokio::sync::oneshot` awaits the result.

### objc2 crates (`Cargo.toml:42-47`, AGENTS.md:120-126)

```
objc2                    0.6      MainThreadMarker
objc2-app-kit            0.3.2    features = ["NSPrintInfo", "NSPrintPanel", "NSPrinter"]
objc2-foundation         0.3.2    NSString
objc2-core-foundation    0.3.2    CFString, CFType
objc2-application-services 0.3.2  features = ["PMCore", "PMDefinitions", "PrintCore"]
                                  PMPrintSession, PMPrinter, PMPrintSettings, PMPageFormat, …
```

Local `extern "C" { fn free; fn dlsym; }`. No `libloading` crate.

### Binding the selected printer (macos.rs:276-347)

CUPS destination IDs ≠ NSPrinter display names. Core Printing "Printer ID" **is** the CUPS queue name.

```
printer_id_cf = CFString(printer_name)
pm_printer    = PMPrinterCreateFromPrinterID(&printer_id_cf)

if pm_printer is null:
    fallback NSPrinter::printerWithName(display_name)
    print_info.setPrinter(ns_printer)
    print_info.setUpPrintOperationDefaultValues()
    if that also fails → Err("No printer found for '…'")

pm_session      = print_info.PMPrintSession()
pm_settings     = print_info.PMPrintSettings()
pm_page_format  = print_info.PMPageFormat()

if pm_printer was created from ID:
    PMSessionSetCurrentPMPrinter(pm_session, pm_printer)   // non-zero → Err
    PMSessionDefaultPrintSettings(pm_session, pm_settings) // warn on fail
    PMSessionDefaultPageFormat(pm_session, pm_page_format) // warn on fail
```

`Printer.display_name` is the CUPS `printer-info` cached at enumeration. That is what System Settings shows ("Epson XP-55 Series") while `printer_name` is the queue id (`EPSON_XP_55_Series`). #188 failed because the old path used the wrong name with the wrong API.

`PMPrinter` from `PMPrinterCreateFromPrinterID` is released with `PMRelease` on all exit paths (cancel, error, success). The NSPrinter fallback path leaves `pm_printer` null so no release.

### ColorSync suppression strategy — UI click to `NSPrintOperation`

End-to-end, **seven independent layers**. All of them exist because no single Apple API is sufficient across Epson PDE / Canon PDE / `cgpdftoraster` / CUPS. v2.0 (#201) replaced the `lp` tail with a headless `NSPrintOperation` that replays a captured `PMPrintSettings`/`PMPageFormat` ticket — layer ⑦ is new.

```
[Preferences click]
    PrintSessionViewModel.openPrinterPreferences
        PrintPanelService.showProperties
            runNativePanel
                ① PMPrinterCreateFromPrinterID + PMSessionSetCurrentPMPrinter   bind queue
                ② set_session_color_matching_mode SPI   gray out PDE Color Matching
                ③ PMPrintSettingsSetValue               AP_ColorMatchingMode + dotted
                ④ detect_driver_color_bypass → SetValue pre-select Canon/Epson/Gutenprint "off"
                ⑤ NSPrintInfo.printSettings dictionary  same keys for AppKit PDEs
                ⑤′ ColorSyncSuppressor.applyQuartzMode   PMColorMatchingMode + legacy + nested mirror
                NSPrintPanel.runModal("Use Settings")
                user picks media / quality (color locked)
                ⑥ PMPrintSettingsToOptions → filter → Stage 2 mirror
                ⑦ PMTicketBridge.serialise(printInfo) → PrintTicket          ticket capture
[frontend]
    capturedCupsOptions[queue] = mirror   +   capturedTickets[queue] = ticket
[Print Target]
    PrintSessionViewModel → TargetPrintRequest → NativeTargetSpooler.spool
        restore ticket → Stage 2 writes → NSPrintOperation.runOperation
        (S1–S14 below — 1:1, device colour space, panels off)
```

Linux uses `-o raw` instead of AP_* flags. macOS **does not** use `-o raw`: a raw queue would skip the raster filter that actually understands `AP_ColorMatchingMode`. The macOS strategy is "tell the filter the application already matched color", not "skip the filter".

### Layer ② — private SPI via `dlsym` (`set_session_color_matching_mode`, macos.rs:32-130)

Used by Photoshop, Lightroom, X-Rite i1Profiler to gray-out Color Matching in driver PDEs. Undocumented; resolved at runtime so the binary does not hard-link a private symbol.

```
RTLD_DEFAULT = (-2isize) as *mut c_void

dlsym(RTLD_DEFAULT, "PMSessionSetColorMatchingModeLock")
dlsym(RTLD_DEFAULT, "PMSessionSetColorMatchingMode")
dlsym(RTLD_DEFAULT, "PMSessionSetColorMatchingModeNoLock")
```

**Signature (all three):**

```c
OSStatus PMSessionSetColorMatchingModeLock  (PMPrintSession, CFStringRef mode);
OSStatus PMSessionSetColorMatchingMode      (PMPrintSession, CFStringRef mode);
OSStatus PMSessionSetColorMatchingModeNoLock(PMPrintSession, CFStringRef mode);
```

Rust:

```rust
type ModeFn = unsafe extern "C" fn(PMPrintSession, *const CFString) -> i32;
```

`status == 0` is success (`noErr`).

**Priority:**

1. `PMSessionSetColorMatchingModeLock` — sets **and locks** the UI in one call (controls grayed).
2. `PMSessionSetColorMatchingMode` — sets mode; lock behaviour unspecified.
3. `PMSessionSetColorMatchingModeNoLock` — sets without locking.

For each symbol, try mode strings in order:

```
"AP_ApplicationColorMatching"   // kPMApplicationColorMatching
"ApplicationColorMatching"      // unprefixed alias
```

First `(symbol, mode)` that returns 0 wins; then break both loops.

**Preconditions:** `pm_session` non-null; `PMSessionGetCurrentPrinter` succeeds with a non-null printer. Otherwise skip SPI (session has no printer to attach a PDE to).

**Stub on non-macOS:** always `false` so unit tests compile.

If all fail: log `"All PMSessionSetColorMatchingMode calls failed; color controls may not be grayed"` and fall through to public `PMPrintSettingsSetValue`.

### Why `AP_ColorSyncMatching` and `AP_VendorColorMatching` are avoided

AGENTS.md:118, macos.rs:82-88:

> Only application-managed color-matching modes are appropriate for profiling targets. ColorSync or vendor modes would apply color management and corrupt the target patches.

| Mode string | Effect on a profiling target |
|-------------|------------------------------|
| `AP_ApplicationColorMatching` / `ApplicationColorMatching` | **Used.** "Application already did color." Filters/PDEs must not transform pixels. UI Color Matching grayed. |
| `AP_ColorSyncMatching` | **Avoided.** ColorSync applies the printer/display profile. Patches become color-managed. |
| `AP_VendorColorMatching` | **Avoided.** Epson/Canon driver color engine (ICM inside the PDE). Same corruption. |

ICCery-CPU uses a **different** vocabulary (`APCustomColorMatching` / `APColorSync` / `APPrinterExtension` on `PMColorMatchingMode`). See the CPU section. v1 kept the two dictionaries on separate paths (`lp` vs Quartz); v2.0 (#201, D2) has a single native path that writes **both** vocabularies — layer ⑤′ below.

### Layer ③ — `PMPrintSettingsSetValue` (macos.rs:357-375)

```
key  = "AP_ColorMatchingMode"     and    "AP.ColorMatchingMode"
val  = "AP_ApplicationColorMatching"
lock = true
PMPrintSettingsSetValue(pm_settings, key, val, true)
```

The dotted `AP.ColorMatchingMode` is a **legacy form used by some raster drivers and PDEs** (macos.rs:540-541). Both are always written.

### Layer ④ — pre-select driver "no color adjustment" in the panel (macos.rs:377-397, 422-432)

`lpoptions -p <printer> -l` → `unix::detect_driver_color_bypass`:

| Driver | Key | Value |
|--------|-----|-------|
| Canon | `CNIJIntent2` | `4` |
| Canon (old) | `CNIJIntent` | `4` |
| Epson | `EPIJ_CCor` | `0` (if that key exists, preferred) |
| Epson | `EPIJ_CMat` | `3` |
| Gutenprint | `StpColorCorrection` | `Uncorrected` |
| generic | `ColorCorrection` | `Uncorrected` |
| Epson alt | `EpsonColorMode` | `Off` |

Written twice: `PMPrintSettingsSetValue(..., lock=false)` **and** `print_info.printSettings().insert`. Lock is false so the user can still change media/quality; only color matching is intended to be locked by the SPI.

### Layer ⑤ — `NSPrintInfo.printSettings` dictionary (macos.rs:399-432)

AppKit PDEs and some raster drivers read this `NSMutableDictionary`, not the PM object.

```
print_info.updateFromPMPageFormat()
print_info.updateFromPMPrintSettings()
print_settings.insert("AP_ColorMatchingMode",  "AP_ApplicationColorMatching")
print_settings.insert("AP.ColorMatchingMode",  "AP_ApplicationColorMatching")
print_settings.insert(<bypass_key>, <bypass_val>)
```

`NSString` is transmuted to `&AnyObject` for the dictionary (`macos.rs:414-416`).

### Layer ⑤′ — Quartz vocabulary (v2.0, #201 D2)

With `lp` gone there is a single native path, and it carries **both**
dictionaries. `ColorSyncSuppressor.applyQuartzMode` additionally writes the
Quartz/`NSPrintOperation` vocabulary (docs/14 §7):

- `PMColorMatchingMode` = `APCustomColorMatching`
- `PMCustomColorMatchingProfile` = `""`
- `com.apple.print.PrintSettings.PMColorMatchingMode` (legacy)
- the same keys inside the nested `com.apple.print.printSettings`
  sub-dictionary of `printInfo.dictionary()`

### Panel options (macos.rs:434-449)

```
NSPrintPanel::printPanel(mtm)
opts = NSPrintPanelOptions::all()
opts.insert(ShowsPageSetupAccessory)
panel.setOptions(opts)
panel.setDefaultButtonTitle(Some("Use Settings"))
response = panel.runModalWithPrintInfo(&print_info)
```

`response != 1` (`NSModalResponseOK` / `NSOKButton`) → **`Ok(None)`** (cancellation is not an error). `PMPrinter` released.

### Layer ⑥ — `PMPrintSettingsToOptions` capture (macos.rs:452-515)

After OK:

1. `PMSessionGetCurrentPrinter` → `PMPrinterGetID` → `selected_printer` string.
2. `panel.printInfo().PMPrintSettings()`.
3. `PMPrintSettingsToOptions(updated_settings, &mut opts_ptr)` — CUPS malloc'd C string of `key=value key=value …`.
4. Copy via `CStr`, `free(opts_ptr)`.
5. `filter_cups_options_string` → `cups_options`.
6. `extract_media_type_from_options` → `media_type`.
7. Return `PrintPropertiesResult { selected_printer, options: PrintOptions { media_type, cups_options, ppd_uncorrected_passthrough: Some(true), ..Default } }`.

Failure of `PMPrintSettingsToOptions` is a hard `Err`.

### Layer ⑦ — ticket serialise/restore (v2.0, #201 D3)

The layer-⑥ flattening is what lost the ticket (#201 root cause 1): it kept
only a `key=value` string and `CupsOptionsFilter` drops every `com.apple.*`
key, so `com.apple.print.PrintSettings` never survived. After the layer-⑥
capture, `PMTicketBridge.serialise(printInfo, queue:)` now snapshots the
whole ticket:

1. `PMPrintSettingsCreateDataRepresentation(settings, &data, kPMDataFormatXMLDefault)` → `PrintTicket.printSettings`.
2. `PMPageFormatCreateDataRepresentation` → `PrintTicket.pageFormat`.
3. Binary-plist snapshot of `NSPrintInfo.dictionary()`, plist-filtered → `PrintTicket.printInfoPlist` — fallback only, never the primary restore path.

`PrintTicket` is in-memory, session-only, keyed by queue. On spool,
`PMTicketBridge.restore` replays it into the job's `NSPrintInfo`:
`PM*CreateWithDataRepresentation` → `PMCopy*` → `PMSessionValidate*` →
`updateFromPM*`. A ticket captured for queue A is never replayed onto
queue B.

### `RELEVANT_CUPS_OPTION_KEYS` (macos.rs:142-174)

Captured from the panel into the Stage 2 mirror (v1 forwarded them to `lp`):

```
Media:      MediaType, CNIJMediaType, EPIJ_Medi, StpMediaType
Tray:       InputSlot, AP_D_InputSlot
Size:       PageSize
Color:      CNIJIntent2, CNIJIntent, EPIJ_CMat, EPIJ_CCor, EPIJ_OSColMat,
            ColorCorrection, StpColorCorrection, EpsonColorMode, ColorModel
Quality:    Resolution, cupsPrintQuality, Quality, EPIJ_Quality, CNIJQuality,
            StpQuality, OutputMode
Duplex:     Duplex, sides
```

`is_relevant_cups_option` (macos.rs:178-204) additionally:

- Drops empty keys
- Drops `com.apple.*` ticket keys
- Drops `AP_ColorMatchingMode` and `AP.ColorMatchingMode` (we always set those ourselves)
- Drops empty values (`AP_D_InputSlot=`)
- Drops `collate`, `copies`, `pserrorhandler-requested`, `job-sheets`
- **Keeps unknown non-`com.*` keys** (permissive: unknown driver keys survive)

### Native spool — S1–S14 (v2.0, #201)

`NativeTargetSpooler.spool(_:)` (app target, `Sources/ICCery/Print/` — `ICCeryCore` stays AppKit-free, D1). One `TargetPrintRequest` per page, or one per run when `singleJobForAllPages` is on (D5):

```
S1  NSPrintInfo()
S2  printInfo.printer = NSPrinter(name: queue) ?? NSPrinter(name: displayName)   [best effort]
S3  PMTicketBridge.makePrinter(queue:) → bind(printer:to:)   ① + PMSessionDefault*
S4  ticket != nil → PMTicketBridge.restore(ticket, into: printInfo)              ⑦′
S5  TicketWriteResolver.resolve(...) → apply to PMPrintSettings + mirror dict    ③④⑤+D2
S6  paper override → PMTicketBridge.applyPaper(token:…)
S7  orientation → printInfo.orientation + orientation-requested
S8  suppressor.applySPIMode(session)                                             ②
S9  Cocoa geometry: margins 0, pagination .clip, scaling 1.0, centering off,
    jobDisposition .spool (or .save + jobSavingURL under the PDF harness)
S10 TargetRasterLoader.load(each page) → device-tagged CGImage + pointSize
S11 TargetPageCanvasView(pages:paperSize: printInfo.paperSize)
S12 NSPrintOperation(view:printInfo:) — panels off, jobTitle set
S13 operation.runOperation() → false ⇒ throw TargetSpoolError.operationFailed
S14 PMRelease the printer on every path (defer)
```

`TicketWriteResolver` produces the resolved write list as a pure value, in a
locked order: both `AP_*` keys (locked) → the three Quartz keys (⑤′) →
`PageSize` → the detected media key → the detected quality key → the driver
colour bypass → `orientation-requested`. Stage 2 overrides **always win**
over the rehydrated ticket (D6 — the v1 captured-wins inversion is gone);
`raw` can never appear because there is no `lp`. Panels stay off
(`showsPrintPanel` / `showsProgressPanel` false, `canSpawnSeparateThread`
false); a multi-page job is one `TargetPageCanvasView` driven by
`knowsPageRange` / `rectForPage`, drawing each page 1:1 top-left anchored
with interpolation and antialiasing disabled (D9, docs/14 §6).

### Cancellation as `None`

`run_native_print_panel` → `Ok(None)` on cancel. `show_printer_properties` propagates that. Frontend: `if (result === null) { showNotification("info", "Printer properties dialog cancelled."); return; }`.

### Preferences crash / #188

#188 was not a segfault; it was a **wrong UI**: System Settings instead of the driver PDE, so color management could not be disabled on Epson XP-55 / Canon Pro 9500 II.

The rewrite:

- Bind by CUPS Printer ID (`PMPrinterCreateFromPrinterID` + `PMSessionSetCurrentPMPrinter`), not by opening System Settings.
- `display_name` fallback for `NSPrinter::printerWithName`.
- Private SPI to lock Color Matching.
- Dual AP_* keys (underscore + dotted).
- Driver-specific PPD bypass pre-selected in the panel and re-applied on the spool ticket (v1 re-applied it on `lp`).
- Capture via `PMPrintSettingsToOptions` into `capturedCupsOptions` (Stage 2 mirror) plus the `PrintTicket` serialise (layer ⑦, v2.0).

`PMPrinter` lifetime is explicit `PMRelease` on every path. SPI is `dlsym`'d so missing symbols on old OS X do not prevent launch. Panel **must** be main-thread (`MainThreadMarker::new().ok_or("Print panel must be invoked on the main thread")`).

### macOS tests — historical v1 (macos.rs:712-863 + tests.rs:278-318)

- Filter drops `com.apple.*`, `collate`, `copies`, `AP_ColorMatchingMode`, empty `AP_D_InputSlot`; keeps `MediaType`, `EPIJ_CMat`, `PageSize`, `CNIJIntent2`, `ColorCorrection`.
- `extract_media_type_from_options` prefers `MediaType` then `EPIJ_Medi`.
- `build_lp_args` always contains both AP_* flags; captured options win over explicit `media_type` / orientation / auto color-bypass; last arg is the TIFF path. (**Historical v1** — the captured-wins behaviour recorded here is #201 root cause 2; v2.0 inverts it: Stage 2 always wins, D6.)
- `detect_driver_color_bypass` Canon `4`, Epson `3`, Gutenprint `Uncorrected`.
- Missing TIFF errors.

v2.0 replacements (`TicketWriteResolverTests`, `PrintTicketTests`,
`TargetRasterTests`, `TargetCanvasGeometryTests`, `NativeSpoolPDFTests`):
both AP_* keys locked + all three Quartz keys always present; Stage 2
always wins (D6); `raw` never emitted; ticket serialise/restore
round-trips bytes; 1:1 geometry and draw flags asserted against a real
`.save`-to-PDF `NSPrintOperation`.

---

## ColorSync suppression — complete key/SPI/flag roster

### Private SPI symbols (dlsym, macOS only)

```
PMSessionSetColorMatchingModeLock     (PMPrintSession, CFStringRef) -> i32
PMSessionSetColorMatchingMode         (PMPrintSession, CFStringRef) -> i32
PMSessionSetColorMatchingModeNoLock   (PMPrintSession, CFStringRef) -> i32
```

Mode strings attempted: `AP_ApplicationColorMatching`, `ApplicationColorMatching`.

Public Core Printing used around the SPI:

```
PMPrinterCreateFromPrinterID
PMSessionSetCurrentPMPrinter
PMSessionGetCurrentPrinter
PMSessionDefaultPrintSettings
PMSessionDefaultPageFormat
PMPrintSettingsSetValue
PMPrintSettingsToOptions
PMPrinterGetID
PMRelease
```

AppKit: `NSPrintInfo`, `NSPrintPanel`, `NSPrinter::printerWithName`, `NSPrintPanelOptions::all` + `ShowsPageSetupAccessory`.

### CUPS / lp flags — historical v1

> No `lp` invocation exists on the v2.0 target-print path (#201 — `LpArgs`,
> `CupsService.printTarget` and the `lp` fixture are deleted). This table
> records the v1 `lp -o` contract for reference only; the live write list is
> `TicketWriteResolver`'s locked order (§native spool above).

| Flag | Platform | When |
|------|----------|------|
| `-o AP_ColorMatchingMode=AP_ApplicationColorMatching` | macOS | always |
| `-o AP.ColorMatchingMode=AP_ApplicationColorMatching` | macOS | always |
| `-o CNIJIntent2=4` | macOS (auto) / if captured | Canon |
| `-o CNIJIntent=4` | macOS auto if no Intent2 | Canon old |
| `-o EPIJ_CCor=0` | macOS auto if present in lpoptions | Epson |
| `-o EPIJ_CMat=3` | macOS auto | Epson Off |
| `-o StpColorCorrection=Uncorrected` | macOS auto | Gutenprint |
| `-o ColorCorrection=Uncorrected` | macOS auto | generic |
| `-o EpsonColorMode=Off` | macOS auto | Epson alt |
| `-o CNIJMediaType=` / `EPIJ_Medi=` / `StpMediaType=` / `MediaType=` | macOS (detected key); Linux always `MediaType=` | media |
| `-o PageSize=` | macOS/Linux | if set |
| `-o orientation-requested=3\|4` | macOS/Linux | portrait/landscape |
| `-o raw` | **Linux only** | default |
| `-o ColorModel=Gray -o cm-calibration` | **Linux only** | PPD fallback checkbox |
| captured `InputSlot`, `AP_D_InputSlot`, `Resolution`, `cupsPrintQuality`, `Quality`, `EPIJ_Quality`, `CNIJQuality`, `StpQuality`, `OutputMode`, `Duplex`, `sides`, `EPIJ_OSColMat`, `ColorModel` | macOS | if panel produced them |

### PPD keys (detection)

```
Media:   CNIJMediaType, EPIJ_Medi, StpMediaType, MediaType, MediaSource, InputSlot, PageSize, MediaSize
Color:   CNIJIntent2, CNIJIntent, EPIJ_CCor, EPIJ_CMat, StpColorCorrection, ColorCorrection, EpsonColorMode
```

---

