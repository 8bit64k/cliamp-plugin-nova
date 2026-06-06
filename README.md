# nova

A music visualizer for [cliamp](https://cliamp.stream) that turns your terminal
into a living wall of light.

**What makes nova different:** instead of bouncing bars or scrolling waveforms,
nova maps the 10-band EQ into **concentric rings** radiating from the center of
your screen. Bass pulses from the middle. Treble shimmers at the edges. As the
music heats up, the rings don't just change color — the braille dots themselves
**thicken toward center**, gaining mass on the beat and melting away slowly
after, like phosphor burning into a CRT.

It needs no art files, no setup, no config. Install it, press `v` until you
reach nova, and play something.

---

## Install

```bash
cliamp plugins install 8bit64k/cliamp-plugin-nova
```

Restart cliamp, press `v` to cycle visualizers until nova appears.

To update later: `cliamp plugins update nova`

---

## What you'll see

- **Concentric rings** — 10 EQ bands laid out in rings, bass at center, treble
  at the edge. The wall breathes from the middle outward.
- **Three ring shapes** — circle, diamond, and vertical wings. Set
  `ring_shape = "cycle"` to rotate through all three hands-free.
- **Seven color themes** — amber (tubeamp family), CRT green phosphor,
  white-hot, black-hot, aurora (the default teal-cyan-green), predator thermal
  vision, and terminal (cliamp's native green→yellow→red spectrum).
- **The wall thickens on the beat** — braille dots fill in toward center as the
  music hits, then fade slowly. Kick drums leave a visible trail.
- **Overdrive flare** — when the bass punches hard, the rings flash hot and the
  heat spills outward into adjacent rings. You'll see it on a good kick drum.
- **Six one-knob presets** — `punch` is snappy and percussive, `ethereal` is
  dreamy and slow, `ghost` is thin and wispy, `plasma` is volatile and
  electric, `classic` has big bloom and symmetric rings. Pick a feel and go.
  Set `cycle_presets = true` to rotate through them hands-free.
- **Compressor lane** — gate + ceiling knobs form a narrow "shimmer band" for
  subtle density-only animation with barely any color shift.

---

## Quick config

Everything is optional. With no config at all, nova renders a clean wall in
aurora with smooth ring blending and dot bloom. Add a `[plugins.nova]` block to
`~/.config/cliamp/config.toml` to tune it:

```toml
[plugins.nova]

# --- look ---
theme = "aurora"
#   amber | crt | whitehot | blackhot | aurora | predator | terminal
ring_shape = "circle"
#   circle | diamond | wings | cycle
ring_blend = true
#   true = smooth gradient across rings | false = hard banded rings

# --- feel ---
preset = "default"
#   default | punch | ethereal | plasma | ghost | classic
cycle_presets = false
#   rotate through all presets automatically

# --- bloom (glyph density) ---
bloom = true
#   false = color only, dots stay fixed

# --- dynamics ---
attack = 0.55
release = 0.18
overdrive = 0.78
sustain = 0.82
#   0–0.97, fraction of heat retained per frame
blend = true
#   overdrive color + bloom spill into adjacent rings
gate = 0.0
#   0–0.5, noise gate — silence below this level
ceiling = 1.0
#   0.01–1.0, limiter — clamp above this (1.0 = off)

# --- performance ---
render_rate = 1.0
#   0.25–1.0, fraction of frames rendered (lower = less CPU)
```

The full config surface with every knob, range, and default is documented in
[docs/DESIGN.md](docs/DESIGN.md).

---

## Color Themes

| Theme | Character |
|-------|-----------|
| **aurora** (default) | Teal through cyan to bright green |
| amber | Dark amber to bright yellow, red overdrive |
| crt | Green phosphor, yellow-green overdrive |
| whitehot | Black to pure white, high contrast |
| blackhot | White to black, inverted thermal |
| predator | Thermal vision: indigo→cyan→yellow→red |
| terminal | cliamp's native green→yellow→red spectrum |

Each theme has an 11-stop glow ramp and 4-stop overdrive ramp. See
[docs/DESIGN.md](docs/DESIGN.md) for the full ANSI 256 palette.

---

## Visual Dynamics presets

| Preset | Feel |
|--------|------|
| **default** | Balanced baseline — smooth, responsive |
| **punch** | Snappy attack, percussive, hard gate |
| **ethereal** | Dreamy, slow glow, soft knee, treble-tilted |
| **plasma** | Volatile, electric, tight bloom |
| **ghost** | Thin, wispy, slow bloom shed, hard knee |
| **classic** | Big bloom, symmetric rings, long sustain |

All presets use aurora + circle. Individual TOML keys override preset values.
Full knob values per preset in [docs/DESIGN.md](docs/DESIGN.md#8-visual-dynamics-presets).

---

## Tips

- Press **Shift+V** in cliamp for fullscreen — nova really shines when it fills
  the terminal.
- Set `ring_shape = "cycle"` to preview every shape without touching config.
- Set `cycle_presets = true` to try all six feels hands-free.
- If the outer rings feel dead on treble-heavy music, try `tilt = 0.3`.
- For subtle density animation with barely any color, try
  `gate = 0.03, ceiling = 0.20` — the compressor lane.
- For a CRT-era hard-edged look: `preset = "ghost"` with `ring_blend = false`.
- For screenshots: play pink noise or a multisine tone that hits all bands.

---

## Troubleshooting

If nova shows a blank pane, check the log:

```bash
tail -n 40 ~/.config/cliamp/plugins.log
```

---

## More

The full design document — implementation walkthrough, audio signal chain,
performance controls, testing, and constraints — lives at
[docs/DESIGN.md](docs/DESIGN.md).

---

License: MIT © 8bit64k