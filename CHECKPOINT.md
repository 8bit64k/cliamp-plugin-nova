# CHECKPOINT — cliamp-plugin-nova

> Transient rolling work-log. DURABLE design rules live in `AGENTS.md`.
> Prior history archived in `CHECKPOINT.2026-05-31.md` and earlier.

**Last commit:** (pending — release prep)
**Branch:** master. **Repo:** github.com/8bit64k/cliamp-plugin-nova (PUBLIC)
**Local dir:** /home/nick/builds/cliamp-plugin-nova/
**Entry file:** nova.lua (repo root, ~1302 lines). Single Lua file, no require/helpers.

## June 5 — final push: public release prep

Release readiness pass. Cleaned up for v0.1.0 public release.

### Changes this session
- Moved `crt_max.txt` + `crt_max_raw.txt` (untracked test art) to scratchpad/
- Fixed stale "WHITE-HOT" comment → "PEAK FLARE" in nova.lua blend section
- Added LICENSE (MIT, © 8bit64k)
- Rewrote README.md for public release: removed dev warning, added `cliamp plugins install` instructions, updated status section
- Updated AGENTS.md: private→public, added plugin manager install line
- Updated docs/DESIGN.md: removed private-QA references, updated install section, visibility status
- Syntax check: `luac -p nova.lua` passes

### Still open
- `breathe-experiment` branch (snake rotate indicator) — kept, not merged
- Shimmer lane (pipeline split for density-full + color-compressed) — vNext
- Responsive layout tiers — vNext
- Truecolor mode — vNext

### Release checklist
- ✅ Syntax check passes
- ✅ No stale config key references in code
- ✅ README config block matches nova.lua config surface
- ✅ AGENTS.md feature summary current
- ✅ DESIGN.md public references updated
- ✅ LICENSE added
- ⬜ Make repo public, tag v0.1.0

## June 4 — symmetry bug, ceiling-bleed fix, code review (4 commits: 4ffd5aa → 43f1e4c)

Long debugging session. Nick reported the bloom wall looked asymmetric;
took far too long to confirm because (a) the render harness still used OLD
config keys after the June-3 renames so it silently rendered defaults, and
(b) my mirror-symmetry test used wrong pairing (H-1-i vs geometric 2*ocy-oy)
and manufactured false passes. Lesson logged in memory: pixel-analyze Nick's
screenshots FIRST, verify the test itself before trusting green.

### Bloom mirror symmetry — center row/column on ODD panes (4ffd5aa)
Root cause: center-axis cells (dirx==0 or diry==0) sit ON the mirror axis,
so they must self-mirror. At odd fill counts they added a single off-axis
dot — same dot COUNT, wrong POSITION (exactly as Nick described). Only
visible on odd-dimensioned panes (the common fullscreen case); even panes
have no on-axis cell so it stayed hidden.
Fix: (1) center-axis FILL_ORDERS rewritten to list dots in mirror-PAIRS
(V-pairs diry=0, H-pairs dirx=0) and QUADS for dead center; (2) thicken()
snaps the add count for center-axis cells — pairs (even) for single-centered,
quads (mult-of-4) for dead center; off-axis cells unchanged. dkey encodes
dirx/diry: dkey 4 = dead center, dkey in {1,3,5,7} = one axis centered.
KNOWN edge case (accepted): the add-snap can leave a 1-cell gap on the
outer ring along the center line at some heights — far milder than the
whole-wall asymmetry, no clean fix without a trade-off, left as-is.
New test scratchpad/test_mirror_symmetry.lua checks EXACT opposite-cell
mirroring (the old test_center_fill only checked "leans toward center" and
missed this) — passes 35/35 shape×pane combos.

### Ceiling-bleed escape — flare detector now ceiling-limited (f54ab66)
Bug Nick chased through two prior reverts: with overdrive=0.90, ceiling=0.80
the bleed still fired and escaped the cap. Root cause: the overdrive flare
detector read raw smoothed[i], which ceiling never limits; ceiling only
clamps the color path at the end, and bloom_bleed[] is a separate array that
clamp never touches. Prior attempts moved bleed AFTER ceiling and tested
effective[i] (carries sustained signal → fired constantly) — wrong lever.
Correct fix at the SOURCE: clamp detector input s = min(smoothed[i], ceiling).
If ceiling=0.80, overdrive=0.90 is unreachable → no flare, no bleed, no
bloom_bleed. ceiling=1.0 (off) leaves the detector byte-identical.

