# cliamp-plugin-dance — Agent Context

## Status

**Working v0.1.** A cliamp visualizer that recolors a user-supplied ASCII/braille
art file from the 10-band EQ. The art's glyphs are preserved — only color reacts.

- Local dir: `/home/nick/builds/cliamp-plugin-ascii-eq/` (NOT renamed; repo IS `cliamp-plugin-dance`)
- Repo: `github.com/8bit64k/cliamp-plugin-dance` (PRIVATE, manual install — clone + cp)
- Entry file: `dance.lua` (repo root — required by cliamp plugin manager)
- Read `CHECKPOINT.md` for current session state and the tuning backlog.

## Load these skills first

- `cliamp-plugin-development` — the plugin API contract, sandbox quirks, color
  ramps, render harness, and family conventions. MANDATORY before touching `dance.lua`.

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

2. **The art is an immutable canvas.** The visualizer never moves or replaces the
   user's glyphs — they carry the image density. Audio drives COLOR only (with the
   deferred exception of bass-transient jitter, which would shift the whole field
   briefly on a kick, then settle — see tuning backlog).

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
