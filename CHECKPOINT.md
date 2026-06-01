# CHECKPOINT — cliamp-plugin-nova

> Transient rolling work-log. DURABLE design rules live in `AGENTS.md` (read it
> first — it never rolls over). Prior history archived in
> `CHECKPOINT.2026-05-30-01.md` (and earlier rollovers).

**Last commit:** 91f86c5 plus uncommitted predator theme.
**Branch:** master. **Repo:** github.com/8bit64k/cliamp-plugin-nova (PRIVATE).
**Local dir:** /home/nick/builds/cliamp-plugin-nova/
**Entry file:** nova.lua (repo root). Single Lua file, no require/helpers.

---

## Session 2026-05-31 — predator theme (uncommitted)

Added predator theme to PRESETS table — iconic Predator thermal-vision heatmap.
11-stop ANSI 256 glow ramp + 4-stop overdrive:

- glow: 17, 21, 39, 46, 112, 142, 184, 220, 208, 196, 231
  (deep indigo -> royal blue -> cyan -> green -> lime -> olive ->
   yellow-green -> yellow -> dark orange -> red-orange -> pure white)
- overdrive: 196, 160, 125, 231
  (red-orange -> crimson -> magenta-red -> white)

Changes:
- nova.lua: predator preset inserted after ember
- README.md: theme list updated to include ember + predator
- Verified via render harness: all 6 scenes, no overflow, ANSI present
- Not yet committed — deferring to Nick

---

## What this is (current, accurate)

A cliamp Lua **visualizer** that renders a **braille wall** reacting to the
10-band EQ. The wall is mapped into 10 concentric rings (band 1 = 32 Hz bass at
center, band 10 = 16 kHz treble at edge). Each ring RECOLORS by its level on a
themed ramp AND braille glyphs THICKEN (gain dots) as they heat. As of 2026-05-30
the wall is **generated procedurally** — no art file needed.

- Render call: `p:render(bands, frame, rows, cols)` — `bands` 1-indexed table,
  MUST return a string (returning non-string = cliamp silently reuses last frame).
- cliamp ticks a visualizer at **20 FPS** while playing (TickFast 50ms; TickSlow
  200ms/5fps when paused/overlay). Source: `~/builds/cliamp/ui/tick.go` +
  `luaModeDriver` in `ui/visualizer.go`.
- cliamp = **gopher-lua (Lua 5.1)**: NO bitwise ops (`>> << | &`), no bit32. All
  bit math is arithmetic on powers of two. Local `lua` is 5.5 and WILL parse
  bitops fine while the host silently fails to load them — always write 5.1-safe.
- Errors go to `~/.config/cliamp/plugins.log` as `[nova] error: ...`, NEVER the UI.
- Sibling: `~/builds/cliamp-plugin-tubeamp/` (shipped v1.2.0; its docs/DESIGN.md is
  the gold-standard plugin doc). Shares the amber glow ramp = one plugin family.

---

## Session 2026-05-30 — what shipped (all on master, all verified)

Four features built this session, in order. All knobs default to no-change
behavior. Reusable test/bench tooling lives in `scratchpad/` (gitignored).

### 1. Canvas cap — `max_cols` / `max_rows` (default 0 = unlimited)
Render cost is almost PERFECTLY LINEAR in drawn cells (`draw_w*draw_h`), ~0.41
ms/1000 cells flat across a 73x pane-size range — so the ~20% CPU overage vs
native visualizers is the per-cell loop at large `fit=fill` panes, not fixed
overhead. The cap clamps the DRAWN grid; art is then centered in the full pane via
existing letterbox padding. 4K 320x80 capped to 160x48 = -69% cost. TRADE: on a
huge `fit=fill` pane the wall becomes a CENTERED BLOCK, not edge-to-edge (can't
fill more columns than you draw). Test: `scratchpad/test_cap.lua`.

### 2. Render rate — `render_rate` (0.25..1.0, default 1.0 = every frame)
FRACTION of frames actually rendered (NOT a skip count — 8bit64k finds the 0->1
dial more natural). 1.0 = every frame (~20 FPS); 0.5 = ~10 FPS; 0.25 = ~5 FPS.
Un-rendered frames REUSE the cached output string. Cuts AVERAGE cost ~(1-rate) at
ANY pane size AND keeps `fit=fill` edge-to-edge (trades refresh rate, not
coverage). Values <0.25 clamp to 0.25 (rate 0 = "never render" is meaningless).
Maps internally to integer skip = `round(1/rate)-1`. Audio state still advances
every frame (envelope never freezes); a bass-transient ONSET force-renders even on
a skip frame so kick FLARES are never dropped; cache invalidated on resize.
Measured: 0.5 -51%, 0.33 -68%, 0.25 -75%. COMBINED cap160x48 + rate0.33 on 4K:
9.88 -> 1.07 ms avg (-89%). Test: `scratchpad/test_frameskip.lua` (still uses the
old internal name "frameskip"; the config key is `render_rate`).

