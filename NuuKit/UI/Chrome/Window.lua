local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto
local Container = UI.Container

-- Windows and in-play panels.
--
-- A window is movable by its title band, clamped to the screen, closes on
-- Escape, and wears the look's chrome: flat colours, or an art theme's
-- tiled background and 9-slice frame. Its body is a column; anything made on
-- the window is made in the body, and a column, panes or tabs made straight
-- on it fill it.
--
-- With `place` (a table the addon keeps) and `key`, its position, size and
-- collapsed state go into place[key]; the kit writes nothing else.

local BAND, STATUS, GRIP = 30, 24, 14
local ART_CORNER, ART_INSET = 24, 17

local function frameName(ui, key)
    if not key then return nil end
    local owner = ui.owner and ui.owner.name or "Nuu"
    return (tostring(owner) .. "_" .. tostring(key) .. "_Window"):gsub("[^%w_]", "")
end

local function save(win)
    local place, key = win.kitPlace, win.kitKey
    if not place or not key then return end
    local left, top = win:GetLeft(), win:GetTop()
    if not left or not top then return end
    local entry = place[key] or {}
    entry.x, entry.y = UI.Snap(win, left), UI.Snap(win, top)
    entry.w = UI.Snap(win, win.kitCollapsed and win.kitExpandedWidth or win:GetWidth())
    entry.h = UI.Snap(win, win.kitCollapsed and win.kitExpandedHeight or win:GetHeight())
    entry.collapsed = win.kitCollapsed or nil
    place[key] = entry
    -- Anchored by its top-left corner, so a change of size leaves it put.
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", entry.x, entry.y)
end

-- Dragging by hand ------------------------------------------------------------------

-- Moves or sizes `frame` while `handle` is held, ported from OpenRoad's
-- tracker grip rather than left to StartMoving / StartSizing: each frame the
-- frame is put where it was when the button went down plus how far the
-- cursor has gone since, so no motion is lost and the point grabbed stays
-- under the cursor. `mode`: "move", "size" (the right and bottom edges) or
-- "width". `opts`: can() false refuses a drag, bounds a table of minW, minH,
-- maxW, maxH, onStop(frame) when let go.
function UI.DragFrame(handle, frame, mode, opts)
    opts = opts or {}
    local driver = CreateFrame("Frame", nil, handle)
    driver:Hide()
    local from
    local function cursor()
        local x, y = GetCursorPosition()
        local scale = frame:GetEffectiveScale() or 1
        return x / scale, y / scale
    end
    local function clamp(value, low, high)
        if low and value < low then value = low end
        if high and value > high then value = high end
        return value
    end
    local function stop()
        if not from then return end
        from = nil
        driver:Hide()
        if opts.onStop then opts.onStop(frame) end
    end
    driver:SetScript("OnUpdate", function()
        if not from then driver:Hide(); return end
        -- The release may land off the handle, which then never hears it.
        if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then stop(); return end
        local x, y = cursor()
        local dx, dy = x - from.x, y - from.y
        if mode == "move" then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", UI.Snap(frame, from.left + dx), UI.Snap(frame, from.top + dy))
        else
            local b = opts.bounds or {}
            frame:SetWidth(UI.Snap(frame, clamp(from.w + dx, b.minW, b.maxW)))
            if mode == "size" then frame:SetHeight(UI.Snap(frame, clamp(from.h - dy, b.minH, b.maxH))) end
        end
    end)
    handle:HookScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or type(GetCursorPosition) ~= "function" then return end
        if opts.can and not opts.can() then return end
        local left, top = frame:GetLeft(), frame:GetTop()
        if not left or not top then return end
        local x, y = cursor()
        from = { x = x, y = y, left = left, top = top, w = frame:GetWidth(), h = frame:GetHeight() }
        -- Held by its top-left corner, so sizing grows it right and down.
        left, top = UI.Snap(frame, left), UI.Snap(frame, top)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        driver:Show()
    end)
    handle:HookScript("OnMouseUp", function(_, button) if button == "LeftButton" then stop() end end)
    handle:HookScript("OnHide", stop)
end

local function setBounds(win, opts)
    local minW, minH = opts.minWidth or 200, opts.minHeight or 120
    local maxW, maxH = opts.maxWidth or 2000, opts.maxHeight or 2000
    win.kitBounds = { minW = minW, minH = minH, maxW = maxW, maxH = maxH }
    if win.SetResizeBounds then
        pcall(win.SetResizeBounds, win, minW, minH, maxW, maxH)
    else
        if win.SetMinResize then pcall(win.SetMinResize, win, minW, minH) end
        if win.SetMaxResize then pcall(win.SetMaxResize, win, maxW, maxH) end
    end
