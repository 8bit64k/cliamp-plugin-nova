-- nova.lua — cliamp visualizer: braille wall that glows to the EQ feed.
--
-- v0.1 "square rings": the art is mapped into 10 concentric SQUARE rings
-- (Chebyshev distance from center). The innermost ring is driven by the lowest
-- EQ band (32 Hz bass), each ring outward by the next band, the outermost by
-- the highest band (16 kHz treble). Each cell is recolored by its ring's
-- smoothed band level using the shared tubeamp glow ramp. The art's original
-- glyphs are preserved (they carry the image density) — only color reacts.
--
-- No motion/jitter in v0.1 (deferred). See BRAINSTORM.md + README.md.

local p = plugin.register({
    name        = "nova",
    type        = "visualizer",
    version     = "0.1.0",
    description = "Braille wall visualizer — EQ-driven glow with presets, themes, and density mutation",
})

-- ---------- Configuration (read once at load) --------------------------------
-- Strip trailing inline comments from config values. Some TOML parsers (including
-- the one cliamp may use) leak #-comments into the value string, so "vantablack"
-- becomes "vantablack   # comment" — which fails exact key lookups.

local function clean(v)
    if v == nil then return nil end
    -- Strip trailing whitespace + optional #-comment
    return (v:gsub("%s*#.*$", ""))
end

local cfg_art_path   = clean(p:config("art_path"))
-- start: the procedural wall's resting glyph when no art_path is given. The wall
-- is generated on load (no file needed) -- "black" starts empty (⠀, U+2800) and
-- blooms dots in from nothing as the music lights each ring; "stipple" starts at
-- the faint least-dense texture (⠡, U+2821, the old dots_braille look) that
-- thickens toward solid. Same additive toward-center density either way; only the
-- resting floor differs. art_path (if set) overrides this with a loaded file.
local cfg_start = clean(p:config("start")) or "black"
local START_GLYPH = { black = 0x2800, stipple = 0x2821 }
local start_cp = START_GLYPH[cfg_start] or START_GLYPH["stipple"]
local cfg_color_mode = clean(p:config("color_mode")) or "glow"
local cfg_mono_color = tonumber(clean(p:config("mono_color"))) or 11
local cfg_attack     = tonumber(clean(p:config("attack"))) or 0.55
local cfg_release    = tonumber(clean(p:config("release"))) or 0.18
local cfg_overdrive  = tonumber(clean(p:config("overdrive"))) or 0.78
local cfg_tilt       = tonumber(clean(p:config("tilt"))) or 0.0
local cfg_theme_name = clean(p:config("theme")) or "amber"
local cfg_ring_shape = clean(p:config("ring_shape")) or "square"
local cfg_cycle_secs = tonumber(clean(p:config("cycle_seconds"))) or 20
if cfg_cycle_secs < 2 then cfg_cycle_secs = 2 end  -- guard against 0/typo thrash
local cfg_fit        = clean(p:config("fit")) or "contain"

-- Debug: when true, show the active preset name via cliamp.message() on change.
local cfg_debug = false
do
    local raw = p:config("debug")
    if type(raw) == "boolean" then
        cfg_debug = raw
    elseif raw ~= nil then
        local v = clean(tostring(raw)):lower():gsub("%s+", "")
        if v == "true" or v == "on" or v == "1" or v == "yes" then cfg_debug = true end
    end
end

-- Dead zone: noise gate — clamp band levels below this threshold to exactly 0
-- before the color and density paths read them. The round-mapping ramp-index fix
-- bumped low-level signal up one visible stop, making the outer rings glow faintly
-- on quiet passages. A small dead zone (~0.08-0.12) restores a clean noise floor
-- without affecting real musical content. 0 = off (default).
local cfg_dead_zone = tonumber(clean(p:config("dead_zone"))) or 0.0
if cfg_dead_zone < 0   then cfg_dead_zone = 0.0 end
if cfg_dead_zone > 0.5 then cfg_dead_zone = 0.5 end

-- Gamma: response curve shaping the level->brightness mapping. 1.0 = linear
-- (default, no change). > 1.0 compresses the low end (darker, more contrast
-- toward the top); < 1.0 lifts mid-levels (brighter, more even). Applied to
-- effective[] after the dead zone gate, before density and color.
local cfg_gamma = tonumber(clean(p:config("gamma"))) or 1.0
if cfg_gamma < 0.1 then cfg_gamma = 0.1 end
if cfg_gamma > 3.0 then cfg_gamma = 3.0 end

-- Cell aspect ratio: terminal cells are ~2x tall, so x-distances are scaled
-- down so circles read round instead of egg-shaped. 0.5 is the standard for
-- most terminal fonts; dial up if your font is unusually wide, down if narrow.
local cfg_cell_aspect = tonumber(clean(p:config("cell_aspect"))) or 0.5
if cfg_cell_aspect < 0.2 then cfg_cell_aspect = 0.2 end
if cfg_cell_aspect > 2.0 then cfg_cell_aspect = 2.0 end

-- Canvas cap: the render cost is LINEAR in drawn cells (draw_w*draw_h), so on a
-- very large pane (fit=fill fullscreen on a 4K terminal) the per-frame work can
-- get heavy. max_cols/max_rows clamp the DRAWN grid; the art is then centered in
-- the (larger) pane with the existing letterbox padding. 0 = unlimited (default),
-- so normal panes are completely unchanged. NOTE for fit=fill: a cap necessarily
-- makes the wall a centered block instead of edge-to-edge (you can't fill more
-- columns than you draw) -- that's the deliberate cost/coverage trade. Use
-- frame_skip instead if you want true edge-to-edge fill on a huge screen.
local cfg_max_cols = tonumber(clean(p:config("max_cols"))) or 0
local cfg_max_rows = tonumber(clean(p:config("max_rows"))) or 0
if cfg_max_cols < 0 then cfg_max_cols = 0 end
if cfg_max_rows < 0 then cfg_max_rows = 0 end

-- Render rate: cliamp ticks a visualizer at ~20 FPS while playing. For a smoothed
-- glow wall, rendering every frame is often more than the eye needs. render_rate
-- is the FRACTION of frames actually rendered, 0..1: 1.0 renders every frame (full
-- ~20 FPS, default -- no change), 0.5 renders half (~10 FPS), 0.25 renders 1 in 4
-- (~5 FPS). On the un-rendered frames the last output string is REUSED, cutting
-- AVERAGE render cost by ~(1-rate) regardless of pane size -- and unlike the
-- canvas cap it keeps fit=fill edge-to-edge (it trades refresh rate, not coverage).
-- Audio state (smoothing/heat/density) still advances every frame so the envelope
-- never freezes; only the expensive cell loop is skipped. A bass-transient ONSET
-- force-renders even on a skipped frame so kick FLARES are never dropped.
--
-- A rate of 0 would mean "never render," which is meaningless, so anything below
-- 0.25 is bumped to 0.25 (1-in-4, the slowest sane setting); above 1.0 clamps to
-- full rate. The continuous rate maps to an integer skip count internally
-- (skip = round(1/rate) - 1), so effective stops are ~{1.0, 0.5, 0.33, 0.25}.
local cfg_render_rate = tonumber(clean(p:config("render_rate")))
if cfg_render_rate == nil then cfg_render_rate = 1.0 end
if cfg_render_rate > 1.0 then cfg_render_rate = 1.0 end
if cfg_render_rate < 0.25 then cfg_render_rate = 0.25 end
-- Integer frames to skip between renders: we draw 1 of every (cfg_frame_skip + 1).
local cfg_frame_skip = math.floor(1 / cfg_render_rate + 0.5) - 1
if cfg_frame_skip < 0 then cfg_frame_skip = 0 end

