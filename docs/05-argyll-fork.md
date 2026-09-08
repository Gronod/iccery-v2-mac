# 05 — Gronod ArgyllCMS fork protocols

> Line numbers refer to ICCery v0.8.5 (`/tmp/ICCery` at analysis time) and the Gronod ArgyllCMS 3.5.0 fork.

Source tree analysed: `/tmp/argyllcms` (fork of upstream ArgyllCMS **V3.5.0**, 21 Aug 2026).
Related: `/tmp/ICCery`, `/tmp/iccery-research/argyll-issues.json`, `/tmp/iccery-research/issues/111.md`.

This document is the fork-vs-upstream delta that ICCery actually depends on. Upstream Graeme Gill ArgyllCMS 3.5.0 has **none** of the `-u` JSON streams, `instlist`, `printtarg -d`, `chartread -Y l`, or the Windows `PeekNamedPipe` stdin fix.

---

## 1. Fork identity, licence, subprocess isolation

| Field | Value |
|---|---|
| Upstream | ArgyllCMS V3.5.0 (Graeme W. Gill) |
| Fork | `gronod/argyllcms` — Gordon Bolton `<gordon@i3omb.com>` |
| Repo | https://git.i3omb.com/gronod/argyllcms |
| Version string | `ARGYLL_VERSION_STR "3.5.0"` (`h/aconfig.h`) |
| Release tags | `v3.5.0-ICCery.1.x` (e.g. 1.0, 1.2, 1.5) |
| Licence | **GNU Affero GPL v3** (`License.txt`, `ReadMe.txt`) |

`ReadMe.txt` states the fork's purpose:

> this fork adds structured JSON output capabilities (via a common `-u` switch) to several tools so they can be driven as isolated subprocesses by external UIs while preserving AGPLv3 licence isolation (no library linking; communication over stdin / stdout / stderr only).

### Why ICCery cannot link

ArgyllCMS is AGPLv3. Linking `libinst` / `libicc` / `libcgats` into the MIT/proprietary host would taint ICCery. The integration contract is:

1. Never `#include` or link Argyll libraries.
2. Spawn each tool as a child process with piped stdin/stdout/stderr.
3. Treat the binaries as an external OS utility.
4. Host parses line-oriented stdout; never shares address space.

ICCery implements this in `src-tauri/src/process_manager.rs`: `Command::new(binary)` + `Stdio::piped()` on all three FDs, plus `ARGYLL_NOT_INTERACTIVE=1`.

The fork ships a dedicated spec at `doc/chartread_integration_guide.md` covering AGPL isolation, `ROW_COLORS_JSON` framing, and host-side parsers.

---

## 2. Each tool's `-u` JSON protocol

**Prefix rule (critical):** only `chartread` prefixes. Every other tool emits **bare JSON** on stdout.

| Tool | Flag | Prefix | Framing | When | Progress vs final |
|---|---|---|---|---|---|
| `chartread` | `-u` | `ROW_COLORS_JSON: ` (space after colon) | **one compact line** + `fflush` | after each completed row (strip / XY sheet rows / whole-chart rows / per-patch in `-p`) | **progress** (one event per row); no final summary JSON |
| `instlist` | *(always)* | none | **pretty-printed multi-line** object | once at exit | **final only** |
| `printtarg` | `-u` | none | **pretty-printed multi-line** object | once after all pages written | **final only** (`event: manifest`) |
| `targen` | `-u` | none | **one compact line** per tick | during OFPS/grid generation | **progress** (`generating` / `seeding` / `optimising`) |
| `colprof` | `-u` | none | **one compact line** per tick | during A2B/B2A/gamut | **progress** (no final report JSON) |
| `profcheck` | `-u` | none | **one compact line** | after all patches scored | **final only** (`event: report`) |

ICCery's process manager only special-cases the chartread prefix:

```129:138:/tmp/ICCery/src-tauri/src/process_manager.rs
                    const JSON_ROW_PREFIX: &str = "ROW_COLORS_JSON: ";
                    let mut reader = BufReader::new(stdout).lines();
                    while let Ok(Some(line)) = reader.next_line().await {
                        if line.starts_with(JSON_ROW_PREFIX) {
                            let json_str = line[JSON_ROW_PREFIX.len()..].to_string();
                            crate::events::emit_json_row(&app_clone, &id_clone, json_str);
                        } else {
                            log::info!(target: "subprocess", "[{id_clone}] {line}");
                            emit_stdout(&app_clone, &id_clone, line);
                        }
                    }
```

Everything else (instlist, printtarg, profcheck, colprof, targen) arrives as ordinary `process:stdout` lines. instlist is reassembled client-side and `JSON.parse`'d as a whole document.

### 2.1 `chartread -u`

Flag parser:

```2885:2887:/tmp/argyllcms/spectro/chartread.c
			/* Enable UI JSON output */
			} else if (argv[fa][1] == 'u') {
				json_ui_out = 1;
```

Emitter (the only place `ROW_COLORS_JSON:` is written):

