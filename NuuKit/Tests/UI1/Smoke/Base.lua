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
