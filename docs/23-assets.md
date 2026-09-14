# 23 — Graphical assets

Reuse these in the rewrite. Do not replace the cone.

## Wordmark — `src/assets/ICCery-logo.svg`

ViewBox `0 0 480 160`.

- Waffle cone path `M 50 82 L 110 82 L 80 142 Z`, fill `#FAD7A1`, stroke `#E59866`, clipped waffle grid.
- Scoops: C `#00BCEB` at (63,72) r=22; M `#EC008C` at (97,72); Y `#FFED00` at (80,48); white stroke 2.5; highlight dots.
- K cherry: stem + circle `#1E293B` at (80,24) r=7.
- Wordmark: `ICC` white, `ery` linear gradient `#00AEEF` → `#0066CC`, weight 800, size 58, x=140 y=105.

Header usage: height `4.42rem`, max-width 175px, object-position left.

## App icon — `src/assets/app-icon.svg`

Cone-only mark for window/taskbar. Raster set:

- `src-tauri/icons/32x32.png`, `64x64.png`, `128x128.png`, `128x128@2x.png`
- `icon.icns`, `icon.ico`, `icon.png`
- Store / Android / iOS variants under `icons/` (legacy Tauri generator output; rewrite may subset)

## Installer chrome

| File | Use |
|------|-----|
| `Resources/dmg-background.png` (+ `@2x`; source `brand/dmg-background.svg`) | macOS DMG window. `scripts/package-release.sh` builds a HiDPI TIFF and passes it to `dmgbuild==1.6.7` from `build/.venv-dmgbuild` (created by `INSTALL_DMGBUILD=1 scripts/ensure-host-tools.sh`). Monterey Python 3.9 needs `PIP_IGNORE_REQUIRES_PYTHON=1` or pip will keep 1.6.5. Missing art is a hard fail (#95, #189). |
| `icons/wix-banner.bmp`, `wix-dialog.bmp` | MSI |
| `icons/nsis-header.bmp`, `nsis-sidebar.bmp` | NSIS |

## Gamut reference

- **Ship `src/assets/sRGB.gam`** — real Argyll sRGB gamut used by the viewer.
- `src-tauri/argyll/reference_gamuts/sRGB.gam` is an **8-cusp stub**. Do not use it as the overlay (#185 notes / gamut rewrite notes).

## Third-party JS (legacy)

- `three.min.js` r128 via script tag
- `OrbitControls.js`, `CSS2DRenderer.js` IIFE attaching to `THREE`
- `vendor/quickhull.js` — used when `.gam` has vertices but no faces

A rewrite may use any WebGL engine; keep Lab mapping `X=a* Y=L* Z=b*` and CSS2D axis labels.

## NSIS USB extras

`windows/hooks.nsh` offers Argyll USB instrument driver install when elevated, and maps missing user-shell-folder drive letters in the elevated session (network home drives) to avoid "Invalid Drive". Preserve the driver-offer behaviour; the DOS-device mapping is a Windows installer idiosyncrasy.
