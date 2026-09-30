local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local types = UI.types

-- Tabs ----------------------------------------------------------------------------

-- A strip of tabs over pages. Tabs are not
-- buttons: a caption with an accent line under the chosen one, on a
-- hairline, so they never read as actions.
--
-- Spec: the entries are the array part, each { key, caption, badge,
-- disabled, tooltip }; value (the tab chosen first, else the first), bind,
-- default, onChange(key, tabs) (the player's choice only: a click or an
-- arrow key), padding (around the pages), pagePadding and gap (in each
-- page), rule (false: no hairline under the strip, as in a window's band).
-- `tabs:Page(key)` is the column that tab shows; it fills the room under
-- the strip.
--
-- For tabs that stand for things the player opens and shuts (documents,
-- guides) rather than parts of one window: onClose(key, tabs) puts a close
-- mark on every tab, shown while the pointer is on the tab, and hears its
-- click (the addon takes the tab away by making the tabs again); divided
-- puts a thin line between each two tabs, so a strip of them reads as tabs
-- with nothing under it; pages = false makes the strip alone, with no pages
-- under it; compact a lower strip; maxTabWidth cuts a longer caption short
-- with "..." (the entry's tooltip can carry the whole of it).
--
-- The widget is a column of two parts it keeps for good: the strip (a row
-- of tab frames) and the holder (a column of pages). Tab frames and pages
-- are made the first time a spec needs that many and reused after; on
-- release, what the addon made in the pages goes back to its pools.
local TAB_HEIGHT, COMPACT_HEIGHT = 30, 24
local STRIP_LAYOUT, COMPACT_LAYOUT = { height = TAB_HEIGHT }, { height = COMPACT_HEIGHT }
-- The close mark's square, and the width it adds to its tab.
local CLOSE_SIZE, CLOSE_ROOM = 16, 12
local TAB_LAYOUT = {}
local NO_GAP = { gap = 0 }

local function paintTabState(tab, t)
    local color
    if not tab:IsEnabled() then
        color = t.muted45
    elseif tab.kitSelected or tab.hover then
        color = t.text
    else
        color = t.muted
    end
    UI.TextColor(tab.label, color)
    UI.TexColor(tab.line, tab.kitSelected and t.accent or nil)
    -- The close mark is there only under the pointer. It fades rather than
    -- hides, so the pointer moving from the tab onto it still finds it.
    local close = tab.closeButton
    if close and tab.kitClosable then close:SetAlpha((tab.hover or close.hover) and 1 or 0) end
end

local function paintTab(tab, t)
    UI.ApplyStyle(tab.label, "body", t, nil, true)
    if tab.divider then UI.TexColor(tab.divider, t.muted45) end
    paintTabState(tab, t)
    tab:Changed()
end

-- The caption, cut short with "..." when it is wider than `room`.
local function fitCaption(tab, room)
    local label, caption = tab.label, tab.kitCaption
    label:SetText(caption)
    if not room or UI.StringWidth(label) <= room then return end
    local low, high = 0, #caption
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        label:SetText(caption:sub(1, mid) .. "...")
        if UI.StringWidth(label) <= room then low = mid else high = mid - 1 end
    end
    label:SetText((caption:sub(1, low):gsub("%s+$", "")) .. "...")
end

local function tabMeasure(tab)
    local w = tab.kitTabsWidget
    local extra = 28
    if tab.badge:IsShown() then extra = extra + 5 + tab.badge:NaturalWidth() end
    if tab.kitClosable then extra = extra + CLOSE_ROOM end
    fitCaption(tab, w.kitMaxTabWidth and (w.kitMaxTabWidth - extra))
    return math.ceil(UI.StringWidth(tab.label) + extra), w.kitTabHeight
end

-- The caption and badge centred together, clear of the close mark.
local function tabSized(tab)
    local shift = 0
    if tab.badge:IsShown() then shift = -(5 + tab.badge:NaturalWidth()) / 2 end
    if tab.kitClosable then shift = shift - CLOSE_ROOM / 2 end
    tab.label:ClearAllPoints()
    tab.label:SetPoint("CENTER", tab, "CENTER", UI.Snap(tab, shift), 1)
end

-- Chooses `key`. Only the player's choice is committed and heard.
local function choose(w, key, byPlayer)
    if not w.kitTabs[key] or w.kitChosen == key then return end
    w.kitChosen = key
    local t = w.ui.tokens
    for _, k in ipairs(w.kitOrder) do
        local tab = w.kitTabs[k]
        tab.kitSelected = k == key
        paintTabState(tab, t)
        local page = w.kitPages[k]
        if page then page:SetShown(k == key) end
    end
    UI.Invalidate(w.holder)
    if byPlayer then UI.Commit(w, key) end
end

local function tabClicked(tab)
    if not tab:IsEnabled() then return end
    local w = tab.kitTabsWidget
    UI.ClearTypingFocus(nil)
    if tab.kitKey ~= w.kitChosen then UI.ClickSound() end
    choose(w, tab.kitKey, true)
end

-- The pointer on the close mark keeps it shown; leaving it for somewhere
-- off the tab puts it away.
local function closeHovered(button)
    local tab = button.kitTab
    paintTabState(tab, tab.ui.tokens)
end

local function closeClicked(button)
    local tab = button.kitTab
    local w = tab.kitTabsWidget
    UI.ClearTypingFocus(nil)
    if w.kitOnClose then w.kitOnClose(tab.kitKey, w) end
end

-- Left / up and right / down move to the next tab that can be chosen, and
-- the focus ring with it.
local function tabArrow(tab, key)
    local w = tab.kitTabsWidget
    local order = w.kitOrder
    local count = #order
    local step = (key == "LEFT" or key == "UP") and -1 or 1
    local at = 1
    for index, k in ipairs(order) do if k == tab.kitKey then at = index end end
    for offset = 1, count - 1 do
        local nextKey = order[((at - 1 + step * offset) % count) + 1]
        local target = w.kitTabs[nextKey]
        if target:IsEnabled() then
            choose(w, nextKey, true)
            local win = UI.WindowOf(tab)
            if win then UI.FocusWidget(win, target) end
            return
        end
    end
end

-- The tab frame at `index`, made the first time it is needed.
local function tabFrame(w, index)
    local tab = w.kitTabFrames[index]
    if tab then return tab end
    local ui = w.ui
    tab = UI.NewFrame("Button", nil, w.strip)
    UI.Adopt(tab, "Tab", { UI.Widget }, { Measure = tabMeasure, Sized = tabSized, Paint = paintTab,
        PaintState = paintTabState, kitKeyArrow = tabArrow })
    tab.ui, tab.kitTabsWidget, tab.kitLayout, tab.kitStretch = ui, w, TAB_LAYOUT, false
    tab:SetHeight(TAB_HEIGHT)
    tab.label = UI.NewText(tab)
    tab.label:SetPoint("CENTER", tab, "CENTER", 0, 1)
    tab.line = tab:CreateTexture(nil, "ARTWORK")
    tab.line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    tab.line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
    UI.Stroke(tab.line, "height", 2)
    tab.badge = UI.Make(ui, "Tag", tab, { "", tone = "estimate" })
    tab.badge.kitFree = true
    tab.badge:SetPoint("LEFT", tab.label, "RIGHT", 5, 0)
    -- Hover repaints the tab alone (its own PaintState), and shows the
    -- entry's tooltip when it has one.
    UI.Hover(tab)
    UI.HookTooltip(tab)
    tab:SetScript("OnClick", tabClicked)
    -- Painted on a look change and laid out again on a change of scale.
    ui.widgets[tab] = true
    w.kitTabFrames[index] = tab
    return tab
end

-- The page at `index`, made the first time it is needed.
local function pageFrame(w, index)
    local page = w.kitPageFrames[index]
    if page then return page end
    page = UI.Part(w.ui, w.holder, "column", {})
    page.kitFillChildren = true
    w.kitPageFrames[index] = page
    return page
end

local function empty(list)
    for index = #list, 1, -1 do list[index] = nil end
end

local function emptyMap(map)
    for key in pairs(map) do map[key] = nil end
end

UI.Define("Tabs", {
    -- A strip alone has nothing to fill the room with.
    stack = true, fills = function(spec) return spec.pages ~= false end,
    Build = function(w)
        local ui = w.ui
        w:SetSize(1, 1)
        UI.MakeStack(ui, w, "column", NO_GAP)

        local strip = UI.Part(ui, w, "row", { gap = 2, padding = 0 }, STRIP_LAYOUT)
        strip.rule = strip:CreateTexture(nil, "BACKGROUND")
        strip.rule:SetPoint("BOTTOMLEFT")
        strip.rule:SetPoint("BOTTOMRIGHT")
        UI.Hairline(strip.rule, "height")
        w.strip = strip

        local holder = UI.Part(ui, w, "column", NO_GAP)
        holder.kitGrow = 1
        holder.kitFillChildren = true
        w.holder = holder

        w.kitTabFrames, w.kitPageFrames = {}, {}
        w.kitTabs, w.kitPages, w.kitOrder = {}, {}, {}
    end,
    Init = function(w, spec)
        local ui = w.ui
        UI.SetStack(w, "column", NO_GAP)
        UI.SetStack(w.holder, "column", { gap = 0, padding = spec.padding or 0 })
        w.strip.rule:SetShown(spec.rule ~= false)
        local paged, height = spec.pages ~= false, spec.compact and COMPACT_HEIGHT or TAB_HEIGHT
        w.kitTabHeight, w.kitMaxTabWidth, w.kitOnClose = height, spec.maxTabWidth, spec.onClose
        local divided = spec.divided and true or false
        w.strip.kitLayout = spec.compact and COMPACT_LAYOUT or STRIP_LAYOUT
        -- A released stack gave its parts up: they come back.
        if #w.kitChildren == 0 then
            w.strip:Show()
            w:Append(w.strip)
            w:Append(w.holder)
        end
        emptyMap(w.kitTabs)
        emptyMap(w.kitPages)
        empty(w.kitOrder)
        empty(w.strip.kitChildren)
        empty(w.holder.kitChildren)
        w.holder:SetShown(paged)
        local count = 0
        for index, entry in ipairs(spec) do
            count = index
            local tab = tabFrame(w, index)
            tab.kitPooled = nil
            tab.kitKey = entry.key
            tab.kitSelected, tab.hover = false, nil
            tab.kitCaption = entry.caption or entry.key
            tab.label:SetText(tab.kitCaption)
            tab.tooltip = entry.tooltip
            tab:SetHeight(height)
            tab.kitClosable = spec.onClose ~= nil
            if tab.kitClosable and not tab.closeButton then
                local close = UI.Make(ui, "GlyphButton", tab, { "close", size = CLOSE_SIZE, glyphSize = 7, onClick = closeClicked })
                close.kitFree = true
                close.kitTab = tab
                close:SetPoint("RIGHT", tab, "RIGHT", -6, 0)
                close:HookScript("OnEnter", closeHovered)
                close:HookScript("OnLeave", closeHovered)
                tab.closeButton = close
            end
            if tab.closeButton then tab.closeButton:SetShown(tab.kitClosable) end
            -- The hairline at a tab's left, from the second tab on.
            if divided and index > 1 and not tab.divider then
                tab.divider = tab:CreateTexture(nil, "ARTWORK")
                tab.divider:SetPoint("LEFT", tab, "LEFT", -1, 0)
                tab.divider:SetHeight(14)
                UI.Hairline(tab.divider, "width")
                UI.TexColor(tab.divider, ui.tokens.muted45)
            end
            if tab.divider then tab.divider:SetShown(divided and index > 1) end
            tab.badge:SetShown(entry.badge ~= nil)
            if entry.badge ~= nil then tab.badge:SetText(tostring(entry.badge)) end
            if entry.disabled then tab:Disable() else tab:Enable() end
            tab.kitNatW, tab.kitNatH = nil, nil
            tab:Show()
            UI.RegisterFocusable(ui, tab, false)
            w.strip:Append(tab)

            if paged then
                local page = pageFrame(w, index)
                UI.SetStack(page, "column", { gap = spec.gap or 8, padding = spec.pagePadding or 0 })
                page.kitGrow = 1
                page:Hide()
                w.holder:Append(page)
                w.kitPages[entry.key] = page
            end

            w.kitTabs[entry.key] = tab
            w.kitOrder[index] = entry.key
        end
        -- Frames this spec does not use wait, hidden, for a longer one.
        for index = count + 1, #w.kitTabFrames do
            local tab = w.kitTabFrames[index]
            tab:Hide()
            tab.kitParent, tab.kitPooled = nil, true
            tab.tooltip = nil
        end
        for index = paged and count + 1 or 1, #w.kitPageFrames do
            w.kitPageFrames[index]:Hide()
            w.kitPageFrames[index].kitParent = nil
        end
        w.kitChosen = nil
        local value = UI.InitValue(w, spec)
        choose(w, w.kitTabs[value] and value or w.kitOrder[1], false)
    end,
    Release = function(w)
        for _, page in ipairs(w.kitPageFrames) do
            page:ReleaseChildren()
            page:Hide()
        end
        for _, tab in ipairs(w.kitTabFrames) do
            tab.kitPooled = true
            tab.tooltip = nil
        end
        w.kitOnClose = nil
    end,
    methods = {
        -- The column a tab shows.
        Page = function(self, key) return self.kitPages[key] end,
        -- Chooses a tab from code: onChange does not hear it. With a spec
        -- it is the Select maker, as on any column.
        Select = function(self, key)
            if type(key) == "table" and UI.Makers.Select then return UI.Makers.Select(self, key) end
            choose(self, key == nil and self.kitOrder[1] or key, false)
        end,
        SetValue = function(self, key) choose(self, key == nil and self.kitOrder[1] or key, false) end,
        GetValue = function(self) return self.kitChosen end,
        GetSelected = function(self) return self.kitChosen end,
        -- A small count beside a tab's caption; nil takes it away.
        SetBadge = function(self, key, text)
            local tab = self.kitTabs[key]
            if not tab then return end
            tab.badge:SetShown(text ~= nil)
            if text ~= nil then tab.badge:SetText(tostring(text)) end
            tab:Changed()
        end,
        SetTabEnabled = function(self, key, enabled)
            local tab = self.kitTabs[key]
            if not tab then return end
            if enabled then tab:Enable() else tab:Disable() end
            paintTabState(tab, self.ui.tokens)
        end,
        Paint = function(self, t)
            UI.TexColor(self.strip.rule, t.hairline)
            for _, key in ipairs(self.kitOrder) do paintTab(self.kitTabs[key], t) end
        end,
    },
})

-- Disclosure ------------------------------------------------------------------------

-- A button that folds a part open or shut: a chevron before the caption,
-- right while folded and down while open; the open one wears the selected
-- look. Spec: a button's ([1] the caption, tone, style, width...), open,
-- onToggle(open, button) (the player's click only). onClick is not used.
local buttonDef = types.Button

local disclosureMethods = {}
for key, fn in pairs(buttonDef.methods) do disclosureMethods[key] = fn end

function disclosureMethods:SetOpen(open)
    self.kitOpen = open and true or false
    self.foldedGlyph:SetShown(not self.kitOpen)
    self.openGlyph:SetShown(self.kitOpen)
    self.glyph = self.kitOpen and self.openGlyph or self.foldedGlyph
    self.kitPressParts = self.kitOpen and self.kitPartsOpen or self.kitPartsFolded
    self:SetActive(self.kitOpen)
end

function disclosureMethods:IsOpen() return self.kitOpen end

function disclosureMethods:Activate()
    self:SetOpen(not self.kitOpen)
    if self.kitOnToggle then self.kitOnToggle(self.kitOpen, self) end
end

-- The chevron sits at the left, whatever the width.
function disclosureMethods:Sized(width, height)
    buttonDef.methods.Sized(self, width, height)
    local x = -(width or self:GetWidth() or 0) / 2 + 12
    self.foldedGlyph:Offset(x, 0)
    self.openGlyph:Offset(x, 0)
end

-- The chevron in the caption's colour.
function disclosureMethods:PaintState(t)
    buttonDef.methods.PaintState(self, t)
    local ink = self.kitInk
    ink[1], ink[2], ink[3], ink[4] = self.label:GetTextColor()
    self.foldedGlyph:SetColor(ink)
    self.openGlyph:SetColor(ink)
end

UI.Define("Disclosure", UI.ClickableType({
    stretch = false,
    Build = function(w)
        buttonDef.Build(w)
        w.kitTextPad, w.kitTextReserve = 34, 34
        w.foldedGlyph = UI.NewGlyph(w, "next", 8, 1.6)
        w.openGlyph = UI.NewGlyph(w, "down", 8, 1.6)
        w.label:ClearAllPoints()
        w.label:SetPoint("LEFT", w, "LEFT", 22, 0)
        w.kitPartsOpen = { w.label, w.openGlyph }
        w.kitPartsFolded = { w.label, w.foldedGlyph }
        w.kitInk = { 1, 1, 1, 1 }
    end,
    Init = function(w, spec)
        buttonDef.Init(w, spec)
        w.kitClick = nil
        w.kitOnToggle = spec.onToggle
        w:SetOpen(spec.open)
    end,
    methods = disclosureMethods,
}))
