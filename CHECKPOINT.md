# CHECKPOINT — cliamp-plugin-nova

> Transient rolling work-log. DURABLE design rules live in `AGENTS.md`.
> Prior history archived in `CHECKPOINT.2026-05-31.md` and earlier.

**Last commit:** `628a94c` — density bleed: overdrive thickens +1/+2 rings, BLD debug footer
**Branch:** master. **Repo:** github.com/8bit64k/cliamp-plugin-nova (PRIVATE)
**Local dir:** /home/nick/builds/cliamp-plugin-nova/
**Entry file:** nova.lua (repo root, ~1267 lines). Single Lua file, no require/helpers.

## June 2 — color way changes (from laptop)

Two new themes: **redhot** (ANSI red ramp: 185→9) and **orangehot** (ANSI orange
ramp: 223→9). Extends the "hot" family alongside whitehot and blackhot.
Ghost preset gamma tweaked from 0.99 → 1 (clean integer). No preset profiles
reference the new themes yet — they're available for manual config only.

## June 2 — density bleed

Overdrive now thickens glyphs in adjacent rings +1 and +2 (color bleed only
reaches +1 — density travels further, reinforcing the radial bulge metaphor).
Latch-and-decay at `overdrive_decay` rate (same clock as color bleed) so the
two channels read as one percussive event. No new config knob — piggybacks on
`overdrive_bleed`. Debug footer shows "BLD" when any ring has active density
bleed. Native indicator (overdrive source breathing) planned but not yet built.

---

## What this is (current, accurate — May 31)

A cliamp Lua visualizer that renders a **braille wall** reacting to the 10-band
EQ. Procedurally generated wall (no art file needed). The wall is mapped into
concentric rings, recolors by band level on a themed ANSI 256 ramp, and braille
glyphs thicken (gain dots toward center) as they heat.

Core features built and shipped this session:

### Presets system — one-knob feel selection
`preset` knob bundles dynamics + theme + ring_shape. 8 presets shipped:
default, punch, ethereal, retro, plasma, ghost, bloom, tacutacu.
`cycle_presets = true` auto-rotates through all 8 on cycle_seconds timer.
Individual TOML keys override preset values. Debug flag shows preset name
as a footer bar + fires `cliamp.message()` in init().

### 8 colour themes
amber, crt, vantablack, whitehot, blackhot, aurora, ember, predator, flan.
All 11-stop ANSI 256 glow + 4-stop overdrive.

### 7 ring shapes
square (Chebyshev), diamond (Manhattan), circle (Euclidean), squircle (p=4
Minkowski), wings (vertical stripes, X-only), layers (horizontal strata,
Y-only), compass (four-pointed star). `ring_shape = "cycle"` rotates all 7.

### Dynamics knobs (all built and shipped)
- dead_zone (noise gate, 0-0.5)
- gamma (response curve, 0.1-3.0)
- cell_aspect (terminal cell ratio, 0.2-2.0)
- density_attack / density_release (dot fill/shed speed)
- overdrive / overdrive_decay / overdrive_bleed (bass flare)
- tilt (treble boost)
- attack / release (color smoothing)
- ring_blend (smooth/hard band boundaries)
- max_cols / max_rows (canvas cap)
- render_rate (frame-skip fraction)
- debug (footer + init message)

---

## Tomorrow (June 1) — review session

### 1. Defaults review
All 8 presets + the shared constants (ONSET_MARGIN=0.18, BASE_RATE=0.05,
FLARE_PEAK=0.92) need validation against varied music. Tune by ear.

### 2. Code + doc review
Full audit in `scratchpad/code-doc-review-2026-05-31.md`. Highlights:
- Stale header comment in nova.lua
- Missing `debug` key in README config block
- AGENTS.md feature summary stale (lists only 4 themes)
- vestigial `var` param in apply_num()
- active_profile() called twice per frame
- README shape-cycle section describes old label

### 3. Make repo public
Flip with `gh repo edit 8bit64k/cliamp-plugin-nova --visibility public`.
Update install instructions from "clone + cp" to `cliamp plugins install`.

