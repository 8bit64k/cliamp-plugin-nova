# cliamp-plugin-nova

> ⚠️ **IN DEVELOPMENT — expect breakage.** This is a work-in-progress cliamp
> visualizer plugin. The name `nova` is provisional, the render is unstable,
> and the config schema may change without notice. Not released. No tags, no
> versioning, no support. Here so 8bit64k can test against live cliamp from a
> remote machine.

A cliamp visualizer that renders a **braille wall** reacting to the 10-band EQ
feed. The wall lights AND thickens with the music: each concentric ring (bass at
the center, treble at the edge) recolors by its band level on an amber-to-hot
ramp (shared with the sibling `tubeamp` plugin), and braille glyphs gain dots
**toward the center** as they heat, so the wall gains matter on the peaks — not
just brightness.

The wall is **generated procedurally** — no art file required. You can optionally
point it at your own ASCII/braille art via `art_path`, but the default needs
nothing but the plugin.

---

## Install (manual — this repo is private)

cliamp's plugin manager (`cliamp plugins install`) only works against **public**
repos, so during development you install by hand: clone the repo and copy the
single Lua file into cliamp's plugins directory.

```bash
# 1. Clone (uses your 8bit64k GitHub credentials)
git clone https://github.com/8bit64k/cliamp-plugin-nova.git
cd cliamp-plugin-nova

# 2. Copy the plugin into cliamp's plugins dir
mkdir -p ~/.config/cliamp/plugins
cp nova.lua ~/.config/cliamp/plugins/nova.lua
```

That's it — the wall is generated procedurally, so there is **no art file to
copy or configure** for the default experience. (If you want to drive a custom
art file instead, see `art_path` under Configure; the file stays in your clone
and the plugin reads it in place — nothing gets copied into cliamp's dirs.)

To **update** after I push changes:

```bash
cd cliamp-plugin-nova
git pull
cp nova.lua ~/.config/cliamp/plugins/nova.lua   # re-copy; cliamp doesn't hot-reload
```

Then restart cliamp and press `v` to cycle visualizers until you reach **nova**.

> cliamp does **not** hot-reload plugins or config — re-copy the file and restart
> cliamp after every change.

---

## Configure

A `[plugins.nova]` block is **optional** — with no config the plugin renders the
default procedural wall (`start = "black"`, `fit = "contain"`). Add a block to
tune it:

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
placeholder message instead of crashing. With no `art_path`, it always has the
generated wall to fall back on.

### Bigger pane / filling the screen

The plugin only fills the pane cliamp hands it. cliamp gives visualizers **5 rows**
in the normal layout — press **Shift+V** for the full-screen visualizer, which
grows the pane to roughly `(terminal_height - 10) * 4/5` rows by your full
terminal width. That's the path to a big canvas; it's a cliamp keybinding, not a
plugin setting.

By default (`fit = "contain"`) the art is scaled to fit while preserving its
aspect ratio, so a wide source gets letterboxed (empty rows top/bottom) in a
tall pane. For the **braille wall** (the procedural default, or any texture with
no shape to preserve) set `fit = "fill"` to stretch each axis independently and
fill the entire pane edge to edge. Pair `fit = "fill"` with Shift+V for a
full-screen reactive wall.

### Reviewing shapes: `ring_shape = "cycle"`

Set `ring_shape = "cycle"` to auto-rotate through square → diamond → circle → squircle → wings → layers → compass every
`cycle_seconds` (default 20). The active shape is labelled `[square]` / `[diamond]`
/ `[circle]` in the bottom-right corner so you can tell them apart as it rotates.
This needs **no restart between shapes** — cliamp doesn't hot-reload config, but
the cycle runs off the wall clock while the plugin is live, so it keeps rotating
within a single session. Use it to pick the shape you like, then set
`ring_shape` to that fixed value (the label only shows in cycle mode).

> **Note:** Keep inline `#` comments on their own line in the TOML config.
> cliamp's parser may leak comment text into the config value, causing preset
> lookups or numeric parsing to fail. The plugin strips these defensively, but
> clean config is cleaner.

---

## Troubleshooting

cliamp swallows plugin render errors silently — they do **not** appear in the UI.
If `nova` shows a blank pane or stale frame, check the log:

```bash
tail -n 40 ~/.config/cliamp/plugins.log
```

Look for `[nova] error: ...` lines.

---

## Status

| | |
|---|---|
| State | In development — not released |
| Repo | `8bit64k/cliamp-plugin-nova` (private) |
| Entry file | `nova.lua` (repo root) |
| Wall | procedural (no art file needed); `start = "black"` (default) \| `"stipple"` |
| Sibling plugin | [`cliamp-plugin-tubeamp`](https://github.com/8bit64k/cliamp-plugin-tubeamp) (shipped, v1.2.0) |

License: MIT © 8bit64k (added at release time).
