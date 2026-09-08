# 15 — Stage 3: `chartread`, averaging, swatch grid

UI: `#stage-3`. Action: `#btnStartRead` → `run_chartread`.

## argv (`build_chartread_args`)

```
-v -u [-c port] [-Y l] basename
```

| Source | Flag |
|--------|------|
| always | `-v -u` |
| `#chartreadInstrumentSelect` value | `-c port` if non-empty **and not `"1"`** (#111) |
| Settings `enable_i1pro2_leds` | `-Y l` (default **off** for stock-Argyll compatibility) (#204) |

If `enable_i1pro2_leds` is omitted in the config, backend loads it from settings.

Process id: `chartread_${basename}`.

**Do not pass instlist device index as `-c`.** `instlist.port` is already the 1-based comm port. Port `1` means "default" — omit `-c` (#111).

## `instlist`

`detect_instruments` spawns `instlist` with **no args**, id `"instlist"`, cwd inherited. Fork emits JSON:

```json
{ "devices": [ { "name": "...", "type": "...", "port": 1, ... } ] }
```

Frontend prefers JSON; falls back to regex `^(\d+)[\s:=]+'?([^'\n]+)'?(?:\s+on\s+'?([^'\n]+)'?)?`. XY label if name/type matches `/spectro\s?scan|i1io/i` (`data-xy="1"`).

## State machine

`STATE`: `IDLE`, `CALIBRATING`, `AWAITING_STRIP`, `READING`, `ALL_STRIPS_READ`, `WARNING`, `PROMPT_CONTINUE`, `TABLE_PLACE_SHEET`, `TABLE_ALIGN`, `ERROR`, `FINISHED`.

Classifier is a **pure function** (`classifyChartreadLine`) with 39 tests. Order of matchers matters — see [05](05-argyll-fork.md) §12.6.

XY two-line prompts: line 1 `locate patch A1 with the sight,` then line 2 `then hit return to continue`. While in `TABLE_PLACE_SHEET` or `TABLE_ALIGN`, continuation lines **stay sticky** in that state (#93).

`Please remove last sheet from table` is info-only (`isRemoveSheetNotice`); do not prompt.

Cancel on XY: send `q\n` then kill so the head parks.

## Averaging (#87, bugs #109/#110)

Each completed pass: `snapshot_ti3` copies `{basename}.ti3` → `{basename}_pass{N}.ti3` and **deletes** the canonical file. Stage 4 stays locked. Finish: `run_average -v pass1 pass2 … output.ti3` then `promote_ti3` if needed.

Do **not** overwrite the same `.ti3` in place (#109). Do **not** unlock Stage 4 after the first pass (#110).

## Swatch grid (#6, #178)

Listens `process:json_row`. Each patch is a 135° diagonal split: **top-left intended**, **bottom-right measured**.

`is_pad` spacers are skipped **only** when there is no measurement **and** device values are all zero. White reference patches (`-e`) may be flagged `is_pad` but have valid Lab — **render them** (#178).

Row order A→Z, patches 1→N left-to-right / top-to-bottom to match printtarg.

ΔE₀₀ from `delta_e.js` (`computeDeltaE00`). Traffic lights from settings:

- `< delta_e_good_max` (default 2.0) Good
- `< delta_e_warning_max` (default 5.0) Warning
- else Bad

`settings-saved` reclassifies live swatches. Thresholds must be ≥ 0 and `good < warning`.

## i1Pro 2 LEDs (#204)

Fork `-Y l` (not the `-L` from the original ticket). Silent no-op on instruments without `inst_stat_leds`.

| LED | Meaning |
|-----|---------|
| Flashing white | awaiting white-tile calibration |
| Flashing blue | ready for strip |
| Flashing red | misread |
| Flashing green | capture OK |

If an unpatched binary rejects `-Y l`, capture last stderr line and expand Process Output.

## Interactive buttons vs real keys

See [05](05-argyll-fork.md) §12. Real strip-mode keys are `f/b/n/d/q`, Space, Return, `y/n`. UI labels "Skip" / "Undo" send `s\n` / `u\n` which the **mock** understands; upstream strip mode treats unknown letters as trigger. Preserve current UI behaviour or document a protocol change — do not silently change what bytes are sent without updating tests.
