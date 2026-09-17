# Issue #201 — Printer quality and media type ignored when printing target

> Analysis doc referenced by issue **[Bug/Critical] Printer quality and media
> type settings ignored when printing target — lp path missing PMPrintSettings
> ticket** (#201). Line numbers refer to `develop` @ `0513b27` (pre-M12 code,
> verified 2026-09-17). The fix landed on `milestone/m12-native-spool` — see
> "Resolution" below.

## 0. Lifecycle trace — what the code did (pre-#201, historical v1)

```
Stage2View "btnPrinterProperties"
  → PrintSessionViewModel.openPrinterPreferences()            :141
      → PrintPanelService.showProperties()                    :59
          → runNativePanel()                                  :85
              ① PMPrinterCreateFromPrinterID + PMSessionSetCurrentPMPrinter   :96–113
              ▸ applyInitialSelections (PMPrintSettingsSetValue ×4)           :216
              ▸ applyPaperPageFormat (PMPaper match → PMCopyPageFormat)       :258
              ②–⑤ ColorSyncSuppressor SPI / AP_* / bypass / mirror            :152–163
              NSPrintPanel.runModal("Use Settings")                           :173
              ⑥ PMPrintSettingsToOptions → CupsOptionsFilter → String         :185–191
      ✗ THE TICKET IS DISCARDED HERE — only the flattened `k=v` string survives
      → capturedCupsOptions[queue] = String                   :174

Stage2View "btnPrintAll"
  → PrintSessionViewModel.printAllPages(from:)                :205
      → spool(page, index:)                                   :263
          → CupsService.printTarget()            CupsService.swift:170
              → LpArgs.build()                   LpArgs.swift:42
              → ProcessManager.runCaptured("/usr/bin/lp", argv)
```

## Root causes (pre-#201, historical v1)

Two defects, both confirmed by reading the code:

### 1. Ticket loss

`ColorSyncSuppressor.captureOptions` (:133) was the only capture path. It
funneled the whole `PMPrintSettings` object through `PMPrintSettingsToOptions`
→ a space-separated `key=value` string, then `CupsOptionsFilter.filter`
**dropped every `com.apple.*` key** (`CupsOptionsFilter.swift:49`) — i.e. it
deliberately discarded `com.apple.print.PrintSettings`, the ticket the
Epson/Canon raster filter reads. `lp` cannot reconstruct it, so the driver
fell back to plain paper / normal quality.

### 2. Override inversion

`LpArgs.build` recorded every captured key in `addedKeys` (:67–73) and then
*suppressed* the explicit Stage 2 value when the key was already present —
media (:81), quality (:90), bypass (:102), orientation (:109), `PageSize`
(:117). A Stage 2 dropdown change after a panel capture was silently ignored.

### Dismissed hypothesis

**argv tokenisation is safe** — `ProcessManager.runCaptured` hands an argv
array to `Process`, never a shell. Space-containing `-o` values were
preserved; this was checked and dismissed in the issue investigation and
re-verified during the M12 audit.

## Locked decisions (D1–D13)

Decisions taken by the M12 megaplan; **locked — do not re-derive.**
(`lp`/`LpArgs` mentions in this table name the deleted historical v1 path.)

