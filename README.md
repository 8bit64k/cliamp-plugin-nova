# nova

A music visualizer for [cliamp](https://cliamp.stream) that turns your terminal
into a living wall of light.

nova maps the 10-band EQ into concentric rings radiating from the center of your
screen. Bass pulses from the middle. Treble shimmers at the edges. As the music
heats up, braille dots thicken toward center on peaks and melt away slowly after
— like phosphor burning into a CRT.

No art files, no setup. Install, press `V` until you reach nova, and play
something.

---

## Install

```bash
cliamp plugins install 8bit64k/cliamp-plugin-nova
```

Restart cliamp, press `V` to cycle visualizers until nova appears.

---

## Themes

Six themes, each a 15-stop RGB glow ramp with truecolor-native ANSI:

| Theme   | Color                              |
|---------|------------------------------------|
| aurora  | Teal → cyan → green *(default)*    |
| sol     | Amber → gold → yellow              |
| sirius  | Black → gray → pure white          |
| rigel   | Navy → electric blue → blue-white  |
| antares | Crimson → neon red → pink → white  |
| crt     | Green phosphor *(easter egg)*      |

Set `cycle_themes = true` to rotate through sol → sirius → rigel → antares →
aurora. CRT is available by name but excluded from the cycle.

---

## Presets

Six one-knob feels. Each bundles theme + shape + dynamics into a named preset.
User-set TOML keys override the preset defaults.

| Preset     | Feel                                    |
|------------|-----------------------------------------|
| reference  | Balanced baseline                       |
| transient  | Snappy and percussive — kick-driven     |
| nebula     | Diffuse and billowy — treble-biased     |
| plasma     | Energetic and sustained — all-rounder   |
| afterglow  | Slow phosphor persistence, slow fade    |
| analog     | Hard-banded rings — old-school EQ look  |

---

## Quick config

Everything is optional. With no config, nova renders aurora + circle with smooth
ring blending and bloom. Add a `[plugins.nova]` block to
`~/.config/cliamp/config.toml`:

```toml
[plugins.nova]

# --- look ---
theme = "aurora"       # sol | sirius | rigel | antares | aurora | crt
ring_shape = "circle"
ring_blend = true
cycle_themes = false   # rotate through all 5 themes automatically

# --- feel ---
preset = "reference"   # reference | transient | nebula | plasma | afterglow | analog
cycle_presets = false  # rotate through all 6 presets automatically
cycle_seconds = 20     # seconds per theme/preset when cycling

# --- bloom ---
bloom = true           # braille dots thicken toward center on peaks

# --- dynamics ---
attack = 0.55
release = 0.18
overdrive = 0.78
sustain = 0.82
blend = true           # overdrive spills into adjacent rings
gate = 0.0             # noise gate (0–0.5)
ceiling = 1.0          # limiter (0.01–1.0)
knee = 1.0             # response curve (0.1–3.0, 1.0 = linear)
tilt = 0.0             # per-band treble boost

# --- performance ---
render_rate = 1.0      # 0.25–1.0, fraction of frames to render
```

The full config surface with every knob, the audio signal chain, and
implementation details: [docs/DESIGN.md](docs/DESIGN.md).

---

## Tips

- Press **Shift+V** in cliamp for fullscreen — nova shines when it fills the
  terminal.
- `cycle_presets = true` rotates through all six presets automatically.
- `cycle_themes = true` rotates through all five themes automatically.
- For subtle density with barely any color: `gate = 0.03, ceiling = 0.20`.
- For a CRT-era hard-edged look: `preset = "afterglow"` with
  `ring_blend = false`.

---

## Troubleshooting

If nova shows a blank pane:

```bash
tail -n 40 ~/.config/cliamp/plugins.log
```

---

License: MIT © 8bit64k
