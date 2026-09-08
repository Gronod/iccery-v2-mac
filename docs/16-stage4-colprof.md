# 16 — Stage 4: `colprof` (#7, #56, #176)

UI: `#stage-4`. Action: `#btnCreateProfile` → `run_colprof`.

## argv (`build_colprof_args`)

```
-v -a {algorithm} -q {quality} [-t intent] [-f [spec]] [-i illum] [-o obs] [-c inView] [-d outView] [-D desc] [-C copyright] basename
```

| UI | Field | Flag | Values |
|----|-------|------|--------|
| Algorithm | `algorithm` | `-a` | typically `l` (cLUT) |
| Quality | `quality` | `-q` | `l`/`m`/`h`/`u` |
| Intent | `intent` | `-t` | omitted if empty |
| FWA/OBA | `fwa` | `-f` | `none` → omit; empty → `-f` alone; else `-f D50\|D65\|path.sp` |
| Illuminant | `illuminant` | `-i` | override D50 |
| Observer | `observer` | `-o` | override 1931 2° |
| Input viewing | `input_viewing_cond` | `-c` | skip `none` |
| Output viewing | `output_viewing_cond` | `-d` | skip `none` |
| Description | `description` | `-D` | |
| Copyright | `copyright` | `-C` | |

Process id: `colprof_${basename}`.

Fork `colprof -u` JSON progress exists; **ICCery does not pass `-u`**. Spinner/stage label is driven from stdout text.

## FWA (#176)

`#colprofFwa`: D50 (recommended modern OBA paper / ISO 3664 M1), None, D65, Custom `.sp`. Custom browse uses `select_spectrum_file` (`*.sp`) — **not** `window.__TAURI__.dialog` (#210).

## IPC mismatch that broke Stage 4 (#56)

Early JS sent `{ basename, cwd }` while Rust expected `{ ti3_path, icc_path }`, and process ids disagreed so exit listeners never fired. **Config struct and process id must match on both sides.**

## After success

If Apply Calibration is on, run `applycal -a` on the new profile. Then enable `#btnGoToVerify`. Locate profile via `get_profile_path` / `resolve_profile_extension` (#69).
