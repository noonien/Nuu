local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto

-- Windows and in-play panels.
--
-- A window is movable by its title band, clamped to the screen, closes on
-- Escape, and wears the look's chrome: flat colours, or an art theme's
-- tiled background and 9-slice frame. Its body is a column; anything made on
-- the window is made in the body, and a column, panes or tabs made straight
-- on it fill it.
--
-- Windows are few and never pooled, so they are made here directly rather
-- than through UI.Define; they answer as a holder does (kitInner is the
-- body, the makers and UI.Holder's methods are on the window). A window is
-- painted through ui:Paint, so a look change repaints it (Paint); the
-- cursor on its band or grip changes colours only (PaintState).
--
-- With `place` (a table the addon keeps) and `key`, its position, size and
-- collapsed state go into place[key]; the kit writes nothing else.
--
-- The focus functions (Base/Focus.lua) and UI.DragFrame (Base/Drag.lua) are
-- the Base's; this file only uses them.

local BAND, STATUS, GRIP = 30, 24, 14
local ART_CORNER, ART_INSET = 24, 17
local NO_LAYOUT = {}

local function frameName(ui, key)
    if not key then return nil end
    local owner = ui.owner and ui.owner.name or "Nuu"
    return (tostring(owner) .. "_" .. tostring(key) .. "_Window"):gsub("[^%w_]", "")
end

-- Anchors the window by the corner it does not grow from, on whole pixels:
-- its top left, or its bottom left when it grows upward.
local function hold(win, left, top, bottom)
    win:ClearAllPoints()
    if win.kitUpward then
        win:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", UI.Snap(win, left), UI.Snap(win, bottom))
    else
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", UI.Snap(win, left), UI.Snap(win, top))
    end
end

-- Writes the window's place into the addon's table, and anchors it by the
-- corner it does not grow from, so a change of size leaves it put. `x`, `y`
-- are its top left; one that grows upward keeps its bottom as `bottom` too.
local function save(win)
    local left, top, bottom = win:GetLeft(), win:GetTop(), win:GetBottom()
    if not left or not top or not bottom then return end
    hold(win, left, top, bottom)
    local place, key = win.kitPlace, win.kitKey
    if not place or not key then return end
    local entry = place[key] or {}
    entry.x, entry.y = UI.Snap(win, left), UI.Snap(win, top)
    entry.bottom = win.kitUpward and UI.Snap(win, bottom) or nil
    entry.w = UI.Snap(win, win.kitCollapsed and win.kitExpandedWidth or win:GetWidth())
    entry.h = UI.Snap(win, win.kitCollapsed and win.kitExpandedHeight or win:GetHeight())
    entry.collapsed = win.kitCollapsed or nil
    place[key] = entry
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
-- The band's marks (close, fold) and the addon's header row, at their
-- distance from the band's right end, centred on it: on whole pixels.
local function placeMarks(win)
    local band = win.band
    for _, mark in ipairs({ win.closeButton, win.collapseButton }) do
        if mark then
            local height = mark.kitPH or mark:GetHeight() or 0
            mark:ClearAllPoints()
            mark:SetPoint("TOPRIGHT", band, "TOPRIGHT", UI.Snap(win, mark.kitFromRight), -UI.Snap(win, (BAND - height) / 2))
        end
    end
    -- The header: from past the subtitle to the marks, the band's height.
    local header = win.header
    if header and header.kitFromRight then
        local inset = UI.Snap(win, win.kitInset or 1)
        local bandWidth = (win.kitPW or win:GetWidth() or 0) - 2 * inset
        local words = 12 + UI.StringWidth(win.title) + 8 + UI.StringWidth(win.subtitle) + 8
        local width = math.max(1, UI.Snap(win, bandWidth + header.kitFromRight - words))
        header:ClearAllPoints()
        header:SetPoint("TOPRIGHT", band, "TOPRIGHT", UI.Snap(win, header.kitFromRight), 0)
        header:SetSize(width, UI.Snap(win, BAND))
    end
end

local function arrange(win)
    placeMarks(win)
    local inset = UI.Snap(win, win.kitInset or 1)
    local band = win.band
    local bandHeight = band:IsShown() and UI.Snap(win, BAND) or 0
    -- A window that grows upward wears its band at the foot, under the
    -- status strip, and its grip at the top.
    local upward = win.kitUpward
    local top, bottom = inset, inset
    band:ClearAllPoints()
    if upward then
        band:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", inset, inset)
        band:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -inset, inset)
        bottom = inset + bandHeight
    else
        band:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -inset)
        band:SetPoint("TOPRIGHT", win, "TOPRIGHT", -inset, -inset)
        top = inset + bandHeight
    end
    band:SetHeight(UI.Snap(win, BAND))
    local status = win.statusStrip
    if status and status:IsShown() and not win.kitCollapsed then
        status:ClearAllPoints()
        status:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", inset, bottom)
        status:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -inset, bottom)
        status:SetHeight(UI.Snap(win, STATUS))
        bottom = bottom + UI.Snap(win, STATUS)
    end
    win.body:ClearAllPoints()
    win.body:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -top)
    win.body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -inset, bottom)
    if win.grip then
        win.grip:ClearAllPoints()
        local corner = UI.Snap(win, math.max(1, inset - 6))
        if upward then
            win.grip:SetPoint("TOPRIGHT", win, "TOPRIGHT", -corner, -corner)
        else
            win.grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -corner, corner)
        end
        win.grip.glyph:SetFlipped(upward)
    end
    UI.Invalidate(win.body)
    UI.Invalidate(win.header)