### Code review cleanup + bloom preset → whiteout (43f1e4c)
Opus code review of the rapid-rename debris:
- Removed dead char_at() (old file-art path, never called)
- Removed vestigial 'var' param from apply_num() + 10 call sites
- Clamp attack/release/overdrive at config-read AND apply_num (was unclamped)
- Aligned ragged user_set_* block
- Fixed stale comments: file header, ceiling 'gamma'→'knee', preset list
  (punchy→punch, "five"→8), phantom 'ring_of', "white-hot bleed bands 2-3"
- Renamed `bloom` PRESET → `whiteout` (collided with the bloom feature
  toggle). Feature toggle stays `bloom`. Invalid `bloom` preset → default.
NOTE: art_lines is NOT dead (read at the row-extract loop + lazy-load
sentinel) — checked before deleting.

### Also fixed earlier this session
- Mirror-symmetric stipple base ⠡→⠤, and clean() strips TOML quotes (e5411cb):
  inline TOML comment on `start = "black"` leaked quotes past clean(),
  falling back to stipple with an asymmetric base. README TOML comments
  moved to their own lines so copy-paste is safe.
- clean() type guard + string.gsub() not v:gsub() (ed500de, 2248b2d):
  gopher-lua panicked on v:gsub for non-string config values.

### Current pedalboard

```
Gate / Ceiling       — noise gate + limiter
Attack / Release     — color smoothing (compressor)
Overdrive / Sustain / Blend — drive + tail + mix (OD pedal)
Knee                 — response curve (compressor knee)
Tilt                 — spectral EQ
Bloom / Bloom Attack / Bloom Release — glyph thickness (second envelope)
```

Pipeline: smoothing → flare(ceiling-limited) → bleed → gate → knee → ceiling → bloom → color

### Shimmer lane (vNext)

Single-pipe limitation: bloom chases effective[] post-ceiling. True shimmer
(density-full, color-compressed) needs pipeline split — bloom taps pre-ceiling.
XOR mask shimmer also noted as an alternative texture approach.

## June 3 — pedalboard rename session (5 commits: fa7d390 → dcf5886)

Full knob rename to guitar-pedal convention.

### Round 1: gate + ceiling (fa7d390)
- `dead_zone` → `gate` — noise gate threshold
- New `ceiling` knob (0.01–1.0, default 1.0=off) — limiter brick wall

### Round 2: pipeline order fix (bd36052)
- gate → knee → ceiling (limiter last, EQ-before-limiter mastering order)

### Round 3: sustain, blend, knee (a0547e8)
- `overdrive_decay` → `sustain`, `overdrive_bleed` → `blend`, `gamma` → `knee`

### Round 4: bloom (76b2c89)
- `density` → `bloom`, `density_attack/release` → `bloom_attack/release`
- Internal: dens[] → bloom[], dens_bleed → bloom_bleed

### Round 5: UK→US spelling (dcf5886)
- colour→color, behaviour→behavior

## June 2 — DESIGN.md written (#4)

`docs/DESIGN.md`: 943 lines, 15 sections, following tubeamp's gold-standard format.
Covers full architecture, 11 color themes, 7 ring shapes, bloom mutation with
toward-center fill + bloom bleed, 8 preset profiles, effective[] layer pipeline
order, performance controls, sandbox constraints, testing procedures, and 26-item
agent handoff checklist. Pushed as `c0b21c4`.

## June 2 — breathe snake experiment (branch, not merged)

Branch `breathe-experiment` (off `c0b21c4`, pushed as `d4011ae`): during overdrive
bleed, source ring cells (bands 1-2) show a 2-dot snake rotating clockwise around
the braille cell perimeter — 8 phases, 2.5 rotations/sec at 20fps. Snake replaces
normal bloom while active; fires independently of bloom knob. Works correctly
in frame-stepping test; needs live visual tuning (spacing between rings, contrast
against bleed neighbors). Keep on branch; do not merge to master yet.

## June 2 — color way changes (from laptop)

Two new themes: **redhot** (ANSI red ramp: 185→9) and **orangehot** (ANSI orange
ramp: 223→9). Extends the "hot" family alongside whitehot and blackhot.
Ghost preset knee tweaked from 0.99 → 1 (clean integer). No preset profiles
reference the new themes yet — they're available for manual config only.

