# 22 — Settings and presets

Persisted at `{app_data}/settings.json` via `load_settings` / `save_settings`. Invalid JSON loads `AppSettings::default()`. `save_settings` calls `validate()` then writes pretty JSON and **immediately** applies `log::set_max_level`.

## `AppSettings` (`settings.rs`)

| Field | Default | Notes |
|-------|---------|-------|
| `argyll_binary_dir` | `null` | Overrides bundled sidecars. `resolve_binary` checks this first. |
| `default_instrument` | `null` | Stored; seeds the Spot Read instrument picker when that instrument is present (#148). **Never** written into `printtarg -i` or `targen` argv. Stage 2 `#instrumentSelect` remains the printtarg instrument. |
| `log_level` | `null` | `error` / `warn` / `info` / `debug` / `trace`. `null` → Debug in debug builds, Info in release. Applied at startup **and** on save (#158). |
| `delta_e_good_max` | `2.0` | Stage 3 swatch traffic-light "Good". Must be ≥ 0. |
| `delta_e_warning_max` | `5.0` | Stage 3 "Warning" band. Must be **strictly greater** than good. |
| `custom_presets` | `[]` | User presets; built-ins are **not** stored here. |
| `enable_i1pro2_leds` | `false` | Adds `chartread -Y l`. Default off so stock Argyll still runs. |
| `calibration_stale_days` | `30` | Stage 0 / Stage 1 reminder. |
| `default_install_location` | `"user"` | `"user"` \| `"system"` for Stage 5. |
| `ask_before_overwrite_profile` | `true` | |
| `open_color_panel_after_install` | `false` | |

Validation error strings (surface in `#deltaEThresholdError`):

- `"ΔE thresholds cannot be negative."`
- `"Good ΔE threshold must be strictly less than the warning threshold."`

Saving dispatches a DOM `settings-saved` event so the live swatch grid reclassifies without a re-read.

Settings dialog ids: `argyll_binary_dir`, `default_instrument`, `enable_i1pro2_leds`, `deltaEGoodMax`, `deltaEWarningMax`, `deltaEThresholdError`, `calibrationStaleDays`, `defaultInstallLocation`, `askBeforeOverwriteProfile`, `openColorPanelAfterInstall`, `logLevelSelect`, `btnOpenLogFolder`, `btnCopyLogPath`, `btnCopyLogExcerpt`, `logPathDisplay`, `saveSettingsBtn`, `closeSettingsBtn`.

Log helpers: `get_log_path`, `get_recent_log_excerpt`, `open_log_dir`.

## `ProfilingPreset`

Every field is optional-defaulted with `#[serde(default)]` except the required identity / Stage 1–2 core. `applyPreset` **must** set TIFF DPI (#113) — a historical bug left `#tiffDpi` at 300 when loading the 150 dpi draft preset.

| Field | Type | Stage |
|-------|------|-------|
| `id`, `name`, `description` | string | identity. Names/descriptions go through `textContent`, never `innerHTML` (#114 XSS) |
| `colour_space` | `"rgb"` \| `"cmyk"` | 1 |
| `patch_count`, `white_patches`, `black_patches` | u32 | 1 |
| `grey_steps`, `single_channel_steps`, `neutral_steps` | Option\<u32\> | 1 advanced |
| `preconditioning_profile` | Option\<path\> | 1 `-c` |
| `neutral_concentration` | Option\<f64\> | 1 `-N` |
| `ofps_high_quality` | Option\<bool\> | 1 `-G` |
| `ofps_adaptation` | Option\<f64\> | 1 `-A` |
| `full_spread_algorithm` | Option\<string\> | 1 `-t/-r/-R/-q/-Q/-i/-I` |
| `total_ink_limit` | Option\<u32\> | 1 `-l` CMYK |
| `dark_emphasis`, `device_power` | Option\<f64\> | 1 `-V` / `-p` |
| `instrument`, `page_size`, `bit_depth`, `dpi` | | 2 |
| `random_seed`, `no_randomize` | | 2 `#printtargLayoutOrder` |
| `calibration_file`, `apply_calibration` | | 0 / 2 `-K` |
| `colprof_algorithm`, `colprof_quality`, `colprof_intent` | | 4 |
| `colprof_fwa`, `colprof_illuminant`, `colprof_observer` | | 4 |
| `colprof_input_viewing_cond`, `colprof_output_viewing_cond` | | 4 |

## Built-in presets (`get_default_presets`)

Built-ins cannot be deleted. Custom presets overlay by `id`. Import/export is JSON via `export_preset_json` / `import_preset_json` with schema validation (unknown keys ignored via serde default; missing required fields fail).

| id | Name | Space | Patches | Page | Bit | DPI | Quality | Extra |
|----|------|-------|---------|------|-----|-----|---------|-------|
| `preset-std-rgb` | Standard RGB Photo (800 patches) | rgb | 800, white 4 | A4 | 8 | 300 | `m` | FWA D50, seed 1, instrument i1, alg `l` |
| `preset-hq-cmyk` | High-Gamut CMYK Proofing (1500 patches) | cmyk | 1500, black 8 | A3 | 16 | 300 | `h` | ink limit 320, FWA D50, seed 1 |
| `preset-draft-rgb` | Fast RGB Draft (400 patches) | rgb | 400 | A4 | 8 | **150** | `l` | FWA D50, seed 1 |
| `preset-ultra-rgb` | Ultra Precision RGB (2500 patches) | rgb | 2500, white 6, black 6 | A3 | 16 | 300 | `u` | `ofps_high_quality=true` (`-G`), FWA D50, seed 1 |

All four: `instrument: "i1"`, `colprof_algorithm: "l"`, `random_seed: 1`, `no_randomize: false`, `colprof_fwa: "D50"`.

UI: `#presetSelect`, `#btnSavePresetModal` → `#savePresetDialog` (`savePresetName`, `savePresetDesc`, `btnConfirmSavePreset`), `#btnOpenPresetsDialog` → `#managePresetsDialog` (`managePresetsList`, `btnExportActivePreset`, `btnImportPreset`).

## Media library (`media_library.json`)

Persisted at `{app_data}/media_library.json` — a sibling of `settings.json`, never a field inside it (issue #146). A `MediaRecipe` binds a CUPS queue + paper + ink set + optional `.cal` to a `ProfilingPreset`. Cap: 200 entries; the 201st is refused with an error, never silently evicted. Corrupt JSON → keep the file, load `[]`, persistent warning banner.

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | `recipe-<uuid>`, never user-typed |
| `name`, `notes` | string | Rendered through `Text` only (#114) |
| `printer_id` | string | CUPS queue id (`lpstat -e` name) |
| `printer_display_name` | string | Human label; applied to `wizard.printerName` |
| `paper_name`, `ink_set` | string | Library metadata only — never written to targen flags |
| `driver_media_type` | string? | Last captured CUPS `media_type` (read-only) |
| `colour_space` | `"rgb"` \| `"cmyk"` | Must match the bound preset |
| `preset_id` | string | `ProfilingPreset.id` (built-in or custom) |
| `calibration_url` | string? | Absolute `.cal` path, stored verbatim |
| `apply_calibration` | bool | Forced off for `CAL_` stems or missing files |
| `created`, `updated` | iso8601 | |

Apply path: recipe → `applyPreset` (#82 mapping, no second Stage 1 form) → queue re-enumerated (`lpstat -e`) → `printer_id` absent from a non-empty list warns "not installed" and leaves the queue untouched; an empty list is indeterminate and never flags. `CAL_` bound cal **or** a live `CAL_` wizard basename forces `applyCalibration` off — `printtarg -K` can never see a `CAL_` file (literal refusal; escape hatch is rename + re-capture). Staleness: `.printer` = absent from enumerated queues; `.calibration` = bound cal `CREATED + calibration_stale_days < now`.

Capture with no preset selected auto-snapshots the live form as a `custom-` preset and binds to it. UI: `#mediaSelect` (immediate apply, `#presetSelect`-style), `#btnMediaLibraryCapture` → `#saveMediaRecipeDialog`, `#btnMediaLibraryManage` → `#manageMediaDialog` (`mediaLibraryList`, `mediaRow-{id}`, `btnMediaLibraryApply-{id}`, `btnMediaLibraryDelete-{id}`), stale badge `#mediaRecipeStale`.
