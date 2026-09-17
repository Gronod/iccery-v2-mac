# 14 — ICCery-CPU / TargetPrint (macOS companion)

> Line numbers refer to ICCery v0.8.5 (`/tmp/ICCery` at analysis time) and the Gronod ArgyllCMS 3.5.0 fork.

## ICCery-CPU / TargetPrint

Separate native macOS AppKit app. Spec: `/tmp/ICCery-CPU/SPEC.md`. Binary name `TargetPrint`. Zero third-party deps. Universal 2. Hardened Runtime on, App Sandbox **off** (needs `cupsGetPPD`).

### Why it exists

ICCery's Tauri path spooled TIFF via `lp` and never went through Quartz (v1; v2.0 spools via a headless `NSPrintOperation` in ICCery proper — #201). That is correct for "don't let ColorSync touch the file", but:

- No 1:1 physical-size preview
- Windows-style `StretchDIBits` scaler (macOS `lp` may still scale inside the filter)
- No AirPrint warning
- NSPrintPanel is settings-only; the job is a second step

TargetPrint is the **Adobe Color Print Utility analogue**: decode TIFF with ImageIO, draw 1:1 in PostScript points with interpolation off, present `NSPrintPanel` as the actual print operation, inject ColorSync-off **and** vendor PPD keys into `NSPrintInfo`.

### Architecture (SPEC §2)

```
ICCery (Tauri)  --job /tmp/iccery_job_<uuid>.json  (fire-and-forget, do not wait)
        ▼
TargetPrint.app  (always NSApplication, never a CLI tool)
  main.swift → AppDelegate → PreviewWindowController
       TargetCanvasView (ImageIO, knowsPageRange/rectForPage)
       PrintEngine (NSPrintOperation + NSPrintInfo + ColorMatching)
       CUPSManager (libcups, AirPrint, vendor PPD)
```

### Invocation contract (SPEC §4, `main.swift`, `AppDelegate.consumeArguments`)

```
TargetPrint.app/Contents/MacOS/TargetPrint --job /tmp/iccery_job_<uuid>.json
TargetPrint --job=/path.json
TargetPrint --verbose --job …          # ~/Library/Logs/TargetPrint/TargetPrint.log
# or open a .targetjob / .json via file association (UTI com.iccery.targetjob)
```

Exit codes (`AppError.swift`): `0` ok/cancel, `1` invalid job, `2` unreadable TIFF, `3` CUPS, `4` fatal. Job JSON is **never deleted** by TargetPrint.

Mode B: no args / drop TIFFs / File→Open — inspector + Print….

`--job` presents `NSPrintPanel` immediately (`AppDelegate:32-33`, SPEC §4.5). Tauri must **not** `wait()`.

### JSON `TargetJob` v1 (SPEC §5, `TargetJob.swift`, `Resources/sample.targetjob`)

```json
{
  "version": 1,
  "jobTitle": "Epson_XP55_IlfordLustre_Target_P1-2",
  "files": ["/abs/page1.tif", "/abs/page2.tif"],
  "printSettings": {
    "printerName": "EPSON_XP_55_Series",
    "mediaSize": "A4",
    "mediaType": "PremiumGlossy",
    "paperSource": "Auto",
    "resolution": "5760x1440dpi",
    "printQuality": null,
    "scaling": 1.0,
    "centered": true,
    "forceUnmanagedColor": true
  },
  "uiPolicy": {
    "lockColorManagement": true,
    "allowBasicDriverChanges": true
  }
}
```

Required: `version==1`, `jobTitle`, non-empty `files`, `printSettings.{printerName,mediaSize,scaling,centered,forceUnmanagedColor}`, `uiPolicy.{lockColorManagement,allowBasicDriverChanges}`. Unknown keys ignored. `printQuality` is implemented in Swift beyond the spec sample.

### Geometry & pixel integrity (SPEC §6, §15)

