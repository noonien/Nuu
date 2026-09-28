local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Container = UI.Container

-- Columns and rows: containers that stack what is made in them.
--
-- A child's layout options are its widget options: `grow` (a weight, or true
-- for 1) takes a share of the spare room along the stack, `width` and
-- `height` fix a size, `minHeight` / `minWidth` hold a growing child open.
-- Across a column, children stretch to its width unless they say
-- `kitStretch = false` (buttons, toggles) or give a width; `align` places
-- those ("left", "center", "right"). Across a row, children are centred;
-- `align` packs the row itself ("left", "center", "right").
--
-- A container lays out again, on the next frame, when its size changes,
-- when a child is added, shown or hidden, or when a text in it changes.

-- The sums, apart from any frame -------------------------------------------------

-- Hands out `available` along a stack. `items` are { size = n } for a fixed
-- child or { grow = weight, min = n } for a growing one. Returns each item's
-- offset from the start and its size.
function UI.Distribute(items, available, gap)
    gap = gap or 0
    local fixed, weights = 0, 0
    for _, item in ipairs(items) do
        if item.grow then weights = weights + item.grow else fixed = fixed + (item.size or 0) end
    end
    local spare = math.max(0, available - fixed - gap * math.max(0, #items - 1))
    local out, offset = {}, 0
    for index, item in ipairs(items) do
        local size = item.size or 0
        if item.grow then size = math.max(item.min or 0, weights > 0 and spare * item.grow / weights or 0) end
        out[index] = { offset = offset, size = size }
        offset = offset + size + gap
    end
    return out
end

-- Puts `child` at `x`, `y` (down from `parent`'s top left) sized `w` by `h`,
-- its edges on whole screen pixels: the size is the distance between the
-- snapped edges, so neighbours neither overlap nor part by a pixel.
local function place(parent, child, x, y, w, h)
    local left, top = UI.Snap(parent, x), UI.Snap(parent, y)
    local width, height = UI.Snap(parent, x + w) - left, UI.Snap(parent, y + h) - top
    child:ClearAllPoints()
    child:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
    child:SetSize(math.max(0.01, width), math.max(0.01, height))
end

-- Where a run of `total` starts in `available` for an alignment.
function UI.AlignStart(align, available, total)
    if align == "center" then return math.max(0, (available - total) / 2) end
    if align == "right" or align == "bottom" then return math.max(0, available - total) end
    return 0
end

-- Scheduling ---------------------------------------------------------------------------

local pending, driver = {}, nil

local function depth(frame)
    local d = 0
    local parent = frame.kitParentContainer
    while parent do
        d = d + 1
        parent = parent.kitParentContainer
    end
    return d
end

local function runLayouts()
    for _ = 1, 20 do
        if next(pending) == nil then break end
        local list = {}
        for container in pairs(pending) do list[#list + 1] = container end
        pending = {}
        table.sort(list, function(a, b) return depth(a) < depth(b) end)
        for _, container in ipairs(list) do
            if container.KitLayout then container:KitLayout() end
        end
    end
    if next(pending) == nil and driver then driver:Hide() end
end

-- Lays `container` out again on the next frame, and every container above
-- it, since its natural size may have changed.
function UI.Invalidate(container)
    local frame = container
    while frame do
        pending[frame] = true
        frame = frame.kitParentContainer
    end
    if not driver then
        if type(CreateFrame) ~= "function" then return end
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", runLayouts)
    end
    driver:Show()
end

-- Lays out a container its parent has just sized. Only that one: the parent
-- is being laid out already, and marking it again (as Invalidate would)
-- makes every pass queue the next, so the layout never settles. A widget
-- holding a container of its own (a card's body) calls it from KitSized.
function UI.LayoutOnly(child)
    pending[child] = true
    if driver then driver:Show() end
end
local relayoutChild = UI.LayoutOnly

-- Lays out now: for code that needs sizes before the next frame.
function UI.LayoutNow()
    runLayouts()
end

-- Whether nothing is waiting to be laid out.
function UI.LayoutSettled()
    return next(pending) == nil
end

-- Measuring ---------------------------------------------------------------------------

local function lay(child) return child.kitLayout or {} end

local function growWeight(child)
    local grow = lay(child).grow
    if grow == true then return 1 end
    if type(grow) == "number" and grow > 0 then return grow end
    return nil
end

local function shown(child)
    return child.IsShown and child:IsShown()
end

function UI.NaturalWidth(child)
    local l = lay(child)
    if l.width then return l.width end
    if child.KitNaturalWidth then return child:KitNaturalWidth() end
    return child:GetWidth() or 0
end

function UI.NaturalHeight(child, width)
    local l = lay(child)
    if l.height then return l.height end
    if child.KitNaturalHeight then return child:KitNaturalHeight(width) end
    return child:GetHeight() or 0
end

local function stretches(child)
    local l = lay(child)
    return child.kitStretch ~= false and not l.width
end

-- Containers ------------------------------------------------------------------------------

function Container:KitAppend(child)
    self.kitChildren = self.kitChildren or {}
    table.insert(self.kitChildren, child)
    child.kitParentContainer = self
    child.kitWindow = child.kitWindow or self.kitWindow
    if child.HookScript and not child.kitShowHooked then
        child.kitShowHooked = true
        child:HookScript("OnShow", function(c) if c.kitParentContainer then UI.Invalidate(c.kitParentContainer) end end)
        child:HookScript("OnHide", function(c) if c.kitParentContainer then UI.Invalidate(c.kitParentContainer) end end)
    end
    if child.KitAttached then child:KitAttached(self) end
    UI.Invalidate(self)
    return child
end

-- Takes a child out of the stack (and hides it); `Clear` takes them all.
function Container:Remove(child)
    local inner = self.kitInner or self
    for index, c in ipairs(inner.kitChildren or {}) do
        if c == child then
            table.remove(inner.kitChildren, index)
            child.kitParentContainer = nil
            child:Hide()
            UI.Invalidate(inner)
            return
        end
    end
end

function Container:Clear()
    local inner = self.kitInner or self
    for _, child in ipairs(inner.kitChildren or {}) do
        child.kitParentContainer = nil
        child:Hide()
    end
    inner.kitChildren = {}
    UI.Invalidate(inner)
end

function Container:GetFrame()
    return self.kitInner or self
end

function Container:Relayout()
    UI.Invalidate(self.kitInner or self)
end

local function statePad(self, height)
    if self.kitState then return math.max(height, self.kitStateHeight or 90) end
    return height
end

local function columnNaturalHeight(self, width)
    width = width or self:GetWidth() or 0
    local p, gap = self.kitPadding or 0, self.kitGap or 0
    local inner = width - 2 * p
    local total, count = 0, 0
    for _, child in ipairs(self.kitChildren or {}) do
        if shown(child) then
            local l = lay(child)
            local cw = stretches(child) and inner or math.min(inner, UI.NaturalWidth(child))
            local h = growWeight(child) and (l.minHeight or 0) or UI.NaturalHeight(child, cw)
            total = total + h
            count = count + 1
        end
    end
    return statePad(self, total + 2 * p + math.max(0, count - 1) * gap)
end

local function columnNaturalWidth(self)
    local widest = 0
    for _, child in ipairs(self.kitChildren or {}) do
        if shown(child) then widest = math.max(widest, UI.NaturalWidth(child)) end
    end
    return widest + 2 * (self.kitPadding or 0)
end

local function columnLayout(self)
    local width = self:GetWidth() or 0
    if width <= 0 then return end
    if self.kitAutoHeight then
        local natural = columnNaturalHeight(self, width)
        if math.abs((self:GetHeight() or 0) - natural) > 0.5 then self:SetHeight(natural) end
    end
    local height = self:GetHeight() or 0
    local p, gap = self.kitPadding or 0, self.kitGap or 0
    local inner = width - 2 * p
    local children, items = {}, {}
    for _, child in ipairs(self.kitChildren or {}) do
        if shown(child) then
            local l = lay(child)
            local cw = stretches(child) and inner or math.min(inner, UI.NaturalWidth(child))
            local weight = growWeight(child)
            children[#children + 1] = { child = child, width = cw }
            if weight then
                items[#items + 1] = { grow = weight, min = l.minHeight or 0 }
            else
                items[#items + 1] = { size = UI.NaturalHeight(child, cw) }
            end
        end
    end
    local placed = UI.Distribute(items, height - 2 * p, gap)
    for index, entry in ipairs(children) do
        local child, spot = entry.child, placed[index]
        local x = p
        if not stretches(child) then
            x = p + UI.AlignStart(lay(child).align or self.kitAlign, inner, entry.width)
        end
        place(self, child, x, p + spot.offset, entry.width, spot.size)
        if child.kitChildren then relayoutChild(child) end
        if child.KitSized then child:KitSized() end
    end
end

local function rowNaturalWidth(self)
    local p, gap = self.kitPadding or 0, self.kitGap or 0
    local total, count = 0, 0
    for _, child in ipairs(self.kitChildren or {}) do
        if shown(child) then
            total = total + (growWeight(child) and (lay(child).minWidth or 0) or UI.NaturalWidth(child))
            count = count + 1
        end
    end
    return total + (self.kitPadLeft or p) + (self.kitPadRight or p) + math.max(0, count - 1) * gap
end

local function rowNaturalHeight(self)
    local tallest = 0
    for _, child in ipairs(self.kitChildren or {}) do
        if shown(child) then
            tallest = math.max(tallest, UI.NaturalHeight(child, UI.NaturalWidth(child)))
        end
    end
    return statePad(self, tallest + 2 * (self.kitPadding or 0))
end

local function rowLayout(self)
    local width, height = self:GetWidth() or 0, self:GetHeight() or 0
    if width <= 0 then return end
    local p, gap = self.kitPadding or 0, self.kitGap or 0
    local innerHeight = height - 2 * p
    local children, items, anyGrow = {}, {}, false
    for _, child in ipairs(self.kitChildren or {}) do
        if shown(child) then
            local weight = growWeight(child)
            children[#children + 1] = child
            if weight then
                anyGrow = true
                items[#items + 1] = { grow = weight, min = lay(child).minWidth or 0 }
            else
                items[#items + 1] = { size = UI.NaturalWidth(child) }
            end
        end
    end
    local padLeft, padRight = self.kitPadLeft or p, self.kitPadRight or p
    local innerWidth = width - padLeft - padRight
    local placed = UI.Distribute(items, innerWidth, gap)
    local start = 0
    if not anyGrow and #placed > 0 then
        local last = placed[#placed]
        start = UI.AlignStart(self.kitAlign, innerWidth, last.offset + last.size)
    end
    for index, child in ipairs(children) do
        local spot = placed[index]
        local l = lay(child)
        local h
        if l.height then
            h = l.height
        elseif child.kitRowStretch or self.kitValign == "stretch" then
            h = innerHeight
        else
            h = math.min(innerHeight, UI.NaturalHeight(child, spot.size))
        end
        local valign = child.kitRowAlign or self.kitValign
        local y = p + UI.AlignStart(valign == "top" and "left" or (valign == "bottom" and "bottom" or "center"), innerHeight, h)
        place(self, child, padLeft + start + spot.offset, y, spot.size, h)
        if child.kitChildren then relayoutChild(child) end
        if child.KitSized then child:KitSized() end
    end
end

-- Makes `frame` a container of `kind` ("column" or "row") for `ui`.
function UI.MakeContainer(ui, frame, kind, opts)
    opts = opts or {}
    for name, fn in pairs(Container) do frame[name] = fn end
    frame.ui = ui
    frame.kitKind = kind
    frame.kitChildren = {}
    frame.kitGap = opts.gap or (kind == "row" and 6 or 8)
    frame.kitPadding = opts.padding or 0
    frame.kitAlign = opts.align
    frame.kitValign = opts.valign
    frame.kitPadLeft = opts.padLeft
    frame.kitPadRight = opts.padRight
    if kind == "row" then
        frame.KitLayout = rowLayout
        frame.KitNaturalWidth = rowNaturalWidth
        frame.KitNaturalHeight = rowNaturalHeight
    else
        frame.KitLayout = columnLayout
        frame.KitNaturalWidth = columnNaturalWidth
        frame.KitNaturalHeight = columnNaturalHeight
    end
    if frame.HookScript then
        frame:HookScript("OnSizeChanged", function(f) UI.Invalidate(f) end)
        frame:HookScript("OnShow", function(f) UI.Invalidate(f) end)
    end
    return frame
end

local function makeStack(kind)
    return function(ui, parent, opts)
        opts = opts or {}
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(opts.width or 1, opts.height or 1)
        UI.MakeContainer(ui, frame, kind, opts)
        return ui:Finish(frame, opts)
    end
end

UI.Define("Column", makeStack("column"), true)
UI.Define("Row", makeStack("row"))

-- Room that grows, or a fixed gap with `size`.
UI.Define("Spacer", function(ui, parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(opts.size or 1, opts.size or 1)
    if opts.grow == nil and not opts.size then opts.grow = true end
    if opts.size then
        if parent.kitKind == "row" then opts.width = opts.size else opts.height = opts.size end
    end
    return ui:Finish(frame, opts)
end)

-- A hairline: across a column, or along a row taking the spare room.
UI.Define("Rule", function(ui, parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    if parent.kitKind == "row" and opts.grow == nil then opts.grow = true end
    opts.height = opts.height or 1
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    UI.Hairline(line, "height")
    return ui:Finish(frame, opts, function(_, t) UI.TexColor(line, UI.TokenColor(t, opts.color) or t.hairline) end)
end)

-- States: loading, empty, error -------------------------------------------------------------

-- Puts a container's content aside for a message: "loading" (with a moving
-- ellipsis), "empty", or "error" (in the danger colour). `opts.action` is
-- { caption, onClick } for a button under the message. `SetState(nil)`
-- brings the content back.
function Container:SetState(kind, text, opts)
    opts = opts or {}
    local inner = self.kitInner or self
    local ui = self.ui
    if not kind then
        if inner.kitState then
            inner.kitState = nil
            for child in pairs(inner.kitStateHidden or {}) do child:Show() end
            inner.kitStateHidden = nil
            if inner.kitStateFrame then inner.kitStateFrame:Hide() end
            UI.Invalidate(inner)
        end
        return
    end
    local overlay = inner.kitStateFrame
    if not overlay then
        overlay = CreateFrame("Frame", nil, inner)
        overlay:SetAllPoints(inner)
        overlay:SetFrameLevel(inner:GetFrameLevel() + 5)
        overlay.message = UI.NewText(overlay)
        if overlay.message.SetWordWrap then overlay.message:SetWordWrap(true) end
        overlay.message:SetJustifyH("CENTER")
        overlay.message:SetPoint("LEFT", overlay, "LEFT", 16, 8)
        overlay.message:SetPoint("RIGHT", overlay, "RIGHT", -16, 8)
        overlay:SetScript("OnUpdate", function(o, elapsed)
            if o.kind ~= "loading" then return end
            o.clock = (o.clock or 0) + elapsed
            local dots = math.floor(o.clock * 2) % 4
            o.message:SetText(o.text .. string.rep(".", dots))
        end)
        ui:Paint(overlay, function(t)
            UI.ApplyStyle(overlay.message, "body", t, overlay.kind == "error" and "danger" or (overlay.kind == "empty" and "text" or "muted"))
        end)
        inner.kitStateFrame = overlay
    end
    overlay.kind, overlay.text, overlay.clock = kind, text or "", 0
    overlay.message:SetText(overlay.text)
    if overlay.action then overlay.action:Hide() end
    if opts.action then
        overlay.action = overlay.action or ui:Button(overlay, opts.action.caption or "", {})
        overlay.action:SetText(opts.action.caption or "")
        overlay.action.kitClick = opts.action.onClick
        overlay.action:ClearAllPoints()
        overlay.action:SetPoint("TOP", overlay.message, "BOTTOM", 0, -10)
        overlay.action:Show()
    end
    ui.painters[overlay](ui.tokens)
    if not inner.kitState then
        inner.kitStateHidden = {}
        for _, child in ipairs(inner.kitChildren or {}) do
            if child:IsShown() then
                inner.kitStateHidden[child] = true
                child:Hide()
            end
        end
    end
    inner.kitState = kind
    inner.kitStateHeight = opts.height
    overlay:Show()
    UI.Invalidate(inner)
end

function Container:GetState()
    local inner = self.kitInner or self
    return inner.kitState
end