```240:282:/tmp/argyllcms/spectro/chartread.c
static void emit_row_json_colors(const char *row_id, int row_index, int total_rows, int patch_count, int nchan, chcol **scbs) {
	int i, j;
	if (!json_ui_out) return;
	fprintf(stdout, "ROW_COLORS_JSON: {\"event\": \"row_complete\", \"row_id\": \"%s\", \"row_index\": %d, \"total_rows\": %d, \"patch_count\": %d, \"patches\": [", row_id ? row_id : "", row_index, total_rows, patch_count);
	/* ... per-patch objects ... */
	fprintf(stdout, "]}\n");
	fflush(stdout);
}
```

Call sites:

| `rmode` | Mode | When emitted |
|---|---|---|
| 3 | whole-chart saved readings | one event per row after all patches transferred |
| 2 | XY table | one event per row of the just-read sheet |
| 1 | strip (handheld i1Pro etc.) | one event per successfully accepted strip, **after** bi-di reversal + DTP51 offset, patches left-to-right |
| 0 | spot / `-p` | **one event per patch**, `patch_count=1` |

Without `-u`, stdout is 100% unmodified (the early `if (!json_ui_out) return`).

### 2.2 `targen -u`

```161:167:/tmp/argyllcms/target/targen.c
int json_progress = 0;

void emit_json_progress(const char *stage, int percent) {
	if (!json_progress) return;
	printf("{\"event\": \"progress\", \"stage\": \"%s\", \"percent\": %d}\n", stage, percent);
	fflush(stdout);
}
```

Stages observed in source:

- `"generating"` — cube / full-spread fill (`targen.c`, `ifarp.c`)
- `"seeding"` — OFPS seed (`ofps.c`)
- `"optimising"` — OFPS / display-delay iteration (`ofps.c`, `targen.c`); last tick is `percent: 100`

ICCery **does not currently pass `-u` to targen** (`build_targen_args` in `commands.rs`). Progress is inferred from verbose text.

### 2.3 `printtarg -u`

Final-only, pretty-printed, **no prefix**:

```2949:2968:/tmp/argyllcms/target/printtarg.c
	if (json_manifest) {
		int pi;
		printf("{\n");
		printf("  \"event\": \"manifest\",\n");
		printf("  \"pages\": [\n");
		for (pi = 0; pi < npages; pi++) {
			printf("    {\"filename\": \"%s\", \"patches\": %d, \"width_mm\": %g, \"height_mm\": %g}%s\n",
				page_filenames[pi] != NULL ? page_filenames[pi] : "",
				page_patches[pi],
				pw,
				ph,
				(pi < npages - 1) ? "," : "");
			if (page_filenames[pi] != NULL)
				free(page_filenames[pi]);
		}
		printf("  ]\n");
		printf("}\n");
		fflush(stdout);
```

Schema:

```json
{
  "event": "manifest",
  "pages": [
    {"filename": "target.tif", "patches": 800, "width_mm": 210, "height_mm": 297},
    {"filename": "target_02.tif", "patches": 250, "width_mm": 210, "height_mm": 297}
  ]
}
```

- `filename` is the basename actually written (`%s.tif` if one page, `%s_%02d.tif` if more).
- `width_mm` / `height_mm` are paper size in millimetres (`pw`/`ph`).
- `patches` is a running count of TID/real patches assigned to that page (includes some padding/TID cells — not strictly "user patches only").
- ICCery **does** pass `-u` (`build_printtarg_args`).

### 2.4 `colprof -u`

Same compact progress line as targen:

```78:84:/tmp/argyllcms/profile/colprof.c
int json_progress = 0;

void emit_json_progress(const char *stage, int percent) {
	if (!json_progress) return;
	printf("{\"event\": \"progress\", \"stage\": \"%s\", \"percent\": %d}\n", stage, percent);
	fflush(stdout);
}
```

Stages: `"gamut_mapping"` (10/25/40/75/100), `"a2b_table"`, `"b2a_table"`, `"gamut_table"`. Percent ticks also fire from LUT fill callbacks in `profout.c` / `profin.c`.

**Flag collision with upstream `-u`.** Parser (`colprof.c:503-521`):

- `-ua` / `-uc` / `-u <number>` → original input-profile white-point flags
- `-u` with no extra token → `json_progress = 1`

For ICCery's **output/printer** profiles this is safe (bare `-u` means JSON). For scanner/camera input profiles it is **not** drop-in. ICCery currently **does not pass `-u` to colprof**; `colprof.mock` emits only human text.

### 2.5 `profcheck -u`

```1256:1268:/tmp/argyllcms/profile/profcheck.c
		if (json_report) {
			if (cie2k) {
				printf("{\"event\": \"report\", \"peak_de2000\": %.2f, \"avg_de2000\": %.2f, \"rms\": %.2f}\n",
				       merr, aerr/nsamps, sqrt(rerr/nsamps));
			} else if (cie94) {
				printf("{\"event\": \"report\", \"peak_de94\": %.2f, \"avg_de94\": %.2f, \"rms\": %.2f}\n",
				       merr, aerr/nsamps, sqrt(rerr/nsamps));
			} else {
				printf("{\"event\": \"report\", \"peak_de\": %.2f, \"avg_de\": %.2f, \"rms\": %.2f}\n",
				       merr, aerr/nsamps, sqrt(rerr/nsamps));
			}
			fflush(stdout);
		}
```

