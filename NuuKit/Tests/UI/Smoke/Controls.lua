-- Buttons, fields, menus, settings, choices and attention.

local ctx = ...
local Kit, UI, g, objects, Object, tick, find, show, assertTrue =
    ctx.Kit, ctx.UI, ctx.g, ctx.objects, ctx.Object, ctx.tick, ctx.find, ctx.show, ctx.assertTrue

-- The wheel passes over a slider and a text area to the page, until the
-- player takes hold of them.
for _, o in ipairs(objects) do
    if o.kind == "Slider" then
        assertTrue(not o.wheel, "a slider leaves the wheel to the page")
        o:Fire("OnMouseDown", "LeftButton")
        assertTrue(o.wheel and o.parent.kitHeld, "until it is pressed, and shows it holds the wheel")
        o:Fire("OnLeave")
        assertTrue(not o.wheel and not o.parent.kitHeld, "and gives it back when the pointer leaves")
    elseif o.kind == "EditBox" and o.parent and o.parent.parent and o.parent.parent.kind == "ScrollFrame" then
        local scroll = o.parent.parent
        assertTrue(not scroll.wheel, "a text area leaves the wheel to the page")
        o:Fire("OnEditFocusGained")
        assertTrue(scroll.wheel, "until it has focus")
        o:Fire("OnEditFocusLost")
        assertTrue(not scroll.wheel, "and gives it back after")
    end
end

show("tables")

-- Settings: a reset shows while changed and puts it back.
local setting = find(function(o) return rawget(o, "SetChanged") and o.reset end)
assertTrue(setting and setting.reset.shown, "a changed setting shows its reset")
setting.reset:Click()
assertTrue(not setting.reset.shown, "and the reset puts it back")

-- Choices: one picked at a time.
local choicesFrame = find(function(o) return o.buttons and rawget(o, "GetValue") end)
choicesFrame.buttons[3]:Click()
local active = 0
for _, b in ipairs(choicesFrame.buttons) do if b:IsActive() then active = active + 1 end end
assertTrue(choicesFrame:GetValue() == "Collect" and active == 1, "a click picks one choice, and only one")
-- The layout sizes a choice: hover repaints it without changing its width.
local choice = choicesFrame.buttons[1]
choice:SetWidth(180)  -- as the layout would share out a wide row
local width = choice:GetWidth()
choice:Fire("OnEnter")
assertTrue(choice:GetWidth() == width, "hovering a choice leaves its width: " .. width .. " to " .. choice:GetWidth())
choice:Fire("OnLeave")

-- A number field steps on the wheel only while it has focus.
local numberBox
for _, o in ipairs(objects) do
    if o.kind == "EditBox" and o.scripts.OnMouseWheel and o.kitFrame and rawget(o.kitFrame, "GetValue") and o.kitFrame.kitTextStyle == "number" then numberBox = o end
end
assertTrue(numberBox and not numberBox.wheel, "a number field leaves the wheel to the page")
local before = numberBox.kitFrame:GetValue()
numberBox:SetFocus()
assertTrue(numberBox.wheel, "until it has focus")
numberBox.scripts.OnMouseWheel(numberBox, 1)
assertTrue(numberBox.kitFrame:GetValue() == before + 1, "then the wheel steps it")
numberBox:ClearFocus()
assertTrue(not numberBox.wheel, "and gives the wheel back")

-- A money field shows coloured coins, plain only while it is typed in,
-- and clicking in and out of it changes nothing.
local changes = 0
local money = g.ui:MoneyInput(UIParent, { value = 12005, onChange = function() changes = changes + 1 end })
assertTrue(string.find(money.box:GetText(), "|cff", 1, true), "a money field shows coloured coins: " .. money.box:GetText())
money.box:SetFocus()
assertTrue(money.box:GetText() == "1g 20s 5c", "plain while typed in: " .. money.box:GetText())
money.box:ClearFocus()
assertTrue(string.find(money.box:GetText(), "|cff", 1, true) and changes == 0 and money:GetValue() == 12005,
    "coloured again after, with no change made")
money.box:SetFocus()
money.box:SetText("2g")
money.box:ClearFocus()
assertTrue(money:GetValue() == 20000 and changes == 1 and string.find(money.box:GetText(), "|cff", 1, true), "a typed amount commits, coloured")
money:Hide()

-- Click every button and link that has a click.
for _, o in ipairs(objects) do
    if o.kind == "Button" and o.kitClick and o:IsVisible() and o.enabled and not o.kitHold then
        local ok, err = pcall(o.Click, o)
        assertTrue(ok, "a click failed: " .. tostring(err))
    end
end
tick()

-- Fields: focus, type, commit, escape.
for _, o in ipairs(objects) do
    if o.kind == "EditBox" and o.kitField and o.scripts.OnEditFocusGained then
        o:SetFocus()
        o:SetText("1g 20s")
        o:Fire("OnTextChanged", true)
        if o.scripts.OnTabPressed then o.scripts.OnTabPressed(o) end
        o:ClearFocus()
        if o.scripts.OnEscapePressed then o.scripts.OnEscapePressed(o) end
        if o.scripts.OnArrowPressed then o.scripts.OnArrowPressed(o, "DOWN") end
    end
end
tick()

-- A menu, filled and chosen from.
g.ui:OpenMenu({
    { header = "Step 12" },
    { caption = "Go", key = "Click" },
    { caption = "Sub", items = { { caption = "Inner" } } },
    { caption = "Check", check = true, value = false },
    { caption = "Radio", group = "g", value = 1, checked = true },
    { separator = true },
    { caption = "Danger", tone = "danger", desc = "A second line." },
}, { at = "cursor", search = true })
local menu = g.ui.kitMenu
assertTrue(menu and menu.count == 7, "the menu fills every item")
menu.search:SetText("ch")
menu.search.scripts.OnTextChanged(menu.search, true)
assertTrue(menu.count == 1, "the filter narrows it")
menu.rows[1]:Click()
g.ui:CloseMenu()

-- Attention, every kind, with and without motion.
local button = g.ui:Button(UIParent, "Look here", {})
for _, kind in ipairs({ "breathe", "pulse", "shimmer", "flash", "trail" }) do
    button:Attract(kind)
    tick()
end
-- The trail's dashes go all the way round, and turning a corner is no gap.
button:SetSize(100, 24)
button:Attract("trail")
local drawn = 0
for _, dash in ipairs(button.kitFx.dashes) do
    if dash.shown then drawn = drawn + math.max(dash.width, dash.height) end
end
assertTrue(math.abs(drawn - 248 * 4 / 7) <= 4, "the trail dashes the whole edge: " .. drawn)
button:Attract(nil)
for _, dash in ipairs(button.kitFx.dashes) do assertTrue(not dash.shown, "stopping takes the trail away") end

-- Kinds combine; breathe and flash share the wash, so the first of them wins.
button:Attract({ "trail", "pulse", "breathe", "flash" })
local fx = button.kitFx
assertTrue(fx.running.trail and fx.running.pulse and fx.ticker.shown, "trail and pulse run together")
assertTrue(fx.wash.shown and fx.wash.alpha ~= 0, "with breathe's wash, not flash's")
tick()
button:Attract("shimmer")
assertTrue(not fx.running.trail and not fx.running.pulse and not fx.wash.shown, "a new kind stops the whole set")
button:Attract(nil)
