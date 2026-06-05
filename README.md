# nova

A music visualizer for [cliamp](https://cliamp.stream) that turns your
terminal into a living wall of light.

**What makes nova different:** instead of bouncing bars or scrolling waveforms,
nova maps the 10-band EQ into **concentric rings** radiating from the center of
your screen. Bass pulses from the middle. Treble shimmers at the edges. As the
music heats up, the rings don't just change color — the dots themselves
**thicken**, gaining mass on the beat and melting away slowly after, like
phosphor burning into a CRT.

It needs no art files, no setup, no config. Install it, press `v` until you
reach nova, and play something.

---

## Install

```bash
cliamp plugins install 8bit64k/cliamp-plugin-nova
```

That's it. Restart cliamp, press `v` to cycle visualizers until nova appears.

To update later: `cliamp plugins update nova`

---

## What you'll see

- **Concentric rings** — 10 bands of your EQ laid out in rings, bass at the
  center, treble at the edge. The wall breathes from the middle outward.
- **Three ring shapes** — circle, diamond, and vertical wings.
- **Six color themes** — amber, phosphor green, white-hot, black-hot, aurora, predator
- **The wall thickens on the beat** — dots fill in toward the center as the
  music hits, then fade slowly. Kick drums leave a visible trail.
- **Overdrive flare** — when the bass punches hard, the rings flash hot and the
  heat spills outward. You'll see it on a good kick drum.
- **Eight one-knob presets** — `punch` is snappy and percussive, `ethereal` is
  dreamy and slow, `retro` feels like a CRT, `ghost` is thin and wispy. Pick a
  feel and go. Set `cycle_presets = true` to rotate through them hands-free.

---

## Configure

Everything is optional. With no config at all, nova renders a clean wall in
amber with smooth ring blending. Add a `[plugins.nova]` block to `~/.config/cliamp/config.toml` to
tune it:

```toml
[plugins.nova]
# --- look ---
theme = "amber"
#   amber | crt | whitehot | blackhot | aurora | predator
ring_shape = "circle"
#   circle | diamond | wings | cycle
cycle_seconds = 20
#   seconds per shape when ring_shape = "cycle"
ring_blend = true
#   true = smooth gradient across rings | false = hard banded rings
fit = "fill"
#   "contain" = letterboxed | "fill" = stretch edge to edge

# --- feel ---
preset = "default"
#   default | punch | ethereal | retro | plasma | ghost | whiteout | tacutacu
#   sets theme + shape + dynamics in one go; you can still override any knob below
cycle_presets = false
#   rotate through all presets automatically

# --- bloom (dot thickness) ---
bloom = true
#   false = color only, dots stay fixed

# --- dynamics (all 0–1 unless noted) ---
attack = 0.55
release = 0.18
overdrive = 0.78
#   how hard the bass has to hit before the wall flares

# --- performance ---
max_cols = 0
max_rows = 0
#   cap the drawn area on huge terminals (0 = no cap)

# --- advanced (see DESIGN.md) ---
# gate, ceiling, knee, tilt, sustain, blend, bloom_attack,
# bloom_release, cell_aspect, render_rate, color_mode, mono_color,
# cycle_seconds, start, art_path
```

The full config surface with every knob and its range is documented in
[docs/DESIGN.md](docs/DESIGN.md).

---

## Tips

- Press **Shift+V** in cliamp for fullscreen — nova really shines when it fills
  the terminal.
- Set `ring_shape = "cycle"` to preview every shape hands-free.
- Set `cycle_presets = true` to try all eight feels without touching config.
- If the outer rings feel dead on treble-heavy music, try `tilt = 0.5`.
- For a subtle shimmer with barely any color, try `gate = 0.03, ceiling = 0.20`.

---

## Troubleshooting

If nova shows a blank pane, check the log:

```bash
tail -n 40 ~/.config/cliamp/plugins.log
```

---

License: MIT © 8bit64k