end

-- Places the band, body and status strip inside the chrome's inset.
-- Every offset is snapped to whole screen pixels: the layout inside the body
-- is snapped relative to the body, so the body must sit on the grid too, or
-- each edge in it is rounded at draw time and can round differently when
-- the body's height changes (a status line coming or going).
local function arrange(win)
    local snap = function(v) return UI.Snap(win, v) end
    local inset = snap(win.kitInset or 1)
    local band = win.band
    local bandHeight = band:IsShown() and snap(BAND) or 0
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -inset)
    band:SetPoint("TOPRIGHT", win, "TOPRIGHT", -inset, -inset)
    band:SetHeight(snap(BAND))
    local status = win.statusStrip
    local bottom = inset
    if status and status:IsShown() and not win.kitCollapsed then
        status:ClearAllPoints()
        status:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", inset, inset)
        status:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -inset, inset)
        status:SetHeight(snap(STATUS))
        bottom = inset + snap(STATUS)
    end
    win.body:ClearAllPoints()
    win.body:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -(inset + bandHeight))
    win.body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -inset, bottom)
    if win.grip then
        win.grip:ClearAllPoints()
        local corner = snap(math.max(1, inset - 6))
        win.grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -corner, corner)
    end
    UI.Invalidate(win.body)
end

local function paintWindow(win, t)
    local art = (not win.kitInPlay) and t.art or nil
    -- The background: an art theme's tile, or the flat plane.
    local tiled = art and art.background and UI.Tile(win.bg, art.background)
    if tiled then
        win.bg:SetVertexColor(1, 1, 1, t.look.opacity)
        win.bg:Show()
    else
        win.bg:Hide()
    end
    local framed = false
    if art and art.frame then
        if win.nineSpec ~= art.frame then
            if win.nine then win.nine:Hide() end
            win.nine = UI.NineSlice(win, "BORDER", art.frame, ART_CORNER, false)
            win.nineSpec = art.frame
        end
        framed = win.nine.loaded
        if framed then win.nine:Show() end
    elseif win.nine then
        win.nine:Hide()
    end
    local fill = win.kitInPlay and t.surfaceBg or t.windowBg
    if tiled then fill = nil end
    win.plate:Flat(fill, (not framed) and (win.kitInPlay and t.border or t.hairline) or nil)
    local inset = framed and ART_INSET or 1
    if inset ~= win.kitInset then
        win.kitInset = inset
        arrange(win)
    end

    -- The band: the art band, the flat band, or for an in-play panel a
    -- faint plate that shows while the cursor is on it.
    local banded = art and art.band and UI.Tile(win.bandBg, art.band)
    if banded then
        win.bandBg:SetVertexColor(1, 1, 1, 1)
    elseif win.kitInPlay then
        UI.TexColor(win.bandBg, win.band.hover and t.raisedBg or nil)
    else
        UI.TexColor(win.bandBg, t.bandBg)
    end
    UI.ApplyStyle(win.title, "window", t)
    UI.ApplyStyle(win.subtitle, "label", t)
    if win.statusStrip then
        UI.TexColor(win.statusStrip.bg, win.kitInPlay and t.raisedBg or t.bandBg)
        UI.TexColor(win.statusStrip.line, t.hairline)
        UI.ApplyStyle(win.statusStrip.text, "label", t)
    end
    if win.focusRing then win.focusRing.plate:Flat(nil, t.accent) end
end

