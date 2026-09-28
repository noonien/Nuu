-- B: shared methods and targeted fixes. Methods and scripts are shared
-- functions copied onto each frame (no per-instance closures). A look change
-- paints fonts and colours; hover paints colours only, from colours worked
-- out once per look. Sizes are measured once and cached; a change bubbles up
-- only while it changes a container's size; placement skips edges that did
-- not move; the pixel scale is read once. Widgets take one spec table, value
-- widgets share Get/SetValue and onChange, and `bind` ties a value to the
-- addon's table. With `pool`, cleared widgets are reused.
--
-- dofile gives a fresh copy each time, so C and D build on their own.

local C = dofile(BENCH .. "Common.lua")
local M = {}
local Widget, Stack, types = {}, {}, {}
M.Widget, M.Stack, M.types = Widget, Stack, types

-- Tokens: everything a paint needs, worked out once per look ----------------

local function buttonColors(t, tone, state)
    local base = tone ~= "neutral" and t[tone]
    if state == "disabled" then return { t.surface, C.Alpha(t.border, 0.5), C.Alpha(t.muted, 0.45) } end
    if not base then
        if state == "hover" then return { t.raised, C.Alpha(t.accent, 0.65), t.text } end
        return { t.surface, t.border, t.text }
    end
    return { C.Mix(base, t.window, state == "hover" and 0.52 or 0.68), C.Alpha(base, 1), t.text }
end

local function Tokens(look)
    local t = {}
    for k, v in pairs(C.themes[look.theme]) do t[k] = v end
    t.textScale = look.textScale
    t.font = GameFontNormal:GetFont()
    t.sizes = {}
    for style, spec in pairs(C.textStyles) do t.sizes[style] = math.floor(spec.size * t.textScale + 0.5) end
    t.button = {}
    for _, tone in ipairs(C.tones) do
        t.button[tone] = {
            rest = buttonColors(t, tone, "rest"),
            hover = buttonColors(t, tone, "hover"),
            disabled = buttonColors(t, tone, "disabled"),
        }
    end
    t.toggleEdge = { rest = t.border, hover = C.Alpha(t.accent, 0.65) }
    return t
end

function M.NewUI(look, opts)
    local ui = {
        widgets = setmetatable({}, { __mode = "k" }),
        dirty = {}, layouts = {}, pools = {}, track = {},
        pool = opts and opts.pool,
    }
    ui.tokens = Tokens(look)
    local _, height = GetPhysicalScreenSize()
    ui.scale = UIParent:GetEffectiveScale() * height / 768
    return ui
end

function M.SetLook(ui, look)
    local before = ui.tokens.textScale
    ui.tokens = Tokens(look)
    local resize = ui.tokens.textScale ~= before
    for w in pairs(ui.widgets) do
        if w:IsShown() then
            w:Paint(ui.tokens)
            if resize then w:Changed() end
        else
            w.kitStale = true
        end
    end
end

local function snap(ui, value) return math.floor(value * ui.scale + 0.5) / ui.scale end

-- Making widgets ---------------------------------------------------------------

local function make(ui, name, parent, spec)
    spec = spec or {}
    local def = types[name]
    local pool = ui.pools[name]
    local w = pool and table.remove(pool)
    if w then
        w:SetParent(parent)
        w:Show()
    else
        if def.kind == "FontString" then
            w = parent:CreateFontString()
        else
            w = CreateFrame(def.kind or "Frame", nil, parent)
        end
        for k, fn in pairs(Widget) do w[k] = fn end
        for k, fn in pairs(def.methods) do w[k] = fn end
        w.ui, w.kitType = ui, name
        if def.Build then def.Build(w) end
        ui.widgets[w] = true
    end
    w.grow, w.fixedWidth, w.stretch = spec.grow, spec.width, def.stretch
    w.natW, w.hover, w.kitStale = nil, nil, nil
    def.Init(w, spec)
    w:Paint(ui.tokens)
    return w
end
M.make = make

-- Registers `name`: `def` is { kind, stretch, Build(w), Init(w, spec), methods }.
function M.Define(name, def)
    types[name] = def
    Stack[name] = function(self, spec)
        local w = make(self.ui, name, self, spec)
        self:Append(w)
        return w
    end
end

-- Base methods --------------------------------------------------------------------

function Widget:Natural()
    if not self.natW then self.natW, self.natH = self:Measure() end
    return self.natW, self.natH