Field names change with `-k` (CIEDE2000, ICCery default) vs `-c` (CIE94) vs default CIE76. ICCery always sends `-v -k -s -u`. The human line `Profile check complete, errors(CIEDE2000): ...` is still printed unless `-v` is off **and** `-u` is on.

`profcheck.mock` emits exactly:

```
{"event": "report", "peak_de2000": 2.41, "avg_de2000": 0.85, "rms": 1.02}
```

---

## 3. `chartread` `ROW_COLORS_JSON` schema (field-by-field)

Exact prefix: **`ROW_COLORS_JSON: `** (17 chars including the trailing space). Payload is compact JSON, no newlines inside. Host must strip the prefix then `JSON.parse`.

### Top-level

| Field | Type | Source | Notes |
|---|---|---|---|
| `event` | string | literal | always `"row_complete"` |
| `row_id` | string | `paix->aix(paix, row_index)` | strip letter, e.g. `"A"`; `""` if NULL |
| `row_index` | int | 0-based overall row | |
| `total_rows` | int | `totpa` | total passes in the chart |
| `patch_count` | int | `stipa` (or `1` in `-p`) | length of `patches[]` |
| `patches` | array | | left-to-right after bi-di reversal |

### Patch object

| Field | Type | Source | Notes |
|---|---|---|---|
| `id` | string | `scb->id` | `"0"` ⇒ spacer |
| `loc` | string | `scb->loc` | e.g. `"A1"` |
| `is_pad` | bool | `strcmp(scb->id, "0") == 0` | JSON `true`/`false` (unquoted) |
| `device` | `[float]` | `scb->dev[j] * 100.0` | `%.4f`, **0–100%**, length = `nchan` (RGB=3, CMYK=4) |
| `expected` | object, **optional** | omitted if `eXYZ` is all zeros | present only when `.ti2` has a reference |
| `expected.XYZ` | `[3]` | `scb->eXYZ` | scale **0–100** |
| `expected.Lab` | `[3]` | `icmXYZ2Lab(&icmD50, …, eXYZ/100)` | D50 |
| `measured` | object | **always present** | even for pads |
| `measured.XYZ` | `[3]` | `scb->XYZ` | scale **0–100** |
| `measured.Lab` | `[3]` | `icmXYZ2Lab(&icmD50, …, XYZ/100)` | D50; L* ~0–100 |
| `measured.spectral` | object, **optional** | omitted if `sp.spec_n == 0` | omitted by `-n` or colorimeter |
| `measured.spectral.bands` | int | `sp.spec_n` | |
| `measured.spectral.start_nm` | float `%.1f` | `sp.spec_wl_short` | typically 380 |
| `measured.spectral.end_nm` | float `%.1f` | `sp.spec_wl_long` | typically 730 |
| `measured.spectral.norm` | float `%.1f` | `sp.norm` | typically 100.0 |
| `measured.spectral.values` | `[float]` | `sp.spec[j]` `%.4f` | length = `bands` |

Lab conversion (XYZ must be divided by 100 before `icmXYZ2Lab`):

```218:237:/tmp/argyllcms/spectro/chartread.c
static void compute_patch_metrics(chcol *scb, double *eLab, double *mLab) {
	if (scb->eXYZ[0] != 0.0 || scb->eXYZ[1] != 0.0 || scb->eXYZ[2] != 0.0) {
		double scaled_exyz[3];
		scaled_exyz[0] = scb->eXYZ[0] / 100.0;
		/* ... */
		icmXYZ2Lab(&icmD50, eLab, scaled_exyz);
	} else {
		eLab[0] = eLab[1] = eLab[2] = 0.0;
	}
	{
		double scaled_mxyz[3];
		scaled_mxyz[0] = scb->XYZ[0] / 100.0;
		/* ... */
		icmXYZ2Lab(&icmD50, mLab, scaled_mxyz);
	}
}
```

Worked example (from `chartread.mock`, which matches the C serializer):

```
ROW_COLORS_JSON: {"event": "row_complete", "row_id": "A", "row_index": 0, "total_rows": 2, "patch_count": 3, "patches": [{"id": "1", "loc": "A1", "is_pad": false, "device": [0.0, 50.0, 100.0], "expected": {"XYZ": [18.4210, 20.1234, 15.6789], "Lab": [51.98, -8.45, 12.32]}, "measured": {"XYZ": [18.5120, 20.0451, 15.7100], "Lab": [51.89, -8.31, 12.15]}}, {"id": "2", "loc": "A2", "is_pad": false, "device": [10.0, 60.0, 90.0], "expected": {"Lab": [60.0, 10.0, -20.0]}, "measured": {"Lab": [60.1, 10.5, -19.5]}}, {"id": "3", "loc": "A3", "is_pad": true, "device": [100.0, 100.0, 100.0]}]}
```

Pad patches still have `device` + `measured`; they usually lack `expected`. UIs must skip `is_pad==true` for ΔE stats (ICCery `swatch_grid.js` does).

---

## 4. `instlist` JSON device enumeration (ICCery bug #111)

New binary `spectro/instlist.c`. Always JSON; no `-u`. Usage: `instlist [-v] [-D [level]]`.

