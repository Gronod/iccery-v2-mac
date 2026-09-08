# 09 — Stage 2: `printtarg` and target layout

UI: `#stage-2`. Action: `#btnCreateLayout` → `run_printtarg`.

## `PrinttargConfig` → argv (`build_printtarg_args`)

```
-v -u -i {instrument} -p {page} [-r | -R seed] [-d label] {-t|-T} {dpi} [-K|-I cal] basename
```

| UI | Field | Flag |
|----|-------|------|
| Instrument | `instrument` | `-i i1\|p3\|CM\|SS\|20\|22\|41\|51` |
| Page size | `page_size` | `-p A4\|A4R\|A3\|A2\|Letter\|LetterR\|Legal\|4x6\|11x17\|WWWxHHH` |
| Custom page | `customPageW/H` | `-p {w}x{h}` millimetres, ≥ 50 |
| Bit depth 8/16 | `bit_depth` | `-t` 8-bit TIFF / `-T` 16-bit |
| DPI | `dpi` | after `-t/-T`, default **300** |
| Layout order | `random_seed`, `no_randomize` | see below |
| Custom label | `custom_label` | `-d` string (fork #19 / ICCery #119) |
| Calibration | `calibration_file`, `calibration_embed_only` | `-K file.cal` apply, `-I file.cal` embed only |

Process id: `printtarg_${basename}`. **Always** passes fork `-u` so a JSON manifest can be parsed from stdout.

## Randomisation (#163)

Default **must** be deterministic (`-R 1`). A missing seed produced different TIFF layouts every run, breaking re-prints.

| `#printtargLayoutOrder` | Flags |
|-------------------------|-------|
| `deterministic` (default) | `-R 1` |
| `custom_seed` | `-R N` (N ≥ 1) |
| `raster` | `-r` (no randomize) — **not** `-R` |

Do **not** confuse printtarg `-r` (raster/no-random) with targen's `-r` (full-spread algorithm).

## Custom label (`-d`)

Assembled as:

```
ICCery - {basename} - {printer} - {ink} - {driverPaper} - {actualPaper} - DD/MM/YYYY HH:MM
```

Manual override via `#targetLabelPreview`. Fork `printtarg -d` is the **label**, not colour space (targen `-d`) and not iccgamut density (`iccgamut -d`).

## JSON manifest

Pretty-printed bare JSON on stdout (no prefix). Frontend `extractManifest` scans accumulated stdout. Typical fields: `pages[]` with TIFF paths, patch counts, instrument. Gallery renders each page via `read_tiff_preview_png` — **never** feed TIFF bytes to `<img>` (#58). Max edge 1200 px, Lanczos3, PNG base64.

## Colour-management warning

`#cmWarningBanner` tells the user to set the driver to "No Colour Adjustment" (Epson) / "Off (No Colour Adjustment)" (Canon). Native print then **also** forces bypass (see [11](11-print-macos.md) / [12](12-print-windows.md)).

## Raw print panel

After successful printtarg, `#rawPrintPanel` is shown. `#cupsOptionsGroup` (PPD uncorrected passthrough) is **hidden on Windows** (#48).
