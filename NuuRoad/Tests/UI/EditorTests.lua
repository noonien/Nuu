-- The guide editor, its Places tab and the place recorder, on the kit's
-- stand-in for the client (Tests/UI/Harness.lua): a packaged guide opened as
-- a copy, steps picked from the list, fields typed and read back into the
-- step, steps added, moved and removed, choices, validation, saving, the
-- Places tab's point editing, and a walk with the recorder. Nothing may reach
-- the error handler, and the kit's audit must find every change marked.
local ctx = dofile("Tests/UI/Harness.lua")
local ns, check, settle = ctx.ns, ctx.check, ctx.settle

local Editor = ns.modules.Editor
local Places = ns.modules.PlacesPanel
local Recorder = ns.modules.PlaceRecorder
local Repository = ns.modules.GuideRepository
check(Editor and Places and Recorder, "the editor, its places tab and the recorder are registered")

-- Where the player stands, for Add point here and the recorder: the map
-- calls the stand-in lacks, put back at the end.
local saved = {}
for _, name in ipairs({ "C_Map", "CreateVector2D", "IsIndoors", "IsShiftKeyDown" }) do saved[name] = rawget(_G, name) end
local spot = { map = 1413, x = 0.5, y = 0.5, indoors = false, shift = false }
_G.C_Map = setmetatable({
    GetBestMapForUnit = function() return spot.map end,
    GetPlayerMapPosition = function() return { x = spot.x, y = spot.y } end,
    GetWorldPosFromMapPos = function(_, vector) return 1, { x = vector.x * 3000, y = vector.y * 2000 } end,
}, { __index = saved.C_Map })
_G.CreateVector2D = function(x, y) return { x = x, y = y } end
_G.IsIndoors = function() return spot.indoors end
_G.IsShiftKeyDown = function() return spot.shift end

-- A field typed into by the player: focus, text, and the commit on leaving.
local function typeInto(field, text)
    field.box:SetFocus()
    field.box:SetText(text)
    field.box:ClearFocus()
end

-- The list row showing `index`, clicked.
local function clickRow(list, index)
    settle()
    for _, row in ipairs(list.rows) do
        if row:IsShown() and row.item and row.item.index == index then
            row:Click()
            return true
        end
    end
    return false
end

