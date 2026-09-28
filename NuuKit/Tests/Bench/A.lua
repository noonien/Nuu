-- A: the kit as it is. Per-instance closures for every method and script, a
-- painters table of closures, a full repaint (font, colours, fit) on hover,
-- colours made fresh on every paint, invalidation up to the window, sizes
-- measured again on every pass, and pixel snapping that asks the client for
-- its scale on every edge.

local C = dofile(BENCH .. "Common.lua")
local M = {}
local Proto, Container = {}, {}

local function Tokens(look)
    local t = {}
    for k, v in pairs(C.themes[look.theme]) do t[k] = v end
    t.textScale = look.textScale
    return t
end

function M.NewUI(look)
    local ui = setmetatable({ painters = setmetatable({}, { __mode = "k" }), track = {} }, { __index = Proto })
    ui.tokens = Tokens(look)
    return ui
end

function M.SetLook(ui, look)
    ui.tokens = Tokens(look)
    local list = {}
    for object, fn in pairs(ui.painters) do list[#list + 1] = fn end
    for _, fn in ipairs(list) do fn(ui.tokens) end
end

local function Define(name, fn)
    Proto[name] = fn
    Container[name] = function(self, ...)
        local widget = fn(self.ui, self, ...)
        self:KitAppend(widget)
        return widget
    end
end

function Proto:Finish(widget, opts, paint)
    widget.ui = self
    widget.kitLayout = widget.kitLayout or opts or {}
    if paint then self.painters[widget] = function(t) paint(widget, t) end end
    widget.Repaint = function(w)
        local fn = self.painters[w]
        if fn then fn(self.tokens) end
    end
    widget:Repaint()
    return widget
end

-- Painting ------------------------------------------------------------------

local function FontFile() return GameFontNormal:GetFont() end

local function ApplyStyle(fs, style, t, color)
    local spec = C.textStyles[style] or C.textStyles.body
    local size = math.floor(spec.size * t.textScale + 0.5)
    local ok = pcall(fs.SetFont, fs, FontFile(), size, "")
    if not ok then pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size, "") end
    color = color or t.text
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end

local function Tex(texture, c)
    if not c then texture:SetColorTexture(0, 0, 0, 0) return end
    texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function scaleOf(frame)
    local scale = frame:GetEffectiveScale() or 1
    local ok, _, height = pcall(GetPhysicalScreenSize)
    if ok and height then scale = scale * height / 768 end
    return scale
end
local function Snap(frame, value)
    local scale = scaleOf(frame)
    return math.floor(value * scale + 0.5) / scale
end

local function NewPlate(frame)
    local plate = { fill = frame:CreateTexture(), edges = {} }
    plate.fill:SetAllPoints(frame)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture()
        edge:SetPoint(side .. "LEFT")
        edge:SetPoint(side .. "RIGHT")
        edge:SetHeight(1)
        plate.edges[side] = edge
    end
    function plate:Flat(fill, edge)
        self.fill:Show()
        Tex(self.fill, fill)
        for _, texture in pairs(self.edges) do
            texture:Show()
            Tex(texture, edge)
        end
    end
    return plate
end

local function ButtonColors(t, tone, state)
    local base = tone and tone ~= "neutral" and t[tone]
    if state == "disabled" then return t.surface, C.Alpha(t.border, 0.5), C.Alpha(t.muted, 0.45) end
    if not base then
        if state == "hover" then return t.raised, C.Alpha(t.accent, 0.65), t.text end
        return t.surface, t.border, t.text
    end
    local ink = C.Alpha(base, 1)
    return C.Mix(base, t.window, state == "hover" and 0.52 or 0.68), ink, t.text
end

-- Layout --------------------------------------------------------------------

local pending = {}

local function Invalidate(container)
    local frame = container
    while frame do
        pending[frame] = true
        frame = frame.kitParentContainer
    end
end

local function depth(frame)
    local d = 0
    local parent = frame.kitParentContainer
    while parent do
        d = d + 1
        parent = parent.kitParentContainer
    end
    return d
end