## June 2 — bloom bleed

Overdrive now thickens glyphs in adjacent rings +1 and +2 (color bleed only
reaches +1 — bloom travels further, reinforcing the radial bulge metaphor).
Latch-and-decay at `sustain` rate (same clock as color bleed) so the
two channels read as one percussive event. No new config knob — piggybacks on
`blend`. Debug footer shows "BLD" when any ring has active bloom
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
default, punch, ethereal, retro, plasma, ghost, whiteout, tacutacu.
`cycle_presets = true` auto-rotates through all 8 on cycle_seconds timer.
Individual TOML keys override preset values. Debug flag shows preset name
as a footer bar + fires `cliamp.message()` in init().

### 8 color themes
amber, crt, vantablack, whitehot, blackhot, aurora, ember, predator, flan.
All 11-stop ANSI 256 glow + 4-stop overdrive.

### 7 ring shapes
square (Chebyshev), diamond (Manhattan), circle (Euclidean), squircle (p=4
Minkowski), wings (vertical stripes, X-only), layers (horizontal strata,
Y-only), compass (four-pointed star). `ring_shape = "cycle"` rotates all 7.

### Dynamics knobs (all built and shipped)
- gate (noise gate, 0-0.5)
- ceiling (limiter, 0.01-1.0)
- knee (response curve, 0.1-3.0)
- cell_aspect (terminal cell ratio, 0.2-2.0)
- bloom_attack / bloom_release (dot fill/shed speed)
- overdrive / sustain / blend (bass flare)
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
bloom = true                   # glyphs thicken toward center
bloom_attack = 0.6             # 0-1
bloom_release = 0.15           # 0-1
theme = "amber"                  # amber | crt | vantablack | whitehot | blackhot | aurora | ember | predator | flan
preset = "default"               # default | punch | ethereal | retro | plasma | ghost | whiteout | tacutacu
cycle_presets = false            # auto-rotate presets on cycle_seconds
debug = false                    # show preset name as footer + init message
mono_color = 11
attack = 0.55
release = 0.18
overdrive = 0.78
sustain = 0.82
blend = true
tilt = 0.0
gate = 0.0                       # 0-0.5, noise gate: clamp bands below this to 0
ceiling = 1.0                    # 0.01-1.0, limiter: clamp bands above this (1.0=off)
knee = 1.0                      # 0.1-3.0
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
| whiteout  | whitehot  | diamond  | bright, fast, blooming  |
| tacutacu  | flan      | diamond  | punchy + warm flan tones|

---

## Architecture quick map (nova.lua, ~1200 lines)

- **Config**: `clean()` strips leaked TOML `#` comments; `cfg_num`/`cfg_bool` absent
  (went with user_set tracking + profile overlay instead). Bool parsed defensively.
- **DIST table**: 7 pluggable distance metrics; reused for max_d + per-cell so they
  can't diverge. `ring_shape="cycle"` rotates via `os.time()`.
- **PRESETS** (color): `{glow=11, overdrive=4}` per theme. `glow_color` uses ROUND
  not floor.
- **PRESET_PROFILES** (behavior): bundles dynamics + theme + ring_shape. Profile
  overlay in render() applies values to cfg_* upvalues each frame, respecting
  user overrides. Theme swap also swaps glow_ramp/overdrive_ramp.
- **Braille bloom**: `FILL_ORDERS[dirx][diry]` (9 toward-center orders),
  `thicken()` memoized per direction. 5.1-safe arithmetic.
- **generate_wall()**: procedural 35x188 source grid. `load_art()` for file path.
  Lazy-loaded on first render. Sentinel = `art_cells`.
- **render()**: profile overlay → smoothing → effective[] (smoothed + flare +
  bleed + gate + knee + ceiling) → dens[] envelope → frame-skip gate → canvas cap →
  fit → per-cell loop → debug footer. Hot loop optimized.

## Conventions

- Git author = 8bit64k ALWAYS, never Nick.
- `scratchpad/` is gitignored.
- cliamp does NOT hot-reload — re-`cp nova.lua` + restart.
- Verify with PLAIN `lua`, NOT luajit.
- 8bit64k reviews visual software LIVE himself — give pull/install steps.
- OK with force-push on private repo; reconcile via `git reset --hard origin/master`.