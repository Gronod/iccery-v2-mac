# 18 — 3D gamut viewer

> Line numbers refer to ICCery v0.8.5 (`/tmp/ICCery` at analysis time) and the Gronod ArgyllCMS 3.5.0 fork.

Exhaustive reading of the current implementation for a rewrite. All citations are
`path:start-end` against `/tmp/ICCery` unless noted. Issue numbers refer to
`/tmp/iccery-research/issues/`.

**Module map**

| File | Role |
|---|---|
| `src/js/gamut_viewer.js` (831 lines) | Scene, parser, mesh, lifecycle, controls |
| `src/js/gamut_viewer.test.js` | Parser + WebGL-heuristic unit tests (Node) |
| `src/js/CSS2DRenderer.js` | Vendored Three.js CSS2D addon (IIFE → `THREE.*`) |
| `src/js/OrbitControls.js` | Vendored Three r128 OrbitControls (IIFE → `THREE.OrbitControls`) |
| `src/js/vendor/quickhull.js` | Incremental 3D QuickHull fallback |
| `src/js/color_convert.js` | Lab → sRGB for per-vertex colour |
| `src/js/three.min.js` | Three.js **r128** (`const e="128"`) |
| `src/js/state.js` | `ensureGamutViewer` / `pauseGamutViewer` on stage change |
| `src/js/app.js` | GPU hints, **no** eager WebGL on `DOMContentLoaded` |
| `src/js/colprof.js` | Post-`colprof` `extract_gamut` + `loadGamutMesh` |
| `src/js/profcheck.js` | Post-verify `loadGamutMesh` |
| `src-tauri/src/commands.rs` | `build_iccgamut_args`, `extract_gamut`, `read_file_base64` |
| `src/assets/sRGB.gam` | Bundled full Argyll surface (448 verts / 892 faces) |
| `src-tauri/argyll/reference_gamuts/sRGB.gam` | Stub 8-cusp CGATS — **not** what the viewer loads |

---

## 1. Lifecycle (MUST NOT init WebGL on `DOMContentLoaded`)

This is the #225 contract. Eager `THREE.WebGLRenderer` + continuous rAF on a
hidden Stage 5 canvas respawns WKWebView’s GPU helper on Monterey Intel: white
flash loop, then silent exit (Web Content process death, no `ICCery` crash
report).

### 1.1 What is forbidden

`src/js/app.js:130-137` explicitly does **not** call `initGamutViewer` in the
`DOMContentLoaded` `safeInit` batch:

```js
// Gamut Viewer is deferred until Stage 5 is shown (eager WebGL on launch
// respawns WKWebView on Monterey Intel).
safeInit('Stage 1 (Targen)', initTargen);
// ...
safeInit('Stage 5 (Profcheck)', initProfcheck);  // profcheck UI only, not WebGL
```