-- Makes the window shell shared by Window and Panel.
local function shell(ui, opts, inPlay)
    local name = (not inPlay or opts.escape) and frameName(ui, opts.key) or nil
    local win = CreateFrame("Frame", name, opts.parent or UIParent)
    win.kitIsWindow, win.kitInPlay, win.ui = true, inPlay, ui
    win.kitKey, win.kitPlace = opts.key, opts.place
    win:SetFrameStrata(opts.strata or (inPlay and "MEDIUM" or "HIGH"))
    if win.SetToplevel then win:SetToplevel(true) end
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetSize(UI.Snap(win, opts.width or 400), UI.Snap(win, opts.height or 300))

    win.bg = win:CreateTexture(nil, "BACKGROUND", nil, -8)
    win.bg:SetAllPoints()
    win.bg:Hide()
    win.plate = UI.NewPlate(win, "BACKGROUND", -6)

    -- The band: title, subtitle, room for the addon's own controls, then the
    -- collapse and close marks. It is what the player drags.
    local band = CreateFrame("Frame", nil, win)
    band:SetHeight(BAND)
    win.band = band
    win.bandBg = band:CreateTexture(nil, "BACKGROUND")
    win.bandBg:SetAllPoints()
    band:EnableMouse(true)
    band:SetScript("OnEnter", function() band.hover = true; win:Repaint() end)
    band:SetScript("OnLeave", function() band.hover = false; win:Repaint() end)
    band:SetScript("OnMouseDown", function() UI.ClearTypingFocus(nil) end)
    UI.DragFrame(band, win, "move", { can = function() return not win.kitLocked end, onStop = save })

    win.title = UI.NewText(band)
    win.title:SetPoint("LEFT", band, "LEFT", 12, 0)
    win.title:SetText(opts.title or "")
    win.subtitle = UI.NewText(band)
    win.subtitle:SetPoint("LEFT", win.title, "RIGHT", 8, 0)
    win.subtitle:SetText(opts.subtitle or "")

    local right = -6
    if opts.close ~= false and not inPlay then
        win.closeButton = ui:GlyphButton(band, "close", { size = 22, glyphSize = 9, boxed = true, bright = true,
            tooltip = nil, onClick = function() win:Hide() end })
        win.closeButton:SetPoint("RIGHT", band, "RIGHT", right, 0)
        right = right - 26
    end
    if opts.collapsible then
        win.collapseButton = ui:GlyphButton(band, "up", { size = 22, glyphSize = 9, onClick = function() win:SetCollapsed(not win.kitCollapsed) end })
        win.collapseButton:SetPoint("RIGHT", band, "RIGHT", right, 0)
        -- Both marks made once; the folded one points down.
        win.collapseButton.kitUp = win.collapseButton.glyph
        win.collapseButton.kitDown = UI.NewGlyph(win.collapseButton, "down", 9, 1.6)
        win.collapseButton.kitDown:SetShown(false)
        right = right - 24
    end
    -- The addon's own controls in the band, right of the title.
    local header = CreateFrame("Frame", nil, band)
    header:SetHeight(BAND)
    UI.MakeContainer(ui, header, "row", { gap = 4, align = "right" })
    header:SetPoint("TOPRIGHT", band, "TOPRIGHT", right, 0)
    header:SetPoint("BOTTOMLEFT", win.subtitle, "BOTTOMRIGHT", 8, -((BAND - 12) / 2))
    win.header = header

    if inPlay and not opts.title and not opts.collapsible then band:Hide() end

    -- The body: a column that fills the window.
    local body = CreateFrame("Frame", nil, win)
    -- What does not fit is cut at the window's edge, not drawn over the world;
    -- a screen that can outgrow the window holds its content in a ScrollArea.
    if body.SetClipsChildren then pcall(body.SetClipsChildren, body, true) end
    UI.MakeContainer(ui, body, "column", { gap = opts.gap or 0, padding = opts.padding or 0 })
    body.kitWindow = win
    body.kitParentContainer = nil
    win.body = body
    for method, fn in pairs(Container) do win[method] = fn end
    win.kitInner = body
    win.kitFillChildren = true
    body.kitFillChildren = true

    -- A click on the bare window takes the focus from a field.
    win:SetScript("OnMouseDown", function() UI.ClearTypingFocus(nil) end)
    -- Wherever it was placed (centred, say), it opens on whole screen pixels,
    -- so the pixel-snapped layout inside it lands on the grid too; and again
    -- whenever the UI scale or the resolution changes.
    local function settle(w)
        w:SetSize(UI.Snap(w, w:GetWidth() or 0), UI.Snap(w, w:GetHeight() or 0))
        arrange(w)
        local left, top = w:GetLeft(), w:GetTop()
        if not left or not top then return end
        local x, y = UI.Snap(w, left), UI.Snap(w, top)
        if math.abs(x - left) < 0.001 and math.abs(y - top) < 0.001 then return end
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
    win:HookScript("OnShow", settle)
    UI.OnPixelScale(win, settle)
    win:HookScript("OnHide", function()
        UI.ClearTypingFocus(nil)
        if ui.CloseMenu then ui:CloseMenu() end
    end)

    if opts.resizable then
        win:SetResizable(true)
        setBounds(win, opts)
        local grip = CreateFrame("Button", nil, win)
        grip:SetSize(GRIP, GRIP)
        grip:SetFrameLevel(win:GetFrameLevel() + 20)
        grip.glyph = UI.NewGlyph(grip, "grip", 9, 1.3)
        UI.DragFrame(grip, win, opts.resizable == "width" and "width" or "size", { bounds = win.kitBounds, onStop = save })
        grip:SetScript("OnEnter", function() grip.hover = true; win:Repaint() end)
        grip:SetScript("OnLeave", function() grip.hover = false; win:Repaint() end)
        win.grip = grip
    end

    -- Where it was, or where the addon asks.
    local placed = opts.place and opts.key and opts.place[opts.key]
    if placed and placed.x and placed.y then
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", placed.x, placed.y)
        if opts.resizable and placed.w and placed.h then
            win:SetSize(placed.w, opts.resizable == "width" and (opts.height or placed.h) or placed.h)
        end
    else
        local point = opts.point or { "CENTER", UIParent, "CENTER", 0, 0 }
        win:SetPoint(point[1], point[2] or UIParent, point[3] or point[1], point[4] or 0, point[5] or 0)
    end

    if name and not inPlay and opts.escape ~= false and type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, name)
    end

    ui:Finish(win, opts, function(w, t)
        paintWindow(w, t)
        if w.grip then w.grip.glyph:SetColor(w.grip.hover and t.accent or t.muted) end
    end)
    arrange(win)
    if placed and placed.collapsed then win:SetCollapsed(true) end
    if opts.shown == false or opts.hidden then win:Hide() end
    return win
