local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- One UI per addon: `ns.UI = ns.Kit.NewUI(ns, look)`. It holds the addon's
-- look, the tokens made from it, and every widget it made, so a new look
-- repaints them all. Two addons sharing one kit in development still get
-- their own UI each, and can wear different looks.
--
-- Widgets are made two ways, the same constructor behind both:
--   UI:Button(parent, "Save", opts)  -- placed by the caller
--   column:Button("Save", opts)      -- made in the column and stacked
-- `UI.Define` registers a constructor under both.

local Proto = UI.Proto or {}
UI.Proto = Proto
local Container = UI.Container or {}
UI.Container = Container

-- Constructors that fill a window, pane or page when made straight on one.
UI.fills = UI.fills or {}

function Kit.NewUI(owner, look)
    local ui = setmetatable({
        owner = owner,
        painters = setmetatable({}, { __mode = "k" }),
        listeners = {},
    }, { __index = Proto })
    ui.look = UI.ResolveLook(look)
    ui.tokens = UI.Tokens(ui.look)
    return ui
end

-- `fn(ui, parent, ...)` makes the widget and returns it.
function UI.Define(name, fn, fills)
    Proto[name] = fn
    if fills then UI.fills[name] = true end
    Container[name] = function(self, ...)
        local inner = self.kitInner or self
        local widget = fn(self.ui, inner, ...)
        if self.kitFillChildren and UI.fills[name] and widget.kitLayout and widget.kitLayout.grow == nil then
            widget.kitLayout.grow = true
        end
        inner:KitAppend(widget)
        return widget
    end
end

-- The look -------------------------------------------------------------------

-- Repaints every widget this UI made, open windows included. The addon keeps
-- `look`; the kit keeps its own copy.
function Proto:SetLook(look)
    self.look = UI.ResolveLook(look)
    self.tokens = UI.Tokens(self.look)
    self:RepaintAll()
    for _, fn in ipairs(self.listeners) do pcall(fn, self.look) end
end

function Proto:GetLook()
    local copy = {}
    for key, value in pairs(self.look) do copy[key] = value end
    return copy
end

-- `fn(tokens)` paints `object` now and again after every look change. For
-- widgets the kit does this itself; an addon uses it for what it draws.
function Proto:Paint(object, fn)
    self.painters[object] = fn
    fn(self.tokens)
    return object
end

function Proto:Unpaint(object)
    self.painters[object] = nil
end

-- Told of every look change, after the repaint.
function Proto:OnLook(fn)
    table.insert(self.listeners, fn)
end

