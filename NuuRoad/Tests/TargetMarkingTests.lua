_G = _G or _ENV
local ns = { modules = {}, db = { settings = { automation = { markTargets = true } } }, logs = {}, prints = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log(message) table.insert(self.logs, message) end
function ns:Print(message) table.insert(self.prints, message) end
ns.Kit = ns.Kit or LoadKit()
Load(ns, "Config.lua")
Load(ns, "Domain/TargetMarking.lua")
local TargetMarking = ns.modules.TargetMarking

-- A fake client: one target, the text behind each secure button, combat flag, and a bound key.
local target, marks, macros, inCombat, key, writes, boundButton = nil, {}, {}, false, nil, 0, nil
local hiddenMarkers = {} -- creature IDs whose marker the client refuses to show
local inView = { [3244] = true, [3245] = true } -- creature IDs that are around
local Client = {}
ns.modules.Client = Client
function Client:Has(capability) return capability == "secureMarking" end
function Client:UnitExists(unit) return unit == "target" and target ~= nil end
function Client:UnitIsDead(unit) return target and target.dead == true end
function Client:GetUnitCreatureID(unit) return target and target.id end
function Client:GetRaidTargetIndex(unit) return target and marks[target.id] end
function Client:MayMarkInGroup() return true end
function Client:InCombatLockdown() return inCombat end
function Client:SetSecureMacroText(button, body) if inCombat then return false end macros[button.name] = body; writes = writes + 1; return true end
function Client:GetBindingKeyForButton() return key end
function Client:BindKeyToButton(newKey, buttonName) key, boundButton = newKey, buttonName; return true end
function Client:CreateSecureMacroButton(name, text) macros[name] = text; return { name = name } end
function Client:RegisterUnitEvent() return true end
local savedCreateFrame = _G.CreateFrame
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local entries = {
    { id = 3244, kind = "kill", marker = 8, name = "Plainstrider" },
    { id = 3245, kind = "kill", marker = 7, name = "Savannah Prowler" },
}
ns.modules.NPCTracking = {
    targets = { [3244] = { marker = 8, kind = "kill" }, [3245] = { marker = 7, kind = "kill" } },
    Enabled = function(_, k) return ns.db.settings.automation[k] == true end,
    MarkerFor = function(_, id) return ({ [3244] = 8, [3245] = 7 })[id] end,
    Entries = function() return entries end,
    MarkersInView = function()
        local seen, unknown = {}, {}
        for id, marker in pairs(marks) do seen[id] = marker end
        for id in pairs(hiddenMarkers) do seen[id], unknown[id] = nil, true end
        return seen, unknown, inView
    end,
    VisibleTargets = function() return inView end,
}

TargetMarking:Initialize()
_G.CreateFrame = savedCreateFrame
assert(TargetMarking.available == true)

-- Nothing targeted: the key does nothing. The mark button starts out as a
-- no-op and is left alone; only the mark-all text, which lists the step's
-- creatures, is written.
TargetMarking:Prepare()
assert(macros.NuuRoadMarkButton == "/stopmacro", "idle body is a no-op")
assert(writes == 1, "only the mark-all text changed since the buttons were made")
TargetMarking:Prepare()
assert(writes == 1, "an unchanged body is not rewritten")

-- Every block clears the marker before setting it, so it sets rather than
-- toggles: nothing here can know what a creature is already wearing, and a
-- press built on that guess could take a marker off instead of putting one
-- on. Pressing twice is therefore the same as pressing once.
local plainstrider = "/cleartarget\n/targetexact Plainstrider\n/cleartarget [dead]\n/tm 0\n/tm 8"
local prowler = "/cleartarget\n/targetexact Savannah Prowler\n/cleartarget [dead]\n/tm 0\n/tm 7"
assert(macros.NuuRoadMarkAllButton == plainstrider .. "\n" .. prowler)
local allText, allIDs = TargetMarking:MarkAllMacroText()
assert(allText == macros.NuuRoadMarkAllButton and #allIDs == 2 and allIDs[1] == 3244, "the click learns what it marked")
assert(TargetMarking:RowBody(entries[1]) == plainstrider, "a row targets its creature and sets its marker")

-- A creature believed to be marked already stays in: what it is really
-- wearing is a guess, and the block sets the marker either way.
marks[3244] = 8
TargetMarking:Prepare()
assert(macros.NuuRoadMarkAllButton == plainstrider .. "\n" .. prowler, "a marked creature is still offered")
assert(TargetMarking:RowBody(entries[1]) == plainstrider, "and its row still sets the marker")
marks[3244] = nil
hiddenMarkers[3244] = true
TargetMarking:NoteMarked(3244)
TargetMarking:Prepare()
assert(macros.NuuRoadMarkAllButton:find("Plainstrider", 1, true), "so does one the client will not report on")
assert(TargetMarking:AssumedList() == "3244")
TargetMarking:ForgetAssumed(3244)
TargetMarking:Prepare()
-- The client reports a unit unmarked for a moment after one of our macros
-- drove the targeting, so a bare reading is not believed straight away; once
-- the click has settled, a bare unit means the player took the marker off.
TargetMarking:NoteMarked(3244)
assert(select(1, TargetMarking:NoteBare(3244)) == false, "a bare reading right after the click is not believed")
assert(TargetMarking:AssumedList() == "3244", "so the click's record stands")
TargetMarking.assumed[3244] = TargetMarking.assumed[3244] - 60
local believed, dropped = TargetMarking:NoteBare(3244)
assert(believed and dropped and TargetMarking:AssumedList() == "none", "once settled, the bare unit is believed")
assert(select(2, TargetMarking:NoteBare(3244)) == false, "and a creature we assumed nothing about drops nothing")

-- What the strip draws: a creature carrying a marker gets an icon, one that
-- is not gets none, and the icon is the marker the step asked for where the
-- client will not say which one is really there.
TargetMarking:ForgetAssumed()
marks[3244], marks[3245] = nil, nil
assert(next(TargetMarking:MarkersToDraw()) == nil, "nothing marked, nothing drawn")
TargetMarking:NoteMarked(3244)
assert(TargetMarking:MarkersToDraw()[3244] == 8 and TargetMarking:MarkersToDraw()[3245] == nil,
    "a creature we marked is drawn with the marker the step asked for")
TargetMarking:ForgetAssumed()
assert(next(TargetMarking:MarkersToDraw()) == nil, "and the icon goes with the record")

-- A key press is the other way a marker gets set, and the only account of
-- it is the text the button was carrying: without recording it, a key marks
-- a creature and the step line never hears.
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local pressed = {}
local hooked = { SetScript = function(self, script, handler) pressed[self.name] = handler end }
local savedCreate = Client.CreateSecureMacroButton
function Client:CreateSecureMacroButton(name, text)
    macros[name] = text
    return setmetatable({ name = name }, { __index = hooked })
end
TargetMarking.assumed = {}
TargetMarking:Initialize()
Client.CreateSecureMacroButton = savedCreate
_G.CreateFrame = savedCreateFrame
target = { id = 3244 }
assert(type(pressed[TargetMarking.buttonName]) == "function", "the mark button records what it did")
pressed[TargetMarking.buttonName]()
assert(TargetMarking:MarkedByUs()[3244] == 8, "a key press on a step creature is recorded")
TargetMarking:ForgetAssumed()
TargetMarking.allIDs = { 3244, 3245 }
pressed[TargetMarking.allButtonName]()
assert(TargetMarking:MarkedByUs()[3245] == 7, "and a mark-all key press records everything its text tried")
TargetMarking:ForgetAssumed()
target = nil

-- The strip and the step lines answer different questions, so they are
-- allowed to disagree: the strip draws any marker really on a creature, the
-- lines only the ones a press through NuuRoad put on.
marks[3245] = 7
assert(TargetMarking:MarkersToDraw()[3245] == 7, "the strip draws a marker somebody else set")
assert(TargetMarking:MarkedByUs()[3245] == nil, "the step line does not claim it")
TargetMarking:NoteMarked(3245)
assert(TargetMarking:MarkedByUs()[3245] == 7, "once a press of ours set one, the line draws it too")
TargetMarking:ForgetAssumed()
marks[3245] = nil

-- A step moving on inside a hub keeps the record for the creatures the new
-- step still names: they are standing there wearing the marker, and dropping
-- the record would take the icon away and put the toggle back in the row.
TargetMarking:NoteMarked({ 3244, 3245 })
TargetMarking:ForgetAssumedExcept({ [3245] = true })
assert(TargetMarking:AssumedList() == "3245", "only the creature the step dropped is forgotten")
TargetMarking:ForgetAssumedExcept(nil)
assert(TargetMarking:AssumedList() == "none", "no targets at all forgets everything")
hiddenMarkers[3244] = nil
TargetMarking:ForgetAssumed()

-- Pressing twice is the same as pressing once, whatever the client says
-- about the creature in between: the block sets the marker, so a second
-- press cannot take it off again.
TargetMarking:NoteMarked(3244)
TargetMarking:Prepare()
assert(macros.NuuRoadMarkAllButton == plainstrider .. "\n" .. prowler, "a press of ours does not empty the next press")
assert(TargetMarking:RowBody(entries[1]) == plainstrider, "and a second click sets the same marker again")
TargetMarking:ForgetAssumed()

-- "Mark all" offers every creature the step still wants marked, in view or
-- not, and credits every one it tried. "In view" means a nameplate, which a
-- player can have turned off while standing in front of all of them; and a
-- claim that turns out to be wrong is dropped by the first look at the
-- creature, since a marker's absence is what the client does report.
inView[3245] = nil
TargetMarking:Prepare()
assert(macros.NuuRoadMarkAllButton:find("Savannah Prowler", 1, true), "a creature out of view is still offered")
TargetMarking:NoteMarkedInView({ 3244, 3245 })
assert(TargetMarking:AssumedList() == "3244, 3245", "the press credits every creature it tried")
TargetMarking:ForgetAssumed()
inView[3245] = true
TargetMarking:Prepare()

-- A finished NPC is left out, and with none left the macro does nothing.
entries[1].done, entries[2].done = true, true
TargetMarking:Prepare()
assert(macros.NuuRoadMarkAllButton == "/stopmacro" and TargetMarking:MarkAllMacroText() == nil)
entries[1].done, entries[2].done = nil, nil
TargetMarking:Prepare()

-- Blocks that no longer fit the button's text limit are dropped
-- and counted, while the panel button's longer text still holds them.
local body, _, skipped = TargetMarking:MarkAllBody(80)
assert(body == plainstrider and skipped == 1, body)

-- A step NPC without a marker arms the key with its icon.
target = { id = 3244 }
TargetMarking:Prepare()
assert(macros.NuuRoadMarkButton == "/tm 0\n/tm 8", "skull for the first kill target, set rather than toggled")
assert(TargetMarking:IsArmed())
assert(#ns.prints == 0, "arming the key says nothing in chat")
target = { id = 3245 }
TargetMarking:Prepare()
assert(macros.NuuRoadMarkButton == "/tm 0\n/tm 7")

-- A unit that already carries a marker is still armed: the key sets the
-- step's marker rather than toggling, so pressing it there is harmless and
-- puts back a marker the player may have changed.
marks[3245] = 7
TargetMarking:Prepare()
assert(macros.NuuRoadMarkButton == "/tm 0\n/tm 7")
marks[3245] = nil

-- Dead units and NPCs outside the step never arm the key.
target = { id = 3245, dead = true }
TargetMarking:Prepare()
assert(macros.NuuRoadMarkButton == "/stopmacro")
target = { id = 999 }
TargetMarking:Prepare()
assert(macros.NuuRoadMarkButton == "/stopmacro")

-- In combat the macro cannot change; the write waits for combat to end.
target = { id = 3244 }
inCombat = true
TargetMarking:Prepare()
assert(macros.NuuRoadMarkButton == "/stopmacro" and TargetMarking.pending == true)
inCombat = false
TargetMarking:Prepare()
assert(macros.NuuRoadMarkButton == "/tm 0\n/tm 8" and TargetMarking.pending == false)

-- Turning the setting off disarms the key, the rows, and the mark-all macro.
ns.db.settings.automation.markTargets = false
TargetMarking:Prepare()
assert(macros.NuuRoadMarkButton == "/stopmacro")
assert(macros.NuuRoadMarkAllButton == "/stopmacro")
assert(TargetMarking:RowBody(entries[1]) == "/cleartarget\n/targetexact Plainstrider\n/cleartarget [dead]", "rows still target, but no longer mark")
ns.db.settings.automation.markTargets = true

-- Key management through the slash command.
TargetMarking:SetKey("")
assert(ns.prints[#ns.prints]:find("No mark key"))
TargetMarking:SetKey(" f8 ")
assert(key == "F8" and ns.prints[#ns.prints]:find("F8"))
TargetMarking:SetKey("")
assert(ns.prints[#ns.prints]:find("Mark key: F8"))
TargetMarking:SetKey("none")
assert(key == nil)
TargetMarking:SetKey("f9", TargetMarking.allButtonName)
assert(boundButton == TargetMarking.allButtonName and key == "F9", "the mark-all key binds its own button")