end

-- Window methods ----------------------------------------------------------------------

local Window = {}

function Window:SetTitle(text) self.title:SetText(text or "") end
function Window:SetSubtitle(text) self.subtitle:SetText(text or "") end

function Window:Toggle()
    self:SetShown(not self:IsShown())
end

-- One line: the band alone.
function Window:SetCollapsed(collapsed)
    collapsed = collapsed and true or false
    if collapsed == (self.kitCollapsed or false) then return end
    if collapsed then
        self.kitExpandedWidth, self.kitExpandedHeight = self:GetWidth(), self:GetHeight()
        self.kitCollapsed = true
        self.body:Hide()
        if self.statusStrip then self.statusStrip:Hide() end
        if self.grip then self.grip:Hide() end
        self:SetHeight(BAND + 2 * (self.kitInset or 1))
    else
        self.kitCollapsed = false
        self.body:Show()
        if self.statusStrip and self.statusStrip.kitHasText then self.statusStrip:Show() end
        if self.grip then self.grip:Show() end
        self:SetHeight(self.kitExpandedHeight or self:GetHeight())
    end
    local fold = self.collapseButton
    if fold then
        fold.kitUp:SetShown(not collapsed)
        fold.kitDown:SetShown(collapsed)
        fold.glyph = collapsed and fold.kitDown or fold.kitUp
        fold.kitPressParts = { fold.glyph }
        fold:Repaint()
    end
    arrange(self)
    save(self)
    if self.kitOnCollapse then self.kitOnCollapse(collapsed) end
end

function Window:IsCollapsed() return self.kitCollapsed or false end

