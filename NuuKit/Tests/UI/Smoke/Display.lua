-- Progress bars, segment bars, strips of slots and the look picker.

local ctx = ...
local UI, ui, assertTrue, testWindow, layout, tick, objects, Object =
    ctx.UI, ctx.ui, ctx.assertTrue, ctx.testWindow, ctx.layout, ctx.tick, ctx.objects, ctx.Object

-- Colours as the client would hold them, to check what is painted.
function Object:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Object:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
local function same(color, expected, alphaScale)
    if not color or not expected then return false end
    for i = 1, 3 do if math.abs(color[i] - expected[i]) > 1e-6 then return false end end
    return math.abs((color[4] or 1) - (expected[4] or 1) * (alphaScale or 1)) < 1e-6
end

local _, body = testWindow(ui, 700, 1400)

-- Progress bars ----------------------------------------------------------------------------

local bar = body:ProgressBar{ label = "Crafts", value = 3, max = 10 }
layout()
local t = ui.tokens
assertTrue(bar.readout.text == "3 / 10" and bar.label.text == "Crafts", "the label and the readout")
assertTrue(bar.kitPH == 16 + 8 + 2, "a label row and the bar: " .. tostring(bar.kitPH))
local width = bar:GetWidth()
assertTrue(width > 100 and math.abs(bar.fill.width - UI.Snap(bar, width * 0.3)) < 1e-6, "the fill is its share: " .. bar.fill.width)
assertTrue(same(bar.fill.color, t.accent), "the fill is the accent by default")
bar:SetValue(5)
assertTrue(bar.readout.text == "5 / 10" and math.abs(bar.fill.width - UI.Snap(bar, width * 0.5)) < 1e-6, "SetValue")
bar:SetMax(20)
assertTrue(bar.readout.text == "5 / 20" and bar:GetMax() == 20, "SetMax")
bar:SetValue(0)
assertTrue(not bar.fill.shown, "nothing done, no fill")
bar:SetValue(8, 16)
assertTrue(bar.readout.text == "8 / 16" and bar.fill.shown, "SetValue with a new max")
bar:SetLabel("Leather")
assertTrue(bar.label.text == "Leather", "SetLabel")
bar:SetMarks({ { at = 4, caption = "Half", tone = "success" }, { at = 12 } })
layout()
assertTrue(bar.kitPH == 16 + 8 + 18 + 2, "a mark with a caption takes a row: " .. tostring(bar.kitPH))
assertTrue(bar.markTicks[1].shown and bar.markLabels[1].text == "Half" and same(bar.markTicks[1].color, t.done or UI.Tone(t, "success")),
    "a mark's tick and caption in its tone")
assertTrue(same(bar.markTicks[2].color, t.muted), "a mark without a tone is muted")
bar:SetMarks({ { at = 2 } })
layout()
assertTrue(not bar.markTicks[2].shown and bar.kitPH == 26, "fewer marks hide the rest; no caption, no row")
bar:SetTone("danger")
assertTrue(same(bar.fill.color, t.danger) and same(bar.readout.textColor, t.danger), "SetTone colours the fill and readout")

-- Busy: a moving run, stopped when not busy; still under reduceMotion.
bar:SetBusy(true)
assertTrue(bar:GetScript("OnUpdate") ~= nil and bar.run.shown and not bar.fill.shown, "busy runs")
assertTrue(bar.readout.text == "", "busy has no readout")
tick()
assertTrue(bar.run:GetNumPoints() == 3, "the run moves along the track")
bar:Hide()
assertTrue(bar:GetScript("OnUpdate") == nil, "a hidden bar stops its run")
bar:Show()
assertTrue(bar:GetScript("OnUpdate") ~= nil, "and starts again when shown")
bar:SetBusy(false)
assertTrue(bar:GetScript("OnUpdate") == nil and not bar.run.shown and bar.readout.text == "8 / 16", "not busy: stopped, the readout back")
ui:SetLook({ reduceMotion = true })
bar:SetBusy(true)
assertTrue(bar:GetScript("OnUpdate") == nil and bar.run.shown, "under reduceMotion the run sits still")
assertTrue(math.abs(bar.run.width - bar:GetWidth() * 0.33) < 1e-6, "over a third")
ui:SetLook({})
assertTrue(bar:GetScript("OnUpdate") ~= nil, "a look without reduceMotion starts it moving")
ui:SetLook({ reduceMotion = true })
assertTrue(bar:GetScript("OnUpdate") == nil, "and one with it stills it")
ui:SetLook({})

