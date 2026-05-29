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

8bit64k is comparing the 3 arts on the laptop (cliamp, real music, mini + full
panes). Needs to report:
- Which art reads best at mini (5-row) and full (Shift+V)?
- Is braille Ruby worth more tuning (tighter crop / harder background knockout /
  hand-clean stray dots), or is the CRT the keeper?
- Earlier feedback: "on mini it's difficult; on full it's pretty good." Braille
  was 8bit64k's idea to improve mini quality.

This decides whether braille-from-photo becomes part of the recommended pipeline
or stays "synthetic art only."

---

## Next steps (after 8bit64k's art verdict)

1. Lock the default test art.
2. Tune smoothing feel (attack/release) + spectral `tilt` (lifts outer/treble
   rings) on real music.
3. Add the DEFERRED bass-transient jitter (gate on low-band overdrive crossing,
   fast decay — punch on kick, not continuous).
4. THEN fold all session learnings into the `cliamp-plugin-development` skill in
   ONE pass (pitfalls: tilde-no-expansion, init-may-not-fire/lazy-load, 5-row
   default pane, downscale-to-fit pattern, braille-art generation pipeline).
   8bit64k explicitly asked to wait until v0.1 is verified on their end before
   documenting — do NOT document unverified.

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
