local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Tabs ----------------------------------------------------------------------------

-- A strip of tabs over pages. Tabs are not buttons: a caption with an accent
-- line under the chosen one, on a hairline, so they never read as actions.
-- `list` is { { key, caption, badge, disabled } }; `opts.value` the first
-- chosen, `opts.onChange(key)` told of a change. `tabs:Page(key)` is the
-- column that tab shows.
local TAB_HEIGHT = 30

local function paintTab(tab, t)
    local on = tab.kitSelected
    local color
    if not tab:IsEnabled() then
        color = t.muted45
    elseif on or tab.hover then
        color = t.text
    else
        color = t.muted
    end
    UI.ApplyStyle(tab.label, "body", t, color)
    UI.TexColor(tab.line, on and t.accent or nil)
    tab:SetWidth(tab:KitNaturalWidth())
end

UI.Define("Tabs", function(ui, parent, list, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    UI.MakeContainer(ui, frame, "column", { gap = 0 })

    local strip = CreateFrame("Frame", nil, frame)
    strip:SetSize(1, TAB_HEIGHT)
    UI.MakeContainer(ui, strip, "row", { gap = 2, padding = 0 })
    strip.kitLayout = { height = TAB_HEIGHT }
    strip.rule = strip:CreateTexture(nil, "BACKGROUND")
    strip.rule:SetPoint("BOTTOMLEFT")
    strip.rule:SetPoint("BOTTOMRIGHT")
    UI.Hairline(strip.rule, "height")
    frame:KitAppend(strip)

    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(1, 1)
    UI.MakeContainer(ui, holder, "column", { gap = 0, padding = opts.padding or 0 })
    holder.kitLayout = { grow = true }
    holder.kitFillChildren = true
    frame:KitAppend(holder)

    frame.tabs, frame.pages, frame.order = {}, {}, {}

    local function select(key, silent)
        if not frame.tabs[key] or frame.selected == key then return end
        frame.selected = key
        for k, tab in pairs(frame.tabs) do
            tab.kitSelected = k == key
            tab:Repaint()
            frame.pages[k]:SetShown(k == key)
        end
        UI.Invalidate(holder)
        if not silent and opts.onChange then opts.onChange(key) end
    end

    for _, entry in ipairs(list or {}) do
        local tab = CreateFrame("Button", nil, strip)
        tab:SetHeight(TAB_HEIGHT)
        tab.kitStretch = false
        tab.kitKey = entry.key
        tab.label = UI.NewText(tab)
        tab.label:SetPoint("CENTER", tab, "CENTER", 0, 1)
        tab.label:SetText(entry.caption or entry.key)
        tab.line = tab:CreateTexture(nil, "ARTWORK")
        tab.line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        tab.line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        UI.Stroke(tab.line, "height", 2)
        tab.badge = ui:Tag(tab, "", { tone = "estimate" })
        tab.badge:SetPoint("LEFT", tab.label, "RIGHT", 5, 0)
        tab.badge:SetShown(entry.badge ~= nil)
        if entry.badge then tab.badge:SetText(tostring(entry.badge)) end
        tab.KitNaturalWidth = function(t)
            local w = UI.StringWidth(t.label) + 28
            if t.badge:IsShown() then w = w + 5 + (t.badge:GetWidth() or 0) end
            return math.ceil(w)
        end
        tab.KitNaturalHeight = function() return TAB_HEIGHT end
        tab:SetScript("OnEnter", function(t) t.hover = true; t:Repaint() end)
        tab:SetScript("OnLeave", function(t) t.hover = false; t:Repaint() end)
        tab:SetScript("OnClick", function(t)
            UI.ClearTypingFocus(nil)
            if t.kitKey ~= frame.selected then UI.ClickSound() end
            select(t.kitKey)
        end)
        tab.kitKeyArrow = function(t, key)
            local step = (key == "LEFT" or key == "UP") and -1 or 1
            local at = 1
            for index, k in ipairs(frame.order) do if k == t.kitKey then at = index end end
            local nextKey = frame.order[((at - 1 + step) % #frame.order) + 1]
            select(nextKey)
            local win = UI.WindowOf(t)
            if win then UI.FocusWidget(win, frame.tabs[nextKey]) end
        end
        UI.RegisterFocusable(ui, tab, false)
        if entry.disabled then tab:Disable() end
        ui:Finish(tab, {}, paintTab)
        strip:KitAppend(tab)
        frame.tabs[entry.key] = tab
        table.insert(frame.order, entry.key)

        local page = CreateFrame("Frame", nil, holder)
        page:SetSize(1, 1)
        UI.MakeContainer(ui, page, "column", { gap = opts.gap or 8, padding = opts.pagePadding or 0 })
        page.kitLayout = { grow = true }
        page.kitFillChildren = true
        page:Hide()
        ui:Finish(page, page.kitLayout)
        holder:KitAppend(page)
        frame.pages[entry.key] = page
    end

    function frame:Page(key) return self.pages[key] end
    function frame:Select(key) select(key, true) end
    function frame:GetSelected() return self.selected end
    function frame:SetBadge(key, text)
        local tab = self.tabs[key]
        if not tab then return end
        tab.badge:SetShown(text ~= nil)
        if text ~= nil then tab.badge:SetText(tostring(text)) end
        tab:Repaint()
        UI.Invalidate(strip)
    end
    function frame:SetTabEnabled(key, enabled)
        local tab = self.tabs[key]
        if not tab then return end
        if enabled then tab:Enable() else tab:Disable() end
        tab:Repaint()
    end

    select(opts.value or frame.order[1], true)
    return ui:Finish(frame, opts, function() UI.TexColor(strip.rule, ui.tokens.hairline) end)
end, true)

-- Disclosure ------------------------------------------------------------------------

-- A button that folds a part open or shut: a chevron before the caption,
-- right while folded and down while open; the open one wears the selected
-- look. `opts.open`, `opts.onToggle(open)`.
UI.Define("Disclosure", function(ui, parent, caption, opts)
    opts = opts or {}
    local copy = {}
    for key, value in pairs(opts) do copy[key] = value end
    copy.onClick = nil
    local button = UI.Proto.Button(ui, parent, caption, copy)
    button.kitTextPad = 34
    local folded = UI.NewGlyph(button, "next", 8, 1.6)
    local open = UI.NewGlyph(button, "down", 8, 1.6)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", 22, 0)
    local function place()
        local x = -(button:GetWidth() or 0) / 2 + 12
        folded:Offset(x, 0)
        open:Offset(x, 0)
    end
    button:HookScript("OnSizeChanged", place)
    button.SetOpen = function(b, value)
        b.kitOpen = value and true or false
        folded:SetShown(not b.kitOpen)
        open:SetShown(b.kitOpen)
        b.glyph = b.kitOpen and open or folded
        b.kitPressParts = { b.label, b.glyph }
        b:SetActive(b.kitOpen)
    end
    button.IsOpen = function(b) return b.kitOpen end
    button.kitClick = function(b)
        b:SetOpen(not b.kitOpen)
        if opts.onToggle then opts.onToggle(b.kitOpen) end
    end
    button:SetOpen(opts.open)
    button:Fit()
    place()
    return button
end)
