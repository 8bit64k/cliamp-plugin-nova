-- dance.lua — cliamp visualizer: animate a user-supplied ASCII art file from the EQ feed.
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
    name        = "dance",
    type        = "visualizer",
    version     = "0.1.0",
    description = "ASCII art that glows to the EQ in concentric square rings",
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

-- Overdrive flare: when bands 1-2 (bass) cross cfg_overdrive they latch hot and
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
    square  = function(adx, ady) return (adx > ady) and adx or ady end,
    diamond = function(adx, ady) return adx + ady end,
    circle  = function(adx, ady) return math.sqrt(adx * adx + ady * ady) end,
}

-- ring_shape = "cycle" rotates square -> diamond -> circle every
-- cfg_cycle_secs seconds for hands-off visual review (no restart needed:
-- cliamp doesn't hot-reload config, but os.time() advances live while the
-- plugin runs, so the shape changes within a single session). os.time() is
-- one of the four os functions the cliamp sandbox keeps (time/date/clock/
-- getenv). The cycle is anchored to a load-time baseline so it always starts
-- on "square" when the visualizer is (re)selected.
local CYCLE_ORDER = { "square", "diamond", "circle" }
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

local ESC = string.char(27)
local function fg256(n) return ESC .. "[38;5;" .. n .. "m" end
local function reset()  return ESC .. "[0m" end

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
        overdrive = { 160, 196, 197, 231 },
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
    aurora = {
        name = "Aurora (teal-cyan-green)",
        -- 11-stop cool palette: deep teal through cyan to bright green-yellow.
        -- Every adjacent pair is visibly distinct — no monochrome blending.
        glow      = { 232, 23, 30, 36, 42, 48, 83, 119, 155, 191, 195 },
        overdrive = { 48, 87, 123, 195 },
    },
}

-- Resolve active preset (fall back to amber on unknown name).
local active_preset = PRESETS[cfg_theme_name] or PRESETS["amber"]
local glow_ramp      = active_preset.glow
local overdrive_ramp = active_preset.overdrive

