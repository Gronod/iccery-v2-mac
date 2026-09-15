# AGENTS.md — ICCery v2 Mac

## Product
Native macOS printer ICC/ICM profiling frontend. Drives the Gronod ArgyllCMS 3.5.0 fork as AGPL-isolated subprocesses. Spec snapshot lives in `docs/` (chapters 01–25). Ticket plan: `BUILD-PLAN.md`.

## Stack
- SwiftUI (`@Observable`, `@MainActor` view models) + AppKit for printing / panels / file dialogs.
- Minimum macOS **14.0**. Universal `arm64` + `x86_64`.
- Bundle id **`com.gronod.iccery2`**. Product name ICCery.
- App Sandbox **OFF**. Hardened Runtime **ON**. Entitlements in `ICCery.entitlements`.
- No Tauri, no Rust host, no WKWebView, no Three.js.

## Package layout
- `ICCery` — app target (SwiftUI shell).
- `ICCeryCore` — wizard state, ProcessManager, argv builders, settings, CGATS, ΔE₀₀ (no AppKit print panel).
- `ICCeryPrintKit` — v2.1 only (issue 16). Zero deps on wizard types.

## AGPL boundary
Never link Argyll. Spawn only.
- Streaming: `ProcessManager` actor (`targen`, `printtarg`, `chartread`, `average`, `colprof`, `profcheck`, `iccgamut`, `instlist`).
- Captured: `runCaptured` (`printcal`, `applycal` only).
Both paths set `ARGYLL_NOT_INTERACTIVE=1`. Never search `$PATH` for binaries.

## Concurrency
No blocking subprocess I/O on `@MainActor`.
Do not hop to main per stdout line (colprof emits thousands of `.`).
Stdin handle is independent of wait (#84). Process ids are exclusive leases (#116).
`killAll` on `NSApplication.willTerminate` and last-window close (#147, #149).
XY cancel: send `q\n`, wait ~500 ms, then kill.

## Argyll flag discipline
See `docs/25-rewrite-notes.md` and `docs/04-argyll-binaries.md` §15.
`-d` / `-r` / `-R` / `-u` / `-Y` / `-c` mean different things per tool.
v2.0 `-u` policy: printtarg + chartread + profcheck only.

## Files
Artefact gating on disk. No placeholder basenames (#60).
Empty cwd illegal (#59). Atomic writes = `.tmp` + rename (#213).
User-supplied strings via SwiftUI `Text` only (#114).
TIFF never rendered directly — host-side PNG preview (#58).

## Versioning
`scripts/version.sh` is the single source: tag/describe → `ICCERY_RELEASE_TAG`
(About shows `tag (marketing)`), `MARKETING_VERSION` = strict `X.Y.Z`,
`CURRENT_PROJECT_VERSION` = `git rev-list --count HEAD` (#189).
`v*` tag builds hard-fail if tag's X.Y.Z ≠ `project.yml` MARKETING_VERSION —
bump `project.yml` on `develop` before tagging. CI needs `fetch-depth: 0`.

## Branching
`develop` ← `milestone/mN-<name>` ← `feat/<issue#>-<slug>`.
PRs via Gitea MCP. Every issue/PR: `Project/ICCery-v2` + `Feature/*` or `Bug/*` + `Priority/*`.

## Verify
```
xcodebuild test -scheme ICCery -destination 'platform=macOS' ARCHS="$(uname -m)"
codesign -dvv <sidecar>
```
Universal (`ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO`) is still required for release verification / packaging.

## Private ColorSync SPI
2-arg `(PMPrintSession, CFStringRef) -> OSStatus`. Never pass integer `1`.
Modes: `AP_ApplicationColorMatching` then `ApplicationColorMatching`.
`lp` path and Quartz/`ICCeryPrintKit` path use **different** ColorSync dictionaries. Never mix.

## Gitea issue dependencies
Use the `gitea` MCP (custom build with blocking support — verified working):

- `issue_write` methods:
  - `add_dependency` — `blocking_issue` blocks `issue_number`.
  - `remove_dependency` — removes `blocking_issue` from `issue_number`'s blockers.
  - `block_issue` / `unblock_issue` — `issue_number` blocks/unblocks `blocked_issue`.
- `issue_read` methods: `list_dependencies` (issues blocking N),
  `list_blocks` (issues N blocks).
- All issue numbers are *display numbers*, not db ids.
