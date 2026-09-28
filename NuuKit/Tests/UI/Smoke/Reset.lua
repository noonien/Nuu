-- Released widgets are reset as far as their marks (w:Customize, flags) ask: what
-- an addon did to one with the plain API, and marked, does not reach the
-- widget's next use (the stand-in's SetToDefaults does what build 70009's
-- does; see Run.lua). The audit (Dev/Audit.lua) makes every wrong mark an
-- error: on release through the error handler, at a call with error().

local ctx = ...
local UI, ui, assertTrue, testWindow, layout, objects = ctx.UI, ctx.ui, ctx.assertTrue, ctx.testWindow, ctx.layout, ctx.objects

local _, body = testWindow(ui, 500, 400)
local Custom = ui.Custom
assertTrue(Custom == UI.Custom and Custom.frame + Custom.parts == 6, "the flags, on the UI too")
assertTrue(UI.resetMode == "marked", "the kit resets marked widgets by default")
-- The audit watches shared methods only: with methods copied on, the
-- marks are still tested, the audit's checks pass over.
local audited = UI.SetAudit(true)
assertTrue(audited == (UI.sharedMethods ~= false), "the audit runs on the stand-in, with shared methods")
UI.ClearAudit()

-- The client's error handler, as the audit reaches it on release.
local raised = {}
local handler = geterrorhandler
geterrorhandler = function() return function(message) raised[#raised + 1] = message end end

-- Whether an error matching `pattern` was raised on release since the last
-- look (every one raised is looked at once).
local seen = 0
local function raisedOnRelease(pattern)
    if not audited then return true end
    for index = seen + 1, #raised do
        if raised[index]:find(pattern) then
            seen = #raised
            return true
        end
    end
    return false
end

-- Whether fn raises an error matching `pattern` at the call.
local function raisesAtCall(pattern, fn, ...)
    if not audited then return true end
    local ok, message = pcall(fn, ...)
    return not ok and tostring(message):find(pattern) ~= nil
end

-- Alpha and scale need no mark: the widget's own SetAlpha and SetScale note
-- a change, and release puts back only that.
local plain = body:Button{ "Plain" }
plain:SetAlpha(0.5)
plain:SetScale(2)
body:Clear()
local plainAgain = body:Button{ "Plain again" }
assertTrue(plainAgain == plain and plainAgain.alpha == 1, "a changed alpha is put back without a mark")
assertTrue(plainAgain.kitFaded == nil and plainAgain.kitScaled == nil, "and the widget forgets it was changed")
assertTrue(#UI.auditLog == 0 or not audited, "alpha and scale are nothing to the audit")

-- Unmarked, any other change carries over, and the audit says so.
local function theirEnter() end
plainAgain:SetScript("OnEnter", theirEnter)
body:Clear()
local unmarked = body:Button{ "Unmarked" }
assertTrue(unmarked == plain and unmarked:GetScript("OnEnter") == theirEnter, "an unmarked change reaches the next use")
assertTrue(raisedOnRelease('NuuKit audit: Button: SetScript at .-Reset%.lua:%d+, not marked: w:Customize%(ui%.Custom%.frame%)'),
    "a missing mark is an error on release")
unmarked:Customize(Custom.frame):SetScript("OnEnter", nil)
body:Clear()

-- Marked for what it changed, and the audit is quiet.
UI.ClearAudit()
local listener = body:Button{ "Listener" }
listener:Customize(Custom.events):RegisterEvent("BAG_UPDATE")
body:Clear()
assertTrue(#raised == seen and #UI.auditLog == 0, "a right mark raises nothing: " .. table.concat(raised, "; ", seen + 1))

-- Marked for nothing, or broader than needed.
local idle = body:Button{ "Idle" }
idle:Customize(Custom.events)
body:Clear()
assertTrue(raisedOnRelease('marked Custom%.events at .-Reset%.lua:%d+, and nothing in that use needed it'),
    "a mark set and not used is an error")
local broad = body:Button{ "Broad" }
broad:Customize(Custom.frame):RegisterEvent("BAG_UPDATE")
body:Clear()
assertTrue(raisedOnRelease('marked Custom%.frame at .-; Custom%.events is enough'), "a broader mark is an error")

-- A frame made on it with the plain API is found by looking.
UI.ClearAudit()
local host = body:Button{ "Host" }
local theirFrame = CreateFrame("Frame", nil, host)
body:Clear()
assertTrue(raisedOnRelease('a frame or region made on it outside the kit'), "an addon's frame on it, unmarked, is an error")
assertTrue(theirFrame:IsShown(), "and left as it was: the audit changes nothing")
theirFrame:Hide()

-- A change after the widget was cleared.
assertTrue(raisesAtCall("SetFrameStrata at .-Reset%.lua:%d+ after it was cleared", function() host:SetFrameStrata("HIGH") end),
    "a change after a clear is an error at the call")

-- Wrong flags are an error at the call; right ones, or none, are not.
local flagged = body:Button{ "Flagged" }
assertTrue(raisesAtCall("Customize%(8%) at .-Reset%.lua:%d+: flags are", flagged.Customize, flagged, Custom.frame + Custom.frame),
    "a flag added twice is an error")
assertTrue(raisesAtCall("Customize%(frame%)", flagged.Customize, flagged, "frame"), "a string is an error")
assertTrue(raisesAtCall("Customize%(0%)", flagged.Customize, flagged, 0), "no flag is an error")
assertTrue(pcall(flagged.Customize, flagged, Custom.events + Custom.parts), "flags that add up are fine")
flagged:RegisterEvent("BAG_UPDATE")
flagged:CreateTexture()
-- An animation group, which no reset undoes, is an error at the call.
assertTrue(raisesAtCall("CreateAnimationGroup at .- is never undone", function() flagged:CreateAnimationGroup() end),
    "a change no reset undoes is an error at the call")
body:Clear()
assertTrue(#raised == seen, "the marks it had were what it needed")
UI.SetAudit(false)
assertTrue(pcall(flagged.Customize, flagged, 8), "without the audit, flags are not checked")
flagged.kitCustom = nil
UI.SetAudit(audited)
UI.ClearAudit()

local clicks, theirs = 0, {}
local button = body:Button{ "Mine", data = { id = 7 }, onClick = function() clicks = clicks + 1 end }
layout()
-- Everything: the frame and its parts.
button:Customize()
assertTrue(button.data.id == 7, "data is the spec's")

-- What an addon might do to it with the plain API.
button:SetScript("OnEnter", function() theirs.enter = true end)
button:HookScript("OnClick", function() theirs.click = true end)
button:SetAlpha(0.5)
button.theirField = "left behind"
local texture = button:CreateTexture()
local child = CreateFrame("Frame", nil, button)
local decoration = button:AddTexture("OVERLAY")
local caption = button:AddText("fine")
caption:SetText("new")
ui:Tooltip(button, "Its tooltip")
ui:OpenMenu({ { caption = "One" } }, { anchor = button })
assertTrue(UI.tipOwner == button and ui:MenuOpenFor(button), "a tooltip and a menu for it")

-- Cleared: it goes back, and what pointed at it lets go.
body:Clear()
assertTrue(UI.tipOwner == nil and not ui:MenuOpenFor(button), "its tooltip and its menu close")
assertTrue(button.data == nil and button.kitClick == nil and next(button.kitLayout) == nil,
    "the pool keeps nothing of the addon's: data, callbacks, spec")
assertTrue(not texture:IsShown() and not child:IsShown(), "the addon's own texture and frame are hidden")
assertTrue(not decoration:IsShown() and not caption:IsShown(), "decorations are put away")

-- Made again from the same frame: none of it comes back.
local made = #objects
local again = body:Button{ "Again", onClick = function() clicks = clicks + 10 end }
layout()
assertTrue(again == button, "the same frame, from the pool")
assertTrue(#objects == made, "no new frames")
assertTrue(again.data == nil, "no old data")
assertTrue(again.alpha == 1, "the alpha is the default again")
again:GetScript("OnEnter")(again)
assertTrue(again.hover and not theirs.enter, "the kit's hover, not the addon's script")
again:GetScript("OnLeave")(again)
again:Click()
assertTrue(clicks == 10 and not theirs.click, "the new onClick, and the addon's hook is gone")
assertTrue(not texture:IsShown() and not child:IsShown(), "the addon's own parts stay hidden")
assertTrue(again.label:IsShown() and again.plate.fill:IsShown(), "the kit's own parts show")

-- A decoration asked for again is the one put away.
assertTrue(again:AddTexture("OVERLAY") == decoration and decoration:IsShown(), "AddTexture takes the kept one again")
assertTrue(again:AddText("fine") == caption, "AddText too")
assertTrue(#objects == made, "and makes nothing")

-- Text widgets are font strings: reset, they get their font back.
body:Clear()
local text = body:Text{ "One" }
text:Customize(ui.Custom.frame):SetTextColor(1, 0, 0, 1)
body:Clear()
local text2 = body:Text{ "Two", style = "title" }
layout()
assertTrue(text2 == text and text2:GetText() == "Two" and text2.fontSize ~= nil, "a reset text takes text and its style again")

-- The focus ring lets go of a released widget.
local win = select(1, testWindow(ui, 300, 200))
local focusBody = win.kitInner
local field = focusBody:Button{ "Focus me" }
layout()
UI.FocusWidget(win, field)
focusBody:Clear()
assertTrue(win.kitFocused == nil, "the focus ring leaves a released widget")

assertTrue(#raised == seen, "the marks above are what their uses needed: " .. table.concat(raised, "; ", seen + 1))
UI.SetAudit(false)
geterrorhandler = handler

-- A strip from the pool is still clamped and movable: what Build set on the
-- frame is made again after the reset.
local stripCalls = {}
local strip = ui:StripPanel({ title = "Items" })
local setMovable, setClamped = strip.SetMovable, strip.SetClampedToScreen
strip:Slot{ item = 6948 }
strip:Release()
rawset(strip, "SetMovable", function(self, on) stripCalls.movable = on; return setMovable(self, on) end)
rawset(strip, "SetClampedToScreen", function(self, on) stripCalls.clamped = on; return setClamped(self, on) end)
UI.ResetFrame(strip, UI.types.StripPanel)
rawset(strip, "SetMovable", nil)
rawset(strip, "SetClampedToScreen", nil)
assertTrue(stripCalls.movable == true and stripCalls.clamped == true, "a reset strip is movable and clamped again")

