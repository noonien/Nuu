_G = _G or _ENV
local ns = { modules = {}, db = { settings = { automation = { markTargets = true } } }, logs = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log(message) table.insert(self.logs, message) end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
AddBuiltInNames(ns)
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Domain/NPCTracking.lua")
local Steps, Progress, NPCTracking = ns.modules.Steps, ns.modules.Progress, ns.modules.NPCTracking

local guide = Steps:Expand({
    kind = "guide", schema = 1, id = "test:npc", updated = 1789862400, title = "NPC", category = "test",
    data = { map = 1413, sections = {
        { title = "Steps", steps = {
            { type = "kill", kill = { 3244, 3245 }, count = 2 },
            { type = "accept", quests = { 870 }, npc = { 3448 } },
            { type = "finish", note = "End" },
        } },
    } },
})
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == guide.id and guide or nil end }
Progress:Select(guide)

-- A fake world: units by token, each with a GUID, a marker, and a dead flag.
local units, marks, canMark, time = {}, {}, true, 100
GetTime = function() return time end
local Client = {}
ns.modules.Client = Client
function Client:UnitExists(unit) return units[unit] ~= nil end
function Client:GetUnitGUID(unit) return units[unit] and units[unit].guid end
function Client:CreatureIDFromGUID(guid) return guid and tonumber(guid:match("^Creature%-0%-1%-1413%-8%-(%d+)%-")) end
function Client:GetUnitCreatureID(unit) return self:CreatureIDFromGUID(self:GetUnitGUID(unit)) end
function Client:UnitIsDead(unit) return units[unit] and units[unit].dead == true end
function Client:CanMarkTargets() return canMark end
-- Like the real one: a second value that is false when the client hides the
-- marker, which happens after one of our own macros did the targeting.
local hidden = {}
function Client:GetRaidTargetIndex(unit)
    if hidden[unit] then return nil, false end
    return units[unit] and marks[units[unit].guid], true
end
function Client:SetRaidTarget(unit, index) marks[units[unit].guid] = index > 0 and index or nil; return true end
function Client:GetNamePlateUnits() local plates = {} for token in pairs(units) do if token:find("^nameplate") then table.insert(plates, token) end end table.sort(plates) return plates end
local inCombat, tapDenied = false, false
function Client:UnitInCombat() return inCombat end
function Client:UnitIsTapDenied(unit) return tapDenied end
function Client:IsPlayerOrGroupGUID(guid) return guid == "Player-1-0A" or guid == "Pet-0-1-1413-8-416-0000000003" end
local combatEntry
function Client:GetCombatLogEvent() return combatEntry end
local function creature(id, serial) return "Creature-0-1-1413-8-" .. id .. "-" .. string.format("%010d", serial) end

-- The panel is told about step changes and about units of the step in view.
local seen, stepChanges = {}, 0
ns.modules.NPCPanel = {
    OnStepChanged = function() stepChanges = stepChanges + 1 end,
    OnUnitSeen = function(_, id, unit) table.insert(seen, id .. "@" .. unit) end,
    Refresh = function() end,
}