end

-- Wherever it was placed (centred, say), it opens on whole screen pixels,
-- so the pixel-snapped layout inside it lands on the grid too; and again
-- whenever the UI scale or the resolution changes.
-- Where on UIParent a point of a frame `width` x `height` lands when
-- anchored `point` to UIParent's `relative`, offset x, y: its top left.
local H = { LEFT = 0, CENTER = 0.5, RIGHT = 1 }
local V = { TOP = 1, CENTER = 0.5, BOTTOM = 0 }
local function split(point)
    point = point or "CENTER"
    local v = point:match("^TOP") and "TOP" or (point:match("^BOTTOM") and "BOTTOM" or "CENTER")
    local h = point:match("LEFT$") and "LEFT" or (point:match("RIGHT$") and "RIGHT" or "CENTER")
    return H[h], V[v]
end
local function topLeftOn(point, relative, x, y, width, height)
    local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    local rh, rv = split(relative)
    local ph, pv = split(point)
    local px, py = sw * rh + (x or 0), sh * rv + (y or 0)
    return px - width * ph, py + height * (1 - pv)
end

-- Anchors `win` by its top left, on whole pixels, from an anchor to UIParent
-- worked out here: the client may not know the window's place yet (on its
-- first show GetLeft answers nil), so it is not asked.
local function pin(win, point)
    local width, height = win:GetWidth() or 0, win:GetHeight() or 0
    local left, top = topLeftOn(point[1], point[3] or point[1], point[4], point[5], width, height)
    hold(win, left, top, top - height)
end

local function settle(win)
    win:SetSize(UI.Snap(win, win:GetWidth() or 0), UI.Snap(win, win:GetHeight() or 0))
    arrange(win)
    local left, top, bottom = win:GetLeft(), win:GetTop(), win:GetBottom()
    if not left or not top or not bottom then
        -- Not placed yet: again on the next frame.
        if C_Timer and C_Timer.After and not win.kitSettleWaiting then
            win.kitSettleWaiting = true
            C_Timer.After(0, function() win.kitSettleWaiting = nil; settle(win) end)
        end
        return
    end
    local y = win.kitUpward and bottom or top
    if math.abs(UI.Snap(win, left) - left) < 0.001 and math.abs(UI.Snap(win, y) - y) < 0.001 then return end
    hold(win, left, top, bottom)
end

-- Painting ---------------------------------------------------------------------------

local function paintStrip(win, t)
    local strip = win.statusStrip
    if not strip then return end
    UI.TexColor(strip.bg, win.kitInPlay and t.raisedBg or t.bandBg)
    UI.TexColor(strip.line, t.hairline)
    UI.ApplyStyle(strip.text, "label", t, strip.kitTone)
