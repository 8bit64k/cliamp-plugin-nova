# cliamp-plugin-nova — Agent Context

## Status

**Working v0.1.** nova is a **braille-wall visualizer**: a dense braille texture
(e.g. `dots_braille.txt`) under `fit="fill"` that the 10-band EQ lights AND
thickens. SCOPE DECISION (2026-05-29): nova is braille-wall ONLY. ASCII portrait
art (Ruby, the CRT) has real problems at cliamp's tiny default pane and will be a
SEPARATE plugin. Don't re-add portrait-preservation hedging here.

- Local dir: `/home/nick/builds/cliamp-plugin-nova/` (NOT renamed; repo IS `cliamp-plugin-nova`)
- Repo: `github.com/8bit64k/cliamp-plugin-nova` (PRIVATE, manual install — clone + cp)
- Entry file: `nova.lua` (repo root — required by cliamp plugin manager)
- Read `CHECKPOINT.md` for current session state and the tuning backlog.

## Load these skills first

- `cliamp-plugin-development` — the plugin API contract, sandbox quirks, color
  ramps, render harness, and family conventions. MANDATORY before touching `nova.lua`.

## Design principles (DURABLE — do not let these die in CHECKPOINT)

> CHECKPOINT.md is a transient rolling work-log; things roll over and get lost
> there. Durable design values live HERE. If a principle matters long-term, put
> it in this file, not (only) in CHECKPOINT.

1. **Retro-faithful > pixel-perfect.** cliamp pays homage to old-school computing,
   and these plugins do by extension. Do NOT chase a flawless/clean aesthetic in
   every case. Don't over-smooth, don't force perfect geometry (circles needn't be
   geometrically perfect), let CRT-era roughness/banding stand where it reads as
   character. When a tuning knob trades "correct" for "more polished but less retro,"
   lean retro and make the polish OPT-IN, not the default.

2. **Audio drives color AND density; it does not move the art.** Color: each cell
   recolors by its ring's level. Density (`density`, default on): braille glyphs
   thicken toward solid ⣿ as they heat (OR dots in, "toward full"), so the wall
   gains matter on peaks, not just brightness. Only braille glyphs mutate; the art
   is never translated/shaken (positional jitter #8 is shelved — density displaced
   it as the texture reaction). NOTE: this is the deliberate exception to the old
   "immutable canvas" rule — that rule protected PORTRAITS, and nova is now
   braille-wall-only, so glyph mutation is correct here.

   **Density fills TOWARD CENTER (2026-05-30).** Because the wall is mapped into
   concentric rings around the pane center, the dots a heating cell adds accrete
   TOWARD that center, not always bottom-up — this reinforces the radial structure
   instead of fighting it. A cell left of center fills from its right edge inward;
   above-center fills from its bottom up; corners fill from the dot nearest center.
   Implemented as 9 direction-specific fill orders (`FILL_ORDERS[dirx][diry]`,
   signs in {-1,0,1}) chosen per cell; `thicken()` is memoized per direction so
   there's no per-frame cost. This is NOT a knob — it's the correct default for a
   radial visualizer; do not revert to a single fixed fill order.

   **The wall MUST be mirror-symmetric (V and H) — INVARIANT (2026-06-04).**
   Opposite cells across the pane center are exact dot-mirrors. This is non-
   negotiable; it's the most visually obvious defect when broken. Two subtleties
   that caused a long bug hunt:
   (a) Off-axis quadrant orders mirror each OTHER (up-left ↔ down-left etc.).
   (b) CENTER-AXIS cells (dirx==0 or diry==0) sit ON the mirror axis and must
       self-mirror. A single dot can't straddle the axis, so at odd fill counts
       they break. Fix: center-axis FILL_ORDERS list dots in mirror-PAIRS (quads
       for dead center), and `thicken()` snaps the add count for those cells —
       even (pairs) for single-centered, mult-of-4 (quads) for dead center
       (dkey 4 = dead center, dkey {1,3,5,7} = one axis centered). Off-axis
       cells take `add` as-is. The trade-off: a possible 1-cell gap on the outer
       center-line ring at some heights — accepted, far milder than asymmetry.
   VERIFY any fill-order or thicken change with `scratchpad/test_mirror_symmetry.lua`
   (checks EXACT opposite-cell mirroring across 7 shapes × 5 pane sizes). The
   older `test_center_fill.lua` only checks "leans toward center" and will NOT
   catch a symmetry break — do not trust it alone.

   **Ceiling caps EVERYTHING, including bleed — INVARIANT (2026-06-04).** If
   `overdrive > ceiling`, the overdrive threshold is unreachable, so no flare, no
   color bleed, and no `bloom_bleed` (a separate array the final color-ceiling
   clamp never touches). Enforced by clamping the flare DETECTOR input to the
   ceiling (`s = min(smoothed, ceiling)`), NOT by reordering the pipeline — two
   reverted fixes tried moving bleed after ceiling / testing effective[i] and
   broke it (effective carries sustained signal → bleed fires constantly). VERIFY
   any change to the flare/bleed/ceiling path with `scratchpad/test_ceiling_bleed.lua`
   (asserts bleed never fires when od>ceil; proven to fail against the pre-fix code).

   **TEST-FIRST for any audio-path fix (do not skip — this is not optional).**
   Both the symmetry bug and the ceiling-bleed bug cost Nick live debugging time
   because fixes shipped with no guard. Before pushing ANY change to the
   fill/thicken/flare/bleed/ceiling logic: write or extend a scratchpad test that
   FAILS against the bug and PASSES against the fix, and run it. A green test on
   stale or absent coverage is worse than none.

   **Bug-hunt lesson (2026-06-04, do not repeat):** when Nick reports a visual
   defect, pixel-analyze his screenshot FIRST (`convert x.png -colorspace gray
   -depth 8 txt:-`). Do NOT argue from harness tests until you've (1) confirmed
   the harness uses CURRENT config keys — after any knob rename the harness/probe
   stubs must be updated in lockstep or they silently render defaults — and (2)
   verified the test's own pairing math (geometric mirror is `2*ocy-oy`, NOT
   `H-1-i`). A green test on stale tooling is worse than no test.