-- Density mutation: as a braille cell climbs the level/color ramp, OR in dots so
-- the glyph thickens toward solid (toward full). This makes the braille WALL not
-- just brighten but gain matter on the peaks — a flare thickens the core. Only
-- braille glyphs (U+2800..U+28FF) mutate; anything else is left as-is. Default ON
-- (nova is a braille-wall plugin). Toggle off to keep the art's glyphs fixed.
local cfg_density = true
do
    local raw = p:config("density")
    if type(raw) == "boolean" then
        cfg_density = raw
    elseif raw ~= nil then
        local v = clean(tostring(raw)):lower():gsub("%s+", "")
        if v == "false" or v == "off" or v == "0" or v == "no" then cfg_density = false end
    end
end

-- Density envelope: dots fill/shed on their OWN attack/release, separate from
-- color smoothing — so the wall can pop dots in fast and melt them away slowly,
-- like CRT phosphor persistence. density_attack = fill speed (high=snappy),
-- density_release = shed speed (low=lingering trail). Both 1.0 = track instantly.
local cfg_dens_attack  = tonumber(clean(p:config("density_attack")))  or 0.6
local cfg_dens_release = tonumber(clean(p:config("density_release"))) or 0.15
if cfg_dens_attack  < 0 then cfg_dens_attack  = 0 elseif cfg_dens_attack  > 1 then cfg_dens_attack  = 1 end
if cfg_dens_release < 0 then cfg_dens_release = 0 elseif cfg_dens_release > 1 then cfg_dens_release = 1 end
-- cool over time instead of snapping off, so a kick flashes-and-fades.
-- overdrive_decay = fraction of heat RETAINED per frame: higher = longer tail.
-- 0 = no retention = instant snap (old behavior); ~0.85 = long glowing tail.
local cfg_od_decay = tonumber(clean(p:config("overdrive_decay"))) or 0.82
if cfg_od_decay < 0 then cfg_od_decay = 0 elseif cfg_od_decay > 0.97 then cfg_od_decay = 0.97 end
-- Bleed: only when a bass ring punches WHITE-HOT does it warm the ring just
-- outside it (band1->band2, band2->band3). Modest flares stay in place; only a
-- full slam blooms outward. Default on; toggle off for clean rings (e.g. CRT art).
local cfg_od_bleed = true
do
    local raw = p:config("overdrive_bleed")
    if type(raw) == "boolean" then
        cfg_od_bleed = raw
    elseif raw ~= nil then
        local v = clean(tostring(raw)):lower():gsub("%s+", "")
        if v == "false" or v == "off" or v == "0" or v == "no" then cfg_od_bleed = false end
    end
end

-- ring_blend: smooth the band boundaries by interpolating the LEVEL between the
-- two bands a cell sits between, instead of snapping to the nearest. Default ON.
-- Config comes in as a string ("true"/"false") or possibly a real bool; treat
-- anything explicitly falsey as off, everything else (incl. nil) as on.
local cfg_ring_blend = true
do
    local raw = p:config("ring_blend")
    if type(raw) == "boolean" then
        cfg_ring_blend = raw
    elseif raw ~= nil then
        local v = clean(tostring(raw)):lower():gsub("%s+", "")
        if v == "false" or v == "off" or v == "0" or v == "no" then
            cfg_ring_blend = false
        end
    end
end

-- Track whether the user EXPLICITLY set each preset-controlled key.
-- true = user set it (cfg_* holds their value); false/nil = use preset profile.
local user_set_attack         = (p:config("attack") ~= nil)
local user_set_release        = (p:config("release") ~= nil)
local user_set_overdrive      = (p:config("overdrive") ~= nil)
local user_set_tilt           = (p:config("tilt") ~= nil)
local user_set_dead_zone      = (p:config("dead_zone") ~= nil)
local user_set_gamma          = (p:config("gamma") ~= nil)
local user_set_density_attack  = (p:config("density_attack") ~= nil)
local user_set_density_release = (p:config("density_release") ~= nil)
local user_set_overdrive_decay = (p:config("overdrive_decay") ~= nil)
local user_set_overdrive_bleed = (p:config("overdrive_bleed") ~= nil)
local user_set_ring_blend      = (p:config("ring_blend") ~= nil)
local user_set_theme         = (p:config("theme") ~= nil)
local user_set_ring_shape    = (p:config("ring_shape") ~= nil)

-- ---------- Ring distance metric --------------------------------------------
-- Rings are level sets of a distance-from-center metric on the OUTPUT grid.
-- The shape of a ring is determined entirely by which metric we use; band
-- index, color, and everything downstream are identical across shapes.
--   square  : Chebyshev  d = max(|dx|, |dy|)  -> nested square frames (default)
--   diamond : Manhattan  d = |dx| + |dy|       -> nested diamonds (rotated squares)
--   circle  : Euclidean  d = sqrt(dx^2 + dy^2) -> nested circles/ellipses
-- dist() receives deltas that are ALREADY absolute AND already x-scaled (the
-- caller applies the *0.5 terminal-cell aspect correction before calling), so
-- this function is pure geometry and is reused verbatim for both the max_d
-- normalization and the per-cell band lookup -- they can never diverge.
local DIST = {
    square   = function(adx, ady) return (adx > ady) and adx or ady end,
    diamond  = function(adx, ady) return adx + ady end,
    circle   = function(adx, ady) return math.sqrt(adx * adx + ady * ady) end,
    squircle = function(adx, ady) return (adx^4 + ady^4) ^ 0.25 end,
    wings    = function(adx, _)   return adx end,
    layers   = function(_, ady)   return ady end,
}

-- ring_shape = "cycle" rotates square -> diamond -> circle every
-- cfg_cycle_secs seconds for hands-off visual review (no restart needed:
-- cliamp doesn't hot-reload config, but os.time() advances live while the
-- plugin runs, so the shape changes within a single session). os.time() is
-- one of the four os functions the cliamp sandbox keeps (time/date/clock/
-- getenv). The cycle is anchored to a load-time baseline so it always starts
-- on "square" when the visualizer is (re)selected.
local CYCLE_ORDER = { "square", "diamond", "circle", "squircle", "wings", "layers" }
local cycle_mode  = (cfg_ring_shape == "cycle")
local cycle_t0    = os.time()

