local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Colours, looks and tokens. Nothing here touches a frame, so all of it runs
-- (and is tested) outside the client.
--
-- A colour is { r, g, b, a } with each part in 0..1. A look is what an addon
-- keeps: { theme, accent, opacity, textSize, reduceMotion }. Tokens are what
-- widgets paint with, made from a look by UI.Tokens.

-- Colours --------------------------------------------------------------------

-- "#rrggbb", "rrggbb" or a colour table -> a new colour table; nil when it
-- cannot be read.
function UI.Color(value, alpha)
    if type(value) == "table" then
        return { value[1] or 0, value[2] or 0, value[3] or 0, alpha or value[4] or 1 }
    end
    if type(value) ~= "string" then return nil end
    local hex = value:gsub("^#", "")
    if not hex:match("^%x%x%x%x%x%x$") then return nil end
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        alpha or 1,
    }
end

-- `amount` of the way from `a` to `b`. The alpha is `a`'s.
function UI.Mix(a, b, amount)
    return {
        a[1] + (b[1] - a[1]) * amount,
        a[2] + (b[2] - a[2]) * amount,
        a[3] + (b[3] - a[3]) * amount,
        a[4] or 1,
    }
end

function UI.Alpha(color, alpha)
    return { color[1], color[2], color[3], alpha }
end

-- "|cffrrggbb", for colouring part of a line of text.
function UI.ColorCode(color)
    local function part(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", part(color[1]), part(color[2]), part(color[3]))
end

-- Looks ----------------------------------------------------------------------

UI.defaultLook = { theme = "midnight", opacity = 1, textSize = "normal", reduceMotion = false }

UI.textSizes = { small = 0.9, normal = 1, large = 1.15 }

-- A full look from whatever the addon kept: unknown themes and sizes fall
-- back to the defaults, opacity is held to 0.4..1. Always a new table, so
-- the kit never writes into the addon's.
function UI.ResolveLook(look)
    look = type(look) == "table" and look or {}
    local resolved = {}
    for key, value in pairs(UI.defaultLook) do resolved[key] = value end
    for key, value in pairs(look) do resolved[key] = value end
    if not UI.themes[resolved.theme] then resolved.theme = UI.defaultLook.theme end
    if not UI.textSizes[resolved.textSize] then resolved.textSize = UI.defaultLook.textSize end
    local opacity = tonumber(resolved.opacity) or 1
    resolved.opacity = math.max(0.4, math.min(1, opacity))
    resolved.reduceMotion = resolved.reduceMotion == true
    return resolved
end

-- The player's class colour, or nil outside the client.
function UI.ClassColor()
    if type(UnitClass) ~= "function" or type(RAID_CLASS_COLORS) ~= "table" then return nil end
    local ok, _, file = pcall(UnitClass, "player")
    local color = ok and file and RAID_CLASS_COLORS[file]
    if not color or not color.r then return nil end
    return { color.r, color.g, color.b, 1 }
end

-- The accent a look asks for: its own colour, "class" for the class colour,
-- else the theme's.
local function accentOf(look, theme)
    if look.accent == "class" then
        local class = UI.ClassColor()
        if class then return class end
    end
    return UI.Color(look.accent) or UI.Color(theme.accent) or UI.Color("#4dc9f0")
end

-- Tokens -----------------------------------------------------------------------

-- Every colour a widget paints with, for one look. The planes come opaque
-- (window, band, surface, raised) and as the look's backgrounds (windowBg,
-- bandBg, surfaceBg, raisedBg, with the opacity applied). The accent comes
-- as given (accentRaw, and opaque as accent), as a button fill and its
-- hover, as a wash for selected rows, and as 65% and 80% edges. Every theme
-- is dark: pale text with a hard shadow on dark planes.
function UI.Tokens(look)
    look = UI.ResolveLook(look)
    local theme = UI.themes[look.theme]
    local o = look.opacity
    local c = function(key) return UI.Color(theme[key]) end
    local t = {
        look = look, theme = theme, art = theme.art,
        window = c("window"), band = c("band"), hairline = c("hairline"),
        surface = c("surface"), raised = c("raised"), border = c("border"),
        text = c("text"), muted = c("muted"),
    }
    t.windowBg = UI.Alpha(t.window, 0.97 * o)
    t.bandBg = UI.Alpha(t.band, o)
    t.surfaceBg = UI.Alpha(t.surface, (theme.surfaceA or 0.8) * o)
    t.raisedBg = UI.Alpha(t.raised, (theme.raisedA or 0.85) * o)
    t.border50 = UI.Alpha(t.border, 0.5)
    t.muted45 = UI.Alpha(t.muted, 0.45)

    local accent = accentOf(look, theme)
    t.accentRaw = accent
    t.accent = UI.Alpha(accent, 1)
    t.accentFill = UI.Mix(accent, t.window, 0.68)
    t.accentHover = UI.Mix(accent, t.window, 0.52)
    t.onFill = UI.Alpha(t.text, 1)
    t.accentWash = UI.Alpha(accent, 0.16)
    t.accent65 = UI.Alpha(t.accent, 0.65)
    t.accent80 = UI.Alpha(t.accent, 0.8)

    for key, hex in pairs(UI.status) do t[key] = UI.Color(hex) end
    t.quest = UI.Color("#ffd100")
    t.coinG = UI.Color(UI.coins.g)
    t.coinS = UI.Color(UI.coins.s)
    t.coinC = UI.Color(UI.coins.c)
    -- A recipe's or a quest's difficulty, flattened so a name reads as a hint
    -- of its colour rather than shouting.
    t.difficulty = { red = UI.Color("#d0655c"), orange = UI.Color("#cc855c"), yellow = UI.Color("#ccb861"),
        green = UI.Color("#70a870"), grey = t.muted }
    t.textScale = UI.textSizes[look.textSize]
    t.reduceMotion = look.reduceMotion
    return t
