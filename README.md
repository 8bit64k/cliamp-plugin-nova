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

# 3. Copy a test art file too (the plugin needs one to render)
mkdir -p ~/.config/cliamp/art
cp ruby.txt ~/.config/cliamp/art/ruby.txt
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
art_path = "~/.config/cliamp/art/ruby.txt"   # required — path to the ASCII art file
bob_max = 2                                    # max vertical displacement, in chars
bob_direction = "both"                         # "up" | "down" | "both"
color_mode = "glow"                            # "glow" | "mono" | "passthrough"
mono_color = 11                                # ANSI 256 index, used when color_mode = "mono"
attack = 0.55                                  # smoothing attack (shared defaults with tubeamp)
release = 0.18                                 # smoothing release
overdrive = 0.78                               # band level above which a column flares red + bobs extra
```

If `art_path` is missing or the file can't be read, the plugin renders a visible
placeholder message instead of crashing.

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
