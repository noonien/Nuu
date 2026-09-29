_G = _G or _ENV
local ns = { modules = {}, db = {}, printed = {}, logs = {}, version = "test", name = "NuuRoad" }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Print(message) table.insert(self.printed, message) end
function ns:Log(message) table.insert(self.logs, message) end
function ns:Record(channel, data) return self.recorder:Record(channel, data) end
function ns:RecordHere(channel, data) return self.recorder:RecordHere(channel, data) end
ns.Kit = ns.Kit or LoadKit()
-- The session log is the kit's recorder (ns.recorder, made in Core.lua), with
-- where the player stands read the way Core.lua reads it.
ns.recorder = ns.Kit.NewRecorder({
    db = function() return ns.db end,
    version = ns.version,
    log = function(message) ns:Log(message) end,
    where = function()
        local Client = ns.modules.Client
        local mapID = Client and Client:GetCurrentMapID()
        if not mapID then return nil end
        return mapID, Client:GetPlayerMapPosition(mapID)
    end,
})

_G.time = function() return 1789862400 end
_G.date = function(format) return format == "%H:%M" and "19:00" or "2026-09-21 19:00:00" end
local clock = 100
_G.GetTime = function() return clock end

local frames = {}
local previousCreateFrame = CreateFrame
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:SetScript(name, handler) self.scripts[name] = handler end
    table.insert(frames, frame)
    return frame
end

Load(ns, "Config.lua")
Load(ns, "Domain/Recording.lua")
local Recorder, Recording = ns.recorder, ns.modules.Recording

-- A stand-in client that answers only what a test has put in front of it, the
-- way the real one answers only what the player is standing in.
local secretValue = setmetatable({}, {})
local world = {
    log = {},             -- { [questID] = { title, objectives = { { text, have, need, finished } } } }
    loot = {},
    bags = {},
    counts = {},
    skills = {},
    money = 0,
    npc = nil, npcName = nil,
    zone = "The Barrens", subzone = "The Crossroads",
    taxiNode = nil, onTaxi = false, bind = "The Crossroads",
}
local Client = {
    capabilities = {},
    IsSecret = function(_, value) return value == secretValue end,
    Read = function(_, func, ...)
        if type(func) ~= "function" then return nil end
        local ok, value = pcall(func, ...)
        if not ok or value == secretValue then return nil end
        return value
    end,
    GetCurrentMapID = function() return world.map or 1413 end,
    GetPlayerMapPosition = function() return 0.522, 0.311 end,
    GetQuestLogEntries = function()
        local entries = {}
        for questID, quest in pairs(world.log) do table.insert(entries, { questID = questID, title = quest.title }) end
        table.sort(entries, function(a, b) return a.questID < b.questID end)
        return entries
    end,
    GetQuestObjectives = function(_, questID)
        local quest = world.log[questID]
        return quest and quest.objectives or {}
    end,
    GetQuestLogText = function(_, questID)
        local quest = world.log[questID]
        return quest and quest.text, quest and quest.objectiveText
    end,
    GetLootSlots = function() return world.loot end,
    GetUnitCreatureID = function() return world.npc end,
    GetUnitName = function() return world.npcName end,
    GetOpenQuestID = function() return world.openQuest end,
    GetQuestOfferText = function() return world.title, world.text, world.objectiveText end,
    GetQuestRewardText = function() return world.rewardText end,
    GetQuestProgressText = function() return world.progressText end,
    GetQuestRewardChoice = function(_, index) return world.rewards and world.rewards[index] end,
    GetBagItems = function() return world.bags end,
    GetItemCount = function(_, itemID) return world.counts[itemID] or 0 end,
    GetMoney = function() return world.money end,
    GetSkillRanks = function() return world.skills end,
    GetCurrentTaxiNodeName = function() return world.taxiNode end,
    GetBindLocation = function() return world.bind end,
    IsOnTaxi = function() return world.onTaxi end,
    GetZoneName = function() return world.zone end,
    GetSubzone = function() return world.subzone end,
    GetEquippedItemID = function() return world.equipped end,
    GetBagItemForSpell = function(_, spellID) return world.spellItem and world.spellItem[spellID] end,
    IsPlayerGhost = function() return world.ghost == true end,
    RegisterUnitEvent = function(_, frame, event) frame:RegisterEvent(event); return true end,
    OnQuestRewardChosen = function() return true end,
}
ns.modules.Client = Client
ns.modules.Names = {
    quests = { [871] = "Plainstrider Menace" },
    npcs = { [3446] = "Mebok Mizzyrix", [3244] = "Greater Plainstrider", [3390] = "Devrak" },
    items = { [3164] = "Plainstrider Beak", [4854] = "Sturdy Cloth Belt", [2318] = "Light Leather", [4540] = "Tough Hunk of Bread" },
    Quest = function(self, id) return self.quests[id] end,
    NPC = function(self, id) return self.npcs[id] end,
    Item = function(self, id) return self.items[id] end,
}
ns.db.settings = { recording = { enabled = false } }
Recorder:Begin({})