-- Resolve the active distance metric for THIS frame. In fixed-shape mode this
-- is constant; in cycle mode it advances with wall-clock time. Returns both
-- the metric function and the shape name (so render can label the active shape).
local function active_dist()
    if cycle_mode then
        local elapsed = os.time() - cycle_t0
        if elapsed < 0 then elapsed = 0 end  -- clock skew guard
        local idx = (math.floor(elapsed / cfg_cycle_secs) % #CYCLE_ORDER) + 1
        local name = CYCLE_ORDER[idx]
        return DIST[name], name
    end
    return (DIST[cfg_ring_shape] or DIST["square"]),
           (DIST[cfg_ring_shape] and cfg_ring_shape or "square")
end

-- ---------- ANSI helpers -----------------------------------------------------

-- Hoist hot math functions to file-scope locals: in Lua a `math.floor` call is
-- two hash lookups (math, then floor) every time; locals skip that. Matters in
-- the per-cell render loop (thousands of cells per frame at fullscreen).
local floor = math.floor
local abs   = math.abs
local sqrt  = math.sqrt

local ESC = string.char(27)
-- Precompute all 256 SGR foreground escapes once, so the hot loop never rebuilds
-- the "\27[38;5;Nm" string via concatenation (which allocated per color change).
local FG = {}
for n = 0, 255 do FG[n] = ESC .. "[38;5;" .. n .. "m" end
local function fg256(n) return FG[n] or (ESC .. "[38;5;" .. n .. "m") end
local function bg256(n) return ESC .. "[48;5;" .. n .. "m" end
local function reset()  return ESC .. "[0m" end

-- ---------- Braille density mutation ----------------------------------------
-- A braille glyph is U+2800 + an 8-bit dot mask. "Toward full" = OR additional
-- dots into the base glyph as level rises, ending at solid ⣿ (U+28FF). Dots are
-- added in a bottom-up visual order so the cell appears to FILL UP, like a tiny
-- sub-cell level meter. Only braille codepoints mutate; callers pass nil for
-- non-braille cells (which are never touched).
--
-- IMPORTANT: cliamp runs gopher-lua (Lua 5.1) — NO native bitwise operators
-- (>> << | &) and no bit32. All bit work below is plain arithmetic on powers of
-- two, which is 5.1-safe. (Local `lua` may be 5.3+ and parse bitops fine; the
-- host would silently fail to load them. Verified gopher-lua = yuin/gopher-lua.)
--
-- Braille dot bit layout (cell is 2 cols x 4 rows):
--   col0: r0=1 r1=2 r2=4 r3=64    col1: r0=8 r1=16 r2=32 r3=128
--
-- DENSITY FILLS TOWARD CENTER. nova maps the art into concentric rings around
-- the pane center, so as the wall heats the matter should accrete TOWARD that
-- center, reinforcing the radial structure -- not always bottom-up. A cell LEFT
-- of center fills from its RIGHT edge inward; a cell ABOVE center fills from its
-- BOTTOM up; corners fill from the dot nearest the center. We pick a fill order
-- per cell by the SIGN of its offset from center (dirx, diry in {-1,0,1}).
--
-- The 9 orders below were derived by sorting the 8 dots so the ones on the
-- center-facing side fill first, then VISUALLY verified (scratchpad/viz_fill.lua:
-- every spatial position marches its dots toward center). Keyed
-- FILL_ORDERS[dirx][diry] with dirx,diry in {-1,0,1}.
local FILL_ORDERS = {
    [-1] = {  -- cell LEFT of center (center is to the right)
        [-1] = {128,32,64,16,4,8,2,1},   -- up-left:  toward down-right corner
        [ 0] = {8,16,32,128,1,2,4,64},   -- left:     toward right column
        [ 1] = {8,16,1,32,2,128,4,64},   -- dn-left:  toward up-right corner
    },
    [ 0] = {  -- cell on the vertical center line
        [-1] = {64,128,4,32,2,16,1,8},   -- up:       toward bottom (center below)
        [ 0] = {1,2,8,4,16,64,32,128},   -- on-center: balanced
        [ 1] = {1,8,2,16,4,32,64,128},   -- down:     toward top (center above)
    },
    [ 1] = {  -- cell RIGHT of center (center is to the left)
        [-1] = {64,4,128,2,32,1,16,8},   -- up-right: toward down-left corner
        [ 0] = {1,2,4,64,8,16,32,128},   -- right:    toward left column
        [ 1] = {1,2,8,4,16,64,32,128},   -- dn-right: toward up-left corner
    },
}

-- Encode a codepoint in 0x2800..0x28FF as 3-byte UTF-8 (no bitops; div/mod).
-- All braille codepoints are 3-byte: lead 0xE2, then two continuation bytes.
local braille_cache = {}   -- [codepoint] -> utf8 string, memoized
local function braille_char(cp)
    local s = braille_cache[cp]
    if s then return s end
    local b1 = 0xE0 + floor(cp / 4096)
    local b2 = 0x80 + (floor(cp / 64) % 64)
    local b3 = 0x80 + (cp % 64)
    s = string.char(b1, b2, b3)
    braille_cache[cp] = s
    return s
end

-- OR a single power-of-two bit into a mask (5.1-safe): add it only if not set.
local function set_bit(mask, bit)
    if floor(mask / bit) % 2 == 0 then return mask + bit end
    return mask
end

-- thicken(base_cp, level, fill_order, dkey) -> thickened glyph string, MEMOIZED.
-- The result depends on (dkey, base_cp, add) where add = round(level*8) in 0..8
-- and dkey identifies the toward-center fill order (0..8) -- at most 9 dirs x 256
-- base glyphs x 9 buckets. After warmup this is a couple table lookups, no bit
-- loop and no allocation in the hot path. thicken_cache[dkey][base_cp][add].
local thicken_cache = {}
local function thicken(base_cp, level, fill_order, dkey)
    local add = floor(level * 8 + 0.5)
    if add < 0 then add = 0 elseif add > 8 then add = 8 end
    local dcache = thicken_cache[dkey]
    if not dcache then dcache = {}; thicken_cache[dkey] = dcache end
    local row = dcache[base_cp]
    if row then
        local hit = row[add]
        if hit then return hit end
    else
        row = {}
        dcache[base_cp] = row
    end
    local mask = base_cp - 0x2800
    for k = 1, add do mask = set_bit(mask, fill_order[k]) end
    local s = braille_char(0x2800 + mask)
    row[add] = s
    return s
end

-- ---------- Color presets (single swap point for upstream theme integration) ---
-- Each preset: { glow = {11 ANSI 256 colors}, overdrive = {4 colors} }.
-- When cliamp exposes theme_colors(), add a from_cliamp_theme() function that
-- returns the same shape, then set active = from_cliamp_theme(name) here.
-- Until then, config key "theme" picks from this table.

local PRESETS = {
    amber = {
        name = "Amber (tubeamp family)",
        -- Original 11-stop amber ramp from tubeamp. Rich distinct stops — kept verbatim.
        glow      = { 232, 234, 52, 94, 130, 166, 202, 208, 214, 220, 226 },
        overdrive = { 160, 196, 197, 198 },
    },
    crt = {
        name = "CRT Green Phosphor",
        -- 11 stops spanning the full green range with wide gaps between adjacent stops.
        -- 232 = near-black baseline; then jumps through the green ANSI block aggressively.
        glow      = { 232, 22, 28, 34, 40, 46, 48, 82, 118, 154, 190 },
        overdrive = { 46, 82, 118, 190 },
    },
    vantablack = {
        name = "Vantablack (mono-ish high contrast)",
        -- 11 stops across the full grayscale range with 3-5 index gaps.
        -- 232 = baseline; 234-254 = visible grayscale; 255 = pure white.
        glow      = { 232, 234, 238, 242, 246, 249, 251, 253, 254, 255, 231 },
        overdrive = { 249, 253, 255, 231 },
    },
    whitehot = {
        name = "White Hot (high contrast)",
        -- 11 stops across the full grayscale range with 3-5 index gaps.
        -- 232 = baseline; 234-254 = visible grayscale; 255 = pure white.
        glow      = { 0, 232, 235, 238, 241, 244, 247, 251, 254, 255, 231 },
        overdrive = { 251, 254, 255, 231 },
    },
    blackhot = {
        name = "Black Hot (high contrast)",
        -- 11 stops across the full grayscale range with 3-5 index gaps.
        -- 232 = baseline; 234-254 = visible grayscale; 255 = pure white.
        glow      = { 231, 249, 247, 245, 243, 241, 239, 237, 235, 233, 16 },
        overdrive = { 238, 235, 233, 16},
    },
    aurora = {
        name = "Aurora (teal-cyan-green)",
        -- 11-stop cool palette: deep teal through cyan to bright green-yellow.
        -- Every adjacent pair is visibly distinct — no monochrome blending.
        glow      = { 232, 23, 30, 36, 42, 48, 83, 119, 155, 191, 195 },
        overdrive = { 48, 87, 123, 195 },
    },
    ember = {
        name = "Ember (green → yellow → red heat map)",
        -- 11-stop heat-map ramp with real yellows in the mid and true red
        -- at the peak: dark green → yellow-green → pure yellow → orange
        -- → true red → hot red. ANSI 256 indices.
        glow      = { 232, 22, 28, 64, 106, 154, 226, 214, 202, 196, 197 },
        -- Overdrive: red → magenta → white
        overdrive = { 196, 197, 201, 230 },
    },
    predator = {
        name = "Predator (thermal vision heatmap)",
        -- 11-stop ramp matching the iconic Predator thermal-vision palette.
        -- Cold: deep indigo → royal blue → cyan (background/cool surfaces).
        -- Warm: green → lime → olive → yellow-green → yellow (body heat onset).
        -- Hot: dark orange → red-orange (core body temperature).
        -- Peak: cream yellow-white (thermal overload). ANSI 256 indices.
        -- 230
        glow      = { 17, 21, 39, 46, 112, 142, 184, 220, 208, 196, 224 },
        -- Overdrive: red-orange → crimson → magenta-red → cream white
        overdrive = { 196, 160, 125, 224 },
    },
    flan = {
        name = "Flan (cream → gold → rose gold)",
        -- 11-stop ramp: cool cream → warm gold → hot rose gold.
        -- Like caramel custard browning under heat. ANSI 256 indices.
        glow      = { 232, 230, 229, 228, 226, 220, 214, 208, 209, 174, 167 },
        -- Overdrive: coral → dusty rose → deep rose → salmon pink
        overdrive = { 209, 174, 167, 210 },
    },
}

-- ---------- Preset profiles (dynamics + behaviour bundled for one-knob feel) ----
-- Each profile sets defaults for the dynamics/config keys that shape how the
-- wall MOVES and FEELS. The user's explicit TOML keys ALWAYS override. Keys not
-- listed in a profile fall back to their standard defaults (the "default" profile).
-- preset = "default" | "punchy" | "ethereal" | "retro" | "plasma"
-- cycle_presets = true to auto-rotate through all five on the cycle_seconds timer.
local PRESET_PROFILES = {
    -- Presets bundle dynamics + theme + ring_shape into a single feel.
    -- Keys not listed fall back to the "default" profile values.
    ["default"] = {
        theme = "amber",  ring_shape = "circle",
        attack = 0.55,  release = 0.18,
        overdrive = 0.78,  overdrive_decay = 0.82,  overdrive_bleed = true,
        density_attack = 0.6,  density_release = 0.15,
        dead_zone = 0.0,  gamma = 1.0,  tilt = 0.0,
        ring_blend = true,
    },
    punch = {
        theme = "crt",  ring_shape = "diamond",
        attack = 1,  release = .25,
        overdrive = 1,  overdrive_decay = 0.9,  overdrive_bleed = false,
        density_attack = 1,  density_release = .85,
        dead_zone = 0.2,  gamma = .99,  tilt = 0.0,
        ring_blend = true,
    },
    ethereal = {
        theme = "aurora",  ring_shape = "diamond",
        attack = 0.3,  release = 0.08,
        overdrive = 0.85,  overdrive_decay = 0.9,  overdrive_bleed = true,
        density_attack = 0.4,  density_release = 0.05,
        dead_zone = 0.0,  gamma = 0.6,  tilt = 0.4,
        ring_blend = true,
    },
    retro = {
        theme = "ember",  ring_shape = "square",
        attack = 0.6,  release = 0.15,
        overdrive = 0.82,  overdrive_decay = 0.78,  overdrive_bleed = false,
        density_attack = 0.7,  density_release = 0.2,
        dead_zone = 0.12,  gamma = 1.4,  tilt = 0.0,
        ring_blend = false,
    },
    plasma = {
        theme = "predator",  ring_shape = "circle",
        attack = 0.65,  release = 0.1,
        overdrive = 0.65,  overdrive_decay = 0.88,  overdrive_bleed = true,
        density_attack = 0.85,  density_release = 0.06,
        dead_zone = 0.03,  gamma = 0.9,  tilt = 0.2,
        ring_blend = true,
    },
    ghost = {
        theme = "vantablack",  ring_shape = "square",
        attack = 0.3,  release = 0.05,
        overdrive = 0.88,  overdrive_decay = 0.9,  overdrive_bleed = false,
        density_attack = 0.05,  density_release = 0.9,
        dead_zone = 0.00,  gamma = 2.6,  tilt = 0.5,
        ring_blend = true,
    },
    tacutacu = {
        theme = "flan",  ring_shape = "diamond",
        attack = 0.75,  release = 0.25,
        overdrive = 0.70,  overdrive_decay = 0.75,  overdrive_bleed = true,
        density_attack = 0.8,  density_release = 0.3,
        dead_zone = 0.05,  gamma = 1.1,  tilt = 0.0,
        ring_blend = true,
    },
     bloom = {
        theme = "whitehot",  ring_shape = "diamond",
        attack = 1,  release = 0.01,
        overdrive = 0.85,  overdrive_decay = 0.05,  overdrive_bleed = true,
        density_attack = 1,  density_release = 0.01,
        dead_zone = 0.0,  gamma = 0.95,  tilt = 0.5,
        ring_blend = true,
    },

}

-- Resolve active behaviour preset. preset = "default" | profile name.
-- cycle_presets = true rotates through all profiles on cycle_seconds (same timer
-- as ring_shape cycle) so you can preview without config edits.
local cfg_preset_name = clean(p:config("preset")) or "default"

-- cycle_presets: auto-rotate presets. Read as bool (same defensive pattern).
local cycle_presets = false
do
    local raw = p:config("cycle_presets")
    if type(raw) == "boolean" then
        cycle_presets = raw
    elseif raw ~= nil then
        local v = clean(tostring(raw)):lower():gsub("%s+", "")
        if v == "true" or v == "on" or v == "1" or v == "yes" then cycle_presets = true end
    end
end

local CYCLE_PRESET_NAMES = { "default", "punch", "ethereal", "retro", "plasma", "ghost", "bloom", "tacutacu" }

-- Resolve the active profile for THIS frame. In fixed mode this is constant;
-- in cycle mode it advances with wall-clock time (same cycle_t0 as ring_shape).
local function active_profile()
    if cycle_presets then
        local elapsed = os.time() - cycle_t0
        if elapsed < 0 then elapsed = 0 end
        local idx = (math.floor(elapsed / cfg_cycle_secs) % #CYCLE_PRESET_NAMES) + 1
        local name = CYCLE_PRESET_NAMES[idx]
        return PRESET_PROFILES[name] or PRESET_PROFILES["default"], name
    end
    return PRESET_PROFILES[cfg_preset_name] or PRESET_PROFILES["default"],
           (PRESET_PROFILES[cfg_preset_name] and cfg_preset_name or "default")
end

-- Resolve active preset (fall back to amber on unknown name).
local active_preset = PRESETS[cfg_theme_name] or PRESETS["amber"]
local glow_ramp      = active_preset.glow
local overdrive_ramp = active_preset.overdrive
local glow_n         = #glow_ramp       -- cached lengths (avoid # in hot path)
local overdrive_n    = #overdrive_ramp

local function glow_color(level, hot)
    local ramp, n
    if hot then ramp, n = overdrive_ramp, overdrive_n
    else        ramp, n = glow_ramp, glow_n end
    -- Round (not floor) so the TOP ramp stop is reachable below level==1.0.
    -- With floor, the brightest color only appeared at an exact 1.0, which the
    -- smoothed/heat level basically never hits — so the peak (e.g. white) was
    -- effectively unreachable. Rounding spreads stops evenly across [0,1].
    local idx = floor(level * (n - 1) + 0.5) + 1
    if idx < 1 then idx = 1 elseif idx > n then idx = n end
    return ramp[idx]
end

-- ---------- Art loading + ring precompute ------------------------------------
-- Loaded once. art_lines = {string,...}; ring_of[y][x] = band index 1..10.

local art_lines   = nil
local art_cells   = nil    -- [y][x] -> single display-cell glyph string
local art_code    = nil    -- [y][x] -> braille codepoint if braille cell, else nil
local art_w       = 0      -- max display width across rows
local art_h       = 0
local load_error  = nil    -- non-nil string => render the placeholder

-- Count display columns: UTF-8 lead bytes only (continuation bytes 0x80..0xBF
-- don't advance a column). Single-width BMP assumption — fine for ASCII art.
local function visible_cols(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

-- Index the i-th display column's byte range in a (possibly UTF-8) string.
-- Returns the substring for display column `col` (1-based), or " " past the end.
local function char_at(s, col)
    local seen = 0
    local i = 1
    local n = #s
    while i <= n do
        local b = s:byte(i)
        -- width of this UTF-8 sequence in bytes
        local len = 1
        if b >= 0xF0 then len = 4
        elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2 end
        seen = seen + 1
        if seen == col then
            return s:sub(i, i + len - 1)
        end
        i = i + len
    end
    return " "
end

-- Expand a leading ~ or $HOME / ${HOME} to the absolute home dir. cliamp's
-- fs layer calls Go's os.ReadFile/os.Stat directly, which do NOT expand the
-- shell tilde — so we must do it here or "~/foo" silently fails to load.
local function expand_path(path)
    if not path or path == "" then return path end
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    if home then
        if path == "~" then
            return home
        elseif path:sub(1, 2) == "~/" then
            return home .. path:sub(2)
        end
        path = path:gsub("%${HOME}", home):gsub("%$HOME", home)
    end
    return path
end

-- Procedurally generate a uniform braille wall -- no file needed. Every cell is
-- the same `start_cp` base glyph; the render loop then lights + thickens it from
-- the EQ exactly as it would a loaded file. We fill a fixed source grid (35x188,
-- matching the old dots_braille.txt dims) so fit=contain/fill behave identically
-- to the file the wall used to ship as. art_code[y][x] = start_cp everywhere
-- (uniform), so density mutation has its base with zero per-cell decode.
local GEN_W, GEN_H = 188, 35
local function generate_wall()
    art_lines, load_error = nil, nil
    art_w, art_h = GEN_W, GEN_H
    local glyph = braille_char(start_cp)
    local is_braille = (start_cp >= 0x2800 and start_cp <= 0x28FF)
    art_cells = {}
    art_code  = {}
    for y = 1, art_h do
        local row  = {}
        local crow = {}
        for x = 1, art_w do
            row[x] = glyph
            if is_braille then crow[x] = start_cp end
        end
        art_cells[y] = row
        art_code[y]  = crow
    end
end

local function load_art()
    art_lines, art_cells, art_code = nil, nil, nil
    art_w, art_h, load_error = 0, 0, nil

    -- No art_path => procedural wall (the default; no file dependency).
    if not cfg_art_path or cfg_art_path == "" then
        generate_wall()
        return
    end
    local path = expand_path(cfg_art_path)
    if not (cliamp and cliamp.fs and cliamp.fs.exists(path)) then
        load_error = "nova: art file not found: " .. tostring(path)
        return
    end

    local data = cliamp.fs.read(path)
    if not data or data == "" then
        load_error = "nova: art file empty or unreadable"
        return
    end

    -- Split into lines (strip a trailing newline, tolerate CRLF).
    local lines = {}
    data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (data .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    -- Drop a single trailing empty line from the terminal newline.
    if #lines > 0 and lines[#lines] == "" then lines[#lines] = nil end
    if #lines == 0 then
        load_error = "nova: art file has no rows"
        return
    end

    art_lines = lines
    art_h = #lines
    for _, l in ipairs(lines) do
        local w = visible_cols(l)
        if w > art_w then art_w = w end
    end
    if art_w == 0 then
        load_error = "nova: art file has zero width"
        art_lines = nil
        return
    end

    -- Pre-extract each row into a flat array of display-cell glyphs so render
    -- can index art cells in O(1) (avoids re-walking UTF-8 every frame).
    -- art_code[y][x] = the braille codepoint (0x2800..0x28FF) if the cell is a
    -- braille glyph, else nil. Precomputed so density mutation never decodes
    -- UTF-8 in the hot loop.
    art_cells = {}
    art_code  = {}
    for y = 1, art_h do
        local row = {}
        local crow = {}
        local s = art_lines[y]
        local seen, i, n = 0, 1, #s
        while i <= n do
            local b = s:byte(i)
            local len = 1
            if b >= 0xF0 then len = 4
            elseif b >= 0xE0 then len = 3
            elseif b >= 0xC0 then len = 2 end
            seen = seen + 1
            row[seen] = s:sub(i, i + len - 1)
            -- braille is the 3-byte sequence 0xE2 0xA0..0xA3 0x80..0xBF =>
            -- codepoint 0x2800..0x28FF. Decode without bitops (5.1-safe).
            if len == 3 and b == 0xE2 then
                local b2 = s:byte(i + 1)
                local b3 = s:byte(i + 2)
                if b2 and b3 then
                    local cp = ((b - 0xE0) * 4096)
                             + ((b2 - 0x80) * 64) + (b3 - 0x80)
                    if cp >= 0x2800 and cp <= 0x28FF then crow[seen] = cp end
                end
            end
            i = i + len
        end
        -- pad short rows with spaces to art_w
        for x = seen + 1, art_w do row[x] = " " end
        art_cells[y] = row
        art_code[y]  = crow
    end
end

-- ---------- Per-instance state -----------------------------------------------

local smoothed  = {0,0,0,0,0,0,0,0,0,0}
-- Overdrive "heat" for the two bass bands: latches on a transient ONSET, then
-- decays slowly so the flare flashes-and-fades.
local heat      = {0, 0}
-- Slow-moving baseline of each bass band's level. A flare fires only when the
-- live level jumps a margin ABOVE this baseline (a transient onset = a kick),
-- NOT when bass merely sits high — cliamp's bands are pre-smoothed and often
-- peg near the top, so an absolute-threshold trigger fires constantly and the
-- flare/bleed stop reading as events. The baseline tracks the recent average so
-- only genuine punches stand out.
local bass_base = {0, 0}
-- effective[] = the level the COLOR uses per band each frame: smoothed plus any
-- overdrive heat (bands 1-2) and white-hot bleed (into bands 2-3). Built once
-- per frame; the per-cell color path reads this instead of smoothed[] so the
-- flare is uniform across each concentric ring (correct) and costs nothing per cell.
local effective = {0,0,0,0,0,0,0,0,0,0}
-- Density envelope per band: chases effective[] with its own attack/release so
-- dots fill/shed on a separate timescale from color (phosphor-persistence feel).
-- This is the level density mutation reads (NOT effective[] directly).
local dens      = {0,0,0,0,0,0,0,0,0,0}

-- Frame-skip state: cache the last rendered string and a frame counter so we can
-- cheaply reuse output on skipped frames. onset_fired flags a bass transient this
-- frame so a skip can be overridden (flares must never be dropped).
local last_output = nil
local skip_counter = 0
local last_rows = 0
local last_cols = 0
local last_shown_preset = nil

function p:init(rows, cols)
    for i = 1, 10 do smoothed[i] = 0; effective[i] = 0; dens[i] = 0 end
    heat[1], heat[2] = 0, 0
    bass_base[1], bass_base[2] = 0, 0
    last_output = nil
    skip_counter = 0
    last_shown_preset = nil
    load_art()
    -- Debug: show active preset once on visualizer selection. Safe here
    -- (outside the render loop); cliamp.message blocks if called in render().
    if cfg_debug and cliamp and cliamp.message then
        local _, pname = active_profile()
        cliamp.message("preset: " .. pname, 2)
    end
end

function p:destroy() end

-- ---------- Render helpers ---------------------------------------------------

local function placeholder(rows, cols, msg)
    -- Centered single-line error/status message. Always a string.
    local lines = {}
    local mid = math.floor(rows / 2) + 1
    local pad = math.max(0, math.floor((cols - #msg) / 2))
    for r = 1, rows do
        if r == mid then
            lines[r] = string.rep(" ", pad) .. fg256(208) .. msg .. reset()
        else
            lines[r] = ""
        end
    end
    return table.concat(lines, "\n")
end

-- ---------- The render loop --------------------------------------------------

function p:render(bands, frame, rows, cols)
    -- Profile overlay: if a named preset (or cycle_presets) is active, apply
    -- the profile's values to any config key the user didn't explicitly set.
    -- This runs first so the smoothing math and hot loop use the right values.
    -- Called every frame (not just on preset change) — cost is negligible.
    do
        local prof, _ = active_profile()
        local function apply_num(key, var, user_set)
            if not user_set then
                local v = prof[key]
                if v ~= nil then
                    -- Re-apply clamping (same ranges as the config reads)
                    if key == "dead_zone" then
                        if v < 0 then v = 0 elseif v > 0.5 then v = 0.5 end
                    elseif key == "gamma" then
                        if v < 0.1 then v = 0.1 elseif v > 3.0 then v = 3.0 end
                    elseif key == "density_attack" or key == "density_release" then
                        if v < 0 then v = 0 elseif v > 1 then v = 1 end
                    elseif key == "overdrive_decay" then
                        if v < 0 then v = 0 elseif v > 0.97 then v = 0.97 end
                    end
                    -- Assign to the upvalue (non-local assignment in Lua
                    -- rebinds the module-level variable for this frame)
                    if key == "attack" then cfg_attack = v
                    elseif key == "release" then cfg_release = v
                    elseif key == "overdrive" then cfg_overdrive = v
                    elseif key == "tilt" then cfg_tilt = v
                    elseif key == "dead_zone" then cfg_dead_zone = v
                    elseif key == "gamma" then cfg_gamma = v
                    elseif key == "density_attack" then cfg_dens_attack = v
                    elseif key == "density_release" then cfg_dens_release = v
                    elseif key == "overdrive_decay" then cfg_od_decay = v
                    end
                end
            end
        end
        local function apply_bool(key, user_set)
            if not user_set then
                local v = prof[key]
                if v ~= nil then
                    if key == "overdrive_bleed" then cfg_od_bleed = v
                    elseif key == "ring_blend" then cfg_ring_blend = v
                    end
                end
            end
        end
        apply_num("attack", cfg_attack, user_set_attack)
        apply_num("release", cfg_release, user_set_release)
        apply_num("overdrive", cfg_overdrive, user_set_overdrive)
        apply_num("tilt", cfg_tilt, user_set_tilt)
        apply_num("dead_zone", cfg_dead_zone, user_set_dead_zone)
        apply_num("gamma", cfg_gamma, user_set_gamma)
        apply_num("density_attack", cfg_dens_attack, user_set_density_attack)
        apply_num("density_release", cfg_dens_release, user_set_density_release)
        apply_num("overdrive_decay", cfg_od_decay, user_set_overdrive_decay)
        apply_bool("overdrive_bleed", user_set_overdrive_bleed)
        apply_bool("ring_blend", user_set_ring_blend)

        -- Theme swap: if profile specifies a theme the user didn't set,
        -- resolve the colour ramp and swap glow_ramp / overdrive_ramp.
        if not user_set_theme then
            local t = prof["theme"]
            if t then
                local theme_preset = PRESETS[t]
                if theme_preset then
                    cfg_theme_name = t
                    glow_ramp      = theme_preset.glow
                    overdrive_ramp = theme_preset.overdrive
                    glow_n         = #glow_ramp
                    overdrive_n    = #overdrive_ramp
                end
            end
        end
        -- Ring shape swap: if profile specifies a shape the user didn't set,
        -- update cfg_ring_shape so active_dist() picks it up next frame.
        -- Round trip through the DIST table to validate.
        if not user_set_ring_shape then
            local s = prof["ring_shape"]
            if s and DIST[s] then
                cfg_ring_shape = s
            end
        end
    end

    -- Debug: track preset changes so we can show the name on first render.
    -- cliamp.message() is NOT safe inside render() (blocks the UI loop),
    -- so we defer the actual message to init() and show the name inline.
    if cfg_debug then
        local _, pname = active_profile()
        last_shown_preset = pname
    end

    -- Always advance smoothing state, even on error/hidden paths, so a resume
    -- never shows cold state.
    for i = 1, 10 do
        local raw = bands[i] or 0
        -- spectral tilt: gently lift higher bands so sparse treble still lights
        -- the outer rings. tilt=0 disables.
        if cfg_tilt > 0 then
            raw = raw * (1.0 + cfg_tilt * (i - 1) / 9)
        end
        if raw > 1.0 then raw = 1.0 end
        if raw < 0.0 then raw = 0.0 end
        if raw > smoothed[i] then
            smoothed[i] = smoothed[i] + (raw - smoothed[i]) * cfg_attack
        else
            smoothed[i] = smoothed[i] - (smoothed[i] - raw) * cfg_release
        end
    end

    -- Build effective[] = the level the COLOR uses this frame. Start from the
    -- smoothed levels, then layer overdrive flare + white-hot bleed on the bass.
    for i = 1, 10 do effective[i] = smoothed[i] end

    -- Overdrive flare on the two bass bands (1,2), TRANSIENT-triggered. A flare
    -- fires on a kick ONSET — when the live level jumps a margin above its slow
    -- baseline AND clears the overdrive floor — not merely when bass sits high
    -- (which it often does). On a fired onset, heat latches to the live level
    -- (fast attack); otherwise heat is RETAINED at cfg_od_decay per frame so the
    -- flare flashes then cools. effective = max(smoothed, heat), so the fading
    -- tail never dims below the live level. cfg_od_decay=0 => no tail => snap.
    local BASE_RATE   = 0.05   -- baseline EMA: slow, so it tracks recent average
    local ONSET_MARGIN = 0.18  -- live must exceed baseline by this to be an onset
    local onset_fired = false  -- a bass transient this frame -> override frame-skip
    for i = 1, 2 do
        local onset = (smoothed[i] >= cfg_overdrive)
                      and (smoothed[i] >= bass_base[i] + ONSET_MARGIN)
        if onset then onset_fired = true end
        if onset and smoothed[i] > heat[i] then
            heat[i] = smoothed[i]                 -- latch hot on the punch
        else
            heat[i] = heat[i] * cfg_od_decay      -- retain a fraction; tail cools
            if heat[i] < smoothed[i] then heat[i] = smoothed[i] end
        end
        if heat[i] > effective[i] then effective[i] = heat[i] end
        -- advance the slow baseline AFTER the onset test (so the spike itself
        -- doesn't immediately raise the bar it has to clear).
        bass_base[i] = bass_base[i] + (smoothed[i] - bass_base[i]) * BASE_RATE
    end

    -- Bleed: ONLY when a bass ring reaches PEAK FLARE (heat at the very top of
    -- the overdrive ramp) does it warm the ring just outside it (1->2, 2->3).
    -- A modest flare stays put; only a full slam blooms outward. Scaled by how
    -- far past the peak-flare cutoff we are, so it's proportional, clamped to <= 1.
    if cfg_od_bleed then
        local FLARE_PEAK = 0.92     -- top-of-overdrive-ramp cutoff
        for i = 1, 2 do
            if heat[i] >= FLARE_PEAK then
                local over = (heat[i] - FLARE_PEAK) / (1 - FLARE_PEAK)  -- 0..1
                local spill = 0.45 * over            -- partial warmth, never full
                local tgt = i + 1                    -- ring just outside
                local v = effective[tgt] + spill
                if v > 1 then v = 1 end
                if v > effective[tgt] then effective[tgt] = v end
            end
        end
    end

    -- Dead zone gate: clamp any band level below cfg_dead_zone to 0.
    -- This runs after the full effective[] layer is built (smoothed + heat + bleed)
    -- but before the per-cell color loop and the density envelope — one gate,
    -- kills both color and density at once. 0 = off (default).
    if cfg_dead_zone > 0 then
        for i = 1, 10 do
            if effective[i] < cfg_dead_zone then effective[i] = 0 end
        end
    end

    -- Gamma: shape the response curve. Applied after the dead zone gate so
    -- bands that were clamped to 0 stay at 0 regardless of gamma.
    if cfg_gamma ~= 1.0 then
        for i = 1, 10 do
            if effective[i] > 0 then
                effective[i] = effective[i] ^ cfg_gamma
            end
        end
    end

    -- Density envelope: chase effective[] with its OWN attack/release so dots
    -- fill fast and shed slow (CRT phosphor persistence) independent of color.
    -- Only advanced when density is on. dens[] is what the glyph mutation reads.
    if cfg_density then
        for i = 1, 10 do
            local target = effective[i]
            if target > dens[i] then
                dens[i] = dens[i] + (target - dens[i]) * cfg_dens_attack
            else
                dens[i] = dens[i] - (dens[i] - target) * cfg_dens_release
            end
        end
    end
    if load_error then
        return placeholder(rows, cols, load_error)
    end
    -- Lazy-load: if init() didn't run (or hasn't yet), load on first render.
    -- This makes the plugin robust to host init-timing differences. art_cells is
    -- the sentinel (set by BOTH the file loader and the procedural generator);
    -- art_lines is only set on the file path, so don't gate on it here.
    if not art_cells and not load_error then
        load_art()
    end
    if load_error then
        return placeholder(rows, cols, load_error)
    end
    if not art_cells then
        return placeholder(rows, cols, "nova: no art loaded")
    end
    if rows < 1 or cols < 1 then return "" end

    -- Frame-skip gate. All audio state (smoothing/heat/baseline/density) has been
    -- advanced above, so skipping here only elides the expensive per-cell render
    -- -- the envelope keeps moving underneath. Reuse the cached frame UNLESS:
    --   * frame_skip is 0 (feature off), or
    --   * we have no cached frame yet, or
    --   * the pane size changed (cache would be the wrong dimensions), or
    --   * a bass transient fired this frame (force a render so flares never drop).
    -- The counter renders 1 frame then reuses for the next `frame_skip` frames.
    if cfg_frame_skip > 0
        and last_output ~= nil
        and last_rows == rows and last_cols == cols
        and not onset_fired then
        if skip_counter > 0 then
            skip_counter = skip_counter - 1
            return last_output
        end
    end
    -- About to render fresh: arm the skip counter for the next N frames.
    skip_counter = cfg_frame_skip

    -- Canvas cap: clamp the grid we actually DRAW into. The art is sized against
    -- the capped dimensions, then centered in the FULL pane below (existing
    -- letterbox padding). Cost is linear in drawn cells, so this bounds the
    -- per-frame work on huge panes. 0 = unlimited. We never draw larger than the
    -- real pane either way.
    local cap_rows = rows
    local cap_cols = cols
    if cfg_max_rows > 0 and cap_rows > cfg_max_rows then cap_rows = cfg_max_rows end
    if cfg_max_cols > 0 and cap_cols > cfg_max_cols then cap_cols = cfg_max_cols end

    -- Fit the art into the (capped) canvas. Two modes:
    --   contain (default): scale DOWN preserving aspect, centered, letterboxed.
    --     Right for pictures (Ruby, CRT) where the shape must be preserved.
    --   fill: stretch each axis independently to the FULL canvas, edge to edge,
    --     no letterbox. Right for textures like the braille wall where there's
    --     no "correct" shape to keep. (With a cap < pane, fill reaches the cap,
    --     not the pane edge -- a centered block; that's the cost/coverage trade.)
    -- Never scales a source axis beyond the canvas in either mode.
    local draw_h, draw_w
    if cfg_fit == "fill" then
        draw_h = cap_rows
        draw_w = cap_cols
    else
        draw_h = art_h
        draw_w = art_w
        if draw_h > cap_rows then draw_h = cap_rows end
        if draw_w > cap_cols then draw_w = cap_cols end
        -- preserve aspect-ish: if one axis must shrink, shrink the other in step
        -- so the face doesn't get grotesquely squished. Use the tighter ratio.
        local sh = draw_h / art_h
        local sw = draw_w / art_w
        local s  = (sh < sw) and sh or sw
        draw_h = math.max(1, math.floor(art_h * s + 0.5))
        draw_w = math.max(1, math.floor(art_w * s + 0.5))
        if draw_h > cap_rows then draw_h = cap_rows end
        if draw_w > cap_cols then draw_w = cap_cols end
    end

    -- Ring geometry computed on the OUTPUT grid (resolution-independent).
    -- Rings are level sets of the selected distance metric (square/diamond/
    -- circle); x scaled 0.5 for the ~2:1 terminal cell aspect ratio so circles
    -- read as circles, not eggs. Band 1 (bass) = center, 10 = edge.
    -- Resolve the metric ONCE per frame (in cycle mode it advances with the
    -- wall clock; resolving once keeps the whole frame on a single shape and
    -- keeps max_d consistent with the per-cell lookup).
    local dist = active_dist()
    local ocx = (draw_w + 1) / 2
    local ocy = (draw_h + 1) / 2
    local max_d = 0
    do
        local dx = (draw_w - ocx) * cfg_cell_aspect
        local dy = (draw_h - ocy)
        max_d = dist(dx, dy)
        if max_d <= 0 then max_d = 1 end
    end

    local left_pad = floor((cols - draw_w) / 2)
    local top_pad  = floor((rows - draw_h) / 2)
    local pad_str  = string.rep(" ", left_pad)

    -- Per-frame scalars hoisted out of the loops (avoid recomputing per cell).
    local inv_dw = art_w / draw_w     -- source-col scale
    local inv_dh = art_h / draw_h     -- source-row scale
    local nine_over_maxd = 9 / max_d  -- pos = d * this
    local is_pass  = (cfg_color_mode == "passthrough")
    local is_mono  = (cfg_color_mode == "mono")
    local do_dens  = cfg_density
    local do_blend = cfg_ring_blend

    local out = {}
    for _ = 1, top_pad do out[#out + 1] = "" end

    for oy = 1, draw_h do
        -- map output row -> source row (nearest neighbor)
        local sy = floor((oy - 0.5) * inv_dh) + 1
        if sy < 1 then sy = 1 elseif sy > art_h then sy = art_h end
        local srow  = art_cells[sy]
        local scode = art_code[sy]

        -- vertical distance is constant across this row -> hoist out of x-loop
        local dy = abs(oy - ocy)
        -- vertical direction toward center (sign of offset): -1 above, +1 below,
        -- 0 on the center line. Density fills toward center, so pick the row's
        -- fill-order sub-table once here; the per-cell dirx selects within it.
        local diry = (oy < ocy) and -1 or ((oy > ocy) and 1 or 0)
        local fill_row = FILL_ORDERS[-1][diry]   -- left-of-center orders (default)
        local fill_mid = FILL_ORDERS[0][diry]
        local fill_rgt = FILL_ORDERS[1][diry]

        local parts = { pad_str }
        local np = 1                 -- track append index (avoid #parts per cell)
        local last_color = nil
        for ox = 1, draw_w do
            local sx = floor((ox - 0.5) * inv_dw) + 1
            if sx < 1 then sx = 1 elseif sx > art_w then sx = art_w end
            local ch = srow[sx] or " "

            if is_pass then
                np = np + 1; parts[np] = ch
            else
                -- ring position for this output cell
                local dx = abs(ox - ocx) * cfg_cell_aspect
                local pos = dist(dx, dy) * nine_over_maxd
                if pos < 0 then pos = 0 elseif pos > 9 then pos = 9 end

                local lvl, dlvl
                if do_blend then
                    local lo = floor(pos)
                    if lo > 8 then lo = 8 end
                    local frac = pos - lo
                    local a = effective[lo + 1]; local b = effective[lo + 2]
                    lvl = a + (b - a) * frac
                    local da = dens[lo + 1]; local db = dens[lo + 2]
                    dlvl = da + (db - da) * frac
                else
                    local band = 1 + floor(pos + 0.5)
                    if band < 1 then band = 1 elseif band > 10 then band = 10 end
                    lvl = effective[band]
                    dlvl = dens[band]
                end

                local color
                if is_mono then
                    color = cfg_mono_color
                    if lvl < 0.12 and ch ~= " " then color = 236 end
                else
                    color = glow_color(lvl, lvl >= cfg_overdrive)
                end

                -- density: thicken braille glyph (cached lookup). braille cells only.
                -- Dots fill TOWARD CENTER: pick the fill order by this cell's
                -- direction from center (dirx selects within the row's diry table).
                if do_dens and scode then
                    local base_cp = scode[sx]
                    if base_cp then
                        local fo, dirx
                        if ox < ocx then fo, dirx = fill_row, -1
                        elseif ox > ocx then fo, dirx = fill_rgt, 1
                        else fo, dirx = fill_mid, 0 end
                        -- dkey 0..8 = (dirx+1)*3 + (diry+1): unique per direction.
                        ch = thicken(base_cp, dlvl, fo, (dirx + 1) * 3 + (diry + 1))
                    end
                end

                if color ~= last_color then
                    np = np + 1; parts[np] = FG[color] or fg256(color)
                    last_color = color
                end
                np = np + 1; parts[np] = ch
            end
        end
        if not is_pass then
            np = np + 1; parts[np] = reset()
        end
        out[#out + 1] = table.concat(parts)
    end

    for _ = #out + 1, rows do out[#out + 1] = "" end

    -- Debug footer: show preset + theme on the last row when cycling.
    -- Safe here (no API calls) — just paints into the output string.
    if cfg_debug and rows > 0 and last_shown_preset then
        local label = " [" .. last_shown_preset .. " + " .. cfg_theme_name .. "] "
        local lc = visible_cols(label)
        local pad = math.floor((cols - lc) / 2)
        if pad < 0 then pad = 0 end
        out[rows] = fg256(244) .. bg256(232) .. string.rep(" ", pad) .. label .. reset()
    end

    -- Cache the rendered frame so frame-skip can reuse it. Stash the pane size too
    -- so a resize forces a fresh render (a stale cache would be the wrong shape).
    local result = table.concat(out, "\n")
    last_output = result
    last_rows = rows
    last_cols = cols
    return result
end
