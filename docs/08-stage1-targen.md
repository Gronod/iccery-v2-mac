# 08 — Stage 1: `targen`

UI: `#stage-1`. Action: `#btnGenerate` → `run_targen`.

## `TargenConfig` → argv (`build_targen_args`)

Always starts `-v -d {2|4}`.

| UI | Config field | Flag | Notes |
|----|--------------|------|-------|
| Colour space RGB/CMYK | `colour_space` | `-d 2` / `-d 4` | 2 = Print RGB, 4 = CMYK |
| Patch count | `patch_count` or `total_patches` | `-f N` | omitted if 0. **Must honour UI** — #44 shipped 836 because `-f` was dropped |
| White patches | `white_patches` | `-e N` | |
| Black patches | `black_patches` | `-B N` | |
| Grey steps | `grey_steps` | `-g N` | if > 0 |
| Single channel steps | `single_channel_steps` | `-s N` | if > 0 |
| Neutral steps | `neutral_steps` | `-n N` | if > 0 |
| Neutral concentration | `neutral_concentration` | `-N x.xx` | only if not ≈ 0.50 |
| Preconditioning profile | `preconditioning_profile` | `-c path` | file filter **`.icc/.icm/.mpp`** not `.ti*` (#172) |
| OFPS high quality | `ofps_high_quality` | `-G` | |
| OFPS adaptation | `ofps_adaptation` | `-A x.xx` | |
| Full spread algorithm | `full_spread_algorithm` | `-t -r -R -q -Q -i -I` | default OFPS = no extra flag |
| Total ink limit | `total_ink_limit` | `-l N` | **CMYK only**, 1–400 |
| Dark emphasis | `dark_emphasis` | `-V x.xx` | if not ≈ 1.0 |
| Device power | `device_power` | `-p x.xx` | if not ≈ 1.0 and > 0 |
| Basename | `basename` | trailing arg | no extension |

Process id: `targen_${basename}`. Cwd: resolved working directory.

Fork `targen -u` JSON progress exists but **ICCery does not pass `-u`**.

## Patch-count presets

`#patchCountPreset`: 400 Draft, **800 Standard (default)**, 1500 Photo, 2500+ custom via `#patchCountCustom`.

## Extra actions

- `#btnOpenExisting` — resume `.ti1`/`.ti2` (#140). **Open** dialog (#103 used save by mistake).
- `#btn-import-dataset` — CGATS/ti3 import (#94). Open dialog, not save (#211).
- `#btnBrowse` — save `.ti1` location (`select_target_file`).
- `#btnToggleAllHelp` — help mode; tooltips must **not** reflow layout (#171) — use overlay positioning, not in-flow height.

## Advanced options

Collapsible `#targenAdvancedDetails`. Ink-limit group `#targenInkLimitGroup` hidden for RGB.