end

-- The look: background, frame, band art, fonts.
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
            -- One frame per art theme, kept for when it comes back.
            win.nines = win.nines or {}
            win.nine = win.nines[art.frame] or UI.NineSlice(win, "BORDER", art.frame, ART_CORNER, false)
            win.nines[art.frame] = win.nine
            win.nineSpec = art.frame
        end
        framed = win.nine.loaded
        if framed then win.nine:Show() end
    elseif win.nine then
        win.nine:Hide()
    end
    local fill = win.kitInPlay and t.surfaceBg or t.windowBg
    if tiled then fill = nil end
    if win.kitNoPlate then
        win.plate:Hide()
    else
        win.plate:Flat(fill, (not framed) and (win.kitInPlay and t.border or t.hairline) or nil)
    end
    local inset = framed and ART_INSET or 1
    if inset ~= win.kitInset then
        win.kitInset = inset
        arrange(win)
    end
    win.kitBanded = art and art.band and UI.Tile(win.bandBg, art.band) or false
    UI.ApplyStyle(win.title, "window", t)
    UI.ApplyStyle(win.subtitle, "label", t)
    paintStrip(win, t)
    win:PaintState(t)
end

-- Colours only: the band (an in-play panel's shows while the cursor is on
-- it) and the grip.
local function paintWindowState(win, t)
    if win.kitBanded then
        win.bandBg:SetVertexColor(1, 1, 1, 1)
    elseif win.kitInPlay then
        UI.TexColor(win.bandBg, win.band.hover and t.raisedBg or nil)
    else
        UI.TexColor(win.bandBg, t.bandBg)
    end
    if win.grip then win.grip.glyph:SetColor(win.grip.hover and t.accent or t.muted) end
end

-- Scripts (shared; each finds its window through the frame) ---------------------------

local function clearTyping() UI.ClearTypingFocus(nil) end

-- A locked window does not move.
local function canMove(win) return not win.kitLocked end

-- The player closes it: onClose hears it. Hide from code does not.
local function closeClicked(button)
    local win = button.kitOwner
    win:Hide()
    if win.kitOnClose then win.kitOnClose(win) end
end

-- The player folds it: onCollapse hears it. SetCollapsed from code does not.
local function collapseClicked(button)
    local win = button.kitOwner
    win:SetCollapsed(not win.kitCollapsed)
    if win.kitOnCollapse then win.kitOnCollapse(win.kitCollapsed, win) end
end

local function undoClicked(link)
    local strip = link.kitStrip
    link:Hide()
    local undo = strip.kitUndo
    strip.kitUndo = nil
    if undo then undo() end
end

local function windowShown(win)
    settle(win)
    -- Laid out now, so it never shows a frame late.
    UI.LayoutNow()
end

local function windowHidden(win)
    UI.ClearTypingFocus(nil)
    if win.ui.CloseMenu then win.ui:CloseMenu() end
end

-- The body follows the window's size; the client tells the body itself, the
-- window's own change is heard here too.
-- A new size: the body lays out again, and the header spans the new band.
local function windowSized(win)
    placeMarks(win)
    UI.Invalidate(win.body)
end

local function keyDown(win, key)
    if not win.kitKeyboard then return end
    local handled = UI.WindowKey(win, key)
    if win.SetPropagateKeyboardInput then pcall(win.SetPropagateKeyboardInput, win, not handled) end
end

-- Window methods ----------------------------------------------------------------------

local Window = {}

function Window:Paint(t) paintWindow(self, t) end
function Window:PaintState(t) paintWindowState(self, t) end
function Window:Repaint() paintWindow(self, self.ui.tokens) end

function Window:SetTitle(text)
    self.title:SetText(text or "")
    placeMarks(self)
end
function Window:SetSubtitle(text)
    self.subtitle:SetText(text or "")
    placeMarks(self)
end

