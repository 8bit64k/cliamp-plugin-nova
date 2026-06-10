# Nova

![Nova Gif](assets/nova-demo-gif-3.gif)

A music visualizer for [cliamp](https://cliamp.stream) that turns your terminal into a living wall of light.

So many of the cliamp visualizers are clever and artful, and that inspired me to build Nova. And because a lot of the music I listen to leans heavy to the bass end of the spectrum, I wanted a visualization that presented in the center of the screen rather than being slammed on the left side where bass EQ bands normally are. 

Therefore, Nova maps the 10-band EQ into concentric rings radiating from the center of your screen. Bass pulses from the middle.Treble shimmers at the edges. As the music heats up, braille dots thicken (are added) toward center on peaks and melt away slowly after— like phosphor burning into a CRT.

No art files, no setup. Install, press `V` until you reach Nova, and play something. Here is a [youtube video](https://youtu.be/ITFSml5cv3Q) of it in action.

---

## Install

```bash
cliamp plugins install 8bit64k/cliamp-plugin-nova
```

Restart cliamp, press `V` to cycle visualizers until Nova appears.

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

Tip: Set `cycle_themes = true` to rotate through sol → sirius → rigel → antares → aurora.

---

## Presets

Six one-knob feels (pre-configured set of "dynamics"). Each bundles `aurora` theme + `circle` shape + dynamics into a named preset.
User-set TOML keys override the preset defaults.

| Preset     | Feel                                    |
|------------|-----------------------------------------|
| reference  | Balanced baseline                       |
| transient  | Snappy and percussive — kick-driven     |
| nebula     | Diffuse and billowy — treble-biased     |
| plasma     | Energetic and sustained — all-rounder   |
| afterglow  | Slow phosphor persistence, slow fade    |
| analog     | Perfect :-P — old-school EQ look        |

---

## Quick config

Everything is optional. With no config, Nova renders aurora + circle with smooth ring blending and bloom. Add a `[plugins.nova]` block to
`~/.config/cliamp/config.toml`:

```toml
[plugins.nova]

# --- look ---
# sol | sirius | rigel | antares | aurora
theme = "aurora"       
ring_blend = true

# set to true rotate through all 5 themes automatically
cycle_themes = false  

# --- feel ---
# reference | transient | nebula | plasma |  afterglow | analog
preset = "analog"   

# rotate through all 6 presets automatically (don't set `preset`)
cycle_presets = false  
# seconds per theme/preset when cycling
cycle_seconds = 20     

# --- bloom ---
# braille dots thicken toward center on peaks
bloom = true           

# --- dynamics ---
attack = 0.55
release = 0.18
overdrive = 0.78
sustain = 0.82
# overdrive spills into adjacent rings
blend = true  
# noise gate (0–0.50)         
gate = 0.00   
# limiter (0.01–1.00)         
ceiling = 1.00 
# response curve (0.10–3.00, 1.00 = linear)        
knee = 1.00   
# per-band treble boost         
tilt = 0.00            

# --- performance ---
# 0.25–1.00, fraction of frames to render (if it's hogging too much cpu)
render_rate = 1.00     
```

The full config surface with every knob, the audio signal chain, and
implementation details: [docs/DESIGN.md](docs/DESIGN.md).

To learn how to tune Nova to your taste — presets as case studies, the compressor lane explained, and common recipes: [docs/USAGE.md](docs/USAGE.md).

---

## Tips

- Press **Shift+V** in cliamp for fullscreen — Nova shines when it fills the
  terminal.
- `cycle_presets = true` rotates through all six presets automatically.
- `cycle_themes = true` rotates through all five themes automatically.
- For subtle density with barely any color: `gate = 0.03, ceiling = 0.20`.
- For a CRT-era hard-edged look: `preset = "afterglow"` with
  `ring_blend = false`.
- Best opinionated tip: analog + rigel/antares for the win
---

## Troubleshooting

If Nova shows a blank pane:

```bash
tail -n 40 ~/.config/cliamp/plugins.log
```

---

License: MIT © 8bit64k
