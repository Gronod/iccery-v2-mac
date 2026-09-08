# 06 — Wizard, artefact gating, resume

## Stages

| # | DOM | Unlocked when |
|---|-----|----------------|
| 0 | `#stage-cal` | Always (optional, not in stepper) |
| 1 | `#stage-1` | Always |
| 2 | `#stage-2` | `{basename}.ti1` exists |
| 3 | `#stage-3` | `.ti1` **and** `.ti2` |
| 4 | `#stage-4` | `.ti3` exists (imported datasets may skip 1–2) |
| 5 | `#stage-5` | `.ti3` **and** `.icc`/`.icm` |

`verify_stage_artefacts(cwd, basename)` returns `{ stage1_complete, stage2_complete, stage3_complete, stage4_complete, profile_path }`.

Stage 4 is **not** unlocked by `.ti2`. Multi-pass averaging **deletes** the canonical `.ti3` after each snapshot (`snapshot_ti3`) so Stage 4 stays locked until Finish (#109, #110).

## `wizardState` fields

| Field | Role |
|-------|------|
| `currentStage` | 0–5 |
| `basename` | run name without extension |
| `cwd` | working directory |
| `printerName` | last spooled printer (drift history) |
| `sessionMode` | `"profile"` (extensible) |
| `profileBasename` | may differ after import |
| `noticeTimer` | banner auto-hide |

`setTarget(basename, cwd)` updates gating. `navigateToStage(n)` refuses locked stages with a warning banner. Window `focus` re-runs `updateGating` (user may have deleted files in Finder/Explorer) (#151).

## Resume from existing target (#140)

Stage 1 **Open Existing** (`select_existing_target`) filters `.ti1`/`.ti2`. `parse_ti2_header` reads `TARGET_INSTRUMENT`, `NUMBER_OF_SETS`, `NUMBER_OF_PAGES`, sibling `.ti1` presence. If `.ti2` exists, Stage 3 banner shows "Resumed from .ti2".

CGATS import (#94, #211) can jump to Stage 4/5 with a synthesised `.ti3` — must use an **open** dialog, never save (#211).

## Empty cwd (#59)

Never spawn with `cwd: ""`. Initialize from `get_default_working_dir` (Documents → Home → app data). Disable Generate until basename **and** directory are set. Display path in `#selectedPathDisplay`.

## Profile extension (#69)

`resolve_profile_extension`: if only `.icm` exists, use it; else if `.icc` exists, use it; else default `.icm` on Windows, `.icc` elsewhere. `profcheck` and `iccgamut` also swap extension if the requested path is missing.

## No `"test_target"` fallbacks (#60)

A rewrite must not invent default basenames. Later stages stay inert until `wizardState.basename` is set from a real artefact.
