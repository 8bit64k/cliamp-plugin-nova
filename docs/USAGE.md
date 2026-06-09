# USAGE.md — cliamp-plugin-nova

> How to tune nova to get the look and feel you want. Presets as case studies,
> the compressor lane explained, and common recipes.

---

## 1. Orientation — three layers

Think of nova as three layers stacked on top of each other:

| Layer    | What it does                                          | Key knobs              |
|----------|-------------------------------------------------------|------------------------|
| Audio    | How the music moves — speed, responsiveness          | attack, release, tilt  |
| Color    | What you see — glow, overdrive, ring blending        | theme, overdrive, sustain, blend, ring_blend |
| Control  | Shape the signal — gate, curve, limiter              | gate, knee, ceiling    |

The **preset** you choose sets all three layers at once. You can then override
any individual knob in your config. The preset is a starting point, not a locked
choice.

---

## 2. How presets work

When you set `preset = "plasma"`, nova applies plasma's profile at the start of
every frame. But here's the key: **any knob you explicitly set in your TOML
config survives the overlay.** The preset only fills in what you didn't set.

```toml
[plugins.nova]
preset = "plasma"
attack = 0.95   # this overrides plasma's attack (0.65)
                 # everything else still comes from plasma
```

This means you can start from a preset you like, then tweak one knob at a time.
Every preset below includes a "try tweaking" section — those are the knobs that
most define that preset's personality.

---

## 3. Preset case studies

### reference — the balanced baseline

The standard everything is measured against. Not the most exciting, but the most
honest — it shows you what nova actually does with no stylistic spin.

```
attack = 0.55   release = 0.18
overdrive = 0.92   sustain = 0.82   blend = true
bloom_attack = 0.6   bloom_release = 0.25
gate = 0.0   knee = 1.0   tilt = 0.0
ring_blend = true
```

**What it's going for:** Neutral. Decay tails are medium-length — a kick drum
lights the wall and fades in about a second. Overdrive fires at 0.92, which is
high enough that only genuine peaks trigger the flare. Bloom has its own
moderate envelope. The compressor lane is wide open (gate=0, knee=1.0 linear).

**Try tweaking:** Lower `sustain` to 0.7 for faster flare decay — the wall
calms down quicker after big hits. Raise `overdrive` to 0.95 to make flares
rarer but more dramatic when they happen.

---

### transient — snappy and percussive

Built for music with sharp attacks — rock, metal, drum-heavy electronic. The
wall snaps to attention on every hit and stays lit.

```
attack = 1.0   release = 0.25
overdrive = 0.96   sustain = 0.9   blend = true
bloom_attack = 1.0   bloom_release = 0.95
gate = 0.2   knee = 1.0   tilt = 0.0
ring_blend = true
```

**What it's going for:** Instant response. attack=1.0 means zero smoothing lag —
the wall jumps on the first tick of any new sound. Bloom is also max attack,
so dots thicken instantly. sustain=0.9 means flares hold on for a long time.
gate=0.2 raises the noise floor, so quiet passages go dark and only real hits
register. The combination of max attack + gate means the wall pulses hard on
beats and goes quiet between them.

**Why bloom_release = 0.95:** Normally bloom release is short — dots melt away
fast. Here it's nearly maxed. Combined with max bloom attack, dots snap to full
density and then barely fade. The wall stays "charged" between hits.

**Try tweaking:** Lower `gate` to 0.1 if the wall feels too dark between hits.
Lower `sustain` to 0.7 if the flare overstays. Try `bloom = false` to see what
transient looks like as pure color with no dot texture — a different animal.

---

### nebula — diffuse and billowy

The opposite of transient. Soft, shimmering, treble-forward. Sounds like looking
at clouds through heat haze.

```
attack = 0.3   release = 0.08
overdrive = 0.97   sustain = 0.9   blend = false
bloom_attack = 0.4   bloom_release = 0.05
gate = 0.0   knee = 0.6   tilt = 0.4
ring_blend = true
```

