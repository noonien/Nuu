local addonName, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- The themes a look can name. Colours are "#rrggbb"; `surfaceA` and
-- `raisedA` are how much of the world shows through an in-play panel.
-- `accent` is the theme's own accent, used while the look names none.
--
-- An art theme adds `art`: texture names under the kit's Media folder, each
-- optional. A texture that is missing or will not load is drawn flat from
-- the colours instead, so a theme can grow its art a piece at a time.
--
--   background    tiles both ways under a window
--   frame         { file, corner, size }: a 9-slice edge, `corner` source
--                 pixels of `size`, the centre left clear
--   band          the header strip, tiled across
--   plate         { file, corner, size }: 9-slice button, field and box plate
--   platePrimary  the same for the call to action
UI.themes = UI.themes or {}
UI.themeOrder = UI.themeOrder or {}

-- Where the kit's textures are. In development the kit is the NuuKit addon;
-- an embedded copy is loaded by its host, so the host's folder is used and
-- `Kit.folder` says where inside it the kit sits (with a trailing "\\").
function UI.MediaPath(name)
    local root = Kit.mediaRoot or ("Interface\\AddOns\\" .. addonName .. "\\" .. (Kit.folder or "") .. "Media\\")
    return root .. name
end

-- Adds a theme, or replaces one with the same key. The order themes were
-- added in is the order the look picker shows them.
-- A texture named alone takes the kit's usual sizes: a frame's corner is 30
-- of 128 pixels, a plate's 12 of a 128 x 64 texture.
local function normalizeArt(art)
    if type(art) ~= "table" then return art end
    local function slice(value, corner, size, width)
        if type(value) == "string" then value = { file = value } end
        if type(value) ~= "table" then return value end
        value.corner = value.corner or corner
        value.size = value.size or size
        value.width = value.width or width
        return value
    end
    art.frame = slice(art.frame, 30, 128, 128)
    art.plate = slice(art.plate, 12, 64, 128)
    art.platePrimary = slice(art.platePrimary, 12, 64, 128)
    return art
end

function UI.AddTheme(key, def)
    assert(type(key) == "string" and type(def) == "table", "AddTheme(key, def)")
    def.art = normalizeArt(def.art)
    if not UI.themes[key] then table.insert(UI.themeOrder, key) end
    def.key = key
    def.name = def.name or key
    UI.themes[key] = def
    return def
end

UI.AddTheme("midnight", {
    name = "Midnight", desc = "Cool near-black glass. OpenRoad's look.",
    window = "#090b0e", band = "#0e1116", hairline = "#1c222b",
    surface = "#0b0e12", surfaceA = 0.72, raised = "#13171d", raisedA = 0.78,
    border = "#2e3847", text = "#ebf0f7", muted = "#8f9eb3", accent = "#4dc9f0",
})

UI.AddTheme("slate", {
    name = "Slate", desc = "Softer grey, lower contrast for long sessions.",
    window = "#16191e", band = "#1c2026", hairline = "#2b313a",
    surface = "#1a1e24", surfaceA = 0.8, raised = "#252a32", raisedA = 0.85,
    border = "#3f4754", text = "#e4e7ec", muted = "#9ba4b1", accent = "#4dc9f0",
})

UI.AddTheme("obsidian", {
    name = "Obsidian", desc = "High contrast: black plates, white text.",
    window = "#000000", band = "#060708", hairline = "#2a2f36",
    surface = "#000000", surfaceA = 0.85, raised = "#0d0f12", raisedA = 0.9,
    border = "#58616e", text = "#ffffff", muted = "#bcc5d1", accent = "#4dc9f0",
})

UI.AddTheme("horde", {
    name = "Horde", desc = "Dark leather and iron, an oxblood accent.",
    window = "#15110f", band = "#1b1613", hairline = "#3d2f26",
    surface = "#1f1916", surfaceA = 0.9, raised = "#2a211c", raisedA = 0.92,
    border = "#5a4636", text = "#e6ddd2", muted = "#ad9e8f", accent = "#e8705a",
    art = {
        background = "horde\\bg",
        frame = { file = "horde\\frame", corner = 30, size = 128 },
        band = "horde\\band",
        plate = { file = "horde\\plate", corner = 12, size = 64, width = 128 },
        platePrimary = { file = "horde\\plate_primary", corner = 12, size = 64, width = 128 },
    },
})

UI.AddTheme("alliance", {
    name = "Alliance", desc = "Blue slate and steel, gold trim.",
    window = "#0f141d", band = "#131a25", hairline = "#2e3a4f",
    surface = "#161e2b", surfaceA = 0.9, raised = "#1f2938", raisedA = 0.92,
    border = "#3c4a63", text = "#e1e6ef", muted = "#a0adc2", accent = "#7aa6ec",
    art = {
        background = "alliance\\bg",
        frame = { file = "alliance\\frame", corner = 30, size = 128 },
        band = "alliance\\band",
        plate = { file = "alliance\\plate", corner = 12, size = 64, width = 128 },
        platePrimary = { file = "alliance\\plate_primary", corner = 12, size = 64, width = 128 },
    },
})

-- The accents the look picker offers, beside the theme's own and the
-- player's class colour.
UI.accents = {
    { key = "cyan", name = "Cyan", hex = "#4dc9f0" },
    { key = "azure", name = "Azure", hex = "#6f9dff" },
    { key = "violet", name = "Violet", hex = "#b08cff" },
    { key = "gold", name = "Gold", hex = "#e8c35a" },
    { key = "rose", name = "Rose", hex = "#f27fa2" },
    { key = "ember", name = "Ember", hex = "#ff8a4c" },
}

-- Status colours never follow the accent.
UI.status = { danger = "#e66157", done = "#73cc80", warning = "#f2bf4d", gain = "#66d1c7", estimate = "#cca8fa", pattern = "#fa85c7" }
