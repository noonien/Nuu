-- Stacks, text, sections, tags, notices, cards; the layout pass.

local ctx = ...
local UI, ui, assertTrue, testWindow, layout = ctx.UI, ctx.ui, ctx.assertTrue, ctx.testWindow, ctx.layout

local win, body = testWindow(ui, 600, 700)
layout()

-- Text in a column: stretched across, as tall as its style.
local title = body:Text{ "Elwynn Forest", style = "title" }
local para = body:Text{ "From Northshire's gate to Goldshire and the farms around it.", wrap = true }
local row = body:Row{ gap = 8 }
local name = row:Text{ "Linen Cloth", grow = true }
local count = row:Text{ "9", style = "number" }
row:Spacer{}
layout()
assertTrue(title.kitPW and title.kitPW > 500, "a text stretches across its column: " .. tostring(title.kitPW))
assertTrue(title.kitPH >= 18, "a title is as tall as its style: " .. tostring(title.kitPH))
assertTrue(para.kitPH > 0, "a wrapped paragraph is laid out")
assertTrue(name.kitPW > count.kitPW, "a growing text takes the row's spare room")

-- A change of text lays out its row again, and nothing above it while the
-- row's size stays; the same text does nothing.
local laid = {}
for _, stack in ipairs({ body, row }) do
    local layoutFn = stack.StackLayout
    stack.StackLayout = function(self) laid[self] = (laid[self] or 0) + 1; return layoutFn(self) end
end
local width = count.kitPW
count:SetText("10")
assertTrue(not UI.LayoutSettled(), "a new text waits for the pass")
layout()
assertTrue(count.kitPW > width, "a longer count is wider")
assertTrue(laid[row] == 1 and not laid[body], "only the row lays out again: row " .. tostring(laid[row]) .. ", column " .. tostring(laid[body]))
count:SetText("10")
assertTrue(UI.LayoutSettled(), "the same text changes nothing")
row.StackLayout, body.StackLayout = nil, nil
row.StackLayout, body.StackLayout = UI.Stack.StackLayout, UI.Stack.StackLayout

-- A hidden child gives up its room.
local before = row.kitPH
local tall = row:Text{ "Tall", style = "title" }
layout()
assertTrue(row.kitPH >= before, "a taller child makes the row taller")
tall:Hide()
layout()
assertTrue(row.kitPH == before, "hidden, it gives the height back: " .. row.kitPH .. " vs " .. before)

-- Sections: a heading, a body that folds, a hint and a reset.
local reset = 0
local section = body:Section{ "Route", hint = "9 legs to 225", foldable = true,
    reset = { stored = true, default = "cheapest", onReset = function() reset = reset + 1 end } }
local inside = section:Text{ "Leg one" }
layout()
assertTrue(inside.kitParent == section.body, "what is made on a section goes in its body")
assertTrue(section.reset:IsShown(), "the reset shows while the choice is stored")
section.reset:Click()
assertTrue(reset == 1, "the reset calls onReset")
local open = section.kitPH
section.toggle:Click()
layout()
assertTrue(not section:IsOpen() and section.kitPH < open, "a folded section is shorter")
section:SetOpen(true)
section:SetStored(false)
layout()
assertTrue(not section.reset:IsShown(), "no reset once the default applies")

-- Tags, notices, cards.
local tag = body:Tag{ "3 guessed", tone = "estimate" }
local notice = body:Notice{ "3 prices are guesses.", tone = "warning", action = { caption = "Set them" }, dismiss = true }
local card = body:Card{ tone = "accent" }
card:Text{ "Kobold Vermin", style = "heading" }
card:Text{ "Most are at the camp north of the abbey, past the lumber pile.", wrap = true }
layout()
assertTrue(tag.kitPW > 20 and tag.kitPW < 200, "a tag is as wide as its words: " .. tostring(tag.kitPW))
assertTrue(notice.kitPH >= 34, "a notice is at least one line tall")
assertTrue(card.kitPH > 40, "a card is as tall as what it holds: " .. tostring(card.kitPH))
notice.close:Click()
layout()
assertTrue(not notice:IsShown(), "a notice dismisses")

-- States put the content aside.
body:SetState("loading", "Reading recipes")
layout()
assertTrue(not title:IsShown(), "a state hides the content")
body:SetState(nil)
layout()
assertTrue(title:IsShown(), "the content comes back")

-- Looks repaint, and a new text size measures again.
local height = title.kitPH
ui:SetLook({ theme = "slate", textSize = "large" })
layout()
assertTrue(title.kitPH > height, "a larger text size makes a title taller: " .. title.kitPH .. " vs " .. height)
ui:SetLook({ theme = "midnight" })
layout()

-- A type defined after stacks were made (an addon defining its own late, on
-- a kit another addon already built with) is made in those stacks too.
UI.Define("SmokeLateType", {
    Build = function() end,
    Init = function() end,
    methods = { Measure = function() return 10, 10 end },
})
-- (Not with methods copied onto frames: those keep the makers they had.)
if UI.sharedMethods then
    local late = body:SmokeLateType{}
    assertTrue(late and late.kitType == "SmokeLateType", "a stack made earlier makes a type defined later")
    body:Remove(late)
end
UI.types.SmokeLateType = nil

-- Icons, chips, and a notice's action as a button.
do
    local _, col = testWindow(ui, 600, 400)
    local icon = col:Icon{ "Interface/GossipFrame/AvailableQuestIcon", fallback = "!", color = "quest", size = 18 }
    layout()
    assertTrue(icon.kitPW == 18 and icon.texture:IsShown(), "an icon at its size")
    icon:SetIcon(nil, "?")
    assertTrue(not icon.texture:IsShown() and icon.fallback:GetText() == "?", "the fallback where no texture loads")
    local removed = 0
    local chip = col:Chip{ "Executor Zygand", initials = "EZ", hint = "Brill 61.9, 52.3", onRemove = function() removed = removed + 1 end }
    local bare = col:Chip{ "Vital Intelligence", tone = "quest" }
    layout()
    assertTrue(chip.badge:IsShown() and chip.initials:GetText() == "EZ" and chip.hint:IsShown(), "initials and a hint")
    assertTrue(chip.kitPW > bare.kitPW and chip.close:IsShown() and not bare.close:IsShown(), "the mark only with onRemove")
    chip.close:Click()
    assertTrue(removed == 1, "the mark takes it out")
    local withIcon = col:Chip{ "Vital Intelligence", icon = "Interface/GossipFrame/ActiveQuestIcon", tone = "quest" }
    layout()
    assertTrue(withIcon.icon:IsShown() and not withIcon.badge:IsShown(), "an icon instead of initials")
    col:Remove(chip)
    local pooled = col:Chip{ "Plain" }
    assertTrue(pooled == chip and not pooled.hint:IsShown() and not pooled.badge:IsShown() and not pooled.close:IsShown(),
        "a pooled chip keeps nothing")
    local fixed = 0
    local notice = col:Notice{ "Nothing in this guide accepts this quest.", tone = "warning",
        action = { caption = "Make it optional", button = true, onClick = function() fixed = fixed + 1 end } }
    layout()
    assertTrue(notice.actionButton and notice.actionButton:IsShown() and not (notice.action and notice.action:IsShown()),
        "the action as a button")
    notice.actionButton:Click()
    assertTrue(fixed == 1, "which acts")
    col:Remove(notice)
    local linked = col:Notice{ "Plain", action = { caption = "Undo", onClick = function() end } }
    assertTrue(linked == notice and not linked.actionButton:IsShown() and linked.action:IsShown(), "a pooled notice takes the link again")
end
