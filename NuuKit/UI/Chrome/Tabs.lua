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
-- disabled }; value (the tab chosen first, else the first), bind, default,
-- onChange(key, tabs) (the player's choice only: a click or an arrow key),
-- padding (around the pages), pagePadding and gap (in each page).
-- `tabs:Page(key)` is the column that tab shows; it fills the room under
-- the strip.
--
-- The widget is a column of two parts it keeps for good: the strip (a row
-- of tab frames) and the holder (a column of pages). Tab frames and pages
-- are made the first time a spec needs that many and reused after; on
-- release, what the addon made in the pages goes back to its pools.
local TAB_HEIGHT = 30
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
end

local function paintTab(tab, t)
    UI.ApplyStyle(tab.label, "body", t, nil, true)
    paintTabState(tab, t)
    tab:Changed()
end

local function tabMeasure(tab)
    local width = UI.StringWidth(tab.label) + 28
    if tab.badge:IsShown() then width = width + 5 + tab.badge:NaturalWidth() end
    return math.ceil(width), TAB_HEIGHT
end

-- The caption and badge centred together.
local function tabSized(tab)
    local shift = 0
    if tab.badge:IsShown() then shift = -(5 + tab.badge:NaturalWidth()) / 2 end
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
        w.kitPages[k]:SetShown(k == key)
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
    tab = CreateFrame("Button", nil, w.strip)
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
    -- Hover repaints the tab alone (its own PaintState).
    UI.Hover(tab)
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
    stack = true, fills = true,
    Build = function(w)
        local ui = w.ui
        w:SetSize(1, 1)
        UI.MakeStack(ui, w, "column", NO_GAP)

        local strip = UI.Part(ui, w, "row", { gap = 2, padding = 0 }, { height = TAB_HEIGHT })
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
        -- A released stack gave its parts up: they come back.
        if #w.kitChildren == 0 then
            w.strip:Show()
            w.holder:Show()
            w:Append(w.strip)
            w:Append(w.holder)
        end
        emptyMap(w.kitTabs)
        emptyMap(w.kitPages)
        empty(w.kitOrder)
        empty(w.strip.kitChildren)
        empty(w.holder.kitChildren)
        local count = 0
        for index, entry in ipairs(spec) do
            count = index
            local tab = tabFrame(w, index)
            tab.kitPooled = nil
            tab.kitKey = entry.key
            tab.kitSelected, tab.hover = false, nil
            tab.label:SetText(entry.caption or entry.key)
            tab.badge:SetShown(entry.badge ~= nil)
            if entry.badge ~= nil then tab.badge:SetText(tostring(entry.badge)) end
            if entry.disabled then tab:Disable() else tab:Enable() end
            tab.kitNatW, tab.kitNatH = nil, nil
            tab:Show()
            UI.RegisterFocusable(ui, tab, false)
            w.strip:Append(tab)

            local page = pageFrame(w, index)
            UI.SetStack(page, "column", { gap = spec.gap or 8, padding = spec.pagePadding or 0 })
            page.kitGrow = 1
            page:Hide()
            w.holder:Append(page)

            w.kitTabs[entry.key] = tab
            w.kitPages[entry.key] = page
            w.kitOrder[index] = entry.key
        end
        -- Frames this spec does not use wait, hidden, for a longer one.
        for index = count + 1, #w.kitTabFrames do
            local tab = w.kitTabFrames[index]
            tab:Hide()
            tab.kitParent, tab.kitPooled = nil, true
            w.kitPageFrames[index]:Hide()
            w.kitPageFrames[index].kitParent = nil
        end
        w.kitChosen = nil
        local value = UI.InitValue(w, spec)
        choose(w, w.kitTabs[value] and value or w.kitOrder[1], false)
    end,
    Release = function(w)
        for index, page in ipairs(w.kitPageFrames) do
            page:ReleaseChildren()
            page:Hide()
            w.kitTabFrames[index].kitPooled = true
        end
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