end

-- A token by name ("muted", "danger") or a colour ("#rrggbb", a table).
function UI.TokenColor(t, value)
    if value == nil then return nil end
    if type(value) == "string" and t[value] and type(t[value]) == "table" and t[value][1] then return t[value] end
    return UI.Color(value)
end

-- Buttons ------------------------------------------------------------------------

UI.tones = {
    accent = "accentRaw", success = "done", danger = "danger", warning = "warning",
    quest = "quest", estimate = "estimate", gain = "gain",
}

-- The base colour of a tone: a name above, or any colour. nil is neutral.
function UI.ToneColor(t, tone)
    if tone == nil or tone == "neutral" then return nil end
    local key = UI.tones[tone]
    if key then return t[key] end
    return UI.Color(tone)
end

-- The colours of a button for its tone, style and state. `state` is one of
-- "rest", "hover", "active", "disabled". Returns fill, edge, text; a nil
-- fill or edge draws nothing there.
--
-- Styles: "solid" (the call to action: filled, for any tone), "soft" (a
-- wash of the tone), "outline", "ghost" (the caption alone), and "plate",
-- the neutral button every window is full of.
function UI.ButtonColors(t, tone, style, state)
    local base = UI.ToneColor(t, tone)
    if tone == "accent" then base = t.accentRaw end
    if state == "disabled" then
        if base and style ~= "plate" then
            return t.surface, UI.Alpha(base, 0.3), UI.Alpha(base, 0.4)
        end
        return t.surface, t.border50, t.muted45
    end

    if not base then
        style = style or "plate"
        if style == "soft" then
            return UI.Alpha(t.muted, state == "hover" and 0.22 or 0.14), UI.Alpha(t.muted, 0.35), t.text
        elseif style == "outline" then
            return state == "hover" and UI.Alpha(t.muted, 0.12) or nil, state == "hover" and t.accent65 or t.border, t.text
        elseif style == "ghost" then
            return state == "hover" and UI.Alpha(t.muted, 0.12) or nil, nil, t.text
        elseif style == "solid" then
            return state == "hover" and t.accentHover or t.raised, t.border, t.text
        end
        if state == "active" then return t.raised, t.accent80, t.accent end
        if state == "hover" then return t.raised, t.accent65, t.text end
        -- A caption is read, so it is never muted; hover and the active one
        -- of a group show in the edge and the accent instead.
        return t.surface, t.border, t.text
    end

    local ink = UI.Alpha(base, 1)
    style = style or "solid"
    if style == "solid" or style == "plate" then
        return UI.Mix(base, t.window, state == "hover" and 0.52 or 0.68), ink, t.onFill
    elseif style == "soft" then
        return UI.Alpha(base, state == "hover" and 0.24 or 0.14), UI.Alpha(ink, 0.45), ink
    elseif style == "outline" then
        return state == "hover" and UI.Alpha(base, 0.12) or nil, ink, ink
    end
    return state == "hover" and UI.Alpha(base, 0.12) or nil, nil, ink