function Proto:RepaintAll()
    local list = {}
    for object, fn in pairs(self.painters) do list[#list + 1] = { object, fn } end
    for _, pair in ipairs(list) do pair[2](self.tokens) end
end

-- A widget's options as layout options, without `keys`: the ones the widget
-- reads as the size of a part of itself (a TextArea's `height` is its box's),
-- which as layout options would pin the whole widget to that size.
function UI.LayoutOptions(opts, ...)
    local copy = {}
    for key, value in pairs(opts or {}) do copy[key] = value end
    for index = 1, select("#", ...) do copy[select(index, ...)] = nil end
    return copy
end

-- What every widget gets: its UI, its layout options, a repaint, a tooltip
-- and a right-click hook. `paint(widget, tokens)` sets every colour.
function Proto:Finish(widget, opts, paint)
    opts = opts or {}
    widget.ui = self
    widget.kitLayout = widget.kitLayout or opts
    if paint then
        self.painters[widget] = function(t) paint(widget, t) end
    end
    widget.Repaint = function(w)
        local fn = self.painters[w]
        if fn then fn(self.tokens) end
    end
    if widget.HookScript and not widget.kitNoTooltip then
        widget.tooltip = opts.tooltip
        widget.SetTooltip = function(w, tip)
            w.tooltip = tip
            UI.HookTooltip(w)
        end
        if opts.tooltip ~= nil or widget.kitTooltipAlways then
            UI.HookTooltip(widget)
        end
    end
    if widget.HookScript then widget.OnRightClick = UI.OnRightClick end
    if widget.CreateTexture then
        widget.Attract = function(w, kind, tone) UI.Attract(w, kind, tone) end
    end
    if opts.hidden then widget:Hide() end
    widget:Repaint()
    return widget
end

-- Right-click on any widget: `fn(widget)`. Buttons are told of right clicks
-- through their click; other frames through the mouse going up.
function UI.OnRightClick(widget, fn)
    widget.kitRightClick = fn
    if widget.RegisterForClicks and widget:GetObjectType() == "Button" then
        widget:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if not widget.kitRightHooked then
            widget.kitRightHooked = true
            widget:HookScript("OnClick", function(w, button)
                if button == "RightButton" and w.kitRightClick then w.kitRightClick(w) end
            end)
        end
    else
        if widget.EnableMouse then widget:EnableMouse(true) end
        if not widget.kitRightHooked then
            widget.kitRightHooked = true
            widget:HookScript("OnMouseUp", function(w, button)
                if button == "RightButton" and w.kitRightClick then w.kitRightClick(w) end
            end)
        end
    end
    return widget
end

-- Painting helpers ---------------------------------------------------------------

function UI.TexColor(texture, color, alphaScale)
    if not color then
        texture:SetColorTexture(0, 0, 0, 0)
        return
    end
    texture:SetColorTexture(color[1], color[2], color[3], (color[4] or 1) * (alphaScale or 1))
end

function UI.TextColor(fontString, color, alphaScale)
    color = color or { 1, 1, 1, 1 }
    fontString:SetTextColor(color[1], color[2], color[3], (color[4] or 1) * (alphaScale or 1))
end

function UI.VertexColor(texture, color, alphaScale)
    color = color or { 1, 1, 1, 1 }
    texture:SetVertexColor(color[1], color[2], color[3], (color[4] or 1) * (alphaScale or 1))
end

-- The client's fonts: its own text face (whatever the locale uses) and its
-- narrow number face.
function UI.FontFile(face)
    if face == "number" then
        local object = _G.NumberFontNormal
        local file = object and object.GetFont and object:GetFont()
        return file or "Fonts\\ARIALN.TTF"
    end
    local object = _G.GameFontNormal
    local file = object and object.GetFont and object:GetFont()
    return file or "Fonts\\FRIZQT__.TTF"
end

-- Sets a font string to a text style for the tokens `t`: face, size, colour
-- (unless `keepColor`) and the shadow.
function UI.ApplyStyle(fontString, style, t, color, keepColor)
    local spec = UI.textStyles[style] or UI.textStyles.body
    local size = math.floor(spec.size * (t.textScale or 1) + 0.5)
    local file = UI.FontFile(spec.face)
    local ok = pcall(fontString.SetFont, fontString, file, size, "")
    if not ok then pcall(fontString.SetFont, fontString, "Fonts\\FRIZQT__.TTF", size, "") end
    if not keepColor then UI.TextColor(fontString, UI.TokenColor(t, color or spec.color) or t.text) end
    -- Pale text holds over the world with its hard shadow.
    if fontString.SetShadowColor then
        fontString:SetShadowColor(0, 0, 0, 0.9)
        fontString:SetShadowOffset(1, -1)
    end
end

-- A font string in a style; `color` a token name or a colour.
function UI.NewText(parent, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(UI.FontFile(), 11, "")
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    return text
end

-- How wide a line of text wants to be, whatever width it is held to now.
function UI.StringWidth(label)
    if label.GetUnboundedStringWidth then
        local ok, width = pcall(label.GetUnboundedStringWidth, label)
        if ok and type(width) == "number" then return width end
    end
    return label:GetStringWidth() or 0
end

-- Whether a texture really took its file. Some clients answer SetTexture
-- with false for a path they do not have, others take it and leave the
-- texture empty; either way the caller draws flat instead.
function UI.LoadTexture(texture, path, wrapH, wrapV)
    local ok, set
    if wrapH then
        ok, set = pcall(texture.SetTexture, texture, path, wrapH, wrapV)
    else
        ok, set = pcall(texture.SetTexture, texture, path)
    end
    if not ok or set == false or texture:GetTexture() == nil then return false end
    return true
end

-- Moves a region by a pixel or two wherever it is anchored: the press nudge.
function UI.ShiftPoints(region, dx, dy)
    local points = {}
    for index = 1, region:GetNumPoints() do points[index] = { region:GetPoint(index) } end
    region:ClearAllPoints()
    for _, point in ipairs(points) do
        region:SetPoint(point[1], point[2] or region:GetParent(), point[3] or point[1], (point[4] or 0) + dx, (point[5] or 0) + dy)
    end
end

-- The light tick of the chat scroll buttons. Silent on a client without it.
function UI.ClickSound()
    if type(PlaySound) ~= "function" or type(SOUNDKIT) ~= "table" then return end
    local kit = SOUNDKIT.U_CHAT_SCROLL_BUTTON or SOUNDKIT.IG_MAINMENU_OPTION
    if kit then pcall(PlaySound, kit) end
end

function UI.Now()
    return type(GetTime) == "function" and GetTime() or 0
end

-- WoW keeps a field focused through a click anywhere else, so keys go on
-- landing in it. Taking the focus away is what lets a field commit before
-- the click that follows it acts. Only the kit's own fields: a chat line the
-- player is writing stays open.
function UI.ClearTypingFocus(except)
    if type(GetCurrentKeyBoardFocus) ~= "function" then return end
    local focus = GetCurrentKeyBoardFocus()
    if focus and focus ~= except and focus.kitField then focus:ClearFocus() end
end

-- Screen pixels ---------------------------------------------------------------------

-- WoW lays the UI out in units, not screen pixels. The screen is always 768
-- units tall at an effective scale of 1, so one unit of a frame is
-- GetEffectiveScale() x (physical screen height / 768) pixels: 1.67 at 1440p
-- with a UI scale of 0.89. The effective scale alone is not enough (the
-- same sum as Blizzard's PixelUtil). An edge
-- at a fraction of a pixel is rounded when drawn, a 1 unit line comes out 1
-- or 2 pixels wide, and a change elsewhere can tip either way. So the kit
-- places everything on whole pixels (Snap), draws hairlines exactly one
-- pixel thick (Hairline) and thicker strokes as whole pixels (Stroke), and
-- does all of it again when the UI scale or the resolution changes.

-- Screen pixels in one unit of `frame`.
local function scaleOf(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    if type(GetPhysicalScreenSize) == "function" then
        local ok, _, height = pcall(GetPhysicalScreenSize)
        if ok and type(height) == "number" and height > 0 then scale = scale * height / 768 end
    end
    return scale
end
UI.PixelsPerUnit = scaleOf

-- `value` (in `frame`'s units) on the nearest whole screen pixel.
function UI.Snap(frame, value)
    local scale = scaleOf(frame)
    return math.floor(value * scale + 0.5) / scale
end

-- `count` whole screen pixels, in `frame`'s units.
function UI.Pixels(frame, count)
    return (count or 1) / scaleOf(frame)
end

local strokes = setmetatable({}, { __mode = "k" })
local function applyStroke(texture, spec)
    local scale = scaleOf(texture)
    local pixels = spec.pixels or math.max(1, math.floor(spec.units * scale + 0.5))
    local size = pixels / scale
    if spec.axis == "width" then texture:SetWidth(size) else texture:SetHeight(size) end
end

-- Makes `texture` exactly one screen pixel thick across `axis` ("height" for
-- a line across, "width" for a line down), and keeps it so.
function UI.Hairline(texture, axis)
    local spec = { axis = axis or "height", pixels = 1 }
    strokes[texture] = spec
    applyStroke(texture, spec)
end

-- Makes `texture` `units` thick across `axis`, rounded to whole screen
-- pixels (never under one), and keeps it so: an accent line, a track.
function UI.Stroke(texture, axis, units)
    local spec = { axis = axis or "height", units = units or 1 }
    strokes[texture] = spec
    applyStroke(texture, spec)
end

-- `fn()` after the UI scale or the resolution changes, once every hairline
-- and stroke has been redrawn. Windows use it to put themselves back on the
-- pixel grid and lay out again.
local scaleListeners = setmetatable({}, { __mode = "k" })
function UI.OnPixelScale(owner, fn)
    scaleListeners[owner] = fn
end

function UI.PixelScaleChanged()
    for texture, spec in pairs(strokes) do applyStroke(texture, spec) end
    for owner, fn in pairs(scaleListeners) do fn(owner) end
end

if type(CreateFrame) == "function" then
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnEvent", function() UI.PixelScaleChanged() end)
end

-- Plates: the box behind a widget ---------------------------------------------------

-- A fill and a one-pixel edge, or a 9-slice texture, whichever the theme has.
-- `plate:Flat(fill, edge)` draws colours (nil draws nothing there);
-- `plate:Art(spec)` draws the texture and answers whether it loaded.
function UI.NewPlate(frame, layer, sublevel)
    layer = layer or "BACKGROUND"
    local plate = { frame = frame }
    plate.fill = frame:CreateTexture(nil, layer, nil, sublevel or 0)
    plate.fill:SetAllPoints(frame)
    plate.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
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

    function plate:Flat(fill, edge, edgeAlpha)
        if self.nine then self.nine:Hide() end
        self.fill:Show()
        UI.TexColor(self.fill, fill)
        for _, texture in pairs(self.edges) do
            texture:Show()
            UI.TexColor(texture, edge, edgeAlpha)
        end
    end

    -- `corner` is how big the corners are drawn. `tint` shades the texture
    -- (hover, press, disabled).
    function plate:Art(spec, corner, tint)
        if not spec then return false end
        if not self.nine or self.nineSpec ~= spec then
            if self.nine then self.nine:Hide() end
            self.nine = UI.NineSlice(frame, layer, spec, corner or 6, true, sublevel)
            self.nineSpec = spec
        end
        if not self.nine.loaded then return false end
        self.fill:Hide()
        for _, texture in pairs(self.edges) do texture:Hide() end
        self.nine:Show()
        self.nine:SetTint(tint)
        return true
    end

    function plate:Hide()
        self.fill:Hide()
        for _, texture in pairs(self.edges) do texture:Hide() end
        if self.nine then self.nine:Hide() end
    end

    return plate
end

-- A 9-slice drawn by the kit: eight pieces and an optional centre cut from
-- one texture with SetTexCoord, so corners keep their size and the edges
-- stretch. `spec` is { file, corner, size, width }: `corner` source pixels
-- of a `width` x `size` texture. `display` is how big a corner is drawn.
function UI.NineSlice(frame, layer, spec, display, center, sublevel)
    local nine = { pieces = {}, loaded = false }
    local path = UI.MediaPath(spec.file)
    local width, height = spec.width or spec.size, spec.size
    local u, v = spec.corner / width, spec.corner / height
    local d = display
    local layout = {
        { "TOPLEFT", 0, 0, 0, u, 0, v },
        { "TOPRIGHT", 0, 0, 1 - u, 1, 0, v },
        { "BOTTOMLEFT", 0, 0, 0, u, 1 - v, 1 },
        { "BOTTOMRIGHT", 0, 0, 1 - u, 1, 1 - v, 1 },
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
        function nine:Show() end
        function nine:Hide() end
        function nine:SetTint() end
        return nine
    end
    for index, spot in ipairs(layout) do
        local texture = index == 1 and first or piece()
        if index > 1 then texture:SetTexture(path) end
        texture:SetSize(d, d)
        texture:SetPoint(spot[1], frame, spot[1], 0, 0)
        texture:SetTexCoord(spot[4], spot[5], spot[6], spot[7])
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
    function nine:Show() for _, texture in ipairs(self.pieces) do texture:Show() end end
    function nine:Hide() for _, texture in ipairs(self.pieces) do texture:Hide() end end
    function nine:SetTint(color)
        color = color or { 1, 1, 1, 1 }
        for _, texture in ipairs(self.pieces) do UI.VertexColor(texture, color) end
    end
    return nine
end

-- A texture tiled both ways over `texture`'s area; false when the file or
-- tiling is not there.
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

-- `size` is the box the glyph fills; `thickness` its stroke.
function UI.NewGlyph(frame, kind, size, thickness)
    local glyph = { lines = {}, kind = kind, dx = 0, dy = 0 }
    size = size or 10
    local half = size / 2
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
    function glyph:Place()
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
    function glyph:SetColor(color, alphaScale)
        for _, line in ipairs(self.lines) do UI.TexColor(line, color, alphaScale) end
        if self.text then UI.TextColor(self.text, color, alphaScale) end
    end
    function glyph:SetShown(shown)
        for _, line in ipairs(self.lines) do line:SetShown(shown) end
        if self.text then self.text:SetShown(shown) end
    end
    -- Moves the glyph off the frame's centre: the press nudge, or a glyph
    -- that sits at one side of its frame.
    function glyph:Offset(dx, dy)
        self.dx, self.dy = dx, dy
        self:Place()
    end
    function glyph:Nudge(dx, dy)
        self:Offset(self.dx + dx, self.dy + dy)
    end
    glyph:Place()
    return glyph
end