### 3. Toward-center density fill
Braille glyphs now accrete dots TOWARD the pane center as they heat (was bottom-up
regardless of position). Reinforces the radial ring structure. Cell left of center
fills from its right edge inward; above-center fills bottom-up; corners from the
dot nearest center. Implemented as 9 direction-specific orders
`FILL_ORDERS[dirx][diry]` (signs in {-1,0,1}), chosen per cell by SIGN of offset
from center; `thicken()` takes `(fill_order, dkey)` and caches per direction
(`thicken_cache[dkey][base_cp][add]`, no per-frame bit loop). NOT a knob — it's
the correct default; folded under existing `density` toggle. Promoted to AGENTS.md
(durable). Test: `scratchpad/test_center_fill.lua`; visual `scratchpad/show_final.lua`.

### 4. Procedural wall — no art file needed
`generate_wall()` fills `art_cells`/`art_code` with a single base glyph at a fixed
35x188 source grid (matches old dots_braille dims so fit behaves identically); the
existing fit/downscale/ring/density path renders it like a file. Config
`start = "black" | "stipple"`, **default "black"** (8bit64k's pick, "it's
beautiful"):
- `black` = base ⠀ (U+2800, empty) — dots bloom in from nothing toward the lit core.
- `stipple` = base ⠡ (U+2821) — faint resting texture that thickens.
- Unknown values fall back to stipple.
`art_path` KEPT as an optional override (set => load file; unset => generate). The
default experience needs ZERO files. Sentinel for "wall ready?" is `art_cells`
(the generator sets art_cells/art_code but NOT art_lines — art_lines is file-path
only). The 5 generated wall files (dots_braille, dots_dense_braille, noise_braille,
weave_braille, art_max) MOVED to `scratchpad/` (gitignored) + removed from repo.
Portrait files (`crt.txt`, `ruby.txt`, `ruby_ascii.txt`) LEFT at root — different
lineage, headed for a future SEPARATE portrait plugin (nova is braille-wall ONLY).
Test: `scratchpad/test_generator.lua` (renders both starts with fs stubbed to
fail), `scratchpad/verify_default.lua` (empty config => black).

README rewritten this session: leads with procedural wall (no file), `art_path`
optional, documents `start` + the perf knobs. Accurate to current plugin.

---

## RESUME HERE — next session

1. **8bit64k is testing the whole batch live** (cap, render_rate, toward-center
   density, black/stipple wall). On the laptop: `git fetch origin && git reset
   --hard origin/master` then `cp nova.lua ~/.config/cliamp/plugins/nova.lua`,
   restart cliamp. No config needed — renders the black bloom wall out of the box.
   Use `color_mode = glow` (NOT passthrough — passthrough skips color AND density).
2. **DOCS LOOP STILL OPEN** (was being batched at session end, budget ran out):
   - `docs/DESIGN.md` not yet updated for this session's 4 features (still
     describes old bottom-up fill + file-required model). README IS updated.
   - The `cliamp-plugin-development` SKILL still documents the old bottom-up
     density fill and file-required wall — update its density + art-pipeline
     sections to reflect toward-center fill and the procedural generator.
   - Optional: fold a git push-verification lesson into the skill — TWICE this
     session a commit went out with an incomplete staged set (only file deletions,
     not nova.lua) because `git add` was assumed instead of verified. Always
     check `git diff --cached --stat` matches the commit message BEFORE committing,
     and `git show --stat` after, before pushing.
3. **Then back to the tuning backlog** (see below). #4 dead_zone is flagged PRIORITY.

---

## Tuning backlog (unbuilt)

- **#4 DEAD ZONE — SHIPPED (1dd55a4).** `dead_zone` knob clamps bands below threshold
  to 0. Default 0 (off). Try 0.08-0.12.
- **#3 Gamma / response curve.** Shape the level→brightness mapping.
- **#5 Aspect ratio knob.** Currently x scaled 0.5 for ~2:1 cell aspect.
- Defaults (flare onset margin 0.18 / baseline EMA 0.05, density attack 0.6 /
  release 0.15) are reasoned but NOT yet validated against lots of real music —
  tune by ear when ready.

