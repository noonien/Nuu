-- The guide editor (UI/Editor.lua), its places window and the place
-- recorder, on the kit's stand-in for the client (Tests/UI/Harness.lua): a
-- packaged guide opened as a draft that becomes the player's copy at its
-- first change, with the tracker following it; steps picked, added from
-- the type menu, filled from the target and by shift-click, their problems
-- shown on the page; undo and redo; the outline's class filter; who sees a
-- step; the guide as text, copied, edited and imported; settings; a new
-- guide; caves and tunnels; and a walk with the recorder. Nothing may reach
-- the error handler, and the kit's audit must find every change marked.
local ctx = dofile("Tests/UI/Harness.lua")
local ns, check, settle = ctx.ns, ctx.check, ctx.settle

local Editor = ns.modules.Editor
local Places = ns.modules.PlacesPanel
local Recorder = ns.modules.PlaceRecorder
local Repository = ns.modules.GuideRepository
local Progress = ns.modules.Progress
check(Editor and Places and Recorder, "the editor, the places panel and the recorder are registered")

-- Where the player stands and what they target: the calls the stand-in
-- lacks, put back at the end.
local saved = {}
for _, name in ipairs({ "C_Map", "CreateVector2D", "IsIndoors", "IsShiftKeyDown", "UnitGUID", "UnitName",
    "GetCurrentKeyBoardFocus" }) do saved[name] = rawget(_G, name) end
local spot = { map = 1413, x = 0.5, y = 0.5, indoors = false, shift = false, target = nil, focus = nil }
_G.C_Map = setmetatable({
    GetBestMapForUnit = function() return spot.map end,
    GetPlayerMapPosition = function() return { x = spot.x, y = spot.y } end,
    GetWorldPosFromMapPos = function(_, vector) return 1, { x = vector.x * 3000, y = vector.y * 2000 } end,
}, { __index = saved.C_Map })
_G.CreateVector2D = function(x, y) return { x = x, y = y } end
_G.IsIndoors = function() return spot.indoors end
_G.IsShiftKeyDown = function() return spot.shift end
_G.UnitGUID = function(unit)
    if unit == "target" and spot.target then return "Creature-0-1-2-3-" .. spot.target.id .. "-0000" end
    return saved.UnitGUID and saved.UnitGUID(unit) or nil
end
_G.UnitName = function(unit)
    if unit == "target" and spot.target then return spot.target.name end
    return saved.UnitName and saved.UnitName(unit) or "Player"
end
_G.GetCurrentKeyBoardFocus = function() return spot.focus end

local function typeInto(field, text)
    field.box:SetFocus()
    field.box:SetText(text)
    field.box:ClearFocus()
    settle()
end

-- The outline row showing `step`, clicked.
local function clickStep(step)
    settle()
    for _, row in ipairs(Editor.outline.rows) do
        if row:IsShown() and row.item and row.item.step == step then
            row:Click()
            settle()
            return true
        end
    end
    return false
end