`#stage-5` starts with `class="stage hidden"` (`src/index.html:901`). Hidden
containers report `clientWidth === 0`; the old code fell back to 500×400 and
still created a GPU context (#225 §7.1).

### 1.2 `ensureGamutViewer` — only when Stage 5 is shown

`src/js/state.js:90-94`:

```js
if (stageNumber === 5) {
  ensureGamutViewer();
} else {
  pauseGamutViewer();
}
```

This is the **only** production call site besides context-restore / fallback
reload. `resumeGamutViewer` is exported (`gamut_viewer.js:180-182`) but **never
imported**. Returning to Stage 5 re-enters `ensureGamutViewer`, which
`startAnimate()`s if already ready.

`ensureGamutViewer` (`gamut_viewer.js:149-174`):

1. Bail if `gamutViewerUnavailable` (WebGL feature-detect failed once — sticky).
2. If `gamutViewerReady`, just `startAnimate()` (no second renderer).
3. If `#stage-5` has class `hidden`, **return without creating WebGL**.
4. Defer actual `initGamutViewer()` by one `requestAnimationFrame` so layout has
   a non-zero size after the `.hidden` class is removed.
5. Re-check hidden + ready flags inside the rAF callback.

`initGamutViewer` (`gamut_viewer.js:187-329`) is the real constructor:

- Re-entry guard: `gamutViewerReady || gamutViewerInitStarted`.
- Requires `#gamutViewerContainer` and global `THREE`.
- Feature-detects WebGL **before** `new THREE.WebGLRenderer` (`webglAvailable`,
  lines 37-46): tries `webgl2`, then `webgl`, then `experimental-webgl`.
- On failure: sets `gamutViewerUnavailable = true`, logs
  `WEBGL_UNAVAILABLE_MESSAGE`, paints fallback, returns. Never throws into
  `safeInit`.
- Constrained-GPU path (`isLikelyConstrainedGpu`, lines 56-79 +
  `setGpuHints` from `app.js:96-100`):

  ```js
  renderer = new THREE.WebGLRenderer({
      antialias: !lowPower,
      alpha: false,          // opaque; matches scene.background 0x0e0e14
      powerPreference: lowPower ? 'low-power' : 'default',
      failIfMajorPerformanceCaveat: false,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, lowPower ? 1 : 2));
  ```

  Arch preference: backend `get_app_info.arch` beats UA. Safari reports
  `navigator.platform === "MacIntel"` on Apple Silicon; treating that as Intel
  would wrongly drop antialias on M-series. Heuristic: `x86_64`/`x86`/`ia32`
  from backend → constrained; else UA `ARM|Apple Silicon|aarch64` → not;
  else Intel Mac UA + `macosMajor < 13` (or unknown major) → constrained.

- Default size if container is still 0: **500×400** (`gamut_viewer.js:214-215`).
  Should not trigger if the hidden-stage guard works.

### 1.3 Pause on leave

`pauseGamutViewer` → `stopAnimate()` (`animationRunning = false`). The rAF loop
(`gamut_viewer.js:334-343`) returns immediately if the flag is false, so a lost
or hidden context does not spin:

```js
function animate() {
    if (!animationRunning) return;
    requestAnimationFrame(animate);
    if (contextLost || !renderer) return;
    if (controls) controls.update();
    if (renderer && scene && camera) {
        renderer.render(scene, camera);
        if (labelRenderer) labelRenderer.render(scene, camera);
    }
}
```

**Does not dispose** the renderer on leave. Scene, GPU context, and meshes
survive. That is intentional: re-entering Stage 5 is cheap, and `loadGamutMesh`
from Stage 4 can populate the scene if the user already visited Stage 5.

### 1.4 Context-lost handler

`gamut_viewer.js:238-252`:

```js
renderer.domElement.addEventListener('webglcontextlost', (e) => {
    e.preventDefault();   // allow restore
    contextLost = true;
    stopAnimate();
    logger.error('WebGL context lost', 'GamutViewer');
    showGamutFallback(container, '3D view lost its GPU context. Profiling stages still work.', {
        reloadable: true,
    });
});
renderer.domElement.addEventListener('webglcontextrestored', () => {
    logger.warn('WebGL context restored — rebuilding viewer', 'GamutViewer');
    contextLost = false;
    disposeViewer();
    ensureGamutViewer();
});
```

`disposeViewer` (`gamut_viewer.js:115-143`) disconnects `ResizeObserver`,
`renderer.dispose()`, removes both canvases, nulls scene/camera/controls/meshes,
clears `gamutViewerReady` / `gamutViewerInitStarted` / `contextLost`.

**Not reset by dispose:** `gamutViewerUnavailable`, `togglesWired`, `gpuHints`.
`togglesWired` is OK (listeners live on HTML checkboxes, not the canvas).
`gamutViewerUnavailable` means a “Reload 3D view” button after a *feature-detect*
failure would no-op — but that path does not show the button (`reloadable`
defaults false). Init-throw and context-lost do show it.

### 1.5 Monterey WKWebView (#225) — adjacent host fixes (not in the JS viewer)

Fix 3 (this module) is the crash stop. Host-side (for rewrite awareness):

- Window `visible: false` until double-rAF + `show_main_window` (`app.js:143-150`).
- Dark `#1A1A22` window / WKWebView backing (`tauri.conf.json`, `macos_webview.rs`).
- `minimumSystemVersion` 12.0; Intel Monterey < 13 gets a one-shot notice
  (`app.js:30-45`).
- `visibilitychange` / `pagehide` logged (`app.js:74-79`).

Rewrite **must** keep: no WebGL until Stage 5 visible; pause rAF on leave;
feature-detect; context-lost fallback; `alpha: false`; DPR cap on constrained
GPU; do not treat MacIntel UA as Intel when backend arch is `aarch64`.

---

## 2. Scene graph

Coordinate convention (commented at `gamut_viewer.js:346-347` and `_buildGeometry`):

```
X = a*   (−128 → +128)   green ← → red
Y = L*   (0 → 100)       lightness, up
Z = b*   (−128 → +128)   blue ← → yellow
```

### 2.1 Camera

- `PerspectiveCamera(45, aspect, 0.1, 2000)`
- Home position `(180, 120, 180)`
- `lookAt(0, 50, 0)` — centre of the L* axis, not the origin
- `OrbitControls.target = (0, 50, 0)`, `enableDamping = true`, `dampingFactor = 0.05`
- Touch override (`gamut_viewer.js:272-275`): `ONE: ROTATE`, `TWO: DOLLY_PAN`
  (same as OrbitControls defaults; #117 says do not change this).
- `renderer.domElement.style.touchAction = 'none'` to stop the webview scrolling.

`resetCamera` (`gamut_viewer.js:676-682`) restores position + target. OrbitControls
also has its own `reset()` using `position0/target0`, but the app never calls it;
the custom function writes the same home pose.

### 2.2 Lights

No shadows, no environment map, no fog.

| Light | Colour | Intensity | Position |
|---|---|---|---|
| AmbientLight | `0xffffff` | 0.75 | — |
| DirectionalLight | `0xffffff` | 0.80 | `(150, 250, 150)` |
| DirectionalLight | `0xffffff` | 0.35 | `(-120, -80, -120)` |

Lambert materials + these lights are what make per-vertex Lab colour readable.
A rewrite that switches to MeshBasicMaterial would lose the slight modelling;
MeshStandardMaterial would need different lighting.

### 2.3 Axis scaffold (`buildAxisScaffold`, `gamut_viewer.js:349-423`)

Replaces `THREE.AxesHelper` (#185). One `THREE.Group` (`axisScaffoldGroup`):

1. **Bounding box** — `BoxGeometry(256, 100, 256)` → `EdgesGeometry` →
   `LineSegments`, colour `0x232336`, opacity 0.9, **positioned at `(0, 50, 0)`**
   so it covers L* 0–100, a*/b* ±128.
2. **Ground grid** — `GridHelper(256, 16, 0x1e1e2e, 0x1a1a28)` at `y = 0`
   (L*=0). #185 said “remove GridHelper”; the implementation kept a custom one.
3. **Axis lines** — L* grey `0xcccccc` `(0,0,0)→(0,100,0)`; a* and b* `0x99bbcc`
   spanning ±128.
4. **Ticks** — L* at 25/50/75/100 (crosses ±4 on X and Z); a* and b* at
   ±128/±64 (vertical ticks ±3). **No tick at 0** on a*/b*.
5. **CSS2D labels** (only if `THREE.CSS2DObject` exists):

   | Text | Position | Class |
   |---|---|---|
   | `L*` | `(0, 110, 0)` | `gamut-axis-primary` |
   | `+a* (Red →)` | `(140, 0, 0)` | `gamut-axis-a-pos` |
   | `← −a* (Green)` | `(-140, 0, 0)` | `gamut-axis-a-neg` |
   | `+b* (Yellow →)` | `(0, 0, 140)` | `gamut-axis-b-pos` |
   | `← −b* (Blue)` | `(0, 0, -140)` | `gamut-axis-b-neg` |
   | `25` / `50` / `75` / `100` | `(10, v, 0)` | `gamut-tick-label` |

   No numeric labels on a*/b* ticks. Colours are CSS (`main.css:1667-1691`):
   a+ salmon, a− green, b+ yellow, b− blue.

Labels are **children of `axisScaffoldGroup`**. `toggleAxes` sets
`axisScaffoldGroup.visible`. WebGL descendants honour group visibility; the
CSS2DRenderer (`CSS2DRenderer.js:87-89`) only tests `object.visible` on the
label itself, **not ancestors**. Toggling axes off can leave CSS2D labels
on-screen. Rewrite should walk parents or hide the label DOM.

### 2.4 CSS2D overlay

`CSS2DRenderer.js` is Three.js `examples/jsm/renderers/CSS2DRenderer.js`
rewritten as an IIFE that assigns `THREE.CSS2DObject` / `THREE.CSS2DRenderer`
(`CSS2DRenderer.js:157-159`). Loaded as a classic script after `three.min.js`
(`index.html:9-11`).

Init (`gamut_viewer.js:255-263`): absolute, `top/left 0`, `pointer-events: none`
so orbit still hits the WebGL canvas. Rendered every frame after the WebGL pass.

### 2.5 Profile mesh (`currentProfileMesh`)

Solid `THREE.Mesh`, `MeshLambertMaterial({ vertexColors: true, transparent: true,
opacity: 0.88, side: THREE.DoubleSide })`. Native `.gam` faces when present;
QuickHull fallback otherwise. See §4–5.

### 2.6 sRGB reference (`sRgbGroup`)

A `THREE.Group` of two children sharing one `BufferGeometry` (#185 component 2):

1. Faint fill: `MeshLambertMaterial({ color: 0x8899bb, opacity: 0.07,
   transparent, DoubleSide, depthWrite: false })`.
2. Structural outline: `EdgesGeometry(geometry, 15)` (15° coplanar threshold)
   + `LineBasicMaterial({ color: 0x6688aa, opacity: 0.55 })`.

Loaded from `fetch('assets/sRGB.gam')` at the end of `initGamutViewer`
(`loadSrgbReferenceGamut`, lines 742-752). **Adobe RGB was specified in #9 and
never shipped.**

### 2.7 Resize

`ResizeObserver` on `#gamutViewerContainer` updates camera aspect, renderer size,
and labelRenderer size. No `window.resize` listener.

### 2.8 Background

`scene.background = 0x0e0e14` matches `#gamutViewerContainer` CSS. `alpha: false`
on the renderer is required so WKWebView does not composite a white underlay.

---

## 3. `.gam` file parser

`parseGamutFile` (`gamut_viewer.js:447-509`) is the post-#179 parser. The
previous `parseCGATS` only read the first `BEGIN_DATA` (vertices), discarded
the triangle table, then handed `{L,a,b}` objects to QuickHull which indexes
`.x/.y/.z` → empty hull → blank scene.

### 3.1 Real Argyll format (`src/assets/sRGB.gam`)

Header (not parsed; ignored because `dataStarted` is false):

```
GAMUT
DESCRIPTOR "Argyll Gamut surface poligon data"
ORIGINATOR "Argyll CMS gamut library"
COLOR_REP "LAB"
GAMUT_CENTER "50.000000 0.000000 0.000000"
CUSP_RED / CUSP_YELLOW / … / CUSP_MAGENTA
# First come the triangle verticy location
NUMBER_OF_FIELDS 4
BEGIN_DATA_FORMAT
VERTEX_NO LAB_L LAB_A LAB_B
END_DATA_FORMAT
NUMBER_OF_SETS 448
BEGIN_DATA
0 53.23738 78.28787 62.14806
…
END_DATA
# And then come the triangles
NUMBER_OF_FIELDS 3
BEGIN_DATA_FORMAT
VERTEX_0 VERTEX_1 VERTEX_2
END_DATA_FORMAT
NUMBER_OF_SETS 892
BEGIN_DATA
13 1 46
…
END_DATA
```

Two `BEGIN_DATA`…`END_DATA` blocks. Block 1 = vertices (`index L a b`).
Block 2+ = 0-based triangle indices. Issue #179’s printer sample
(`xp_55_koala_satin.gam`) is the same shape: 739 verts, 1474 faces.

### 3.2 Algorithm (quote)

```js
const trimmed = raw.replace(/#.*$/, '').trim();  // strip inline comments
if (trimmed === '') continue;

if (trimmed.toUpperCase() === 'BEGIN_DATA') { dataBlock++; dataStarted = true; continue; }
if (trimmed.toUpperCase() === 'END_DATA')   { dataStarted = false; continue; }
if (!dataStarted) continue;

const parts = trimmed.split(/\s+/).map(Number);

if (dataBlock === 1) {
    // Vertex format: index L a b (index is usually ignored)
    const [_, L, a, b] = parts;           // VERTEX_NO discarded
    vertices.push([L, a, b]);
} else {
    faces.push([parts[0], parts[1], parts[2]]);
}
```

Rules:

- Hash comments stripped **even inside data blocks** (`# inline comment` test).
- `BEGIN_DATA` / `END_DATA` matched case-insensitively.
- Header keys (`COLOR_REP`, `NUMBER_OF_SETS`, `BEGIN_DATA_FORMAT`, …) skipped.
- Non-numeric data lines → warning, skip.
- Vertex arity < 4 or face arity < 3 → warning.
- Lab plausibility warning (does **not** drop the vertex):
  `L < 0 || L > 100 || Math.abs(a) > 128 || Math.abs(b) > 128`.
  Bundled sRGB cusp blue is `b* = -126.4162` (inside); a printer gamut can
  exceed ±128.
- Multiple face blocks are concatenated (`dataBlock >= 2`). Dual-table test
  covers this.
- Vertices with no faces → warning *“will compute convex hull on the fly.”*
- Zero `BEGIN_DATA` → warning *“file may be empty or not a valid Argyll .gam”*.

`VERTEX_NO` is discarded. Faces are assumed to index **push order** (Argyll
writes 0..N-1 sequentially). A non-dense index column would silently mis-bind.

### 3.3 Lab vs XYZ

`COLOR_REP "LAB"` is **not read**. Columns are always treated as L, a, b.
`iccgamut` default is Lab. If a rewrite (or a user) ever passed `iccgamut -x`
(XYZ), the viewer would plot XYZ as if it were Lab and colour it through
`labToSrgb`. There is no XYZ path.

### 3.4 Stub vs real sRGB.gam

`src-tauri/argyll/reference_gamuts/sRGB.gam` is **not** an Argyll gamut surface:

```
CGATS.17
NUMBER_OF_FIELDS 4
BEGIN_DATA_FORMAT
INDEX LAB_L LAB_A LAB_B
END_DATA_FORMAT
NUMBER_OF_SETS 8
BEGIN_DATA
0 0.0 0.0 0.0          # black
1 100.0 0.0 0.0        # white
2 53.2 80.1 67.2       # red cusp (approx)
…
END_DATA
```

8 points, **no face table**. The parser would emit 8 vertices + the hull-fallback
warning; QuickHull of 8 cusps is a coarse octahedron, not sRGB. The viewer
never loads this file. It `fetch`es `src/assets/sRGB.gam` (448/892, produced by
`iccgamut` on 2026-08-25). Rewrite: either delete the stub or generate it the
same way as the asset, and do not assume `reference_gamuts/` is the runtime
source.

---

## 4. Mesh generation: QuickHull vs ConvexGeometry

### 4.1 History

| Issue | What happened |
|---|---|
| #9 | Planned Delaunay on Lab point cloud + sRGB/AdobeRGB wireframes. |
| #57 | Viewer was a dead panel; v0.2 used 2D Delaunay on (a*, b*) flattening L*. |
| #89 | Replaced Delaunay with inlined 3D QuickHull (~270 lines in `gamut_viewer.js`); touch OrbitControls. `delaunator.min.js` deleted. |
| #117 | Proposed replacing the inline hull with Three r128 `ConvexGeometry` / `ConvexHull`, **or** vendoring `quickhull3d`. Optional. |
| #179 | Real `.gam` files already contain the surface triangulation. Parser was throwing it away and hulling `{L,a,b}` objects → empty mesh. |

**Current state:** native face indices are the primary path. QuickHull is only
the no-faces fallback. There is **no** `ConvexGeometry.js` / `ConvexHull.js` in
the tree (`src/js/vendor/` contains only `quickhull.js`). #117 was closed but
the code took the “vendor quickhull3d-like ESM” option, not Three’s addon.

### 4.2 `_buildGeometry` (`gamut_viewer.js:515-568`)

```js
if (vertices.length < 4) return null;

if (faces.length > 0) {
    // Native mesh: position [a, L, b] per vertex, Uint32 index from .gam
    posArr[i*3]   = a;   // X
    posArr[i*3+1] = L;   // Y
    posArr[i*3+2] = b;   // Z
    geometry.setIndex(new THREE.BufferAttribute(idxArr, 1));
    geometry.computeVertexNormals();
} else {
    const pts = vertices.map(v => ({ x: v[1], y: v[0], z: v[2] })); // a, L, b
    const hullFaces = computeQuickHull(pts);
    // Dedup by `${x}_${y}_${z}` string key while expanding hull faces
    // Then rewrite `vertices` from the position attribute as [L, a, b]
}
```

Critical #179 fix for the fallback: points **must** be `{x,y,z}` not `{L,a,b}`.
`quickhull.js:44` uses `pts[i].x`; undefined x made `minX === maxX` and returned `[]`.

### 4.3 `computeQuickHull` (`src/js/vendor/quickhull.js`)

Classic incremental convex hull (150 lines):

1. O(n²) duplicate filter, eps `1e-5` (#117 risk: density-50 clouds freeze here).
2. Extreme points: min/max X, then furthest from that line, then furthest from
   that plane → initial tetrahedron.
3. Outward winding via tetrahedron **centroid** (`createFace` flips if the
   centroid is in front). Horizon winding is recovered from this centroid, not
   the growing hull (#117 risk for re-entrant sets — moot for a true convex hull).
4. For each remaining point: collect visible faces (`n·(p-a) > 1e-9`), build
   horizon as edges that appear once (`uId+'_'+vId` via `pts.indexOf`, another
   O(n)), deactivate visible faces, fan new faces from horizon to the point.
5. Return `faces.filter(f => f.active)` as `{a,b,c}` point references.

A convex hull of a printer gamut **fills concavities** (dark cyan/magenta
indentations that #89 wanted to preserve). That is why native `.gam` faces are
the correct primary path: `iccgamut` already computed the (possibly non-convex)
surface. Hull is only for vertex-only clouds (the 8-cusp stub, or a future
`.ti3` point cloud).

`EdgesGeometry(geometry, 15)` on the sRGB mesh strips coplanar internal
triangle edges. Threshold 15° is a magic number from #185.

---

## 5. Per-vertex colouring from Lab

`_renderProfileGamut` (`gamut_viewer.js:623-667`) — **profile only**, not sRGB
reference (reference stays steel-blue `0x8899bb` / `0x6688aa`).

```js
const posAttr = geometry.getAttribute('position'); // laid out [a, L, b]
const colorArr = new Float32Array(posAttr.count * 3);
for (let i = 0; i < posAttr.count; i++) {
    const a_star = posAttr.getX(i);
    const L_star = posAttr.getY(i);
    const b_star = posAttr.getZ(i);
    const [r, g, b] = labToSrgb(L_star, a_star, b_star);
    colorArr[i*3]   = r / 255;
    colorArr[i*3+1] = g / 255;
    colorArr[i*3+2] = b / 255;
}
geometry.setAttribute('color', new THREE.BufferAttribute(colorArr, 1));
material = new THREE.MeshLambertMaterial({ vertexColors: true, opacity: 0.88, … });
```

`labToSrgb` (`color_convert.js:9-45`):

- D50 white `Xn=0.9642, Yn=1, Zn=0.8249` (ICC PCS).
- CIE Lab → XYZ (standard `δ = 6/29` piecewise cube).
- XYZ D50 → linear sRGB via a **Bradford-adapted D50→D65** matrix (not a raw
  D65 sRGB matrix — correct for ICC Lab).
- sRGB gamma, clamp 0–255, `Math.round`.

Out-of-gamut Lab (printer vertices outside sRGB) clips to the sRGB cube. That
is the intended diagnostic: the blob is “true colour” where representable and
clips where the printer exceeds sRGB — which is exactly when it pokes out of
the sRGB wireframe.

`colprof.js:206` still calls `loadGamutMesh(gamFilePath, 0x3b82f6)`. The second
arg is **ignored** (flat-blue leftover from pre-#185). Rewrite: drop it.

---

## 6. Controls

### 6.1 HTML overlay (`index.html:980-1038`)

Glassmorphic panel, `position: absolute; top/right: 12px` over
`#gamutViewerWrap`. Three layers, each a toggle + opacity slider:

| Control | Id | Default | Handler |
|---|---|---|---|
| Profile visibility | `chkProfileGamut` | checked | `toggleProfileGamut` |
| Profile opacity | `rngProfileOpacity` | 0.88 | `setProfileOpacity` |
| sRGB visibility | `chkSrgbReference` | checked | `toggleSrgbReference` |
| sRGB opacity | `rngSrgbOpacity` | 0.55 | `setSrgbReferenceOpacity` |
| Axes visibility | `chkLabAxes` | checked | `toggleAxes` |
| Axes opacity | `rngAxisOpacity` | 0.80 | `setAxisOpacity` |
| Reset | `btnGamutResetCamera` | — | `resetCamera` |

Hint text: “Drag to rotate • Scroll to zoom • Right-drag to pan” /
“Press R to reset”.

Wired once in `_wireToggles` (`gamut_viewer.js:791-831`). `togglesWired` is
never cleared on dispose.

### 6.2 Opacity idiosyncrasy (`setSrgbReferenceOpacity`, lines 700-710)

```js
child.material.opacity = child.material.opacity >= 0.5
    ? Math.max(0.05, Math.min(1, opacity))          // treated as edges
    : Math.max(0.02, Math.min(0.2, opacity * 0.2)); // treated as fill
```

Initial edges 0.55 ≥ 0.5, fill 0.07 < 0.5. **If the user drags the slider below
0.5, edges flip into the fill branch permanently** (next input sees 0.1 < 0.5).
Rewrite should tag the two materials, not infer role from current opacity.

`setProfileOpacity` also sets `transparent = opacity < 1`. `setAxisOpacity`
walks all children with a `.material` (lines, grid) but CSS2D labels have none.

### 6.3 Reset (R)

Two mechanisms:

1. Button `btnGamutResetCamera`.
2. `stage5.addEventListener('keydown', …)` when key is `r`/`R` and stage is not
   hidden (`gamut_viewer.js:822-829`).

`_onKeyDown` (`gamut_viewer.js:730-734`) is **dead code** — never registered.
`#stage-5` has **no `tabindex`**, so it will not receive `keydown` unless a
focusable descendant (slider, checkbox, button, or a form control earlier in
Stage 5) is focused. The button is the reliable path. Rewrite: listen on
`document` while Stage 5 is active, ignore events from text inputs.

### 6.4 Touch

Vendored `OrbitControls.js` is Three r128 (IIFE, assigns `THREE.OrbitControls`
and `THREE.MapControls` at the bottom). Touch is fully implemented
(`onTouchStart/Move/End`, `passive: false`, `preventDefault` on start).
Mapping used by the viewer:

- 1 finger → rotate
- 2 fingers → dolly + pan

Mouse: left rotate, wheel dolly, right pan. `renderer.domElement.style.touchAction
= 'none'` is required on WKWebView / mobile.

`OrbitControls` is **not** an ES module; it depends on global `THREE` from
`three.min.js` r128. A rewrite that npm-installs a newer three must vendor a
matching OrbitControls (and CSS2DRenderer) — the current files are frozen to r128.

---

## 7. `iccgamut` CLI flags

### 7.1 Current argv (#112 fix)

`commands.rs:684-690`:

```rust
pub fn build_iccgamut_args(resolved_path: &str) -> Vec<String> {
    vec![
        "-v".to_string(),
        "-d".to_string(),
        "10".to_string(),
        resolved_path.to_string(),
    ]
}
```

Locked by `test_build_iccgamut_args` (`commands.rs:1475-1478`):
`["-v", "-d", "10", "/path/to/profile.icc"]`.

Meaning:

| Flag | Meaning |
|---|---|
| `-v` | Verbose (stdout into the process log via ProcessManager). |
| `-d 10` | **Surface point density**, typical useful range ~1–10. Not a directory. |
| `{profile}` | Resolved `.icc`/`.icm` path. |
| *(cwd)* | Profile parent dir, so `{basename}.gam` lands next to the profile. Set via `ProcessManager::spawn(..., cwd)`, **not** via `-d`. |
| no `-w` | VRML not required; `.gam` is the default. |

`extract_gamut` (`commands.rs:694-731`) also swaps `.icc`↔`.icm` if the given
path does not exist, process id `iccgamut_{basename}`.

### 7.2 The `-d 50.0` bug (#112)

Pre-fix argv was `-v -d 50.0 {profile}`. Density 50 produces thousands of
vertices; QuickHull’s O(n²) duplicate filter then froze the UI. There was
historical confusion that `-d` meant “directory”. Directory is `cwd`. Do **not**
pass the parent path as `-d`. Do **not** revert to 50.

#179’s real printer file was generated with `-v -d 10` (739 verts / 1474 faces,
43.6 KB) — the density we want.

### 7.3 When it runs

1. **Stage 4 success** (`colprof.js:173-174, 197-215`): `triggerGamutExtraction`
   listens for `process:exit` on `iccgamut_{basename}`, then
   `loadGamutMesh(cwd/basename.gam)`. This often runs **while Stage 5 is still
   hidden**, so `scene` is null and `_renderProfileGamut` returns null. The
   `.gam` file is still written to disk.
2. **Stage 5 verify success** (`profcheck.js:626-635`): `loadGamutMesh` again.
   This is the path that actually puts the printer mesh on screen, assuming the
   user has opened Stage 5 (viewer inited) and then clicked Verify.

If the user opens Stage 5 *before* verifying, they see axes + sRGB only.
Navigating to Stage 5 does **not** auto-load an existing `{basename}.gam`.
Rewrite should load it in `ensureGamutViewer` once basename/cwd are known.

---

## 8. Fallback UI when WebGL is missing

`showGamutFallback` (`gamut_viewer.js:81-102`) wipes
`#gamutViewerContainer.innerHTML` and inserts:

```html
<div class="gamut-webgl-fallback" role="status">
  <p>…message…</p>
  <!-- optional --> <button class="secondary btn-md">Reload 3D view</button>
</div>
```

CSS (`main.css:1494-1511`): flex-centred, min-height 280px, same `#0e0e14`
background, muted text. Controls panel is a **sibling** of the container
(`#gamutViewerWrap` > container + panel), so the legend remains visible over
an empty/fallback view — another rewrite nicety: hide or disable it.

Messages:

| Trigger | Copy | Reload? |
|---|---|---|
| `webglAvailable() === false` | `WEBGL_UNAVAILABLE_MESSAGE` = “3D gamut viewer requires WebGL; the rest of ICCery still works.” | no |
| `initGamutViewer` throw | same `WEBGL_UNAVAILABLE_MESSAGE` | yes |
| `webglcontextlost` | “3D view lost its GPU context. Profiling stages still work.” | yes |

Reload: `disposeViewer(); ensureGamutViewer();`. Feature-detect failure sets
`gamutViewerUnavailable`, so a hypothetical reload would no-op until a full
page reload.

Intel Monterey < 13 also gets a session-once wizard banner
(`app.js:30-45`): “On this Mac the 3D gamut view may be unavailable…”

Init catch path removes a half-attached `renderer.domElement` before showing
fallback (`gamut_viewer.js:321-327`).

---

## 9. Tests

`src/js/gamut_viewer.test.js` — Node-runnable ESM (`node src/js/gamut_viewer.test.js`).

#212: previously crashed with `window is not defined` because `gamut_viewer.js`
top-level-dereferenced `window.__TAURI__.core`. Now guarded
(`gamut_viewer.js:5`):

```js
const invoke = typeof window !== 'undefined' && window.__TAURI__?.core?.invoke
    ? window.__TAURI__.core.invoke : null;
```

The test file polyfills `globalThis.window` / `document` **before** a dynamic
`await import('./gamut_viewer.js')` (static import is hoisted and would still
lose the race). Canvas `getContext` returns `null` so `webglAvailable()` is
false in Node.

Cases (`runAll`):

| Test | Asserts |
|---|---|
| `testParseGamutBasic` | 4 verts, 2 faces, 0 warnings |
| `testParseGamutDualTable` | two face `BEGIN_DATA` blocks concatenate to 2 faces |
| `testParseGamutWithComments` | `#` lines + `# inline comment` stripped |
| `testWebglAvailableFalseWithoutContext` | no context / no document → false |
| `testWebglAvailableTrueWithWebgl` | `getContext('webgl')` → true |
| `testConstrainedGpuPrefersBackendArch` | `aarch64` + MacIntel UA → **not** constrained; `x86_64` → constrained |
| `testConstrainedGpuIgnoresAppleSiliconUa` | ARM UA → not constrained |
| `testConstrainedGpuIntelMac` | Monterey Intel UA → constrained; x86_64 on Ventura still constrained |
| `testEnsureGamutViewerNoopsWithoutDom` | no Stage 5 / no THREE → `isGamutViewerReady() === false` |
| `testFallbackMessage` | copy contains “requires WebGL” |

**Not tested:** real `sRGB.gam` golden parse (448/892), Lab-bounds warnings,
empty file, XYZ, QuickHull tetrahedron/cube fixtures (#117 AC),
`labToSrgb` colours, `loadGamutMesh`, context-lost, opacity slider, R-key,
`build_iccgamut_args` is a **Rust** test not a JS one.

Auto-run:

```js
if (typeof process !== 'undefined' && process.argv[1]?.endsWith('gamut_viewer.test.js')) {
  runAll();  // throws if any fail → non-zero exit
}
```

---

## 10. Idiosyncrasies / rewrite traps

1. **Do not create WebGL on `DOMContentLoaded`.** Stage 5 starts `.hidden`.
   `ensureGamutViewer` + one rAF + hidden-class re-check is the contract (#225).
2. **Pause rAF on leave; do not necessarily dispose.** Scene stays so Stage 4’s
   late `loadGamutMesh` can work *if* Stage 5 was visited first — which it
   usually is not. Safer rewrite: queue the `.gam` path and load on first
   `ensureGamutViewer`.
3. **Native faces > hull.** A convex hull of Lab points is the wrong surface
   for a printer gamut. Only hull when the face table is missing.
4. **Position layout is `(a, L, b)` not `(L, a, b)`.** Colour, hull fallback,
   and CSS2D all depend on this. Mixing them was the #179 blank-scene bug.
5. **`VERTEX_NO` is ignored; faces are 0-based push-order.** Fine for Argyll.
6. **`COLOR_REP` is ignored.** Lab only.
7. **Two sRGB.gam files, only one is real.** Runtime = `src/assets/sRGB.gam`
   (448/892). `src-tauri/argyll/reference_gamuts/sRGB.gam` is an 8-point stub.
8. **No Adobe RGB overlay** despite #9.
9. **`loadGamutMesh(path, 0x3b82f6)`** — extra colour arg is dead.
10. **sRGB opacity slider infers fill vs edges from `opacity >= 0.5`.** Breaks
    after the user goes below 0.5.
11. **CSS2D labels ignore parent `visible`.** Axis toggle is incomplete.
12. **R-key is bound to `#stage-5` without `tabindex`.** `_onKeyDown` is unused.
13. **Duplicate CSS** for `#gamutViewerContainer`: `main.css:835-842`
    (`height: 400px; background: #111116`) and `main.css:1480-1486`
    (`min-height: 420px; background: #0e0e14`). Later rules win for
    background; `height: 400px` + `min-height: 420px` → 420px.
14. **Three r128 via `<script>` + IIFE addons.** Not ESM. `gamut_viewer.js` is
    ESM and talks to `window.THREE`. A bundler rewrite must keep that seam or
    import matching addons.
15. **`invoke` is null outside Tauri.** `loadGamutMesh` will throw if called
    from tests / a browser without the polyfill.
16. **`togglesWired` / `gamutViewerUnavailable` survive `disposeViewer`.**
17. **`GridHelper` still present** after #185 said to remove it.
18. **QuickHull O(n²) duplicate filter** — keep density at 10, never 50 (#112).
19. **`atob(read_file_base64)`** assumes the `.gam` is ASCII. It is (CGATS).
    Do not switch to a UTF-16 profile dump without a TextDecoder.
20. **DoubleSide Lambert** hides winding errors in Argyll’s triangle table.
    If a rewrite uses FrontSide, audit winding.
21. **`failIfMajorPerformanceCaveat: false`** — accept software GL rather than
    crash Monterey.
22. **No `resumeGamutViewer` call site.** `ensureGamutViewer` already restarts
    the loop when `gamutViewerReady`.
23. **Feature-detect prefers webgl2** but r128 `WebGLRenderer` still opens a
    WebGL1 context unless `r128` is given `{ capability: … }`. Detecting webgl2
    does not mean Three uses it.
24. **Stage 5 verify is what actually shows the printer mesh**, not Stage 4
    extraction and not merely opening the viewer.
25. **Cusp vertices in the header** (`CUSP_RED` etc.) are not used. They are
    duplicated as the first few `BEGIN_DATA` rows. A rewrite could label cusps
    but the current viewer does not.

---

## 11. Public API surface (for a rewrite to preserve)

```js
setGpuHints(hints)                 // { arch, os, macosMajor }
isGamutViewerReady()
webglAvailable(doc?)
isLikelyConstrainedGpu(hints?)
ensureGamutViewer()                // Stage 5 entry
pauseGamutViewer()                 // Stage 5 leave
resumeGamutViewer()                // unused
initGamutViewer()                  // internal-ish but exported
parseGamutFile(text) → { vertices, faces, warnings }
resetCamera()
setProfileOpacity(0..1)
setSrgbReferenceOpacity(0..1)
setAxisOpacity(0..1)
loadSrgbReferenceGamut()
loadGamutMesh(gamFilePath) → Mesh|null
toggleSrgbReference(visible)
toggleProfileGamut(visible)
toggleAxes(visible)
WEBGL_UNAVAILABLE_MESSAGE
```

HTML ids that `_wireToggles` hard-codes: `chkProfileGamut`, `chkSrgbReference`,
`chkLabAxes`, `btnGamutResetCamera`, `rngProfileOpacity`, `rngSrgbOpacity`,
`rngAxisOpacity`, `gamutViewerContainer`, `stage-5`.

---

## 12. Issue → code checklist

| Issue | Status in tree |
|---|---|
| #9 3D Lab viewer | Shipped; no Adobe RGB; Delaunay replaced. |
| #57 dead panel | `extract_gamut` + `loadGamutMesh` wired from colprof + profcheck. Stage 4 load still races init. |
| #89 3D hull + touch | Hull vendored; OrbitControls touch live; Delaunay gone. |
| #112 `-d 50` | Fixed to `-d 10`; Rust unit test. |
| #117 ConvexGeometry | Not done; `vendor/quickhull.js` instead. Native faces make this low-priority. |
| #179 blank mesh + 0.00 ΔE | `parseGamutFile` uses both tables; points passed as `{x,y,z}`. (Profcheck regex is out of scope here.) |
| #185 axes / EdgesGeometry / vertex colour / legend | All present (GridHelper kept; CSS2D parent-visibility bug). |
| #212 Node test crash | Polyfill + dynamic import + `typeof window` guard. |
| #225 Monterey WebGL | Lazy ensure, feature-detect, pause rAF, context-lost, low-power flags. |
| #147 compare + inspect | macOS native: layer toggles (`gamutLayer-*`), compare slot (one extra profile or `.gam`), click/typed-Lab containment, TIFF pixel sample. |

---

## 13. macOS rewrite notes (#28, #147)

The native viewer (`Sources/ICCery/GamutView.swift` + `GamutViewModel`) keeps
the v1 contract points that matter — `(a*, L*, b*)` axes, camera home
(180,120,180) lookAt (0,50,0), R resets via a local `NSEvent` monitor, native
faces only — and adds the compare/inspect layer model:

- **Layers.** `NamedGamut` (reference / profileA / profileB). sRGB cannot be
  removed, only hidden. The compare slot holds exactly one profile; picking a
  third replaces it and posts `gamutNoticeText`.
- **Toggles hide, not unload.** `visibleIDs` maps to `SCNNode.isHidden`; the
  scene is built once and a checkbox never resets the camera.
- **Containment.** `GamutGeometry.containment` ray-casts the face table
  (`GamutVertex.position` space) with off-axis retries on edge hits; no faces
  → `.unknown`. `GamutGeometry.volume` sums signed tetrahedra from the vertex
  centroid (Lab-cubic); the `vol % of sRGB` clause only prints when both
  volumes are finite and > 0.
- **Inspect.** Click a mesh (hit-test in the `SCNView` coordinator on
  mouse-up, never a ZStack tap gesture), type Lab, or sample a TIFF pixel.
  Per-layer in/out/? + swatch; `gamutInspectApprox` marks samples that went
  through `ApproximateLab` (fixed-matrix sRGB→Lab D50, **not** ColorSync, no
  CMM).
- **Fallback.** No GPU → `gamutViewerUnavailable` text replaces the scene;
  layer toggles stay visible but disabled; the representable is never
  respawned in a loop.
- **iccgamut** still runs only as the bundled sidecar, `-v -d {density}`
  (density 10 = surface density, not a directory). Failure is an in-sheet
  info notice — sRGB + profile A stay loaded (#24).