- 72 pt = 1 in. **Never** `backingScaleFactor` (`Geometry.swift`).
- `physicalInches = pixels / dpi`; `pointSize = physical * 72 * scaling`.
- Papers: A4/A3/A5/Letter/Legal/Tabloid/4x6/5x7. Unknown names fall back to A4, with substring match for `A4.Borderless`.
- Destination origin rounded to 0.001 pt to avoid fractional-device resampling while staying inside G1 ±0.1 mm.
- ImageIO load: `kCGImageSourceShouldCache=true`, `ShouldAllowFloat=false`. DPI from `kCGImagePropertyDPIWidth/Height`, default 72.
- `TargetPage.makeUnmanagedDeviceRGB`: redraw into `CGColorSpaceCreateDeviceRGB()` with interpolation **none**, antialias **off**, `shouldInterpolate: false`. SPEC §6.3: do **not** `CGImageCreateCopyWithColorSpace` into a calibrated space.
- Print draw (`TargetCanvasView.drawPrintedPage`): `interpolationQuality = .none`, `setShouldAntialias(false)`, `setAllowsAntialiasing(false)`, `setShouldSmoothFonts(false)`, fill paper white, `context.draw(cgImage, in: dest)`. GState saved/restored so page N does not inherit page N-1's transform.
- `PixelIntegrity.scanVerticalSeam`: any pixel on a red\|green seam that is not exactly left or right fails P1 (interpolation/antialias detected).
- Pagination: `knowsPageRange` 1…N, `rectForPage` = paper size, empty header/footer.

### ColorSync disable in TargetPrint (SPEC §7) — **different keys from ICCery**

`ColorMatching.swift`:

| User mode | `PMColorMatchingMode` value |
|-----------|-----------------------------|
| Unmanaged (profiling default) | `"APCustomColorMatching"` |
| ColorSync | `"APColorSync"` |
| Driver / Vendor | `"APPrinterExtension"` |

Injected into:

- `printInfo.dictionary()["PMColorMatchingMode"]`
- `printInfo.dictionary()["PMCustomColorMatchingProfile"]` = `""` when unmanaged else `"System"`
- `printInfo.dictionary()["com.apple.print.PrintSettings.PMColorMatchingMode"]` (legacy)
- nested `com.apple.print.printSettings` dictionary, same keys

