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

## Branching
`develop` ← `milestone/mN-<name>` ← `feat/<issue#>-<slug>`.
PRs via Gitea MCP. Every issue/PR: `Project/ICCery-v2` + `Feature/*` or `Bug/*` + `Priority/*`.

## Verify
```
xcodebuild test -scheme ICCery -destination 'platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
codesign -dvv <sidecar>
```

## Private ColorSync SPI
2-arg `(PMPrintSession, CFStringRef) -> OSStatus`. Never pass integer `1`.
Modes: `AP_ApplicationColorMatching` then `ApplicationColorMatching`.
`lp` path and Quartz/`ICCeryPrintKit` path use **different** ColorSync dictionaries. Never mix.
