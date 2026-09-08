# 20 — CGATS dataset interop (#94, #211)

Native Rust parser `src-tauri/src/cgats.rs` plus frontend `cgats_interop.js`. Used to jump the wizard to Stage 4/5 from a lab/spectral measurement file that did not originate in this ICCery run.

## Commands

| Command | Role |
|---------|------|
| `select_dataset_file` | **Open** dialog: `*.ti3, *.txt, *.cgats, *.csv` |
| `import_measurement_dataset` | Parse + write canonical `.ti3` into cwd, then `wizardState.setTarget` |
| `export_measurement_dataset` | Write canonical `.ti3` / txt |
| `inspect_dataset_preview` | Preview rows for the CGATS viewer (`DatasetSummary`) |
| `select_existing_target` | Related: open `.ti1`/`.ti2` for resume, not CGATS |

#211: import used a **save** dialog and left wizard state uninitialised. Always `pick_file` (open), then `wizardState.setTarget(basename, cwd)`. Never `save` for import.

v0.8.3 also opens an existing `.ti3` in the viewer without re-importing.

## `CgatsDataset` model

```
file_type: "CGATS.17" | "CTI3" | "ISO28178" | "CSV"
originator, created, descriptor, target_instrument
illuminant, observer, measurement_condition
color_rep: Rgb | Cmyk | Lab | DeviceN(n)
fields: [{ name, field_type }]
samples: [{ sample_id, sample_loc, device_coords[], lab[3], xyz[3], spectral[] }]
spectral_range: { start_nm, end_nm, step_nm, bands[] }
```

`FieldType`: `Id`, `DeviceCoord(i)`, `LabL/A/B`, `XyzX/Y/Z`, `Spectral(nm)`, `Custom(name)`.

`DatasetSummary` (preview): `patch_count`, `color_space`, `has_spectral`, `has_lab`, `spectral_start/end`, `illuminant`, `sample_preview` (first N rows).

## Normalisation (`to_canonical_ti3`)

Must satisfy the Argyll C CGATS parser (strict):

- Emit `CTI3` / `CGATS.17` keywords Argyll expects (`NUMBER_OF_FIELDS`, `BEGIN_DATA_FORMAT`, `BEGIN_DATA`, `COLOR_REP`, `DEVICE_CLASS`, `TARGET_INSTRUMENT` when known)
- Device coordinates 0–255 → 0–100 if the column max is > 100
- Field aliases: `SAMPLE_ID` / `SAMPLE_LOC` / `LAB_L` `LAB_A` `LAB_B` / `XYZ_*` / `SPEC_*` / `RGB_*` / `CMYK_*`
- Synthesise `COLOR_REP` and `DEVICE_CLASS` if missing
- Drop rows with no device **and** no Lab/XYZ/spectral
- Preserve spectral bands if present so `colprof -f` FWA still has data

Imported datasets can jump to Stage 4 (profile from the set) or Stage 5 (verify an existing profile against the set). Stage 1–2 stay locked unless sibling `.ti1`/`.ti2` exist.

## Security

Never `innerHTML` dataset names or originator strings (#114 was presets; same rule applies). Paths from the open dialog are the only allowed sources — no URL fetch of CGATS.
