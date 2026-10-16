_G = _G or _ENV
local ns = { modules = {}, builtInGuides = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Data/GuideCheck.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
-- Every packaged guide listed in the real addon manifest, as the guide
-- source its file holds, and the development fixtures.
LoadBuiltIns(ns)

-- The guide's own condition, holding one key: as the guide writes it
-- (`cond = { faction = "Horde" }`), or as the expanded guide keeps it (one
-- predicate).
local function onlyFor(guide, kind, value)
    if guide.kind == "guide" then
        local cond = guide.cond
        if type(cond) ~= "table" then return false end
        local held = cond[kind]
        if type(held) == "table" then held = held[1] end
        local keys = 0
        for _ in pairs(cond) do keys = keys + 1 end
        return keys == 1 and held == value
    end
    local condition = guide.condition
    return type(condition) == "table" and condition.type == kind and condition.values ~= nil and condition.values[1] == value
end
for _, source in pairs(ns.builtInGuides) do
    local expanded = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.GuideCheck:Validate(expanded)
    assert(valid, source.id .. ": " .. table.concat(problems, "; "))
end

-- Each guide names every NPC it shows, on its own: loaded alone, no step,
-- goal line or reference falls back to "NPC 1234". Quests, items, spells and
-- factions are the client's to name.
local unnamed = {}
for id, source in pairs(ns.builtInGuides) do
    -- The IDs the client cannot be asked about (areas, skills, flight
    -- points) are named from Data/IDNames.lua, which the addon loads before
    -- any guide.
    local alone = { modules = {}, Kit = ns.Kit, idNames = ns.idNames }
    function alone:RegisterModule(name, module) self.modules[name] = module end
    Load(alone, "Data/GuideCheck.lua")
    Load(alone, "Data/Names.lua")
    Load(alone, "Data/Steps.lua")
    local Steps, Names = alone.modules.Steps, alone.modules.Names
    local function check(text)
        local raw = type(text) == "string" and text:match("NPC %d+")
        if raw then table.insert(unnamed, id .. ": " .. raw) end
    end
    for _, node in ipairs(Steps:Expand(source).nodes) do
        check(Steps:Title(node))
        for _, goal in ipairs(Steps:Goals(node) or {}) do
            for _, part in ipairs(goal.parts or {}) do check(part.text) end
        end
        local refs = node.refs or {}
        for _, npc in ipairs(refs.npcs or {}) do check(Names:DescribeNPC(npc)) end
    end
end
table.sort(unnamed)
assert(#unnamed == 0, "every NPC a guide shows is in its npcs: " .. table.concat(unnamed, "; "))

-- NPC names are shared once the guides load, so two guides that name one
-- NPC must agree.
local named, disagree = {}, {}
for id, source in pairs(ns.builtInGuides) do
    for _, byID in pairs(source.data and source.data.npcs or {}) do
        for key, name in pairs(byID) do
            if type(name) == "table" then name = name.name end
            local other = named[key]
            if other and other.name ~= name then
                table.insert(disagree, string.format("npc %d: '%s' (%s) and '%s' (%s)", key, name, id, other.name, other.guide))
            end
            named[key] = other or { name = name, guide = id }
        end
    end
end
assert(#disagree == 0, "guides agree on names: " .. table.concat(disagree, "; "))

-- A visit goes where its NPC stands (data.npcs), so a step repeats that
-- point only when the NPC really is elsewhere for it. Points are hundredths
-- of a map percent, so a quarter of a percent is 25.
local repeated = {}
for id, source in pairs(ns.builtInGuides) do
    local npcs = source.data and source.data.npcs or {}
    local function stands(npc)
        for map, byID in pairs(npcs) do
            local entry = byID[npc]
            if type(entry) == "table" and type(entry.at) == "table" then return entry.at, map end
        end
    end
    local function walk(steps, map)
        for _, step in ipairs(steps) do
            if step.group then walk(step.group, map)
            else
                local visited = type(step.npc) == "table" and step.npc[1] or step.npc
                local at, npcMap
                if visited then at, npcMap = stands(visited) end
                local here = type(step.at) == "table" and step.at[1]
                -- An NPC that moves about lists several points; a visit goes
                -- to the first, so a step may name one of the others.
                local spot = type(at) == "table" and (type(at[1]) == "table" and at[1] or at)
                if spot and type(here) == "table" and type(here[1]) == "number"
                    and (here.map or map) == (spot.map or npcMap)
                    and math.abs(here[1] - spot[1]) <= 25 and math.abs(here[2] - spot[2]) <= 25 then
                    table.insert(repeated, id .. ": npc " .. visited)
                end
            end
        end
    end
    for _, section in ipairs(source.data.sections or {}) do walk(section.steps, section.map or source.data.map) end
end
assert(#repeated == 0, "steps that repeat their NPC's point: " .. table.concat(repeated, "; "))

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
local ok, errors = ns.modules.GuideCheck:Validate(guide)
assert(ok, table.concat(errors, "; "))
assert(#guide.groups == 26, "Barrens has fifteen visit groups and eleven camps of kills and pickups")
assert(#guide.sections == 15, "Horde Barrens guide keeps its fifteen sections, got " .. #guide.sections)
local kinds = {}
for _, node in ipairs(guide.nodes) do kinds[node.kind] = (kinds[node.kind] or 0) + 1 end
assert(kinds.hearth == 3 and kinds.flight == 3, "hearth and flight path steps are observed")
local carried = 0
for _, node in ipairs(guide.nodes) do
    if node.carriedFrom then
        carried = carried + 1
        assert(node.carriedFrom < node.index, "a step is carried from an earlier one: " .. node.index)
    end
end
assert(carried >= 10, "background work is carried from where it starts, got " .. carried)
assert(#guide.nodes > 200, "Horde Barrens guide should carry the full Zygor route, got " .. #guide.nodes)
for _, node in ipairs(guide.nodes) do
    if node.location then
        assert(node.location.x <= 1 and node.location.y <= 1, "percent coordinates normalize: " .. node.index)
        assert(node.location.mapID == 1413 or node.location.mapID == 1454 or node.location.mapID == 1456 or node.location.mapID == 1442 or node.location.mapID == 1450, "known map: " .. node.index)
    end
end
assert(onlyFor(compact, "faction", "Horde") and guide.condition.type == "faction", "the Barrens guide is Horde-only")
for _, source in pairs(ns.builtInGuides) do
    assert(source.kind == "guide", source.id .. " must be a guide source")
    assert(type(source.updated) == "number", source.id .. " must carry an updated stamp")
    assert(type(source.data) == "table" and type(source.data.sections) == "table", source.id .. " must hold its sections in data")
    for _, section in ipairs(source.data.sections) do
        assert(type(section.title) == "string" and type(section.steps) == "table",
            source.id .. ": every section has a title and steps")
    end
end
for _, node in ipairs(guide.nodes) do
    if node.body then assert(#node.body > 0, "body text is never empty: " .. node.index) end
    assert(#ns.modules.Steps:Title(node) > 0, "every step renders a title: " .. node.index)
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "every NPC is named: " .. node.index .. " -> " .. title)
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
ok, errors = ns.modules.GuideCheck:Validate(fixture)
assert(ok, table.concat(errors, "; "))
assert(fixture.nodes[1].completion.observed.startsQuestID == 819 and fixture.nodes[3].completion.observed.questID == 924)

-- The two ported RestedXP Mulgore guides.
local mulgoreMaps = { [1411] = true, [1412] = true, [1413] = true, [1450] = true, [1456] = true }
for _, id in ipairs({ "nuuroad:leveling:horde-mulgore-1-6", "nuuroad:leveling:horde-mulgore-6-12" }) do
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(onlyFor(source, "faction", "Horde") and source.data.map == 1412, id .. " is a Horde guide on the Mulgore map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.GuideCheck:Validate(ported)
    assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    assert(#ported.groups > 0, id .. " keeps the source's shared quest visits as groups")
    for _, node in ipairs(ported.nodes) do
        if node.location then
            assert(node.location.x <= 1 and node.location.y <= 1, id .. ": percent coordinates normalize at " .. node.index)
            assert(mulgoreMaps[node.location.mapID], id .. ": known map at " .. node.index)
        end
        local title = ns.modules.Steps:Title(node)
        assert(#title > 0, id .. ": every step renders a title at " .. node.index)
        assert(not title:find("NPC %d"),
            id .. ": every NPC is named -> " .. title)
        -- The client only answers with an objective line while the quest is in
        -- the log, so a step that names nothing of its own reads as "<quest>,
        -- objective 1" everywhere else: the tracker before the quest is taken,
        -- the editor, and the audit. Every step says what it asks for instead.
        assert(not title:find(", objective %d+$"),
            id .. ": a step must say what it asks for, not a quest and an index -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- The ported RestedXP Tirisfal guides: Deathknell, then Brill and the Undercity.
for _, id in ipairs({ "nuuroad:leveling:horde-tirisfal-1-6", "nuuroad:leveling:horde-tirisfal-6-12" }) do
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(onlyFor(source, "faction", "Horde") and source.data.map == 1420, id .. " is a Horde guide on the Tirisfal map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.GuideCheck:Validate(ported)
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
        assert(not title:find("NPC %d"),
            id .. ": every NPC is named -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- The ported RestedXP Silverpine Forest guide, from the Tirisfal border to Far Watch Post.
do
    local id = "nuuroad:leveling:horde-silverpine-12-14"
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(onlyFor(source, "faction", "Horde") and source.data.map == 1421, id .. " is a Horde guide on the Silverpine map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.GuideCheck:Validate(ported)
    assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    assert(#ported.groups > 0, id .. " keeps the source's shared quest visits as groups")
    local maps = { [1421] = true, [1458] = true, [1420] = true, [1411] = true, [1413] = true }
    for _, node in ipairs(ported.nodes) do
        if node.location then
            assert(node.location.x <= 1 and node.location.y <= 1, id .. ": percent coordinates normalize at " .. node.index)
            assert(maps[node.location.mapID], id .. ": known map at " .. node.index)
        end
        local title = ns.modules.Steps:Title(node)
        assert(#title > 0, id .. ": every step renders a title at " .. node.index)
        assert(not title:find("NPC %d"),
            id .. ": every NPC is named -> " .. title)
        assert(not title:find(", objective %d+$"),
            id .. ": a step must say what it asks for, not a quest and an index -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- The ported RestedXP Hillsbrad Foothills guide, from the Orgrimmar zeppelin to the Hillsbrad farms.
do
    local id = "nuuroad:leveling:horde-hillsbrad-22-24"
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(onlyFor(source, "faction", "Horde") and source.data.map == 1424, id .. " is a Horde guide on the Hillsbrad map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.GuideCheck:Validate(ported)
    assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    assert(#ported.groups > 0, id .. " keeps the source's shared quest visits as groups")
    local maps = { [1424] = true, [1421] = true, [1420] = true, [1411] = true }
    for _, node in ipairs(ported.nodes) do
        if node.location then
            assert(node.location.x <= 1 and node.location.y <= 1, id .. ": percent coordinates normalize at " .. node.index)
            assert(maps[node.location.mapID], id .. ": known map at " .. node.index)
        end
        local title = ns.modules.Steps:Title(node)
        assert(#title > 0, id .. ": every step renders a title at " .. node.index)
        assert(not title:find("NPC %d"),
            id .. ": every NPC is named -> " .. title)
        assert(not title:find(", objective %d+$"),
            id .. ": a step must say what it asks for, not a quest and an index -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- The ported RestedXP southern Barrens guide, from Thunder Bluff through Bael Modan to the Crossroads.
do
    local id = "nuuroad:leveling:horde-southern-barrens-24-25"
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(onlyFor(source, "faction", "Horde") and source.data.map == 1413, id .. " is a Horde guide on the Barrens map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.GuideCheck:Validate(ported)
    assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    assert(#ported.groups > 0, id .. " keeps the source's shared quest visits as groups")
    local maps = { [1413] = true, [1456] = true }
    for _, node in ipairs(ported.nodes) do
        if node.location then
            assert(node.location.x <= 1 and node.location.y <= 1, id .. ": percent coordinates normalize at " .. node.index)
            assert(maps[node.location.mapID], id .. ": known map at " .. node.index)
        end
        local title = ns.modules.Steps:Title(node)
        assert(#title > 0, id .. ": every step renders a title at " .. node.index)
        assert(not title:find("NPC %d"),
            id .. ": every NPC is named -> " .. title)
        assert(not title:find(", objective %d+$"),
            id .. ": a step must say what it asks for, not a quest and an index -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- The ported RestedXP Stonetalon Mountains guide, from the Crossroads to Sun Rock Retreat.
do
    local id = "nuuroad:leveling:horde-stonetalon-25-26"
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(onlyFor(source, "faction", "Horde") and source.data.map == 1442, id .. " is a Horde guide on the Stonetalon map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.GuideCheck:Validate(ported)
    assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    assert(#ported.groups > 0, id .. " keeps the source's shared quest visits as groups")
    for _, node in ipairs(ported.nodes) do
        if node.location then
            assert(node.location.x <= 1 and node.location.y <= 1, id .. ": percent coordinates normalize at " .. node.index)
            assert(node.location.mapID == 1442, id .. ": known map at " .. node.index)
        end
        local title = ns.modules.Steps:Title(node)
        assert(#title > 0, id .. ": every step renders a title at " .. node.index)
        assert(not title:find("NPC %d"),
            id .. ": every NPC is named -> " .. title)
        assert(not title:find(", objective %d+$"),
            id .. ": a step must say what it asks for, not a quest and an index -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- The ported RestedXP Thousand Needles route, from Thunder Bluff to the level 30 cap.
do
    local id = "nuuroad:leveling:horde-thousand-needles-28-30"
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(onlyFor(source, "faction", "Horde") and source.data.map == 1441, id .. " is a Horde guide on the Thousand Needles map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.GuideCheck:Validate(ported)
    assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    assert(#ported.groups > 0, id .. " keeps the source's shared quest visits as groups")
    local maps = { [1441] = true, [1456] = true, [1413] = true, [1444] = true, [1446] = true, [1434] = true, [1454] = true }
    for _, node in ipairs(ported.nodes) do
        if node.location then
            assert(node.location.x <= 1 and node.location.y <= 1, id .. ": percent coordinates normalize at " .. node.index)
            assert(maps[node.location.mapID], id .. ": known map at " .. node.index)
        end
        local title = ns.modules.Steps:Title(node)
        assert(#title > 0, id .. ": every step renders a title at " .. node.index)
        assert(not title:find("NPC %d"),
            id .. ": every NPC is named -> " .. title)
        assert(not title:find(", objective %d+$"),
            id .. ": a step must say what it asks for, not a quest and an index -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- The ported RestedXP Skyborne start: one guide for a race that picks either faction.
local skyborneID = "nuuroad:leveling:skyborne-zephras-isle"
local skyborneSource = ns.builtInGuides[skyborneID]
assert(skyborneSource, skyborneID .. " must register")
assert(onlyFor(skyborneSource, "race", "skyborne") and skyborneSource.data.map == 2521, "the Skyborne guide is for Skyborne, on Zephras Isle")
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
    assert(not title:find("NPC %d"),
        skyborneID .. ": every NPC is named -> " .. title)
    assert(not title:find(", objective %d+$"),
        skyborneID .. ": a step must say what it asks for, not a quest and an index -> " .. title)
end
-- Whether a step's `cond` names a faction: as its own key, or inside an
-- any, all or none list, or a named condition (`is`) in data.conds.
local conds = skyborneSource.data.conds or {}
local function names(cond, faction)
    if type(cond) ~= "table" then return false end
    local held = cond.faction
    if held == faction then return true end
    if type(held) == "table" then
        for _, value in ipairs(held) do if value == faction then return true end end
    end
    if cond.is and names(conds[cond.is], faction) then return true end
    for _, key in ipairs({ "any", "all", "none" }) do
        for _, child in ipairs(cond[key] or {}) do if names(child, faction) then return true end end
    end
    return false
end
local function countFactions(steps)
    for _, step in ipairs(steps) do
        if step.group then countFactions(step.group) end
        for faction in pairs(factionSteps) do
            if names(step.cond, faction) then factionSteps[faction] = factionSteps[faction] + 1 end
        end
    end
end
for _, section in ipairs(skyborneSource.data.sections) do countFactions(section.steps) end
assert(factionSteps.Alliance > 50 and factionSteps.Horde > 20, "both factions' forks of the island are ported")
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
assert(onlyFor(wc, "faction", "Horde"), "the Wailing Caverns guide is Horde-only")
local wcTurnins, wcSticky = {}, 0
for _, node in ipairs(wc.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "Wailing Caverns names everything: " .. title)
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
assert(onlyFor(rfc, "faction", "Horde"), "the Ragefire Chasm guide is Horde-only")
local rfcMaps = { [1411] = true, [1454] = true, [1456] = true, [1458] = true }
local rfcTurnins, rfcSticky = {}, 0
for _, node in ipairs(rfc.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "Ragefire Chasm names everything: " .. title)
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
assert(onlyFor(rol, "faction", "Horde"), "the Ruins of Lordaeron guide is Horde-only")
local rolTurnins = {}
for _, node in ipairs(rol.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "Ruins of Lordaeron names everything: " .. title)
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
assert(onlyFor(sfk, "faction", "Horde"), "the Shadowfang Keep guide is Horde-only")
local sfkMaps = { [1413] = true, [1421] = true, [1458] = true }
local sfkTurnins, sfkSticky = {}, 0
for _, node in ipairs(sfk.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "Shadowfang Keep names everything: " .. title)
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

-- Blackfathom Deeps (HordeBlackfathomDeeps.lua).
local bfd = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:dungeon:horde-blackfathom-deeps-quests"])
assert(onlyFor(bfd, "faction", "Horde"), "the Blackfathom Deeps guide is Horde-only")
local bfdMaps = { [1413] = true, [1440] = true, [1442] = true, [1456] = true }
local bfdTurnins, bfdSticky = {}, 0
for _, node in ipairs(bfd.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "Blackfathom Deeps names everything: " .. title)
    if node.sticky then bfdSticky = bfdSticky + 1 end
    if node.kind == "turnInQuest" or node.kind == "talk" then
        for _, goal in ipairs(node.completion.observed.children or { node.completion.observed }) do
            if goal.state == "finished" then for _, id in ipairs(goal.ids) do bfdTurnins[id] = true end end
        end
    end
    if node.location then
        assert(bfdMaps[node.location.mapID], "Blackfathom Deeps stays in Ashenvale, Stonetalon, Thunder Bluff and the Barrens: " .. node.index)
    end
end
assert(bfdSticky == 1, "the Soran'ruk Fragments ride along inside, got " .. bfdSticky)
for _, id in ipairs({ 1740, 6561, 6562, 6563, 6564, 6565, 6921, 6922 }) do
    assert(bfdTurnins[id], "the Blackfathom Deeps guide turns in quest " .. id)
end

local rfk = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:dungeon:horde-razorfen-kraul-quests"])
assert(onlyFor(rfk, "faction", "Horde"), "the Razorfen Kraul guide is Horde-only")
local rfkMaps = { [1413] = true, [1456] = true, [1458] = true }
local rfkTurnins, rfkSticky = {}, 0
for _, node in ipairs(rfk.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "Razorfen Kraul names everything: " .. title)
    if node.sticky then rfkSticky = rfkSticky + 1 end
    if node.kind == "turnInQuest" or node.kind == "talk" then
        for _, goal in ipairs(node.completion.observed.children or { node.completion.observed }) do
            if goal.state == "finished" then for _, id in ipairs(goal.ids) do rfkTurnins[id] = true end end
        end
    end
    if node.location then
        assert(rfkMaps[node.location.mapID], "Razorfen Kraul stays in the Barrens, Thunder Bluff and the Undercity: " .. node.index)
    end
end
assert(rfkSticky == 2, "the guano and the tubers ride along inside, got " .. rfkSticky)
for _, id in ipairs({ 1102, 1109, 1144, 1221, 6522 }) do
    assert(rfkTurnins[id], "the Razorfen Kraul guide turns in quest " .. id)
end

local gnomer = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:dungeon:horde-gnomeregan-quests"])
assert(onlyFor(gnomer, "faction", "Horde"), "the Gnomeregan guide is Horde-only")
local gnomerMaps = { [1426] = true, [1434] = true, [1454] = true }
local gnomerTurnins = {}
for _, node in ipairs(gnomer.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "Gnomeregan names everything: " .. title)
    if node.kind == "turnInQuest" or node.kind == "talk" then
        for _, goal in ipairs(node.completion.observed.children or { node.completion.observed }) do
            if goal.state == "finished" then for _, id in ipairs(goal.ids) do gnomerTurnins[id] = true end end
        end
    end
    if node.location then
        assert(gnomerMaps[node.location.mapID], "Gnomeregan stays in Orgrimmar, Stranglethorn and Dun Morogh: " .. node.index)
    end
end
for _, id in ipairs({ 2841, 2842, 2843, 2904, 2945, 2949, 2950, 2951 }) do
    assert(gnomerTurnins[id], "the Gnomeregan guide turns in quest " .. id)
end

local dalaran = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:dungeon:horde-city-of-dalaran-quests"])
assert(onlyFor(dalaran, "faction", "Horde"), "the City of Dalaran guide is Horde-only")
local dalaranMaps = { [1416] = true, [1424] = true, [1458] = true }
local dalaranTurnins = {}
for _, node in ipairs(dalaran.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "City of Dalaran names everything: " .. title)
    if node.kind == "turnInQuest" or node.kind == "talk" then
        for _, goal in ipairs(node.completion.observed.children or { node.completion.observed }) do
            if goal.state == "finished" then for _, id in ipairs(goal.ids) do dalaranTurnins[id] = true end end
        end
    end
    if node.location then
        assert(dalaranMaps[node.location.mapID], "City of Dalaran stays in Alterac, Hillsbrad and the Undercity: " .. node.index)
    end
end
for _, id in ipairs({ 96986, 96987, 96988 }) do
    assert(dalaranTurnins[id], "the City of Dalaran guide turns in quest " .. id)
end

-- Horde Druid Cat Form: Forever-only, recorded in play; Druid and not Alliance.
local cat = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:class:horde-druid-cat-form"])
assert(cat.condition.type == "all", "the Cat Form guide needs both the class and the faction")
for _, node in ipairs(cat.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "Cat Form names everything: " .. title)
    if node.location then
        assert(node.location.mapID == 1456 or node.location.mapID == 1450, "Cat Form stays in Thunder Bluff and Moonglade: " .. node.index)
    end
end

-- The ported RestedXP Ashenvale guide, from Orgrimmar's trainers to the Zoram'gar turn-ins.
do
    local id = "nuuroad:leveling:horde-ashenvale-26-30"
    local source = ns.builtInGuides[id]
    assert(source, id .. " must register")
    assert(onlyFor(source, "faction", "Horde") and source.data.map == 1440, id .. " is a Horde guide on the Ashenvale map")
    local ported = ns.modules.Steps:Expand(source)
    local valid, problems = ns.modules.GuideCheck:Validate(ported)
    assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    assert(#ported.groups > 0, id .. " keeps the source's shared quest visits as groups")
    local maps = { [1440] = true, [1454] = true, [1450] = true }
    for _, node in ipairs(ported.nodes) do
        if node.location then
            assert(node.location.x <= 1 and node.location.y <= 1, id .. ": percent coordinates normalize at " .. node.index)
            assert(maps[node.location.mapID], id .. ": known map at " .. node.index)
        end
        local title = ns.modules.Steps:Title(node)
        assert(#title > 0, id .. ": every step renders a title at " .. node.index)
        assert(not title:find("NPC %d"),
            id .. ": every NPC is named -> " .. title)
        assert(not title:find(", objective %d+$"),
            id .. ": a step must say what it asks for, not a quest and an index -> " .. title)
        if node.body then assert(#node.body > 0, id .. ": body text is never empty at " .. node.index) end
    end
    assert(ported.nodes[#ported.nodes].kind == "end", id .. " ends with a closing step")
end

-- Excavation Site: Wetlands (HordeExcavationSite.lua): built from data, no recorded run.
local exc = ns.modules.Steps:Expand(ns.builtInGuides["nuuroad:dungeon:horde-excavation-site-quests"])
assert(onlyFor(exc, "faction", "Horde"), "the Excavation Site guide is Horde-only")
local excMaps = { [1437] = true, [1454] = true, [1417] = true, [1456] = true, [1412] = true }
local excTurnins, excSticky = {}, 0
for _, node in ipairs(exc.nodes) do
    local title = ns.modules.Steps:Title(node)
    assert(not title:find("NPC %d"), "Excavation Site names everything: " .. title)
    if node.sticky then excSticky = excSticky + 1 end
    if node.kind == "turnInQuest" or node.kind == "talk" then
        for _, goal in ipairs(node.completion.observed.children or { node.completion.observed }) do
            if goal.state == "finished" then for _, id in ipairs(goal.ids) do excTurnins[id] = true end end
        end
    end
    if node.location then
        assert(excMaps[node.location.mapID], "Excavation Site stays in the Wetlands, Orgrimmar, Hammerfall, Thunder Bluff and Mulgore: " .. node.index)
    end
end
assert(excSticky == 4, "the four dungeon objective lines ride along inside, got " .. excSticky)
for _, id in ipairs({ 95663, 95664, 95682, 95697, 98823 }) do
    assert(excTurnins[id], "the Excavation Site guide turns in quest " .. id)
end

return true