-- Shows or hides it. `win:Toggle{ ... }` (a spec) is the Toggle maker: a
-- toggle made in the body, as on any holder.
function Window:Toggle(spec)
    if spec ~= nil and UI.Makers.Toggle then return UI.Makers.Toggle(self, spec) end
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
        self:SetHeight(UI.Snap(self, BAND + 2 * (self.kitInset or 1)))
    else
        self.kitCollapsed = false
        self.body:Show()
        if self.statusStrip and self.statusStrip.kitHasText then self.statusStrip:Show() end
        if self.grip then self.grip:Show() end
        self:SetHeight(self.kitExpandedHeight or self:GetHeight())
    end
    -- The fold mark points down while folded.
    if self.collapseButton then self.collapseButton:SetGlyph(collapsed and "down" or "up") end
    arrange(self)
    save(self)
end

function Window:IsCollapsed() return self.kitCollapsed or false end

-- Upward (true): the window is held by its bottom-left corner, so a change
-- of height moves its top, and wears its band at the foot. Its place is
-- kept where it stands now.
function Window:SetUpward(upward)
    upward = upward and true or false
    if upward == (self.kitUpward or false) then return end
    self.kitUpward = upward
    arrange(self)
    save(self)
end

function Window:IsUpward() return self.kitUpward or false end

