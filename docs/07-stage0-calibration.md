# 07 — Stage 0: printer calibration (`printcal` / `applycal`) (#224)

Optional dashboard opened by **Calibrate Printer** (`#btnCalibratePrinter`). The 1–5 wizard is unchanged when skipped.

## Why `CAL_` prefix

Calibration charts use basename `CAL_<run>` so they never collide with profiling `.ti1/.ti2/.ti3`. `printtarg -K file.cal` is applied only to **profiling** layouts, never to the calibration chart itself.

## Flow

1. **Generate Calibration Target** → `targen` via `build_calibration_targen_args`
2. **Create Layout & Print** → existing Stage 2 printtarg + native print (same unmanaged path)
3. **Measure Chart** → existing Stage 3 chartread
4. **Compute Curves** → `printcal` (captured, not streamed)
5. Toggle **Apply Calibration** → subsequent profiling `printtarg -K` and post-`colprof` `applycal -a`

## `targen` for calibration wedges

```
-v -d {2|4} -s {steps} -g {steps} [-n {steps}] -e {white|4} [-l {tac}] -f 0 CAL_<basename>
```

- RGB: `-d 2`; CMYK: `-d 4`
- Steps clamped 11–51, default 21 (`#calSteps`)
- Neutral emphasis: `-n` same as steps
- CMYK ink-limit exploration: `-l` 200–400 (`#calInkExplore`, default 320)
- `-f 0` — no full-spread patches (wedges only)
- Default 4 white patches if unspecified

## `printcal`

```
-v -e [-I] [-z] [-a previous.cal] [-m TAC] [-xC pct]… -o out.cal CAL_basename
```

| Flag | Meaning |
|------|---------|
| `-e` | even (always passed) |
| `-I` | no ink limit |
| `-z` | verify |
| `-a` | previous `.cal` |
| `-m` | total ink limit |
| `-xC` / `-xM` / … | per-channel limit |
| `-o` | output `.cal` |

`.cal` overwrite requires Overwrite / Rename / Cancel (`#calCollisionDialog`). Never silently clobber.

## `applycal` (after Stage 4)

```
-v -a <cal> <input.icc> [output]
```

JS never sends `-u` (unapply). Fork `-u` on applycal is **not** JSON.

## Staleness

Warn if loaded `.cal` is older than `calibration_stale_days` (default 30) **or** stored printer name differs. CMYK Stage 1 shows "No calibration applied" reminder.

## UI

Channel-response SVG (`#calCurveSvg`): solid = post-linearization, dashed = identity. TAC card + per-channel limit editors. Recommended power shown for `targen -p`.
