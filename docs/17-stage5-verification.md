# 17 — Stage 5: verification, drift, install

UI: `#stage-5`. Actions: `#btnVerify` → `run_profcheck` then `extract_gamut`; `#btnInstallProfile` → `install_profile_to_system`.

## `profcheck` argv (`build_profcheck_args`)

```
-v -k -s -u {ti3} {icc}
```

`-u` is the fork JSON ΔE report. Also swap `.icc`/`.icm` if missing (#69). Process id: `profcheck_${ti3_path}` (note: contains path — listeners must use the same string).

## Parsing (`parseProfcheckReport`)

Prefer JSON summary (`avg`, `max`, `rms`, patch count). Fall back to legacy plain-text. If nothing parses, cards show `0.00` **and** a warning is appended to the process log (#179) — never silently zero.

## Verification bands (#95) — **not** the Stage 3 swatch thresholds

Stored on each `VerificationRecord.status`:

| avg ΔE₀₀ | Status | Badge |
|----------|--------|-------|
| < 1.0 | Excellent | `badge-excellent` |
| < 2.0 | Good | `badge-good` |
| < 3.5 | Acceptable | `badge-acceptable` |
| ≥ 3.5 | Warning | `badge-poor` |

Do **not** reuse `delta_e_good_max` / `delta_e_warning_max` (those are live swatch lights, defaults 2.0 / 5.0).

## History store (`quality_store.rs`)

Path: app data `verification_history.json`.

```
id: vr-<epoch_millis>-<seq>
profile_name, printer_name (wizardState.printerName or "Unknown")
avg_de, max_de, rms_de, patch_count, status, timestamp ISO-8601 UTC
```

Capacity **1000** (README; some older comments said 500). Evict oldest.

**Atomic write (#213):** write `.tmp` then `rename`. Non-atomic writes corrupted history on crash.

Serde: nested structs `snake_case`; Tauri command **arguments** `camelCase` (`savePath`, `record`, `profileName`).

## Drift UI

- SVG dual-series trend with shaded ICCery bands
- Consecutive-breach alert: ≥ 2 consecutive runs with status Warning, on **distinct calendar days** or **≥ 1 hour apart**
- Printer filter `#driftPrinterFilter`
- CSV export RFC-4180 (`export_verification_history_csv`)
- Clear history command

## `iccgamut`

```
-v -d 10 {resolved_profile}
```

`-d 10` is **surface density**, not a directory (#112). Never pass `-d 50.0` as a folder. Cwd = profile parent. Output `{stem}.gam` next to the profile.

See [18](18-gamut-viewer.md).

## Install profile (#223)

See [19](19-profile-install.md). Never move the working-directory artefact.