```90:135:/tmp/argyllcms/spectro/instlist.c
	if ((icmps = new_icompaths(g_log)) == NULL) {
		printf("{\n  \"event\": \"instruments\",\n  \"devices\": []\n}\n");
		fflush(stdout);
		return 1;
	}
	paths = icmps->paths;
	printf("{\n  \"event\": \"instruments\",\n  \"devices\": [\n");
	if (paths != NULL) {
		for (i = 0; paths[i] != NULL; i++) {
			char *tname = inst_name(paths[i]->dtype);
			char *name = paths[i]->name ? paths[i]->name : "Unknown";
			/* ... */
			printf("      \"port\": %d,\n", i + 1);
			printf("      \"name\": \""); /* escaped " and \ */
			printf("\",\n");
			printf("      \"type\": \"%s\"\n", (tname != NULL && tname[0] != '\000') ? tname : "Unknown");
			printf("    }");
			count++;
		}
	}
	printf("\n  ]\n}\n");
	fflush(stdout);
```

Schema (from `doc/instlist.html` + source):

```json
{
  "event": "instruments",
  "devices": [
    {
      "port": 1,
      "name": "usb:/bus0/dev1 (X-Rite i1Pro)",
      "type": "i1Pro"
    }
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `port` | int, **1-based** | `i+1` over `icompaths->paths[]` — **the same integer as `chartread -c N`** |
| `name` | string | `icompath->name` (USB path + product string). `"` and `\` escaped. |
| `type` | string | `inst_name(dtype)` e.g. `"i1Pro"`, `"ColorMunki"`, `"SpectroScan"` |

Empty enumeration (no USB perms / no devices / `new_icompaths` fail) still emits `{"event":"instruments","devices":[]}` (exit 1 only if `new_icompaths` itself fails).

### Bug #111 — ports vs device index

ICCery originally treated instlist's ordinal as `chartread -c`. That is **correct in this fork** *if* you use `devices[i].port` (which **is** the comm-port index). It is **wrong** if you:

- use 0-based array index,
- parse `chartread -??` separately (different listing / extra serial junk),
- or pass `-c 1` when the UI meant "auto".

ICCery's current fix (`chartread.js`):

- JSON path: `opt.value = inst.port && inst.port !== "1" ? inst.port : ""`
- empty value → `build_chartread_args` **omits `-c`** (Argyll default port 1)
- regex fallback requires a known instrument token or `on '…'` clause

`doc/instlist.html` explicitly: *The `port` number directly corresponds to the `-c` parameter accepted by chartread, spotread, and dispread.*

---

## 5. `chartread -Y l` LED protocol / colours

**Not `-L`.** Issue #37 proposed `-L`; the implementation is **`-Y l`** (also accepts `-Y L`).

```2943:2953:/tmp/argyllcms/spectro/chartread.c
			else if (argv[fa][1] == 'Y') {
				fa = nfa;
				if (na == NULL)
					usage();
				if (na[0] == 'l' || na[0] == 'L') {
					g_use_leds = 1;
				} else {
					usage();
				}
			}
```

ICCery: `enable_i1pro2_leds` → `["-Y", "l"]`. Usage text: `-Y l             Enable i1Pro 2 visual LED feedback`. **Not documented in `doc/chartread.html` yet** (only `usage()`).

Dispatch is capability-silent: missing `set_led_state` or non-i1Pro2 returns `inst_unsupported` and is ignored.

```207:216:/tmp/argyllcms/spectro/chartread.c
static int g_use_leds = 0;
static void update_led_state(inst *it, inst_led_state state) {
	if (!g_use_leds || it == NULL)
		return;
	if (it->set_led_state != NULL) {
		it->set_led_state(it, state);
	}
}
```

Enum (`spectro/inst.h`):

```c
typedef enum {
    inst_led_off           = 0,
    inst_led_cal_wait      = 1, /* Flashing White */
    inst_led_row_ready     = 2, /* Flashing Blue  */
    inst_led_row_fail      = 3, /* Flashing Red   */
    inst_led_row_success   = 4  /* Solid/Flash Green */
} inst_led_state;
```

Hardware: **X-Rite i1Pro 2 (Rev E) only** (`p->dtype != instI1Pro2` → `inst_unsupported`). Default `inst.c` stub returns `inst_unsupported`. Implementation is a background thread in `i1pro_imp.c` driving `i1pro2_indLEDset` bitmasks:

| State | Visual | Timing | Mask |
|---|---|---|---|
| `inst_led_cal_wait` | White flash | 500 ms on / 500 ms off | `0x3F` (L+R R+G+B) |
| `inst_led_row_ready` | Blue pulse | 300 ms on / 700 ms off | `0x24` (L+R Blue) |
| `inst_led_row_fail` | Red strobe | 3× (100 ms on / 100 ms off), then auto-off | `0x09` (L+R Red) |
| `inst_led_row_success` | Green confirm | 400 ms solid, then auto-off | `0x12` (L+R Green) |
| `inst_led_off` | Off | — | `i1pro2_indLEDoff` |

Lifecycle hooks in `chartread.c`:

- before `inst_handle_calibrate` → `cal_wait`; after → `off`
- before `read_strip` / `read_sample` wait → `row_ready`
- misread / coms fail / unexpected error → `row_fail`
- accepted strip → `row_success`
- abort / session end → `off`

---

## 6. `printtarg -d` custom label