3. **User content stays in the user's clone.** `art_path` is an absolute path the
   plugin reads in place. Never copy art into cliamp's own dirs (`~/.config/cliamp/...`).
   App dirs hold app stuff, not the user's content.

4. **Single Lua file, defensive config.** No `require`/helper files. Every
   `p:config(...)` read goes through `clean()` (cliamp's TOML parser leaks inline
   `#` comments into values). Numeric configs: `tonumber(clean(...))`. Unknown
   enum values fall back to a safe default, never crash.

5. **Verify geometry before color.** For any spatial mapping (rings/zones), dump
   the numeric band grid (`scratchpad/band_map_probe_allshapes.lua`) and confirm
   the geometry BEFORE judging ANSI output. Then run the render harness.

## Feature summary (v0.1)

- Concentric rings, bass=center / treble=edge. `ring_shape`: square (Chebyshev),
  diamond (Manhattan), circle (Euclidean), or `cycle` (auto-rotates for review).
- `fit`: `contain` (aspect-preserved, letterboxed — for pictures) or `fill`
  (stretch to whole pane — for textures like the braille wall).
- `ring_blend` (default on): interpolate level between adjacent rings for a smooth
  radial gradient instead of hard band steps.
- Themes: amber / crt / vantablack / aurora (11-stop ANSI 256 ramps).
- Color modes: glow / mono / passthrough.

## Discovery worth remembering

The **braille wall** (a dense, even dot-field art like `dots_braille.txt`) under
`fit="fill"` + `ring_blend` reads less like "a picture reacting" and more like a
genuine standalone visualization. 8bit64k flagged this as a discovery ("the braille
wall IS the product — end-user ASCII art"). NOT yet a decision to build an art
gallery — but if it becomes one, the candidate walls live in `scratchpad/`
(`_cand_*`, `_dot_*`) and the blessed ones at repo root (`dots_braille.txt`,
`dots_dense_braille.txt`, `weave_braille.txt`, `noise_braille.txt`).

## Sibling / upstream

- `~/builds/cliamp-plugin-tubeamp/` — shipped sibling (v1.2.0); its `docs/DESIGN.md`
  is the gold-standard plugin doc. Color ramp + ANSI helpers shared so the family
  feels consistent.
- `~/builds/cliamp/` — upstream checkout. Ground truth in `docs/plugins.md`,
  `luaplugin/*.go`, `ui/visualizer.go`. NOTE: cliamp gives visualizers 5 rows by
  default (`DefaultVisRows`); a big pane is Shift+V (full-screen), not a plugin setting.

## Conventions (inherited from /home/nick/builds/AGENTS.md)

- Git author = 8bit64k ALWAYS, never Nick.
- `scratchpad/` is gitignored — harnesses, probes, source images, candidate art
  stay local; never part of a release.
- cliamp does NOT hot-reload — re-`cp` the file and restart after every change.
- See `BRAINSTORM.md` for the original 8-approach design exploration.