-- The strip at the foot: what a change just did, with Undo when `opts.undo`
-- is given, in `opts.tone` (a token name or a colour: "text" for news,
-- "danger" for what went wrong; muted, as a hint, without). nil text puts
-- the strip away, or, in a window made with
-- `status`, empties it (to the window's hint, if `status` was one): that
-- window keeps its strip, so its body never changes size when a message
-- comes or goes. A body that changes size redraws what scrolls in it, and
-- the client can draw its edges a pixel differently each time.
function Window:Status(text, opts)
    local strip = self.statusStrip
    if not strip then
        strip = UI.NewFrame("Frame", nil, self)
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
        strip.undo = self.ui:Link(strip, { "Undo", onClick = undoClicked })
        strip.undo.kitStrip = strip
        strip.undo:SetPoint("LEFT", strip.text, "RIGHT", 8, 0)
        self.statusStrip = strip
        paintStrip(self, self.ui.tokens)
    end
    local undo = opts and opts.undo
    local tone = text ~= nil and opts and opts.tone or nil
    if tone ~= strip.kitTone then
        strip.kitTone = tone
        UI.ApplyStyle(strip.text, "label", self.ui.tokens, tone)
    end
    strip.kitHasText = text ~= nil or self.kitStatusKept
    strip.text:SetText(text or self.kitStatusHint or "")
    strip.kitUndo = undo
    strip.undo:SetShown(undo ~= nil)
    local shown = strip.kitHasText and not self.kitCollapsed and true or false
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
        self:SetScript("OnKeyDown", keyDown)
    end
    if not self.kitKeyboard then UI.FocusWidget(self, nil) end
end

function Window:SetLocked(locked) self.kitLocked = locked and true or false end

-- Tabs in the band ----------------------------------------------------------------------

-- A window's tabs sit in its band after the title; their pages are columns
-- of its body, the chosen one shown (a hidden column takes no room, so the
-- chosen page fills the window). The Tabs widget in the band is used for its
-- strip alone. The addon's own band controls (`win.header`) follow them at
-- the right.
local function showPage(win, key)
    for pageKey, page in pairs(win.kitPages) do page:SetShown(pageKey == key) end
end

local function tabChosen(key, tabs)
    local win = tabs.kitTabsWindow
    showPage(win, key)
    if win.kitOnTab then win.kitOnTab(key, win) end
end

local function buildTabs(win, spec)
    local header = win.header
    header:Spacer{ size = spec.offset or 24 }
    local entries = { value = spec.value, onChange = tabChosen, rule = false }
    for index, entry in ipairs(spec) do entries[index] = entry end
    local tabs = header:Tabs(entries)
    tabs.kitTabsWindow = win
    -- What the addon puts in the band after this goes to the right.
    header:Spacer{}
    win.tabs, win.kitOnTab, win.kitPages = tabs, spec.onChange, {}
    for _, entry in ipairs(spec) do
        win.kitPages[entry.key] = win:Column{ padding = spec.padding or 12, gap = spec.gap or 8 }
    end
    showPage(win, tabs:GetValue())
end

-- The page of tab `key` (a window made with `tabs`).
function Window:Page(key) return self.kitPages and self.kitPages[key] end

-- Chooses a tab from code: its page shows, and onChange does not hear it.
function Window:SetTab(key)
    if not self.tabs then return end
    self.tabs:SetValue(key)
    showPage(self, self.tabs:GetValue())
end

function Window:GetTab() return self.tabs and self.tabs:GetValue() end

-- The shell ------------------------------------------------------------------------------

-- A window is never released to a pool.
local function keepWindow() end

-- Makes the window shell shared by Window and Panel.
local function shell(ui, opts, inPlay)
    local name = (not inPlay or opts.escape) and frameName(ui, opts.key) or nil
    local win = UI.NewFrame("Frame", name, opts.parent or UIParent)
    -- What a widget has (Changed, Repaint, OnRightClick...), but a window
    -- is never released to a pool; a holder: what is made on the window
    -- goes in the body.
    UI.Adopt(win, "Window", { UI.Widget, UI.Makers, UI.Holder, Window }, { Release = keepWindow })
    win.ui, win.kitLayout = ui, NO_LAYOUT
    win.kitIsWindow, win.kitInPlay = true, inPlay
    win.kitKey, win.kitPlace = opts.key, opts.place
    win.kitUpward = opts.upward and true or nil
    win.kitOnCollapse, win.kitOnClose = opts.onCollapse, opts.onClose
    win.kitNoPlate = inPlay and opts.plate == false
    win:SetFrameStrata(opts.strata or (inPlay and "MEDIUM" or "HIGH"))
    if win.SetToplevel then pcall(win.SetToplevel, win, true) end
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
    local band = UI.NewFrame("Frame", nil, win)
    band:SetHeight(BAND)
    win.band = band
    win.bandBg = band:CreateTexture(nil, "BACKGROUND")
    win.bandBg:SetAllPoints()
    band:EnableMouse(true)
    UI.Hover(band, win)
    band:SetScript("OnMouseDown", clearTyping)
    UI.DragFrame(band, win, "move", { can = canMove, onStop = save })

    win.title = UI.NewText(band)
    win.title:SetPoint("LEFT", band, "LEFT", 12, 0)
    win.title:SetText(opts.title or "")
    win.subtitle = UI.NewText(band)
    win.subtitle:SetPoint("LEFT", win.title, "RIGHT", 8, 0)
    win.subtitle:SetText(opts.subtitle or "")

    local right = -6
    -- A window has its close mark unless it says no; a panel only when it asks.
    if (inPlay and opts.close == true) or (not inPlay and opts.close ~= false) then
        local close = ui:GlyphButton(band, { "close", size = 22, glyphSize = 9, boxed = true, bright = true,
            onClick = closeClicked })
        close.kitOwner = win
        close.kitFromRight = right
        win.closeButton = close
        right = right - 26
    end
    if opts.collapsible then
        local fold = ui:GlyphButton(band, { "up", size = 22, glyphSize = 9, onClick = collapseClicked })
        fold.kitOwner = win
        fold.kitFromRight = right
        win.collapseButton = fold
        right = right - 24
    end
    -- The addon's own controls in the band, right of the title:
    -- `win.header:Button{ ... }`.
    -- `arrange` below places and sizes it.
    local header = UI.Part(ui, band, "row", { gap = 4, align = "right" })
    header.kitWindow = win
    header.kitFromRight = right
    win.header = header

    if inPlay and not opts.title and not opts.collapsible then band:Hide() end

    -- The body: a column that fills the window.
    local body = UI.NewFrame("Frame", nil, win)
    -- What does not fit is cut at the window's edge, not drawn over the world;
    -- a screen that can outgrow the window holds its content in a ScrollArea.
    if body.SetClipsChildren then pcall(body.SetClipsChildren, body, true) end
    UI.MakeStack(ui, body, "column", { gap = opts.gap or 0, padding = opts.padding or 0 })
    body.kitWindow = win
    body.kitFillChildren = true
    win.body = body
    win.kitInner = body
    win.kitFillChildren = true

    -- A click on the bare window takes the focus from a field.
    win:SetScript("OnMouseDown", clearTyping)
    win:HookScript("OnShow", windowShown)
    win:HookScript("OnHide", windowHidden)
    win:HookScript("OnSizeChanged", windowSized)
    UI.OnPixelScale(win, settle)

    if opts.resizable then
        if win.SetResizable then win:SetResizable(true) end
        setBounds(win, opts)
        local grip = UI.NewFrame("Button", nil, win)
        grip:SetSize(GRIP, GRIP)
        grip:SetFrameLevel(win:GetFrameLevel() + 20)
        grip.glyph = UI.NewGlyph(grip, "grip", 9, 1.3)
        UI.DragFrame(grip, win, opts.resizable == "width" and "width" or "size", { bounds = win.kitBounds, onStop = save })
        UI.Hover(grip, win)
        win.grip = grip
    end

    -- Where it was, or where the addon asks.
    local placed = opts.place and opts.key and opts.place[opts.key]
    if placed and placed.x and placed.y then
        if opts.resizable and placed.w and placed.h then
            win:SetSize(placed.w, opts.resizable == "width" and (opts.height or placed.h) or placed.h)
        end
        local height = win:GetHeight() or 0
        hold(win, placed.x, placed.y, placed.bottom or (placed.y - height))
    else
        local point = opts.point or { "CENTER", UIParent, "CENTER", 0, 0 }
        if (point[2] or UIParent) == UIParent then
            pin(win, point)
        else
            win:SetPoint(point[1], point[2], point[3] or point[1], point[4] or 0, point[5] or 0)
        end
    end

    if name and not inPlay and opts.escape ~= false and type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, name)
    end

    -- Painted now and on every look change. Not in ui.widgets: a window is
    -- no stack of its own to lay out, and never pooled.
    ui:Paint(win, function(t) paintWindow(win, t) end)
    arrange(win)
    if opts.tabs then buildTabs(win, opts.tabs) end
    if placed and placed.collapsed then win:SetCollapsed(true) end
    if opts.shown == false or opts.hidden then win:Hide() end
    return win