**What it's going for:** Smear. attack=0.3 means the wall takes several frames
to reach full brightness — sounds blur into each other. release=0.08 is fast
decay, so the blur is attack-side only. tilt=0.4 boosts treble, making outer
rings more active than inner — the opposite of bass-heavy presets. knee=0.6
(soft knee) makes low-level signal brighter, so quiet passages glow evenly.

**Why blend = false:** Normally blend lets overdrive color spill into adjacent
rings. Nebula kills it. Flares stay confined to their own bands. Combined with
tilt pushing energy outward, this creates distinct ring separation at the edges.

**Why bloom_release = 0.05:** Dots melt almost instantly. The glyph wall barely
thickens — it's a pure color show with brief texture flashes on peaks.

**Try tweaking:** Drop `tilt` to 0.0 to hear what the preset sounds like
without the treble bias — the bass rings will come back. Raise `attack` to
0.5 to reduce the smear. Try `blend = true` to let flares bleed — it softens
the hard ring boundaries.

---

### plasma — the set-and-forget all-rounder

Energetic, sustained, works with everything. The preset to pick when you don't
want to think about presets.

```
attack = 0.65   release = 0.1
overdrive = 0.90   sustain = 0.88   blend = true
bloom_attack = 0.45   bloom_release = 0.23
gate = 0.03   knee = 0.9   tilt = 0.2
ring_blend = true
```

**What it's going for:** Lively but not extreme. attack=0.65 is a touch faster
than reference — the wall feels "alive" without being twitchy. gate=0.03 is a
tiny noise floor bump — nearly imperceptible, but it cleans up the faintest
flicker on silence. tilt=0.2 gives treble a slight edge for sparkle.

**Why these values work together:** Plasma is the midpoint of almost every
dimension. It's faster than reference, slower than transient. More bloom than
nebula, less than afterglow. Every knob is nudged slightly from neutral toward
"energetic" — no single knob defines it, the sum does.

**Try tweaking:** Raise `gate` to 0.08 for a cleaner noise floor on quiet
passages. Drop `overdrive` to 0.85 for more frequent but gentler flares.
Try `ring_blend = false` to see the hard-ring version — surprisingly different
feel from the same dynamics.

---

### afterglow — slow phosphor persistence

The CRT burn-in preset. Slow to wake, slow to fade, treble-biased for a
ghostly glow. Named for the green phosphor afterimage on old monitors.

```
attack = 0.3   release = 0.05
overdrive = 0.98   sustain = 0.9   blend = false
bloom_attack = 0.05   bloom_release = 0.9
gate = 0.0   knee = 2.6   tilt = 0.5
ring_blend = true
```

**What it's going for:** Persistence. The key numbers are bloom_attack=0.05 and
bloom_release=0.9. Dots take forever to wake up and even longer to fade. A big
hit lights the wall, the hit passes, and the dots linger — sometimes across
multiple beats. It's the visual equivalent of looking at a bright light and
still seeing it when you close your eyes.

**Why knee = 2.6:** This is the hardest knee of any preset. The response curve
is strongly concave — low levels are dark, high levels hit hard. Combined with
tilt=0.5 pushing energy to the edges, the outer rings glow persistently while
the center stays dark until genuine bass events.

**Why blend = false:** Like nebula, afterglow keeps flares in their lanes. But
for a different reason — with bloom holding dots for so long, bleed would
smear the ring boundaries into mud.

**Try tweaking:** Lower `bloom_release` to 0.5 for faster dot fade — still
persistent, but less extreme. Drop `knee` to 1.5 if the contrast feels too
stark. Try `bloom = false` — the color-only version is a completely different
vibe, more "aurora borealis" than "CRT burn."

---

### analog — hard-banded old-school EQ

The hardware EQ look. Distinct ring bands, fast attack, slow release. Like
watching a 10-band graphic equalizer rendered as concentric circles.

```
attack = 0.85   release = 1.0
overdrive = 0.95   sustain = 0.95   blend = false
bloom_attack = 1.0   bloom_release = 0.85
tilt = 0.3
ring_blend = true
```

