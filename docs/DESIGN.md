# DESIGN.md — cliamp-plugin-nova

> Braille-wall visualizer for cliamp: a dense braille texture mapped into
> concentric rings, colored by the 10-band EQ on themed ANSI 256 ramps, with
> glyph bloom that thickens toward center as rings heat. Procedurally generated
> — no art file required.
>
> v0.1.0. Single Lua file (~1404 lines). gopher-lua 5.1 sandbox.
>
> **Repo:** `8bit64k/cliamp-plugin-nova` (public)
> **Install:** `cliamp plugins install 8bit64k/cliamp-plugin-nova`

---

## Table of contents

1. [What this plugin is](#1-what-this-plugin-is)
2. [Upstream — what matters](#2-upstream--what-matters)
3. [Visualizer API contract](#3-visualizer-api-contract)
4. [Design goals](#4-design-goals)
5. [Implementation walkthrough](#5-implementation-walkthrough)
6. [Color Themes](#6-color-themes)
7. [Ring shapes](#7-ring-shapes)
8. [Visual Dynamics presets](#8-visual-dynamics-presets)
9. [Configuration surface](#9-configuration-surface)
10. [Audio signal chain](#10-audio-signal-chain)
11. [Constraints & gotchas](#11-constraints--gotchas)
12. [Testing](#12-testing)
13. [Known limitations & vNext](#13-known-limitations--vnext)
14. [File map](#14-file-map)

---

## 1. What this plugin is

`nova` is a visualizer plugin for cliamp. It generates a uniform braille wall
at load time and maps it into 10 concentric rings centered on the pane. Each
ring is driven by one EQ band — bass (32 Hz) at center, treble (16 kHz) at the
edge. Every cell recolors by its ring's smoothed level and its braille glyph
thickens (gains dots toward center) as the ring heats.

### Feature summary (v0.1.0)

| Feature | Surface |
|---------|---------|
| Ring shape | Circle (Euclidean radial distance) |
| Color themes | 6: sol, sirius, rigel, antares, aurora (default), crt (easter egg) |
| Presets | 6: reference, transient, nebula, plasma, afterglow, analog |
| Cycle | `cycle_presets` rotates presets, `cycle_themes` rotates themes — independent axes |
| Bloom bleed | Overdrive transients thicken +1/+2 adjacent rings |
| Overdrive | Transient-onset flare on bass bands, latch-and-decay tail |
| Pipeline | gate → knee → ceiling compressor lane + tilt EQ |
| Performance | `render_rate` frame throttling, `max_cols`/`max_rows` canvas cap |
| Procedural wall | `start = "black"` (empty) or `"stipple"` (faint texture). `art_path` override |

**Defaults:** theme=aurora, ring_shape=circle, fit=fill, start=black.

---

## 2. Upstream — what matters

cliamp is a Bubbletea-based terminal music player (Go). It ticks visualizers at
~20 FPS (50ms TickFast) while playing, 5 FPS (200ms TickSlow) when paused.
The 10-band EQ is pre-smoothed and log-scaled; bands arrive normalized 0.0–1.0.

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

The plugin does its own additional asymmetric smoothing on top for the
attack/release tube-like feel, and bloom has its own separate envelope.

Upstream checkout at `~/builds/cliamp/`. Ground truth files: `docs/plugins.md`,
`luaplugin/visualizer.go`, `luaplugin/sandbox.go`, `ui/tick.go`.

---

## 3. Visualizer API contract

```lua
function p:render(bands, frame, rows, cols)
    -- bands: table { [1]=0.0..1.0, ..., [10]=0.0..1.0 }
    -- frame: monotonic counter, resets on visualizer (re-)selection
    -- rows, cols: terminal pane dimensions
    -- returns: multi-line string (\n-separated). ANSI escapes pass through.
end
```

**Hard rules:**
- Return MUST be a string. Non-string → silent frame reuse (previous frame).
- 10ms budget per call. Render is serialized per plugin (host mutex).
- ANSI 256-color escapes pass through Bubbletea unchanged.
- `init(rows, cols)` optional, runs once on selection. `destroy()` on deselection.
- gopher-lua = Lua 5.1: no bitwise operators (`>>`, `<<`, `|`, `&`), no `bit32`.
  All bit work is arithmetic on powers of two.

**Sandbox:** no `os.execute`, no `io.*`, no `dofile`. File reads from any path
(1 MB cap). `~` not expanded in `cliamp.fs` paths — `expand_path()` handles it.
`cliamp.message()` deadlocks inside `render()` — call only from `init()`.

---

## 4. Design goals

1. **Concentric rings, bass at center.** Band 1 innermost, band 10 outermost.
2. **Radial ring shape** via Euclidean distance from pane center. Bass maps to
   the innermost ring, treble to the outermost.
3. **Color themes from the tubeamp family.** 15-stop RGB-native glow + 4-stop
   overdrive ramp per theme, truecolor with ANSI fallback.
4. **Braille bloom mutation.** Glyphs thicken toward center as rings heat. Dots
   OR into base glyph, ending at solid ⣿ (U+28FF). Own attack/release envelope
   for phosphor persistence.
5. **Bloom bleed.** Overdrive transients thicken +1/+2 adjacent rings (bulge
   travels further than color).
6. **Transient-triggered overdrive.** Flare fires on bass ONSET (kick drum),
   not sustained level. Slow baseline EMA + onset margin.
7. **One-knob presets.** 6 curated feels bundle theme + shape + all dynamics.
   Individual TOML keys override.
8. **Procedural wall.** No file dependency. `art_path` optional override.

**Non-goals:** ASCII portrait art (separate plugin), positional jitter, truecolor.

---

## 5. Implementation walkthrough

Everything in `nova.lua`. Single file, no requires.

### Registration

```lua
local p = plugin.register({
    name = "nova", type = "visualizer", version = "0.1.0",
    description = "Braille wall visualizer — EQ-driven glow with presets, themes, and bloom mutation",
})
```

### Configuration

Every `p:config(key)` goes through `clean()` which strips trailing `#`-comments
(cliamp's TOML parser leaks them) and surrounding quotes. Booleans parsed
defensively: real bool first, then string `"true"`/`"false"`/`"1"`/`"0"`.

User-set tracking: a `user_set` table keyed by config name.
`user_set[key] = (p:config(key) ~= nil)` for every key in `PRESET_KEYS`.
These flags let the preset profile overlay skip keys the user explicitly set.

### Ring distance metrics

One distance-metric function in a `DIST` table (circle). Additional shapes
(diamond, wings) are preserved on the `vnext-shapes` branch. The caller applies
`cfg_cell_aspect` x-scaling (default 0.5) BEFORE calling `dist()`, so `dist()`
is pure geometry with no aspect logic. The same `dist()` is used for both
`max_d` normalization and per-cell band lookup — they CANNOT diverge.

```lua
DIST = {
    circle  = function(adx, ady) return math.sqrt(adx*adx + ady*ady) end,
}
```


### ANSI helpers

`FG[256]` precomputed table — per-cell color changes are single table lookups.
`fg256(n)` returns `FG[n]`. Hot math functions hoisted to locals: `floor`,
`abs`, `sqrt`.

### Braille bloom mutation

All bit math is plain arithmetic (gopher-lua 5.1 safe).

- `braille_char(cp)` — encodes `0x2800 + mask` as 3-byte UTF-8 via div/mod,
  memoized in `braille_cache[cp]`.
- `set_bit(mask, bit)` — ORs a power-of-two bit using `floor(mask/bit) % 2`.
- `thicken(base_cp, level, fill_order, dkey)` — computes `add = round(level*8)`
  dots to OR into base. Memoized: `thicken_cache[dkey][base_cp][add]`. After
  warmup this is pure table lookups, zero bit loops in hot path.

**Toward-center fill:** 9 directional fill orders keyed by
`FILL_ORDERS[dirx][diry]` where `dirx, diry ∈ {-1,0,1}`. Each order sorts the 8
braille dots so the ones nearest center fill first. Center-axis cells (any dirx
or diry == 0) list dots in mirror-PAIRS (or quads for dead center); `thicken()`
snaps `add` to even/pairs or mult-of-4/quads via `dkey` parity check. This
preserves the wall's mirror symmetry on odd-dimensioned panes.

**INVARIANT:** the wall must be mirror-symmetric (V and H). Opposite cells
across pane center must be exact dot-mirrors. Verify with
`scratchpad/test_mirror_symmetry.lua`.

### Procedural wall generation

`generate_wall()` fills a fixed 35×188 source grid with the `start_cp` base
glyph — uniform, zero decode cost, bloom base ready on every cell.
`start = "black"` → U+2800 (empty), `"stipple"` → U+2824 (faint texture).

File path: `load_art()` reads via `cliamp.fs.read()`. `expand_path()` handles
`~`, `~/`, `$HOME`, `${HOME}`. Pre-extracts `art_cells[y][x]` (glyph strings)
and `art_code[y][x]` (braille codepoint or nil). Lazy-load guard: `render()`
calls load on first use if `art_cells` is nil — `init()` is an optimization.

### Per-instance state

```
smoothed[10]    — asymmetric attack/release envelope
heat[2]         — overdrive flare latch-and-decay (bands 1-2)
bass_base[2]    — slow baseline EMA for transient onset detection
effective[10]   — the final level COLORS read (after all effects)
bloom[10]       — bloom envelope (chases effective[] with own attack/release)
bloom_bleed[10] — bloom bleed boost (latch-and-decay at sustain)

```

Render-rate state: `last_output`, `last_rows`, `last_cols`.

### Render pipeline

Each `render()` call:

1. **Preset profile overlay** — apply profile values to `cfg_*` keys the user
   didn't explicitly set. Theme swap rebinds `glow_ramp`/`overdrive_ramp`.
   Ring shape swap updates `cfg_ring_shape`.
2. **Spectral tilt + smoothing** — per-band treble boost (`cfg_tilt`), then
   asymmetric attack/release on `smoothed[i]`.
3. **Build effective[] layer stack** (see [Audio signal chain](#10-audio-signal-chain)):
   - Copy `smoothed[]` → `effective[]`
   - Overdrive flare: transient-onset detection on bands 1-2 via baseline EMA
     + onset margin. Latch `heat[i]`, else `heat[i] *= cfg_sustain`.
     `effective[i] = max(effective[i], heat[i])`. Flare detector input clamped
     to `cfg_ceiling` so ceiling below overdrive means no flare, ever.
   - Color bleed: when `heat[i] >= FLARE_PEAK`, spill into ring +1. Clamped ≤1.
     `FLARE_PEAK = max(0.92, cfg_overdrive)` — never below overdrive threshold.
   - Bloom bleed: separate `bloom_bleed[]` array, same `FLARE_PEAK` gate.
     Latches on bass transient: +1 ring gets full spill, +2 gets half.
     Decays at `cfg_sustain` (shared clock with color bleed).
   - Gate: clamp `effective[i] < cfg_gate` → 0.
   - Knee: `effective[i] = effective[i] ^ cfg_knee` (skip dead bands).
   - Ceiling: final hard clamp `effective[i] > cfg_ceiling` → cfg_ceiling.
     **Must be last** — knee < 1 lifts clamped values past ceiling.
4. **Bloom envelope** — `bloom[i]` chases `effective[i]` with its own
   attack/release (`cfg_bloom_attack`, `cfg_bloom_release`).
5. **Apply bloom bleed boost** — `bloom[i] += bloom_bleed[i]`. Added AFTER
   the envelope so bleed decays at `sustain`, not `bloom_release`.
6. **Lazy-load guard** — load art if `art_cells` is nil.
7. **Render-rate gate** — `should_render()` Bresenham accumulator gate drops
   frames at `render_rate` (0.25–1.0). When skipping, reuse cached
   `last_output`. Audio state always advances even on skipped frames.
   Pane resize always forces a render (resets accumulator).
8. **Canvas cap** — clamp draw grid to `max_cols`/`max_rows` if set.
9. **Fit art to canvas** — `fit = "fill"` stretches (default for the wall).
   `fit = "contain"` preserves aspect.
10. **Ring geometry** — compute `max_d` from corner of output grid using active
    distance metric. `pos = dist(dx, dy) * 9 / max_d` gives float ring position.
11. **Per-cell loop** (the hot path):
    - Nearest-neighbor sample from `art_cells[sy][sx]`.
    - Ring blend: interpolate `effective[lo]`/`effective[lo+1]` by `frac`.
      Same for `bloom[lo]`/`bloom[lo+1]` → `dlvl`.
      Ring snap: `band = 1 + floor(pos + 0.5)`, direct lookup.
    - Color: `glow_color(lvl, lvl >= cfg_overdrive)`. `mono_color` for mono mode.
    - Bloom: if `cfg_bloom` and cell is braille, `thicken(base_cp, dlvl, fill_order, dkey)`.
    - Color-run optimization: emit ANSI only when `color != last_color`.
    - Track append index instead of `#parts`. End each row with `reset()`.
12. **Debug footer** — if `cfg_debug`, paint `[preset + theme]` centered on
    last output row. Also tracks `last_shown_preset` and `last_profile_name`.
13. **Cache** — stash result for render-rate skip reuse.
14. Return the assembled string.

---

## 6. Color Themes

Six themes (five stellar + aurora), 15-stop RGB ramp + 4-stop overdrive each.
Truecolor-native with ANSI 256 fallback. Selected via `theme` config key;
falls back to `aurora` on unknown names. `cycle_themes = true` rotates
sol → sirius → rigel → antares → aurora; crt is excluded from the cycle.

| Theme | Star | Color |
|-------|------|-------|
| **aurora** (default) | — | Dark → teal → cyan → green |
| sol | Sol (G2, 5,800K) | Dark → amber → gold → yellow |
| sirius | Sirius (A1, 9,900K) | Black → gray → pure white |
| rigel | Rigel (B8, 12,000K) | Navy → electric blue → blue-white |
| antares | Antares (M1, 3,500K) | Crimson → neon red → pink → white |
| crt | — (easter egg) | Dark → green → bright green |

All themes are 15-stop RGB ramps, truecolor-native with ANSI 256 fallback.

Theme architecture: single assignment point. `glow_ramp` and `overdrive_ramp`
are upvalues set from the active preset. Preset profile overlay rebinds them
at render time on theme swap. `glow_color()` references the upvalues — it never
knows where the numbers came from.

Ramp indexing uses ROUND not floor: `idx = floor(level * (n - 1) + 0.5) + 1`.
Ensures the peak stop is reachable on real musical peaks, not just at exact 1.0.

---

## 7. Ring shape

Circle (Euclidean radial distance). Bass at center, treble at edge.

| Shape | Metric | Visual |
|-------|--------|--------|
| **circle** (default) | Euclidean: `sqrt(dx² + dy²)` | Nested circles |

`cell_aspect = 0.5` x-scaling applied BEFORE `dist()` so circles read round.

Additional shapes (diamond, wings) preserved on `vnext-shapes` branch.

---

## 8. Visual Dynamics presets

Six one-knob presets. Each bundles theme + ring_shape + all dynamics into a
named feel. The profile overlay runs at the start of each `render()`. User-set
TOML keys survive the overlay. All presets use aurora + circle unless overridden.

| Preset | Feel |
|--------|------|
| **reference** | Balanced baseline — the standard everything is measured against |
| **transient** | Snappy and percussive — max attack, max bloom, kick-driven |
| **nebula** | Diffuse and billowy — treble-biased, fast shimmer |
| **plasma** | Energetic and sustained — the set-and-forget all-rounder |
| **afterglow** | Slow phosphor persistence — slow to wake, slow to fade |
| **analog** | Hard-banded rings — old-school EQ visualizer look |

`cycle_presets = true` rotates through all 6 on `cycle_seconds`.
`cycle_themes = true` independently rotates color themes.

vNext presets (retro, whiteout, tacutacu) preserved on `vnext-themes` branch.

---

## 9. Configuration surface

Lives in `~/.config/cliamp/config.toml`. Entire block is optional.

```toml
[plugins.nova]

# --- look ---
theme = "aurora"
#   sol | sirius | rigel | antares | aurora | crt
ring_shape = "circle"
cycle_seconds = 20
#   seconds per preset/theme in cycle modes (min 2)
ring_blend = true
#   true = smooth gradient across rings | false = hard banded rings
fit = "fill"
#   "contain" = letterboxed | "fill" = stretch edge to edge

# --- feel ---
preset = "reference"
#   reference | transient | nebula | plasma | afterglow | analog
cycle_presets = false
#   rotate through all presets automatically
cycle_themes = false
#   rotate through all themes automatically (sol→sirius→rigel→antares→aurora)

# --- bloom (glyph density) ---
bloom = true
#   false = color only, dots stay fixed
bloom_attack = 0.60
bloom_release = 0.15

# --- dynamics (all 0–1 unless noted) ---
attack = 0.55
release = 0.18
overdrive = 0.78
sustain = 0.82
#   0–0.97, fraction of heat retained per frame (0 = instant snap)
blend = true
#   overdrive color + bloom spill into adjacent rings
tilt = 0.00
#   per-band treble boost (try 0.30–0.50)
gate = 0.00
#   0–0.50, noise gate — silence below this level
ceiling = 1.00
#   0.01–1.00, limiter — clamp above this (1.00 = off)
knee = 1.00
#   0.10–3.00, response curve (<1 softer, >1 harder, 1.00 linear)

# --- procedural wall ---
start = "black"
#   "black" = empty canvas, dots bloom from silence
#   "stipple" = faint resting texture
#   art_path = "/abs/path/to/file.txt"
#   optional file override (stays in your clone)

# --- advanced ---
cell_aspect = 0.50
color_mode = "glow"
#   "glow" | "mono" | "passthrough" (no color, no bloom)
mono_color = 11

# --- performance ---
max_cols = 0
max_rows = 0
#   cap drawn area (0 = unlimited)
render_rate = 1.00
#   0.25–1.00, fraction of frames rendered
```

All keys optional. With no config block, nova renders a procedural wall in
aurora + circle + fill with the `reference` preset dynamics.

---

## 10. Audio signal chain

The `effective[]` layer stack runs in a fixed order — same as a mastering chain.

```
raw bands
    │
    ▼
  TILT ─── per-band treble boost
    │
    ▼
  SMOOTH ─ asymmetric attack/release → smoothed[]
    │
    ▼
  effective[] ◄── copy smoothed[]
    │
    ├─► HEAT ─────── transient onset, latch+decay
    ├─► COLOR BLEED ─ +1 ring, cfg_blend gated
    ├─► BLOOM BLEED ─ +1/+2 rings, same sustain clock
    ├─► GATE ─────── clamp below threshold → 0
    ├─► KNEE ─────── response curve ^cfg_knee
    └─► CEILING ──── brick-wall cap (LAST)
         │
         ├──► effective[] ──► COLOR (per-cell ring blend/snap)
         │
         └──► bloom[] chase ──► + bloom_bleed ──► BLOOM (glyph thicken)
              (own attack/release)
```

Steps in order:

1. **Tilt** — per-band treble boost on raw bands (before smoothing)
2. **Smooth** — asymmetric attack/release → `smoothed[]`
3. **Copy** — `smoothed[]` → `effective[]`
4. **Overdrive heat** — transient-onset flare latch-and-decay on bands 1-2
5. **Color bleed** — peak flare spill into ring +1 (`cfg_blend`)
6. **Bloom bleed** — separate `bloom_bleed[]` array, +1/+2 rings, same `sustain` clock
7. **Gate** — clamp below `cfg_gate` to 0
8. **Knee** — `effective[i] ^ cfg_knee` (EQ-stage, before limiter)
9. **Ceiling** — final brick-wall clamp (MUST be last; knee < 1 lifts clamped values)
10. **Bloom envelope** — `bloom[]` chases `effective[]` with own attack/release
11. **Bloom bleed boost** — `bloom[] += bloom_bleed[]` (after envelope, so bleed
    decays at `sustain` not `bloom_release`)

Per-cell: color reads `effective[]` (ring blend or snap), bloom reads `bloom[]`.

**Key invariants:**
- Ceiling clamps the flare DETECTOR input (`s = min(smoothed[i], ceiling)`),
  not just the output. This means `ceiling < overdrive` → no flare, no bleed,
  no bloom_bleed — the overdrive threshold is unreachable.
- Bleed gates on `heat[i]`, NOT `effective[i]`. `effective[]` carries sustained
  signal and would fire bleed constantly.
- `attack=0` kills both color AND bloom — both read from `effective[]` which
  is built from `smoothed[]`. Use gate+ceiling compressor lane instead.

---

## 11. Constraints & gotchas

| Constraint | Why it matters |
|------------|---------------|
| gopher-lua = Lua 5.1, no bitops | All bloom math is arithmetic. `luac -p` can't catch bitops (local Lua accepts them, host rejects silently) |
| `init()` may not fire | Art loads lazily on first `render()` if `art_cells` is nil |
| `cliamp.message()` deadlocks in `render()` | Only call from `init()`. Debug footer uses inline ANSI |
| Return MUST be string | Non-string → silent frame reuse. Every exit path returns a string |
| TOML `#`-comments leak into values | Every `p:config(...)` goes through `clean()` |
| `~` not expanded in fs paths | `expand_path()` before `cliamp.fs` calls |
| `v:gsub()` crashes on chained calls | Use `string.gsub(v, ...)` with type guard |
| Ceiling/bleed interaction | See invariants above. `bloom_bleed[]` is separate array, bypasses output clamp |

---

## 12. Testing

### Syntax check
```sh
lua nova.lua   # errors on missing 'plugin' global = expected; watch for syntax errors
```

### Render harness
```sh
lua scratchpad/render_harness.lua
lua scratchpad/render_harness.lua | grep -c $'\x1b\['   # verify ANSI present
```

### Band map probe (verify geometry before color)
```sh
lua scratchpad/band_map_probe_allshapes.lua
```

### Mirror symmetry (run after any FILL_ORDERS or thicken change)
```sh
lua scratchpad/test_mirror_symmetry.lua
```

### Ceiling/bleed (run after any flare/bleed/ceiling change)
```sh
lua scratchpad/test_ceiling_bleed.lua
```

### In-host
1. `cp nova.lua ~/.config/cliamp/plugins/nova.lua`
2. Start cliamp, press `v` to cycle to `nova`
3. Check `~/.config/cliamp/plugins.log` for `[nova] error:` lines

---

## 13. Known limitations & vNext

### Limitations
- **No truecolor.** ANSI 256 only. A `COLORTERM=truecolor` secondary path is a v2 idea.
- **No responsive layout tiers.** Unlike tubeamp (FULL/COMPACT/MINI/HIDDEN),
  nova renders at whatever pane size it gets.
- **Smoothing not dt-aware.** Same per-tick rate at both TickFast and TickSlow.
  In practice fine — visible motion during slow ticks is minimal.
- **Single-pipe limitation.** `attack=0` kills bloom too (both read from
  `effective[]`). Gate+ceiling compressor lane is the workaround.

### vNext branches
- `vnext-shapes` — square, squircle, layers, compass shapes
- `vnext-themes` — vantablack, redhot, orangehot, ember, flan themes + retro/whiteout/tacutacu presets

---

## 14. File map

```
cliamp-plugin-nova/
├── .gitignore              # AGENTS.md, CHECKPOINT*.md, scratchpad/
├── LICENSE                 # MIT, © 8bit64k
├── README.md               # User-facing install + config
├── nova.lua                # The plugin (single file, ~1404 lines)
├── AGENTS.md               # Durable design principles (gitignored, local)
├── docs/
│   └── DESIGN.md           # This document
└── scratchpad/              # Gitignored — harnesses, probes, tests
    ├── render_harness.lua
    ├── band_map_probe_allshapes.lua
    ├── test_mirror_symmetry.lua
    ├── test_ceiling_bleed.lua
    └── ...
```

---

*Last reviewed: 2026-06-09. Version: nova 0.1.0.*