end

-- Constructors ---------------------------------------------------------------------------

-- Spec: title, subtitle, key and place (where it is kept), width, height,
-- point, parent, strata, resizable (true, or "width"), minWidth, minHeight,
-- maxWidth, maxHeight, upward (held by its bottom left, band at the foot:
-- see SetUpward), collapsible, onCollapse(collapsed, win) (the
-- player's fold), close (false: no close mark; on a panel, true gives it
-- one), onClose(win) (the player's close), escape (false: Escape does
-- not close it), gap and padding of the body, hidden (or shown = false).
-- `status`: true (or a hint to show while it is empty) keeps the status
-- strip at the foot always, rather than only while it has a message.
-- `tabs`: tabs in the band after the title, each with a page in the body:
-- the entries are its array part ({ key, caption, badge, disabled }, as a
-- Tabs'), with value (the tab chosen first), onChange(key, win) (the
-- player's choice), offset (room after the title, 24), padding and gap of
-- each page (12, 8). `win:Page(key)` is a tab's page, `win:SetTab(key)`
-- chooses one from code, `win:GetTab()` answers the chosen one, and
-- `win.header` controls made after follow the tabs at the right.
function Proto:Window(opts)
    opts = opts or {}
    local win = shell(self, opts, false)
    if opts.status then
        win.kitStatusKept = true
        win.kitStatusHint = type(opts.status) == "string" and opts.status or nil
        win:Status(nil)
    end
    return win
end

-- A frame over the world: always flat and translucent, following the look's
-- opacity, with a band only when it has a title or folds. The same spec as
-- a window; it has no close mark unless `close = true`, and does not close
-- on Escape (`escape` only gives its frame a name). `plate = false` leaves out the plate and
-- border, so only what the addon draws on it shows.
function Proto:Panel(opts)
    return shell(self, opts or {}, true)
end
