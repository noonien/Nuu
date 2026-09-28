local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI1 = Kit.UI1 or {}
local UI = Kit.UI1

-- Keyboard focus in a window, as in UI/Chrome/Window.lua. What can take the
-- focus registers as it is made (UI.RegisterFocusable, in Core). By default
-- Tab moves through a window's text fields; with full keyboard control
-- (window:TakeKeyboard) it reaches buttons, toggles, tabs, selects and
-- sliders too, and a ring shows where it is. A focused widget may answer
-- `w:kitKeyPress(key)` (Enter, Space; else it is clicked) and
-- `w:kitKeyArrow(key)` (the arrows).

local function reachable(w)
    if w.kitPooled or not w:IsVisible() then return false end
    if w.IsEnabled and not w:IsEnabled() then return false end
    return true
end

-- The fields (or, with full keyboard control, every focusable) of a window,
-- in the order they were made; a window's own TabOrder replaces it.
function UI.FocusOrder(win, fieldsOnly)
    if win.kitTabOrder then return win.kitTabOrder end
    local list = {}
    for w in pairs(win.ui.focusables) do
        if (not fieldsOnly or w.kitIsField) and not w.kitPooled and UI.WindowOf(w) == win then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a.kitSerial < b.kitSerial end)
    return list
end

-- From `current`, the next reachable entry of the window's order.
function UI.NextFocus(win, current, step, fieldsOnly)
    local list = UI.FocusOrder(win, fieldsOnly)
    local count = #list
    if count == 0 then return nil end
    local at = 0
    for index, w in ipairs(list) do if w == current then at = index end end
    for offset = 1, count do
        local candidate = list[((at - 1 + step * offset) % count) + 1]
        if candidate ~= current and reachable(candidate) then return candidate end
    end
    return nil
end

-- Moves the focus ring to `w`, or away.
function UI.FocusWidget(win, w)
    win.kitFocused = w
    local ring = win.focusRing
    if not w then
        if ring then ring:Hide() end
        return
    end
    if not ring then
        ring = CreateFrame("Frame", nil, win)
        ring.plate = UI.NewPlate(ring, "OVERLAY")
        win.focusRing = ring
        win.ui:Paint(ring, function(t) ring.plate:Flat(nil, t.accent) end)
    end
    ring:SetFrameLevel((w:GetFrameLevel() or 1) + 5)
    ring:ClearAllPoints()
    local gap = UI.Snap(win, 3)
    ring:SetPoint("TOPLEFT", w, "TOPLEFT", -gap, gap)
    ring:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", gap, -gap)
    ring:Show()
    if w.kitIsField and w.SetFocus then w:SetFocus() end
end

-- A key in a window under full keyboard control; true when the kit used it.
function UI.WindowKey(win, key)
    local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
    local focused = win.kitFocused
    if key == "TAB" then
        UI.FocusWidget(win, UI.NextFocus(win, focused, shift and -1 or 1, false))
        return true
    elseif key == "ESCAPE" then
        win:Hide()
        return true
    elseif focused and (key == "ENTER" or key == "SPACE") then
        if focused.kitKeyPress then focused:kitKeyPress(key) elseif focused.Click then focused:Click() end
        return true
    elseif focused and focused.kitKeyArrow and (key == "LEFT" or key == "RIGHT" or key == "UP" or key == "DOWN") then
        focused:kitKeyArrow(key)
        return true
    end
    return false
end
