# nova

<p align="center">
  <img src="assets/nova-demo.gif" alt="nova visualizer demo" width="400">
</p>

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

---

## Color Themes

Six themes — five named for stars across the temperature spectrum, plus aurora.
Each is a 15-stop RGB glow ramp with a 4-stop overdrive ramp. Truecolor-native,
ANSI 256 fallback.

| Theme | Star | Color |
|-------|------|-------|
| sol | Sol (G2, 5,800K) | Amber → gold → yellow |
| sirius | Sirius (A1, 9,900K) | Black → gray → pure white |
| rigel | Rigel (B8, 12,000K) | Navy → electric blue → blue-white |
| antares | Antares (M1, 3,500K) | Crimson → neon red → pink → white |
| aurora | — (default) | Teal → cyan → green |
| crt | — (easter egg) | Green phosphor |

Set `cycle_themes = true` to rotate through sol → sirius → rigel → antares → aurora.
CRT is available by name but excluded from the cycle.

---

## Ring Shape

Nova uses a single radial distance metric: **circle** (Euclidean). Bass lives at
the center, treble at the edges.

<p align="center">
  <img src="assets/aurora-theme-colors.png" width="220" alt="circle">
</p>

---

## Quick config

Everything is optional. With no config at all, nova renders in aurora + circle
with smooth ring blending and dot bloom. Add a `[plugins.nova]` block to
`~/.config/cliamp/config.toml`:

```toml
[plugins.nova]

# --- look ---
theme = "aurora"
#   sol | sirius | rigel | antares | aurora | crt
ring_shape = "circle"
ring_blend = true

# --- feel ---
preset = "reference"
#   reference | transient | nebula | plasma | afterglow | analog
cycle_presets = false
cycle_themes = false

# --- bloom (glyph density) ---
bloom = true

# --- dynamics ---
attack = 0.55
release = 0.18
overdrive = 0.78
sustain = 0.82
blend = true
gate = 0.0
ceiling = 1.0

# --- performance ---
render_rate = 1.0
```

The full config surface with every knob, the Visual Dynamics preset table, and
the audio signal chain is documented in [docs/DESIGN.md](docs/DESIGN.md).

All theme + shape screenshots: [assets/](assets/)

---

## Tips

- Press **Shift+V** in cliamp for fullscreen — nova shines when it fills the terminal.
- Set `cycle_presets = true` to rotate through all six presets.
- Set `cycle_themes = true` to rotate through all five themes.
- For subtle density animation with barely any color, try `gate = 0.03, ceiling = 0.20`.
- For a CRT-era hard-edged look: `preset = "afterglow"` with `ring_blend = false`.

---

## Troubleshooting

If nova shows a blank pane:

```bash
tail -n 40 ~/.config/cliamp/plugins.log
```

---

License: MIT © 8bit64k