# cliamp-plugin-dance

> ⚠️ **IN DEVELOPMENT — expect breakage.** This is a work-in-progress cliamp
> visualizer plugin. The name `dance` is provisional, the render is unstable,
> and the config schema may change without notice. Not released. No tags, no
> versioning, no support. Here so 8bit64k can test against live cliamp from a
> remote machine.

A cliamp visualizer that takes a user-supplied ASCII art file and makes it
**dance** to the 10-band EQ feed — vertical columns bob with the beat and glow
with an amber-to-white-hot ramp (shared with the sibling `tubeamp` plugin).

---

## Install (manual — this repo is private)

cliamp's plugin manager (`cliamp plugins install`) only works against **public**
repos, so during development you install by hand: clone the repo and copy the
single Lua file into cliamp's plugins directory.

```bash
# 1. Clone (uses your 8bit64k GitHub credentials)
git clone https://github.com/8bit64k/cliamp-plugin-dance.git
cd cliamp-plugin-dance

# 2. Copy the plugin into cliamp's plugins dir
mkdir -p ~/.config/cliamp/plugins
cp dance.lua ~/.config/cliamp/plugins/dance.lua
```

The **art file stays in the clone** — there's nothing to copy into cliamp's
dirs. The plugin reads it directly from wherever you point `art_path` (the
sandbox allows reads from any path, 1 MB cap). Just note the absolute path to
`ruby.txt` in your clone for the config below, e.g.:

```bash
realpath ruby.txt
# -> /home/you/code/cliamp-plugin-dance/ruby.txt
```

To **update** after I push changes:

```bash
cd cliamp-plugin-dance
git pull
cp dance.lua ~/.config/cliamp/plugins/dance.lua   # re-copy; cliamp doesn't hot-reload
```

Then restart cliamp and press `v` to cycle visualizers until you reach **dance**.

> cliamp does **not** hot-reload plugins or config — re-copy the file and restart
> cliamp after every change.

---

## Configure

Add a `[plugins.dance]` block to your cliamp config:

```toml
[plugins.dance]
art_path = "/abs/path/to/cliamp-plugin-dance/ruby.txt"   # required — absolute path to the ASCII art file (lives in your clone, not cliamp's dirs)
color_mode = "glow"                            # "glow" | "mono" | "passthrough"
ring_shape = "square"                          # "square" | "diamond" | "circle" | "cycle" — geometry of the concentric bands
cycle_seconds = 20                             # when ring_shape="cycle", seconds per shape before rotating (min 2)
fit = "contain"                                # "contain" = preserve aspect, letterboxed (pictures) | "fill" = stretch to fill the whole pane (textures)
ring_blend = true                              # true = smooth gradient across rings (default) | false = hard stepped band boundaries
theme = "amber"                                # "amber" | "crt" | "vantablack" | "aurora"
mono_color = 11                                # ANSI 256 index, used when color_mode = "mono"
attack = 0.55                                  # smoothing attack (shared defaults with tubeamp)
release = 0.18                                 # smoothing release
overdrive = 0.78                               # band level above which a column flares red + bobs extra
tilt = 0.0                                     # per-band boost toward treble (0=off; try 0.5 if outer rings feel dead)
```

If `art_path` is missing or the file can't be read, the plugin renders a visible
placeholder message instead of crashing.

### Bigger pane / filling the screen

The plugin only fills the pane cliamp hands it. cliamp gives visualizers **5 rows**
in the normal layout — press **Shift+V** for the full-screen visualizer, which
grows the pane to roughly `(terminal_height - 10) * 4/5` rows by your full
terminal width. That's the path to a big canvas; it's a cliamp keybinding, not a
plugin setting.

By default (`fit = "contain"`) the art is scaled to fit while preserving its
aspect ratio, so a wide source gets letterboxed (empty rows top/bottom) in a
tall pane — correct for pictures like Ruby or the CRT. For a **texture** like a
braille wall, where there's no shape to preserve, set `fit = "fill"` to stretch
each axis independently and fill the entire pane edge to edge (it upscales when
the pane is bigger than the source). Pair `fit = "fill"` with a dense noise/
braille source and Shift+V for a full-screen reactive wall.

### Reviewing shapes: `ring_shape = "cycle"`

Set `ring_shape = "cycle"` to auto-rotate through square → diamond → circle every
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
If `dance` shows a blank pane or stale frame, check the log:

```bash
tail -n 40 ~/.config/cliamp/plugins.log
```

Look for `[dance] error: ...` lines.

---

## Status

| | |
|---|---|
| State | In development — not released |
| Repo | `8bit64k/cliamp-plugin-dance` (private) |
| Entry file | `dance.lua` (repo root) |
| Test art | `ruby.txt` |
| Sibling plugin | [`cliamp-plugin-tubeamp`](https://github.com/8bit64k/cliamp-plugin-tubeamp) (shipped, v1.2.0) |

License: MIT © 8bit64k (added at release time).