-- The strip at the foot: what a change just did, with Undo when `opts.undo`
-- is given. nil text puts the strip away, or, in a window made with
-- `status`, empties it (to the window's hint, if `status` was one): that
-- window keeps its strip, so its body never changes size when a message
-- comes or goes. A body that changes size redraws what scrolls in it, and
-- the client can draw its edges a pixel differently each time.
function Window:Status(text, opts)
    opts = opts or {}
    local strip = self.statusStrip
    if not strip then
        strip = CreateFrame("Frame", nil, self)
        strip:Hide()
        strip:SetHeight(STATUS)
        strip.bg = strip:CreateTexture(nil, "BACKGROUND")
        strip.bg:SetAllPoints()
        strip.line = strip:CreateTexture(nil, "ARTWORK")
        strip.line:SetPoint("TOPLEFT")
        strip.line:SetPoint("TOPRIGHT")
        UI.Hairline(strip.line, "height")
        strip.text = UI.NewText(strip)
        strip.text:SetPoint("LEFT", strip, "LEFT", 12, 0)
        strip.undo = self.ui:Link(strip, "Undo", {})
        strip.undo:SetPoint("LEFT", strip.text, "RIGHT", 8, 0)
        self.statusStrip = strip
        self:Repaint()
    end
    strip.kitHasText = text ~= nil or self.kitStatusKept
    strip.text:SetText(text or self.kitStatusHint or "")
    strip.undo:SetShown(opts.undo ~= nil)
    strip.undo.kitClick = function()
        strip.undo:Hide()
        if opts.undo then opts.undo() end
    end
    local shown = strip.kitHasText and not self.kitCollapsed
    if shown ~= strip:IsShown() then
        strip:SetShown(shown)
        arrange(self)
    end
end

-- Tab moves through the window's text fields in the order they were made;
-- a list here replaces that order.
function Window:TabOrder(fields)
    if not fields then self.kitTabOrder = nil; return end
    local list = {}
    for _, field in ipairs(fields) do list[#list + 1] = field.box or field end
    self.kitTabOrder = list
end

-- Opt in to full keyboard control: Tab also reaches buttons, toggles, tabs,
-- selects and sliders, Enter or Space presses, arrows move a slider,
-- Escape closes. The window holds the keyboard while it is shown, so the
-- game's keybinds stop until it closes.
function Window:TakeKeyboard(on)
    self.kitKeyboard = on and true or false
    if not self.EnableKeyboard then return end
    pcall(self.EnableKeyboard, self, self.kitKeyboard)
    if not self.kitKeysHooked then
        self.kitKeysHooked = true
        self:SetScript("OnKeyDown", function(win, key)
            if not win.kitKeyboard then return end
            local handled = UI.WindowKey(win, key)
            if win.SetPropagateKeyboardInput then pcall(win.SetPropagateKeyboardInput, win, not handled) end
        end)
    end
    if not self.kitKeyboard then UI.FocusWidget(self, nil) end
end

function Window:SetLocked(locked) self.kitLocked = locked and true or false end

-- Keyboard focus -------------------------------------------------------------------------

-- Every widget that can take the keyboard's focus, in the order it was made.
local serial = 0
function UI.RegisterFocusable(ui, widget, isField)
    serial = serial + 1
    widget.kitSerial = serial
    widget.kitFocusable = true
    widget.kitIsField = isField
    ui.focusables = ui.focusables or setmetatable({}, { __mode = "k" })
    ui.focusables[widget] = true
end

local function reachable(widget)
    if not widget:IsVisible() then return false end
    if widget.IsEnabled and not widget:IsEnabled() then return false end
    return true
end

-- The fields (or, with full keyboard control, every focusable) of a window,
-- in order.
function UI.FocusOrder(win, fieldsOnly)
    if win.kitTabOrder then return win.kitTabOrder end
    local list = {}
    for widget in pairs(win.ui.focusables or {}) do
        if (not fieldsOnly or widget.kitIsField) and UI.WindowOf(widget) == win then list[#list + 1] = widget end
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
    for index, widget in ipairs(list) do if widget == current then at = index end end
    for offset = 1, count do
        local candidate = list[((at - 1 + step * offset) % count) + 1]
        if candidate ~= current and reachable(candidate) then return candidate end
    end
    return nil
end

-- Moves the focus ring (full keyboard control) to `widget`, or away.
function UI.FocusWidget(win, widget)
    win.kitFocused = widget
    local ring = win.focusRing
    if not widget then
        if ring then ring:Hide() end
        return
    end
    if not ring then
        ring = CreateFrame("Frame", nil, win)
        ring.plate = UI.NewPlate(ring, "OVERLAY")
        win.focusRing = ring
        win:Repaint()
    end
    ring:SetFrameLevel((widget:GetFrameLevel() or 1) + 5)
    ring:ClearAllPoints()
    local gap = UI.Snap(win, 3)
    ring:SetPoint("TOPLEFT", widget, "TOPLEFT", -gap, gap)
    ring:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", gap, -gap)
    ring:Show()
    if widget.kitIsField and widget.SetFocus then widget:SetFocus() end
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

-- Constructors ---------------------------------------------------------------------------

-- `opts.status`: true (or a hint to show while it is empty) keeps the status
-- strip at the foot always, rather than only while it has a message.
function Proto:Window(opts)
    opts = opts or {}
    local win = shell(self, opts, false)
    for method, fn in pairs(Window) do win[method] = fn end
    if opts.status then
        win.kitStatusKept = true
        win.kitStatusHint = type(opts.status) == "string" and opts.status or nil
        win:Status(nil)
    end
    return win
end

-- A frame over the world: always flat and translucent, following the look's
-- opacity, with a band only when it has a title or folds.
function Proto:Panel(opts)
    opts = opts or {}
    local win = shell(self, opts, true)
    for method, fn in pairs(Window) do win[method] = fn end
    return win
end
