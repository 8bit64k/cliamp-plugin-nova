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
local cfg_bob_dir    = clean(p:config("bob_direction")) or "both"
local cfg_color_mode = clean(p:config("color_mode")) or "glow"
local cfg_mono_color = tonumber(clean(p:config("mono_color"))) or 11
local cfg_attack     = tonumber(clean(p:config("attack"))) or 0.55
local cfg_release    = tonumber(clean(p:config("release"))) or 0.18
local cfg_overdrive  = tonumber(clean(p:config("overdrive"))) or 0.78
local cfg_tilt       = tonumber(clean(p:config("tilt"))) or 0.0
local cfg_theme_name = clean(p:config("theme")) or "amber"

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
}

-- Resolve active preset (fall back to amber on unknown name).
local active_preset = PRESETS[cfg_theme_name] or PRESETS["amber"]
local glow_ramp      = active_preset.glow
local overdrive_ramp = active_preset.overdrive

local function glow_color(level, hot)
    local ramp = hot and overdrive_ramp or glow_ramp
    local idx = math.floor(level * (#ramp - 1)) + 1
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

local smoothed = {0,0,0,0,0,0,0,0,0,0}

function p:init(rows, cols)
    for i = 1, 10 do smoothed[i] = 0 end
    load_art()
    -- Diagnostic: log the resolved config so we can see what theme is active.
    cliamp.log.info("theme=" .. cfg_theme_name .. " preset=" .. (active_preset.name or "?"))
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

    -- Fit the art into the pane. Scale DOWN to fit (never up — keeps the art
    -- crisp at its native size and centered when the pane is larger). Each
    -- output cell maps to a source cell via nearest-neighbor, so this works at
    -- any pane size from cliamp's default 5 rows up to fullscreen.
    local draw_h = art_h
    local draw_w = art_w
    if draw_h > rows then draw_h = rows end
    if draw_w > cols then draw_w = cols end
    -- preserve aspect-ish: if one axis must shrink, shrink the other in step so
    -- the face doesn't get grotesquely squished. Use the tighter ratio.
    local sh = draw_h / art_h
    local sw = draw_w / art_w
    local s  = (sh < sw) and sh or sw
    draw_h = math.max(1, math.floor(art_h * s + 0.5))
    draw_w = math.max(1, math.floor(art_w * s + 0.5))
    if draw_h > rows then draw_h = rows end
    if draw_w > cols then draw_w = cols end

    -- Ring geometry computed on the OUTPUT grid (resolution-independent).
    -- Square rings via Chebyshev distance from center, x scaled 0.5 for the
    -- ~2:1 terminal cell aspect ratio. Band 1 (bass) = center, 10 = edge.
    local ocx = (draw_w + 1) / 2
    local ocy = (draw_h + 1) / 2
    local max_d = 0
    do
        local dx = (draw_w - ocx) * 0.5
        local dy = (draw_h - ocy)
        max_d = ((dx > dy) and dx or dy)
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
                local d  = (dx > dy) and dx or dy
                local band = 1 + math.floor(d / max_d * 9 + 0.5)
                if band < 1 then band = 1 elseif band > 10 then band = 10 end

                local lvl = smoothed[band]
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
    -- Debug indicator: show theme on bottom-right (remove when verified)
    if rows > 0 then
        local indicator = cfg_theme_name .. " (" .. (active_preset.name or "?") .. ")"
        local pad = cols - #indicator - 1
        if pad < 0 then pad = 0 end
        out[rows] = string.rep(" ", pad) .. fg256(240) .. indicator .. reset()
    end

    return table.concat(out, "\n")
end
