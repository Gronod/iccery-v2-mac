# 19 — System profile installation (#223)

Command: `install_profile_to_system(profile_path, options) → InstallResult`.

**Copies** (never moves, never deletes) the working `.icc`/`.icm` into the OS colour store. The wizard artefact in `cwd` must remain so Stage 5 / drift / re-install still work.

Also: `get_profile_install_dir(prefer_system_wide) → path` so the UI can preview the destination.

## `InstallOptions`

| Field | Default | Meaning |
|-------|---------|---------|
| `force_overwrite` | false | Treat as overwrite regardless of `collision_policy` |
| `prefer_system_wide` | false | user dir vs system dir |
| `register_with_os` | true | ColorSync / ICM / colord after copy |
| `collision_policy` | `"cancel"` | `overwrite` \| `rename` \| `cancel` |
| `open_color_panel` | false | open OS colour UI after success |
| `calibration_note` | null | echoed back in the result for the toast if applycal embedded a `.cal` |

## `InstallResult`

| Field | Meaning |
|-------|---------|
| `dest_path` | Final file written |
| `registered` | OS registration attempted and reported success |
| `overwritten` | Collision resolved by overwrite |
| `renamed` | Collision resolved by timestamp suffix |
| `opened_panel` | Colour UI launched |
| `message` | Human status for the banner |
| `calibration_note` | Pass-through |

## Destinations

| OS | User | System | On-disk extension |
|----|------|--------|-------------------|
| Windows | `%USERPROFILE%\AppData\Local\Microsoft\Windows\Color` | `%WINDIR%\System32\spool\drivers\color` | always `.icm` (`profile_extension_for_os`) |
| macOS | `~/Library/ColorSync/Profiles` | `/Library/ColorSync/Profiles` | always `.icc` |
| Linux | `~/.local/share/icc` | `/usr/share/color/icc` | always `.icc` |

The **source** may be `.icc` or `.icm`; the **destination filename** is `{stem}.{os_ext}`. Stem is rejected if it contains `..`, `/`, or `\`.

System-wide paths need elevation. `permission_message` must mention UAC / admin / sudo, not a generic I/O failure.

## Collision + atomic copy

`resolve_destination`:

- missing → write that name
- exists + overwrite / `force_overwrite` → same path, `overwritten=true`
- exists + rename → `{stem}-{unix_epoch}.{ext}` (`timestamped_filename`)
- exists + cancel → `Err("A profile named {filename} already exists at … Choose Overwrite, Rename, or Cancel.")`

Copy is atomic: write `{dest}.iccery-install.tmp` then `rename`. On rename failure, delete the tmp. Create parent dirs as needed.

## Source verification (`verify_source_profile`)

- Path is a file
- Extension `icc` or `icm` (case-insensitive)
- Size ≥ **128** bytes (ICC header)

## OS registration (`register_with_os=true`)

| OS | Mechanism |
|----|-----------|
| Windows | Copy into the Color folder is enough for ICM to pick it up; optional `InstallColorProfileW` when linked. Do not call `SetDeviceGammaRamp`. |
| macOS | File in ColorSync folder is sufficient. Optional open ColorSync Utility (`open -a "ColorSync Utility"`) when `open_color_panel`. |
| Linux | `colormgr import-profile` when `colormgr` exists on PATH; ignore if missing. Optional `open_color_panel` → GNOME Color / `colormgr` GUI if present. |

Never register a path that failed to copy.

## UI

`#btnInstallProfile` → collision dialog `#profileInstallCollisionDialog` (`profileInstallCollisionMessage`, `profileOverwriteBtn`, `profileRenameBtn`, `profileCancelCollisionBtn`) matching the calibration collision pattern.

Settings: `default_install_location` `user`\|`system`, `ask_before_overwrite_profile`, `open_color_panel_after_install`.
