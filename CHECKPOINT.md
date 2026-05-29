# CHECKPOINT — cliamp-plugin-dance (formerly cliamp-plugin-ascii-eq)

**Status:** v0.1 working. Square-ring concentric glow visualizer renders at all
pane sizes. Three test arts in repo. Paused mid-art-comparison while 8bit64k
runs errands.

**Last commit:** see `git log --oneline -1` (latest = braille ruby.txt swap).
**Branch:** master. **Repo:** github.com/8bit64k/cliamp-plugin-dance (PRIVATE).

---

## What this project is

A cliamp Lua visualizer that loads a user-supplied ASCII/braille art file and
makes it glow to the 10-band EQ. The art is mapped into 10 concentric SQUARE
rings (Chebyshev distance from center): band 1 (32 Hz bass) drives the center,
each band outward, band 10 (16 kHz treble) the outer edge. Bass-heavy music
keeps the center lit/throbbing; sparse treble makes the edges flare occasionally.
Reuses tubeamp's amber glow ramp so the plugins feel like one family.

- Local dir: `/home/nick/builds/cliamp-plugin-ascii-eq/` (dir NOT renamed; repo IS `cliamp-plugin-dance`)
- Entry file: `dance.lua` (repo root — required by cliamp plugin manager)
- Sibling: `~/builds/cliamp-plugin-tubeamp/` (shipped v1.2.0; its docs/DESIGN.md is the gold standard)
- Upstream cliamp checkout: `~/builds/cliamp/` (read luaplugin/*.go for ground truth)

---

## Design decisions (locked with 8bit64k)

1. **Approach:** concentric SQUARE rings (Chebyshev), bass=center / treble=edge.
   This came from 8bit64k's own idea ("lowest bands map to inner areas, next
   around that") + the keystone observation that music is bass-heavy / treble-
   sparse. Chosen over the originally-recommended #1+#3 (column-bob + glow).
2. **Square rings**, not circles/diamond. x scaled 0.5 to correct ~2:1 cell aspect.
3. **Glyphs preserved, only color reacts** (don't replace art chars — they carry
   the image density). passthrough/glow/mono modes.
4. **Jitter DEFERRED** to a later version. Build/tune color moods first, then add
   bass-transient-gated global jitter (punches on the kick, otherwise still —
   NOT continuous bass shake).
5. **Name:** "dance" (provisional, renameable). Installs as visualizer `dance`.
6. **Private repo + manual install** (clone + cp, README has commands). NOT public.
7. **Art lives in the clone**, not in cliamp's app dirs. `art_path` = absolute
   path (tilde-expanded by the plugin).

---

## Bugs found + fixed this session (all real cliamp gotchas)

1. **Tilde not expanded.** `cliamp.fs.read/exists` call Go `os.ReadFile/os.Stat`
   directly — no shell `~` expansion. Plugin now expands `~`, `~/`, `$HOME`,
   `${HOME}` via `os.getenv("HOME")`. (`os.getenv` IS available in the sandbox;
   only os.execute/remove/rename/exit/setlocale/tmpname are stripped.)
2. **init may not populate state / fire as expected.** "no art loaded" appeared
   because art only loaded in `p:init`. Plugin now LAZY-LOADS art on first
   `render()` if not already loaded. Robust to host init-timing.
3. **5-row default pane.** cliamp gives visualizers `DefaultVisRows = 5` normally;
   fullscreen (Shift+V) = `max(5, (termheight-10)*4/5)`. Width = `PanelWidth`.
   ruby was 30 rows → old code returned "" (blank) when art > pane. FIXED:
   render now DOWNSCALES art to fit ANY pane (nearest-neighbor, aspect-preserved).
   Ring geometry computed per-OUTPUT-cell, so it's resolution-independent.

Render call signature (verified in ui/visualizer.go:871 + luaplugin/visualizer.go):
`render(bands, frame, rows, cols)` — bands 1-indexed table, returns string.
cliamp reuses last frame silently on render error; errors go to
`~/.config/cliamp/plugins.log` as `[dance] error: ...`, NEVER the UI.

---

## Current state of the art files (3 in repo)

| File | What | Notes |
|------|------|-------|
| `ruby.txt` | Braille render of Ruby (8bit64k's French bulldog) head | NEW. Cropped from ruby.jpeg + stylized. Reads as a Frenchie but left edge has some leftover background fill. |
| `ruby_ascii.txt` | Original hand-ASCII portrait | Backup of the first test art. |
| `crt.txt` | Braille CRT monitor, generated from scratch (SVG) | Crispest — synthetic high-contrast source brailles cleanest. Screen centered = bass glow. |

**Braille-from-photo recipe (in scratchpad, NOT committed):**
- Source: `scratchpad/ruby.jpeg` (3024x4032 iPhone photo, Frenchie in orange harness)
- Crop head: `magick ruby.jpeg -crop 2400x2400+80+900 +repage ruby_head.png`
- Stylize: `magick ruby_head.png -colorspace Gray -morphology Convolve Gaussian:0x2 -sigmoidal-contrast 10x52% -level 8%,72% -posterize 5 ruby_style2.png`
- Convert: `chafa --symbols braille --fill braille -c none --size 46x26 ruby_style2.png | sed 's/[[:space:]]*$//'`

**Braille-from-SVG recipe (CRT):**
- `scratchpad/crt.svg` → `rsvg-convert crt.svg -o crt.png --width=560 --height=600`
- `chafa --symbols braille --fill braille -c none --size 50x30 crt.png`

KEY INSIGHT: braille (2x4 dots/cell, ~8x resolution) survives downscaling far
better than single-glyph ASCII. Synthetic high-contrast art brailles cleanly;
casual photos need background-knockout (level) + posterize or they come out as a
solid blob (dark=filled) or pure noise (edge-detect on busy background).

---

## OPEN QUESTION (waiting on 8bit64k — this is where we resume)

RESOLVED: art comparison done. noise_braille.txt + art_max.txt are the primary test
files. crt.txt is the crispest synthetic braille. ruby.txt kept for sentimental value.

Next session: tackle ring shape (#1) and ring blend (#2) from the tuning list.
Then jitter (#9, still deferred per 8bit64k's earlier call).

---

## v0.1 feature summary (shipped this session)

**Rendering:**
- Square concentric rings (Chebyshev), bass=center, treble=edge
- Downscale-to-fit any pane (nearest-neighbor, aspect-preserved)
- Ring geometry computed per-output-cell (resolution-independent)
- Preserves source glyphs, only color reacts

**Config keys (current):**
```toml
[plugins.dance]
art_path    = "~/Code/cliamp-plugin-dance/noise_braille.txt"
color_mode  = "glow"       # glow | mono | passthrough
theme       = "aurora"     # amber (warm tubeamp) | crt (green phosphor) | vantablack (grayscale) | aurora (teal-cyan-green)
mono_color  = 11           # ANSI 256, for mono mode
attack      = 0.55
release     = 0.18
overdrive   = 0.78
tilt        = 0.0          # spectral boost for sparse treble; try 0.5
```

**Theme presets:** 4 built-in, all 11-stop ANSI 256 ramps:
- `amber` — original tubeamp warm amber (232,234,52,94,130,166,202,208,214,220,226)
- `crt` — green phosphor (232,22,28,34,40,46,48,82,118,154,190)
- `vantablack` — mono-ish grayscale (232,234,238,242,246,249,251,253,254,255,231)
- `aurora` — cool teal-cyan-green (232,23,30,36,42,48,83,119,155,191,195)

Architecture: `PRESETS[name] = {glow={...}, overdrive={...}}`. Single swap point
for future upstream theme integration (add `from_cliamp_theme()` that returns
same shape, swap one line).

**Bugs fixed this session (cliamp gotchas):**
1. Tilde not expanded → Plugin expands `~`/`$HOME` itself
2. Init may not fire → Lazy-load art on first render
3. 5-row default pane → Downscale to fit, works at any pane size
4. Inline comments leak into config values → `clean()` strips `#` comments defensively
5. Monochrome presets blend together → Wide ANSI gaps between ramp stops

**Test art files (5 in repo):**
- `noise_braille.txt` — 28×150 random braille (best for color engine testing)
- `art_max.txt` — 23-row stacked "PHOSPHOR" banner
- `crt.txt` — braille CRT monitor (crispest synthetic)
- `ruby.txt` — braille Ruby (Frenchie head)
- `ruby_ascii.txt` — original hand-ASCII portrait (backup)

**Tuning list (deferred):**
1. Ring shape (square/circle/diamond)
2. Ring blend (smooth band boundaries)
3. Gamma / response curve
4. Dead zone
5. Aspect ratio
6. Ring count
7. Overdrive behavior
8. Bass-transient jitter (still deferred per 8bit64k)

*Checkpoint updated 2026-05-29. Resume at ring shape + ring blend.*

---

## Config (README has full version)

```toml
[plugins.dance]
art_path = "~/Code/cliamp-plugin-dance/ruby.txt"   # or crt.txt / ruby_ascii.txt
color_mode = "glow"        # "glow" | "mono" | "passthrough"
attack = 0.55
release = 0.18
overdrive = 0.78
tilt = 0.0                 # >0 lifts higher bands so sparse treble lights edges
```

## Install / update on remote laptop

```bash
cd cliamp-plugin-dance && git pull
cp dance.lua ~/.config/cliamp/plugins/dance.lua   # cliamp does NOT hot-reload; restart after copy
```

---

## Conventions reminder (from builds/AGENTS.md)

- Git author = 8bit64k ALWAYS (never Nick). Already configured local user.name/email.
- scratchpad/ is gitignored — working notes (harnesses, source jpeg, SVG, PNGs) stay local.
- Verify end-to-end, not just syntax. Harness lives at scratchpad/render_harness.lua.

*Checkpoint written 2026-05-29 mid-session. Resume at the OPEN QUESTION above.*