Issue #19. `-d` was unused (TIFF 8-bit dither is `-D`).

```3342:3348:/tmp/argyllcms/target/printtarg.c
			else if (argv[fa][1] == 'd') {
				fa = nfa;
				if (na == NULL) usage("Expected argument to -d");
				custom_label = na;
				custom_label_set = 1;
			}
```

```3836:3847:/tmp/argyllcms/target/printtarg.c
	if (custom_label_set) {
		if (custom_label[0] != '\000') {
			strncpy(label, custom_label, sizeof(label) - 1);
			label[sizeof(label) - 1] = '\000';
			ocg->add_kword(ocg, 0, "CHART_LABEL", custom_label, NULL);
		} else {
			label[0] = '\000';
		}
	} else {
		sprintf(label, "ArgyllCMS - Chart \"%s\" (%s %d) %s",
		               psname, rand ? "Random Start" : "Chart ID", rstart, atm);
	}
```

And inside layout:

```2299:2300:/tmp/argyllcms/target/printtarg.c
	if (label == NULL || label[0] == '\000')
		dopglabel = 0;		/* Omit per-page labelling */
```

Behaviour:

| Invocation | Border text | `.ti2` keyword |
|---|---|---|
| no `-d` | `ArgyllCMS - Chart "<psname>" (Chart ID\|Random Start N) <datetime>` | none (`CHART_ID` / `RANDOM_START` still written) |
| `-d "My Media 1440dpi"` | that string (truncated to 1023 chars) | `CHART_LABEL` |
| `-d ""` | omitted (`dopglabel=0`) | not written |

ICCery always passes `-d` when `custom_label` is `Some(...)` (test: `"ICCery - Pro900 - Luster - 29/08/2026 12:00"`).

---

## 7. Windows anonymous-pipe stdin deadlock (argyllcms #24)

Symptom: ICCery/Tauri on Windows, `chartread` as child with redirected stdin. Calibration works; holding the i1Pro button never lights the lamp. Process stuck in stdin poll.

Root cause (upstream `ARGYLL_NOT_INTERACTIVE`):

1. `numlib/numsup.c` `check_if_not_interactive()` calls `SetNamedPipeHandleState(PIPE_NOWAIT)` on stdin.
2. That **fails on Win32 anonymous pipes** (`CreatePipe` / Rust `Stdio::piped()`). Pipe stays blocking.
3. `spectro/conv.c` `con_char(wait=0)` then `ReadFile()`'s the pipe, **blocks forever**.
4. `def_uicallback` → `poll_con_char` → `con_char(0)` runs from `i1pro_imp_measure()`'s UI callback, so USB EP `0x84` switch polling never resumes.

Fork fix in `spectro/conv.c`: `PeekNamedPipe` before `ReadFile`:

```203:237:/tmp/argyllcms/spectro/conv.c
		} else if (stdin_type == FILE_TYPE_PIPE) {
			int i, bib;
			DWORD bytes_avail = 0;

			if (!PeekNamedPipe(stdinh, NULL, 0, NULL, &bytes_avail, NULL) || bytes_avail == 0) {
				if (!wait) {
					return 0;
				}
			}

			for (bib = 0; bib < 10;) {
				if (!wait) {
					if (!PeekNamedPipe(stdinh, NULL, 0, NULL, &bytes_avail, NULL) || bytes_avail == 0) {
						break;
					}
				}
				if ((!ReadFile(stdinh, buf + bib, 10 - bib, &bread, NULL) || bread == 0)
				 && !wait) {
					break;
				}
				/* ... wait for \n / \r / ^C ... */
			}
			rv = buf[0];
```

`SetNamedPipeHandleState` is still attempted (harmless failure). `PeekNamedPipe` is valid on both anonymous and named pipes.

Shipped in `v3.5.0-ICCery.1.2`. ICCery always sets `ARGYLL_NOT_INTERACTIVE=1` and `CREATE_NO_WINDOW` on Windows, so this fix is load-bearing.

Doc (`doc/Environment.html`): *On MSWin systems, the character and return or line feed characters must be written to stdin in a single operation.* ICCery honours this (`" \n"`, `"d\n"`, `"q\n"`).

---

## 8. USB drivers packaging

