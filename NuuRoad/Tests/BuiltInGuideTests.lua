_G = _G or _ENV
local ns = { modules = {}, builtInGuides = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
-- Load every packaged guide listed in the real addon manifest.
for line in io.lines("NuuRoad.toc") do
    if line:match("^Data/BuiltIn/.*%.lua$") then Load(ns, line) end
end
for _, source in pairs(ns.builtInGuides) do
    local expanded = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.Schema:Validate(expanded)
    assert(valid, source.id .. ": " .. table.concat(problems, "; "))
end

-- A quest objective step whose note says to loot the kills, or what they
-- drop, is a collect step: without `collect = <item>` it reads "Kill
-- Highlands Bandit" and the tracker cannot tell the loot from the kills
-- beside it. A grind step's "loot as you go" is vendor trash, not an item.
local unlooted = {}
for id, source in pairs(ns.builtInGuides) do
    for _, node in ipairs(ns.modules.Steps:Expand(source).nodes) do
        local auto, body = node.auto or {}, (node.body or ""):lower()
        local observed = node.completion and node.completion.observed
        local objective = type(observed) == "table" and observed.type == "objective"
        if objective and auto.kill and not auto.collect and (body:find("loot") or body:find("drop")) then
            table.insert(unlooted, id .. " step " .. node.index .. " (" .. ns.modules.Steps:Title(node) .. ")")
        end
    end
end
assert(#unlooted == 0, "steps that loot their kills name the item with collect: " .. table.concat(unlooted, "; "))

-- The travel test window finds each test guide's steps by label.
local labelled = {
    ["nuuroad:fixture:travel-flight"] = { "crossroads" },
    ["nuuroad:fixture:travel-zeppelin"] = { "brill", "back" },
    ["nuuroad:fixture:travel-hearth"] = { "bind", "away", "home", "far" },
    ["nuuroad:fixture:travel-other-flight"] = { "taurajo" },
    ["nuuroad:fixture:travel-lifts"] = { "down", "up" },
    ["nuuroad:fixture:cave-place"] = { "den", "ledge", "camp" },
}
for id, labels in pairs(labelled) do
    local expanded = ns.modules.Steps:Expand(ns.builtInGuides[id])
    for _, label in ipairs(labels) do
        local found = false
        for _, node in ipairs(expanded.nodes) do if node.label == label then found = true end end
        assert(found, id .. " keeps its step labelled " .. label)
    end
end

local compact = ns.builtInGuides["nuuroad:leveling:horde-barrens-13-21"]
assert(compact, "Horde Barrens guide must register")
local guide = ns.modules.Steps:Expand(compact)
local ok, errors = ns.modules.Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))
assert(#guide.groups == 26, "Barrens has fifteen visit groups and eleven camps of kills and pickups")
assert(#guide.sections == 15, "Horde Barrens guide keeps its fifteen sections, got " .. #guide.sections)
local kinds = {}
for _, node in ipairs(guide.nodes) do kinds[node.kind] = (kinds[node.kind] or 0) + 1 end
assert(kinds.hearth == 3 and kinds.flight == 3, "hearth and flight path steps are observed")
assert(kinds.reminder and kinds.reminder >= 20, "sticky objectives are tracked")
local tracks = ns.modules.Steps:ActiveTracks(guide, guide.nodes[#guide.nodes])
assert(#tracks == 0, "every track is closed by the end: " .. table.concat(tracks, ","))
assert(#guide.nodes > 200, "Horde Barrens guide should carry the full Zygor route, got " .. #guide.nodes)
for _, node in ipairs(guide.nodes) do
    if node.location then
        assert(node.location.x <= 1 and node.location.y <= 1, "percent coordinates normalize: " .. node.index)
        assert(node.location.mapID == 1413 or node.location.mapID == 1454 or node.location.mapID == 1456 or node.location.mapID == 1442 or node.location.mapID == 1450, "known map: " .. node.index)
    end
end
assert(guide.only == "Horde" and guide.condition.type == "faction", "the Barrens guide is Horde-only")
for _, source in pairs(ns.builtInGuides) do
    assert(source.schema == 2, source.id .. " must declare schema 2")
    assert(type(source.updated) == "number", source.id .. " must carry an updated stamp")
    for _, wrapper in ipairs(source.steps) do
        assert(type(wrapper.section) == "string" and type(wrapper.steps) == "table",
            source.id .. ": every top-level entry is a section")
    end
end
for _, node in ipairs(guide.nodes) do
    if node.body then assert(#node.body > 0, "body text is never empty: " .. node.index) end
    assert(#ns.modules.Steps:Title(node) > 0, "every step renders a title: " .. node.index)
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("quest %d") and not title:find("NPC %d") and not title:find("item %d"), "every referenced quest, NPC, and item is named: " .. node.index .. " -> " .. title)
end
assert(guide.nodes[#guide.nodes].kind == "end" and guide.nodes[#guide.nodes].completion.type == "manual")

-- Quest-starting items and quest items are tied to their quest in the port.
local byItem = {}
for _, node in ipairs(guide.nodes) do
    local observed = node.completion and node.completion.observed
    if observed and observed.type == "item" then byItem[observed.itemID] = node end
end
assert(byItem[4926].completion.observed.startsQuestID == 819, "Chen's Empty Keg begins quest 819")
assert(byItem[4986].completion.observed.questID == 924, "the Flawed Power Stone is a quest item for The Demon Seed")

local fixture = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:fixture:quest-items"])
ok, errors = ns.modules.Schema:Validate(fixture)
assert(ok, table.concat(errors, "; "))
assert(fixture.nodes[1].completion.observed.startsQuestID == 819 and fixture.nodes[3].completion.observed.questID == 924)

-- The two ported RestedXP Mulgore guides.
local mulgoreMaps = { [1411] = true, [1412] = true, [1413] = true, [1450] = true, [1456] = true }
for _, id in ipairs({ "nuuroad:leveling:horde-mulgore-1-6", "nuuroad:leveling:horde-mulgore-6-12" }) do
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(source.only == "Horde" and source.map == 1412, id .. " is a Horde guide on the Mulgore map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.Schema:Validate(ported)
    assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    assert(#ported.groups > 0, id .. " keeps the source's shared quest visits as groups")
    for _, node in ipairs(ported.nodes) do
        if node.location then
            assert(node.location.x <= 1 and node.location.y <= 1, id .. ": percent coordinates normalize at " .. node.index)
            assert(mulgoreMaps[node.location.mapID], id .. ": known map at " .. node.index)
        end
        local title = ns.modules.Steps:Title(node)
        assert(#title > 0, id .. ": every step renders a title at " .. node.index)
        assert(not title:find("quest %d") and not title:find("NPC %d") and not title:find("item %d"),
            id .. ": every referenced quest, NPC, and item is named -> " .. title)
        -- The client only answers with an objective line while the quest is in
        -- the log, so a step that names nothing of its own reads as "<quest>,
        -- objective 1" everywhere else: the tracker before the quest is taken,
        -- the editor, and the audit. Every step says what it asks for instead.
        assert(not title:find(", objective %d+$"),
            id .. ": a step must say what it asks for, not a quest and an index -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    local open = ns.modules.Steps:ActiveTracks(ported, ported.nodes[#ported.nodes])
    assert(#open == 0, id .. ": every track is closed by the end: " .. table.concat(open, ","))
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- The ported RestedXP Tirisfal guides: Deathknell, then Brill and the Undercity.
for _, id in ipairs({ "nuuroad:leveling:horde-tirisfal-1-6", "nuuroad:leveling:horde-tirisfal-6-12" }) do
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(source.only == "Horde" and source.map == 1420, id .. " is a Horde guide on the Tirisfal map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.Schema:Validate(ported)
    assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    assert(#ported.groups > 0, id .. " keeps the source's shared quest visits as groups")
    local maps = { [1420] = true, [1458] = true }
    for _, node in ipairs(ported.nodes) do
        if node.location then
            assert(node.location.x <= 1 and node.location.y <= 1, id .. ": percent coordinates normalize at " .. node.index)
            assert(maps[node.location.mapID], id .. ": known map at " .. node.index)
        end
        local title = ns.modules.Steps:Title(node)
        assert(#title > 0, id .. ": every step renders a title at " .. node.index)
        -- Forever's Jorin Croge and Ander Solliden have no known creature IDs, so
        -- their Touring the Grounds lines read as the quest and an index until the
        -- quest is in the log; the objective-index check the Mulgore ports make
        -- would fail on them alone.
        assert(not title:find("quest %d") and not title:find("NPC %d") and not title:find("item %d") and not title:find("spell %d"),
            id .. ": every referenced quest, NPC, item, and spell is named -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    local open = ns.modules.Steps:ActiveTracks(ported, ported.nodes[#ported.nodes])
    assert(#open == 0, id .. ": every track is closed by the end: " .. table.concat(open, ","))
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- The ported RestedXP Skyborne start: one guide for a race that picks either faction.
local skyborneID = "nuuroad:leveling:skyborne-zephras-isle"
local skyborneSource = ns.builtInGuides[skyborneID]
assert(skyborneSource, skyborneID .. " must register")
assert(skyborneSource.only == "Skyborne" and skyborneSource.map == 2521, "the Skyborne guide is for Skyborne, on Zephras Isle")
local skyborne = ns.modules.Steps:Expand(skyborneSource)
assert(skyborne.condition.type == "race" and skyborne.condition.values[1] == "skyborne", "Skyborne is a race term")
local skyborneMaps = { [2521] = true, [1416] = true, [1453] = true, [1412] = true, [1456] = true, [1454] = true }
local factionSteps = { Alliance = 0, Horde = 0 }
local lastMap = nil
for _, node in ipairs(skyborne.nodes) do
    if node.location then
        assert(node.location.x <= 1 and node.location.y <= 1, skyborneID .. ": percent coordinates normalize at " .. node.index)
        assert(skyborneMaps[node.location.mapID], skyborneID .. ": known map at " .. node.index)
        lastMap = node.location.mapID
    end
    local title = ns.modules.Steps:Title(node)
    assert(#title > 0, skyborneID .. ": every step renders a title at " .. node.index)
    assert(not title:find("quest %d") and not title:find("NPC %d") and not title:find("item %d") and not title:find("spell %d"),
        skyborneID .. ": every referenced quest, NPC, item, and spell is named -> " .. title)
    assert(not title:find(", objective %d+$"),
        skyborneID .. ": a step must say what it asks for, not a quest and an index -> " .. title)
end
local function countFactions(steps)
    for _, step in ipairs(steps) do
        if step.steps then countFactions(step.steps) end
        if step.group then countFactions(step.group) end
        for faction in pairs(factionSteps) do
            if type(step.only) == "string" and step.only:find(faction) then factionSteps[faction] = factionSteps[faction] + 1 end
        end
    end
end
countFactions(skyborneSource.steps)
assert(factionSteps.Alliance > 50 and factionSteps.Horde > 20, "both factions' forks of the island are ported")
local skyborneOpen = ns.modules.Steps:ActiveTracks(skyborne, skyborne.nodes[#skyborne.nodes])
assert(#skyborneOpen == 0, skyborneID .. ": every track is closed by the end: " .. table.concat(skyborneOpen, ","))
assert(skyborne.nodes[#skyborne.nodes].kind == "end", skyborneID .. " ends with a closing step")
assert(lastMap == 1454, "the Horde road ends at Thrall in Orgrimmar")
local skyborneQuests = {}
for _, node in ipairs(skyborne.nodes) do
    for _, id in ipairs(node.refs and node.refs.quests or {}) do skyborneQuests[id] = true end
end
assert(skyborneQuests[94946] and skyborneQuests[92644], "the Alliance storyline to Dalaran is ported, so its last turn-in has a quest")

local mulgore16 = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:leveling:horde-mulgore-1-6"])
local starter = nil
for _, node in ipairs(mulgore16.nodes) do
    local observed = node.completion and node.completion.observed
    if observed and observed.type == "item" and observed.itemID == 4851 then starter = node end
end
assert(starter and starter.completion.observed.startsQuestID == 781,
    "the Dirt-stained Map begins Attack on Camp Narache")

local mulgore612 = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:leveling:horde-mulgore-6-12"])
assert(#mulgore612.sections >= 10, "the 6-12 guide keeps the whole route through Thunder Bluff and the Barrens")
local reachedBarrens, reachedThunderBluff = false, false
for _, node in ipairs(mulgore612.nodes) do
    if node.location and node.location.mapID == 1413 then reachedBarrens = true end
    if node.location and node.location.mapID == 1456 then reachedThunderBluff = true end
end
assert(reachedBarrens and reachedThunderBluff, "the 6-12 route leaves Mulgore for Thunder Bluff and the Crossroads")

local wc = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:dungeon:horde-wailing-caverns-quests"])
assert(wc.only == "Horde", "the Wailing Caverns guide is Horde-only")
local wcTurnins, wcSticky = {}, 0
for _, node in ipairs(wc.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("quest %d") and not title:find("NPC %d") and not title:find("item %d"), "Wailing Caverns names everything: " .. title)
    if node.sticky then wcSticky = wcSticky + 1 end
    if node.kind == "turnInQuest" or node.kind == "talk" then
        for _, goal in ipairs(node.completion.observed.children or { node.completion.observed }) do
            if goal.state == "finished" then for _, id in ipairs(goal.ids) do wcTurnins[id] = true end end
        end
    end
    if node.location then
        assert(node.location.mapID == 1413 or node.location.mapID == 1456, "Wailing Caverns stays in the Barrens and Thunder Bluff: " .. node.index)
    end
end
assert(wcSticky == 7, "the seven dungeon objectives ride along inside, got " .. wcSticky)
for _, id in ipairs({ 914, 959, 962, 1486, 1487, 1491, 3369, 6981 }) do
    assert(wcTurnins[id], "the Wailing Caverns guide turns in quest " .. id)
end

local rfc = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:dungeon:horde-ragefire-chasm-quests"])
assert(rfc.only == "Horde", "the Ragefire Chasm guide is Horde-only")
local rfcMaps = { [1411] = true, [1454] = true, [1456] = true, [1458] = true }
local rfcTurnins, rfcSticky = {}, 0
for _, node in ipairs(rfc.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("quest %d") and not title:find("NPC %d") and not title:find("item %d"), "Ragefire Chasm names everything: " .. title)
    if node.sticky then rfcSticky = rfcSticky + 1 end
    if node.kind == "turnInQuest" or node.kind == "talk" then
        for _, goal in ipairs(node.completion.observed.children or { node.completion.observed }) do
            if goal.state == "finished" then for _, id in ipairs(goal.ids) do rfcTurnins[id] = true end end
        end
    end
    if node.location then
        assert(rfcMaps[node.location.mapID], "Ragefire Chasm stays in Orgrimmar, Durotar, Thunder Bluff and the Undercity: " .. node.index)
    end
end
assert(rfcSticky == 4, "the four dungeon objectives ride along inside, got " .. rfcSticky)
for _, id in ipairs({ 5722, 5723, 5724, 5725, 5726, 5727, 5728, 5729, 5730, 5761 }) do
    assert(rfcTurnins[id], "the Ragefire Chasm guide turns in quest " .. id)
end

local rol = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:dungeon:horde-ruins-of-lordaeron-quests"])
assert(rol.only == "Horde", "the Ruins of Lordaeron guide is Horde-only")
local rolTurnins = {}
for _, node in ipairs(rol.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("quest %d") and not title:find("NPC %d") and not title:find("item %d"), "Ruins of Lordaeron names everything: " .. title)
    if node.kind == "turnInQuest" or node.kind == "talk" then
        for _, goal in ipairs(node.completion.observed.children or { node.completion.observed }) do
            if goal.state == "finished" then for _, id in ipairs(goal.ids) do rolTurnins[id] = true end end
        end
    end
    if node.location then
        assert(node.location.mapID == 1458 or node.location.mapID == 1420 or node.location.mapID == 1421,
            "Ruins of Lordaeron points only at recorded Undercity, Brill, and Sepulcher spots: " .. node.index)
    end
end
for _, id in ipairs({ 92401, 92421, 92422, 95216, 97289 }) do
    assert(rolTurnins[id], "the Ruins of Lordaeron guide turns in quest " .. id)
end

local sfk = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:dungeon:horde-shadowfang-keep-quests"])
assert(sfk.only == "Horde", "the Shadowfang Keep guide is Horde-only")
local sfkMaps = { [1413] = true, [1421] = true, [1458] = true }
local sfkTurnins, sfkSticky = {}, 0
for _, node in ipairs(sfk.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("quest %d") and not title:find("NPC %d") and not title:find("item %d"), "Shadowfang Keep names everything: " .. title)
    if node.sticky then sfkSticky = sfkSticky + 1 end
    if node.kind == "turnInQuest" or node.kind == "talk" then
        for _, goal in ipairs(node.completion.observed.children or { node.completion.observed }) do
            if goal.state == "finished" then for _, id in ipairs(goal.ids) do sfkTurnins[id] = true end end
        end
    end
    if node.location then
        assert(sfkMaps[node.location.mapID], "Shadowfang Keep stays in Silverpine, the Undercity and the Barrens: " .. node.index)
    end
end
assert(sfkSticky == 1, "the Large Soran'ruk Fragment rides along inside, got " .. sfkSticky)
for _, id in ipairs({ 1013, 1014, 1098, 1740 }) do
    assert(sfkTurnins[id], "the Shadowfang Keep guide turns in quest " .. id)
end

-- Horde Druid Cat Form: Forever-only, recorded in play; Druid and not Alliance.
local cat = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:class:horde-druid-cat-form"])
assert(cat.condition.type == "all", "the Cat Form guide needs both the class and the faction")
for _, node in ipairs(cat.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("quest %d") and not title:find("NPC %d"), "Cat Form names everything: " .. title)
    if node.location then
        assert(node.location.mapID == 1456 or node.location.mapID == 1450, "Cat Form stays in Thunder Bluff and Moonglade: " .. node.index)
    end
end

return true