end

-- Text ---------------------------------------------------------------------------

-- Sizes are game pixels at the "normal" text size. `face` is "text" (the
-- game's own font) or "number" (the narrow face the game uses for numbers).
-- Game fonts come in one weight, so a style is its size and its colour.
UI.textStyles = {
    title = { size = 18, color = "text" },
    window = { size = 15, color = "text" },
    heading = { size = 13, color = "text" },
    body = { size = 11, color = "text" },
    label = { size = 11, color = "muted" },
    link = { size = 11, color = "accent" },
    fine = { size = 10, color = "muted" },
    number = { size = 12, color = "text", face = "number" },
    figure = { size = 17, color = "text", face = "number" },
    key = { size = 9, color = "muted", face = "number" },
}

-- Money --------------------------------------------------------------------------

-- Money as the player reads it: the two largest coins, rounded to the
-- second, with a zero coin left out. 12005 -> "1g 20s", 20013 -> "2g",
-- 150 -> "1s 50c", 0 -> "0c"; a negative amount keeps its sign. `exact`
-- keeps every coin (12005 -> "1g 20s 5c"), for a field the player edits.
-- Each coin's letter is always coloured the way the game does, gold, silver
-- and copper; `plain` false leaves them uncoloured, only for text the
-- player is typing into. (A tokens table there is taken as coloured, as
-- the kit's callers once passed one.)
UI.coins = { g = "#ffd100", s = "#c7c7cf", c = "#eda55f" }
local COIN = { g = UI.Color(UI.coins.g), s = UI.Color(UI.coins.s), c = UI.Color(UI.coins.c) }

-- How to write money, for a field that refused what was typed; the example
-- in coin colours like any other amount.
function Kit.MoneyHint()
    return "Write it like " .. Kit.FormatMoney(12005, true) .. ", or a number of copper."
end

function Kit.FormatMoney(copper, exact, plain)
    copper = tonumber(copper)
    if not copper then return "?" end
    local sign = ""
    if copper < 0 then sign, copper = "-", -copper end
    copper = math.floor(copper + 0.5)
    if not exact and copper >= 10000 then copper = math.floor(copper / 100 + 0.5) * 100 end
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local colored = plain ~= false
    local function coin(amount, letter)
        if colored then return amount .. UI.ColorCode(COIN[letter]) .. letter .. "|r" end
        return amount .. letter
    end
    local parts = {}
    if gold > 0 then table.insert(parts, coin(gold, "g")) end
    if silver > 0 then table.insert(parts, coin(silver, "s")) end
    if rest > 0 then table.insert(parts, coin(rest, "c")) end
    if #parts == 0 then return sign .. coin(0, "c") end
    return sign .. table.concat(parts, " ")
end

-- "1g 20s 5c", "1g20s", "20s", "5c" or a bare number of copper -> copper. nil
-- for anything else, so a typo is refused rather than read as zero.
function Kit.ParseMoney(text)
    if type(text) == "number" then return text >= 0 and math.floor(text) or nil end
    if type(text) ~= "string" then return nil end
    -- Coloured coins read the same as plain ones.
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if text == "" then return nil end
    if text:match("^%d+$") then return tonumber(text) end
    local total, seen = 0, {}
    local rest = text:gsub("(%d+)%s*([gsc])", function(amount, unit)
        if seen[unit] then total = nil end
        seen[unit] = true
        if total then total = total + tonumber(amount) * (unit == "g" and 10000 or unit == "s" and 100 or 1) end
        return ""
    end)
    if not total or rest:match("%S") or next(seen) == nil then return nil end
    return total
end

-- Key hints ------------------------------------------------------------------------

-- "SHIFT-BUTTON4" is too long for the corner of a slot, so a key hint is cut
-- to its modifiers' initials and a short name: "sM4".
local keyWords = { SHIFT = "s", CTRL = "c", ALT = "a" }

function UI.ShortKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    local text = key:upper():gsub("BUTTON", "M"):gsub("NUMPAD", "N"):gsub("MOUSEWHEEL", "W")
    local parts = {}
    for piece in string.gmatch(text, "[^-]+") do table.insert(parts, piece) end
    local last = table.remove(parts) or ""
    local prefix = ""
    for _, piece in ipairs(parts) do prefix = prefix .. (keyWords[piece] or string.lower(string.sub(piece, 1, 1))) end
    if string.len(last) > 3 then last = string.sub(last, 1, 3) end
    return prefix .. last
end