-- Released: stopped; from the pool: the new spec only.
local formatted = body:ProgressBar{ value = 1, max = 4, format = function(v, m) return v .. " of " .. m end }
assertTrue(formatted.readout.text == "1 of 4", "format")
body:Remove(bar)
assertTrue(bar.kitPooled and bar:GetScript("OnUpdate") == nil, "a released bar is stopped")
local made = #objects
local again = body:ProgressBar{ showValue = false, barHeight = 12 }
layout()
assertTrue(again == bar and #objects == made, "a bar comes from the pool")
assertTrue(not again:IsBusy() and not again.run.shown and again:GetScript("OnUpdate") == nil, "not busy")
assertTrue(again.readout.text == "" and again.label.text == "" and again.kitPH == 12 + 2, "no label row, its own bar height")
assertTrue(not again.markTicks[1].shown and same(again.fill.color, t.accent), "no marks, the default tone")
local busy = body:ProgressBar{ busy = true, label = "Reading" }
assertTrue(busy:GetScript("OnUpdate") ~= nil, "busy from the spec")
busy:Release()

-- Segment bars ----------------------------------------------------------------------------

-- Values to places and back, runs and marks where they fall, and the value
-- under the cursor for a click, a drag and a tooltip.
local picks, asked = {}, {}
local segBar = ui:SegmentBar(UIParent, { min = 0, max = 10, scrub = true,
    segments = { { from = 2, to = 5, tone = "success" }, { from = 5, to = 6, tone = "accent", style = "outline" } },
    marks = { { at = 5.5, kind = "pointer" }, { at = 8, tone = "accent" } },
    onPick = function(value) picks[#picks + 1] = value end,
    tooltipFor = function(value) asked[#asked + 1] = value; return "Step " .. math.floor(value) + 1 end })
assertTrue(segBar:NaturalHeight() == 8 + 8 + 3, "room for a pointer above and a line's overhang below: " .. segBar:NaturalHeight())
segBar:SetSize(400, segBar:NaturalHeight())
assertTrue(segBar:XOf(5) == 200 and segBar:ValueAt(200) == 5 and segBar:XOf(99) == 400, "values map to places and back, held to the range")
local fill
for _, o in ipairs(objects) do if o.parent == segBar and o.kind == "Texture" and o.kitSegment then fill = o end end
assertTrue(fill and fill.points[1][4] == 80 and fill.width == 120, "a run covers its values: " .. tostring(fill and fill.points[1][4]))
assertTrue(same(fill.color, UI.Tone(t, "success")), "in its tone")
local outlined = segBar.kitParts.outlines[1]
assertTrue(outlined and outlined.shown and outlined.width == 40, "an outlined run is drawn as a box")
assertTrue(segBar.kitParts.pointers[1].shown and segBar.kitParts.lines[1].shown, "a pointer and a line")
segBar:SetRange(0, 20)
assertTrue(segBar:XOf(5) == 100 and fill.width == 60, "SetRange moves the runs")
segBar:SetRange(0, 10)
_G.GetCursorPosition = function() return 300, 300 end  -- 200 in from the bar's left at 100
segBar:GetScript("OnMouseDown")(segBar, "LeftButton")
assertTrue(picks[1] == 5, "a click picks the value under the cursor: " .. tostring(picks[1]))
_G.GetCursorPosition = function() return 340, 300 end
segBar:GetScript("OnUpdate")(segBar, 0.016)
assertTrue(picks[2] == 6, "dragging picks as it goes: " .. tostring(picks[2]))
segBar:GetScript("OnMouseUp")(segBar, "LeftButton")
assertTrue(segBar:GetScript("OnUpdate") == nil, "let go, it stops following")
-- Fired as the client does, hooks and all: only ever asked about a value.
segBar:Fire("OnEnter")
assertTrue(asked[#asked] == 6 and GameTooltip.text == "Step 7", "the tooltip says what the value under the cursor is")
assertTrue(segBar.hoverLine.shown and segBar.hoverLine.points[1][4] == 240, "and a line follows it")
for _, value in ipairs(asked) do assertTrue(type(value) == "number", "the tooltip is only asked about values") end
_G.GetCursorPosition = function() return 150, 300 end
segBar:GetScript("OnUpdate")(segBar, 0.016)
assertTrue(GameTooltip.text == "Step 2" and segBar.hoverLine.points[1][4] == 50, "moving the cursor moves both")
segBar:Fire("OnLeave")
assertTrue(segBar:GetScript("OnUpdate") == nil and not segBar.hoverLine.shown, "and stops following once the cursor leaves")
_G.GetCursorPosition = function() return 300, 300 end
segBar:SetSegments({ { from = 0, to = 1, tone = "danger" } })
assertTrue(not segBar.kitParts.fills[2] or not segBar.kitParts.fills[2].shown, "SetSegments hides runs it no longer has")
assertTrue(not segBar.kitParts.outlines[1].shown, "SetSegments hides runs it no longer has")
assertTrue(same(segBar.kitParts.fills[1].color, t.danger), "and paints the new ones")
segBar:SetMarks({})
layout()
assertTrue(segBar:NaturalHeight() == 8 and not segBar.kitParts.pointers[1].shown, "no marks, no room for them")
segBar:Release()
made = #objects
local plain = ui:SegmentBar(UIParent, { max = 4, segments = { { from = 0, to = 1 } } })
assertTrue(plain == segBar and #objects == made, "a segment bar from the pool")
plain:Fire("OnEnter")
assertTrue(plain:GetScript("OnUpdate") == nil and not plain.kitInteractive, "without tooltipFor or onPick it does not follow the cursor")
plain:GetScript("OnMouseDown")(plain, "LeftButton")
assertTrue(#picks == 2, "nor pick")
plain:Release()

-- Strips and slots -------------------------------------------------------------------------

_G.GetItemIcon = function(id) return "Interface\\Icons\\item" .. id end
_G.GetItemInfo = function(id) return "Item", nil, id == 6948 and 1 or 3 end
_G.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [3] = { r = 0, g = 0.44, b = 0.87 } }
_G.GetItemCooldown = function() return 10, 30, 1 end
function Object:SetAttribute(key, value)
    self.attributes = self.attributes or {}
    self.attributes[key] = value
end

local place = {}
local strip = ui:StripPanel{ key = "bag", place = place, title = "Quest items", summary = "3 of 5", rail = "quest" }
local clicks = {}
local s1 = strip:Slot{ item = 6948, key = "SHIFT-1", count = 5, tooltip = "Hearth",
    onClick = function(slot, mouse) clicks[#clicks + 1] = mouse end }
local s2 = strip:Slot{ icon = "Interface\\Icons\\inv", quest = true }
local s3 = strip:Slot{ item = 2589, marker = 8, edge = "success" }
local sec = strip:Slot{ item = 6948, secure = { type = "item", item = "item:6948" } }
layout()
assertTrue(s1.kitType == "Slot" and sec.kitType == "SecureSlot" and sec:IsSecure() and not s1:IsSecure(), "secure slots are their own type")
assertTrue(sec.attributes and sec.attributes.type == "item" and sec.attributes.item == "item:6948", "its attributes are set")
assertTrue(strip.body.kitPW == 4 * 36 + 3 * 4 and s2.kitPX == 40, "the slots side by side: " .. tostring(strip.body.kitPW))
assertTrue(strip.kitPW >= strip.body.kitPW and strip.header.width == strip.kitPW, "the strip as long as its slots or its words")
assertTrue(strip.kitPH == 20 + 4 + 36, "a header over a row of slots")
assertTrue(strip.header.title.text == "Quest items" and strip.header.summary.text == "3 of 5", "title and summary")
local before = strip.kitPW
strip:SetTitle("A much longer title for the strip of slots")
layout()
assertTrue(strip.kitPW > before and strip.header.width == strip.kitPW, "a longer title makes it longer")
strip:SetSummary("")
strip:Fit()
assertTrue(UI.LayoutSettled(), "Fit lays it out now")

-- In combat a strip holding a secure slot is protected: it is left as it
-- is, and laid out when combat ends.
local layoutDriver
for _, o in ipairs(objects) do
    if o.scripts and o.scripts.OnEvent and o.scripts.OnUpdate then layoutDriver = o end
end
_G.InCombatLockdown = function() return true end
strip.IsProtected = function() return true end
sec.IsProtected = function() return true end
local calm = strip.kitPW
strip:SetTitle("A title long enough to need a longer strip than before, in combat")
layout()
assertTrue(strip.kitPW == calm and strip.width == calm, "in combat a protected strip keeps its size")
_G.InCombatLockdown = function() return false end
layoutDriver.scripts.OnEvent(layoutDriver, "PLAYER_REGEN_ENABLED")
layout()
assertTrue(strip.kitPW > calm and strip.header.width == strip.kitPW, "and fits its title when combat ends")
_G.InCombatLockdown, strip.IsProtected, sec.IsProtected = nil, nil, nil
strip:SetTitle("Quest items")
strip:Fit()

-- Every setter.
assertTrue(s1.icon.texture == "Interface\\Icons\\item6948" and s1.kitLinks.item == 6948, "an item's icon, and its tooltip link")
assertTrue(same(s1.ring[1].color, { 1, 1, 1, 1 }), "a ring in the item's quality colour")
assertTrue(s1.keyText.text == UI.ShortKey("SHIFT-1") and s1.countText.text == "5" and s1.countStrip.shown, "key and count")
assertTrue(s2.icon.texture == "Interface\\Icons\\inv" and s2.questMark.shown and same(s2.ring[1].color, t.border), "an icon, a quest mark, a plain ring")
assertTrue(s3.marker.shown and string.find(s3.marker.texture, "Icon_8", 1, true) and same(s3.ring[1].color, UI.Tone(t, "success")),
    "a marker, the edge's tone over the quality")
s2:SetItem(2589)
assertTrue(s2.icon.texture == "Interface\\Icons\\item2589" and same(s2.ring[1].color, { 0, 0.44, 0.87, 1 }), "SetItem")
s2:SetIcon("Interface\\Icons\\other")
assertTrue(s2.icon.texture == "Interface\\Icons\\other", "SetIcon")
s2:SetKey("BUTTON4")
assertTrue(s2.keyText.text == UI.ShortKey("BUTTON4"), "SetKey")
s2:SetKey(nil)
assertTrue(s2.keyText.text == "", "no key")
s2:SetCount(14)
assertTrue(s2.countText.text == "14" and s2.countStrip.shown, "SetCount")
s2:SetMarker(8)
assertTrue(s2.marker.shown and not s2.questMark.shown, "a raid marker takes the corner")
s2:SetMarker(nil)
s2:SetCount(1)
assertTrue(s2.questMark.shown and not s2.marker.shown and not s2.countStrip.shown, "and gives it back; one of a thing has no count")
s2:SetQuest(false)
assertTrue(not s2.questMark.shown, "SetQuest")
s2:SetMissing(true)
assertTrue(s2.alpha == 0.6 and same(s2.ring[1].color, t.danger), "missing: dimmed, a danger ring")
s2:SetMissing(false)
s2:SetEdge("warning")
assertTrue(s2.alpha == 1 and same(s2.ring[1].color, UI.Tone(t, "warning")), "SetEdge")
local cooled
s1.cooldown.SetCooldown = function(_, start, duration) cooled = { start, duration } end
s1:UpdateCooldown()
assertTrue(cooled and cooled[1] == 10 and cooled[2] == 30, "a cooldown from the item")
assertTrue(s1:SetSecure({ type = "macro" }) and s1.attributes.type == "macro", "SetSecure")
s1:Click("RightButton")
assertTrue(clicks[1] == "RightButton", "onClick hears which button")
s1:Fire("OnEnter")
assertTrue(GameTooltip.text == "Hearth", "a slot's tooltip")
s1:Fire("OnLeave")

-- Hover repaints nothing it need not: the slot text keeps its font.
local fonts = 0
local setFont = s1.keyText.SetFont
s1.keyText.SetFont = function(...) fonts = fonts + 1; return setFont(...) end
s1:SetMissing(true)
s1:SetEdge("danger")
s1:SetMissing(false)
assertTrue(fonts == 0, "ring changes set no font")
s1.keyText.SetFont = nil

-- The player drags the header: the place is saved by its top-left corner.
strip.header:Fire("OnMouseDown", "LeftButton")
strip.header:Fire("OnMouseUp", "LeftButton")
assertTrue(place.bag and place.bag.x == 100 and place.bag.y == 500, "the strip's place is saved")
local moved = ui:StripPanel{ key = "bag", place = place, title = "Again" }
assertTrue(moved.points[1][1] == "TOPLEFT" and moved.points[1][4] == 100 and moved.points[1][5] == 500, "and a strip opens there")
moved:Release()

-- Clear: plain slots back to their pool, the secure one never pooled.
strip:Clear()
layout()
assertTrue(s1.kitPooled and s2.kitPooled and s3.kitPooled and not s1:IsShown(), "cleared slots are pooled")
assertTrue(not sec.kitPooled and not sec:IsShown(), "a secure slot is hidden, never pooled")
for _, w in ipairs(ui.pools.Slot) do assertTrue(w ~= sec, "not in the slots' pool") end
assertTrue(ui.pools.SecureSlot == nil, "and there is no pool of secure slots")
assertTrue(strip.body.kitPW == 1 or #strip:GetChildren() == 0, "an empty strip")
made = #objects
local r1 = strip:Slot{ icon = "Interface\\Icons\\a", size = 24 }
local r2 = strip:Slot{ size = 24, onClick = function() clicks[#clicks + 1] = "new" end }
local r3 = strip:Slot{ size = 24 }
layout()
assertTrue(#objects == made, "a rebuild takes every slot from the pool: " .. (#objects - made) .. " new")
for _, r in ipairs({ r1, r2, r3 }) do
    assertTrue(r == s1 or r == s2 or r == s3, "from the pool")
    assertTrue(r.kitItem == nil and r.kitLinks == nil and not r.kitMissing and r.alpha == 1, "no item, not missing")
    assertTrue(not r.questMark.shown and not r.marker.shown and not r.countStrip.shown and r.keyText.text == "", "no marks, no count, no key")
    assertTrue(r.kitEdge == nil and same(r.ring[1].color, t.border) and r.kitPW == 24, "a plain ring, its new size")
    assertTrue(r.tooltip == nil, "no old tooltip")
end
assertTrue(r1.icon.texture == "Interface\\Icons\\a" and r2.icon.texture == nil, "only the icon it is given")
r3:Click()
assertTrue(#clicks == 1, "no old onClick")
r2:Click()
assertTrue(clicks[2] == "new", "its new onClick")
assertTrue(strip.body.kitPW == 3 * 24 + 2 * 4, "the strip fits its new slots: " .. tostring(strip.body.kitPW))
local sec2 = strip:Slot{ secure = { type = "spell", spell = "Hearthstone" } }
assertTrue(sec2 ~= sec and sec2.attributes.spell == "Hearthstone" and sec2.attributes.item == nil, "a new secure slot is made fresh")

-- A slot placed by the caller, as in UI/.
local slot = ui:Slot(UIParent, { quest = true, count = 14 })
assertTrue(slot.questMark.shown and slot.countStrip.shown, "a quest item shows its mark, a count its strip")
slot:SetMarker(8)
assertTrue(slot.marker.shown and not slot.questMark.shown and string.find(slot.marker.texture, "Icon_8", 1, true),
    "a raid marker takes the corner")
slot:SetMarker(nil)
slot:SetCount(1)
assertTrue(slot.questMark.shown and not slot.marker.shown and not slot.countStrip.shown, "and gives it back; one of a thing has no count")
-- A note in a tone has no strip; a model is the picture, under the marks.
slot:SetCount("talk", "accent")
assertTrue(slot.countText.text == "talk" and not slot.countStrip.shown, "a toned note has no strip")
assertTrue(slot.kitCountTone == "accent", "and is in its tone")
local model = CreateFrame("Frame")
slot:HoldModel(model)
assertTrue(model.parent == slot and slot.kitMarks and slot.countText.parent == slot.kitMarks, "a model on the slot, the marks over it")
assertTrue(model.level < slot.kitMarks.level, "the marks above the model")
slot:FadePicture(0.75)
assertTrue(slot.icon.alpha == 0.75 and model.alpha == 0.75 and slot.alpha == 1, "only the picture fades")
slot:Release()
local again = ui:Slot(UIParent, {})
assertTrue(again == slot and not model:IsShown() and slot.kitModel == nil and slot.icon.alpha == 1,
    "taken again: no model, the picture whole")
again:Release()
Object.SetAttribute = nil

-- The look picker ----------------------------------------------------------------------------

-- Its toggles, slider and select come from Fields and Menus; where those are
-- not loaded, stand-ins with the same contract (InitValue, Commit, a silent
-- SetValue) take their place for this part only.
local standIns = {}
local function standIn(name)
    if UI.types[name] then return end
    UI.Define(name, {
        stretch = false,
        Init = function(w, spec) w.kitValue = UI.InitValue(w, spec) end,
        methods = {
            SetValue = function(self, value) self.kitValue = value end,
            GetValue = function(self) return self.kitValue end,
            Measure = function() return 120, 20 end,
        },
    })
    standIns[#standIns + 1] = name
end
standIn("Toggle")
standIn("Slider")
standIn("Select")

local db = { look = { theme = "midnight" } }
local looks = {}
local appearance = body:Section{ "Appearance" }
local picker = appearance:LookPicker{ look = db.look, onChange = function(look) looks[#looks + 1] = look end }
layout()
assertTrue(#picker.cards == #UI.themeOrder and #picker.swatches == #UI.accents + 1, "a card for each theme, a swatch for each accent")
assertTrue(picker.desc:GetText() == UI.themes.midnight.desc, "the theme's words")
assertTrue(picker.opacity:GetValue() == 100 and picker.size:GetValue() == "normal" and picker.motion:GetValue() == false,
    "the controls show the look")
assertTrue(not picker.accents.reset:IsShown(), "no accent stored, no reset")

local function cardOf(key)
    for _, card in ipairs(picker.cards) do if card.kitKey == key then return card end end
end
local midnight, slate = cardOf("midnight"), cardOf("slate")
assertTrue(same(midnight.plate.edges.TOP.color, t.accent) and same(slate.plate.edges.TOP.color, t.border), "the chosen theme is ringed")

-- Hover and a pick repaint colours only.
fonts = 0
local counted = {}
for _, card in ipairs(picker.cards) do
    local original = card.name.SetFont
    counted[card] = original
    card.name.SetFont = function(...) fonts = fonts + 1; return original(...) end
end
slate:GetScript("OnEnter")(slate)
assertTrue(same(slate.plate.edges.TOP.color, t.accent65), "a hovered card's ring")
slate:GetScript("OnLeave")(slate)
slate:Click()
assertTrue(fonts == 0, "hover and a pick set no font")
for card in pairs(counted) do card.name.SetFont = nil end
layout()
assertTrue(#looks == 1 and looks[1].theme == "slate", "a pick reports the new look")
assertTrue(looks[1] ~= db.look and db.look.theme == "midnight", "a new table: the addon keeps it, the picker does not write")
assertTrue(same(slate.plate.edges.TOP.color, t.accent) and same(midnight.plate.edges.TOP.color, t.border), "the ring moves")
assertTrue(picker.desc:GetText() == UI.themes.slate.desc, "the words follow")

-- Accents.
local hex = UI.accents[2].hex
picker.swatches[3]:Click()
assertTrue(looks[#looks].accent == hex and looks[#looks].theme == "slate", "a swatch picks its accent")
assertTrue(picker.accents.reset:IsShown(), "an accent stored shows the reset")
assertTrue(same(picker.swatches[3].ring.edges.TOP.color, t.text), "the chosen swatch is ringed")
picker.accents.reset:Click()
assertTrue(looks[#looks].accent == nil and not picker.accents.reset:IsShown(), "the reset forgets the accent")
UI.Commit(picker.classToggle, true)
assertTrue(looks[#looks].accent == "class" and picker.classToggle:GetValue() == true, "the class colour")
picker.swatches[1]:Click()
assertTrue(looks[#looks].accent == nil and picker.classToggle:GetValue() == false, "the theme's own turns the class colour off")

-- Opacity, text size, less motion.
UI.Commit(picker.opacity, 60)
assertTrue(looks[#looks].opacity == 0.6, "opacity")
UI.Commit(picker.size, "large")
assertTrue(looks[#looks].textSize == "large", "text size")
UI.Commit(picker.motion, true)
local last = looks[#looks]
assertTrue(last.reduceMotion == true and last.opacity == 0.6 and last.textSize == "large" and last.theme == "slate",
    "less motion, and the look keeps every other choice")

-- The addon keeps it and sets it: every picker of the UI shows it.
local other = appearance:LookPicker{ look = db.look, onChange = function(look) db.look = look; ui:SetLook(look) end }
layout()
assertTrue(other.kitLook.theme == "midnight", "a second picker starts from its look")
ui:SetLook(last)
assertTrue(other.kitLook.theme == "slate" and other.opacity:GetValue() == 60 and other.motion:GetValue() == true,
    "a look set elsewhere shows in the picker")
cardOf = function(key) for _, card in ipairs(other.cards) do if card.kitKey == key then return card end end end
cardOf("obsidian"):Click()
assertTrue(db.look.theme == "obsidian" and ui.look.theme == "obsidian", "the addon stores and sets it")
assertTrue(picker.kitLook.theme == "obsidian", "and the other picker follows")
ui:SetLook({})

-- Every theme, including the art ones, and the look's other settings.
for _, key in ipairs(UI.themeOrder) do
    ui:SetLook({ theme = key, accent = "#6f9dff", opacity = 0.6, textSize = "large", reduceMotion = true })
    tick()
end
ui:SetLook({ theme = "horde", accent = "class" })
tick()
ui:SetLook({})
layout()

-- From the pool, with another look.
appearance:Clear()
layout()
assertTrue(picker.kitPooled and other.kitPooled, "pickers go back to the pool")
made = #objects
local fresh = appearance:LookPicker{ look = { theme = "alliance", accent = "class", textSize = "small" } }
layout()
assertTrue(#objects == made, "a picker from the pool makes no new frames: " .. (#objects - made) .. " new")
assertTrue(fresh.kitLook.theme == "alliance" and fresh.classToggle:GetValue() == true and fresh.size:GetValue() == "small",
    "it shows the new look")
assertTrue(#fresh.cards == #UI.themeOrder and fresh.kitOnChange == nil, "its own cards, no old onChange")
for _, card in ipairs(fresh.cards) do
    assertTrue(card.kitPicker == fresh and not card.hover, "each card knows its picker, no old hover")
end
fresh.swatches[2]:Click()
assertTrue(fresh.kitLook.accent == UI.accents[1].hex, "a picker with no onChange still shows the change")
appearance:Clear()

for _, name in ipairs(standIns) do
    UI.types[name], UI.Proto[name], UI.Makers[name] = nil, nil, nil
end
Object.SetColorTexture, Object.SetTextColor = nil, nil
