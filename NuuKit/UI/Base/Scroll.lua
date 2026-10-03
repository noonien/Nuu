local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- The slim scroll bar and the scroll frame it serves: the bar sits inside its owner's right edge and hides when the content
-- fits. Callers keep UI.SCROLLBAR clear at the right of their content.
UI.SCROLLBAR = 10
UI.SCROLL_STEP = 40
local THUMB_MIN = 20

-- The bar asks its `source` (any table) how things stand:
--   source:ScrollRange()   how far it scrolls
--   source:ScrollAt()      where it is
--   source:ScrollView()    how much shows
--   source:ScrollSet(v)    scroll to v (the source clamps and snaps)
-- `step` is the source's unit when it scrolls by rows (a list); nil for units.
local Bar = {}

local function cursorY(bar)
    local _, y = GetCursorPosition()
    return y / (bar:GetEffectiveScale() or 1)
end

-- Colours only; the thumb lights while the cursor is on it or drags it.
function Bar:PaintState()
    local t = self.ui.tokens
    UI.TexColor(self.track, t.border, 0.6)
    UI.TexColor(self.fill, t.accent, (self.thumb.hover or self.thumb.kitDrag) and 1 or 0.65)
end

function Bar:Sync()
    local source = self.kitSource
    local maxScroll = source:ScrollRange()
    local at = source:ScrollAt()
    if at > maxScroll then
        at = maxScroll
        source:ScrollSet(at)
    end
    if maxScroll < 1 then
        self:Hide()
        return
    end
    self:Show()
    local length = self:GetHeight() or 0
    local shown = source:ScrollView()
    local size = math.max(THUMB_MIN, length * shown / (shown + maxScroll))
    if size > length then size = length end
    local thumb = self.thumb
    thumb:SetHeight(UI.Snap(self, size))
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", self, "TOP", 0, -UI.Snap(self, (length - size) * at / maxScroll))
end

local function thumbDrag(thumb)
    local drag = thumb.kitDrag
    if not drag then return end
    local bar = thumb:GetParent()
    local travel = (bar:GetHeight() or 0) - (thumb:GetHeight() or 0)
    if travel <= 0 then return end
    local source = bar.kitSource
    source:ScrollSet(drag.from + (drag.y - cursorY(bar)) * source:ScrollRange() / travel)
    bar:Sync()
end

local function stopDrag(frame)
    local bar = frame.kitSource and frame or frame:GetParent()
    local thumb = bar.thumb
    thumb.kitDrag = nil
    thumb:SetScript("OnUpdate", nil)
    bar:PaintState()
end

local function thumbDown(thumb, mouse)
    if mouse ~= "LeftButton" then return end
    local bar = thumb:GetParent()
    thumb.kitDrag = { y = cursorY(bar), from = bar.kitSource:ScrollAt() }
    bar:PaintState()
    thumb:SetScript("OnUpdate", thumbDrag)
end

-- A click on the track above or below the thumb turns a page.
local function trackDown(bar, mouse)
    if mouse ~= "LeftButton" then return end
    local thumb = bar.thumb
    local y, top, bottom = cursorY(bar), thumb:GetTop(), thumb:GetBottom()
    if not top or not bottom then return end
    local source = bar.kitSource
    local step = bar.kitStep or UI.SCROLL_STEP
    local page = math.max(step, source:ScrollView() - step)
    if y > top then source:ScrollSet(source:ScrollAt() - page) elseif y < bottom then source:ScrollSet(source:ScrollAt() + page) end
    bar:Sync()
end

-- Makes the bar in `parent` for `source`. The caller anchors it.
function UI.NewScrollBar(ui, parent, source, step)
    local bar = UI.NewFrame("Frame", nil, parent)
    for key, fn in pairs(Bar) do bar[key] = fn end
    bar.ui, bar.kitSource, bar.kitStep = ui, source, step
    bar:SetWidth(UI.SCROLLBAR)
    bar:SetFrameLevel(parent:GetFrameLevel() + 10)
    bar:EnableMouse(true)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    UI.Stroke(bar.track, "width", 4)
    local thumb = UI.NewFrame("Frame", nil, bar)
    bar.thumb = thumb
    thumb:SetWidth(UI.Snap(bar, 6))
    thumb:SetHeight(THUMB_MIN)
    thumb:EnableMouse(true)
    bar.fill = thumb:CreateTexture(nil, "ARTWORK")
    bar.fill:SetAllPoints()
    UI.Hover(thumb, bar)
    thumb:SetScript("OnMouseDown", thumbDown)
    thumb:SetScript("OnMouseUp", stopDrag)
    bar:SetScript("OnHide", stopDrag)
    bar:SetScript("OnMouseDown", trackDown)
    ui:Paint(bar, function() bar:PaintState() end)
    bar:Hide()
    return bar
end

-- Scroll frames -------------------------------------------------------------------------

-- A ScrollFrame is its own bar's source.
local Scroll = {}

function Scroll:ScrollRange()
    return math.max(0, (self.content:GetHeight() or 0) - (self:GetHeight() or 0))
end
function Scroll:ScrollAt() return self:GetVerticalScroll() or 0 end
function Scroll:ScrollView() return self:GetHeight() or 0 end
-- On whole screen pixels, so what scrolls keeps the layout's pixel grid.
function Scroll:ScrollSet(value)
    local maxScroll = self:ScrollRange()
    if value > maxScroll then value = maxScroll end
    if value < 0 then value = 0 end
    self:SetVerticalScroll(UI.Snap(self, value))
end
function Scroll:ScrollTo(value)
    self:ScrollSet(value or 0)
    self.bar:Sync()
end
function Scroll:ScrollToTop() self:ScrollTo(0) end
function Scroll:Sync() self.bar:Sync() end

local function syncBar(frame)
    local scroll = frame.kitScroll or frame
    scroll.bar:Sync()
end

local function wheel(scroll, delta)
    scroll:ScrollSet(scroll:ScrollAt() - delta * UI.SCROLL_STEP)
    scroll.bar:Sync()
end

-- Whether something around `frame` would scroll under the wheel: a kit
-- scroll frame above it that takes the wheel and has further to go. A view
-- inside one (a list, a text area) leaves the wheel to it until taken hold
-- of; with none, the view takes the wheel as soon as the pointer is on it.
function UI.PageScrolls(frame)
    local parent = frame:GetParent()
    while parent do
        if parent.ScrollRange == Scroll.ScrollRange and parent:IsMouseWheelEnabled() and parent:ScrollRange() > 0 then
            return true
        end
        parent = parent:GetParent()
    end
    return false
end

-- A ScrollFrame and its content frame with the slim bar. Returns scroll,
-- content; `scroll:ScrollTo(y)`, `scroll:ScrollToTop()`, `scroll:Sync()`.
function UI.NewScroll(ui, parent)
    local scroll = UI.NewFrame("ScrollFrame", nil, parent)
    for key, fn in pairs(Scroll) do scroll[key] = fn end
    local content = UI.NewFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    content.kitScroll = scroll
    scroll:SetScrollChild(content)
    scroll.content = content
    local bar = UI.NewScrollBar(ui, scroll, scroll)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -2)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 2)
    scroll.bar = bar
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", wheel)
    scroll:SetScript("OnScrollRangeChanged", syncBar)
    scroll:SetScript("OnVerticalScroll", syncBar)
    scroll:HookScript("OnSizeChanged", syncBar)
    content:SetScript("OnSizeChanged", syncBar)
    return scroll, content
end