Windows release zip must contain `usb/` (issue #21: CRLF in `binfiles` / `doc/afiles` / `usb/binfiles.msw` made `cp` miss every manifest entry). Fork sanitises with `tr -d '\r'` in `makepackagebin.sh` and copies missing `ArgyllCMS_{x64,arm64}.cat` from `ArgyllCMS.cat`.

`usb/binfiles.msw`:

```
ArgyllCMS_install_USB.exe
ArgyllCMS_uninstall_USB.exe
ArgyllCMS.cat
ArgyllCMS_x64.cat
ArgyllCMS_arm64.cat
ArgyllCMS.inf
bin/libusb-win32-bin-README.txt
bin/x86/libusb0.sys
bin/amd64/libusb0.sys
bin/arm64/libusb0.sys
```

ICCery `scripts/fetch-argyll.mjs` copies `usb/` from the Windows archive into `src-tauri/argyll/usb/` and **fails the fetch** if `ArgyllCMS_install_USB.exe` or `ArgyllCMS.inf` is missing.

NSIS (`src-tauri/windows/hooks.nsh`): admin install prompts "Install ArgyllCMS USB instrument drivers?" then `ExecWait ArgyllCMS_install_USB.exe`. Uninstall does **not** auto-run `ArgyllCMS_uninstall_USB.exe` (would break other Argyll apps).

Linux: udev rules live in the Argyll tarball `usb/` (`binfiles.lx`); ICCery does not currently stage them (USB access is via user-installed udev / plugdev).

---

## 9. macOS ad-hoc signing of Mach-O sidecars

Issue #32, release `v3.5.0-ICCery.1.5` (`1eb72e8`, `cf93305`).

`makepackagebin.sh`:

```176:185:/tmp/argyllcms/makepackagebin.sh
# Apply ad-hoc code signatures to macOS Mach-O binaries before staging
if [ "${OSTYPE#*darwin*}" != "$OSTYPE" ] ; then
	echo "=== Applying ad-hoc code signatures to macOS Mach-O binaries ==="
	for f in bin/* ; do
		if [ -f "$f" ] && file "$f" | grep -q "Mach-O" ; then
			echo "Signing $f..."
			codesign -f -s - "$f" || true
		fi
	done
fi
```

Also signs `lipo` universal (`x86_64` + `arm64`) binaries (issue #27: `Argyll_V*_macOS_universal_bin.tgz`). CI verifies with `codesign -dvv`.

ICCery prefers `argyll/macos-universal/instlist` when present (`commands.rs` / `build.rs`); otherwise `macos-aarch64` / `macos-x86_64`. Unsigned Mach-O sidecars are killed by Gatekeeper / `killed: 9` on Apple Silicon.

---

## 10. Which binaries ICCery actually ships vs uses

`fetch-argyll.mjs` copies the **entire** `bin/` of the Gronod release (full Argyll suite: `dispcal`, `dispread`, `spotread`, `collink`, `cctiff`, `oeminst`, … plus fork `instlist`). Marker binary: `instlist` / `instlist.exe`. Plus `License.txt`. Plus Windows `usb/`.

**Invoked by ICCery** (`resolve_binary` call sites):

| Binary | Stage / feature |
|---|---|
| `instlist` | instrument dropdown |
| `targen` | Stage 1 + calibration charts |
| `printtarg` | Stage 2 |
| `chartread` | Stage 3 |
| `average` | multi-pass `.ti3` merge |
| `colprof` | Stage 4 |
| `profcheck` | Stage 4 QA |
| `iccgamut` | gamut viewer |
| `printcal` | Stage 0 linearization (#224) |
| `applycal` | embed/apply `.cal` into ICC |

The rest of the suite is on disk as AGPL corresponding source/binary distribution but unused.

Mocks used by tests (`src-tauri/argyll/mocks/`): `chartread.mock`, `colprof.mock`, `profcheck.mock` only. `chartread.mock` speaks `ROW_COLORS_JSON`; `profcheck.mock` speaks bare `{"event":"report",...}`; `colprof.mock` does **not** speak JSON.

---

## 11. Environment variables the fork / tools honour

### Fork-critical (ICCery always sets)

| Var | Set by ICCery | Effect |
|---|---|---|
| `ARGYLL_NOT_INTERACTIVE` | `"1"` in `process_manager.rs` and `calibration.rs` | LF instead of CR on progress; stdin is "char + return" not raw key; Windows pipe NOWAIT + (fork) PeekNamedPipe; unbuffered/line-buffered stdout |

### Upstream vars still live in this tree (host may set)

| Var | Consumer |
|---|---|
| `ARGYLL_3D_DISP_FORMAT` | `VRML` / `X3D` / `X3DOM` |
| `ARGYLL_COLMTER_CAL_SPEC_SET` / `ARGYLL_COLMTER_COR_MATRIX` | default CCSS/CCMX (`-X`) |
| `ARGYLL_MIN_DISPLAY_UPDATE_DELAY_MS` | display tools |
| `ARGYLL_DISPLAY_SETTLE_TIME_MULT` | display tools |
| `ARGYLL_DISPLAY_FAKE_RAND_SEED` | `dispsup.c` |
| `ARGYLL_CREATE_WRONG_VON_KRIES_OUTPUT_CLASS_REL_WP` | ICC writer |
| `ARGYLL_CREATE_DISPLAY_PROFILE_WITH_CHAD` / `_WITHOUT_CHAD` | ICC writer |
| `ARGYLL_CREATE_OUTPUT_PROFILE_WITH_CHAD` | ICC writer |
| `ARGYLL_CREATE_V2COLORANT_TABLE` | ICC writer |
| `ARGYLL_PLATFORM_OVERRIDE` | `icc.c` |
| `ARGYLL_CCAST_DEFAULT_RECEIVER` / `ARGYLL_CCAST_TEST_PATTERN` | Chromecast |
| `ARGYLL_IGNORE_XRANDR1_2` / `ARGYLL_IGNORE_XINERAMA` | Linux display |
| `ARGYLL_USE_COLORD` | Linux profile store |
| `ARGYLL_DISABLE_I1PRO2_DRIVER` | force i1Pro2 legacy |
| `ARGYLL_EXCLUDE_SERIAL_SCAN` | skip COM/tty fast-scan |
| `ARGYLL_XRGA` | `XRGA` / `XRDI` / `GMDI` reflective conversion |
| `ARGYLL_XCALSTD` | per-driver X-Rite cal standard (i1pro, munki, dtp*, ss) |
| `ARGYLL_UNTWIST_GAMUT_SURFACE` | B2A / collink clip |
| `ARGYLL_REV_CACHE_MULT` / `ARGYLL_REV_ACC_GRID_RES_MULT` | rspl invert |
| `ARGYLL_SUPPRESS_PLOT` | `plot.c` |
| `XDG_{DATA,CONFIG,CACHE}_{HOME,DIRS}` | Linux paths |
| `SPYD2024_LOWLEV_MEASURE` | Spyder 2024 |
| `I1D3_DISABLE_AIO` | i1d3 (upstream) |
| `DISPLAY` / `SUDO_UID` / `SUDO_GID` | X11 / privilege drop |

ICCery does not currently set any of these besides `ARGYLL_NOT_INTERACTIVE`.

---

## 12. `chartread` interactive stdin commands and UI classifier

### 12.1 Real fork `chartread` (strip mode, `rmode==1`)

UIH table (`chartread.c:1547-1561`):

```c
inst_set_uih(0x00, 0xff, DUIH_TRIG);   /* every other key starts a read */
inst_set_uih('f'/'F'/'b'/'B'/'n'/'N'/'g'/'G'/'d'/'D', DUIH_CMND);
inst_set_uih('q'/'Q'/^C/Esc, DUIH_ABORT);
```

| Key | Class | Action |
|---|---|---|
| **any other key**, Space, Return, instrument switch | TRIG | start strip read |
| `f` / `F` | CMND | next row / +10 (spot: F=+10) |
| `b` / `B` | CMND | previous row / −10 |
| `n` / `N` | CMND | next **unread** row |
| `g` / `G` | CMND | goto (spot mode; registered in strip too) |
| `d` / `D` | CMND | done & save `.ti3`. If unread patches remain → confirm `[y/n]` |
| `q` / `Q` / Esc / `^C` | ABORT | quit without saving (retry prompt first) |
| `y` / `Y` | confirm | "Are you sure [y/n]" (done-with-unread, abort) |
| `n` (at `[y/n]`) | confirm | stay in session |
| `s` / `S` | **optional calibration only** | `inst_handle_calibrate`: "or S to skip" when `inst_calc_optional_flag` |
| `k` | CMND (spot only) | force calibrate |

**There is no strip-mode `s` = skip row, and no `u` = undo.** Those exist only in ICCery's mock / UI. Sending `s` or `u` during "Ready to read strip" is **DUIH_TRIG** → starts a measurement.

### 12.2 Spot mode (`-p`) extra keys

`f/F/b/B/n/N/g/G/d/D/k` as above; Return/Space/`0` = take reading.

### 12.3 XY table (`rmode==2`)

Return = continue; `q`/Esc/`^C` = give up (parks head if `q` sent before kill — ICCery does this).

### 12.4 Exact prompt strings the C code prints

(With `ARGYLL_NOT_INTERACTIVE=1`, prompt lines still have **no trailing LF** unless noted; they are flushed via `do_fflush()`. ICCery's line reader may not see a prompt until a later `\n`.)

**Calibration** (`instappsup.c`) — real i1Pro:

```
Place the instrument on its reflective white reference S/N <id>,
 and then hit any key to continue,
 or hit Esc or Q to abort: 
```

(optional cal appends `or S to skip`)

Other cal variants: `"Do a reflective white calibration,"`, `"Place the instrument on light trap..."`, `"Click the instrument on its reflective white reference..."`, `"Hit any key to retry, or Esc or Q to abort:"`.

**Strip ready:**

```
Ready to read strip pass <row>[ (!! ALL ROWS READ !!)| (This row has been read)]
Press 'f' to move forward, 'b' to move back, 'n' for next unread,
 'd' when done, Esc or 'q' to quit without saving.
Trigger instrument switch to start reading.          # uswitch==1
Trigger instrument switch or any other key to start: # uswitch==2
Press any other key to start:                        # uswitch==0
```

**Success / fail:**

```
 Strip read OK
(Warning) Seem to have read strip pass <X> rather than <Y>!
Hit Return to use it anyway, any other key to retry, Esc or 'q' to give up:
There is at least one patch with an very unexpected response! (DeltaE <n>)
Hit Return to use it anyway, any other key to retry, Esc or  'q' to give up:
Strip read failed due to misread (<reason>)
Hit Esc to give up, any other key to retry:
Strip read failed due to communication problem.
Hit Esc or 'q' to give up, any other key to retry:
Done ? - At least one unread patch (<id>, <loc>), Are you sure [y/n]:
```

**XY table:**

```
Please place sheet <n> of <N> on table, then
hit return to continue, Esc or 'q' to give up
Please remove previous sheet, then place sheet <n> of <N> on table, then
hit return to continue, Esc or 'q' to give up
Using the XY table controls, locate patch <id> with the sight,
then hit return to continue, Esc or 'q' to give up
Sheet <n> of <N> read OK
Please remove last sheet from table
```

**Done / abort:**

```
Chart read OK
Abort ? - Are you sure ? [y/n]:
```

### 12.5 What ICCery actually sends (`chartread.js`)

| UI button | stdin bytes | Intended |
|---|---|---|
| Calibrate / Retry | `" \n"` | space + NL (single WriteFile) |
| Accept / Continue | `"\n"` | Return (use-it-anyway, XY continue) |
| Done & Save | `"d\n"` | done |
| Undo | `"u\n"` | **not a chartread command** — will TRIG a read |
| Skip | `"s\n"` | **only skips optional cal**; otherwise TRIG a read |
| Cancel (XY) | `"q\n"` then kill after 500 ms | park head |
| Cancel (strip) | kill process | |

### 12.6 `classifyChartreadLine` (tests in `chartread.test.js`)

Priority order:

1. `"remove last sheet from table"` → info, no state change (`isRemoveSheetNotice`)
2. `/sheet\s+(\d+)\s+of\s+(\d+)\s+read\s+ok/i` → `sheetOk`
3. `"locate patch … with … sight"` → `TABLE_ALIGN` (`meta.patch`)
4. `"place sheet N of M"` / `"remove previous sheet"` → `TABLE_PLACE_SHEET`
5. `"hit return to continue"` (sticky if already TABLE_*) → `PROMPT_CONTINUE` otherwise
6. `"'d' if/when done"`, `"all strips/patches read"`, `"d to finish/save"` → `ALL_STRIPS_READ`
7. `"(warning)"`, `"use it anyway"`, `"seem to have read strip pass"`, `"unexpected response"` → `WARNING`
8. place + (reference|white|calibrat|standard) / `"hit any key to continue"` / `"calibration"` → `CALIBRATING`
9. hit+read+strip / `"ready to read"` → `AWAITING_STRIP`
10. `"reading strip"` / `"processing"` / `"scanning"` / `"reading sheet"` → `READING`
11. `"error"` / `"too fast"` / `"too slow"` / `"misread"` / `"failed to read"` → `ERROR`

### 12.7 Mock vs real (tests rely on mock phrasing)

`chartread.mock` (and classifier tests) use **synthetic** lines that real chartread never prints:

| Mock / test line | Real chartread |
|---|---|
| `Place instrument on calibration tile and hit [Space] to calibrate.` | `Place the instrument on its reflective white reference S/N …` + `hit any key to continue` |
| `Hit [Space] to read strip A (or 's' to skip).` | `Ready to read strip pass A` + f/b/n/d menu |
| `Reading strip A...` | no such line; success is ` Strip read OK` |
| `Calibration successful.` | no such line |
| `Ready to read... done.` | `Chart read OK` |

Classifier still matches real prompts because of substring rules (`"ready to read"`, `"hit any key to continue"`, `"use it anyway"`, `"place sheet"`, `"locate patch"`). Rewrite UIs should classify the **C strings above**, not only the mock.

---

## Appendix A — Fork vs upstream 3.5.0 checklist

| Feature | Upstream 3.5.0 | Gronod fork |
|---|---|---|
| `chartread -u` / `ROW_COLORS_JSON` | no | yes |
| `instlist` | no | yes |
| `printtarg -u` JSON manifest | no | yes |
| `printtarg -d` custom label | no | yes |
| `targen -u` progress JSON | no | yes |
| `colprof -u` progress JSON (bare `-u`) | `-u` is WP-scale for **input** profiles | same, plus bare `-u` → JSON |
| `profcheck -u` ΔE JSON | no | yes |
| `chartread -Y l` i1Pro2 LEDs | no | yes |
| Windows `PeekNamedPipe` stdin | no (deadlocks on anon pipes) | yes |
| `makepackagebin.sh` CRLF sanitize + cat copies | no | yes |
| macOS `codesign -s -` + universal lipo archive | no | yes |
| `doc/chartread_integration_guide.md` | no | yes |
| `doc/instlist.html` | no | yes |

## Appendix B — ICCery `-u` usage vs fork capability

| Tool | Fork `-u` | ICCery currently passes `-u` |
|---|---|---|
| chartread | yes | **yes** (`-v -u [-c port] [-Y l] basename`) |
| printtarg | yes | **yes** (`-v -u …`) |
| profcheck | yes | **yes** (`-v -k -s -u`) |
| targen | yes | **no** |
| colprof | yes | **no** |
| instlist | always JSON | spawned with no args |

## Appendix C — Issues mapped

| Repo | # | Topic |
|---|---|---|
| argyllcms | 1 | chartread `-u` ROW_COLORS_JSON |
| argyllcms | 2 | targen `-u` |
| argyllcms | 3 | printtarg `-u` |
| argyllcms | 4 | colprof `-u` |
| argyllcms | 5 | profcheck `-u` |
| argyllcms | 6 | instlist |
| argyllcms | 19 | printtarg `-d` |
| argyllcms | 21 | Windows zip missing usb/doc (CRLF) |
| argyllcms | 24 | PeekNamedPipe deadlock |
| argyllcms | 27 | macOS universal lipo |
| argyllcms | 32 | ad-hoc codesign |
| argyllcms | 37 | i1Pro2 LEDs (spec said `-L`, code is `-Y l`) |
| ICCery | 111 | instlist port vs `-c` index |
