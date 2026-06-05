# cliamp-plugin-nova

A cliamp visualizer that renders a **braille wall** reacting to the 10-band EQ
feed. The wall lights AND thickens with the music: each concentric ring (bass at
the center, treble at the edge) recolors by its band level on a themed ANSI 256
ramp, and braille glyphs gain dots **toward the center** as they heat — the wall
gains matter on peaks, not just brightness.

The wall is **generated procedurally** — no art file required. You can optionally
point it at your own ASCII/braille art via `art_path`.

Features:
- **Procedural braille wall** (no art file needed) — `start = "black"` (empty) or `"stipple"` (faint resting texture)
- **11 color themes** — amber, crt, vantablack, whitehot, blackhot, redhot, orangehot, aurora, ember, predator, flan
- **7 ring shapes** — square, diamond, circle, squircle, wings, layers, compass (+ `cycle` to auto-rotate)
- **Braille bloom** — glyphs thicken toward center as they heat (phosphor persistence)
- **8 behaviour presets** — one-knob feel (default, punch, ethereal, retro, plasma, ghost, whiteout, tacutacu)
- **Overdrive flare** — bass transients flash hot with a decay tail, spill into adjacent rings
- **Bloom bleed** — overdrive thickens adjacent rings +1/+2 (mechanical bulge)
- **Full dynamics** — gate, ceiling, knee, tilt, attack/release, sustain, blend
- **Performance controls** — `render_rate` (frame-skip) and `max_cols`/`max_rows` (canvas cap)
- **Debug footer** — shows preset + theme + bloom bleed indicator when `debug = true`

Sibling to [`cliamp-plugin-tubeamp`](https://github.com/8bit64k/cliamp-plugin-tubeamp) —
same ANSI 256 palette, same compressor-lane dynamics philosophy.

---

## Install

### cliamp plugin manager (recommended)

```bash
cliamp plugins install 8bit64k/cliamp-plugin-nova
```

To pin a version:

```bash
cliamp plugins install 8bit64k/cliamp-plugin-nova@v0.1.0
```

### Manual install

```bash
git clone https://github.com/8bit64k/cliamp-plugin-nova.git
cp cliamp-plugin-nova/nova.lua ~/.config/cliamp/plugins/nova.lua
```

To update: `git pull` + re-`cp`. cliamp does not hot-reload plugins — restart
after every change.

---

## Configure

A `[plugins.nova]` block is optional — with no config the plugin renders the
default procedural wall (`start = "black"`, `fit = "contain"`).

```toml
[plugins.nova]
# --- appearance ---
start = "black"
#   "black" (default) = empty canvas, bloom dots in from nothing
#   "stipple"        = faint resting texture that thickens
# art_path = "/abs/path/to/your_art.txt"
#   optional — drive a custom ASCII/braille file (stays in your clone)
color_mode = "glow"
#   "glow" | "mono" | "passthrough"
#   passthrough: raw glyphs, no color or bloom
ring_shape = "square"
#   square | diamond | circle | squircle | wings | layers | compass | cycle
cycle_seconds = 20
#   when ring_shape="cycle", seconds per shape (min 2)
fit = "contain"
#   "contain" = preserve aspect, letterboxed | "fill" = stretch edge-to-edge
ring_blend = true
#   true = smooth gradient across rings | false = hard stepped bands
theme = "amber"
#   amber | crt | vantablack | whitehot | blackhot | redhot | orangehot
#   aurora | ember | predator | flan

# --- bloom (glyph thickness) ---
bloom = true
bloom_attack = 0.6
bloom_release = 0.15

# --- preset (one-knob feel: bundles dynamics + theme + ring_shape) ---
preset = "default"
#   default | punch | ethereal | retro | plasma | ghost | whiteout | tacutacu
cycle_presets = false
#   auto-rotate through all presets on cycle_seconds

# --- signal chain ---
attack = 0.55
release = 0.18
overdrive = 0.78
sustain = 0.82
#   bass flare tail: fraction of heat retained per frame
#   0 = instant snap, ~0.85 = long glowing tail
blend = true
#   spill overdrive into adjacent rings
tilt = 0.0
#   per-band boost toward treble (try 0.5 if outer rings feel dead)
gate = 0.0
#   noise gate: clamp below this to 0
#   try 0.08-0.12 to silence faint ring glow on quiet passages
ceiling = 1.0
#   limiter: clamp above this (1.0 = off)
#   try 0.2-0.6 for compressed shimmer lane
knee = 1.0
#   response curve: 1.0=linear, >1=harder knee, <1=softer
cell_aspect = 0.5
#   terminal cell width/height ratio (0.5 = standard; 0.2-2.0)

# --- performance ---
mono_color = 11
#   ANSI 256 index, used when color_mode = "mono"
max_cols = 0
max_rows = 0
#   0 = unlimited. Cap the drawn grid on huge fullscreen panes.
render_rate = 1.0
#   fraction of frames rendered: 1.0 = every frame (~20 FPS),
#   0.5 = ~10 FPS, 0.25 = ~5 FPS (minimum)
```

If a configured `art_path` can't be read, the plugin renders a visible
placeholder message instead of crashing.

### Bigger pane / filling the screen

cliamp gives visualizers **5 rows** in the normal layout — press **Shift+V** for
the full-screen visualizer, which grows the pane to roughly
`(terminal_height - 10) * 4/5` rows by your full terminal width.

By default (`fit = "contain"`) the art is scaled to fit while preserving its
aspect ratio. For the **braille wall** set `fit = "fill"` to stretch edge to
edge. Pair with Shift+V for a full-screen reactive wall.

### Reviewing shapes: `ring_shape = "cycle"`

Set `ring_shape = "cycle"` to auto-rotate through all 7 shapes every
`cycle_seconds` (default 20). This needs no restart — the cycle runs off the
wall clock while the plugin is live. Use it to pick the shape you like, then
set `ring_shape` to that fixed value.

---

## Troubleshooting

cliamp swallows plugin render errors silently — they do not appear in the UI.
Check the log:

```bash
tail -n 40 ~/.config/cliamp/plugins.log
```

Look for `[nova] error:` lines.

---

## Status

| | |
|---|---|
| State | v0.1.0 — stable |
| Repo | [`8bit64k/cliamp-plugin-nova`](https://github.com/8bit64k/cliamp-plugin-nova) |
| Entry file | `nova.lua` (repo root) |
| Wall | procedural (no art file needed); `start = "black"` (default) \| `"stipple"` |
| Sibling | [`cliamp-plugin-tubeamp`](https://github.com/8bit64k/cliamp-plugin-tubeamp) (shipped, v1.2.0) |

License: MIT © 8bit64k