local function rows() return Recording:Rows() end
local function last() local list = rows(); return list[#list] end
local function lastData() local row = last(); return row and row.d or {} end

-- Off is off: a producer called with recording disabled writes nothing at all.
world.log[871] = { title = "Plainstrider Menace", text = "Your first prey will be easy.", objectiveText = "Collect 7 Plainstrider Beaks.",
    objectives = { { text = "Plainstrider Beak: 0/7", have = 0, need = 7, type = "item" } } }
Recording:ScanObjectives()
Recording:OnQuestAccepted(871)
Recording:OnLootOpened()
Recording:Write({ event = "objective" })
assert(#rows() == 0, "nothing is written while recording is off")

-- Turning it on says so, and tells whoever is watching.
local changes = 0
Recording:OnChange(function() changes = changes + 1 end)
Recording:SetEnabled(true)
assert(ns.db.settings.recording.enabled == true, "the setting is the one source of truth")
assert(Recording:Enabled())
assert(#rows() == 2 and rows()[1].d.event == "recording" and rows()[1].d.on == true, "the session says when it started recording")
assert(rows()[1].d.map == 1413 and rows()[1].d.at[1] == 52.2, "and where, since every row carries its place")
assert(changes >= 1, "listeners hear it")

-- The quest log as it stood is written once, whole, so the ticks that follow
-- have something to be relative to.
local snapshot = rows()[2].d
assert(snapshot.event == "questlog" and snapshot.count == 1, "the quest log is recorded when recording starts")
assert(snapshot.quests[1].quest == 871 and snapshot.quests[1].title == "Plainstrider Menace")
assert(snapshot.quests[1].objectives[1].have == 0 and snapshot.quests[1].objectives[1].need == 7 and snapshot.quests[1].objectives[1].done == false)
assert(snapshot.quests[1].text == "Your first prey will be easy." and snapshot.quests[1].objectiveText == "Collect 7 Plainstrider Beaks.", "the words come along, as on an accept row")
local described = Recording:Describe(rows()[2])
assert(described.text == "Quest log: 1 quest", described.text)
assert(described.detail[1] == "Plainstrider Menace (0/7)", described.detail[1])

-- A quest already in the log at that moment is the baseline, not seven things
-- that just happened.
Recording:ScanObjectives()
assert(#rows() == 2, "the quests already in the log seed the baseline silently")

-- An objective line that moved is one row, and standing still is none.
world.log[871].objectives[1] = { text = "Plainstrider Beak: 3/7", have = 3, need = 7, type = "item" }
Recording:ScanObjectives()
assert(#rows() == 3 and lastData().event == "objective", "a line that moved is recorded")
assert(lastData().quest == 871 and lastData().part == 1 and lastData().have == 3 and lastData().need == 7)
assert(lastData().done == false and lastData().type == "item")
Recording:ScanObjectives()
Recording:ScanObjectives()
assert(#rows() == 3, "and a line that did not move is not recorded again")
world.log[871].objectives[1] = { text = "Plainstrider Beak: 7/7", have = 7, need = 7, finished = true, type = "item" }
Recording:ScanObjectives()
assert(#rows() == 4 and lastData().done == true, "finishing is a move too")

-- A quest accepted carries the words the dialog was showing, because they are
-- gone by the time the client says the quest was taken.
local before = #rows()
world.openQuest, world.npc, world.npcName = 871, 3446, "Mebok Mizzyrix"
world.title, world.text, world.objectiveText = "Plainstrider Menace", "Those birds...", "Bring 7 beaks."
Recording:OnQuestDetail()
Recording:OnQuestAccepted(871)
local accept = lastData()
assert(accept.event == "accept" and accept.quest == 871 and accept.npc == 3446)
assert(accept.title == "Plainstrider Menace" and accept.objectiveText == "Bring 7 beaks.")
assert(#rows() == before + 2, "the dialog itself is one row and the acceptance another")

-- A reward the player chose is data about what they chose, on the turn-in row.
world.rewards = { [2] = 4854 }
world.rewardText = "Take this."
Recording:OnQuestComplete()
Recording:OnRewardChosen(2)
Recording:OnQuestTurnedIn(871)
local turnin = lastData()
assert(turnin.event == "turnin" and turnin.quest == 871 and turnin.rewardChoice == 2 and turnin.rewardItem == 4854)
assert(turnin.rewardText == "Take this.")

-- A quest leaving the log right after a turn-in is that turn-in, not an abandon.
before = #rows()
Recording:OnQuestRemoved(871)
assert(#rows() == before, "a quest removed because it was handed in is not an abandon")
Recording:OnQuestRemoved(4021)
assert(lastData().event == "abandon" and lastData().quest == 4021)

-- Loot: the game's own quest-item flag, an item a quest in the log names, and
-- nothing else. A session full of grey drops is a session nobody reads.
world.log[871] = { title = "Plainstrider Menace", objectives = { { text = "Plainstrider Beak: 3/7", have = 3, need = 7 } } }
Recording:ScanObjectives()
before = #rows()
world.loot = {
    { index = 1, itemID = 3164, name = "Plainstrider Beak", count = 1, questItem = false, from = 3244, fromKind = "Creature" },
    { index = 2, itemID = 2589, name = "Linen Cloth", count = 4, questItem = false },
    { index = 3, itemID = 7148, name = "Sealed Note", count = 1, questItem = true },
}
Recording:OnLootOpened()
assert(#rows() == before + 2, "the beak and the flagged item are kept, the cloth is not")
local beak = rows()[before + 1].d
assert(beak.event == "loot" and beak.item == 3164 and beak.quest == 871)
assert(beak.from == 3244 and beak.fromKind == "Creature" and beak.fromName == "Greater Plainstrider")
assert(rows()[before + 2].d.item == 7148 and rows()[before + 2].d.questItem == true)

-- The chat line that follows the same slot is the same pickup.
before = #rows()
Recording:OnChatLoot("You receive loot: |cffffffff|Hitem:3164::::::::1:::::::|h[Plainstrider Beak]|h|r.")
assert(#rows() == before, "the chat line does not double a slot already taken from the window")
clock = clock + 30
Recording:OnChatLoot("You receive loot: |cffffffff|Hitem:3164::::::::1:::::::|h[Plainstrider Beak]|h|r.")
assert(#rows() == before + 1 and lastData().source == "chat", "once the window's memory lapses the chat line stands on its own")
before = #rows()
Recording:OnChatLoot("You receive loot: |cffffffff|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r.")
assert(#rows() == before, "and the same filter applies to it")

-- A craft is the client's own "You create" line, filtered the same way.
_G.LOOT_ITEM_CREATED_SELF = "You create: %s."
world.log[3091] = { title = "Leather", objectives = { { text = "Light Leather: 0/4", have = 0, need = 4 } } }
Recording:ScanObjectives()
clock = clock + 30
Recording:OnChatLoot("You create: |cffffffff|Hitem:2318::::::::1:::::::|h[Light Leather]|h|r.")
assert(lastData().event == "craft" and lastData().item == 2318 and lastData().quest == 3091)

-- A visit to a merchant is told by what the bags and the purse did across it.
world.bags = { { itemID = 4540, name = "Tough Hunk of Bread" } }
world.counts = { [4540] = 5 }
world.money, world.npc, world.npcName = 5000, 3313, "Wharfmaster"
Recording:OnMerchantShow()
world.counts = { [4540] = 10, [3164] = 0 }
world.bags = { { itemID = 4540, name = "Tough Hunk of Bread" } }
world.money = 4500
Recording:OnMerchantClosed()
before = #rows()
Recording:FlushMerchant()
assert(#rows() == before + 1 and lastData().event == "buy" and lastData().item == 4540 and lastData().count == 5)
assert(lastData().npc == 3313)

-- Money gone and nothing carried away is a repair.
world.money = 4500
Recording:OnMerchantShow()
world.money = 4286
Recording:OnMerchantClosed()
Recording:FlushMerchant()
assert(lastData().event == "repair" and lastData().copper == 214)

-- A trainer visit is told by the skill ranks across it.
world.skills = { Skinning = 0 }
world.npc = 3067
Recording:OnTrainerShow()
world.skills = { Skinning = 1 }
Recording:OnTrainerClosed()
Recording:FlushTrainer()
assert(lastData().event == "train" and lastData().skill == "Skinning")
assert(lastData().rankBefore == 0 and lastData().rankAfter == 1 and lastData().npc == 3067)

-- A flight: the taxi map names where it started, the landing names where it
-- ended, and the destination is written back onto the row it belongs to.
world.taxiNode, world.npc, world.npcName = "The Crossroads, The Barrens", 3390, "Devrak"
Recording:OnTaxiMap()
assert(lastData().event == "flightpath" and lastData().node == "The Crossroads, The Barrens")
Recording:OnControlLost()
local flight = last()
assert(flight.d.event == "flight" and flight.d.from == "The Crossroads, The Barrens")
world.subzone, world.onTaxi = "Ratchet", false
Recording:OnControlGained()
assert(flight.d.to == "Ratchet", "the takeoff row is finished rather than left to be paired up")
assert(lastData().event == "flightend" and lastData().node == "Ratchet")

-- Crossing into another zone or subzone is not a row.
world.zone, world.subzone = "Durotar", "Razor Hill"
before = #rows()
Recording:OnControlGained()
assert(#rows() == before, "a zone change writes nothing")

-- A map change on foot is a doorway, written where it happened; one after a
-- loading screen, or while flying, is travel.
Recording:OnMapChanged()
world.map = 1454
Recording:OnMapChanged()
assert(lastData().event == "door" and lastData().from == 1413 and lastData().to == 1454, "walking into a city is a doorway")
before = #rows()
Recording:OnJump()
world.map = 1411
Recording:OnMapChanged()
assert(#rows() == before, "a map change after a loading screen is not a doorway")
clock = clock + 20
world.onTaxi, world.map = true, 1413
Recording:OnMapChanged()
assert(#rows() == before, "nor one on a taxi")
world.onTaxi = false
world.map = nil

-- Talking to the same NPC twice in a breath is one visit.
world.npc, world.npcName = 3390, "Devrak"
clock = clock + 10
before = #rows()
Recording:Talk("taxi")
Recording:Talk("taxi")
assert(#rows() == before + 1, "the same dialog with the same NPC is one row")
clock = clock + 10
Recording:Talk("taxi")
assert(#rows() == before + 2, "a later visit is another")

-- A cast is worth a row when it is the hearthstone or a carried item.
world.spellItem = { [4996] = { 4874, "Rejuvenation Potion" } }
Client.GetBagItemForSpell = function(_, spellID)
    local entry = world.spellItem[spellID]
    if entry then return entry[1], entry[2] end
    return nil
end
before = #rows()
Recording:OnSpellCast("player", "Cast-1", 172)
assert(#rows() == before, "an ordinary spell is not a row")
Recording:OnSpellCast("player", "Cast-2", 4996)
assert(lastData().event == "use" and lastData().item == 4874 and lastData().spell == 4996)
Recording:OnSpellCast("player", "Cast-3", 8690)
assert(lastData().event == "hearth" and lastData().location == "The Crossroads")
before = #rows()
Recording:OnSpellCast("target", "Cast-4", 8690)
assert(#rows() == before, "somebody else's cast is not the player's")
Recording:OnSpellCast("player", "Cast-5", secretValue)
assert(#rows() == before, "and a spell the client hides is no cast at all")

-- The rest of the vocabulary.
Recording:OnTargetDied("Creature-0-1-1-1-3244-0001", 3244, "Greater Plainstrider")
assert(lastData().event == "kill" and lastData().npc == 3244 and lastData().seen == "target")
world.equipped = 4854
Recording:OnEquipmentChanged(16)
assert(lastData().event == "equip" and lastData().item == 4854 and lastData().slot == 16)
Recording:OnLevelUp(14)
assert(lastData().event == "level" and lastData().level == 14)
Recording:OnDeath()
assert(lastData().event == "death")
world.ghost = true
Recording:OnAlive()
assert(lastData().event == "alive" and lastData().ghost == true)
Recording:OnHearthstoneBound()
assert(lastData().event == "hearthset" and lastData().location == "The Crossroads")

-- One row, as a step line would show it, with everything it carries under it.
local function describe(data) return Recording:Describe({ at = 1789862400, d = data }) end
local function line(data) return describe(data).text end
assert(line({ event = "accept", quest = 871 }) == "Accept: Plainstrider Menace")
assert(line({ event = "turnin", quest = 871 }) == "Turn in: Plainstrider Menace")
assert(line({ event = "abandon", quest = 871 }) == "Abandon: Plainstrider Menace")
assert(line({ event = "objective", quest = 871, text = "Plainstrider Beak: 3/7", have = 3, need = 7 }) == "Plainstrider Beak 3/7")
assert(line({ event = "loot", item = 3164, count = 1, from = 3244, fromKind = "Creature" })
    == "Loot: Plainstrider Beak x1 from Greater Plainstrider")
assert(line({ event = "craft", item = 2318, count = 2 }) == "Craft: Light Leather x2")
assert(line({ event = "kill", npc = 3244 }) == "Killed: Greater Plainstrider")
assert(line({ event = "talk", kind = "taxi", npc = 3390 }) == "Talk: Devrak (flight master)")
assert(line({ event = "buy", item = 4540, count = 5 }) == "Buy: Tough Hunk of Bread x5")
assert(line({ event = "sell", item = 3164, count = 1 }) == "Sell: Plainstrider Beak x1")
assert(line({ event = "repair", copper = 214 }) == "Repair: 2s 14c")
assert(line({ event = "train", skill = "Skinning", rankBefore = 0, rankAfter = 1 }) == "Train: Skinning 0 > 1")
assert(line({ event = "train", spell = 5187, name = "Corruption" }) == "Train: Corruption")
assert(line({ event = "flightpath", node = "The Crossroads" }) == "Flight path: The Crossroads")
assert(line({ event = "flight", from = "The Crossroads", to = "Ratchet" }) == "Fly: The Crossroads > Ratchet")
assert(line({ event = "flightend", node = "Ratchet" }) == "Landed: Ratchet")
assert(line({ event = "hearthset", location = "The Crossroads" }) == "Hearth set: The Crossroads")
assert(line({ event = "hearth", location = "The Crossroads" }) == "Hearth: The Crossroads")
assert(line({ event = "use", item = 4874, name = "Rejuvenation Potion" }) == "Use: Rejuvenation Potion")
assert(line({ event = "equip", item = 4854 }) == "Equip: Sturdy Cloth Belt")
assert(line({ event = "level", level = 14 }) == "Level 14")
assert(line({ event = "death" }) == "Died")
assert(line({ event = "alive", ghost = false }) == "Alive")
assert(line({ event = "alive", ghost = true }) == "Released")
assert(line({ event = "recording", on = true }) == "Recording on")
assert(line({ event = "something-new", quest = 871 }) == "something-new: Plainstrider Menace", "an event nobody taught it still reads")

-- A value the client hid reads as the word the recorder put in its place.
assert(line({ event = "hearth", location = "<secret>" }) == "Hearth: <secret>")

local described = describe({ event = "loot", item = 3164, count = 1, quest = 871, map = 1413, at = { 52.2, 31.1 } })
assert(described.kind == "loot" and described.quest == 871 and described.item == 3164)
assert(described.time == "19:00", "the row carries the hour and minute it happened")
local detail = table.concat(described.detail, "\n")
assert(detail:find("map: 1413", 1, true) and detail:find("at: 52.2, 31.1", 1, true), detail)
assert(not detail:find("event:", 1, true), "the event is the kind, not a detail line")
assert(Recording:Describe(nil).kind == "unknown", "a row that is not a row still describes")

-- Turning it off says so before it stops saying anything.
before = #rows()
Recording:SetEnabled(false)
assert(#rows() == before + 1 and rows()[before + 1].d.on == false)
assert(not Recording:Enabled())
Recording:OnLevelUp(15)
assert(#rows() == before + 1, "and nothing after it")

-- At login the log arrives after the addon does, so the snapshot waits for
-- the first scan that finds anything, and the ticks still start silent.
world.log = {}
Recording:SetEnabled(true)
before = #rows()
assert(lastData().event == "recording", "an empty log at start writes no snapshot")
Recording:ScanObjectives()
assert(#rows() == before, "and keeps waiting")
world.log[872] = { title = "Zhevra Runner", objectives = { { text = "Zhevra Runner slain: 2/4", have = 2, need = 4, type = "monster" } } }
Recording:ScanObjectives()
assert(#rows() == before + 1 and lastData().event == "questlog" and lastData().quests[1].quest == 872, "the snapshot is written when the log arrives")
Recording:ScanObjectives()
assert(#rows() == before + 1, "once")
Recording:SetEnabled(false)
before = #rows()

-- Initialize registers rather than assuming any event fires.
ns.db.settings.recording.enabled = false
Recording:Initialize()
local frame = frames[#frames]
assert(frame.events.QUEST_ACCEPTED and frame.events.LOOT_OPENED and frame.events.QUEST_LOG_UPDATE)
assert(frame.events.UNIT_SPELLCAST_SUCCEEDED, "the cast is watched as a unit event, never the combat log")
assert(not frame.events.COMBAT_LOG_EVENT_UNFILTERED, "the combat log is forbidden on this client")
frame.scripts.OnEvent(frame, "PLAYER_LEVEL_UP", 16)
assert(#Recording:Rows() == before, "an event that arrives while recording is off does nothing")

CreateFrame = previousCreateFrame
print("NuuRoad recording tests passed")