### 4. Docs still open
- docs/DESIGN.md never written (gold-standard plugin doc — see tubeamp)
- cliamp-plugin-development skill needs toward-center fill + procedural
  generator updates

---

## Full current config surface

```toml
[plugins.nova]                    # entire block OPTIONAL
start = "black"                   # "black" | "stipple"
# art_path = "/abs/path.txt"     # OPTIONAL file override
color_mode = "glow"              # "glow" | "mono" | "passthrough"
ring_shape = "square"            # square | diamond | circle | squircle | wings | layers | compass | cycle
cycle_seconds = 20               # seconds per shape/preset in cycle modes
fit = "contain"                  # "contain" | "fill"
ring_blend = true                # smooth gradient between rings
density = true                   # glyphs thicken toward center
density_attack = 0.6             # 0-1
density_release = 0.15           # 0-1
theme = "amber"                  # amber | crt | vantablack | whitehot | blackhot | aurora | ember | predator | flan
preset = "default"               # default | punch | ethereal | retro | plasma | ghost | bloom | tacutacu
cycle_presets = false            # auto-rotate presets on cycle_seconds
debug = false                    # show preset name as footer + init message
mono_color = 11
attack = 0.55
release = 0.18
overdrive = 0.78
overdrive_decay = 0.82
overdrive_bleed = true
tilt = 0.0
dead_zone = 0.0                  # 0-0.5
gamma = 1.0                      # 0.1-3.0
cell_aspect = 0.5                # 0.2-2.0
max_cols = 0                     # 0=unlimited
max_rows = 0
render_rate = 1.0                # 0.25-1.0
```

---

## Preset quick reference

| Preset    | Theme     | Shape    | Feel                    |
|-----------|-----------|----------|-------------------------|
| default   | amber     | circle   | balanced baseline       |
| punch     | crt       | diamond  | snappy, percussive      |
| ethereal  | aurora    | diamond  | dreamy, slow glow       |
| retro     | ember     | square   | CRT-era grit, hard bands|
| plasma    | predator  | circle   | volatile, electric      |
| ghost     | vantablack| square   | thin, wispy, slow       |
| bloom     | whitehot  | diamond  | bright, fast, blooming  |
| tacutacu  | flan      | diamond  | punchy + warm flan tones|

---

## Architecture quick map (nova.lua, ~1200 lines)

- **Config**: `clean()` strips leaked TOML `#` comments; `cfg_num`/`cfg_bool` absent
  (went with user_set tracking + profile overlay instead). Bool parsed defensively.
- **DIST table**: 7 pluggable distance metrics; reused for max_d + per-cell so they
  can't diverge. `ring_shape="cycle"` rotates via `os.time()`.
- **PRESETS** (colour): `{glow=11, overdrive=4}` per theme. `glow_color` uses ROUND
  not floor.
- **PRESET_PROFILES** (behaviour): bundles dynamics + theme + ring_shape. Profile
  overlay in render() applies values to cfg_* upvalues each frame, respecting
  user overrides. Theme swap also swaps glow_ramp/overdrive_ramp.
- **Braille density**: `FILL_ORDERS[dirx][diry]` (9 toward-center orders),
  `thicken()` memoized per direction. 5.1-safe arithmetic.
- **generate_wall()**: procedural 35x188 source grid. `load_art()` for file path.
  Lazy-loaded on first render. Sentinel = `art_cells`.
- **render()**: profile overlay → smoothing → effective[] (smoothed + flare +
  bleed + dead_zone + gamma) → dens[] envelope → frame-skip gate → canvas cap →
  fit → per-cell loop → debug footer. Hot loop optimized.

## Conventions

- Git author = 8bit64k ALWAYS, never Nick.
- `scratchpad/` is gitignored.
- cliamp does NOT hot-reload — re-`cp nova.lua` + restart.
- Verify with PLAIN `lua`, NOT luajit.
- 8bit64k reviews visual software LIVE himself — give pull/install steps.
- OK with force-push on private repo; reconcile via `git reset --hard origin/master`.