| # | Decision | Consequence |
|---|----------|-------------|
| D1 | Spooler lives in the **app target** (`Sources/ICCery/Print/`), not in `CupsService` | `ICCeryCore` stays AppKit-free (AGENTS §Package layout). `CupsService.printTarget` is **deleted**; `CupsService` keeps enumeration/capabilities/PPD only. The issue body's "in `CupsService`" is superseded — posted as errata on #201 |
| D2 | Write **both** ColorSync vocabularies on the native path | AP_* (locked) **and** Quartz `PMColorMatchingMode=APCustomColorMatching` + `PMCustomColorMatchingProfile=""` + legacy `com.apple.print.PrintSettings.PMColorMatchingMode` + the nested `com.apple.print.printSettings` mirror. AGENTS §"Private ColorSync SPI — never mix" is **amended**: with `lp` gone there is one path and it carries both dictionaries (docs/14 decision table, "Set both if using NSPrintOperation") |
| D3 | Ticket = `PMPrintSettings` **Data** + `PMPageFormat` **Data** + an `NSPrintInfo.dictionary()` plist fallback | `kPMDataFormatXMLDefault`. Restored via `PM*CreateWithDataRepresentation` → `PMCopy*` → `PMSessionValidate*` → `updateFromPM*`. Byte round-trip is unit-testable |
| D4 | Delete `lp`; **keep** `CupsParsers` + `CupsOptionsFilter` | Parsers still drive capabilities (#183/#180/#181), media/quality key detection, driver-bypass detection, and the panel→Stage-2 apply-back mirror (#186). Only `LpArgs` dies |
| D5 | Job granularity is **user-selectable**, default **one job per page** | New session-only `@Published var singleJobForAllPages = false`; Stage 2 checkbox `chkSingleSpoolJob`. Default preserves today's per-page notices and error attribution |
| D6 | **Stage 2 always wins** over the rehydrated ticket | Unconditional overwrite of paper / media / quality / orientation. Mitigation for vendor companion-key desync: only write when the value differs from the ticket's current value, and log both (R4) |
| D7 | Spool **silently** | `showsPrintPanel = false`, `showsProgressPanel = false`, `canSpawnSeparateThread = false`. Feedback stays on the existing `isPrinting` + `Notice`. No new system modal → XCUITest unaffected |
| D8 | Verification = **recorder seam + PDF harness** | DEBUG `RecordingTargetSpooler` writes resolved ticket lines to `ICCERY_TEST_SPOOL_LOG` (replaces `ICCERY_TEST_LP_ARGV`); a real `NSPrintOperation` with `jobDisposition = .save` produces a PDF for geometry assertions |
| D9 | Never scale; **warn + spool** | 1:1 always, anchored at the paper's top-left. `warn` when the DPI-derived size disagrees with the manifest `width_mm`/`height_mm` by >0.5 mm; warning `Notice` when the image exceeds the paper |
| D10 | Device colour spaces implemented **and verified** for 1/3/4 channels at 8 and 16 bpc | Re-tag the decoded `CGImage` into `DeviceGray`/`DeviceRGB`/`DeviceCMYK` reusing the source `dataProvider` — **no resample, no bit-depth change**. Hardware gate covers RGB-8, RGB-16, DeviceGray-8 and CMYK-16 |
| D11 | AirPrint detection + Stage 2 banner **in scope**, as its own issue | docs/14 §10.2 rules. Blocked-by #201 → filed as #202 |
| D12 | Extract a **shared** `PMTicketBridge` | Single `@MainActor enum` owning every `PM*` call, with one documented `PMRelease` rule. `PrintPanelService` migrates onto it |
| D13 | New milestone **M12 — Native print spool** | `milestone/m12-native-spool` from `develop`; #201 moves off the shipped M11 (id 34) |

## Resolution

Implemented on `milestone/m12-native-spool` (Phases 1–5, PRs #203–#207).
(`LpArgs`/`lp` references below name deleted historical v1 artefacts.)

- `PMTicketBridge` owns every `PM*` call; `PrintPanelService.showProperties`
  returns `PanelCaptureResult` carrying a `PrintTicket` (layer ⑦ serialise).
- `NativeTargetSpooler` rehydrates the ticket into a fresh `NSPrintInfo`
  (S1–S14, docs/11 §native spool) and spools a headless `NSPrintOperation`
  over `TargetPageCanvasView` — 1:1, top-left anchored, interpolation off.
- `TicketWriteResolver` replaces `LpArgs.build`: Stage 2 always wins (D6),
  both ColorSync vocabularies written (D2), no `raw` can ever appear.
- `LpArgs`, `CupsService.printTarget`, the `lp` fixture and
  `ICCERY_TEST_LP_ARGV` are deleted; `RecordingTargetSpooler` writes to
  `ICCERY_TEST_SPOOL_LOG` for tests (D8).
- AirPrint detection + Stage 2 warning badge shipped as #202 (D11).

## References

- `Sources/ICCery/Print/{PMTicketBridge,PrintTicket,NativeTargetSpooler,TicketWriteResolver,TargetRaster,TargetPageCanvasView}.swift`
- `Packages/ICCeryCore/Sources/ICCeryCore/Print/{CupsService,CupsParsers,CupsOptionsFilter,PrinterModels,ColorMatchingAttempts}.swift`
- `docs/11-print-macos.md` §ColorSync suppression — UI click to `NSPrintOperation`
- `docs/14-iccery-cpu-targetprint.md` §6–§7 (geometry + Quartz vocabulary)
- M12 megaplan (`plan-be303e6f3f5e89da`)