**This is not `AP_ApplicationColorMatching`.** TargetPrint talks to Quartz/`NSPrintOperation`. v1 ICCery talked to the CUPS `lp` ticket / `cgpdftoraster`; a rewrite that unifies them must keep both vocabularies or prove one is honored on both paths. **v2.0 (#201, D2) resolved this:** the Quartz vocabulary in this section is now live in ICCery proper — `ColorSyncSuppressor.applyQuartzMode` / `TicketWriteResolver` write `PMColorMatchingMode=APCustomColorMatching`, `PMCustomColorMatchingProfile=""`, the legacy `com.apple.print.PrintSettings.PMColorMatchingMode` and the nested `com.apple.print.printSettings` mirror **alongside** the locked AP_* keys on the single native spool path.

Panel policy (`ColorMatching.configurePanel`):

- Always: copies, page range, preview
- If `allowBasicDriverChanges`: paper size, orientation, scaling
- If `lockColorManagement`: `stripColorMatchingAccessories` — walk `panel.accessoryControllers`, remove any whose class/title/nib contains "color matching" / "colour matching" / "colormatch", requiring `NSPrintPanelAccessorizing`. Stripped twice (configure + immediately before `runModal`) because system accessories install lazily.

### CUPS / PPD (`CUPSManager.swift`, `Bridging-Header.h`)

Bridging header:

```objc
#import <cups/cups.h>
#import <cups/ppd.h>
static inline const char *TPCupsGetPPD(const char *name) {
    return cupsGetPPD(name);   // deprecated; Swift overlay marks cupsGetPPD unavailable
}
```

- `cupsGetDests` / `cupsFreeDests` / `cupsGetOption` for `printer-uri-supported`, `device-uri`, `printer-make-and-model`.
- `TPCupsGetPPD` → read ISO-Latin-1 → `unlink` the temp PPD.
- AirPrint (SPEC §10.2) if any of: URI `apple-airprint://`; PPD `*APAirPrint: True`; make Apple + model contains AirPrint; `ipps://` **and** PPD text contains `airprint`. Persistent warning badge; unmanaged color cannot be trusted. Tests in `AirPrintTests.swift`.
- Vendor bypass (SPEC §10.3) — **different keys from ICCery's lpoptions detector:**

| Vendor | TargetPrint keys | ICCery macOS `lpoptions`-detected keys (v1: `lp -o`) |
|--------|------------------|------------------------|
| Epson | `ColorModel=RGB`, `EPSONColorControls=Off` | `EPIJ_CMat=3` / `EPIJ_CCor=0` / `EpsonColorMode=Off` |
| Canon | `CNColorMatching=None` | `CNIJIntent2=4` / `CNIJIntent=4` |
| HP | `ColorModel=RGB`, `HPColorControl=Off` | (none auto) |
| Generic | any Color/Colour OpenUI choice in `{none,off,no,nocoloradjustment}` | `ColorCorrection=Uncorrected` / `StpColorCorrection=Uncorrected` |

A rewrite should apply **both** dictionaries (ICCery's empirically captured PDE keys **and** TargetPrint's SPEC keys).

Media/tray/quality discovery walks `*Keyword code/Title:` and `*OpenUI` translations (`media type`, `paper source`, `print quality`, …). Keywords tried:

- Media: `MediaType`, `CNIJMediaType`
- Tray: `InputSlot`, `EPIJ_FdSo`, `CNIJMediaSupply`
- Quality: `CNIJPrintQuality`, `EPIJ_Qual`, `cupsPrintQuality`, `PrintQuality`, `CNIJPrintMode2`, `Quality`, `StpQuality`

Canon quality is a triple (`CNIJPrintQuality` + `CNIJPrintMode2` + `CNIJPQualitySlider`) mapped in `PrintEngine.applyOptionalPPDKeys`.

PPD hex escapes (`<2F>` → `/`) decoded by `decodePPDString`.

### PrintEngine (`PrintEngine.swift`)

`makePrintInfo()`:

- `jobDisposition = .spool`
- margins 0, centering **off** (geometry is in the view), pagination `.clip`, `scalingFactor = 1.0`
- `NSPrinter(name: printerName)`
- paper size from `Geometry.paper(named:)`
- `ColorMatching.apply`
- `CUPSManager.namedQueue` → `vendorColorBypass` + optional media/tray/quality/resolution extras
- `canSpawnSeparateThread = false` on the operation
- `runModal(for: window, delegate:didRun:)` — exit code 0 on success **or** cancel (SPEC §4)

### How ICCery would invoke it (SPEC §16, `VENDOR.md`)

Not implemented in current ICCery Rust. Specified as:

```rust
let json = serde_json::to_string_pretty(&job)?;
let mut path = env::temp_dir();
path.push(format!("iccery_job_{}.json", uuid::Uuid::new_v4()));
fs::write(&path, json)?;

Command::new("/Applications/TargetPrint.app/Contents/MacOS/TargetPrint")
// or vendored: src-tauri/targetprint/macos-{x86_64,aarch64,universal}/TargetPrint.app/Contents/MacOS/TargetPrint
    .arg("--job")
    .arg(&path)
    .spawn()?;   // fire-and-forget — do not wait
```

CI publishes `vendor-iccery.zip` with `macos-x86_64` / `macos-aarch64` / `macos-universal` app bundles to drop into `src-tauri/targetprint/`.

Suggested ICCery integration (**superseded** — v2.0 took option 2's rendering model in-process instead; #201 adopted Quartz/`NSPrintOperation` spooling inside ICCery proper and removed `lp` entirely. The `--job` companion-app contract remains the v2.1 plan for `ICCeryPrintKit`, #16):

1. ~~Keep current `lp` path as the headless/fast path (and the only path on Linux).~~
2. On macOS, Preferences / Print can spawn TargetPrint with a `TargetJob` built from `PrintOptions` + TIFF list + `forceUnmanagedColor: true` + `lockColorManagement: true`.
3. Do not `CREATE_NO_WINDOW` (macOS); do not `wait()`. Cleanup of the JSON is ICCery's job after process exit, or leave in `/tmp` as an audit trail (SPEC §13).

### TargetPrint vs ICCery macOS — decision table for the rewrite

| Concern | ICCery `macos.rs` | TargetPrint | Rewrite recommendation |
|---------|-------------------|-------------|------------------------|
| Spool | `lp` TIFF | Quartz `NSPrintOperation` | Quartz `NSPrintOperation` — **adopted in v2.0 via #201** (`NativeTargetSpooler`; `lp` removed from the target-print path) |
| ColorSync ticket | `AP_ApplicationColorMatching` (+ dotted) | `PMColorMatchingMode=APCustomColorMatching` | Set **both** — **adopted in v2.0 via #201** (D2: the single native path carries AP_* and the Quartz §7 vocabulary) |
| Lock PDE UI | private `PMSessionSetColorMatchingMode*` SPI | strip Color Matching accessories | Use SPI **and** strip; accessories API misses driver PDEs (the #188 failure mode) |
| Canon off | `CNIJIntent2=4` | `CNColorMatching=None` | Apply both |
| Epson off | `EPIJ_CMat=3` / `EPIJ_CCor=0` | `EPSONColorControls=Off` + `ColorModel=RGB` | Apply both; prefer captured panel values |
| Geometry | none (filter decides) | 1:1 pt from DPI | 1:1 pt from DPI — **adopted in v2.0 via #201** (`TargetRasterLoader`/`TargetPageCanvasView`, docs/14 §6) |
| Interpolation | n/a (file passthrough) | explicitly disabled | Required for patch edges — **adopted in v2.0 via #201** (interpolation/antialias off in `TargetPageCanvasView.draw`) |
| AirPrint | none | detected + warned | Ported into ICCery — **adopted in v2.0 via #201/#202** (`lpstat -v` + PPD §10.2 rules, Stage 2 `airPrintWarningBadge`) |
| Linux | `-o raw` | n/a (macOS only) | Keep raw + PPD fallback |
| Windows | GDI ICM_OFF | n/a | Keep GDI; do not route through TargetPrint |

---

## Issue cross-reference

| # | Title | Print relevance |
|---|-------|-----------------|
| 25 | Raw OS Printing Engine | Parent feature. ACPU-equivalent, no `window.print()`. |
| 26 | Windows GDI/ICM | `SetICMMode`, `DMICMMETHOD_NONE`, BGR DIB, `StretchDIBits`. |
| 27 | macOS/Linux CUPS | Originally `-o raw`. macOS later diverged to AP_* (#92/#188). |
| 28 | UI + IPC | `get_printers`, printer `<select>`, Print Target button, toasts. |
| 34 | Driver properties, trays, orientation, auto-fit | Windows dialog + scaler; Unix lpoptions; `PrintOptions`. |
| 36 | DEVMODE not applied | Full buffer + `dmDriverExtra` retained into `CreateDCW`. |
| 46 | Console windows on Windows | `CREATE_NO_WINDOW` on Argyll spawn, **not** on print. |
| 48 | Hide PPD checkbox on Windows | `#cupsOptionsGroup.hidden`. |
| 50 | Stage 2 badge cleanup | Removed ACPU / auto-fit badges. |
| 67 | Consolidate print commands | `get_printers` / `print_target_native` only. |
| 68 | printtarg JSON manifest | Gallery + per-page print consume `event: manifest`. |
| 92 | macOS CUPS raw spooler | `macos.rs` created; ColorSync research. Milestone 9. |
| 127 | Fetch Argyll + NSIS USB | Instrument USB, not printer drivers. |
| 188 | Cannot disable Epson/Canon CM on macOS | Preferences was System Settings. Now NSPrintPanel + SPI + AP_* + PPD bypass + capture. |

---

## Files (absolute)

```
/tmp/ICCery/src-tauri/src/print/mod.rs
/tmp/ICCery/src-tauri/src/print/macos.rs
/tmp/ICCery/src-tauri/src/print/windows.rs
/tmp/ICCery/src-tauri/src/print/unix.rs
/tmp/ICCery/src-tauri/src/print/tests.rs
/tmp/ICCery/src-tauri/src/commands.rs          # get_printers, get_printer_capabilities,
                                               # show_printer_properties, print_target_native
/tmp/ICCery/src-tauri/src/lib.rs               # PrinterDevModeStore manage + command list
/tmp/ICCery/src-tauri/src/process_manager.rs   # CREATE_NO_WINDOW for Argyll
/tmp/ICCery/src-tauri/src/calibration.rs       # CREATE_NO_WINDOW for printcal
/tmp/ICCery/src-tauri/Cargo.toml               # objc2* / windows features
/tmp/ICCery/src-tauri/windows/hooks.nsh        # NSIS USB
/tmp/ICCery/src/js/printtarg.js
/tmp/ICCery/src/index.html                     # #rawPrintPanel
/tmp/ICCery/AGENTS.md                          # #188 contract
/tmp/ICCery-CPU/SPEC.md
/tmp/ICCery-CPU/VENDOR.md
/tmp/ICCery-CPU/Bridging-Header.h
/tmp/ICCery-CPU/Sources/main.swift
/tmp/ICCery-CPU/Sources/AppDelegate.swift
/tmp/ICCery-CPU/Sources/AppError.swift
/tmp/ICCery-CPU/Sources/Printing/ColorMatching.swift
/tmp/ICCery-CPU/Sources/Printing/PrintEngine.swift
/tmp/ICCery-CPU/Sources/Printing/CUPSManager.swift
/tmp/ICCery-CPU/Sources/Models/TargetJob.swift
/tmp/ICCery-CPU/Sources/Models/TargetPage.swift
/tmp/ICCery-CPU/Sources/Models/Geometry.swift
/tmp/ICCery-CPU/Sources/Models/PixelIntegrity.swift
/tmp/ICCery-CPU/Sources/Views/TargetCanvasView.swift
/tmp/ICCery-CPU/Sources/Controllers/PreviewWindowController.swift
```