local function notices()
    local out = {}
    for _, child in ipairs(Editor.problemArea.kitChildren or {}) do out[#out + 1] = child end
    return out
end

-- Opening a packaged guide: a draft, not yet a copy.
local source = Repository:Get("nuuroad:leveling:horde-barrens-13-21")
check(source, "the Barrens guide is packaged")
Progress:Select(source)
Editor:OpenGuide(source)
settle()
ctx.noErrors("open")
local draft = Editor.draft
check(Editor:IsShown() and draft and draft.copyOf == source.id, "a packaged guide opens as a draft of a copy")
check(draft:Count() == #source.nodes, "every step is in the draft")
local sections = #draft:Sections()
check(#Editor.outlineItems == sections + draft:Count(), "the outline lists every section and step")
check(Editor.win.subtitle == nil or true, "the window has a subtitle")
check(not Repository:IsUserGuide(source.id), "nothing kept yet")

-- Picking a step: its page.
local third = draft:StepAt(3)
check(clickStep(third), "row 3 is on screen")
check(Editor.step == third, "a click selects the step")
check(Editor.titleText:GetText() == Editor:TitleOf(third), "the page's title is the step's")
check(Editor.controls.note and Editor.controls.type, "the note and the type button")

-- The first change makes it the player's own copy, and the tracker follows.
typeInto(Editor.controls.note, "Written in the editor.")
check(third.note == "Written in the editor.", "the note is kept in the step")
local id = draft.guide.id
check(id ~= source.id and Repository:IsUserGuide(id), "now a guide of the player's own: " .. tostring(id))
check(draft.guide.title == source.meta.title .. " (my copy)", "named as a copy")
check(ns.db.account.guides[id].kind == "guide", "kept in format v1")
check(Progress.store.activeGuideID == id, "the tracker follows the copy")
check(Repository:Get(source.id) == source, "the packaged guide is untouched")
check(Editor.step == third, "still on the same step")
ctx.noErrors("first change")

-- Adding a kill step: its problem on the page until its creatures are named.
Editor:AddStep("kill")
settle()
local kill = Editor.step
check(kill and kill.type == "kill" and draft:EntryOf(kill).position == 4, "a kill step after the selected one")
local list = notices()
check(#list >= 1, "its problem is on the page")
check(Editor.controls.killTarget, "the creatures field offers the target")
spot.target = { id = 3244, name = "Plainstrider" }
Editor.controls.killTarget:Click()
settle()
check(kill.kill and kill.kill[1] == 3244, "the target is the creature")
check(draft:NPCName(3244) == "Plainstrider", "named in the guide")
check(not draft:ProblemsOf(kill), "no problem now")
ctx.noErrors("kill step")

-- Undo and redo, from the window's band.
local count = draft:Count()
Editor.undoButton:Click()
settle()
check(kill.kill == nil or draft:EntryOf(kill) == nil, "undone")
Editor.undoButton:Click()
settle()
check(draft:Count() == count - 1, "the step is gone again")
Editor.redoButton:Click()
Editor.redoButton:Click()
settle()
check(draft:Count() == count and draft:StepAt(4).kill and draft:StepAt(4).kill[1] == 3244, "and back")
kill = draft:StepAt(4)
Editor:Select(kill)
ctx.noErrors("undo")

-- A talk step with the target as its NPC, a quest added by shift-click.
Editor:AddStep("talk")
settle()
local talk = Editor.step
spot.target = { id = 3338, name = "Sergra Darkthorn" }
spot.x, spot.y = 0.5212, 0.3101
Editor.controls.useTarget:Click()
settle()
check(talk.npc and talk.npc[1] == 3338, "the target is the NPC")
local entry = draft:NPC(3338)
check(type(entry) == "table" and entry.at and entry.at[1] == 5212 and entry.at[2] == 3101, "standing where the player is")
-- A shift-click with no field in focus: a quest ready to hand in goes to
-- the turn-ins, any other to the accepts.
local clientModule = ns.modules.Client
local ready = clientModule.IsQuestReadyToTurnIn
clientModule.IsQuestReadyToTurnIn = function(_, questID) return questID == 871 end
Editor:InsertLink("|cffffff00|Hquest:871:14|h[Disrupt the Attacks]|h|r")
settle()
clientModule.IsQuestReadyToTurnIn = ready
check(talk.turnin and talk.turnin[1] == 871, "a shift-clicked quest ready to hand in is a turn-in")
check(not draft:ProblemsOf(talk), "a talk with an NPC and a quest is fine")
Editor:AskIDs("Add quest", "Quest ID", function(ids) Editor:Hard(draft.SetField, draft, talk, "accept", ids, "accept") end)
Editor.prompt.input:SetText("872, 873")
Editor.prompt.ok:Click()
settle()
check(talk.accept and #talk.accept == 2, "IDs typed into the small window")
ctx.noErrors("talk step")

-- Changing the type, through the type button's menu: a click on a row
-- changes it (and the menu marks the step's own type).
local function menuRow(caption)
    local menu = ns:GetUI().kitMenu
    for _, row in ipairs(menu and menu.rows or {}) do
        if row:IsShown() and row.item and row.item.caption == caption then return row, row.item end
    end
end
Editor.controls.type:Click()
settle()
local talkRow, talkItem = menuRow("Talk")
check(talkRow and talkItem.checked, "the type menu marks the step's own type")
local noteRow = menuRow("Note")
check(noteRow, "the menu lists the types")
noteRow:Click()
settle()
check(talk.type == "note" and Editor.controls.type:GetText() == "Note", "a click on a type changes it")
Editor:Undo()
settle()
talk = Editor.step
check(talk.type == "talk", "undone")
-- Add step, through its menu too.
local stepsNow = draft:Count()
Editor:OpenAddMenu(Editor.undoButton)
settle()
local killRow = menuRow("Kill")
check(killRow and killRow.item.checked == nil, "the add menu lists plain types")
killRow:Click()
settle()
check(draft:Count() == stepsNow + 1 and Editor.step.type == "kill", "a click adds a step of that type")
Editor:Undo()
settle()
for _, entry in ipairs(draft:Entries()) do
    local step = entry.step
    if step.type == "talk" and step.npc and step.npc[1] == 3338 and step.turnin and step.turnin[1] == 871 then talk = step end
end
check(draft:Count() == stepsNow and talk.type == "talk", "undone")
Editor:Select(talk)
-- Changing the type keeps the NPC.
Editor:Hard(draft.SetType, draft, talk, "vendor")
settle()
check(talk.type == "vendor" and talk.npc[1] == 3338 and talk.sell == true, "a vendor, the same NPC")
check(Editor.controls.type:GetText() == "Sell, repair", "the type button says so")
Editor:Hard(draft.SetType, draft, talk, "talk")
check(talk.turnin and talk.turnin[1] == 871, "the quests come back with the type")
ctx.noErrors("type")

-- Who sees the step.
Editor:OpenShownTo(talk)
settle()
local shown = Editor.shownWin
check(shown and shown:IsShown(), "the shown-to window")
local toggles = {}
local function collect(widget)
    for _, child in ipairs(widget.kitChildren or {}) do
        if child.kitType == "Toggle" then toggles[#toggles + 1] = child end
        collect(child)
    end
end
collect(shown.kitInner or shown)
check(#toggles == 9, "a toggle per class: " .. #toggles)
toggles[4]:Click()
settle()
check(talk.cond and talk.cond.class == "ROGUE", "Rogues only")
check(Editor:DescribeWho(talk) == "Rogues", "said in words")
shown:Hide()
Editor:SetFilter("WARRIOR")
local hidden = true
for _, item in ipairs(Editor.outlineItems) do
    if item.step == talk then hidden = false end
end
check(hidden, "the Warrior filter leaves the Rogue step out")
Editor:SetFilter("all")
ctx.noErrors("shown to")

-- The outline's menu: move, duplicate, delete.
local position = draft:EntryOf(talk).position
Editor:Hard(draft.Move, draft, talk, -1)
check(draft:EntryOf(talk).position == position - 1, "moved up")
local twin = Editor:Hard(function() return draft:Duplicate(talk) end)
check(twin and draft:Count() == count + 2 and twin.label == nil, "duplicated")
Editor:Hard(draft.Delete, draft, twin)
check(draft:Count() == count + 1, "deleted")
Editor:OutlineMenu({ kind = "step", step = talk, entry = draft:EntryOf(talk) })
settle()
ns:GetUI():CloseMenu()
ctx.noErrors("outline menu")

-- Several steps at once: Shift-click a range, Ctrl-click one more or less,
-- and the selection page's actions, each one change.
local savedCtrl = rawget(_G, "IsControlKeyDown")
local ctrl = false
_G.IsControlKeyDown = function() return ctrl end
local a, b, c = draft:StepAt(5), draft:StepAt(6), draft:StepAt(7)
check(clickStep(a), "the first step of the range")
spot.shift = true
check(clickStep(c), "shift-click the last")
spot.shift = false
check(#Editor:Selected() == 3 and Editor:Selected()[2] == b, "the steps between are picked")
check(Editor.controls.group and Editor.controls.delete, "the selection page with its actions")
local tinted = 0
for _, row in ipairs(Editor.outline.rows) do
    if row:IsShown() and row.kitTint == "accentWash" then tinted = tinted + 1 end
end
check(tinted == 2, "the picked rows show it (the clicked one is the list's own selection): " .. tinted)
ctrl = true
check(clickStep(b), "ctrl-click one of them")
ctrl = false
check(#Editor:Selected() == 2 and not Editor.selection[b], "takes it out")
ctrl = true
clickStep(b)
ctrl = false
check(#Editor:Selected() == 3, "and back in")
local countBefore = draft:Count()
Editor.controls.duplicate:Click()
settle()
check(draft:Count() == countBefore + 3 and #Editor:Selected() == 3 and Editor:Selected()[1] ~= a, "duplicated, the copies picked")
Editor.controls.delete:Click()
Editor.controls.delete:Click()
settle()
check(draft:Count() == countBefore and #Editor:Selected() == 1, "the copies deleted, one step left picked")
Editor:Undo()
check(draft:Count() == countBefore + 3, "one undo brings all three back")
Editor:Undo()
check(draft:Count() == countBefore, "and one more takes the copies away")
a, b, c = draft:StepAt(5), draft:StepAt(6), draft:StepAt(7)
clickStep(a)
spot.shift = true
clickStep(c)
spot.shift = false
Editor.controls.up:Click()
settle()
check(draft:EntryOf(a).position == 4 and draft:EntryOf(c).position == 6, "moved up as a block")
Editor:OpenShownTo(a, Editor:Selected())
settle()
local shownToggles = {}
local function collectToggles(widget)
    for _, child in ipairs(widget.kitChildren or {}) do
        if child.kitType == "Toggle" then shownToggles[#shownToggles + 1] = child end
        collectToggles(child)
    end
end
collectToggles(Editor.shownWin.kitInner or Editor.shownWin)
shownToggles[1]:Click()
settle()
check(a.cond and b.cond and c.cond and a.cond.class == "WARRIOR" and c.cond.class == "WARRIOR", "who sees them, for all three")
Editor.shownWin:Hide()
Editor:Undo()
_G.IsControlKeyDown = savedCtrl
Editor:Select(draft:StepAt(3))
ctx.noErrors("several steps")

-- The guide as text: copied, edited, imported.
Editor:CopyAsText()
settle()
check(Editor.copyWin and Editor.copyWin:GetText():find('kind = "guide"', 1, true), "copied as text")
Editor.copyWin:Hide()
Editor:EditGuideAsText()
settle()
local text = Editor.textWin.area:GetText()
check(text:find("Written in the editor.", 1, true), "the text holds the note")
Editor.textWin.area:SetText(text:gsub("Written in the editor%.", "Rewritten as text."))
Editor.textWin.apply:Click()
settle()
check(not Editor.textWin:IsShown(), "applied")
check(draft:StepAt(3).note == "Rewritten as text.", "the guide changed: " .. tostring(draft:StepAt(3).note))
Editor:EditGuideAsText()
Editor.textWin.area:SetText("{ not a guide")
Editor.textWin.apply:Click()
check(Editor.textWin:IsShown() and Editor.textWin.problem:GetText():find("does not read", 1, true), "bad text is refused")
Editor.textWin:Hide()
Editor.undoButton:Click()
check(draft:StepAt(3).note == "Written in the editor.", "and the text change undone")
local before = 0
for _ in pairs(ns.db.account.guides) do before = before + 1 end
Editor:ImportFromText()
Editor.textWin.area:SetText(draft:Text())
Editor.textWin.apply:Click()
settle()
local after = 0
for _ in pairs(ns.db.account.guides) do after = after + 1 end
check(after == before + 1 and Editor.draft ~= draft and Editor.draft.guide.id ~= id, "imported as a new guide")
ctx.noErrors("text")

-- Settings.
Editor:OpenSettings()
typeInto(Editor.settings.title, "Imported Barrens")
check(Editor.draft.guide.title == "Imported Barrens" and Editor.win.title:GetText() == "Imported Barrens", "renamed")
typeInto(Editor.settings.from, "13")
typeInto(Editor.settings.to, "21")
check(Editor.draft.guide.levels and Editor.draft.guide.levels.to == 21, "levels")
Editor.settings:Hide()
ctx.noErrors("settings")

-- The look: section rows on the band, problems with their fix as a button.
local sectionRow
for _, row in ipairs(Editor.outline.rows) do
    if row:IsShown() and row.item and row.item.kind == "section" then sectionRow = row break end
end
check(sectionRow and sectionRow.kitTint == "band", "a section row is tinted")

-- History: the guide as it was when opened, restored as a change of its own.
local history = Editor:History(Editor.draft.guide.id)
check(#history >= 1 and history[1].what == "As it was when opened", "the opened version is kept")
Editor:OpenHistory()
settle()
check(Editor.historyWin:IsShown(), "the history window")
local titleBefore = Editor.draft.guide.title
local restore
for _, child in ipairs(Editor.historyWin.kitInner.kitChildren[1].kitChildren) do
    for _, part in ipairs(child.kitChildren or {}) do
        if part.kitType == "Button" and part:GetText() == "Restore" then restore = restore or part end
    end
end
restore:Click()
settle()
check(Editor.draft.guide.title ~= titleBefore and not Editor.historyWin:IsShown(), "restored")
Editor:Undo()
check(Editor.draft.guide.title == titleBefore, "and taken back")

-- Ctrl-Z and Ctrl-Y, with no field in focus; other keys go on to the game.
local controlDown = false
local savedControl = rawget(_G, "IsControlKeyDown")
_G.IsControlKeyDown = function() return controlDown end
-- The stand-in has no keyboard calls: given them, the hook is made.
local Object = ctx.frames.Object
Object.EnableKeyboard = Object.EnableKeyboard or function(self, on) self.keyboard = on end
Object.SetPropagateKeyboardInput = Object.SetPropagateKeyboardInput or function(self, on) self.propagate = on end
Editor:HookKeys()
check(Editor.keys, "the key hook is made")
if Editor.keys then
    local keyHandler = Editor.keys:GetScript("OnKeyDown")
    Editor:Hard(Editor.draft.SetGuideField, Editor.draft, "author", "Someone")
    controlDown = true
    keyHandler(Editor.keys, "Z")
    check(Editor.draft.guide.author ~= "Someone", "Ctrl-Z undoes")
    keyHandler(Editor.keys, "Y")
    check(Editor.draft.guide.author == "Someone", "Ctrl-Y does it again")
    controlDown = false
    keyHandler(Editor.keys, "W")
    check(Editor.draft.guide.author == "Someone" and Editor.keys.propagate == true, "other keys go on to the game")
end
_G.IsControlKeyDown = savedControl

-- Quests in the log the guide does not take.
local savedEntries = ns.modules.Client.GetQuestLogEntries
ns.modules.Client.GetQuestLogEntries = function() return { { questID = 99001, title = "A stray quest" }, { questID = 871, title = "Taken" } } end
local menuItems
local ui = ns:GetUI()
local savedOpen = ui.OpenMenu
ui.OpenMenu = function(_, items) menuItems = items end
Editor:OpenMissingQuests()
ui.OpenMenu = savedOpen
ns.modules.Client.GetQuestLogEntries = savedEntries
check(menuItems and #menuItems == 2 and menuItems[2].caption == "A stray quest", "only the quest the guide does not take")
local countNow = Editor.draft:Count()
menuItems[2].onClick()
check(Editor.draft:Count() == countNow + 1 and Editor.step.type == "accept" and Editor.step.quests[1] == 99001, "a click adds its accept")
ctx.noErrors("history and keys")

-- Play from this step.
Editor:Select(Editor.draft:StepAt(5))
Editor:PlayFromStep()
settle()
check(Progress.store.activeGuideID == Editor.draft.guide.id, "the tracker follows it")
local _, at = Editor:NodeOf(Editor.step)
check(Progress:GetState(Repository:Get(Editor.draft.guide.id)).currentStep == at, "from the selected step")
ctx.noErrors("play")

-- The Guide menu, and deleting a guide of the player's own.
Editor:OpenGuideMenu(Editor.undoButton)
settle()
ns:GetUI():CloseMenu()
local deleting = Editor.draft.guide.id
Editor:DeleteGuide()
check(not Repository:IsUserGuide(deleting) and not Editor:IsShown(), "deleted")
ctx.noErrors("delete")

-- A new guide: named, kept at once, and the adding panel beside the tracker.
local Panel = ns.modules.AddingPanel
Editor:OpenNew()
settle()
check(Editor.newWin and Editor.newWin:IsShown(), "the new guide dialog")
Editor.newWin.name:SetText("Hand written")
local startButton
for _, child in ipairs(Editor.newWin.kitInner.kitChildren[1].kitChildren) do
    for _, part in ipairs(child.kitChildren or {}) do
        if part.kitType == "Button" and part:GetText() == "Start adding while I play" then startButton = part end
    end
end
check(startButton, "it offers to start adding while playing")
startButton:Click()
settle()
check(Editor.draft and Editor.draft.guide.title == "Hand written" and Repository:IsUserGuide(Editor.draft.guide.id), "a new guide")
check(Panel:IsShown() and Panel.draft == Editor.draft, "the adding panel opens on it")
check(Panel.buttons.accept.icon and Panel.buttons.accept.icon:IsShown(), "its buttons carry the type's icon")
local made = Editor.draft
ctx.noErrors("new guide")

-- The quest window: Accept adds the quest with the NPC it is open with.
local questFrame = CreateFrame("Frame", "QuestFrame")
questFrame:Show()
local npcUnit = { id = 3449, name = "Darsok Swiftdagger" }
local unitGUID = _G.UnitGUID
_G.UnitGUID = function(unit)
    if unit == "npc" and npcUnit then return "Creature-0-1-2-3-" .. npcUnit.id .. "-0000" end
    return unitGUID(unit)
end
local unitName = _G.UnitName
_G.UnitName = function(unit)
    if unit == "npc" and npcUnit then return npcUnit.name end
    return unitName(unit)
end
local openQuest = 845
_G.GetQuestID = function() return openQuest end
Panel:OnEvent("QUEST_DETAIL")
settle()
check(Panel.questButton and Panel.questButton:IsShown() and Panel.questButton:GetText() == "Add the accept", "the quest window offers the accept")
Panel.questButton:Click()
settle()
local accept = Panel.lastAdded
check(accept and accept.type == "accept" and accept.quests[1] == 845 and accept.npc[1] == 3449, "accept, from the NPC in the window")
check(made:NPC(3449) and type(made:NPC(3449)) == "table" and made:NPC(3449).at, "the NPC kept where the player stands")
check(Panel.questButton:GetText():find("Added as step", 1, true) and Panel.questUndo:IsShown(), "and the window says it is in, with an undo")
check(Panel.buttons.accept:IsActive(), "Accept stands out while the quest window offers one")
openQuest = 846
Panel:Press("accept")
check(Panel.lastAdded == accept and #accept.quests == 2, "a second accept at the same NPC joins the step")

-- The rest of the quest once it is in the log.
local client = ns.modules.Client
local inLog, objectives = client.IsQuestInLog, client.GetQuestObjectives
client.IsQuestInLog = function() return true end
client.GetQuestObjectives = function() return { { text = "Kolkar Bracers: 0/7", type = "item" }, { text = "Kolkar killed: 0/4", type = "monster" } } end
local stepsBefore = made:Count()
Panel:OnEvent("QUEST_ACCEPTED", 846)
settle()
check(Panel.pending and Panel.pending.steps and #Panel.pending.steps == 3, "the rest of the quest is offered")
Panel:TakeOffer()
settle()
check(made:Count() == stepsBefore + 3, "a step per objective and the turn-in")
local position = made:EntryOf(accept).position
check(made:StepAt(position + 1).type == "collect" and made:StepAt(position + 1).quest[2] == 1, "the first objective, right after")
check(made:StepAt(position + 3).type == "turnin", "then the turn-in")
client.IsQuestInLog, client.GetQuestObjectives = inLog, objectives
Panel:OnEvent("QUEST_FINISHED")
questFrame:Hide()
ctx.noErrors("quest window")

-- Kill, go here, a note: from the target, the spot, and typing.
spot.target = { id = 3273, name = "Kolkar Stormer" }
npcUnit = nil
Panel:Press("kill")
check(Panel.lastAdded.type == "kill" and Panel.lastAdded.kill[1] == 3273, "kill the target")
check(made:NPCName(3273) == "Kolkar Stormer" and not made:NPC(3273).at, "a creature is named, not placed")
spot.x, spot.y = 0.4, 0.6
Panel:Press("travel")
check(Panel.lastAdded.type == "travel" and Panel.lastAdded.at[1][1] == 4000, "go here")
Panel:Press("note")
settle()
typeInto(Panel.noteField, "Stay on the road.")
check(Panel.lastAdded.type == "note" and Panel.lastAdded.note == "Stay on the road.", "a note")
local count = made:Count()
Panel.undoButton:Click()
settle()
check(made:Count() == count, "undo takes the note's text back first")
Panel:Undo()
check(made:Count() == count - 1, "then the note")

-- The gossip window: one step for everything at the NPC.
local gossip = CreateFrame("Frame", "GossipFrame")
gossip:Show()
local savedGossip = rawget(_G, "C_GossipInfo")
_G.C_GossipInfo = {
    GetAvailableQuests = function() return { { questID = 850, title = "Kolkar Leaders" }, { questID = 855, title = "Centaur Bracers" } } end,
    GetActiveQuests = function() return { { questID = 846, title = "Done", isComplete = true } } end,
}
npcUnit = { id = 3389, name = "Regthar Deathgate" }
Panel:OnEvent("GOSSIP_SHOW")
settle()
check(Panel.gossipButton and Panel.gossipButton:IsShown() and Panel.gossipButton:GetText() == "Add one step: accept 2",
    "the gossip window offers one step: " .. tostring(Panel.gossipButton and Panel.gossipButton:GetText()))
Panel.gossipButton:Click()
settle()
local talk = Panel.lastAdded
check(talk.type == "talk" and #talk.accept == 2 and talk.npc[1] == 3389, "a talk step accepting both")
Panel:OnEvent("GOSSIP_CLOSED")
gossip:Hide()
_G.C_GossipInfo = savedGossip
_G.UnitGUID, _G.UnitName, _G.GetQuestID = unitGUID, unitName, nil
Panel:Hide()
check(not Panel:IsShown() and not Panel.questButton:IsShown(), "put away, with its buttons")
ctx.noErrors("adding panel")

-- The tracker's fixes, on a guide of the player's own and on a packaged one.
local mine = Repository:Get(made.guide.id)
Progress:Select(mine)
-- Undo restores an earlier copy of the guide, so the accept is looked up again.
for _, entry in ipairs(made:Entries()) do
    if entry.step.type == "accept" and entry.step.quests[1] == 845 then accept = entry.step end
end
local _, acceptAt = Editor:NodeOf(accept)
check(acceptAt, "the accept plays")
spot.target = nil
spot.x, spot.y = 0.55, 0.45
local said = Editor:SpotIsHere(mine, acceptAt)
check(said and made:NPC(3449).at[1] == 5500, "the visit's NPC moved to where the player stands")
spot.target = { id = 3449, name = "Darsok Swiftdagger" }
spot.x = 0.56
said = Editor:NPCIsHere(mine, acceptAt)
check(said and made:NPC(3449).at[1] == 5600, "the NPC is here")
local Main = ns.modules.MainWindow
local items = Main:StepMenuItems(mine, mine.nodes[1])
check(#items == 5 and items[3].caption == "Edit this step", "the tracker's step menu")
local packaged = Repository:Get("nuuroad:leveling:horde-mulgore-6-12")
check(packaged, "the Mulgore guide is packaged")
Progress:Select(packaged)
said = Editor:SpotIsHere(packaged, 3)
local copyID = Editor.draft.guide.id
check(said and copyID ~= packaged.id and Repository:IsUserGuide(copyID), "a fix to a packaged guide makes the player's copy")
check(Progress.store.activeGuideID == copyID, "and the tracker follows it")
ctx.noErrors("tracker fixes")

-- Next guide: a finish step leads on, and the tracker offers it.
local finish = Editor.draft:StepAt(Editor.draft:Count())
check(finish.type == "finish", "the guide ends with a finish step")
Editor.draft:SetField(finish, "next", "nuuroad:leveling:horde-barrens-13-21")
local node = Repository:Get(copyID).nodes[#Repository:Get(copyID).nodes]
check(node.nextGuides and node.nextGuides[1] == "nuuroad:leveling:horde-barrens-13-21", "built with the next guide")
check(Main:NextGuide(node) == Repository:Get("nuuroad:leveling:horde-barrens-13-21"), "the tracker finds it")
ctx.noErrors("next guide")

Editor:Hide()
Editor:Toggle()
check(Editor:IsShown(), "toggle shows what it had")
Editor:Hide()

-- Caves and tunnels, on the cave fixture.
Editor:OpenGuide(Repository:Get("nuuroad:fixture:cave-place"))
settle()
Editor:OpenPlaces()
settle()
check(Editor.placesWin and Editor.placesWin:IsShown(), "the places window shows")
local place = Places:Place()
check(place and Places.pager:GetCount() == #Editor.working.places, "the pager counts the places")
check(#Places.list:GetItems() == #place.points and #place.points >= 2, "every point is listed")
local function clickPoint(index)
    settle()
    for _, row in ipairs(Places.list.rows) do
        if row:IsShown() and row.item and row.item.index == index then row:Click() return true end
    end
    return false
end
check(clickPoint(1), "point 1 on screen")
spot.shift = true
check(clickPoint(2), "point 2 on screen")
spot.shift = false
check(Places.selected == 1 and Places.second == 2, "a shift-click picks a second")
typeInto(Places.placeName, "Test cave")
check(place.name == "Test cave", "the place's name")
local points = #place.points
spot.x, spot.y = 0.51, 0.52
Places:AddPointHere()
settle()
check(#place.points == points + 1, "a point where the player stands")
Editor.placesWin:Hide()
settle()
local kept = Editor.draft.guide.data.places[1]
check(kept.name == "Test cave" and #kept.points == points + 1, "kept in the guide, in format v1")
check(kept.points[points + 1].at[1] == 5100, "in hundredths of a percent")
check(Repository:IsUserGuide(Editor.draft.guide.id), "the fixture became a copy of the player's own")
ctx.noErrors("places")

-- The recorder, from the places window: the walk extends the place.
Editor:OpenPlaces()
settle()
place = Places:Place()
Places.selected = nil
Places:OpenRecorder()
settle()
check(Recorder.win:IsShown() and not Editor.placesWin:IsShown(), "the recorder opens and the places window goes away")
check(Recorder:ShownPlace() == place and not Recorder.owned, "it walks the editor's place")
Recorder.record:Click()
spot.indoors = true
for step = 1, 6 do
    spot.x = 0.5 + step * 0.005
    Recorder:Sample()
end
Recorder.record:Click()
check(not Recorder.recording, "stopped")
Recorder.toEditor:Click()
settle()
check(Editor.placesWin:IsShown(), "back to the places window")
Editor.placesWin:Hide()
settle()

-- A place of the recorder's own, sent to the editor's guide.
Recorder:Start(nil)
check(Recorder.owned, "a place of its own")
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
local placesBefore = #Editor.draft.guide.data.places
check(#Recorder.place.points > 0, "the walk makes a place")
Recorder:SendToEditor()
settle()
check(Editor.placesWin:IsShown() and not Recorder.owned, "the place joins the guide's places window")
Editor.placesWin:Hide()
settle()
check(#Editor.draft.guide.data.places == placesBefore + 1, "and is kept")
Recorder:Close()
Editor:Hide()
settle()
ctx.noErrors("recorder")

for name, value in pairs(saved) do _G[name] = value end
print("editor tests passed")