local function glow_color(level, hot)
    local ramp = hot and overdrive_ramp or glow_ramp
    -- Round (not floor) so the TOP ramp stop is reachable below level==1.0.
    -- With floor, the brightest color only appeared at an exact 1.0, which the
    -- smoothed/heat level basically never hits — so the peak (e.g. white) was
    -- effectively unreachable. Rounding spreads stops evenly across [0,1].
    local idx = math.floor(level * (#ramp - 1) + 0.5) + 1
    if idx < 1 then idx = 1 end
    if idx > #ramp then idx = #ramp end
    return ramp[idx]
end

-- ---------- Art loading + ring precompute ------------------------------------
-- Loaded once. art_lines = {string,...}; ring_of[y][x] = band index 1..10.

local art_lines   = nil
local art_cells   = nil    -- [y][x] -> single display-cell glyph string
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

local function load_art()
    art_lines, art_cells = nil, nil
    art_w, art_h, load_error = 0, 0, nil

    if not cfg_art_path or cfg_art_path == "" then
        load_error = "dance: no art_path configured"
        return
    end
    local path = expand_path(cfg_art_path)
    if not (cliamp and cliamp.fs and cliamp.fs.exists(path)) then
        load_error = "dance: art file not found: " .. tostring(path)
        return
    end

    local data = cliamp.fs.read(path)
    if not data or data == "" then
        load_error = "dance: art file empty or unreadable"
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
        load_error = "dance: art file has no rows"
        return
    end

    art_lines = lines
    art_h = #lines
    for _, l in ipairs(lines) do
        local w = visible_cols(l)
        if w > art_w then art_w = w end
    end
    if art_w == 0 then
        load_error = "dance: art file has zero width"
        art_lines = nil
        return
    end

    -- Pre-extract each row into a flat array of display-cell glyphs so render
    -- can index art cells in O(1) (avoids re-walking UTF-8 every frame).
    art_cells = {}
    for y = 1, art_h do
        local row = {}
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
            i = i + len
        end
        -- pad short rows with spaces to art_w
        for x = seen + 1, art_w do row[x] = " " end
        art_cells[y] = row
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

function p:init(rows, cols)
    for i = 1, 10 do smoothed[i] = 0; effective[i] = 0 end
    heat[1], heat[2] = 0, 0
    bass_base[1], bass_base[2] = 0, 0
    load_art()
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
    for i = 1, 2 do
        local onset = (smoothed[i] >= cfg_overdrive)
                      and (smoothed[i] >= bass_base[i] + ONSET_MARGIN)
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

    if load_error then
        return placeholder(rows, cols, load_error)
    end
    -- Lazy-load: if init() didn't run (or hasn't yet), load on first render.
    -- This makes the plugin robust to host init-timing differences.
    if not art_lines and not load_error then
        load_art()
    end
    if load_error then
        return placeholder(rows, cols, load_error)
    end
    if not art_lines then
        return placeholder(rows, cols, "dance: no art loaded")
    end
    if rows < 1 or cols < 1 then return "" end

    -- Fit the art into the pane. Two modes:
    --   contain (default): scale DOWN preserving aspect, centered, letterboxed.
    --     Right for pictures (Ruby, CRT) where the shape must be preserved.
    --   fill: stretch each axis independently to the FULL pane (rows x cols),
    --     edge to edge, no letterbox. Right for textures like the braille wall
    --     where there's no "correct" shape to keep -- it fills the whole screen.
    -- Never scales a source axis beyond the pane in either mode.
    local draw_h, draw_w
    if cfg_fit == "fill" then
        draw_h = rows
        draw_w = cols
    else
        draw_h = art_h
        draw_w = art_w
        if draw_h > rows then draw_h = rows end
        if draw_w > cols then draw_w = cols end
        -- preserve aspect-ish: if one axis must shrink, shrink the other in step
        -- so the face doesn't get grotesquely squished. Use the tighter ratio.
        local sh = draw_h / art_h
        local sw = draw_w / art_w
        local s  = (sh < sw) and sh or sw
        draw_h = math.max(1, math.floor(art_h * s + 0.5))
        draw_w = math.max(1, math.floor(art_w * s + 0.5))
        if draw_h > rows then draw_h = rows end
        if draw_w > cols then draw_w = cols end
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
        local dx = (draw_w - ocx) * 0.5
        local dy = (draw_h - ocy)
        max_d = dist(dx, dy)
        if max_d <= 0 then max_d = 1 end
    end

    local left_pad = math.floor((cols - draw_w) / 2)
    local top_pad  = math.floor((rows - draw_h) / 2)
    local pad_str  = string.rep(" ", left_pad)

    local out = {}
    for _ = 1, top_pad do out[#out + 1] = "" end

    for oy = 1, draw_h do
        -- map output row -> source row (nearest neighbor)
        local sy = math.floor((oy - 0.5) / draw_h * art_h) + 1
        if sy < 1 then sy = 1 elseif sy > art_h then sy = art_h end
        local srow = art_cells[sy]

        local parts = { pad_str }
        local last_color = nil
        for ox = 1, draw_w do
            local sx = math.floor((ox - 0.5) / draw_w * art_w) + 1
            if sx < 1 then sx = 1 elseif sx > art_w then sx = art_w end
            local ch = srow[sx] or " "

            if cfg_color_mode == "passthrough" then
                parts[#parts + 1] = ch
            else
                -- ring/band for this output cell
                local dx = math.abs(ox - ocx) * 0.5
                local dy = math.abs(oy - ocy)
                local d  = dist(dx, dy)

                -- Continuous ring position in [0,9]. With blend ON we interpolate
                -- the level between the two bands the cell sits between, so ring
                -- boundaries dissolve into a smooth gradient. With blend OFF we
                -- snap to the nearest band (hard concentric steps).
                local pos = d / max_d * 9
                if pos < 0 then pos = 0 elseif pos > 9 then pos = 9 end
                local lvl
                if cfg_ring_blend then
                    local lo = math.floor(pos)
                    if lo > 8 then lo = 8 end          -- keep lo+1 (Lua lo+2) <= 10
                    local frac = pos - lo
                    local a = effective[lo + 1]
                    local b = effective[lo + 2]
                    lvl = a + (b - a) * frac
                else
                    local band = 1 + math.floor(pos + 0.5)
                    if band < 1 then band = 1 elseif band > 10 then band = 10 end
                    lvl = effective[band]
                end

                local color
                if cfg_color_mode == "mono" then
                    color = cfg_mono_color
                    if lvl < 0.12 and ch ~= " " then color = 236 end
                else
                    color = glow_color(lvl, lvl >= cfg_overdrive)
                end
                if color ~= last_color then
                    parts[#parts + 1] = fg256(color)
                    last_color = color
                end
                parts[#parts + 1] = ch
            end
        end
        if cfg_color_mode ~= "passthrough" then
            parts[#parts + 1] = reset()
        end
        out[#out + 1] = table.concat(parts)
    end

    for _ = #out + 1, rows do out[#out + 1] = "" end

    return table.concat(out, "\n")
end
