# cliamp ASCII-EQ Visualizer — Brainstorm

> Placeholder project. Not yet implemented. This file captures the design
> conversation so we can pick it back up after tubeamp QA & fixes.

**Status:** parking lot — paused while tubeamp v1.0.0 is finalized.

---

## The brief (from Nick)

> "Let's say I had an ascii art file, could that be the basis of the display
> but have the EQ bands make it dance?"

Translation: a cliamp visualizer plugin that loads a user-supplied ASCII art
file and animates/illuminates it from the 10-band EQ feed.

---

## Design space (8 approaches, pros/cons)

### 1. Vertical-slice column drive — "the art is a sound-reactive equalizer"
Slice into 10 vertical columns, one per EQ band. Each band drives a transform:
y-offset (column bobs), brightness, or vertical squish.

- **Best for:** art with vertical structure (wizard, robot, guitar, tube amp).
- **Failure mode:** horizontal-continuity art (unicorn, landscape) gets shredded
  into a fence of disconnected verticals.

### 2. Y-slice row drive — "the art breathes"
Slice horizontally; bottom rows driven by low bands, top by high. Or wave
propagation: kick drum sends a ripple bottom-to-top.

- **Failure mode:** easily reads as "the whole picture is glitching" instead of
  a feature.

### 3. Glyph illumination — "the art glows in spots"
No motion. Partition art into 10 spatial zones; recolor each by its band level
(amber → hot ramp, reuse tubeamp's color system).

- **Best for:** portraits with separable regions (face → eyes / mouth / cheeks).
- **Failure mode:** flat or unstructured art makes partitioning arbitrary.

### 4. Particle eruption — "the art is the source, EQ is the dust"
Static art silhouette emits particles outward from its outline. Bass = heavy
`█` particles from the bottom, treble = light `·*` from the top. Particles fade.

- **Cliché 2010s music-video aesthetic in ASCII.** Lots of motion, very dramatic.
- **Failure mode:** art gets buried under particle soup. Need particle cap +
  aggressive decay.

### 5. Displacement field — "digital glitch"
Per-character jitter; bands drive `(dx, dy)` offsets per column-region with
smooth interpolation between bands.

- **Failure mode:** unreadable at high amplitude. Needs a hard cap.

### 6. Marquee / scroll modulation — "the art reads the music"
Art scrolls horizontally; EQ modulates scroll speed and vertical jitter.

- **Different vibe — ticker tape.** Works for wider-than-tall art.

### 7. Multi-art crossfade — "EQ picks which is visible"
User provides N art files. Plugin crossfades between them based on overall
energy or which bands are loudest. Quiet → portrait A, loud bass → portrait B,
treble peak → portrait C.

- **Failure mode:** authoring burden — needs N matching-dimension files.

### 8. Spectrogram overlay — "art as canvas, EQ paints over it"
Art is the static backdrop. EQ bars draw on top; art shows through unlit cells.

- **Cheap, looks cool, zero risk of damaging the art.**
- **Like a Winamp spectrum with a wallpaper behind it.**

---

## Recommended v1: combine #1 (column drive) + #3 (glyph illumination)

**Why this pairing:**

- Works on almost any vaguely-centered rectangular art.
- Motion is constrained (max ~2 char vertical displacement) — art stays
  recognizable.
- Color does the "music-reactive" heavy lifting; motion does the "alive"
  heavy lifting.
- Reuses tubeamp's color ramp → consistent visual family.
- Single Lua file, well under 10ms/frame budget for any reasonable art size.

### Mechanics

1. Slice art into 10 vertical columns.
2. Per column, compute smoothed band level (asymmetric attack/release, same as
   tubeamp).
3. Apply vertical bob: column y-offset = `smoothed * bob_max` (default ±2 chars).
4. Apply color illumination via tubeamp's amber→white-hot ramp.
5. Bands above `overdrive` threshold push column an extra char AND flare red.
6. Phosphor afterglow on color — slow release so columns glow after transient.

### Proposed config schema

```toml
[plugins.ascii-eq]
art_path = "~/.config/cliamp/art/myportrait.txt"   # required
bob_max = 2                                         # max vertical displacement (chars)
bob_direction = "both"                              # "up" | "down" | "both"
color_mode = "glow"                                 # "glow" | "mono" | "passthrough"
mono_color = 11                                     # ANSI 256 index for mono mode
attack = 0.55                                       # same defaults as tubeamp
release = 0.18
overdrive = 0.78
```

---

## Edge cases to decide upfront

| Question | v1 answer |
|----------|-----------|
| Art wider than terminal? | Clip with horizontal centering. (Not scale, not scroll.) |
| Art shorter than pane? | Center vertically; leave background. |
| Odd width vs 10 columns? | Floor `width / 10`; leftover cols get last band. |
| Mood-based art swap? | Out of scope. v2 = approach #7 crossfade. |
| Multi-frame animated `.txt`? | v2. v1 = single static frame. |
| Art file missing at load? | Don't crash. Render placeholder error message. Use `cliamp.fs.exists()` to check. |

---

## Constraints (carried from tubeamp's DESIGN.md)

- 20 FPS render budget, 10 ms per call.
- Sandbox lets us `cliamp.fs.read()` from anywhere (1 MB cap).
- ANSI passthrough confirmed working — `.ans` files render verbatim.
- `rows`/`cols` may change — must clip/letterbox dynamically.
- Single Lua file, no `require`, no external deps.

---

## Open decisions (need Nick's input before v1)

1. **Combo choice:** #1+#3 (column bob + glow) — my recommendation — or one of
   the splashier options like #4 (particles) for max drama?

2. **Test art file:** need a placeholder ASCII art to build against. Could be:
   - A guitar / tube amp / synth (visualizer-themed)
   - A CRT monitor (Phosphor-themed)
   - A Phosphor logo
   - Nick's face in ASCII
   - Anything tall and central enough to slice into 10 columns

3. **Plugin name:** candidates —
   - `dancer` — generic, focuses on the verb
   - `ascii-eq` — descriptive
   - `tubeamp-portrait` — positions as part of the tubeamp family
   - `phosphor-art` — claims the brand
   - `glowboard` — invented, suggestive

   Repo would be `cliamp-plugin-<name>` per cliamp's convention.

---

## Relationship to tubeamp

This plugin should reuse tubeamp's color system verbatim (the 11-step amber ramp
and 4-step overdrive ramp). If both plugins are installed, they should feel like
the same family. Consider extracting the color ramp into a doc reference so both
plugins can copy it without diverging.

Tubeamp's existing assets to reuse / mirror:
- ANSI helper functions (`fg256`, `bold`, `reset`)
- Glow ramp + overdrive ramp arrays
- Asymmetric smoother (attack/release pattern)
- Peak tracker (might not be needed here — depends on whether we surface peaks)
- `init` / `render` / `destroy` lifecycle pattern

---

## Pre-build checklist (when we resume)

- [ ] Tubeamp v1.0.0 QA'd and any fixes merged.
- [ ] Nick picks the combo (#1+#3, or alternative).
- [ ] Nick supplies test ASCII art file (or I generate a placeholder).
- [ ] Nick picks the plugin name.
- [ ] Create `cliamp-plugin-<name>` repo under 8bit64k (private during QA).
- [ ] Initialize with tubeamp's DESIGN.md structure as the template.

---

*Captured: 2026-05-28. Resumes after tubeamp fixes.*
