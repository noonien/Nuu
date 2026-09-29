-- Fields, toggles, sliders, the Tab chain, settings and choices; and a
-- clear and rebuild from the pools.

local ctx = ...
local UI, ui, Kit, assertTrue, testWindow, layout, objects =
    ctx.UI, ctx.ui, ctx.Kit, ctx.assertTrue, ctx.testWindow, ctx.layout, ctx.objects

-- The stand-in ignores these; the checks below read what was set.
local Object = ctx.Object
function Object:SetMaxLetters(count) self.maxLetters = count end
function Object:SetNumeric(on) self.numeric = on end

-- A window for Tab: a real one when Chrome is there, else the stand-in's
-- holder marked as one.
local function window(width, height)
    local win, body = testWindow(ui, width, height)
    if not win.kitIsWindow then
        win.kitIsWindow = true
        win.ui = ui
    end
    return win, body
end

local win, body = window(700, 2400)
layout()

local function type_(box, text)
    box:SetText(text)
    box:Fire("OnTextChanged", true)
end

-- Input ---------------------------------------------------------------------------------

local db = {}
local typed, committed = {}, {}
local name
name = body:Input{ label = "Name", placeholder = "A guide name", help = "Shown in the list.", maxLetters = 20,
    bind = { db, "name" }, default = "Untitled",
    validate = function(text) if text:find("!", 1, true) then return "No ! please." end end,
    onType = function(text, w) typed[#typed + 1] = text; assertTrue(w == name, "onType gets the field") end,
    onChange = function(text, w) committed[#committed + 1] = text; assertTrue(w == name, "onChange gets the field") end }
layout()
local box = name.box
assertTrue(box.kitField, "a field's box is marked for UI.ClearTypingFocus")
assertTrue(name:GetText() == "Untitled" and name:GetValue() == "Untitled", "the default shows: " .. name:GetText())
assertTrue(not name:IsStored(), "a default is not a stored choice")
assertTrue(name.label:IsShown() and name.label:GetText() == "Name", "the label")
assertTrue(name.message:IsShown() and name.message:GetText() == "Shown in the list.", "the help line")
assertTrue(box.maxLetters == 20, "maxLetters reaches the box")
assertTrue(not box.placeholder:IsShown(), "no placeholder over text")
assertTrue(name.kitPH > 24 + 12, "label, box and help are laid out: " .. tostring(name.kitPH))

-- Code never calls onChange (or onType).
name:SetText("Code")
name:SetValue("Code 2")
assertTrue(#committed == 0 and #typed == 0 and db.name == nil, "code sets no callback and no table")
name:SetText("")
assertTrue(box.placeholder:IsShown() and box.placeholder:GetText() == "A guide name", "the placeholder over an empty box")
name:SetPlaceholder("")
assertTrue(not box.placeholder:IsShown(), "no placeholder once it is gone")

-- Enter commits and leaves.
box:SetFocus()
type_(box, "Elwynn")
assertTrue(typed[1] == "Elwynn" and #committed == 0, "typing calls onType, not onChange")
box:GetScript("OnEnterPressed")(box)
assertTrue(committed[1] == "Elwynn" and db.name == "Elwynn", "Enter commits into the table and onChange")
assertTrue(not box:HasFocus() and name:IsStored(), "and leaves; the choice is stored")

-- Escape puts back what was there.
box:SetFocus()
type_(box, "Westfall")
box:GetScript("OnEscapePressed")(box)
assertTrue(name:GetText() == "Elwynn" and #committed == 1 and not box:HasFocus(), "Escape restores the old text")

-- A click elsewhere commits.
box:SetFocus()
type_(box, "Duskwood")
box:ClearFocus()
assertTrue(committed[2] == "Duskwood" and db.name == "Duskwood", "leaving commits")
box:SetFocus()
box:ClearFocus()
assertTrue(#committed == 2, "leaving unchanged commits nothing")

-- validate refuses, and typing clears the error.
box:SetFocus()
type_(box, "Bad!")
box:GetScript("OnEnterPressed")(box)
assertTrue(name:IsInvalid() and name.message:GetText() == "No ! please." and name.kitMessageError, "validate refuses")
assertTrue(#committed == 2 and db.name == "Duskwood", "a refused text is not committed")
type_(box, "Bad")
assertTrue(not name:IsInvalid() and name.message:GetText() == "Shown in the list.", "typing clears the error")
name:SetInvalid("Taken.")
layout()
assertTrue(name:IsInvalid() and name.message:GetText() == "Taken.", "SetInvalid with a message")
name:SetInvalid(nil)
assertTrue(not name:IsInvalid() and not name.kitMessageError, "and cleared")

-- Reset forgets the choice.
name:Reset()
assertTrue(db.name == nil and name:GetText() == "Untitled" and committed[3] == "Untitled", "Reset shows the default and tells onChange")
assertTrue(not name:IsStored(), "nothing stored after a reset")

-- Disabled: no focus, muted.
box:SetFocus()
name:SetEnabled(false)
assertTrue(not box:HasFocus() and not name:IsEnabled(), "disabling takes the focus")
name:SetEnabled(true)
name:SetLabel("Guide name")
assertTrue(name.label:GetText() == "Guide name", "SetLabel")

-- Hover and focus repaint colours only: no layout.
layout()
box:SetFocus()
box:ClearFocus()
assertTrue(UI.LayoutSettled(), "focus lays nothing out")

local numeric = body:Input{ numeric = true, value = 12 }
assertTrue(numeric.box.numeric == true and numeric:GetText() == "12" and not numeric.label:IsShown(), "numeric, a value, no label")

-- Search --------------------------------------------------------------------------------

local searched, searchCommits = {}, 0
local list = { moves = {}, activated = 0 }
function list:MoveSelection(step) self.moves[#self.moves + 1] = step end
function list:Activate() self.activated = self.activated + 1 end
local search = body:Search{ placeholder = "Search recipes", onType = function(text) searched[#searched + 1] = text end,
    onChange = function() searchCommits = searchCommits + 1 end }
assertTrue(search.lens and search.kitOnType, "a search has a lens, and reports its text")
search.kitList = list
local sbox = search.box
sbox:SetFocus()
type_(sbox, "lin")
assertTrue(searched[1] == "lin", "a keystroke reaches kitOnType")
sbox:GetScript("OnArrowPressed")(sbox, "DOWN")
sbox:GetScript("OnArrowPressed")(sbox, "UP")
assertTrue(list.moves[1] == 1 and list.moves[2] == -1, "UP and DOWN move through the list")
sbox:GetScript("OnEnterPressed")(sbox)
assertTrue(list.activated == 1 and not sbox:HasFocus() and searchCommits == 1, "Enter picks from the list and leaves")
search:SetText("cloth")
assertTrue(searched[#searched] == "cloth" and searchCommits == 1, "a text set by code reaches the list too, not onChange")
sbox:SetFocus()
sbox:GetScript("OnEscapePressed")(sbox)
assertTrue(search:GetText() == "" and searched[#searched] == "" and sbox:HasFocus(), "Escape empties it first")
sbox:GetScript("OnEscapePressed")(sbox)
assertTrue(not sbox:HasFocus(), "then leaves")

-- Text areas ------------------------------------------------------------------------------

local areaCommits = {}
local notes = body:TextArea{ label = "Notes", boxHeight = 60, maxLetters = 200, value = "abc",
    onChange = function(text) areaCommits[#areaCommits + 1] = text end }
layout()
assertTrue(notes.line:GetHeight() == 60 and notes.kitPH >= 72, "boxHeight is the box's height: " .. notes.kitPH)
assertTrue(notes.counter:IsShown() and notes.counter:GetText() == "3 / 200", "the count: " .. notes.counter:GetText())
local nbox, scroll = notes.box, notes.scroll
assertTrue(nbox.parent.parent == scroll and scroll.kind == "ScrollFrame", "the box scrolls")
assertTrue(nbox.multi and not nbox:GetScript("OnEnterPressed"), "Enter makes a new line")
assertTrue(not scroll.wheel, "a text area leaves the wheel to the page")
nbox:SetFocus()
assertTrue(scroll.wheel, "until it has focus")
type_(nbox, "abcd\nnext")
assertTrue(notes.counter:GetText() == "9 / 200", "the count follows the text")
nbox:GetScript("OnEscapePressed")(nbox)
assertTrue(notes:GetText() == "abc" and not scroll.wheel and #areaCommits == 0, "Escape restores, and gives the wheel back")
nbox:SetFocus()
type_(nbox, "a line")
nbox:ClearFocus()
assertTrue(areaCommits[1] == "a line", "leaving commits")
notes.boxFrame:GetScript("OnMouseDown")(notes.boxFrame)
assertTrue(nbox:HasFocus(), "a click anywhere on the box focuses the text")
nbox:ClearFocus()

-- Money -------------------------------------------------------------------------------------

-- Coloured coins, plain only while typed in; clicking in and out changes
-- nothing.
local moneyChanges, moneyLast = 0, nil
local money = body:MoneyInput{ value = 12005, label = "Price", onChange = function(copper) moneyChanges = moneyChanges + 1; moneyLast = copper end }
local mbox = money.box
assertTrue(mbox:GetText():find("|cff", 1, true), "a money field shows coloured coins: " .. mbox:GetText())
assertTrue(money.preview:GetText() ~= "", "and the amount beside it")
mbox:SetFocus()
assertTrue(mbox:GetText() == "1g 20s 5c", "plain while typed in: " .. mbox:GetText())
mbox:ClearFocus()
assertTrue(mbox:GetText():find("|cff", 1, true) and moneyChanges == 0 and money:GetValue() == 12005,
    "coloured again after, with no change made")
mbox:SetFocus()
type_(mbox, "2g")
mbox:ClearFocus()
assertTrue(money:GetValue() == 20000 and moneyChanges == 1 and moneyLast == 20000 and mbox:GetText():find("|cff", 1, true),
    "a typed amount commits, coloured")
mbox:SetFocus()
type_(mbox, "lots")
mbox:GetScript("OnEnterPressed")(mbox)
assertTrue(money:IsInvalid() and money:GetValue() == 20000 and moneyChanges == 1, "a typo is refused")
mbox:SetFocus()
type_(mbox, "")
mbox:GetScript("OnEnterPressed")(mbox)
assertTrue(money:GetValue() == nil and moneyLast == nil and moneyChanges == 2 and money.preview:GetText() == "", "emptied: no amount")
money:SetValue(500)
assertTrue(money:GetValue() == 500 and moneyChanges == 2, "SetValue is silent")
local guess = body:MoneyInput{ guess = 4000, boxWidth = 90 }
assertTrue(guess.box.placeholder:IsShown() and guess.box.placeholder:GetText():find("a guess", 1, true), "a guess shows as the placeholder")
assertTrue(guess.kitPlaceholderColor == "estimate" and guess.box.width == 90 and guess:GetValue() == nil, "in the estimate colour; boxWidth")
local mdb = { price = 300 }
local boundMoney = body:MoneyInput{ bind = { mdb, "price" } }
assertTrue(boundMoney:GetValue() == 300 and boundMoney:IsStored(), "a bound amount")
boundMoney:Reset()
assertTrue(mdb.price == nil and boundMoney:GetValue() == nil and boundMoney:GetText() == "", "reset to nothing")
-- In a table's cell: no amount beside it and no line under it; what is
-- wrong goes to onInvalid.
local invalid
local cellMoney = body:MoneyInput{ boxWidth = 70, preview = false, compact = true, value = 100,
    onInvalid = function(message) invalid = message end }
assertTrue(not cellMoney.preview:IsShown() and cellMoney:NaturalWidth() == 70, "no amount beside it")
cellMoney.box:SetFocus()
type_(cellMoney.box, "lots")
cellMoney.box:GetScript("OnEnterPressed")(cellMoney.box)
assertTrue(cellMoney:IsInvalid() and invalid ~= nil and not cellMoney.message:IsShown() and cellMoney:GetValue() == 100,
    "a typo goes to onInvalid, not under the box")

-- Numbers ------------------------------------------------------------------------------------

local numberChanges = {}
local count
count = body:NumberInput{ label = "Count", value = 5, min = 1, max = 20,
    onChange = function(n, w) numberChanges[#numberChanges + 1] = n; assertTrue(w == count, "onChange gets the field") end }
local cbox = count.box
assertTrue(count:GetValue() == 5 and count:GetText() == "5", "a number shows its value")
assertTrue(count.message:GetText() == "1 to 20", "the range is its help")
count.plus:Click()
assertTrue(count:GetValue() == 6 and numberChanges[1] == 6, "+ steps it")
count.minus:Click()
assertTrue(count:GetValue() == 5 and numberChanges[2] == 5, "- steps it back")
count:SetValue(50)
assertTrue(count:GetValue() == 20 and #numberChanges == 2, "SetValue holds to the range, silently")
count.plus:Click()
assertTrue(#numberChanges == 2 and count:GetValue() == 20, "at the top, + changes nothing")
-- The wheel steps it only while it has focus.
assertTrue(not cbox.wheel, "a number field leaves the wheel to the page")
cbox:SetFocus()
assertTrue(cbox.wheel, "until it has focus")
cbox:GetScript("OnMouseWheel")(cbox, -1)
assertTrue(count:GetValue() == 19 and numberChanges[3] == 19, "then the wheel steps it")
cbox:GetScript("OnArrowPressed")(cbox, "DOWN")
assertTrue(count:GetValue() == 18, "DOWN steps it")
cbox:ClearFocus()
assertTrue(not cbox.wheel and #numberChanges == 4, "and gives the wheel back, with no second commit")
cbox:SetFocus()
type_(cbox, "abc")
cbox:GetScript("OnEnterPressed")(cbox)
assertTrue(count:IsInvalid() and count.message:GetText() == "A number from 1 to 20.", "a typo is refused")
cbox:SetFocus()
type_(cbox, "99")
cbox:GetScript("OnEnterPressed")(cbox)
assertTrue(count:GetValue() == 20 and numberChanges[5] == 20 and count:GetText() == "20", "a typed number is held to the range")
count:SetEnabled(false)
assertTrue(not count.minus:IsEnabled() and not count.plus:IsEnabled(), "disabled, the - and + too")
count:SetEnabled(true)
local ndb = {}
local bound = body:NumberInput{ bind = { ndb, "n" }, default = 3, step = 2 }
bound.plus:Click()
assertTrue(ndb.n == 5 and bound:IsStored(), "a bound number is stored by a step")
bound:Reset()
assertTrue(ndb.n == nil and bound:GetValue() == 3, "and reset to its default")

-- Toggles ------------------------------------------------------------------------------------

-- The benchmark screen's form: a caption and a bind.
local tdb = {}
local toggle = body:Toggle{ "Sell back", bind = { tdb, "sell" } }
assertTrue(toggle:GetValue() == false and toggle:GetText() == "Sell back" and not toggle:IsStored(), "off, not stored")
toggle:Click()
assertTrue(toggle:GetValue() == true and tdb.sell == true and toggle:IsStored(), "a click turns it on, into the table")
toggle:Reset()
assertTrue(tdb.sell == nil and toggle:GetValue() == false, "Reset forgets it")
local heard = {}
local lit
lit = body:Toggle{ "Lit", default = true, onChange = function(on, w) heard[#heard + 1] = on; assertTrue(w == lit, "onChange gets the toggle") end }
assertTrue(lit:GetValue() == true and lit:GetChecked(), "on by default")
lit:SetValue(false)
lit:SetChecked(true)
assertTrue(#heard == 0, "SetValue and SetChecked are silent")
lit:Click()
assertTrue(heard[1] == false and not lit:GetValue(), "a click tells onChange")
lit:Reset()
assertTrue(heard[2] == true and lit:GetValue() == true, "Reset tells onChange the default")
lit:SetValue(false)
local offDb = { on = false }
local off = body:Toggle{ "Off", bind = { offDb, "on" }, default = true, onChange = function(on) heard[#heard + 1] = on end }
assertTrue(off:GetValue() == false and off:IsStored(), "false in the table is a stored choice")
off:Reset()
assertTrue(off:GetValue() == true and heard[3] == true, "reset to the default")
lit:Reset()
lit:SetValue(true)
layout()
local width = lit.kitPW
local fonts = 0
local setFont = lit.label.SetFont
lit.label.SetFont = function(...) fonts = fonts + 1; return setFont(...) end
lit:GetScript("OnEnter")(lit)
lit:GetScript("OnLeave")(lit)
lit.label.SetFont = nil
assertTrue(fonts == 0 and UI.LayoutSettled() and lit.kitPW == width, "hover sets no font and lays nothing out")
local disabled = body:Toggle{ "Nope", disabled = "Not yet" }
disabled:Click()
assertTrue(disabled:GetValue() == false and disabled.kitReason == "Not yet", "a disabled toggle does not change")
lit:SetText("Lit up")
layout()
assertTrue(lit.kitPW > width, "a longer caption is wider")

-- Sliders ------------------------------------------------------------------------------------

local slid = {}
local slider
slider = body:Slider{ label = "Scale", min = 0, max = 10, step = 1, value = 4, format = "%d%%",
    onChange = function(v, w) slid[#slid + 1] = v; assertTrue(w == slider, "onChange gets the slider") end }
layout()
local bar = slider.slider
assertTrue(slider:GetValue() == 4 and slider.readout:GetText() == "4%", "a slider shows its value: " .. slider.readout:GetText())
assertTrue(slider.kitPH == 36, "labelled, it is 36 tall")
-- The wheel passes over it to the page until the player takes hold of it.
assertTrue(not bar.wheel, "a slider leaves the wheel to the page")
bar:Fire("OnMouseDown", "LeftButton")
assertTrue(bar.wheel and slider.kitHeld, "until it is pressed, and shows it holds the wheel")
bar:GetScript("OnMouseWheel")(bar, 1)
assertTrue(slider:GetValue() == 5 and slid[1] == 5, "then the wheel moves it")
bar:Fire("OnLeave")
assertTrue(not bar.wheel and not slider.kitHeld, "and gives it back when the pointer leaves")
bar:SetValue(7.2)
assertTrue(slider:GetValue() == 7 and slid[2] == 7, "a drag commits, on the step")
bar.kitKeyArrow(bar, "LEFT")
assertTrue(slider:GetValue() == 6, "an arrow moves it")
slider:SetValue(9)
assertTrue(slider:GetValue() == 9 and #slid == 3 and slider.readout:GetText() == "9%", "SetValue is silent")
for _ = 1, 3 do bar:GetScript("OnMouseWheel")(bar, 1) end
assertTrue(slider:GetValue() == 10, "held to the range")
local sdb = {}
local plain = body:Slider{ bind = { sdb, "v" }, default = 30 }
assertTrue(plain:GetValue() == 30 and not plain:IsStored(), "a bound slider shows its default")
plain.slider:SetValue(40)
assertTrue(sdb.v == 40 and plain:IsStored(), "a move is stored")
plain:Reset()
assertTrue(sdb.v == nil and plain:GetValue() == 30, "and reset")
layout()
assertTrue(plain.kitPH == 18, "unlabelled, 18 tall")

-- Settings ----------------------------------------------------------------------------------

-- A bound control: the reset shows while it is stored, and resets it.
local setDb = {}
local settingHeard = {}
local setting = body:Setting{ "Sell back", help = "Sell what the route makes.", default = "on" }
local sell = setting:Toggle{ bind = { setDb, "sell" }, default = true, onChange = function(on) settingHeard[#settingHeard + 1] = on end }
layout()
assertTrue(sell.kitParent == setting.controls and setting:GetControl() == sell, "the control goes in the setting, watched")
assertTrue(setting.label:GetText() == "Sell back" and setting.help:IsShown(), "the name and help beside it")
assertTrue(setting.about.kitPW == 260, "the name takes labelWidth: " .. tostring(setting.about.kitPW))
assertTrue(not setting.reset:IsShown(), "no reset while the default applies")
sell:Click()
assertTrue(setDb.sell == false and settingHeard[1] == false and setting.reset:IsShown(), "a change shows the reset, and onChange still hears it")
setting.reset:Click()
assertTrue(setDb.sell == nil and sell:GetValue() == true and not setting.reset:IsShown(), "the reset resets the control")
assertTrue(settingHeard[2] == true, "and onChange hears the reset")
setDb.sell = false
sell:SetValue(false)
setting:Refresh()
assertTrue(setting.reset:IsShown(), "Refresh after code changed the table")
setting.reset:Click()
layout()

-- The old way: SetChanged and onReset.
local resets = 0
local route = body:Setting{ "Route by", labelWidth = 200, onReset = function(s) resets = resets + 1; s:SetChanged(false) end }
route:Slider{ min = 1, max = 5 }
layout()
assertTrue(route.about.kitPW == 200 and not route.help:IsShown(), "labelWidth, no help")
assertTrue(not route.reset:IsShown(), "no reset until changed")
route:SetChanged(true)
assertTrue(route.reset:IsShown(), "a changed setting shows its reset")
route.reset:Click()
assertTrue(resets == 1 and not route.reset:IsShown(), "and the reset puts it back")
local plainSetting = body:Setting{ "Nothing to reset" }
plainSetting:Input{ value = "x" }
plainSetting:SetChanged(true)
assertTrue(not plainSetting.reset:IsShown(), "without onReset or a bound control, no reset")

-- Choices ----------------------------------------------------------------------------------

local picked = {}
local choices
choices = body:Choices{ "Kill", "Loot", { value = "Collect", caption = "Collect", tooltip = "Gather things" }, "Talk",
    { value = "Use", caption = "Use an item", disabled = "Not yet" },
    value = "Kill", onChange = function(v, w) picked[#picked + 1] = v; assertTrue(w == choices, "onChange gets the choices") end }
layout()
assertTrue(#choices.buttons == 5 and #choices.kitChildren == 2, "five choices in rows of three")
assertTrue(#choices.kitChildren[2].kitChildren == 3, "the last row keeps the others' widths")
assertTrue(choices.buttons[1]:IsActive() and choices:GetValue() == "Kill", "the value is picked")
choices.buttons[3]:Click()
local active = 0
for _, b in ipairs(choices.buttons) do if b:IsActive() then active = active + 1 end end
assertTrue(choices:GetValue() == "Collect" and active == 1 and picked[1] == "Collect", "a click picks one choice, and only one")
choices.buttons[3]:Click()
assertTrue(#picked == 1, "the same pick is no change")
choices.buttons[5]:Click()
assertTrue(choices:GetValue() == "Collect" and choices.buttons[5].kitReason == "Not yet", "a disabled choice cannot be picked")
choices:SetValue("Talk")
assertTrue(#picked == 1 and choices.buttons[4]:IsActive() and not choices.buttons[3]:IsActive(), "SetValue is silent")
-- The layout sizes a choice: hover repaints it without changing its width.
local choice = choices.buttons[1]
local choiceWidth = choice.kitPW
choice:GetScript("OnEnter")(choice)
choice:GetScript("OnLeave")(choice)
assertTrue(choice.kitPW == choiceWidth and UI.LayoutSettled(), "hovering a choice leaves its width")
assertTrue(math.abs(choices.buttons[2].kitPW - choiceWidth) <= 1, "choices share a row evenly")
local cdb = { kind = "b" }
local boundChoices = body:Choices{ "a", "b", columns = 2, bind = { cdb, "kind" }, default = "a" }
assertTrue(boundChoices:GetValue() == "b" and boundChoices:IsStored(), "bound choices")
boundChoices.buttons[1]:Click()
assertTrue(cdb.kind == "a", "a pick is stored")
boundChoices:Reset()
assertTrue(cdb.kind == nil and boundChoices:GetValue() == "a", "reset")
layout()

-- The Tab chain -------------------------------------------------------------------------------

local tabWin, tabBody = window(500, 400)
local a = tabBody:Input{ label = "A" }
local b = tabBody:Input{ label = "B" }
local t = tabBody:Toggle{ "Between" }
local c = tabBody:NumberInput{ value = 1 }
layout()
local function tab(field) field.box:GetScript("OnTabPressed")(field.box) end
a:SetFocus()
tab(a)
assertTrue(b:HasFocus() and not a:HasFocus(), "Tab goes to the next field")
tab(b)
assertTrue(c:HasFocus(), "past what is not a field")
tab(c)
assertTrue(a:HasFocus(), "and round to the first")
b:SetEnabled(false)
tab(a)
assertTrue(c:HasFocus(), "a disabled field is passed over")
b:SetEnabled(true)
local shift = IsShiftKeyDown
IsShiftKeyDown = function() return true end
tab(c)
assertTrue(b:HasFocus(), "Shift-Tab goes back")
IsShiftKeyDown = shift
-- Tab commits what was typed.
local tabCommits = 0
local d = tabBody:Input{ onChange = function() tabCommits = tabCommits + 1 end }
d:SetFocus()
type_(d.box, "typed")
tab(d)
assertTrue(tabCommits == 1 and a:HasFocus(), "Tab commits and moves on")
-- Full keyboard control: Tab reaches the toggle too.
tabWin.kitKeyboard = true
b:SetFocus()
tab(b)
assertTrue(tabWin.kitFocused == t and not b:HasFocus(), "under full keyboard control Tab reaches a toggle")
tabWin.kitKeyboard = nil
UI.FocusWidget(tabWin, nil)
-- A chain of the caller's own: in a window, the window's order.
ui:TabChain({ c, a })
c:SetFocus()
tab(c)
assertTrue(a:HasFocus(), "a TabChain orders the window")
tabWin.kitTabOrder = nil
a:ClearFocus()
-- Outside a window: Tab along the list.
local x = ui:Input(UIParent, { label = "X" })
local y = ui:Input(UIParent, { label = "Y" })
local z = ui:Input(UIParent, { label = "Z" })
ui:TabChain({ x, z, y })
x:SetFocus()
tab(x)
assertTrue(z:HasFocus() and not x:HasFocus(), "a chain outside a window")
tab(z)
tab(y)
assertTrue(x:HasFocus(), "round the chain")
x:ClearFocus()
-- UI.ClearTypingFocus finds the kit's own boxes.
local focusGetter = GetCurrentKeyBoardFocus
GetCurrentKeyBoardFocus = function() return y.box end
y:SetFocus()
UI.ClearTypingFocus()
assertTrue(not y:HasFocus(), "ClearTypingFocus takes the focus from a field")
GetCurrentKeyBoardFocus = focusGetter
x:Release()
y:Release()
z:Release()

-- Looks repaint fields ----------------------------------------------------------------------

ui:SetLook({ theme = "slate", textSize = "large" })
layout()
assertTrue(name.kitBand > 16, "a larger text size moves the box down: " .. name.kitBand)
ui:SetLook({})
layout()

-- A clear and rebuild from the pool ----------------------------------------------------------

local _, poolBody = window(600, 1400)
local oldCalls = 0
local function old() oldCalls = oldCalls + 1 end
local list1 = { moves = {}, activated = 0, MoveSelection = function() end, Activate = function() end }

local function build(round)
    local w = {}
    if round == 1 then
        w.input = poolBody:Input{ label = "Old", help = "Old help", placeholder = "Old placeholder", maxLetters = 5,
            numeric = true, value = "old", validate = function() return "never" end, onChange = old, onType = old }
        w.search = poolBody:Search{ value = "old search", onType = old, onChange = old }
        w.area = poolBody:TextArea{ label = "Old area", maxLetters = 50, value = "old text", boxHeight = 40, onChange = old }
        w.money = poolBody:MoneyInput{ guess = 100, value = 5, onChange = old, boxWidth = 60 }
        w.number = poolBody:NumberInput{ value = 7, min = 5, max = 9, onChange = old }
        w.toggle = poolBody:Toggle{ "Old toggle", value = true, onChange = old }
        w.slider = poolBody:Slider{ label = "Old slider", min = 0, max = 10, value = 8, format = "%d!", onChange = old }
        w.setting = poolBody:Setting{ "Old setting", help = "Old", onReset = old }
        w.settingToggle = w.setting:Toggle{ bind = { {}, "k" }, value = true }
        w.choices = poolBody:Choices{ "p", "q", "r", "s", "t", value = "q", onChange = old }
    else
        w.input = poolBody:Input{ onChange = function() w.inputCommits = (w.inputCommits or 0) + 1 end }
        w.search = poolBody:Search{ placeholder = "New" }
        w.area = poolBody:TextArea{ value = "new" }
        w.money = poolBody:MoneyInput{}
        w.number = poolBody:NumberInput{ min = 0, max = 3 }
        w.toggle = poolBody:Toggle{ "New toggle" }
        w.slider = poolBody:Slider{ min = 100, max = 200 }
        w.setting = poolBody:Setting{ "New setting" }
        w.settingToggle = w.setting:Toggle{ "plain" }
        w.choices = poolBody:Choices{ "u", "v", "w", "z", columns = 2 }
    end
    return w
end

local one = build(1)
layout()
-- Leave every one in some state a new use must not see.
one.input:SetInvalid("Old error")
one.input:SetFocus()
type_(one.input.box, "typed")
one.input:SetEnabled(true)
one.search.kitList = list1
ui:TabChain({ one.input, one.search })
one.area:SetFocus()
one.number:SetFocus()
one.slider.slider:Fire("OnMouseDown", "LeftButton")
one.slider.hover = true
one.toggle:GetScript("OnEnter")(one.toggle)
one.setting:SetChanged(true)
one.choices.buttons[4]:Click()
local callsBefore = oldCalls
layout()
local made = #objects

poolBody:Clear()
layout()
assertTrue(oldCalls == callsBefore, "clearing a focused, changed field commits nothing into its old callbacks")
local two = build(2)
layout()
assertTrue(#objects == made, "a rebuild takes every frame from the pools: " .. (#objects - made) .. " new")
assertTrue(two.input == one.input and two.toggle == one.toggle and two.choices == one.choices, "the same frames, from the pools")

-- Nothing of the last use survives.
local input = two.input
assertTrue(input:GetText() == "" and not input:IsInvalid() and not input:HasFocus(), "an input from the pool: no text, error or focus")
assertTrue(not input.label:IsShown() and not input.message:IsShown(), "no old label or help")
assertTrue(input.box.placeholder:GetText() == "" and input.box.maxLetters == 0 and input.box.numeric == false, "no old placeholder, limit or numeric")
assertTrue(input.box.kitChain == nil and input.box.kitBaseline == nil and not input.box.kitPooled, "no old chain or baseline")
assertTrue(ui.focusables[input.box] and input:IsEnabled(), "in the Tab order again, enabled")
assertTrue(input.kitValidate == nil and input.kitOnType == nil, "no old validate or onType")
input:SetFocus()
type_(input.box, "new")
input:ClearFocus()
assertTrue(two.inputCommits == 1 and oldCalls == callsBefore, "the new onChange only")
local search2 = two.search
assertTrue(search2.kitList == nil and search2:GetText() == "" and search2.box.placeholder:GetText() == "New", "a search from the pool: no list")
search2.box:GetScript("OnEnterPressed")(search2.box)
assertTrue(list1.activated == 0, "and the old list is not told")
local area = two.area
assertTrue(area:GetText() == "new" and not area.counter:IsShown() and area.kitBoxHeight == 90 and not area.label:IsShown(), "a text area from the pool")
assertTrue(not area:HasFocus() and not area.scroll.wheel, "without the focus or the wheel")
local money2 = two.money
assertTrue(money2:GetValue() == nil and money2:GetText() == "" and money2.preview:GetText() == "", "money from the pool: no amount")
assertTrue(money2.kitPlaceholderColor == nil and money2.box.placeholder:GetText() == "" and money2.box.width == 120, "no old guess or width")
local number2 = two.number
assertTrue(number2:GetValue() == nil and number2:GetText() == "" and not number2.box.wheel, "a number from the pool: no value, no wheel")
assertTrue(number2.message:GetText() == "0 to 3" and number2.kitMin == 0 and number2.kitMax == 3, "its new range")
number2.plus:Click()
assertTrue(number2:GetValue() == 1 and oldCalls == callsBefore, "steps from the new range, into no old onChange")
local toggle2 = two.toggle
assertTrue(toggle2:GetValue() == false and not toggle2.hover and toggle2:GetText() == "New toggle", "a toggle from the pool: off, not hovered")
toggle2:Click()
assertTrue(oldCalls == callsBefore and not toggle2:IsStored(), "no old onChange, no old table")
local slider2 = two.slider
assertTrue(slider2:GetValue() == 100 and not slider2.kitHeld and not slider2.slider.wheel and not slider2.hover, "a slider from the pool: not held")
assertTrue(not slider2.label:IsShown() and slider2.readout:GetText() == "100" and slider2.kitHeight == 18, "no old label or format")
slider2.slider:SetValue(150)
assertTrue(slider2:GetValue() == 150 and oldCalls == callsBefore, "no old onChange")
local setting2 = two.setting
assertTrue(setting2.label:GetText() == "New setting" and not setting2.help:IsShown() and not setting2.reset:IsShown(), "a setting from the pool: no help, no reset")
assertTrue(setting2:GetControl() == nil and two.settingToggle.kitParent == setting2.controls, "no old control watched")
local choices2 = two.choices
assertTrue(#choices2.buttons == 4 and choices2:GetValue() == nil, "choices from the pool: the new list, nothing picked")
for _, button in ipairs(choices2.buttons) do assertTrue(not button:IsActive(), "no old pick") end
choices2.buttons[1]:Click()
assertTrue(choices2:GetValue() == "u" and oldCalls == callsBefore, "a pick calls no old onChange")
