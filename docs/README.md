# ICCery Rewrite Specification

**Product:** ICCery — printer ICC/ICM profiling frontend for ArgyllCMS  
**Source analysed:** [git.i3omb.com/gronod/ICCery](https://git.i3omb.com/gronod/ICCery) `v0.8.5` (`main`, merge #229)  
**Related:** [gronod/argyllcms](https://git.i3omb.com/gronod/argyllcms) (fork of ArgyllCMS 3.5.0), [gronod/ICCery-CPU](https://git.i3omb.com/gronod/ICCery-CPU) (`TargetPrint`)  
**Current stack (do not reuse):** Tauri v2 + Rust host + vanilla JS + Three.js  
**Licence:** ICCery GUI is proprietary EULA; ArgyllCMS binaries are AGPLv3 and **must remain subprocess-isolated** (stdin/stdout/stderr only — never link)

This folder is a complete functional specification of the existing application so it can be reimplemented in a different stack under the same name, using the same graphical assets (CMY ice-cream-cone wordmark).

## How to use these documents

Read in this order if you are implementing:

1. [01-overview.md](01-overview.md) — product, wizard, platforms
2. [02-architecture.md](02-architecture.md) — process isolation, modules, events
3. [03-ipc-and-process-manager.md](03-ipc-and-process-manager.md) — spawn / stdin / kill contract
4. [04-argyll-binaries.md](04-argyll-binaries.md) — **every** Argyll CLI invocation
5. [05-argyll-fork.md](05-argyll-fork.md) — `-u` JSON protocols, `instlist`, `-Y l`, Windows pipe fix
6. Wizard stages: [06](06-wizard-and-artefacts.md) → [07](07-stage0-calibration.md) → [08](08-stage1-targen.md) → [09](09-stage2-printtarg.md) → [15](15-stage3-chartread.md) → [16](16-stage4-colprof.md) → [17](17-stage5-verification.md)
7. Print (critical): [10](10-print-system.md) → [11-print-macos.md](11-print-macos.md) → [12](12-print-windows.md) → [13](13-print-linux.md) → [14](14-iccery-cpu-targetprint.md)
8. [18-gamut-viewer.md](18-gamut-viewer.md)
9. [21-ui-reference.md](21-ui-reference.md) — every control id
10. [24-issues-invariants.md](24-issues-invariants.md) — bugs that must not be repeated
11. [25-rewrite-notes.md](25-rewrite-notes.md) — stack-agnostic idiosyncrasies
12. [26-v2-mac-ticket-plan.md](26-v2-mac-ticket-plan.md) — **reviewed** Gitea milestone/ticket plan for the macOS SwiftUI rewrite (executable; supersedes the 2026-09-08 draft)

## Non-goals of the original (do not reintroduce)

- Display calibration wizard (`dispwin` / `dispread`) — won't-fix (#90)
- i18n (en/de/fr/ja) — won't-fix (#96); Argyll diagnostics are English-only
- Linking against Argyll as a library (AGPL contamination)

## Source map (legacy Tauri tree)

| Area | Path |
|------|------|
| Wizard HTML | `src/index.html` |
| Frontend modules | `src/js/*.js` |
| Styles | `src/styles/main.css` |
| Logo | `src/assets/ICCery-logo.svg` |
| Rust host | `src-tauri/src/` |
| Print backends | `src-tauri/src/print/{mod,macos,windows,unix}.rs` |
| Argyll sidecars | `src-tauri/argyll/<platform>/` (not in git; `npm run fetch-argyll`) |
| Bundled sRGB gamut | `src/assets/sRGB.gam` |

Analysed at 2026-09-08 from Gitea (`109` ICCery issues, `13` Argyll-fork issues, `3` ICCery-CPU issues) plus a full source read of `v0.8.5`.
