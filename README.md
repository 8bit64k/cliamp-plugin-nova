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
start = "black"                                # procedural wall when no art_path: "black" = empty canvas, dots bloom in from nothing (default) | "stipple" = faint resting texture that thickens
# art_path = "/abs/path/to/your_art.txt"       # OPTIONAL — drive a custom ASCII/braille file instead of the generated wall (lives in your clone, read in place)
color_mode = "glow"                            # "glow" | "mono" | "passthrough"  (NOTE: passthrough shows raw glyphs — no color OR density thickening)
ring_shape = "square"                          # "square" | "diamond" | "circle" | "squircle" | "wings" | "layers" | "compass" | "cycle" — geometry of the concentric bands
cycle_seconds = 20                             # when ring_shape="cycle", seconds per shape before rotating (min 2)
fit = "contain"                                # "contain" = preserve aspect, letterboxed (pictures) | "fill" = stretch to fill the whole pane (textures / the wall)
ring_blend = true                              # true = smooth gradient across rings (default) | false = hard stepped band boundaries
density = true                                  # true = braille glyphs thicken toward center as they heat (default) | false = glyphs fixed, color only
density_attack = 0.6                            # how fast dots FILL toward the level (high = snappy; 1.0 = instant)
density_release = 0.15                          # how fast dots SHED when level drops (low = lingering CRT-phosphor trail; 1.0 = instant)
theme = "amber"                                # "amber" | "crt" | "vantablack" | "aurora" | "ember" | "predator" | "flan"
preset = "default"                             # behaviour preset: "default" | "punchy" | "ethereal" | "retro" | "plasma" | "ghost" | "tacutacu" — bundles dynamics + theme + ring_shape into a single feel; individual overrides still work
cycle_presets = false                           # auto-rotate through all 7 presets on cycle_seconds (like ring_shape=cycle) — hands-free preview
mono_color = 11                                # ANSI 256 index, used when color_mode = "mono"
attack = 0.55                                  # smoothing attack (shared defaults with tubeamp)
release = 0.18                                 # smoothing release
overdrive = 0.78                               # band level above which a bass ring (bands 1-2) flares hot
overdrive_decay = 0.82                          # bass flare tail: fraction of heat retained per frame (0 = instant snap, ~0.85 = long glowing fade)
overdrive_bleed = true                          # when a bass ring punches hot, bleed warmth into the ring just outside it (true | false)
tilt = 0.0                                     # per-band boost toward treble (0=off; try 0.5 if outer rings feel dead)
gate = 0.0                                     # noise gate: clamp band level below this to 0 (0=off; try 0.08-0.12 to silence faint outer-ring glow on quiet passages)
ceiling = 1.0                                  # limiter: clamp band level above this to ceiling (1.0=off; try 0.2-0.6 for a compressed shimmer lane with density-only animation)
gamma = 1.0                                    # response curve: 1.0=linear (default); >1 compresses low end; <1 lifts mids (0.1-3.0)
cell_aspect = 0.5                              # terminal cell width/height ratio for round circles (0.5=standard; 0.2-2.0)

# --- performance (all default OFF / full rate; only needed on very large panes) ---
max_cols = 0                                   # cap the DRAWN width (0 = unlimited). On a huge fit=fill pane this bounds per-frame cost; the wall becomes a centered block.
max_rows = 0                                   # cap the DRAWN height (0 = unlimited)
render_rate = 1.0                              # fraction of frames actually rendered, 0.25..1.0. 1.0 = every frame (~20 FPS); 0.5 = ~10 FPS; 0.25 = ~5 FPS. Reuses the last frame in between; keeps fit=fill edge-to-edge. Values below 0.25 are clamped.
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