-- Opening a packaged guide: a personal copy, on its first step.
local source = Repository:Get("nuuroad:leveling:horde-barrens-13-21")
check(source, "the Barrens guide is packaged")
Editor:OpenGuide(source)
settle()
ctx.noErrors("open")
check(Editor:IsShown() and Editor.frame == Editor.win, "the window shows")
check(Editor.isClone and Editor.working ~= source, "a packaged guide opens as a copy")
check(Editor.working.meta.title == "Copy of " .. source.meta.title, "the copy is named")
check(#Editor.stepList:GetItems() == #Editor.working.nodes, "every step is listed")
check(Editor.stepCount:GetText() == #Editor.working.nodes .. " steps", "the count beside the list")
check(Editor.guideTitle:GetText() == Editor.working.meta.title, "the title field")
check(Editor.win.statusStrip.text:GetText():find("personal copy"), "the status says it is a copy")

-- Picking steps from the list.
check(clickRow(Editor.stepList, 3), "row 3 is on screen")
check(Editor.stepIndex == 3, "a click selects the step")
check(Editor.stepList:GetSelected() == Editor.stepList:GetItems()[3], "the row shows selected")
local node = Editor:CurrentNode()
check(Editor.stepTitle:GetText() == ns.modules.Steps:Title(node, true), "the title is drawn from the step")

-- Fields typed on the Step tab are read back into the step when another is picked.
Editor:SelectStep(2)
settle()
local kinds = Editor.kindChoices.buttons
local function kindButton(kind)
    for _, button in ipairs(kinds) do if button.kitChoiceValue == kind then return button end end
end
kindButton("action"):Click()
check(Editor:CurrentNode().kind == "action", "a type button sets the kind")
typeInto(Editor.stepTitle, "Talk to the guard")
typeInto(Editor.stepBody, "He stands by the gate.")
typeInto(Editor.carriedWith, "")
typeInto(Editor.waitSeconds, "8")
Editor.sticky:Click()
Editor:SelectStep(3)
node = Editor.working.nodes[2]
check(node.title == "Talk to the guard" and node.body == "He stands by the gate.", "title and details are kept")
check(node.wait == 8 and node.sticky == true, "wait and sticky are kept")
Editor:SelectStep(2)
settle()
check(Editor.sticky:GetValue() == true and Editor.waitSeconds:GetText() == "8", "drawn back from the step")

-- A kill step: its NPCs and count make the observed completion.
kindButton("kill"):Click()
settle()
check(Editor.killCount:IsShown(), "the kill count shows for a kill step")
check(not Editor.goalRow:IsShown(), "no goal fields on a kill step")
typeInto(Editor.npcIDs, "3244, 3245")
typeInto(Editor.killCount, "6")
Editor:SelectStep(3)
node = Editor.working.nodes[2]
check(node.auto and node.auto.verb == "kill" and node.auto.count == 6, "the kill rule")
check(node.completion.observed.type == "kills" and #node.completion.observed.npcs == 2, "the kills are observed")

-- A goal step: the fields are relabelled per type, and the rank escape.
Editor:SelectStep(2)
kindButton("gather"):Click()
settle()
check(Editor.goalRow:IsShown() and Editor.goalUpto:IsShown(), "gather has the four goal fields")
check(Editor.goalValue.label:GetText() == "Item ID", "the value field is relabelled")
check(not Editor.killCount:IsShown(), "no kill count on a gather step")
typeInto(Editor.npcIDs, "")
typeInto(Editor.goalValue, "2770")
typeInto(Editor.goalAmount, "20")
typeInto(Editor.goalExtra, "Mining")
typeInto(Editor.goalUpto, "50")
Editor:SelectStep(3)
node = Editor.working.nodes[2]
check(node.auto.verb == "gather" and node.auto.item == 2770 and node.auto.count == 20, "the gather rule")
check(node.auto.upto and node.auto.upto.skill == "Mining" and node.auto.upto.rank == 50, "the rank escape")
check(node.completion.type == "observed", "the step completes on its own")
-- Both halves of the escape survive the write-back (OpenRoad kept only the
-- skill; Steps:ApplyCarried).
local either = node.completion.observed
check(either and either.type == "any" and #either.children == 2 and either.children[1].type == "item"
    and either.children[2].type == "skill", "the gather completes on the items or the skill")
Editor:SelectStep(2)
kindButton("equip"):Click()
settle()
check(Editor.goalValue:IsShown() and not Editor.goalAmount:IsShown(), "equip asks for one thing")
ctx.noErrors("step tab")

-- The tabs in the band.
local function clickTab(key)
    for _, tab in ipairs(Editor.tabs.kitTabFrames) do
        if tab.kitKey == key and tab:IsShown() then tab:Click(); return end
    end
    error("no tab " .. key)
end
clickTab("navigation")
settle()
check(Editor.activeTab == "navigation" and Editor.pages.navigation:IsShown() and not Editor.pages.basic:IsShown(),
    "the Destination tab shows its page alone")
typeInto(Editor.mapID, "1413")
typeInto(Editor.locationX, "52.26")
typeInto(Editor.locationY, "31.93")
clickTab("condition")
typeInto(Editor.conditionText, "Warrior or Shaman")
clickTab("materials")
typeInto(Editor.materials, "2840 x10 gather\n3466 x2 ah")
Editor.materialsBySection:Click()
check(Editor.working.meta.materials == "section", "the materials list by section")
Editor:SelectStep(3)
node = Editor.working.nodes[2]
check(node.location and node.location.mapID == 1413 and math.abs(node.location.x - 0.5226) < 1e-9, "the destination")
check(node.condition ~= nil, "the condition")
check(node.needs and #node.needs == 2 and node.needs[2].source == "ah", "the materials")
Editor:SelectStep(2)
settle()
check(Editor.locationX:GetText() == "52.26" and Editor.materials:GetText():find("3466 x2 ah", 1, true),
    "drawn back as percentages and lines")
-- A line that cannot be read is refused, and the step keeps what it had.
typeInto(Editor.materials, "not a material")
Editor:SelectStep(3)
check(#Editor.working.nodes[2].needs == 2, "a bad line keeps the materials")
check(Editor.win.statusStrip.text:GetText():find("Could not read the material line", 1, true), "and says why")
ctx.noErrors("tabs")

-- Choices.
clickTab("choices")
Editor:SelectStep(4)
local before = #Editor.working.nodes
Editor.choicePager.addButton:Click()
node = Editor:CurrentNode()
check(node.kind == "choice" and #node.choices == 1 and node.choices[1]["next"] == 5, "a choice to the next step")
check(Editor.choicePager:GetCount() == 1, "the pager counts it")
typeInto(Editor.choiceTitle, "Go to Ratchet first")
typeInto(Editor.choiceTarget, "6")
Editor:SelectStep(5)
check(Editor.working.nodes[4].choices[1].title == "Go to Ratchet first" and Editor.working.nodes[4].choices[1]["next"] == 6,
    "the choice is kept")
Editor:SelectStep(4)
Editor:RemoveChoice()
check(Editor:CurrentNode().choices == nil, "the choice removed")
check(#Editor.working.nodes == before, "no step came or went")

-- Adding, moving and removing steps.
clickTab("basic")
Editor:SelectStep(3)
Editor:AddStep()
settle()
check(#Editor.working.nodes == before + 1 and Editor.stepIndex == 4, "a step after the selected one")
check(#Editor.stepList:GetItems() == before + 1, "the list grows")
local added = Editor:CurrentNode()
Editor:MoveStep(-1)
check(Editor.stepIndex == 3 and Editor.working.nodes[3] == added, "moved up")
Editor:DeleteStep()
settle()
check(#Editor.working.nodes == before and #Editor.stepList:GetItems() == before, "removed again")
ctx.noErrors("steps")

-- Validation and saving.
typeInto(Editor.guideTitle, "")
check(Editor:Save() == false, "an empty title is refused")
check(Editor.win.statusStrip.text:GetText():find("Guide title", 1, true), "and the status says so")
typeInto(Editor.guideTitle, "My Barrens")
typeInto(Editor.guideCategory, "Leveling/Mine")
check(Editor:Save() == true, "saved")
local id = Editor.working.id
check(ns.db.account.guides[id] and ns.db.account.guides[id].meta.title == "My Barrens", "kept on the account")
check(ns.db.account.guides[id].meta.category == "Leveling/Mine", "in its folder")
check(not Editor.isClone and Editor.win.statusStrip.text:GetText() == "Saved.", "no longer a copy")
check(Editor:SaveAndPreview() == true and not Editor:IsShown(), "save and preview closes the editor")
ctx.noErrors("save")

-- A new guide, then the saved one opened again: not a copy this time.
Editor:OpenNew()
settle()
check(#Editor.working.nodes == 1 and Editor.working.meta.title == "Untitled guide", "a new guide")
Editor:OpenGuide(ns.db.account.guides[id])
settle()
check(not Editor.isClone and Editor.working.meta.title == "My Barrens", "a personal guide opens as itself")
Editor:Hide()
Editor:Toggle()
check(Editor:IsShown() and Editor.working.meta.title == "My Barrens", "toggle shows what it had")
ctx.noErrors("reopen")

-- The Places tab, on the cave fixture.
Editor:OpenGuide(Repository:Get("nuuroad:fixture:cave-place"))
settle()
clickTab("places")
settle()
check(Editor.pages.places:IsShown(), "the places page shows")
local place = Places:Place()
check(place and Places.pager:GetCount() == #Editor.working.places, "the pager counts the places")
check(#Places.list:GetItems() == #place.points and #place.points >= 2, "every point is listed")
check(Places.placeID:GetText() == place.place, "the place's ID")
check(clickRow(Places.list, 1), "point 1 on screen")
check(Places.selected == 1 and Places.second == nil, "a click selects a point")
spot.shift = true
check(clickRow(Places.list, 2), "point 2 on screen")
spot.shift = false
check(Places.selected == 1 and Places.second == 2, "a shift-click picks a second")
Places:Disconnect()
Places:Connect(true)
local _, into = ns.modules.PlaceEditing.Neighbours(place, 2)
check(#into == 1 and into[1] == 1, "a one-way connection from the first to the second")
local kindBefore = place.points[1].kind
Places.kindButton:Click()
check(place.points[1].kind ~= kindBefore, "the kind button cycles the point's kind")
typeInto(Places.pointLabel, "the gallery")
typeInto(Places.pointID, "gallery")
check(place.points[1].label == "the gallery" and place.points[1].id == "gallery", "label and ID kept")
typeInto(Places.pointID, "not.one")
check(place.points[1].id == "gallery", "a dotted ID is refused")
typeInto(Places.placeName, "Test cave")
check(place.name == "Test cave", "the place's name")
local points = #place.points
spot.x, spot.y = 0.51, 0.52
Places:AddPointHere()
settle()
check(#place.points == points + 1 and Places.selected == points + 1, "a point where the player stands")
Places:DeletePoint()
check(#place.points == points, "and removed")
local count = #Editor.working.places
Places.pager.addButton:Click()
check(#Editor.working.places == count + 1 and Places.placeIndex == count + 1, "a new place")
Places:DeletePlace()
check(#Editor.working.places == count, "and removed")
check(Places.problems:GetText() ~= "", "the footer says something")
-- The step form sees the guide's points.
clickTab("navigation")
check(Editor.placeNote:GetText():find("gallery", 1, true), "the destination tab lists the points")
typeInto(Editor.placePoint, place.place .. ".gallery")
local standing = Editor.stepIndex
Editor:SelectStep(standing == 1 and 2 or 1)
local location = Editor.working.nodes[standing].location
check(location and location.point == place.place .. ".gallery" and math.abs(location.x - place.points[1].at[1] / 100) < 1e-9,
    "a step stands on a place point, with its coordinates")
ctx.noErrors("places tab")

-- The recorder, from the Places tab: the editor goes away, the walk extends the place.
clickTab("places")
Places.selected = nil
Places:OpenRecorder()
settle()
check(Recorder.win:IsShown() and not Editor:IsShown(), "the recorder opens and the editor goes away")
check(Recorder:ShownPlace() == place and not Recorder.owned, "it walks the editor's place")
check(Recorder.toEditor:GetText() == "Editor", "its button goes back to the editor")
Recorder.record:Click()
check(Recorder.recording and Recorder.record:GetText() == "Stop", "recording")
spot.indoors = true
for step = 1, 6 do
    spot.x = 0.5 + step * 0.005
    Recorder:Sample()
end
typeInto(Recorder.markText, "the bank")
Recorder:Mark()
check(#Recorder.trail.marks == 1 and Recorder.markText:GetText() == "", "a mark")
check(#Recorder.trail.samples >= 6, "samples every few yards")
check(Recorder.status:GetText():find("Recording", 1, true), "the status counts the walk")
Recorder.record:Click()
check(not Recorder.recording and Recorder.record:GetText() == "Record", "stopped")
Recorder.indoorsToggle:Click()
check(ns.modules.Config:Get("placeRecorder.outdoors") == true and Recorder.indoorsToggle:GetValue() == false,
    "the indoors switch is the setting")
Recorder.indoorsToggle:Click()
check(ns.modules.Config:Get("placeRecorder.outdoors") == false, "and back")
Recorder:ShowLua()
check(Recorder.source and Recorder.source:IsShown() and Recorder.sourceText:GetText() ~= "", "the place as source")
Recorder.source:Hide()
Recorder.toEditor:Click()
check(Editor:IsShown() and Editor.activeTab == "places", "back to the editor's places tab")

-- A place of the recorder's own, sent to the editor's guide.
Recorder:Start(nil)
check(Recorder.owned and Recorder.toEditor:GetText() == "To editor", "a place of its own")
Recorder:ToggleRecording()
spot.indoors = false
spot.x = 0.4
Recorder:Sample()
spot.indoors = true
for step = 1, 5 do
    spot.x = 0.4 - step * 0.005
    Recorder:Sample()
end
Recorder:ToggleRecording()
local placesBefore = #Editor.working.places
check(#Recorder.place.points > 0, "the walk makes a place")
Recorder:SendToEditor()
check(#Editor.working.places == placesBefore + 1 and not Recorder.owned, "the place joins the guide")
check(Places.placeIndex == placesBefore + 1 and Editor.win.statusStrip.text:GetText():find("Save to keep it", 1, true),
    "shown on the places tab")
Recorder:Toggle()
check(not Recorder.win:IsShown(), "toggled away")
Recorder:Toggle()
check(Recorder.win:IsShown(), "and back")
Recorder:Close()
Editor:Hide()
settle()
ctx.noErrors("recorder")

for _, name in ipairs({ "C_Map", "CreateVector2D", "IsIndoors", "IsShiftKeyDown" }) do _G[name] = saved[name] end
spot = nil
ctx.noErrors("end")
return true
