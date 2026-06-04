# DESIGN.md — cliamp-plugin-nova

> Braille-wall visualizer for cliamp: a dense braille texture reacts to the 10-band EQ.
> Each concentric ring recolors by band level on themed ANSI 256 ramps, and braille
> glyphs thicken toward center as they heat — the wall gains matter on peaks, not just
> brightness. Procedurally generated (no art file needed).
> This document is the authoritative reference for the plugin's design, constraints,
> and integration points. An agent dropping into this project should be able to read
> this file and modify the plugin confidently without reading the upstream cliamp
> source first.

---

## Table of contents

1. [What this plugin is](#1-what-this-plugin-is)
2. [Upstream project (cliamp) — what you need to know](#2-upstream-project-cliamp--what-you-need-to-know)
3. [The cliamp plugin system, condensed](#3-the-cliamp-plugin-system-condensed)
4. [Visualizer plugin API contract](#4-visualizer-plugin-api-contract)
5. [Design goals & visual brief](#5-design-goals--visual-brief)
6. [Implementation walkthrough](#6-implementation-walkthrough)
7. [Color system (themes)](#7-color-system-themes)
8. [State & per-frame timing](#8-state--per-frame-timing)
9. [Configuration surface](#9-configuration-surface)
10. [Constraints & sandbox boundaries](#10-constraints--sandbox-boundaries)
11. [Testing & local verification](#11-testing--local-verification)
12. [Installation & distribution](#12-installation--distribution)
13. [Known limitations & ideas for v2](#13-known-limitations--ideas-for-v2)
14. [File map](#14-file-map)
15. [Agent handoff checklist](#15-agent-handoff-checklist)

---

## 1. What this plugin is

`nova` is a custom visualizer plugin for cliamp that renders a **braille wall**
reacting to the 10-band EQ feed. It is written in Lua (~1268 lines, single file),
runs inside cliamp's sandboxed `gopher-lua` VM, and uses ANSI 256-color escape
sequences to draw themed radial rings where bass = center and treble = edge. The
wall is **generated procedurally** — no art file required. Config key `art_path`
provides an optional override to drive a custom ASCII/braille file instead.

It is the active visualizer sibling to `cliamp-plugin-tubeamp` (shipped v1.2.0)
and was renamed from `cliamp-plugin-dance` on 2026-05-31 after a scope decision:
nova is braille-wall only; ASCII portrait art will be a separate plugin.

**Repo:** `8bit64k/cliamp-plugin-nova` (private during QA)
**Install path:** `~/.config/cliamp/plugins/nova.lua`
**cliamp visualizer name:** `nova` (cycle to it with `v` in the player)

### Feature summary (v0.1)

- **Procedural braille wall** — `start = "black"` (empty canvas, dots bloom from
  silence) or `"stipple"` (faint resting texture). `art_path` for custom files.
- **9 color themes** — amber, crt, vantablack, whitehot, blackhot, redhot,
  orangehot, aurora, ember, predator, flan. All 11-stop ANSI 256 glow + 4-stop
  overdrive ramp. (redhot + orangehot added June 2 from laptop.)
- **7 ring shapes** — square (Chebyshev), diamond (Manhattan), circle (Euclidean),
  squircle (p=4 Minkowski), wings (vertical stripes), layers (horizontal strata),
  compass (four-pointed star). `ring_shape = "cycle"` auto-rotates all 7.
- **Braille density mutation** — glyphs gain dots toward center as they heat,
  with a separate attack/release envelope (phosphor persistence). 9 directional
  fill orders so dots always accrete toward center regardless of quadrant.
- **Density bleed** — overdrive transients thicken adjacent rings +1 and +2
  (mechanical bulge travels further than color heat), sharing the overdrive
  decay clock so the two channels read as one percussive event.
- **8 behaviour presets** — default, punch, ethereal, retro, plasma, ghost, bloom,
  tacutacu. One-knob feel selection: each bundles dynamics + theme + ring_shape.
  `cycle_presets = true` auto-rotates through all 8 for hands-free review.
- **Performance controls** — `render_rate` (fraction of frames rendered, 0.25–1.0)
  and `max_cols`/`max_rows` (canvas cap) for large fit=fill fullscreen panes.
- **Debug footer** — shows preset + theme + density bleed indicator ("BLD") on the
  bottom row when `debug = true`.

---

## 2. Upstream project (cliamp) — what you need to know

### What cliamp is

cliamp is a Bubbletea-based terminal music player inspired by Winamp. Written in
Go. Plays local files, HTTP streams, podcasts, and content from many providers.

**Repo:** https://github.com/bjarneo/cliamp
**Site:** https://cliamp.stream
**Built with:** Bubbletea (TUI), Lip Gloss (styling), Beep (audio), gopher-lua (plugin VM)

### Local checkout

The upstream is cloned at `~/builds/cliamp/` for reference. Read the following
files when you need ground truth:

| Path | What's in it |
|------|--------------|
| `~/builds/cliamp/docs/plugins.md` | User-facing plugin API reference — authoritative spec |
| `~/builds/cliamp/luaplugin/visualizer.go` | Go-side visualizer plugin host — defines render contract |
| `~/builds/cliamp/luaplugin/luaplugin.go` | Plugin manager: registration, lifecycle, VM-per-plugin isolation |
| `~/builds/cliamp/luaplugin/sandbox.go` | What's removed/restricted in the Lua sandbox |
| `~/builds/cliamp/ui/visualizer.go` | Visualizer driver that calls into Lua via `RenderVis` |
| `~/builds/cliamp/ui/vis_*.go` | 30+ first-party reference visualizer implementations |
| `~/builds/cliamp/ui/tick.go` | Frame cadence constants (`TickFast = 50ms`, `TickSlow = 200ms`) |

### The 10-band EQ

cliamp ships a 10-band parametric EQ with these center frequencies, in order:

| Index (Lua 1-based) | Frequency |
|---------------------|-----------|
| 1 | 32 Hz |
| 2 | 64 Hz |
| 3 | 125 Hz |
| 4 | 250 Hz |
| 5 | 500 Hz |
| 6 | 1 kHz |
| 7 | 2 kHz |
| 8 | 4 kHz |
| 9 | 8 kHz |
| 10 | 16 kHz |

The same band layout is used for the spectrum visualizer feed — the `bands` table
passed to `p:render(...)` is normalized FFT energy in those 10 buckets, range
0.0 to 1.0 each. Bands are already log-magnitude scaled and pre-smoothed by
cliamp's analysis driver. The plugin does its own additional smoothing pass on
top for the asymmetric attack/release tube-like feel, and for density's separate
envelope.

### Audio analysis pipeline (relevant facts)

- Bands are already log-magnitude scaled (`(10*log10(sum) + 10) / 50`, clamped
  0..1) — the plugin sees a perceptually reasonable spectrum, not raw power.
- `frame` counter is monotonic and resets on visualizer (re-)selection.
- You do **not** need to do dB conversion, smoothing, or FFT in the plugin.

---

## 3. The cliamp plugin system, condensed

### Plugin types

| Type | Purpose | Callback shape |
|------|---------|----------------|
| `hook` | Event-driven (track.change, playback.state, app.start, app.quit, track.scrobble) | `p:on(event, fn)` — async, 5s timeout |
| `visualizer` | Per-frame rendering | `p:render(bands, frame, rows, cols)` — sync, 10ms budget |

### Loading

- Plugins live at `~/.config/cliamp/plugins/`.
- Each `.lua` file is loaded into its own `gopher-lua` VM at startup.
- A plugin is recognized only if it calls `plugin.register({...})`.
- VMs are isolated — a crash in one cannot affect another or the player.
- Render errors fall back to the previous frame silently.

### Registration shape

```lua
local p = plugin.register({
    name        = "nova",
    type        = "visualizer",
    version     = "0.1.0",
    description = "Braille wall visualizer — EQ-driven glow with presets, themes, and density mutation",
})
```

Callbacks: `p.render` (required), `p.init` (optional, called once on selection),
`p.destroy` (optional, called on deselection).

### Frame cadence

- `TickFast = 50ms` (20 FPS) when playing and foreground.
- `TickSlow = 200ms` (5 FPS) when paused or overlay open.
- Render budget: 10ms wall time per call.

---

## 4. Visualizer plugin API contract

```lua
function p:render(bands, frame, rows, cols)
    --   bands : table { [1]=0.0..1.0, ..., [10]=0.0..1.0 } — 1-indexed, 10-band normalized spectrum
    --   frame : monotonic counter, resets on visualizer (re-)selection
    --   rows  : terminal rows available to the visualizer
    --   cols  : terminal columns available to the visualizer
    -- returns: multi-line string (newline-separated). ANSI escapes pass through.
end
```

### Hard rules

- Return value MUST be a string. `nil`, `false`, or non-string → silent frame reuse.
- ANSI 256-color escapes pass through Bubbletea — full ANSI 256 is safe.
- Render is serialized per-plugin (host mutex); state mutation needs no locks.
- 10ms per call budget.
- `init(rows, cols)` is optional; runs once on selection.
- `destroy()` is optional; runs once on deselection.

### Sandbox restrictions

- No `os.execute`, no `io.*`, no `dofile`, no `loadfile`.
- File reads from ANY path (1 MB cap). Writes restricted to `/tmp/`,
  `~/.config/cliamp/`, `~/.local/share/cliamp/`, `~/Music/cliamp/`.
- Network only via `cliamp.http` (5s timeout, 1MB body cap).
- `os.time`, `os.date`, `os.clock`, `os.getenv` are kept — but `os.execute`,
  `os.remove`, `os.rename`, `os.exit`, `os.setlocale`, `os.tmpname` are stripped.
- **gopher-lua is Lua 5.1** — no bitwise operators (`>>`, `<<`, `|`, `&`) and no
  `bit32`. All bit work must use plain arithmetic on powers of two. Local `lua`
  may be 5.3+ and parse bitops fine; the host would silently fail to load them.
  This is the single most dangerous invisible footgun.

---

## 5. Design goals & visual brief

### Brief (from user)

Originally nicknamed "dance" — an ASCII/braille visualizer. Evolved into nova
after the discovery that a uniform braille wall under concentric ring coloring
+ density mutation reads as a genuine standalone visualization, not just "a
picture reacting to EQ."

### Concrete design goals

1. **Concentric rings, bass at center** — band 1 (32 Hz) drives the innermost ring,
   band 10 (16 kHz) the outermost. The wall is mapped into those rings so color
   and density radiate from the center outward.
2. **Multiple ring shapes** — square (default), diamond, circle, and four more.
   Each is a pure distance metric in a dispatch table, so shape selection is a
   one-line swap with zero downstream changes.
3. **Color themes from the tubeamp family** — reuse the same ANSI 256 convention
   so the plugin siblings feel consistent. 11-stop glow + 4-stop overdrive ramp
   per theme.
4. **Braille density mutation** — glyphs don't just recolor; they THICKEN. Dots
   OR into the base glyph as level rises, ending at solid `⣿` (U+28FF). Dots fill
   TOWARD CENTER (not always bottom-up) so the accretion reinforces the radial
   structure. Separate attack/release envelope (phosphor persistence) so dots pop
   fast and melt slow.
5. **Density bleed** — an overdrive transient not only spills color into adjacent
   rings (+1) but also thickens their glyphs (+1 and +2, because mechanical
   deformation travels further than color heat). Shares the overdrive decay clock
   so both channels read as one percussive event.
6. **Transient-triggered overdrive** — flare fires on a bass ONSET (kick drum),
   not on a sustained high level. Uses a slow baseline EMA + onset margin. The
   flare latch-and-decays so it flashes and fades.
7. **One-knob presets** — a user shouldn't need to tune 15 dynamics knobs. Eight
   curated presets bundle theme + ring_shape + all dynamics into a single feel.
   Individual TOML keys override preset values.
8. **Procedural wall, no file dependency** — the default wall is generated on
   load. No art file to copy or configure. `art_path` is an optional override.

### Non-goals

- ASCII portrait art — scoped out to a future separate plugin. Nova is braille-wall
  only. Don't re-add portrait-preservation hedging.
- Positional jitter / art translation — density mutation displaced this. Motion is
  shelved.
- Truecolor / 24-bit color — ANSI 256 only, matching the tubeamp family.
- Per-frame spatial animation beyond density. The art canvas is fixed; only color
  and glyph dots react.

### Visual model

```
Pane center = bass (ring 1, band 1 = 32 Hz)
│
├── ring 1: 32 Hz  (innermost, hottest on bass)
├── ring 2: 64 Hz
├── ring 3: 125 Hz
├── ...
├── ring 8: 4 kHz
├── ring 9: 8 kHz
└── ring 10: 16 kHz (outermost, lights on treble/hi-hats)

Ring boundaries are leveled by the selected distance metric.
ring_blend = true (default) interpolates between adjacent rings for smooth gradients.
ring_blend = false gives hard stepped ring boundaries.

Density: dots fill TOWARD CENTER. Cell left of center fills rightward.
Cell above center fills upward. Corners fill from the dot nearest center.
Overdrive density bleed: bass transient thickens +1/+2 rings outward,
reinforcing the radial bulge effect.
```

---

## 6. Implementation walkthrough

Everything lives in **`nova.lua`** (single file, ~1268 lines). No modules, no
requires, no helper files. Section-by-section:

### Top of file: registration (lines 12–17)

Standard visualizer registration. `version = "0.1.0"`.

### Configuration pulls (lines 19–198)

Every config value is read through `clean()` which strips trailing `#`-comments
(crucial: cliamp's TOML parser leaks inline `#` comments into config values,
breaking exact-string lookups and `tonumber`). Booleans are parsed defensively:
`type(raw) == "boolean"` is checked first (the `p:config` call may already
return a real bool), then string values (`"true"`, `"false"`, `"on"`, `"off"`,
`"1"`, `"0"`, `"yes"`, `"no"`).

User-override tracking is done alongside config reads: `user_set_attack =
(p:config("attack") ~= nil)`. These flags let the preset profile overlay know
which keys to not overwrite.

Config defaults:
- `start = "black"`, `color_mode = "glow"`, `theme = "amber"`, `ring_shape = "square"`
- `attack = 0.55`, `release = 0.18` (same as tubeamp)
- `overdrive = 0.78`, `overdrive_decay = 0.82`, `overdrive_bleed = true`
- `density = true`, `density_attack = 0.6`, `density_release = 0.15`
- `gate = 0.0`, `ceiling = 1.0`, `gamma = 1.0`, `tilt = 0.0`
- `cell_aspect = 0.5`, `ring_blend = true`, `fit = "contain"`
- `max_cols = 0`, `max_rows = 0`, `render_rate = 1.0`

### Ring distance metrics (lines 200–245)

Seven pure distance-metric functions in a `DIST` table:

```lua
DIST = {
    square   = function(adx, ady) return (adx > ady) and adx or ady end,  -- Chebyshev
    diamond  = function(adx, ady) return adx + ady end,                    -- Manhattan
    circle   = function(adx, ady) return math.sqrt(adx*adx + ady*ady) end, -- Euclidean
    squircle = function(adx, ady) return (adx^4 + ady^4) ^ 0.25 end,       -- p=4 Minkowski
    wings    = function(adx, _)   return adx end,                           -- X-only, vertical stripes
    layers   = function(_, ady)   return ady end,                           -- Y-only, horizontal strata
    compass  = function(adx, ady) return math.min(adx, ady) + 0.4 * math.abs(adx - ady) end,
}
```

The same `dist()` is used for both `max_d` normalization and per-cell band
lookup — they CANNOT diverge. The caller applies `cfg_cell_aspect` x-scaling
BEFORE calling `dist()`, so `dist()` is pure geometry with no aspect logic.

`ring_shape = "cycle"` rotates through all seven shapes every `cycle_seconds`
(default 20) using `os.time()`. The cycle is anchored to a load-time baseline
(`cycle_t0 = os.time()`) so it always starts on "square" on selection.

### ANSI helpers (lines 247–263)

`fg256(n)` uses a precomputed `FG[256]` table so the hot loop never rebuilds
ANSI escape strings — `FG[color]` is a single table lookup.

```lua
FG = {}
for n = 0, 255 do FG[n] = ESC .. "[38;5;" .. n .. "m" end
local function fg256(n) return FG[n] or (ESC .. "[38;5;" .. n .. "m") end
```

`bg256(n)` is defined on-demand (not precomputed — background colors aren't used
in the hot loop, only in the debug footer).

Math functions are hoisted to locals: `floor`, `abs`, `sqrt` — saving two hash
lookups per call in the per-cell hot loop.

### Braille density mutation (lines 264–353)

All bit math is plain arithmetic (gopher-lua = Lua 5.1 safe). No `|`, `>>`, `&`.

- `braille_char(cp)` — encodes `0x2800 + mask` as 3-byte UTF-8 via div/mod, memoized.
- `set_bit(mask, bit)` — ORs a power-of-two bit into mask, arithmetic only.
- `thicken(base_cp, level, fill_order, dkey)` — computes `add = round(level*8)` dots
  to OR into the base mask. Uses a 3-level cache: `thicken_cache[dkey][base_cp][add]`.
  After warmup this is pure table lookups — zero bit loops, zero allocation in the
  hot path. At most 9 dirs × 256 base glyphs × 9 add buckets = ~20K entries.

The 9 toward-center fill orders are keyed by `FILL_ORDERS[dirx][diry]` where
`dirx, diry ∈ {-1,0,1}`. Each order sorts the 8 braille dots so the ones nearest
the center fill first. Verified visually with `scratchpad/viz_fill.lua`: every
spatial position marches its dots toward center.

### Color presets (lines 355–443)

Nine themes in a `PRESETS` table. Each has `{glow = {11 ANSI 256 indices},
overdrive = {4 ANSI 256 indices}, name = "..."}`.

The config key `theme = "amber"` selects the preset. Unknown names fall back to
amber. Theme swap at render-time (from preset profile overlay) rebinds
`glow_ramp` and `overdrive_ramp` directly.

Themes: amber, crt, vantablack, whitehot, blackhot, redhot, orangehot, aurora,
ember, predator, flan. (redhot + orangehot added June 2 from laptop.)

`glow_color(level, hot)` uses ROUND not floor for ramp indexing — `idx =
floor(level * (n - 1) + 0.5) + 1`. This ensures the peak stop (e.g. white-hot at
index 11) is reachable on real musical peaks, not just at exact `level == 1.0`.

### Preset profiles (lines 445–552)

Eight behaviour profiles in `PRESET_PROFILES`. Each bundles theme, ring_shape,
and all dynamics knobs into a single named feel:

| Preset    | Theme     | Shape    | Feel |
|-----------|-----------|----------|------|
| default   | amber     | circle   | balanced baseline |
| punch     | crt       | diamond  | snappy, percussive |
| ethereal  | aurora    | diamond  | dreamy, slow glow |
| retro     | ember     | square   | CRT-era grit, hard rings |
| plasma    | predator  | circle   | volatile, electric |
| ghost     | vantablack| square   | thin, wispy, slow |
| bloom     | whitehot  | diamond  | bright, fast, blooming |
| tacutacu  | flan      | diamond  | punchy + warm flan tones |

The profile overlay runs at the start of `render()`. For each key, it checks
`user_set_*` — if the user explicitly set it in TOML, the overlay skips it. If
not, the profile's value overwrites the `cfg_*` upvalue for that frame. This
includes theme swap (rebinds glow_ramp/overdrive_ramp) and ring shape swap
(updates cfg_ring_shape so `active_dist()` picks it up).

`cycle_presets = true` rotates through all 8 presets on `cycle_seconds`, using
the same `cycle_t0` baseline as the ring shape cycle (so both cycle modes start
deterministically on selection).

### Art loading (lines 574–744)

Two paths:

1. **Procedural generation** (`generate_wall()`) — fills a fixed 35×188 source
   grid with the `start_cp` base glyph. `start = "black"` → U+2800 (empty braille).
   `start = "stipple"` → U+2821 (faint resting texture). `art_code[y][x] = start_cp`
   everywhere — uniform, zero decode cost, density mutation has its base ready.

2. **File loading** (`load_art()`) — reads via `cliamp.fs.read()`, splits into
   lines, pre-extracts `art_cells[y][x]` (UTF-8 glyph strings) and
   `art_code[y][x]` (braille codepoint if U+2800..U+28FF, else nil).

Path expansion: `expand_path()` handles `~`, `~/`, `$HOME`, `${HOME}` before
passing to `cliamp.fs` (cliamp's Go sandbox does NOT expand shell tilde).

Lazy-load robustness: `init()` calls `load_art()`, but `render()` also calls it
lazily on first use if `art_cells` is nil — `init()` is an optimization, not a
correctness dependency. The readiness sentinel is `art_cells` (set by BOTH the
procedural generator AND the file loader — `art_lines` is only set by the file
path and must not be the gate).

### Per-instance state (lines 746–801)

```lua
smoothed  = {0,0,0,0,0,0,0,0,0,0}  -- asymmetric attack/release envelope
heat      = {0, 0}                   -- overdrive flare latch-and-decay (bands 1-2)
bass_base = {0, 0}                   -- slow baseline EMA for transient onset detection
effective = {0,0,0,0,0,0,0,0,0,0}  -- the final level COLORS read (after all effects)
dens      = {0,0,0,0,0,0,0,0,0,0}  -- density envelope (chases effective[] with its own attack/release)
dens_bleed= {0,0,0,0,0,0,0,0,0,0}  -- density bleed boost (latch-and-decay at overdrive_decay)
bleeding  = false                    -- set during effective[] build, read by debug footer
```

Frame-skip state: `last_output`, `skip_counter`, `last_rows`, `last_cols`.

### The render pipeline (lines 824–1268)

Each `render()` call:

1. **Preset profile overlay** — apply profile values to any `cfg_*` key the user
   didn't explicitly set. Theme swap rebinds color ramps. Ring shape swap updates
   `cfg_ring_shape` for the active distance metric.

2. **Spectral tilt + smoothing** — apply per-band treble boost (`cfg_tilt`),
   then asymmetric attack/release: `smoothed[i] += (raw - smoothed[i]) * attack`
   (fast rise) or `smoothed[i] -= (smoothed[i] - raw) * release` (slow fall).

3. **Build effective[] layer stack**:
   a. Copy `smoothed[]` → `effective[]`
   b. Overdrive flare: transient-onset detection on bands 1-2. Fire when
      `smoothed[i] >= cfg_overdrive AND smoothed[i] >= bass_base[i] + ONSET_MARGIN(0.18)`.
      Latch `heat[i]` to the live level; otherwise `heat[i] *= cfg_od_decay`.
      `effective[i] = max(effective[i], heat[i])`.
      Advance `bass_base[i]` AFTER the onset test (spike doesn't raise its own bar).
   c. Color bleed: when `heat[i] >= FLARE_PEAK` (where `FLARE_PEAK = max(0.92,
      cfg_overdrive)` — never below the overdrive floor), spill
      `0.45 * over` into the ring just outside (`effective[i+1]`). Clamped to ≤1.
   d. Density bleed: same `FLARE_PEAK` gate. Separate `dens_bleed[]` array
      decays at `cfg_od_decay` (same clock as color bleed). Latches on bass
      transient: +1 ring gets full spill, +2 ring gets `spill * 0.5`. Applied
      AFTER the density envelope (step 6 below) so bleed is independent of
      `density_release`.
   e. Gate: clamp `effective[i] < cfg_gate` → 0 (noise gate).
   f. Ceiling: clamp `effective[i] > cfg_ceiling` → cfg_ceiling (limiter).
   g. Gamma curve: `effective[i] = effective[i] ^ cfg_gamma` (skip already-dead bands).

4. **Density envelope**: `dens[i]` chases `effective[i]` with its own attack/release
   (`cfg_dens_attack`, `cfg_dens_release`). Density reads `dens[]`, not `effective[]`.

5. **Apply density bleed boost**: `dens[i] += dens_bleed[i]`. Bleed decays at
   `overdrive_decay`, not `density_release` — the two channels feel like one event.

6. **Lazy-load guard** — load art if `art_cells` is nil.

7. **Frame-skip gate** — if `cfg_frame_skip > 0` and we have a cached frame and the
   pane size hasn't changed and no bass transient fired this frame: reuse
   `last_output`, return early. Audio state still advances (the envelope keeps
   moving). A bass onset force-renders so flares are never dropped.

8. **Canvas cap** — clamp draw grid to `max_cols`/`max_rows` if set.

9. **Fit art to canvas** — `contain` preserves aspect (pictures). `fill` stretches
   each axis independently (textures/wall — the default for the procedural wall).

10. **Ring geometry** — compute `max_d` from the corner of the output grid using
    the active distance metric (resolved once per frame — cycle mode advances here).
    `pos = dist(dx, dy) * 9 / max_d` gives the float ring position (0–9).

11. **Per-cell loop** (the hot path):
    - Map output cell → nearest-neighbor source cell (`art_cells[sy][sx]`).
    - Compute ring position, then `lvl` and `dlvl` via ring blend or snap:
      - Blend: interpolate between `effective[lo]` and `effective[lo+1]` by
        `frac = pos - floor(pos)`. Same for `dens[lo]`/`dens[lo+1]` → `dlvl`.
      - Snap: `band = 1 + floor(pos + 0.5)`. `lvl = effective[band]`, `dlvl = dens[band]`.
    - Color: `glow_color(lvl, lvl >= cfg_overdrive)` for glow mode;
      `mono_color` for mono mode.
    - Density: if `do_dens` and the cell is braille (`art_code[sy][sx]` is set):
      `thicken(base_cp, dlvl, fill_order, dkey)` → thickened UTF-8 glyph.
    - Emit color change (ANSI escape) only when `color != last_color` (color-run
      optimization). Emit glyph. Track append index instead of `#parts`.
    - End each row with `reset()`.

12. **Debug footer** — if `cfg_debug`, paint `[preset + theme + BLD]` centered on
    the last output row using `fg256(244) + bg256(232)`. BLD only shows when
    density bleed is active.

13. **Cache** — stash `result`, `last_rows`, `last_cols` for frame-skip reuse.

14. Return the assembled string.

---

## 7. Color system (themes)

### Why ANSI 256

cliamp's first-party visualizers use Lip Gloss's `ANSIColor(n)` — ANSI 16/256
throughout. ANSI 256 is universally supported. Truecolor support is a v2 idea.

### Theme architecture

All themes are in the `PRESETS` table with a single assignment point:

```lua
local active_preset = PRESETS[cfg_theme_name] or PRESETS["amber"]
local glow_ramp      = active_preset.glow       -- 11 stops
local overdrive_ramp = active_preset.overdrive   -- 4 stops
```

When the preset profile overlay swaps themes (at render time), it rebinds these
upvalues directly. The `glow_color()` function references `glow_ramp`/
`overdrive_ramp` — it never knows where the numbers came from. When cliamp
eventually exposes `cliamp.player.theme_colors()`, you add a `from_cliamp_theme()`
function that maps hex → nearest ANSI 256 → same `{glow, overdrive}` shape, and
change ONE line at the assignment point.

### Theme catalog

| Theme | Glow ramp character | Overdrive ramp character |
|-------|---------------------|--------------------------|
| amber | 232→...→226 (dark→amber→bright yellow) | 160→196→197→198 (red→magenta-pink) |
| crt | 232→...→190 (dark→green→bright green) | 46→82→118→190 |
| vantablack | 232→...→231 (grayscale→pure white) | 249→253→255→231 |
| whitehot | 0→...→231 (dark→white) | 251→254→255→231 |
| blackhot | 231→...→16 (white→dark, inverted) | 238→235→233→16 |
| redhot | 185→...→9 (dark→red→bright red) | 196→197→160→9 |
| orangehot | 223→...→9 (dark→orange→bright red) | 172→166→130→9 |
| aurora | 232→...→195 (dark→teal→cyan→green) | 48→87→123→195 |
| ember | 232→...→197 (green→yellow→red heatmap) | 196→197→201→230 |
| predator | 17→...→224 (indigo→cyan→yellow→red thermal) | 196→160→125→224 |
| flan | 232→...→167 (cream→gold→rose gold) | 209→174→167→210 |

All values are ANSI 256 indices. Glow ramps are 11 stops (matching tubeamp's
canonical ramp length). Overdrive ramps are 4 stops.

---

## 8. State & per-frame timing

### Asymmetric smoothing

Same attack/release model as tubeamp: fast attack (0.55 default) so kick drums
snap on immediately; slow release (0.18 default) so level fades gradually,
giving the afterglow feel. Applied on top of cliamp's own pre-smoothing.

### Transient onset detection (not absolute level)

cliamp's bands are pre-smoothed and bass bands (1-2) often peg near the top on
real music. An `if level >= overdrive` gate would fire CONSTANTLY. Instead:

1. Maintain a slow baseline EMA per bass band: `base += (smoothed - base) * BASE_RATE`
   (where `BASE_RATE = 0.05`).
2. Fire when `smoothed >= base + ONSET_MARGIN` (0.18) AND `smoothed >= cfg_overdrive`.
3. Advance the baseline AFTER the onset test so the spike doesn't raise its own bar.

Sustained-loud bass produces no event; only a genuine jump (a kick) does.

### Overdrive decay tail

On fire: `heat[i] = smoothed[i]` (latch). Else: `heat[i] *= cfg_od_decay`.
`cfg_od_decay` is the fraction RETAINED per frame: 0 = instant snap, ~0.85 =
long glowing tail. `effective[i] = max(smoothed[i], heat[i])` so the tail
never dims below the live level.

### FLARE_PEAK bleed gate

FLARE_PEAK is NOT a fixed constant. It's `max(0.92, cfg_overdrive)` so it can
never fall below the overdrive threshold. A hardcoded `0.92` would break when
the user sets `overdrive > 0.92` — bleed would fire below the overdrive floor,
making no physical sense.

### effective[] layer pipeline (processing order matters)

1. Apply tilt (per-band treble boost) on raw bands before smoothing
2. Smooth bands (asymmetric attack/release) → `smoothed[]`
3. Copy `smoothed[]` → `effective[]`
4. Layer overdrive heat (transient-onset flare latch-and-decay on bass 1-2)
5. Layer color bleed (spill from peak flare into adjacent ring +1)
6. Layer density bleed latch + decay (`dens_bleed[]` — separate array, +1/+2 rings,
   same `overdrive_decay` clock)
7. Apply gate (clamp bands below `cfg_gate` to 0)
8. Apply ceiling (clamp bands above `cfg_ceiling` to ceiling)
9. Apply gamma curve (`effective[i] = effective[i] ^ cfg_gamma`)
10. Advance density envelope (`dens[]` chases `effective[]` with own attack/release)
11. Apply density bleed boost (`dens[] += dens_bleed[]` — added AFTER the envelope
    so bleed decays at `overdrive_decay`, not `density_release`)

Per-cell: color reads `effective[]` (via ring blend or snap), glyph density reads `dens[]`.

### Frame-skip

`render_rate` (0.25–1.0) maps to `cfg_frame_skip = round(1/rate) - 1`. The
counter renders 1 frame, then reuses `last_output` for the next N frames. Audio
state (smoothing, heat, baseline, density) ALWAYS advances — skipping only
elides the expensive per-cell render loop. A bass transient (`onset_fired`)
bypasses the skip so flares are never dropped. Pane resize also invalidates the
cache (dimensions changed).

### Canvas cap

`max_cols` / `max_rows` clamp the DRAWN grid. Cost is linear in drawn cells, so
this bounds per-frame work on huge panes. The art is then centered in the FULL
pane (letterbox padding). With `fit=fill`, a cap makes the wall a centered block
instead of true edge-to-edge — that's the deliberate cost/coverage trade. Use
`render_rate` instead if edge-to-edge coverage matters.

---

## 9. Configuration surface

Lives in `~/.config/cliamp/config.toml`:

```toml
[plugins.nova]                    # entire block OPTIONAL
start = "black"                   # "black" | "stipple" — procedural wall resting glyph
# art_path = "/abs/path.txt"     # OPTIONAL file override (stays in your clone)
color_mode = "glow"              # "glow" | "mono" | "passthrough"
                                 #   passthrough: raw glyphs, NO color OR density
ring_shape = "square"            # square | diamond | circle | squircle | wings | layers | compass | cycle
cycle_seconds = 20               # seconds per shape/preset in cycle modes (min 2)
fit = "contain"                  # "contain" | "fill"
ring_blend = true                # smooth gradient between rings
density = true                   # glyphs thicken toward center
density_attack = 0.6             # 0–1, how fast dots FILL (high = snappy)
density_release = 0.15           # 0–1, how fast dots SHED (low = lingering)
theme = "amber"                  # amber | crt | vantablack | whitehot | blackhot | redhot | orangehot | aurora | ember | predator | flan
preset = "default"               # default | punch | ethereal | retro | plasma | ghost | bloom | tacutacu
cycle_presets = false            # auto-rotate presets on cycle_seconds
debug = false                    # show preset + theme + BLD on bottom row
mono_color = 11                  # ANSI 256 index, used in color_mode="mono"
attack = 0.55                    # smoothing attack (0–1)
release = 0.18                   # smoothing release (0–1)
overdrive = 0.78                 # 0–1, band level above which bass flares hot
overdrive_decay = 0.82           # 0–0.97, fraction of heat RETAINED per frame (0=snap, 0.85=long tail)
overdrive_bleed = true           # when bass punches hot, spill color + density into adjacent rings
tilt = 0.0                       # 0–? — per-band boost toward treble (0=off; try 0.5)
gate = 0.0                       # 0–0.5, noise gate: clamp bands below this to 0
ceiling = 1.0                    # 0.01–1.0, limiter: clamp bands above this (1.0=off)
gamma = 1.0                      # 0.1–3.0, response curve (1.0=linear)
cell_aspect = 0.5                # 0.2–2.0, terminal cell width/height ratio for round circles

# --- performance (0 = off / unlimited) ---
max_cols = 0                     # cap DRAWN width (0=unlimited)
max_rows = 0                     # cap DRAWN height (0=unlimited)
render_rate = 1.0                # 0.25–1.0, fraction of frames rendered (~20 FPS at 1.0)
```

All keys are optional. With no config block at all, the plugin renders the default
procedural wall (`start = "black"`, `circle` shape, `amber` theme, `default` preset).

### Preset profile override semantics

When `preset = "punch"`, every bundled key is set to the Punch profile's values
AT THE START OF EACH RENDER. If the user ALSO sets `overdrive = 0.95` in their
TOML, that explicit value WINS (the overlay skips user-set keys). Individual
overrides survive preset cycling.

---

## 10. Constraints & sandbox boundaries

| Limit | Source | Why it matters here |
|-------|--------|---------------------|
| 10ms per `render()` call | `luaplugin/visualizer.go` | Hot loop is O(draw_h × draw_w) with cached table lookups. At normal pane sizes (5×80) this is trivial. At fullscreen fit=fill on a 4K terminal it tightens — use `render_rate` and `max_cols`/`max_rows` to cap cost. |
| Return-string only | host | Every exit path must return a string. Non-string → silent frame reuse. |
| gopher-lua = Lua 5.1, no bitops | sandbox | All density math uses arithmetic on powers of two. `luac -p` cannot catch bitops (local Lua accepts them, host rejects silently). |
| No `os.execute`, no `io.*` | sandbox | Not needed. All state is in-memory. Art reads via `cliamp.fs`. |
| `cliamp.message()` deadlocks in `render()` | gopher-lua UI mutex | Only call from `init()`. Debug footer uses inline ANSI labels on output rows instead. |
| Render serialized per plugin | host mutex | State mutation needs no locks. |
| ANSI 256 only | Bubbletea | Truecolor is a v2 idea. |
| TOML `#`-comments leak into values | cliamp parser | Every `p:config(...)` goes through `clean()` which strips `%s*#.*$`. |
| `~` not expanded in `cliamp.fs` paths | Go `os.ReadFile` | `expand_path()` handles `~`, `~/`, `$HOME`, `${HOME}` before `cliamp.fs` calls. |
| `init(rows, cols)` may not fire | host timing | Art loads lazily on first `render()` if `art_cells` is nil. `init()` is an optimization. |

---

## 11. Testing & local verification

### Syntax check

```sh
lua nova.lua
```

Will error on missing `plugin` global — that's expected. Look for real syntax errors.

### Standalone render harness

The repo ships a harness at `scratchpad/render_harness.lua`. It stubs the plugin
host (`plugin.register(...)`, `cliamp.fs`, `cliamp.message`), loads `nova.lua`,
and pumps frames across varied scenes. Run:

```sh
lua scratchpad/render_harness.lua
```

Check ANSI output: `lua scratchpad/render_harness.lua | grep -c $'\x1b\['`

### Band map probe

Before eyeballing ANSI color, verify ring geometry with the numeric probes:

```sh
lua scratchpad/band_map_probe_allshapes.lua
```

This dumps the per-cell band index (0–9) for every ring shape as a numeric
grid — independent of color. Bass should be center, treble at edges, clean rings.

### In-host verification

1. `cp nova.lua ~/.config/cliamp/plugins/nova.lua`
2. Start cliamp on real audio.
3. Press `v` until the cycle reaches `nova`.
4. Check `~/.config/cliamp/plugins.log` for `[nova] error:` lines.
5. QA checklist:
   - Wall fills with color bottom-up (bass rings light first).
   - On a kick drum, the center ring(s) flash bright and decay over ~1 second.
   - Glyphs thicken (gain dots) toward center on peaks — not just recolor.
   - Set `ring_shape = "cycle"` and watch all 7 shapes rotate.
   - Set `cycle_presets = true` and watch presets rotate with theme changes.
   - Set `debug = true` — footer shows preset name + theme + BLD indicator.
   - On loud music, bass overdrive flares and bleeds into adjacent rings.
   - Fullscreen mode (Shift+V): wall scales smoothly, no rendering glitches.
   - Set `density = false` and confirm glyphs stay fixed (color only).
   - Set `color_mode = "passthrough"` — raw braille wall, no color or density.

### Deterministic stateful-effect testing

For effects with per-frame state (overdrive decay, baseline EMA, density
envelope, density bleed), the scratchpad probes verify transitions
deterministically:

```sh
lua scratchpad/test_overdrive.lua     # flare/decay/bleed state machine
lua scratchpad/test_center_fill.lua   # toward-center fill order correctness
```

---

## 12. Installation & distribution

### cliamp's install convention

cliamp's plugin manager recognizes repos named `cliamp-plugin-<name>` and
installs the entry `<name>.lua` from the repo root. The `cliamp-plugin-` prefix
is stripped on install, so the user-visible plugin name is `nova`.

### Install sources

```sh
# Once the repo is public:
cliamp plugins install 8bit64k/cliamp-plugin-nova
cliamp plugins install 8bit64k/cliamp-plugin-nova@v0.1.0

# During private QA (manual):
git clone https://github.com/8bit64k/cliamp-plugin-nova.git
cd cliamp-plugin-nova
cp nova.lua ~/.config/cliamp/plugins/nova.lua
# After pushing changes:
git pull && cp nova.lua ~/.config/cliamp/plugins/nova.lua
# Force-push recovery (8bit64k laptop):
git fetch origin && git reset --hard origin/master
```

cliamp does NOT hot-reload — re-copy and restart after every change.

### Versioning

- `version` in `plugin.register({...})` is informational only.
- Git tags (`v0.1.0`, etc.) for plugin manager pinning.
- Bump the version string alongside any meaningful release tag.

### Visibility

- Currently **private** during QA.
- Flip to public when ready:
  ```sh
  gh repo edit 8bit64k/cliamp-plugin-nova --visibility public
  ```

### Branch policy

- `master` is the default and only long-lived branch.
- **Experimental visual features (breathing, bold, untested effects) must branch
  off master.** Iterate on the branch, test live, merge only when solid. Force-push
  on private repos is acceptable for clean history (8bit64k reconciles laptop with
  `git fetch origin && git reset --hard origin/master`).

---

## 13. Known limitations & ideas for v2

### Limitations

1. **No truecolor mode.** ANSI 256 only. Users on truecolor terminals see the
   same 256-color ramps. A `COLORTERM=truecolor` detection + secondary 24-bit
   ramp path would allow smoother gradients.

2. **No responsive layout tiers.** Unlike tubeamp (FULL/COMPACT/MINI/HIDDEN),
   nova renders at whatever size the pane is. At the default 5-row pane, the wall
   is squashed but still renders. A MINI tier could render coarser rings and
   simpler glyphs; a HIDDEN tier could return `""` below 3 rows.

3. **No per-band peak hold markers.** Tubeamp has floating `●` markers; nova
   doesn't. Density mutation fills a similar role (the visual punch), but peak
   markers would add a second visual channel.

4. **Smoothing is not dt-aware.** If cliamp's tick rate changes (TickSlow during
   pauses), the smoother converges at the same per-tick rate regardless of
   wall-clock dt. In practice this is fine — visible motion during slow ticks
   is minimal.

5. **No sub-cell glyph block fill.** Fractional vertical fill (like native bar
   modes' `▁▂▃▄▅▆▇█`) is not used. Nova uses braille density mutation (OR-ing dots)
   which is a different visual language — more "texture thickening" than
   "level meter." Reconsider if users want more precise level reading.

6. **`active_profile()` called twice per frame** — once for profile overlay and
   once for debug label. Cost is negligible (~2 table lookups), but worth
   consolidating in a cleanup pass.

7. **Stale header comment** — line 3 says "v0.1 square rings" and describes the
   original prototype. Update to match current feature set.

### v2 ideas

- **24-bit truecolor ramp** behind a `color_mode = "truecolor"` toggle, with
  smooth gradient interpolation.
- **Responsive layout tiers** — FULL / COMPACT / MINI / HIDDEN, matching tubeamp's
  tiered approach. HIDDEN returns `""` below a minimum pane size.
- **Peak hold markers** — a dot floating at the recent band maximum, decaying slowly.
- **Braille wall art gallery** — ship multiple procedural wall textures
  (uniform, twill, noise, lattice) as named presets or a `wall` config key.
- **Native overdrive indicator** — currently density bleed is shown via the "BLD"
  debug footer tag. A native indicator (the source ring's glyphs pulsing bold
  during a flare) would provide the same information without chrome.
- **More themes** — `military` (green phosphor), `nixie` (orange), `cathode`
  (cyan-green oscilloscope), matching tubeamp's v2 theme ideas.
- **Per-band custom labels** — overlay Hz values as faint numbers on the wall.

---

## 14. File map

```
cliamp-plugin-nova/
├── .gitignore                  # *.swp, *.bak, scratchpad/ (gitignored)
├── LICENSE                     # MIT, © 8bit64k (added at release)
├── README.md                   # User-facing install + config
├── nova.lua                    # The plugin itself (single file, ~1268 lines)
├── AGENTS.md                   # Durable design principles + agent context
├── CHECKPOINT.md               # Transient rolling work-log (current session state)
├── CHECKPOINT.2026-05-31.md    # Archived checkpoint rollover
├── CHECKPOINT.2026-05-30-01.md # Archived checkpoint rollover
├── BRAINSTORM.md               # Original 8-approach design exploration
├── crt.txt                     # Portrait art file (Ruby — not used by nova)
├── ruby.txt                    # Portrait art file (not used by nova)
├── ruby_ascii.txt              # Portrait art file (not used by nova)
├── docs/
│   └── DESIGN.md               # This document
└── scratchpad/                 # Gitignored — harnesses, probes, session artifacts
    ├── render_harness.lua
    ├── band_map_probe_allshapes.lua
    ├── test_overdrive.lua
    ├── test_center_fill.lua
    ├── test_cycle.lua
    ├── test_blend.lua
    ├── code-doc-review-2026-05-31.md
    └── ... (session artifacts)
```

Repo root holds `nova.lua` because cliamp's plugin manager looks there. Don't
move it into a subdirectory.

---

## 15. Agent handoff checklist

Before declaring any change "done," verify:

- [ ] `lua nova.lua` parses (will error on `plugin` global — expected; look for real syntax errors)
- [ ] No Lua 5.3+ syntax used (no `>>`, `<<`, `|`, `&`, `bit32`) — gopher-lua 5.1
- [ ] Standalone render harness (`scratchpad/render_harness.lua`) pumps 5+ scenes without errors
- [ ] ANSI escape count non-zero in harness output
- [ ] All render paths return a string (no bare `return`, no nil returns)
- [ ] `cliamp.message()` NOT called inside `render()` — only from `init()`
- [ ] Plugin installs into `~/.config/cliamp/plugins/nova.lua` and shows in cliamp's visualizer cycle
- [ ] `~/.config/cliamp/plugins.log` has no `[nova] error` entries after a fresh playback session
- [ ] Wall lights and thickens correctly: bass center, treble edge, rings concentric
- [ ] All 7 ring shapes render correctly (use `band_map_probe_allshapes.lua`)
- [ ] All 9 themes produce distinct, recognizable color output
- [ ] Overdrive flare fires on bass transients, decays with tail, bleeds into adjacent rings
- [ ] Density bleed (+1/+2 rings) visible in debug BLD footer
- [ ] Preset profiles override correctly; user-set keys survive preset overlay
- [ ] `cycle_presets` and `ring_shape = "cycle"` rotate on wall clock
- [ ] Frame-skip (`render_rate`) caches and reuses output; onset overrides work
- [ ] Canvas cap (`max_cols`/`max_rows`) bounds drawn grid
- [ ] Procedural wall loads with no `art_path` (`start = "black"` and `"stipple"`)
- [ ] File art path loads correctly; `~`/`$HOME` expansion works
- [ ] No debug scaffolding left in output (footer indicators removed when done)
- [ ] README.md reflects current config keys (no drift between README and `nova.lua`)
- [ ] AGENTS.md feature summary matches current state
- [ ] DESIGN.md reflects current behavior (this document)
- [ ] Commits authored as 8bit64k
- [ ] `version` bumped in `plugin.register({...})` for user-visible changes
- [ ] CHECKPOINT.md updated with session summary, commit hash, decisions
- [ ] Experimental/tenuous visual work done on a branch, not master

---

*Last reviewed: 2026-06-02. Version covered: nova 0.1.0.*