**What it's going for:** Discrete band response. attack=0.85 and release=1.0
mean bands snap up fast and hold — a snare hit lights its ring and that ring
stays lit for the full decay window. bloom attack is instant, bloom release is
slow. The wall pulses in distinct rings rather than a smooth gradient.

**Note:** analog doesn't set `gate`, `knee`, or `ceiling` — it inherits those
from your config (or reference defaults: gate=0, knee=1.0, ceiling=1.0).

**Why release = 1.0:** This is the maximum — bands never decay on their own,
they only drop when the music drops. Every hit leaves a visible "hold" on its
ring. In practice the band smoothing means they still move, but each ring has
a pronounced sustained presence.

**Try tweaking:** Set `ring_blend = false` for the hardest possible ring
boundaries — pure bands with no gradient. Lower `release` to 0.3 for more
movement between hits. Try `blend = true` to let flares bleed — the hard
bands soften at the edges.

---

## 4. The compressor lane — gate, knee, ceiling

These three knobs form a mastering-style compressor lane. They apply in order:
gate → knee → ceiling. Understanding them as a unit is more useful than
understanding each in isolation.

```
raw signal
    │
    ▼
  GATE      — clamp everything below threshold to 0
    │
    ▼
  KNEE      — reshape the response curve (^knee)
    │
    ▼
  CEILING   — hard-cap everything above threshold
    │
    ▼
  final level → color + bloom
```

**Gate (0–0.5):** A noise gate. Anything below this level is forced to zero.
Useful for cleaning up the faint outer-ring glow on quiet passages. Start at
0.03–0.08 for subtle cleanup; 0.1–0.2 for aggressive silence between hits.
transient uses 0.2 for exactly this reason — the wall goes properly dark
between beats.

**Knee (0.1–3.0):** Shapes the level→brightness curve. 1.0 is linear — a
band at 0.5 maps to 50% brightness. Below 1.0 is "soft knee" — low levels
are brighter, the curve is flatter and more even (nebula uses 0.6). Above 1.0
is "hard knee" — low levels are darker, high levels hit harder, more contrast
(afterglow uses 2.6).

**Ceiling (0.01–1.0):** A brick-wall limiter. Any level above ceiling is
clamped flat. 1.0 = off. Lower values create a narrow shimmer band — try
0.2–0.6 with gate=0.03 to constrain color to a thin slice while bloom still
animates.

**Putting them together:** `gate = 0.08, knee = 2.0, ceiling = 0.5` creates a
narrow, high-contrast window — bands below 8% are silent, bands above 50% are
clamped flat, and the remaining 8–50% range is aggressively curved for maximum
contrast. The wall barely flickers until a real hit, then slams to full.

---

## 5. Common recipes

**"I want more movement"**
→ Lower `attack` (0.3–0.4) so bands lag behind the music, creating visible
sweep. Raise `release` (0.3–0.5) so they linger. The wall "breathes."

**"I want less color, more texture"**
→ Lower `ceiling` to 0.3–0.5. Set `knee = 0.5`. Colors stay muted and narrow.
Bloom (which reads from the same signal but has its own envelope) still
animates fully — the wall pulses in density rather than color.

**"I want a retro CRT look"**
→ `preset = "afterglow"` with `ring_blend = false`. Try `theme = "crt"` for
green phosphor. The slow bloom release + hard ring boundaries + green glow is
as close to an old monitor as nova gets.

**"I want the wall to barely move"**
→ `attack = 0.1, release = 0.02`. `gate = 0.03, ceiling = 0.2, knee = 0.5`.
The wall shimmers faintly. Almost ambient. Works well as a background
visualizer for coding or reading.

**"I want to see every kick drum"**
→ Start from `preset = "transient"`. Set `gate = 0.15`. The wall is dark until
a kick hits, then the bass rings flare hard. Max attack means no lag — the hit
and the flash are simultaneous.

**"Cycle everything and watch"**
→ `cycle_presets = true, cycle_themes = true, cycle_seconds = 15`. Every 15
seconds nova switches to a new preset and theme. A zero-effort way to preview
all the feels and find what you like.

---

