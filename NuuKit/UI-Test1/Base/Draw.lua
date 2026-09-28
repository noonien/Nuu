local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI1 = Kit.UI1 or {}
local UI = Kit.UI1

-- What widgets draw with: plates, 9-slices, tiles and glyphs. Each is a small
-- table with shared methods (a metatable), made once when its widget is
-- built. The same calls as UI/Base/UI.lua.

-- Plates: the box behind a widget ---------------------------------------------------

-- A fill and a one-pixel edge, or a 9-slice texture, whichever the theme has.
-- `plate:Flat(fill, edge, edgeAlpha)` draws colours (nil draws nothing
-- there); `plate:Art(spec, corner, tint)` draws the texture and answers
-- whether it loaded.
local Plate = {}
Plate.__index = Plate
local SIDES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

function UI.NewPlate(frame, layer, sublevel)
    layer = layer or "BACKGROUND"
    -- Textures start shown, so the flat parts are counted as shown.
    local plate = setmetatable({ frame = frame, layer = layer, sublevel = sublevel, edges = {}, flatShown = true }, Plate)
    plate.fill = frame:CreateTexture(nil, layer, nil, sublevel or 0)
    plate.fill:SetAllPoints(frame)
    for _, side in ipairs(SIDES) do
        local edge = frame:CreateTexture(nil, layer, nil, (sublevel or 0) + 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, 0)
            UI.Hairline(edge, "height")
        else
            edge:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
            UI.Hairline(edge, "width")
        end
        plate.edges[side] = edge
    end
    return plate
end

-- Shows or hides the flat parts only when that changes.
local function showFlat(plate, shown)
    if plate.flatShown == shown then return end
    plate.flatShown = shown
    plate.fill:SetShown(shown)
    for _, side in ipairs(SIDES) do plate.edges[side]:SetShown(shown) end
end

function Plate:Flat(fill, edge, edgeAlpha)
    if self.nine and self.nineShown then
        self.nine:Hide()
        self.nineShown = false
    end
    showFlat(self, true)
    UI.TexColor(self.fill, fill)
    for _, side in ipairs(SIDES) do UI.TexColor(self.edges[side], edge, edgeAlpha) end
end

-- `corner` is how big the corners are drawn; `tint` shades the texture.
function Plate:Art(spec, corner, tint)
    if not spec then return false end
    if not self.nine or self.nineSpec ~= spec then
        if self.nine then self.nine:Hide() end
        self.nine = UI.NineSlice(self.frame, self.layer, spec, corner or 6, true, self.sublevel)
        self.nineSpec = spec
        self.nineShown = false
    end
    if not self.nine.loaded then return false end
    showFlat(self, false)
    if not self.nineShown then
        self.nine:Show()
        self.nineShown = true
    end
    self.nine:SetTint(tint)
    return true
end

function Plate:Hide()
    showFlat(self, false)
    if self.nine then
        self.nine:Hide()
        self.nineShown = false
    end
end

-- 9-slices --------------------------------------------------------------------------

-- Eight pieces and an optional centre cut from one texture with SetTexCoord,
-- so corners keep their size and the edges stretch. `spec` is { file,
-- corner, size, width }: `corner` source pixels of a `width` x `size`
-- texture. `display` is how big a corner is drawn.
local Nine = {}
Nine.__index = Nine

function Nine:Show() for _, texture in ipairs(self.pieces) do texture:Show() end end
function Nine:Hide() for _, texture in ipairs(self.pieces) do texture:Hide() end end
function Nine:SetTint(color)
    if color == self.tint then return end
    self.tint = color
    for _, texture in ipairs(self.pieces) do UI.VertexColor(texture, color) end
end

local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }

function UI.NineSlice(frame, layer, spec, display, center, sublevel)
    local nine = setmetatable({ pieces = {}, loaded = false }, Nine)
    local path = UI.MediaPath(spec.file)
    local width, height = spec.width or spec.size, spec.size
    local u, v = spec.corner / width, spec.corner / height
    local d = display
    local coords = {
        { 0, u, 0, v }, { 1 - u, 1, 0, v }, { 0, u, 1 - v, 1 }, { 1 - u, 1, 1 - v, 1 },
    }
    local function piece()
        local texture = frame:CreateTexture(nil, layer or "BORDER", nil, sublevel or 0)
        table.insert(nine.pieces, texture)
        return texture
    end
    local first = piece()
    nine.loaded = UI.LoadTexture(first, path)
    if not nine.loaded then
        first:Hide()
        nine.pieces = {}
        return nine
    end
    for index, corner in ipairs(CORNERS) do
        local texture = index == 1 and first or piece()
        if index > 1 then texture:SetTexture(path) end
        texture:SetSize(d, d)
        texture:SetPoint(corner, frame, corner, 0, 0)
        local c = coords[index]
        texture:SetTexCoord(c[1], c[2], c[3], c[4])
    end
    local function edge(a, ax, ay, b, bx, by, l, r, t, bottom, w, h)
        local texture = piece()
        texture:SetTexture(path)
        texture:SetPoint(a, frame, a, ax, ay)
        texture:SetPoint(b, frame, b, bx, by)
        if w then texture:SetWidth(w) end
        if h then texture:SetHeight(h) end
        texture:SetTexCoord(l, r, t, bottom)
    end
    edge("TOPLEFT", d, 0, "TOPRIGHT", -d, 0, u, 1 - u, 0, v, nil, d)
    edge("BOTTOMLEFT", d, 0, "BOTTOMRIGHT", -d, 0, u, 1 - u, 1 - v, 1, nil, d)
    edge("TOPLEFT", 0, -d, "BOTTOMLEFT", 0, d, 0, u, v, 1 - v, d, nil)
    edge("TOPRIGHT", 0, -d, "BOTTOMRIGHT", 0, d, 1 - u, 1, v, 1 - v, d, nil)
    if center then
        local texture = piece()
        texture:SetTexture(path)
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", d, -d)
        texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -d, d)
        texture:SetTexCoord(u, 1 - u, v, 1 - v)
    end
    return nine