### Deferred (bottom of list)

- **Truecolor 24-bit ramp.** Removes the 11-stop brightness ceiling. Detect
  `COLORTERM=truecolor` via `os.getenv`.
- **Ring count.** Staying fixed at 10 — 1:1 mapping with cliamp's 10-band EQ
  is the correct call. Defer until there's a compelling reason to break it.

---

## Full current config surface (as of 91f86c5)

```toml
[plugins.nova]                 # entire block OPTIONAL — defaults render the black wall
start = "black"                 # "black" (empty, blooms — default) | "stipple" (faint texture)
# art_path = "/abs/path.txt"    # OPTIONAL override — load a custom ASCII/braille file
color_mode = "glow"             # "glow" | "mono" | "passthrough" (passthrough = raw glyphs, no color/density)
ring_shape = "square"           # "square" | "diamond" | "circle" | "cycle"
cycle_seconds = 20              # cycle mode: seconds per shape (min 2)
fit = "contain"                 # "contain" (aspect, letterboxed) | "fill" (stretch to pane)
ring_blend = true               # smooth radial gradient between rings (default on)
density = true                  # braille glyphs thicken toward center as they heat (default on)
density_attack = 0.6            # dots fill speed (high=snappy; 1.0=instant)
density_release = 0.15          # dots shed speed (low=lingering CRT-phosphor trail)
theme = "amber"                 # "amber" | "crt" | "vantablack" | "aurora" (4x 11-stop ANSI ramps)
mono_color = 11                 # ANSI 256 index for mono mode
attack = 0.55                   # color smoothing attack
release = 0.18                  # color smoothing release
overdrive = 0.78                # bass band level above which a flare can fire
overdrive_decay = 0.82          # bass flare tail: fraction of heat retained/frame (0=snap)
overdrive_bleed = true          # peak bass flare bleeds warmth into the next ring outward
tilt = 0.0                      # per-band boost toward treble (try 0.5 if outer rings feel dead)
max_cols = 0                    # cap drawn width (0=unlimited) — perf on huge fit=fill panes
max_rows = 0                    # cap drawn height (0=unlimited)
render_rate = 1.0               # fraction of frames rendered, 0.25..1.0 (1.0=every frame)
```

---

## Architecture quick map (nova.lua, ~870 lines)

- **Config reads** (top): all via `clean()` (strips leaked TOML `#` comments);
  numerics via `tonumber(clean(...))`; bools parsed defensively (string or real).
- **DIST table**: square=Chebyshev / diamond=Manhattan / circle=Euclidean; ONE
  dispatch reused for both max_d and per-cell so the metric can't diverge.
  `ring_shape="cycle"` rotates via `os.time()`.
- **Braille density**: `FILL_ORDERS[dirx][diry]` (9 toward-center orders),
  `thicken(base_cp, level, fill_order, dkey)` memoized per direction. 5.1-safe
  arithmetic only.
- **PRESETS**: `{glow=11 colors, overdrive=4 colors}` per theme; single swap point
  (`active_preset`) so upstream `theme_colors()` integration is a one-line change.
  `glow_color` uses ROUND not floor for the ramp index (else top stop unreachable).
- **generate_wall()** (no file) and **load_art()** (file path, lazy-loaded on first
  render if init didn't fire). Sentinel = `art_cells`.
- **render()**: advance smoothing -> build `effective[]` (smoothed + overdrive heat
  + bleed) once/frame -> advance `dens[]` envelope -> frame-skip gate -> canvas cap
  -> fit -> per-cell loop (ring distance -> blend/snap level -> color + toward-center
  thicken). Hot loop optimized (precomputed ANSI escapes, memoized thicken, hoisted
  math locals, append-index tracking).

---

## Conventions (from /home/nick/builds/AGENTS.md)

- Git author = **8bit64k ALWAYS**, never Nick:
  `git -c user.name=8bit64k -c user.email=8bit64k@users.noreply.github.com ...`
- `scratchpad/` is gitignored — harnesses, probes, the moved wall .txt files,
  source images stay local; never part of a release.
- cliamp does NOT hot-reload — re-`cp nova.lua` + restart after every change.
- Verify end-to-end, not just syntax. Run with PLAIN `lua` for tests, NOT luajit
  (host has no JIT — luajit perf numbers mislead; relative cost only).
- 8bit64k reviews visual/terminal software LIVE himself — give pull/install steps,
  don't over-preview. Fine with git history rewrites/force-push on this private
  repo (wants clean history); he reconciles with `git reset --hard origin/master`.
