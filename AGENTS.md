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
- `ICCery` — app target (SwiftUI shell). Also owns the native print stack in
  `Sources/ICCery/Print/`: `PMTicketBridge`, `PrintTicket`,
  `TicketWriteResolver`, `NativeTargetSpooler` (+ `RecordingTargetSpooler`),
  `TargetRaster`, `TargetPageCanvasView` (#201 D1 — AppKit/`NSPrintOperation`
  lives here, never in `ICCeryCore`).
- `ICCeryCore` — wizard state, ProcessManager, argv builders, settings, CGATS, ΔE₀₀ (no AppKit print panel; CUPS enumeration/parsers only).
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

## Print spool — native since v2.0 (#201); v1 `lp` path eradicated
Target printing is a headless `NSPrintOperation` via `NativeTargetSpooler`
(#201): restore the captured `PrintTicket`, apply `TicketWriteResolver`
(Stage 2 always wins, D6), draw 1:1 with interpolation off.
`lp` is eradicated from the target-print path (historical v1: `LpArgs`,
`CupsService.printTarget`, `ICCERY_TEST_LP_ARGV` all deleted).
`CupsParsers`/`CupsOptionsFilter` stay (D4): enumeration, capabilities,
media/quality/bypass key detection and the Stage 2 mirror.
UI-test seam: `ICCERY_TEST_SPOOL_LOG` — DEBUG `RecordingTargetSpooler`
appends one resolved-ticket line per page (D8).

## Versioning
`scripts/version.sh` is the single source: tag/describe → `ICCERY_RELEASE_TAG`
(About shows `tag (marketing)`), `MARKETING_VERSION` = strict `X.Y.Z`,
`CURRENT_PROJECT_VERSION` = `git rev-list --count HEAD` (#189).
`v*` tag builds hard-fail if tag's X.Y.Z ≠ `project.yml` MARKETING_VERSION —
bump `project.yml` on `develop` before tagging. CI needs `fetch-depth: 0`.

## Branching
`develop` ← `milestone/mN-<name>` ← `feat/<issue#>-<slug>`.
PRs via Gitea MCP. Every issue/PR: `Project/ICCery-v2` + `Feature/*` or `Bug/*` + `Priority/*`.

## Issue ticket style
- Title: `[Kind/Priority] short description` — e.g. `[Bug/Critical] …`, `[Feature/Medium] …`.
- Labels: `Kind/Bug` or `Kind/Feature` (also `Kind/Testing` for test work),
  one `Bug/<area>` or `Feature/<area>` (Architecture/Backend/UI/DevOps),
  one `Priority/*`, plus `Project/ICCery-v2`. Set the milestone when the work
  belongs to an active `mN` milestone.
- Bug bodies: `## Summary` → `## Root Cause Analysis` (file:line evidence;
  note checked-and-dismissed hypotheses) → `## Proposed Fix` (options or
  deterministic plan) → `## Acceptance Criteria` (checkbox list) →
  `## Dependencies` → `## References`.
- Feature bodies: same skeleton minus Root Cause; lead with Summary and a
  concrete implementation plan.
- Dependencies/blockers must **always** be recorded via the gitea MCP
  `issue_write` methods (`add_dependency`, `block_issue`; reads via
  `issue_read` `list_dependencies` / `list_blocks` — see "Gitea issue
  dependencies"), not just mentioned in the body. This is
  mandatory when issues share a milestone with an implementation order:
  wire up `add_dependency` (blocked-by) and `block_issue` (blocks) links so
  the order is machine-readable. The `## Dependencies` body section may
  still summarise them for readability, but the MCP links are authoritative.

## Verify
```
xcodebuild test -scheme ICCery -destination 'platform=macOS' ARCHS="$(uname -m)"
codesign -dvv <sidecar>
```
Universal (`ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO`) is still required for release verification / packaging.

## Private ColorSync SPI
2-arg `(PMPrintSession, CFStringRef) -> OSStatus`. Never pass integer `1`.
Modes: `AP_ApplicationColorMatching` then `ApplicationColorMatching`.
One spool path remains (#201 D2): write **both** vocabularies on the native
path — locked AP_* (`AP_ColorMatchingMode` + `AP.ColorMatchingMode` =
`AP_ApplicationColorMatching`) **and** the Quartz dictionary
(`PMColorMatchingMode=APCustomColorMatching`, `PMCustomColorMatchingProfile=""`,
legacy `com.apple.print.PrintSettings.PMColorMatchingMode`, nested
`com.apple.print.printSettings` mirror).

## Gitea issue dependencies
Use the `gitea` MCP (custom build with blocking support — verified working):

- `issue_write` methods:
  - `add_dependency` — `blocking_issue` blocks `issue_number`.
  - `remove_dependency` — removes `blocking_issue` from `issue_number`'s blockers.
  - `block_issue` / `unblock_issue` — `issue_number` blocks/unblocks `blocked_issue`.
- `issue_read` methods: `list_dependencies` (issues blocking N),
  `list_blocks` (issues N blocks).
- All issue numbers are *display numbers*, not db ids.