end

-- The widget's size may have changed; the next flush measures it again.
function Widget:Changed() self.ui.dirty[self] = true end

function Widget:Paint(t) end
function Widget:Measure() return 0, 0 end

-- Stacks ------------------------------------------------------------------------------

function Stack:Append(child)
    local children = self.children
    children[#children + 1] = child
    child.parent, child.depth = self, self.depth + 1
    self.ui.dirty[self] = true
    self.ui.layouts[self] = true
    return child
end

function Stack:Measure()
    local p, gap = self.padding, self.gap
    local main, cross, count = 0, 0, 0
    local column = self.axis == "column"
    for _, child in ipairs(self.children) do
        local w, h = child:Natural()
        if child.fixedWidth then w = child.fixedWidth end
        local along, across = column and h or w, column and w or h
        if child.grow then along = 0 end
        main = main + along
        if across > cross then cross = across end
        count = count + 1
    end
    main = main + 2 * p + math.max(0, count - 1) * gap
    cross = cross + 2 * p
    if column then return cross, main end
    return main, cross
end

-- Puts `child` at x, y sized w by h, snapped; skips what did not move.
-- Answers whether its size changed.
local function place(self, child, x, y, w, h)
    local ui = self.ui
    local left, top = snap(ui, x), snap(ui, y)
    local width = math.max(0.01, snap(ui, x + w) - left)
    local height = math.max(0.01, snap(ui, y + h) - top)
    if child.px ~= left or child.py ~= top then
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", self, "TOPLEFT", left, -top)
        child.px, child.py = left, top
    end
    if child.pw ~= width or child.ph ~= height then
        child:SetSize(width, height)
        child.pw, child.ph = width, height
        return true
    end
    return false
end

function Stack:Layout(done)
    done[self] = true
    local width, height = self.pw or self:GetWidth(), self.ph or self:GetHeight()
    if width <= 0 then return end
    local p, gap, column = self.padding, self.gap, self.axis == "column"
    local innerW, innerH = width - 2 * p, height - 2 * p
    local items = {}
    for index, child in ipairs(self.children) do
        local w, h = child:Natural()
        if child.fixedWidth then w = child.fixedWidth end
        if child.grow then
            items[index] = { grow = 1, min = 0 }
        else
            items[index] = { size = column and h or w }
        end
    end
    local placed = C.Distribute(items, column and innerH or innerW, gap)
    for index, child in ipairs(self.children) do
        local spot = placed[index]
        local w, h = child:Natural()
        local resized
        if column then
            local cw = (child.stretch ~= false and not child.fixedWidth) and innerW or math.min(innerW, child.fixedWidth or w)
            resized = place(self, child, p, p + spot.offset, cw, spot.size)
        else
            local ch = math.min(innerH, h)
            resized = place(self, child, p + spot.offset, p + (innerH - ch) / 2, spot.size, ch)
        end
        if child.children and (resized or self.ui.layouts[child]) and not done[child] then child:Layout(done) end
    end
end

local function makeStack(axis)
    return {
        stretch = true,
        Build = function(w)
            for k, fn in pairs(Stack) do w[k] = fn end
        end,
        Init = function(w, spec)
            w.axis, w.gap, w.padding = axis, spec.gap or 6, spec.padding or 0
            w.children = w.children or {}
            w.depth = 0
        end,
        methods = {},
    }
end
M.Define("Column", makeStack("column"))
M.Define("Row", makeStack("row"))
M.Define("Spacer", {
    Init = function(w) w.grow = true end,
    methods = {},
})

local function windowSized(self) self.ui.layouts[self] = true; self.pw, self.ph = self:GetWidth(), self:GetHeight() end

function M.Window(ui, width, height)
    local win = CreateFrame("Frame", nil, UIParent)
    for k, fn in pairs(Widget) do win[k] = fn end
    for k, fn in pairs(Stack) do win[k] = fn end
    win.ui, win.axis, win.gap, win.padding, win.children, win.depth = ui, "column", 0, 0, {}, 0
    win:SetScript("OnSizeChanged", windowSized)
    win:SetSize(width, height)
    return win
end

-- Lays out what changed: measures bottom-up while sizes change, then lays
-- out top-down only the stacks whose children moved or resized.
function M.Flush(ui)
    if next(ui.dirty) == nil and next(ui.layouts) == nil then return end
    local layouts = ui.layouts
    -- Deepest first, so each stack is measured once, after its children.
    local byDepth, deepest = {}, 0
    for node in pairs(ui.dirty) do
        local d = node.depth or 0
        byDepth[d] = byDepth[d] or {}
        byDepth[d][node] = true
        if d > deepest then deepest = d end
    end
    ui.dirty = {}
    for d = deepest, 0, -1 do
        for node in pairs(byDepth[d] or {}) do
            local oldW, oldH = node.natW, node.natH
            node.natW = nil
            local newW, newH = node:Natural()
            local parent = node.parent
            if parent and (newW ~= oldW or newH ~= oldH) then
                layouts[parent] = true
                byDepth[d - 1] = byDepth[d - 1] or {}
                byDepth[d - 1][parent] = true
            end
        end
    end
    local list = {}
    for stack in pairs(layouts) do list[#list + 1] = stack end
    table.sort(list, function(a, b) return a.depth < b.depth end)
    local done = {}
    for _, stack in ipairs(list) do
        if not done[stack] then stack:Layout(done) end
    end
    ui.layouts = {}
end

-- Clearing: with pooling the widgets go back to be made again.
local function release(ui, w)
    w:Hide()
    w:ClearAllPoints()
    w.px, w.py, w.pw, w.ph, w.parent = nil, nil, nil, nil, nil
    if w.children then
        for _, child in ipairs(w.children) do release(ui, child) end
        w.children = {}
    end
    ui.pools[w.kitType] = ui.pools[w.kitType] or {}
    table.insert(ui.pools[w.kitType], w)
end
M.release = release

function M.Clear(ui, win)
    for _, child in ipairs(win.children) do
        if ui.pool then release(ui, child) else child:Hide(); child.parent = nil end
    end
    win.children = {}
    ui.layouts[win] = true
end

-- Widgets ----------------------------------------------------------------------------

local function setFont(fs, t, style)
    fs:SetFont(t.font, t.sizes[style], "")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end
local function ink(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
local function tex(texture, c)
    if not c then texture:SetColorTexture(0, 0, 0, 0) return end
    texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- A fill and four hairlines, kept as fields.
local function buildPlate(frame)
    local fill = frame:CreateTexture()
    fill:SetAllPoints(frame)
    frame.plateFill = fill
    frame.plateEdges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture()
        edge:SetPoint(side .. "LEFT")
        edge:SetPoint(side .. "RIGHT")
        edge:SetHeight(1)
        frame.plateEdges[i] = edge
    end
end
local function paintPlate(frame, fill, edge)
    tex(frame.plateFill, fill)
    for i = 1, 4 do tex(frame.plateEdges[i], edge) end
end

-- The client's own SetText, for widgets that are font strings themselves.
local FontStringSetText = UIParent:CreateFontString().SetText

M.Define("Text", {
    kind = "FontString",
    Init = function(w, spec)
        w.style, w.color, w.value = spec.style or "body", spec.color, nil
        w:SetText(spec[1])
    end,
    methods = {
        SetText = function(self, value)
            value = value == nil and "" or tostring(value)
            if value == self.value then return end
            self.value = value
            FontStringSetText(self, value)
            self:Changed()
        end,
        Measure = function(self)
            return math.ceil(self:GetStringWidth()) + 1, math.ceil(self:GetStringHeight())
        end,
        Paint = function(self, t)
            setFont(self, t, self.style)
            ink(self, self.color and t[self.color] or t.text)
        end,
    },
})

-- Shared scripts: one function for every button.
local function onEnter(self) self.hover = true; self:PaintState(self.ui.tokens) end
local function onLeave(self) self.hover = false; self:PaintState(self.ui.tokens) end
local function onClick(self, mouse)
    if mouse == "RightButton" then return end
    self:Activate()
end

local function wireButton(w)
    w:RegisterForClicks("LeftButtonUp")
    w:SetScript("OnEnter", onEnter)
    w:SetScript("OnLeave", onLeave)
    w:SetScript("OnClick", onClick)
end

local function stateOf(w)
    if not w:IsEnabled() then return "disabled" end
    return w.hover and "hover" or "rest"
end

M.Define("Button", {
    kind = "Button", stretch = false,
    Build = function(w)
        buildPlate(w)
        w.label = w:CreateFontString()
        w.label:SetPoint("CENTER")
        wireButton(w)
        w.ui.track[#w.ui.track + 1] = w
    end,
    Init = function(w, spec)
        w.tone, w.onClick, w.caption = spec.tone or "neutral", spec.onClick, nil
        w:SetText(spec[1])
    end,
    methods = {
        SetText = function(self, text)
            text = text == nil and "" or tostring(text)
            if text == self.caption then return end
            self.caption = text
            self.label:SetText(text)
            self:Changed()
        end,
        GetText = function(self) return self.caption end,
        SetTone = function(self, tone)
            tone = tone or "neutral"
            if tone == self.tone then return end
            self.tone = tone
            self:PaintState(self.ui.tokens)
        end,
        SetEnabled = function(self, on)
            if on then self:Enable() else self:Disable() end
            self:PaintState(self.ui.tokens)
        end,
        Activate = function(self) if self.onClick then self.onClick(self) end end,
        Measure = function(self) return math.max(24, math.ceil(self.label:GetStringWidth() + 20)), 24 end,
        Paint = function(self, t)
            setFont(self.label, t, "body")
            self:PaintState(t)
        end,
        PaintState = function(self, t)
            local colors = t.button[self.tone][stateOf(self)]
            paintPlate(self, colors[1], colors[2])
            ink(self.label, colors[3])
        end,
    },
})

M.Define("Toggle", {
    kind = "Button", stretch = false,
    Build = function(w)
        w.box = CreateFrame("Frame", nil, w)
        w.box:SetSize(14, 14)
        w.box:SetPoint("LEFT")
        buildPlate(w.box)
        w.check = w.box:CreateTexture()
        w.check:SetAllPoints()
        w.label = w:CreateFontString()
        w.label:SetPoint("LEFT", w.box, "RIGHT", 6, 0)
        wireButton(w)
    end,
    Init = function(w, spec)
        w.bind, w.onChange, w.default = spec.bind, spec.onChange, spec.default or false
        w.label:SetText(spec[1] or "")
        local value = spec.value
        if w.bind then value = w.bind[1][w.bind[2]] end
        if value == nil then value = w.default end
        w.value = value
    end,
    methods = {
        GetValue = function(self) return self.value end,
        -- From code: never tells onChange.
        SetValue = function(self, value)
            value = value and true or false
            if value == self.value then return end
            self.value = value
            self:PaintState(self.ui.tokens)
        end,
        -- Back to the default, forgetting the stored choice.
        Reset = function(self)
            if self.bind then self.bind[1][self.bind[2]] = nil end
            self:SetValue(self.default)
        end,
        Activate = function(self)
            self:SetValue(not self.value)
            if self.bind then self.bind[1][self.bind[2]] = self.value end
            if self.onChange then self.onChange(self.value, self) end
        end,
        Measure = function(self) return math.ceil(self.label:GetStringWidth()) + 20, 22 end,
        Paint = function(self, t)
            setFont(self.label, t, "body")
            ink(self.label, t.text)
            self:PaintState(t)
        end,
        PaintState = function(self, t)
            paintPlate(self.box, t.surface, self.hover and t.toggleEdge.hover or t.toggleEdge.rest)
            tex(self.check, self.value and t.accent or nil)
        end,
    },
})

-- The sample screen: one spec table per widget, and `bind`.
-- screen:begin
function M.Screen(ui, win, db, items)
    local body = win:Column{ gap = 6, padding = 10 }
    local head = body:Row{ gap = 8 }
    head:Text{ "Settings", style = "title" }
    head:Spacer{}
    local toggles, counts = {}, {}
    head:Button{ "Reset", onClick = function()
        for _, toggle in ipairs(toggles) do toggle:Reset() end
        for i, item in ipairs(items) do
            item.count = 0
            counts[i]:SetText(0)
        end
    end }
    for _, key in ipairs(C.KEYS) do
        toggles[#toggles + 1] = body:Toggle{ key, bind = { db, key } }
    end
    for i, item in ipairs(items) do
        local row = body:Row{ gap = 8 }
        row:Text{ item.name, grow = true }
        counts[i] = row:Text{ item.count, style = "number" }
        row:Button{ "+1", onClick = function()
            item.count = item.count + 1
            counts[i]:SetText(item.count)
        end }
    end
    return body
end
-- screen:end

return M