-- The kill step marks its targets skull then cross, and nothing else.
NPCTracking:Sync()
assert(stepChanges == 1, "the panel hears about the first step")
assert(NPCTracking:MarkerFor(3244) == 8 and NPCTracking:MarkerFor(3245) == 7 and NPCTracking:MarkerFor(3448) == nil)
local entries = NPCTracking:Entries()
assert(#entries == 2 and entries[1].id == 3244 and entries[2].id == 3245, "kill entries in guide order")
assert(entries[1].kind == "kill" and entries[1].marker == 8 and entries[1].markerName == "skull" and entries[2].markerName == "cross")
assert(entries[1].kills == 0 and entries[1].killsNeeded == 2 and entries[1].done == false, "kill entries carry the shared count")
assert(entries[1].name == "Greater Plainstrider" and entries[2].name == "Ornery Plainstrider", "entries carry display names")
assert(NPCTracking:DescribeMarker(3244) == "skull" and NPCTracking:DescribeMarker(3245) == "cross" and NPCTracking:DescribeMarker(1) == nil)
-- The tracker draws the marker in front of the creature's name, so putting
-- one on asks it to repaint; a unit that gets no marker asks for nothing.
local repaints = 0
ns.modules.MainWindow = { RequestRefresh = function() repaints = repaints + 1 end }
units.target = { guid = creature(3244, 1) }
NPCTracking:Consider("target")
assert(marks[creature(3244, 1)] == 8, "a targeted kill target gets the skull")
assert(seen[1] == "3244@target", "the panel is told the target is in view")
assert(repaints == 1, "marking the target asks the tracker to repaint")
units.mouseover = { guid = creature(3245, 2) }
NPCTracking:Consider("mouseover")
assert(marks[creature(3245, 2)] == 7, "the second kind gets the cross")
-- What we put on a creature is remembered against the creature, not against
-- the unit in view, so the icon stays put when the nameplate goes away.
local worn = NPCTracking:WornMarkers()
assert(worn[3244] == 8 and worn[3245] == 7, "both marks are remembered by creature")
units.target, units.mouseover = nil, nil
worn = NPCTracking:WornMarkers()
assert(worn[3244] == 8 and worn[3245] == 7, "and they outlive the units leaving view")
units.target = { guid = creature(3244, 1) }
units.mouseover = { guid = creature(3245, 2) }
local quiet = repaints
units.nameplate1 = { guid = creature(3246, 3) }
NPCTracking:Consider("nameplate1")
assert(marks[creature(3246, 3)] == nil, "a creature the step does not name is left alone")
assert(repaints == quiet, "a creature the step does not name asks for no repaint")
ns.modules.MainWindow = nil
assert(#seen == 2 and seen[2] == "3245@mouseover", "and the panel does not hear about it")
units.nameplate2 = { guid = creature(3244, 4), dead = true }
NPCTracking:Consider("nameplate2")
assert(seen[3] == "3244@nameplate2", "a corpse still counts as seen for the portrait")
assert(marks[creature(3244, 4)] == nil, "corpses are not marked")
marks[creature(3244, 5)] = 3
units.nameplate3 = { guid = creature(3244, 5) }
NPCTracking:Consider("nameplate3")
assert(marks[creature(3244, 5)] == 3, "a marker someone else set is kept")
canMark = false
units.nameplate4 = { guid = creature(3244, 6) }
NPCTracking:Consider("nameplate4")
assert(marks[creature(3244, 6)] == nil, "no marking without the right to mark")
canMark = true
ns.db.settings.automation.markTargets = false
NPCTracking:Consider("nameplate4")
assert(marks[creature(3244, 6)] == nil, "the setting turns marking off")
NPCTracking:OnSettingsChanged()
assert(marks[creature(3244, 1)] == nil and marks[creature(3245, 2)] == nil, "turning it off removes this module's marks from units in view")
assert(marks[creature(3244, 5)] == 3, "but not marks it did not set")
ns.db.settings.automation.markTargets = true
NPCTracking:OnSettingChanged("tracker.scale")
assert(marks[creature(3244, 1)] == nil, "a setting that is not an automation switch changes nothing")
NPCTracking:OnSettingChanged("automation.markTargets")
assert(marks[creature(3244, 1)] == 8 and marks[creature(3245, 2)] == 7, "turning it on marks what is in view")

-- What is reported is the marker the creature is wearing, not the one the
-- step wanted: a player who changes it by hand changes what NuuRoad says.
-- Marking is off for this, as it is on a client that will not let the addon
-- set one, so nothing puts the step's own marker straight back.
canMark = false
marks[creature(3245, 2)] = 4
NPCTracking:Consider("mouseover")
assert(NPCTracking:WornMarkers()[3245] == 4, "a marker changed by hand replaces the step's own")
marks[creature(3245, 2)] = nil
NPCTracking:Consider("mouseover", true)
assert(NPCTracking:WornMarkers()[3245] == nil, "a marker taken off by hand is not claimed")
-- A marker read off a creature is kept for the session: the step moving on
-- does not unsay what was seen, and only another look at that creature can.
marks[creature(3245, 2)] = 5
NPCTracking:Consider("mouseover")
NPCTracking:Refresh({})
assert(NPCTracking.observed[3245] == 5, "the reading outlives the step it was taken on")
NPCTracking:Sync()
assert(NPCTracking:WornMarkers()[3245] == 5, "and comes back with the creature")
marks[creature(3245, 2)] = nil
NPCTracking:Consider("mouseover", true)
-- A marker changed by hand is read off the unit where the client answers.
-- Where it does not, the reading says nothing either way: the marker-change
-- event names no creature, so treating it as evidence would unsay the icons
-- of everything else in view every time one more creature was marked.
marks[creature(3245, 2)] = 6
NPCTracking:Consider("mouseover")
assert(NPCTracking:WornMarkers()[3245] == 6, "a readable change is simply read")
hidden.mouseover = true
NPCTracking:Consider("mouseover", true)
assert(NPCTracking:WornMarkers()[3245] == 6, "an unreadable one is no evidence against what is known")
-- A guarded value still says the creature wears something, which is enough
-- to stop the row offering a marker and toggling off the one it has.
assert(NPCTracking:CarriedMarkers()[3245] == true, "a guarded value means a marker is there")
hidden.mouseover = nil
marks[creature(3245, 2)] = nil
NPCTracking:Consider("mouseover", true)
assert(NPCTracking:CarriedMarkers()[3245] == nil, "a plain nil means it is not")
marks[creature(3245, 2)] = 6
NPCTracking:Consider("mouseover")
canMark = true
marks[creature(3245, 2)] = nil
NPCTracking:Consider("mouseover")
assert(marks[creature(3245, 2)] == 7 and NPCTracking:WornMarkers()[3245] == 7, "the step marks it again")

-- What the marking macros read: the markers the step's creatures in view
-- already carry, so a click never toggles one of them back off.
local inView, unreadable = NPCTracking:MarkersInView()
assert(inView[3244] == 8 and inView[3245] == 7, "creatures in view report their marker")
assert(inView[3246] == nil, "a creature the step does not name is not reported")
assert(next(unreadable) == nil, "nothing is hidden while the client answers")

-- And which of them are around at all, which is what "Mark all" may offer.
local visible = NPCTracking:VisibleTargets()
assert(visible[3244] == true and visible[3245] == true, "creatures in view are visible")
assert(visible[3246] == nil, "a creature the step does not name is not")

-- A marker the client hides is reported as unreadable, not as absent.
hidden.mouseover = true
local readable, unknown = NPCTracking:MarkersInView()
assert(readable[3245] == nil and unknown[3245] == true, "a hidden marker is not mistaken for no marker")
marks[creature(3245, 2)] = nil
NPCTracking:Consider("mouseover")
assert(marks[creature(3245, 2)] == nil, "and nothing is marked while the marker is hidden")
hidden.mouseover = nil
NPCTracking:Consider("mouseover")
assert(marks[creature(3245, 2)] == 7, "once it can be read again, marking resumes")
marks[creature(3244, 1)], marks[creature(3244, 5)], marks[creature(3244, 6)] = nil, nil, nil
assert(NPCTracking:MarkersInView()[3244] == nil, "an unmarked creature is left out")
marks[creature(3244, 1)], marks[creature(3244, 5)], marks[creature(3244, 6)] = 8, 3, 8

-- Kills: only PARTY_KILL credited to the player or their group, each corpse once.
local refreshed = 0
ns.modules.ObservedProgress = { Refresh = function()
    refreshed = refreshed + 1
    local node = Progress:GetCurrentNode(guide)
    if node and node.completion.observed.type == "kills" and Progress:KillCount(guide, node.index) >= node.completion.observed.count then Progress:Complete(guide, nil, "observed"); return true end
    return false
end }
combatEntry = { subevent = "PARTY_KILL", sourceGUID = "Player-1-0A", destGUID = creature(3244, 1), destName = "Greater Plainstrider" }
NPCTracking:OnCombatLog()
assert(Progress:KillCount(guide, 1) == 1 and refreshed == 1)
NPCTracking:OnCombatLog()
assert(Progress:KillCount(guide, 1) == 1, "the same corpse is not counted twice")
combatEntry = { subevent = "PARTY_KILL", sourceGUID = "Player-1-0B", destGUID = creature(3245, 7) }
NPCTracking:OnCombatLog()
assert(Progress:KillCount(guide, 1) == 1, "someone else's kill does not count")
combatEntry = { subevent = "UNIT_DIED", sourceGUID = nil, destGUID = creature(3245, 8) }
NPCTracking:OnCombatLog()
assert(Progress:KillCount(guide, 1) == 1, "a death without a killing blow of ours does not count")
combatEntry = { subevent = "PARTY_KILL", sourceGUID = "Player-1-0A", destGUID = creature(3246, 9) }
NPCTracking:OnCombatLog()
assert(Progress:KillCount(guide, 1) == 1, "a creature the step does not ask for does not count")
combatEntry = { subevent = "PARTY_KILL", sourceGUID = "Pet-0-1-1413-8-416-0000000003", destGUID = creature(3245, 10) }
NPCTracking:OnCombatLog()
assert(Progress:KillCount(guide, 1) == 2, "a pet's killing blow counts")
assert(Progress:GetCurrentNode(guide).index == 2, "reaching the count completes the step")
Progress:Back(guide); NPCTracking:Sync()
assert(NPCTracking:Entries()[1].kills == 2 and NPCTracking:Entries()[1].done == true, "entries report the kills so far")
Progress:Complete(guide, nil, "observed"); NPCTracking:Sync()

-- Without the combat log, the player's own target dying while fighting counts.
Progress:Back(guide); Progress.session[guide.id].kills = {}; NPCTracking:Sync()
units.target = { guid = creature(3244, 20) }
NPCTracking:OnTargetChanged()
inCombat = true
units.target.dead = true
NPCTracking:OnTargetHealth()
assert(Progress:KillCount(guide, 1) == 1, "the target dying in combat counts")
NPCTracking:OnTargetHealth()
assert(Progress:KillCount(guide, 1) == 1, "a second health event for the corpse does not")
units.target = { guid = creature(3244, 21), dead = true }
NPCTracking:OnTargetChanged(); NPCTracking:OnTargetHealth()
assert(Progress:KillCount(guide, 1) == 1, "targeting a corpse is not a kill")
units.target = { guid = creature(3245, 22) }
NPCTracking:OnTargetChanged()
inCombat = false; time = 200; NPCTracking.combatLeftAt = 150
units.target.dead = true
NPCTracking:OnTargetHealth()
assert(Progress:KillCount(guide, 1) == 1, "a target dying long after combat is someone else's")
units.target = { guid = creature(3245, 23) }
NPCTracking:OnTargetChanged()
NPCTracking.combatLeftAt = 199
units.target.dead = true
NPCTracking:OnTargetHealth()
assert(Progress:KillCount(guide, 1) == 2, "a target dying as combat ends counts")
units.target = { guid = creature(3245, 24) }
tapDenied = true
NPCTracking:OnTargetChanged()
inCombat = true; units.target.dead = true
NPCTracking:OnTargetHealth()
assert(Progress:KillCount(guide, 1) == 2, "a creature tagged by someone else does not count")
tapDenied = false
assert(Progress:GetCurrentNode(guide).index == 2)

-- The next step marks its quest giver with a star and records the dialog.
assert(marks[creature(3245, 2)] == nil, "a finished target's mark comes off without waiting for the step to change")
NPCTracking:Sync()
assert(NPCTracking:MarkerFor(3448) == 1 and NPCTracking:MarkerFor(3244) == nil and NPCTracking:DescribeMarker(3448) == "star")
assert(marks[creature(3245, 2)] == nil, "a mark from the finished step is taken off a unit still in view")
assert(marks[creature(3244, 5)] == 3, "a mark someone else set stays")
units.nameplate5 = { guid = creature(3245, 13) }
marks[creature(3245, 13)] = 7
NPCTracking:Consider("nameplate5")
assert(marks[creature(3245, 13)] == 7, "a cross this module did not set on a creature of an earlier step is left alone")
entries = NPCTracking:Entries()
assert(#entries == 1 and entries[1].id == 3448 and entries[1].kind == "talk" and entries[1].markerName == "star" and entries[1].done == false)
assert(entries[1].name == "Tonga Runetotem" and entries[1].kills == nil, "a talk entry carries the name and no kill count")
units.target = { guid = creature(3448, 11) }
NPCTracking:Consider("target")
assert(marks[creature(3448, 11)] == 1, "the quest giver gets a star")
units.npc = { guid = creature(3244, 12) }
local seenBefore = #seen
NPCTracking:OnDialog()
assert(not Progress:HasTalked(guide, 2, 3448), "a dialog with another creature is not the talk")
assert(#seen == seenBefore, "and the panel does not hear about it")
units.npc = { guid = creature(3448, 11) }
NPCTracking:OnDialog()
assert(Progress:HasTalked(guide, 2, 3448), "opening the quest giver's dialog records the talk")
assert(seen[#seen] == "3448@npc", "the dialog unit is offered for the portrait")
assert(NPCTracking:Entries()[1].done == false, "the row of a quest NPC is done by its quest, not by the dialog")
-- The tracker's talk line reads the visit the same way the panel row does.
function Client:IsQuestInLog() return false end
function Client:IsQuestComplete() return false end
function Client:IsQuestReadyToTurnIn() return false end
assert(Steps:GoalStatus(Steps:Goals(Progress:GetCurrentNode(guide))[1], Progress:GetCurrentNode(guide)) == "active",
    "the tracker's talk line is work under way until the quest is taken")

-- A run of quest steps is followed as one: every quest giver is a target at
-- once, a turn-in NPC waits for its quest, and a dialog credits every step
-- that names the NPC.
local hub = Steps:Expand({
    kind = "guide", schema = 1, id = "test:hub", updated = 1789862400, title = "Hub", category = "test",
    data = { map = 1413, sections = {
        { title = "Steps", steps = {
            { group = {
                { type = "accept", quests = { 870 }, npc = { 3448 } },
                { type = "accept", quests = { 869 }, npc = { 3464 } },
                { type = "turnin", quests = { 842 }, npc = { 3338 } },
                { type = "talk", turnin = { 869 }, accept = { 871 }, npc = { 3464 } },
            } },
            { type = "kill", quest = 870 },
            { type = "turnin", quests = { 870 }, npc = { 3448 } },
        } },
    } },
})
ns.modules.GuideRepository = { Get = function(_, id) return id == hub.id and hub or nil end }
Progress.store, Progress.session = {}, {}
Progress:Select(hub)
local questLog, questDone = {}, {}
function Client:IsQuestInLog(id) return questLog[id] == true end
function Client:IsQuestComplete(id) return questDone[id] == true end
function Client:IsQuestReadyToTurnIn(id) return false end
function Client:IsQuestObjectiveComplete() return false end
function Client:MatchesObservedCompletion() return false end
Load(ns, "Domain/GuideScan.lua")
stepChanges = 0
NPCTracking:Sync()
assert(stepChanges == 1, "the panel hears about the group once")
entries = NPCTracking:Entries()
assert(#entries == 3 and entries[1].id == 3448 and entries[2].id == 3464 and entries[3].id == 3338, "one row per creature, in guide order, the NPC of two steps once")
-- One icon each: five stars in a hub tell five givers apart no better than
-- none would, so the star goes to the first and the rest follow it.
assert(NPCTracking:MarkerFor(3448) == 1 and NPCTracking:MarkerFor(3464) == 2, "each quest giver of the group gets its own marker")
assert(NPCTracking:MarkerFor(3338) == nil and entries[3].live == false and entries[3].waiting == 842 and entries[3].marker == nil, "a turn-in NPC whose quest is missing is listed but not live")
assert(entries[1].live == true and entries[1].done == false)
units.target = { guid = creature(3338, 30) }
NPCTracking:Consider("target")
assert(marks[creature(3338, 30)] == nil, "and is not marked on sight")
units.target = { guid = creature(3464, 31) }
NPCTracking:Consider("target")
assert(marks[creature(3464, 31)] == 2, "a later step's quest giver is marked on sight, with its own icon")
questLog[842] = true
NPCTracking:Sync()
assert(NPCTracking:MarkerFor(3338) == 3 and NPCTracking:Entries()[3].live == true, "the turn-in NPC goes live once the quest is in the log")
assert(stepChanges == 1, "with no change of membership the targets are kept")
units.npc = { guid = creature(3464, 31) }
NPCTracking:OnDialog()
assert(Progress:HasTalked(hub, 2, 3464) and Progress:HasTalked(hub, 4, 3464), "a dialog credits every step naming the NPC")
assert(NPCTracking:Entries()[2].done == false, "a quest NPC is done by its quests, not its dialog")
questLog[869] = true
Progress:Record(hub, 2, "observed")
assert(NPCTracking:Entries()[2].done == false, "one of its two steps done is not enough")
questDone[869] = true; questLog[869] = nil; questLog[871] = true
assert(NPCTracking:Entries()[2].done == true, "both done: the row is done")
assert(NPCTracking:MarkerFor(3464) == nil, "and a finished NPC gets no marker")
NPCTracking:Consider("target")
assert(marks[creature(3464, 31)] == nil, "the marker this module set is taken off it")
Progress:Complete(hub, nil, "observed"); Progress:Complete(hub, nil, "observed"); Progress:Complete(hub, nil, "observed"); Progress:Complete(hub, nil, "observed")
NPCTracking:Sync()
assert(stepChanges == 2 and #NPCTracking:Entries() == 0, "the objective step is its own group with no creatures")

-- Kill steps in one camp can be grouped: every target is marked at once, and
-- a kill counts for the step that names the creature, not the current one.
local camp = Steps:Expand({
    kind = "guide", schema = 1, id = "test:camp", updated = 1789862400, title = "Camp", category = "test",
    data = { map = 1413, sections = {
        { title = "Steps", steps = {
            { group = {
                { type = "kill", kill = { 3265 }, count = 3 },
                { type = "kill", kill = { 3267 }, count = 2 },
            } },
            { type = "finish", note = "End" },
        } },
    } },
})
ns.modules.GuideRepository = { Get = function(_, id) return id == camp.id and camp or nil end }
ns.modules.ObservedProgress = nil
Progress.store, Progress.session = {}, {}
Progress:Select(camp)
NPCTracking:Sync()
assert(NPCTracking:MarkerFor(3265) == 8 and NPCTracking:MarkerFor(3267) == 7, "each grouped kill target gets its own marker")
combatEntry = { subevent = "PARTY_KILL", sourceGUID = "Player-1-0A", destGUID = creature(3267, 40) }
NPCTracking:OnCombatLog()
assert(Progress:KillCount(camp, 1) == 0 and Progress:KillCount(camp, 2) == 1, "a kill counts for the member that names it")
entries = NPCTracking:Entries()
assert(entries[1].kills == 0 and entries[1].killsNeeded == 3, "the first target reads its own step's count")
assert(entries[2].kills == 1 and entries[2].killsNeeded == 2, "the second target reads its own step's count")
-- A member finished ahead of its turn leaves the strip with its line on the
-- card, and its creatures are no longer marked.
Progress:Record(camp, 2, "observed")
entries = NPCTracking:Entries()
assert(entries[2].done == true and entries[2].marker == nil, "a finished member's target is done")
assert(NPCTracking:MarkerFor(3267) == nil and NPCTracking:MarkerFor(3265) == 8, "and only the unfinished target is marked")
assert(entries[1].done == false)
-- A creature that stays in the group keeps its marker when the group
-- changes; only a creature new to it takes one, the first one free.
local members = NPCTracking.nodes
NPCTracking:Refresh({ members[2] })
assert(NPCTracking:AssignedMarker(3267) == 7, "a creature left alone in the group keeps its marker")
NPCTracking:Refresh({ members[1], members[2] })
assert(NPCTracking:AssignedMarker(3265) == 8 and NPCTracking:AssignedMarker(3267) == 7, "one joining it takes the first marker free")
NPCTracking:Refresh({ members[1] })
NPCTracking:Refresh({ members[2] })
assert(NPCTracking:AssignedMarker(3267) == 8, "a creature that left the group starts afresh")

return true