end

-- A texture tiled both ways over its area; false when the file or tiling is
-- not there.
function UI.Tile(texture, name)
    if not UI.LoadTexture(texture, UI.MediaPath(name), "REPEAT", "REPEAT") then return false end
    if texture.SetHorizTile then pcall(texture.SetHorizTile, texture, true) end
    if texture.SetVertTile then pcall(texture.SetVertTile, texture, true) end
    return true
end

-- Glyphs: small marks drawn from lines ------------------------------------------------

-- Drawn with Line objects where the client has them, so they take any colour
-- and size; an ASCII character where it does not.
local GLYPHS = {
    close = { { -1, 1, 1, -1 }, { -1, -1, 1, 1 } },
    next = { { -0.35, 0.8, 0.45, 0 }, { 0.45, 0, -0.35, -0.8 } },
    back = { { 0.35, 0.8, -0.45, 0 }, { -0.45, 0, 0.35, -0.8 } },
    down = { { -0.8, 0.35, 0, -0.45 }, { 0, -0.45, 0.8, 0.35 } },
    up = { { -0.8, -0.35, 0, 0.45 }, { 0, 0.45, 0.8, -0.35 } },
    menu = { { -0.9, 0.65, 0.9, 0.65 }, { -0.9, 0, 0.9, 0 }, { -0.9, -0.65, 0.9, -0.65 } },
    plus = { { -0.8, 0, 0.8, 0 }, { 0, 0.8, 0, -0.8 } },
    minus = { { -0.8, 0, 0.8, 0 } },
    check = { { -0.8, 0.05, -0.25, -0.55 }, { -0.25, -0.55, 0.85, 0.7 } },
    grip = { { 1, -0.1, 0.1, -1 }, { 1, 0.5, -0.5, -1 } },
    search = { { 0.25, -0.25, 0.9, -0.9 } },
}
local GLYPH_TEXT = { close = "x", next = ">", back = "<", down = "v", up = "^", menu = "=", plus = "+", minus = "-", check = "x", grip = "", search = "o" }

local Glyph = {}
Glyph.__index = Glyph

-- `size` is the box the glyph fills; `thickness` its stroke.
function UI.NewGlyph(frame, kind, size, thickness)
    local glyph = setmetatable({ frame = frame, lines = {}, kind = kind, dx = 0, dy = 0 }, Glyph)
    local half = (size or 10) / 2
    if frame.CreateLine and GLYPHS[kind] then
        local segments = {}
        for _, spec in ipairs(GLYPHS[kind]) do
            table.insert(segments, { spec[1] * half, spec[2] * half, spec[3] * half, spec[4] * half })
        end
        if kind == "search" then
            -- A ring for the lens, from short lines.
            local r, cx, cy = half * 0.55, -half * 0.2, half * 0.2
            for step = 0, 11 do
                local a1, a2 = step * math.pi / 6, (step + 1) * math.pi / 6
                table.insert(segments, { cx + math.cos(a1) * r, cy + math.sin(a1) * r, cx + math.cos(a2) * r, cy + math.sin(a2) * r })
            end
        end
        for _, segment in ipairs(segments) do
            local line = frame:CreateLine(nil, "OVERLAY")
            line:SetThickness(thickness or 1.5)
            line.kitSegment = segment
            table.insert(glyph.lines, line)
        end
    else
        glyph.text = UI.NewText(frame)
        glyph.text:SetJustifyH("CENTER")
        glyph.text:SetText(GLYPH_TEXT[kind] or "")
    end
    glyph:Place()
    return glyph
end

function Glyph:Place()
    local frame = self.frame
    for _, line in ipairs(self.lines) do
        local s = line.kitSegment
        line:SetStartPoint("CENTER", frame, s[1] + self.dx, s[2] + self.dy)
        line:SetEndPoint("CENTER", frame, s[3] + self.dx, s[4] + self.dy)
    end
    if self.text then
        self.text:ClearAllPoints()
        self.text:SetPoint("CENTER", frame, "CENTER", self.dx, self.dy)
    end
end

function Glyph:SetColor(color, alphaScale)
    for _, line in ipairs(self.lines) do UI.TexColor(line, color, alphaScale) end
    if self.text then UI.TextColor(self.text, color, alphaScale) end
end

function Glyph:SetShown(shown)
    for _, line in ipairs(self.lines) do line:SetShown(shown) end
    if self.text then self.text:SetShown(shown) end
end

-- Moves the glyph off the frame's centre: the press nudge, or a glyph that
-- sits at one side of its frame.
function Glyph:Offset(dx, dy)
    if dx == self.dx and dy == self.dy then return end
    self.dx, self.dy = dx, dy
    self:Place()
end

function Glyph:Nudge(dx, dy) self:Offset(self.dx + dx, self.dy + dy) end
