# 03 — IPC and process manager

The host never waits on a child from the request that spawned it (except `printcal`/`applycal`, which use captured `.output()`). Streaming tools go through a process manager that:

1. Rejects a duplicate `id` while that child is still mapped (#116).
2. Pipes stdin/stdout/stderr.
3. Sets `ARGYLL_NOT_INTERACTIVE=1`.
4. On Windows sets `CREATE_NO_WINDOW` (`0x08000000`) (#46).
5. Splits stdout: lines beginning `ROW_COLORS_JSON: ` become `process:json_row` (prefix stripped); everything else is `process:stdout`.
6. Reaps the child on natural exit **or** kill signal; then emits `process:exit`.
7. Drops stdin from the map on kill so writers fail fast.

## Commands the rewrite must expose

| Command | Args | Returns |
|---------|------|---------|
| `spawn_process` | `{ id, binary, args }` | `()` — unused by current JS (registered only) |
| `send_stdin` | `{ id, input }` | `()` — `input` is the **exact bytes**, already including `\n` |
| `kill_process` | `{ id }` | `()` |
| `kill_all_processes` | — | `usize` count signaled |
| `resolve_binary` | `{ binaryName }` | absolute path string |
| `run_targen` / `run_printtarg` / `run_chartread` / `run_average` / `run_colprof` / `run_profcheck` / `extract_gamut` / `detect_instruments` | typed configs | `()` after spawn (not after exit) |
| `generate_calibration_target` / `compute_calibration_curves` / `apply_calibration` | typed | captured result |

Frontend waits for `process:exit` with matching `id`. **Never** assume invoke() resolves when the tool finishes.

## Deadlock history (must not regress)

### ICCery #84 (P0)

Early ProcessManager held a `Mutex<Child>` across `Child::wait()`. `send_stdin` needed the same mutex → Calibrate/Retry hung. Dropping the mutex also dropped `ChildStdin` at spawn, closing the pipe immediately.

**Invariant:** stdin handle lives in its own map, independent of wait. Wait runs in a background task with a oneshot kill channel.

### ArgyllCMS fork #24 + ICCery #134

On Windows, `SetNamedPipeHandleState(PIPE_NOWAIT)` **fails on anonymous pipes** created by `Stdio::piped()`. Argyll's `con_char(wait=0)` then `ReadFile`s a blocking pipe during `uicallback`, so the instrument trigger thread never sees the button and the lamp never lights.

Fork fix: `PeekNamedPipe` before `ReadFile` (`spectro/conv.c`). ICCery always sets `ARGYLL_NOT_INTERACTIVE=1` so Argyll uses the pipe path, not a console.

**Invariant:** ship the Gronod fork (or equivalent PeekNamedPipe patch). Stock Argyll 3.5.0 will hang interactive chartread on Windows.

### Kill on window close (#147, #149)

`chartread` outlives the UI if not killed. XY tables need `q\n` first to park the head, then kill. On `CloseRequested` / `Exit`, `kill_all` is mandatory. Frontend Cancel in `TABLE_*` states sends `q\n` then kills.

## stdin protocol

`send_stdin` writes UTF-8 bytes and flushes. ICCery strings (see [05](05-argyll-fork.md) §12.5):

| UI | Bytes | Meaning in real chartread |
|----|-------|---------------------------|
| Calibrate / Retry strip / Accept (many states) | `" \n"` or `"\n"` | Space or Return = trigger (`DUIH_TRIG`) |
| Done & Save | `"d\n"` | finish and write `.ti3` |
| Skip | `"s\n"` | **not a skip in real strip mode** — treated as trigger. Mock/UI invention. Rewrite should verify against fork `chartread.c` before advertising Skip. |
| Undo | `"u\n"` | same caveat |
| XY cancel | `"q\n"` | abort / park |
| Warning accept | `"\n"` | "use it anyway" |

Always include the newline. Argyll line-buffers prompts.

## Logging hygiene

Spawn argv is logged with home directories rewritten to `~` (case-insensitive on Windows). Raw argv only at debug.