## 6. The bloom layer — what the dots are doing

Bloom is nova's signature: braille dots that thicken toward the center of the
screen as rings heat up. It has its own attack/release envelope (separate from
the color envelope), so dots can move at a different speed than color.

- **bloom_attack:** How fast dots thicken when a ring heats. Low = slow creep
  (afterglow's 0.05). High = instant snap (transient's 1.0).
- **bloom_release:** How fast dots melt back. Low = quick dissolve (nebula's
  0.05). High = persistent burn (afterglow's 0.9).

The interplay of color envelope and bloom envelope is where nova's personality
lives. afterglow is the clearest example: color fades fast (release=0.05) but
dots hold for nearly a second (bloom_release=0.9). You see the color flash pass,
and the dot pattern lingers like a ghost.

Set `bloom = false` to turn off dot mutation entirely — the glyphs stay fixed
and only color changes. This isn't "worse" — it's a different visual.
afterglow + bloom=false is a smooth color field. transient + bloom=false is
pure ring pulses with no texture.

---

## 7. Reference — every config key

The complete list. For the audio signal chain and implementation details, see
[docs/DESIGN.md](docs/DESIGN.md).

### Look
| Key | Values | Default | What it does |
|-----|--------|---------|--------------|
| `theme` | aurora, sol, sirius, rigel, antares, crt | aurora | Color theme |
| `ring_shape` | circle | circle | Ring geometry |
| `ring_blend` | true/false | true | Smooth gradient between rings |
| `fit` | fill, contain | fill | How art fits the pane |
| `start` | black, stipple | black | Resting glyph density |
| `art_path` | file path | — | External art file (optional) |

### Feel
| Key | Values | Default | What it does |
|-----|--------|---------|--------------|
| `preset` | reference, transient, nebula, plasma, afterglow, analog | reference | One-knob feel |
| `cycle_presets` | true/false | false | Auto-rotate presets |
| `cycle_themes` | true/false | false | Auto-rotate themes |
| `cycle_seconds` | 2+ | 20 | Seconds per cycle step |

### Dynamics (0–1 unless noted)
| Key | Range | Default | What it does |
|-----|-------|---------|--------------|
| `attack` | 0–1 | 0.55 | Envelope rise speed |
| `release` | 0–1 | 0.18 | Envelope decay speed |
| `overdrive` | 0–1 | 0.78 | Flare trigger threshold |
| `sustain` | 0–0.97 | 0.82 | Flare decay per frame |
| `blend` | true/false | true | Flare spills into adjacent rings |
| `tilt` | 0–1 | 0.0 | Per-band treble boost |

### Bloom
| Key | Range | Default | What it does |
|-----|-------|---------|--------------|
| `bloom` | true/false | true | Braille dot thickening |
| `bloom_attack` | 0–1 | 0.6 | Dot thickening speed |
| `bloom_release` | 0–1 | 0.15 | Dot melting speed |

### Compressor lane
| Key | Range | Default | What it does |
|-----|-------|---------|--------------|
| `gate` | 0–0.5 | 0.0 | Noise gate threshold |
| `knee` | 0.1–3.0 | 1.0 | Response curve (1.0 = linear) |
| `ceiling` | 0.01–1.0 | 1.0 | Limiter ceiling |

### Performance
| Key | Range | Default | What it does |
|-----|-------|---------|--------------|
| `render_rate` | 0.25–1.0 | 1.0 | Fraction of frames rendered |
| `max_cols` | 0+ | 0 | Canvas width cap (0 = unlimited) |
| `max_rows` | 0+ | 0 | Canvas height cap (0 = unlimited) |
| `cell_aspect` | 0.2–2.0 | 0.5 | Terminal cell aspect ratio |

### Advanced
| Key | Values | Default | What it does |
|-----|--------|---------|--------------|
| `color_mode` | glow, mono, passthrough | glow | Color rendering mode |
| `mono_color` | 0–255 | 11 | ANSI color for mono mode |
| `debug` | true/false | false | Show preset/theme footer |

---

*Last reviewed: 2026-06-08.*
