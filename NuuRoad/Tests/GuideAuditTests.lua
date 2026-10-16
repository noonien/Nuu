_G = _G or _ENV
local ns = { modules = {}, db = { settings = { debug = true } } }
function ns:RegisterModule(name, module) self.modules[name] = module end
local printed = {}
function ns:Print(message) table.insert(printed, message) end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
Load(ns, "Data/GuideCheck.lua")
Load(ns, "Data/Names.lua")
AddBuiltInNames(ns)
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/GuideAudit.lua")
local Client, Names, Steps, GuideAudit = ns.modules.Client, ns.modules.Names, ns.modules.Steps, ns.modules.GuideAudit

local function last() return printed[#printed] end
local function count() return #printed end

-- The authored snapshot survives live corrections.
assert(Names.authored.quests[870] == "The Forgotten Pools" and Names.authored.npcs[3448] == "Tonga Runetotem" and Names.authored.items[5087] == "Plainstrider Beak")

-- A live name that agrees is silent; one that differs is reported once, naming the guide's own ID for that name.
assert(not GuideAudit:Compare("quests", 870, "The Forgotten Pools"))
assert(count() == 0)
assert(GuideAudit:Compare("quests", 870, "The Zhevra"))
assert(last():find("quest 870 is 'The Zhevra' on this client, but the guide expects 'The Forgotten Pools'", 1, true), last())
assert(last():find("the guide uses 'The Zhevra' for quest 845", 1, true), last())
assert(not GuideAudit:Compare("quests", 870, "The Zhevra"), "each finding prints once")
assert(count() == 1)
assert(not GuideAudit:Compare("quests", 999999, "Anything"), "IDs the guide never names are not judged")

-- A live ID unknown to the guide but carrying a guide name reveals the right ID.
assert(GuideAudit:NoticeLive("npcs", 99999, "Tonga Runetotem", "your target"))
assert(last() == "|cffffb347[audit]|r guide expects NPC 3448 for 'Tonga Runetotem', but your target 'Tonga Runetotem' is NPC 99999.", last())
assert(not GuideAudit:NoticeLive("npcs", 3448, "Tonga Runetotem", "your target"), "a matching ID and name is silent")
assert(not GuideAudit:NoticeLive("npcs", 42, "Nobody the guide knows", "your target"))
assert(GuideAudit:NoticeLive("npcs", 3448, "Sergra Darkthorn", "your target"), "a known ID with another guide name is a mismatch")
assert(last():find("NPC 3448 is 'Sergra Darkthorn' on this client, but the guide expects 'Tonga Runetotem' (the guide uses 'Sergra Darkthorn' for NPC 3338)", 1, true), last())

-- Names feeds live lookups into the audit before overwriting its table.
C_QuestLog = { GetTitleForQuestID = function(id) return id == 845 and "Plainstrider Menace" or nil end }
assert(Names:Quest(845) == "Plainstrider Menace")
assert(last():find("quest 845 is 'Plainstrider Menace' on this client, but the guide expects 'The Zhevra' (the guide uses 'Plainstrider Menace' for quest 844)", 1, true), last())
assert(Names.authored.quests[845] == "The Zhevra", "the authored name is kept for later reports")

-- Client helpers: GUID parsing, quest log, and bags.
UnitGUID = function(unit) return unit == "target" and "Creature-0-4170-1413-11-3448-00001ABCDE" or (unit == "player" and "Player-1-0000ABCD") or nil end
UnitName = function(unit) return unit == "target" and "Tonga Runetotem" or "Me" end
assert(Client:GetUnitCreatureID("target") == 3448)
assert(Client:GetUnitCreatureID("player") == nil and Client:GetUnitCreatureID("focus") == nil)
assert(not GuideAudit:CheckUnit("target", "your target"), "the expected creature is silent")
C_QuestLog.GetNumQuestLogEntries = function() return 3 end
C_QuestLog.GetInfo = function(index)
    return ({ { title = "The Barrens", isHeader = true }, { title = "Fungal Spores", questID = 848 }, { title = "Raptor Thieves", questID = 77777 } })[index]
end
local entries = Client:GetQuestLogEntries()
assert(#entries == 2 and entries[1].questID == 848 and entries[2].title == "Raptor Thieves")
local before = count()
GuideAudit:ScanQuestLog()
assert(count() == before + 1 and last():find("guide expects quest 869 for 'Raptor Thieves', but the quest in your log 'Raptor Thieves' is quest 77777", 1, true), last())
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
    GetContainerItemInfo = function(_, slot)
        return ({ { itemID = 5087, hyperlink = "|cffffffff|Hitem:5087::::::::15:::::|h[Plainstrider Beak]|h|r" }, { itemID = 66666, hyperlink = "|cffffffff|Hitem:66666::::::::15:::::|h[Zhevra Hooves]|h|r" } })[slot]
    end,
}
local items = Client:GetBagItems()
assert(#items == 2 and items[1].name == "Plainstrider Beak" and items[2].itemID == 66666)
before = count()
GuideAudit:ScanBags()
assert(count() == before + 1 and last():find("guide expects item 5086 for 'Zhevra Hooves', but the item in your bags 'Zhevra Hooves' is item 66666", 1, true), last())

-- Node IDs are gathered from completion rules, refs, and auto titles, and audited against live names.
local guide = Steps:Expand({ kind = "guide", id = "test:audit", updated = 1789862400, title = "Audit", category = "test",
    data = { map = 1413, sections = { { title = "Steps", steps = {
        { type = "talk", turnin = { 871 }, accept = { 872, 5041 }, npc = { 3429 }, at = { { 5150, 3087 } } },
        { type = "collect", item = 5087, count = 7, kill = { 3244, 3246 }, quest = { 844, 1 }, at = { { 5300, 2240 } } },
    } } } } })
local ids = GuideAudit:NodeIDs(guide.nodes[1])
assert(#ids.quests == 3 and ids.quests[1] == 871 and ids.quests[3] == 5041 and ids.npcs[1] == 3429 and #ids.items == 0)
ids = GuideAudit:NodeIDs(guide.nodes[2])
assert(#ids.quests == 1 and ids.items[1] == 5087 and #ids.npcs == 2 and ids.npcs[2] == 3246)
C_Item = { GetItemNameByID = function(id) return id == 5087 and "Plainstrider Feather" or nil end }
before = count()
GuideAudit:AuditNode(guide.nodes[2])
assert(count() == before + 1 and last():find("item 5087 is 'Plainstrider Feather' on this client, but the guide expects 'Plainstrider Beak'", 1, true), last())

-- Quest dialogs: an unexpected title is reported against the current step.
local Progress = { store = {} }
function Progress:GetActiveGuide() return guide end
function Progress:GetCurrentNode() return guide.nodes[1] end
ns.modules.Progress = Progress
GetTitleText = function() return "Disrupt the Attacks" end
before = count()
GuideAudit:CheckQuestDialog()
assert(count() == before, "a title the step expects is silent")
GetTitleText = function() return "Samophlange" end
GuideAudit:CheckQuestDialog()
assert(last():find("the quest dialog shows 'Samophlange', but step 'Turn in Disrupt the Attacks, accept The Disruption Ends and Supplies for the Crossroads' expects quest 871", 1, true), last())
GuideAudit:CheckQuestEvent(55555)
assert(last():find("guide expects quest 894/900/901/902 for 'Samophlange', but the quest you just handled 'Samophlange' is quest 55555", 1, true), last())

-- Quest givers: the step's quest handled by an NPC the step does not name.
UnitGUID = function(unit) return unit == "npc" and "Creature-0-4170-1413-11-3390-00001ABCDE" or nil end
UnitName = function(unit) return unit == "npc" and "Apothecary Helbrim" or nil end
GetTitleText = function() return "Disrupt the Attacks" end
before = count()
GuideAudit:CheckQuestDialog()
assert(count() == before + 1, "the giver mismatch is reported")
assert(last():find("quest 871 'Disrupt the Attacks' is handled by NPC 3390 'Apothecary Helbrim', but step 'Turn in Disrupt the Attacks, accept The Disruption Ends and Supplies for the Crossroads' says NPC 3429 'Thork'", 1, true), last())
GuideAudit:CheckQuestEvent(871)
assert(count() == before + 1, "the same finding from the accept event is not repeated")
GuideAudit:CheckQuestEvent(872)
assert(last():find("quest 872 'The Disruption Ends' is handled by NPC 3390", 1, true), last())
UnitGUID = function(unit) return unit == "npc" and "Creature-0-4170-1413-11-3429-00001ABCDE" or nil end
UnitName = function(unit) return unit == "npc" and "Thork" or nil end
GetTitleText = function() return "Supplies for the Crossroads" end
before = count()
GuideAudit:CheckQuestDialog()
GuideAudit:CheckQuestEvent(5041)
assert(count() == before, "the named giver is silent")
GetTitleText = function() return "Fungal Spores" end
GuideAudit:CheckQuestDialog()
assert(last():find("the quest dialog shows 'Fungal Spores'", 1, true), last())
before = count()
GuideAudit:CheckQuestEvent(848)
assert(count() == before, "quests the step does not expect are not matched against its giver")

-- Objective steps: the quest line must be about the step's target, with the same count.
local objectiveNode = guide.nodes[2]
assert(objectiveNode.completion.observed.type == "objective" and objectiveNode.auto.count == 7)
C_Item.GetItemNameByID = function() return nil end
C_QuestLog.GetQuestObjectives = function(id)
    return id == 844 and { { text = "Plainstrider Beak: 2/7", finished = false }, { text = "Zhevra Hooves: 0/4", finished = false } } or nil
end
before = count()
assert(not GuideAudit:CheckObjective(objectiveNode), "a matching objective line is silent")
assert(count() == before)
C_QuestLog.GetQuestObjectives = function(id)
    return id == 844 and { { text = "Plainstrider Beak: 2/9", finished = false } } or nil
end
assert(GuideAudit:CheckObjective(objectiveNode))
assert(last():find("objective 1 of quest 844 'Plainstrider Menace' needs 9 ('Plainstrider Beak: 2/9'), but step 'Collect 7 Plainstrider Beak from Greater Plainstrider and Fleeting Plainstrider' says 7", 1, true), last())
C_QuestLog.GetQuestObjectives = function(id)
    return id == 844 and { { text = "Zhevra Hooves: 0/4", finished = false }, { text = "Plainstrider Beak: 0/7", finished = false } } or nil
end
assert(GuideAudit:CheckObjective(objectiveNode))
assert(last():find("objective 1 of quest 844 'Plainstrider Menace' reads 'Zhevra Hooves: 0/4', but step 'Collect 7 Plainstrider Beak from Greater Plainstrider and Fleeting Plainstrider' is about 'Greater Plainstrider', 'Fleeting Plainstrider', 'Plainstrider Beak' (that is objective 2)", 1, true), last())
C_QuestLog.GetQuestObjectives = function(id) return id == 844 and { { text = "Plainstrider Beak: 0/7", finished = false } } or nil end
local partThree = Steps:Expand({ kind = "guide", id = "test:part", updated = 1789862400, title = "Part", category = "test",
    data = { map = 1413, sections = { { title = "Steps", steps = {
        { type = "kill", kill = { 3244 }, quest = { 844, 3 }, at = { { 5300, 2240 } } },
    } } } } }).nodes[1]
assert(GuideAudit:CheckObjective(partThree))
assert(last():find("is about objective 3 of quest 844 'Plainstrider Menace', which has only 1 objectives", 1, true), last())

-- A line the client calls an item, on a step that only names kills. The
-- step names no count, so its title takes the objective's 7.
local killOnly = Steps:Expand({ kind = "guide", id = "test:loot", updated = 1789862400, title = "Loot", category = "test",
    data = { map = 1413, sections = { { title = "Steps", steps = {
        { type = "kill", kill = { 3244 }, quest = { 844, 1 }, at = { { 5300, 2240 } } },
    } } } } }).nodes[1]
C_QuestLog.GetQuestObjectives = function(id)
    return id == 844 and { { text = "Plainstrider Beak: 0/7", finished = false, type = "item" } } or nil
end
assert(GuideAudit:CheckObjective(killOnly), "a kill step for an item line is reported")
assert(last():find("is an item to loot ('Plainstrider Beak: 0/7'), but step 'Kill 7 Greater Plainstrider' names no collect item", 1, true), last())
before = count()
assert(not GuideAudit:CheckObjective(objectiveNode), "a collect step for an item line is silent")
assert(count() == before)
C_QuestLog.GetQuestObjectives = function(id) return id == 844 and { { text = "Plainstrider Beak: 0/7", finished = false } } or nil end

-- A world object is named for itself, not for the objective it serves.
local objectNode = Steps:Expand({ kind = "guide", id = "test:object", updated = 1789862400, title = "Object", category = "test",
    data = { map = 1413, sections = { { title = "Steps", steps = {
        { type = "interact", object = "The Altar of Fire", quest = { 924, 1 }, at = { { 4796, 1907 } } },
    } } } } }).nodes[1]
C_QuestLog.GetQuestObjectives = function(id) return id == 924 and { { text = "0/1 Destroy the Demon Seed", finished = false } } or nil end
before = count()
assert(not GuideAudit:CheckObjective(objectNode), "an object whose name the objective does not use is silent")
assert(count() == before)
C_QuestLog.GetQuestObjectives = function(id)
    return id == 924 and { { text = "0/1 Destroy the Demon Seed", finished = false }, { text = "0/1 Douse The Altar of Fire", finished = false } } or nil
end
assert(GuideAudit:CheckObjective(objectNode), "an object named by another line accuses the step")
assert(last():find("is about 'The Altar of Fire' (that is objective 2)", 1, true), last())
C_QuestLog.GetQuestObjectives = function(id) return id == 844 and { { text = "Plainstrider Beak: 0/7", finished = false } } or nil end

-- Positions: a quest handled, or progress made, far from the step's coordinates or on another map.
local acceptNode = guide.nodes[1]
C_Map = { GetBestMapForUnit = function() return 1413 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.515, 0.309 end } end }
before = count()
assert(not GuideAudit:CheckPosition(acceptNode, "quest 871 handled"), "standing at the step is silent")
assert(count() == before)
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.62, 0.36 end } end
assert(GuideAudit:CheckPosition(acceptNode, "quest 871 'Disrupt the Attacks' handled"))
assert(last():find("quest 871 'Disrupt the Attacks' handled at 62.0, 36.0, but step 'Turn in Disrupt the Attacks, accept The Disruption Ends and Supplies for the Crossroads' points to 51.5, 30.9 (12% of the map away)", 1, true), last())
C_Map.GetBestMapForUnit = function() return 1454 end
assert(GuideAudit:CheckPosition(acceptNode, "quest 872 handled"))
assert(last():find("quest 872 handled on map 1454, but step 'Turn in Disrupt the Attacks, accept The Disruption Ends and Supplies for the Crossroads' is on map 1413", 1, true), last())
C_Map.GetBestMapForUnit = function() return 1413 end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.80, 0.60 end } end
GuideAudit:CheckProgressPosition(objectiveNode)
before = count()
GuideAudit:CheckProgressPosition(objectiveNode)
assert(count() == before, "unchanged progress is silent")
C_QuestLog.GetQuestObjectives = function(id) return id == 844 and { { text = "Plainstrider Beak: 1/7", finished = false } } or nil end
GuideAudit:CheckProgressPosition(objectiveNode)
assert(last():find("progress 'Plainstrider Beak: 1/7' at 80.0, 60.0, but step 'Collect 7 Plainstrider Beak from Greater Plainstrider and Fleeting Plainstrider' points to 53.0, 22.4", 1, true), last())

-- Hearth and flight path names.
local hearthGuide = Steps:Expand({ kind = "guide", id = "test:hearth", updated = 1789862400, title = "Hearth", category = "test",
    data = { map = 1413, sections = { { title = "Steps", steps = {
        { type = "hearth", area = 380, npc = { 3934 }, at = { { 5199, 2990 } } },
        { type = "flight", node = 80, npc = { 16227 }, at = { { 6309, 3716 } } },
    } } } } })
local current = hearthGuide.nodes[1]
function Progress:GetActiveGuide() return hearthGuide end
function Progress:GetCurrentNode() return current end
GetBindLocation = function() return "The Crossroads" end
before = count()
GuideAudit:CheckHearth()
assert(count() == before, "the expected bind location is silent")
GetBindLocation = function() return "Ratchet" end
GuideAudit:CheckHearth()
assert(last():find("hearthstone bound at 'Ratchet', but step 'Set your hearthstone at The Crossroads' says 'The Crossroads'", 1, true), last())
current = hearthGuide.nodes[2]
NumTaxiNodes = function() return 2 end
TaxiNodeGetType = function(index) return index == 1 and "CURRENT" or "REACHABLE" end
TaxiNodeName = function(index) return index == 1 and "Ratchet, The Barrens" or "Orgrimmar, Durotar" end
assert(Client:GetCurrentTaxiNodeName() == "Ratchet, The Barrens")
before = count()
GuideAudit:CheckFlightMaster()
assert(count() == before, "the expected flight master is silent")
TaxiNodeName = function(index) return index == 1 and "The Crossroads, The Barrens" or "Orgrimmar, Durotar" end
GuideAudit:CheckFlightMaster()
assert(last():find("the flight master here is 'The Crossroads, The Barrens', but step 'Learn the Ratchet, The Barrens flight path' says 'Ratchet, The Barrens'", 1, true), last())
function Progress:GetActiveGuide() return guide end
function Progress:GetCurrentNode() return guide.nodes[1] end

-- Every reported finding is kept once in SavedVariables and exported as plain text.
local findings = GuideAudit:Findings()
assert(#findings > 0 and findings[1].text:find("quest 870 is 'The Zhevra'", 1, true), findings[1].text)
local recorded55555
for _, finding in ipairs(findings) do if finding.text:find("quest 55555", 1, true) then recorded55555 = finding end end
assert(recorded55555 and recorded55555.guideTitle == "Audit", "findings carry the active guide")
local seenTexts = {}
for _, finding in ipairs(findings) do assert(not seenTexts[finding.text], "findings are unique"); seenTexts[finding.text] = true end
ns.version = "9.9.9-test"
Client.build = { version = "1.15.8", build = "60000", date = "Sep 1 2026", toc = 11508 }
local export = GuideAudit:ExportText()
local exportLines = {}
for line in (export .. "\n"):gmatch("(.-)\n") do table.insert(exportLines, line) end
assert(exportLines[1]:find("^NuuRoad 9.9.9%-test | client 1.15.8 %(60000, Sep 1 2026, toc 11508%) | exported "), exportLines[1])
assert(recorded55555.step == guide.nodes[1].index and recorded55555.guideID == "test:audit" and recorded55555.guideUpdated == 1789862400, "findings carry guide, revision, and step")
local guideHeaders, characterHeaders, findingLines = 0, 0, 0
for index = 2, #exportLines do
    local line = exportLines[index]
    if line:find("^Guide: ") or line == "No active guide" then guideHeaders = guideHeaders + 1
    elseif line:find("^  %S") then characterHeaders = characterHeaders + 1
    elseif line:find("^    ") then findingLines = findingLines + 1
    else error("unexpected export line: " .. line) end
end
assert(guideHeaders == 3, "findings without a guide, with the test guide, and with the hearth guide form three groups, got " .. guideHeaders)
assert(characterHeaders >= 2 and findingLines == #findings, "a character group under each guide and one line per finding")
assert(export:find("Guide: Audit (test:audit, updated 1789862400)\n  ", 1, true), export)
assert(export:find("@" .. guide.nodes[1].index .. "  guide expects quest 894/900/901/902", 1, true), export)
GuideAudit:ClearFindings()
assert(#GuideAudit:Findings() == 0 and GuideAudit:ExportText():find("No findings", 1, true))

-- Passive checks stay quiet with the debug log off; the on-demand audit does not.
ns.db.settings.debug = false
before = count()
assert(not GuideAudit:Compare("quests", 870, "Something Else"))
assert(count() == before)
C_QuestLog.RequestLoadQuestByID = function() return nil end
GuideAudit:AuditGuide(guide)
for _, line in ipairs(printed) do assert(not line:find("quest 5041 is", 1, true), "unknown titles are not mismatches") end
assert(printed[#printed - 1]:find("Audited 'Audit': 4 quests, 1 items, 3 NPCs. 0 mismatched, 4 requested from the server, 1 unanswerable", 1, true), printed[#printed - 1])
assert(last():find("Server answers follow", 1, true), last())
assert(GuideAudit.pending.quests[871] and GuideAudit.pending.quests[872] and GuideAudit.pending.quests[5041] and GuideAudit.pending.quests[844])
GuideAudit:OnDataLoaded("quests", 871, false)
assert(last():find("quest 871 'Disrupt the Attacks' does not exist on this client", 1, true), last())
C_QuestLog.GetTitleForQuestID = function(id) return id == 872 and "The Disruption Ends" or nil end
before = count()
GuideAudit:OnDataLoaded("quests", 872, true)
assert(count() == before, "a matching answer is silent")
GuideAudit:OnDataLoaded("quests", 5041, true)
assert(not last():find("Audit finished", 1, true), "one answer is still outstanding")
GuideAudit:OnDataLoaded("quests", 844, true)
assert(last():find("Audit finished", 1, true), last())

return true