function M.Flush()
    for _ = 1, 20 do
        if next(pending) == nil then break end
        local list = {}
        for container in pairs(pending) do list[#list + 1] = container end
        pending = {}
        table.sort(list, function(a, b) return depth(a) < depth(b) end)
        for _, container in ipairs(list) do container:KitLayout() end
    end
end

local function lay(child) return child.kitLayout or {} end
local function growWeight(child)
    local grow = lay(child).grow
    if grow == true then return 1 end
    if type(grow) == "number" and grow > 0 then return grow end
end
local function shown(child) return child:IsShown() end
local function NaturalWidth(child)
    if lay(child).width then return lay(child).width end
    if child.KitNaturalWidth then return child:KitNaturalWidth() end
    return child:GetWidth()
end
local function NaturalHeight(child, width)
    if lay(child).height then return lay(child).height end
    if child.KitNaturalHeight then return child:KitNaturalHeight(width) end
    return child:GetHeight()
end
local function stretches(child) return child.kitStretch ~= false and not lay(child).width end

local function place(parent, child, x, y, w, h)
    local left, top = Snap(parent, x), Snap(parent, y)
    local width, height = Snap(parent, x + w) - left, Snap(parent, y + h) - top
    child:ClearAllPoints()
    child:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
    child:SetSize(math.max(0.01, width), math.max(0.01, height))
end

function Container:KitAppend(child)
    table.insert(self.kitChildren, child)
    child.kitParentContainer = self
    if child.HookScript and not child.kitShowHooked then
        child.kitShowHooked = true
        child:HookScript("OnShow", function(c) if c.kitParentContainer then Invalidate(c.kitParentContainer) end end)
        child:HookScript("OnHide", function(c) if c.kitParentContainer then Invalidate(c.kitParentContainer) end end)
    end
    Invalidate(self)
    return child
end

function Container:Clear()
    for _, child in ipairs(self.kitChildren) do
        child.kitParentContainer = nil
        child:Hide()
    end
    self.kitChildren = {}
    Invalidate(self)
end

local function columnNaturalHeight(self, width)
    width = width or self:GetWidth()
    local p, gap = self.kitPadding, self.kitGap
    local inner = width - 2 * p
    local total, count = 0, 0
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then
            local cw = stretches(child) and inner or math.min(inner, NaturalWidth(child))
            total = total + (growWeight(child) and 0 or NaturalHeight(child, cw))
            count = count + 1
        end
    end
    return total + 2 * p + math.max(0, count - 1) * gap
end

local function columnNaturalWidth(self)
    local widest = 0
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then widest = math.max(widest, NaturalWidth(child)) end
    end
    return widest + 2 * self.kitPadding
end

local function columnLayout(self)
    local width, height = self:GetWidth(), self:GetHeight()
    if width <= 0 then return end
    local p, gap = self.kitPadding, self.kitGap
    local inner = width - 2 * p
    local children, items = {}, {}
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then
            local cw = stretches(child) and inner or math.min(inner, NaturalWidth(child))
            local weight = growWeight(child)
            children[#children + 1] = { child = child, width = cw }
            items[#items + 1] = weight and { grow = weight, min = 0 } or { size = NaturalHeight(child, cw) }
        end
    end
    local placed = C.Distribute(items, height - 2 * p, gap)
    for index, entry in ipairs(children) do
        local child, spot = entry.child, placed[index]
        place(self, child, p, p + spot.offset, entry.width, spot.size)
        if child.kitChildren then pending[child] = true end
    end
end

local function rowNaturalWidth(self)
    local p, gap = self.kitPadding, self.kitGap
    local total, count = 0, 0
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then
            total = total + (growWeight(child) and 0 or NaturalWidth(child))
            count = count + 1
        end
    end
    return total + 2 * p + math.max(0, count - 1) * gap
end

local function rowNaturalHeight(self)
    local tallest = 0
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then tallest = math.max(tallest, NaturalHeight(child, NaturalWidth(child))) end
    end
    return tallest + 2 * self.kitPadding
end

local function rowLayout(self)
    local width, height = self:GetWidth(), self:GetHeight()
    if width <= 0 then return end
    local p, gap = self.kitPadding, self.kitGap
    local innerHeight = height - 2 * p
    local children, items = {}, {}
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then
            local weight = growWeight(child)
            children[#children + 1] = child
            items[#items + 1] = weight and { grow = weight, min = 0 } or { size = NaturalWidth(child) }
        end
    end
    local placed = C.Distribute(items, width - 2 * p, gap)
    for index, child in ipairs(children) do
        local spot = placed[index]
        local h = math.min(innerHeight, NaturalHeight(child, spot.size))
        place(self, child, p + spot.offset, p + (innerHeight - h) / 2, spot.size, h)
        if child.kitChildren then pending[child] = true end
    end
end

local function MakeContainer(ui, frame, kind, opts)
    for name, fn in pairs(Container) do frame[name] = fn end
    frame.ui = ui
    frame.kitChildren = {}
    frame.kitGap = opts.gap or 6
    frame.kitPadding = opts.padding or 0
    if kind == "row" then
        frame.KitLayout, frame.KitNaturalWidth, frame.KitNaturalHeight = rowLayout, rowNaturalWidth, rowNaturalHeight
    else
        frame.KitLayout, frame.KitNaturalWidth, frame.KitNaturalHeight = columnLayout, columnNaturalWidth, columnNaturalHeight
    end
    frame:HookScript("OnSizeChanged", function(f) Invalidate(f) end)
    frame:HookScript("OnShow", function(f) Invalidate(f) end)
    return frame
end

local function makeStack(kind)
    return function(ui, parent, opts)
        opts = opts or {}
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(1, 1)
        MakeContainer(ui, frame, kind, opts)
        return ui:Finish(frame, opts)
    end
end
Define("Column", makeStack("column"))
Define("Row", makeStack("row"))

Define("Spacer", function(ui, parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    opts.grow = true
    return ui:Finish(frame, opts)
end)

function M.Window(ui, width, height)
    local win = CreateFrame("Frame", nil, UIParent)
    win:SetSize(width, height)
    MakeContainer(ui, win, "column", {})
    win.kitFill = true
    return ui:Finish(win, {})
end

-- Widgets -------------------------------------------------------------------

Define("Text", function(ui, parent, text, style, opts)
    opts = opts or {}
    local label = parent:CreateFontString()
    label.kitStyle = style or "body"
    label.kitColor = opts.color
    label:SetJustifyH(opts.justify or "LEFT")
    local setText, show, hide = label.SetText, label.Show, label.Hide
    local function changed(l)
        if l.kitParentContainer then Invalidate(l.kitParentContainer) end
    end
    label.SetText = function(l, value)
        setText(l, value == nil and "" or tostring(value))
        changed(l)
    end
    label.Show = function(l) show(l); changed(l) end
    label.Hide = function(l) hide(l); changed(l) end
    label.SetShown = function(l, on) if on then l:Show() else l:Hide() end end
    label.SetColor = function(l, color) l.kitColor = color; l:Repaint() end
    label.SetStyle = function(l, value) l.kitStyle = value; l:Repaint(); changed(l) end
    label.KitNaturalWidth = function(l) return math.ceil(l:GetStringWidth()) + 1 end
    label.KitNaturalHeight = function(l) return math.ceil(l:GetStringHeight()) end
    setText(label, text == nil and "" or tostring(text))
    return ui:Finish(label, opts, function(l, t)
        ApplyStyle(l, l.kitStyle, t, l.kitColor and t[l.kitColor])
        changed(l)
    end)
end)

local function wire(button)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnEnter", function(b) b.hover = true; b:Repaint() end)
    button:SetScript("OnLeave", function(b) b.hover = false; b:Repaint() end)
    button.kitPressParts = button.kitPressParts or {}
    local function release(b)
        if not b.pressed then return end
        b.pressed = false
    end
    button:HookScript("OnMouseDown", function(b) b.pressed = true end)
    button:HookScript("OnMouseUp", release)
    button:HookScript("OnHide", release)
    button:SetScript("PreClick", function() end)
    button:SetScript("OnClick", function(b, mouse)
        if mouse == "RightButton" then return end
        if b.kitClick then b.kitClick(b) end
    end)
    button:HookScript("OnEnable", function(b) if b.Repaint then b:Repaint() end end)
    button:HookScript("OnDisable", function(b) if b.Repaint then b:Repaint() end end)
    button.SetEnabled = function(b, enabled)
        if enabled then b:Enable() else b:Disable(); release(b) end
        b:Repaint()
    end
    button.SetOnClick = function(b, fn) b.kitClick = fn end
end

local function stateOf(button)
    if not button:IsEnabled() then return "disabled" end
    if button.hover then return "hover" end
    return "rest"
end

Define("Button", function(ui, parent, caption, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(24, 24)
    button.kitStretch = false
    button.kitTone = opts.tone
    button.kitClick = opts.onClick
    button.plate = NewPlate(button)
    local label = button:CreateFontString()
    label:SetPoint("CENTER")
    label:SetText(caption or "")
    button.label = label
    function button:Fit()
        label:SetWidth(0)
        local width = math.max(24, math.ceil(label:GetStringWidth() + 20))
        if math.abs(self:GetWidth() - width) > 0.5 then
            self:SetWidth(width)
            if self.kitParentContainer then Invalidate(self.kitParentContainer) end
        end
    end
    button.KitNaturalWidth = function()
        label:SetWidth(0)
        return math.max(24, math.ceil(label:GetStringWidth() + 20))
    end
    button.KitNaturalHeight = function() return 24 end
    button.SetText = function(b, text) label:SetText(text or ""); b:Fit() end
    button.GetText = function() return label:GetText() end
    button.SetActive = function(b, active) b.kitActive = active; b:Repaint() end
    button.IsActive = function(b) return b.kitActive end
    button.SetTone = function(b, tone) b.kitTone = tone; b:Repaint() end
    wire(button)
    ui.track[#ui.track + 1] = button
    return ui:Finish(button, opts, function(b, t)
        local fill, edge, ink = ButtonColors(t, b.kitTone, stateOf(b))
        b.plate:Flat(fill, edge)
        ApplyStyle(label, "body", t, ink)
        b:Fit()
    end)
end)

Define("Toggle", function(ui, parent, caption, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(1, 22)
    button.kitStretch = false
    button.kitChecked = opts.value and true or false
    local box = CreateFrame("Frame", nil, button)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    box.plate = NewPlate(box)
    local check = box:CreateTexture()
    check:SetAllPoints()
    local label = button:CreateFontString()
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(caption or "")
    button.KitNaturalWidth = function() return math.ceil(label:GetStringWidth()) + 20 end
    button.KitNaturalHeight = function() return 22 end
    function button:SetValue(on)
        self.kitChecked = on and true or false
        self:Repaint()
    end
    function button:GetValue() return self.kitChecked end
    function button:SetText(text)
        label:SetText(text or "")
        if self.kitParentContainer then Invalidate(self.kitParentContainer) end
    end
    button.kitClick = function(b)
        b:SetValue(not b.kitChecked)
        if opts.onChange then opts.onChange(b.kitChecked) end
    end
    wire(button)
    return ui:Finish(button, opts, function(b, t)
        local hover = b.hover
        box.plate:Flat(t.surface, hover and C.Alpha(t.accent, 0.65) or t.border)
        Tex(check, b.kitChecked and t.accent or nil)
        ApplyStyle(label, "body", t, t.text)
    end)
end)

-- The sample screen, in the kit's current API.
-- screen:begin
function M.Screen(ui, win, db, items)
    local body = win:Column({ gap = 6, padding = 10 })
    local head = body:Row({ gap = 8 })
    head:Text("Settings", "title")
    head:Spacer()
    local toggles, counts = {}, {}
    head:Button("Reset", { onClick = function()
        for _, key in ipairs(C.KEYS) do
            db[key] = nil
            toggles[key]:SetValue(false)
        end
        for i, item in ipairs(items) do
            item.count = 0
            counts[i]:SetText(0)
        end
    end })
    for _, key in ipairs(C.KEYS) do
        toggles[key] = body:Toggle(key, { value = db[key], onChange = function(on) db[key] = on end })
    end
    for i, item in ipairs(items) do
        local row = body:Row({ gap = 8 })
        row:Text(item.name, "body", { grow = true })
        counts[i] = row:Text(item.count, "number")
        row:Button("+1", { onClick = function()
            item.count = item.count + 1
            counts[i]:SetText(item.count)
        end })
    end
    return body
end
-- screen:end

function M.Clear(ui, win) win:Clear() end

return M
