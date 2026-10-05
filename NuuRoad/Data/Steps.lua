local _, ns = ...

-- The v2 guide format: what the editor and the fixtures write, and what
-- Data/Import.lua turns a packaged guide (export format 1) into; the fields
-- it adds for that are in docs/guide-schema.md, "Read from the export
-- format". It is not the shape the addon runs on. Expand()
-- converts a guide once, here, and everything downstream sees ordinary
-- runtime nodes; anything derived -- titles, step positions, section and group
-- spans, reference lists, completion rules -- is built on the way in and never
-- authored.
--
-- A guide is a list of sections; a section is a list of steps and groups:
--
--   {
--       schema = 2, id = "nuuroad:leveling:barrens", updated = 1789862400,
--       map = 1413, only = "Horde",
--       meta = { title = "...", author = "...", category = "Leveling/The Barrens",
--                tags = { ... }, levels = { 13, 21 }, source = "..." },
--       steps = {
--           { section = "Crossroads", steps = { ... } },
--           { section = "Orgrimmar", map = 1454, steps = { ... } },
--       },
--   }
--
-- Steps, one verb key each:
--
--   { note = "Turn in Crossroads Conscription first." }      -- a step of its own
--   { accept = 870, npc = 3448, note = "Inside the inn." }   -- shown under that step
--   { travel = "Ratchet", at = { 63, 37.2 } }
--   { turnin = { 870, 845 }, npc = 3448, at = { ... } }
--   { turnin = 871, accept = { 872, 5041 }, npc = 3429 }  -- one visit, both
--   { objective = 870, at = { ... }, radius = 0.05 }      -- readyToTurnIn
--   { objective = 821, part = 2, at = { ... } }           -- one objective line
--   { objectives = { 871, 844 }, at = { ... } }           -- all readyToTurnIn
--   { objective = 871, part = 1, kill = 3267, count = 8 }   -- fallback title "Kill 8 ..."
--   { objective = 844, part = 1, collect = 5087, count = 7 } -- fallback title "Collect 7 ..."
--   { escort = 99144, npc = 275954, at = { ... } }          -- "Escort <npc>" to `at`: readyToTurnIn
--   { collect = 4926, object = "Chen's Empty Keg", at = { ... } } -- item in bags
--   { collect = 4926, starts = 819, object = "Chen's Empty Keg" } -- item that begins quest 819
--   { collect = 4986, quest = 924, object = "Flawed Power Stones" } -- quest item picked up for quest 924
--   { hearth = "The Crossroads", npc = 3934, at = { ... } }
--   { flight = "Ratchet", npc = 16227, at = { ... } }
--   { track = 869 } / { untrack = 869 }                     -- sticky objective shown alongside later steps
--   { object = "Control Console", turnin = 894, accept = 900 } -- interaction target on any step
--   { kill = 3267, count = 8, at = { ... } }                 -- no quest: counted from the combat log
--   { objective = 746, part = 1, collect = 4703, count = 5, use = 4702 } -- press the pick, count the tools
--   { train = "Mining", npc = 3357, at = { ... } }          -- learn it, or its next rank
--   { learn = { 100, 772 }, npc = 3353, at = { ... } }      -- class spells from a trainer: known
--   { cast = 1259686, at = { ... } }                        -- cast that spell while on the step
--   { skill = "Mining", rank = 150 }                        -- raise a skill to a rank
--   { gather = 2770, count = 20, skill = "Mining", at = { ... } } -- pick it, or buy it
--   { gather = 2770, count = 20, skill = "Mining", upto = 150 } -- ... or until the rank lands
--   { gather = 2835, count = 40, upto = { "Blacksmithing", 100 } } -- ... a rank in another profession
--   { craft = 2862, count = 30, skill = "Blacksmithing" }   -- make that many
--   { skillup = 2862, skill = "Blacksmithing", rank = 100 } -- make them until that rank
--   { buy = 2320, count = 10, npc = 3134, at = { ... } }    -- buy from that vendor
--   { equip = 7360 }                                        -- wear it
--   { reputation = 576, standing = "Honored" }              -- reach a standing
--   { craft = 2862, needs = { { 2840, 10 }, { 3466, 2, "ah" } } } -- materials
--   { level = 17 } / { level = 13, xp = 9200 }
--   { level = 14, by = "ratchet" }   -- the turn-ins before that label count
--   { group = { { accept = 870 }, { accept = 869 } } }    -- concurrent quest visits
--   { finish = "Closing text." }
--
-- Steps run in order. A branch is a `choice` whose options name labels, never
-- positions: any step or section may carry `label = "circuit"`, and an option
-- says `goto = "circuit"`. A label behind the choice runs that stretch again,
-- which is how a farming circuit is written.
--
--   { section = "Copper circuit", label = "circuit", steps = { ... } },
--   { choice = "Another lap?", options = {
--       { "Run the circuit again", goto = "circuit" },
--       { "Done farming", goto = "done" } } },
--
-- `at` is one point `{ x, y }`, or a list of points whose first is the arrow
-- target and whose rest are map pins. Either may carry `map = 1454` for a
-- coordinate off the guide's map; a section carries `map` for its whole span.
-- Coordinates may be percentages (52.26, 31.93) or normalized (0.5226).
--
-- Any step may carry `only`: "Warrior", "Warrior or Shaman", "not Tauren",
-- "Horde", "quest 858", "not quest 858", "Mage | level 4 | now gold 100".
-- `|` joins groups that must all hold; inside a group positive terms are
-- OR-ed and negated terms AND-ed. A step for another class, race, or faction
-- is left out for that character; one waiting on a quest or a level is
-- stopped on until it opens or the player skips it. A term marked `now` is
-- read as it stands when the guide reaches the step and never waited on: the
-- step is passed over if it does not hold (item count, money, xp and
-- cooldown gates). A guide carries `only` the same way.
--
-- IDs only; the guide's `names` table names them, by kind:
--   names = { npcs = { [2980] = "Grull Hawkwind" }, quests = { [747] = "The Hunt Begins" } }
-- (npcs, quests, items, factions, spells). An NPC the guide visits also says
-- where it stands, and may carry a note shown on every visit:
--   [3448] = { "Tonga Runetotem", at = { 52.26, 31.93 }, note = "..." }
-- so `{ accept = 870, npc = 3448 }` needs no `at`; a step's own `at` wins. `object` is the one exception:
-- world objects are named, not numbered. ASCII only.
local Steps = {}


-- `kill` comes after `collect` so a collect step with kill targets stays a collect step.
-- The profession verbs come before `skill`, which they carry as the
-- profession they use, so a step that names its profession keeps its verb.
local verbs = { "travel", "turnin", "accept", "objective", "objectives", "escort", "collect", "kill", "gather", "skillup", "craft", "buy", "vendor", "equip", "train", "learn", "cast", "skill", "reputation", "hearth", "flight", "track", "untrack", "level", "choice", "finish" }
local radiusByVerb = {
    accept = 0.02, turnin = 0.02, talk = 0.02, travel = 0.03, objective = 0.05, objectives = 0.05, escort = 0.05,
    level = 0.025, collect = 0.04, kill = 0.05, hearth = 0.02, interact = 0.02,
    train = 0.02, learn = 0.02, cast = 0.03, buy = 0.02, vendor = 0.02, craft = 0.03, skillup = 0.03, equip = 0.03, skill = 0.05, reputation = 0.05,
    gather = 0.05, flight = 0.02, finish = 0.02,
}

local classTokens = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
    shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID",
}
local factionTokens = { horde = "Horde", alliance = "Alliance" }
local raceTokens = {
    orc = "orc", troll = "troll", tauren = "tauren", undead = "scourge", ["blood elf"] = "bloodelf", bloodelf = "bloodelf",
    human = "human", dwarf = "dwarf", ["night elf"] = "nightelf", nightelf = "nightelf", gnome = "gnome", draenei = "draenei",
    -- Forever's own race, either faction. Matches the client's
    -- UnitRace token "Skyborne"; unverified here, see docs/api-compatibility.md.
    skyborne = "skyborne",
}

local function list(value)
    if type(value) == "table" then
        local result = {}
        for index, entry in ipairs(value) do result[index] = entry end
        return result
    end
    if value ~= nil then return { value } end
    return {}
end

-- Where a material comes from. The guide says which; nothing is looked up,
-- and no price, stock, or auction data is ever read.
Steps.materialSources = { gather = true, vendor = true, ah = true, drop = true, craft = true }

-- `needs = { { 2840, 10 }, { 3466, 2, "ah" } }` -> the node's material list.
-- Counts are the whole step's, not per item made, so what an author writes is
-- what the list asks for.
local function materials(step)
    if step.needs == nil then return nil end
    if type(step.needs) ~= "table" then error("NuuRoad: needs must be a list of materials") end
    local list = {}
    for _, entry in ipairs(step.needs) do
        if type(entry) ~= "table" then error("NuuRoad: each material is { itemID, count, source }") end
        local itemID, count, source = entry[1], entry[2] or 1, entry[3] or "gather"
        if type(itemID) ~= "number" then error("NuuRoad: a material is named by item ID") end
        if not Steps.materialSources[source] then error("NuuRoad: unknown material source '" .. tostring(source) .. "'") end
        table.insert(list, { itemID = itemID, count = count, source = source })
    end
    if #list == 0 then return nil end
    return list
end

-- The profession rank that makes the step moot. A materials step in a
-- profession guide is only ever a means to a rank, so reaching the rank
-- finishes it however few were gathered, bought, or made -- an escape hatch
-- on every such step.
--
--   upto = 150                      -- the step's own profession
--   upto = { "Blacksmithing", 100 } -- another one: a crafting guide's
--                                      gather step escapes on the craft
local function uptoRank(step)
    if step.upto == nil then return nil end
    local skill, rank = step.skill, tonumber(step.upto)
    if type(step.upto) == "table" then skill, rank = step.upto[1], tonumber(step.upto[2]) end
    if not rank then error("NuuRoad: upto is a rank, or { skill, rank }") end
    if type(skill) ~= "string" then error("NuuRoad: upto has no skill, and the step names no profession") end
    return { skill = skill, rank = rank }
end

local function verbOf(step)
    if step.turnin ~= nil and step.accept ~= nil then return "talk" end
    -- `talk = true`: a visit with nothing to hand in or take, such as a
    -- trainer. The player says when it is done.
    if step.talk == true then return "talk" end
    -- `collect` and `kill` are modifiers when the step is a quest objective.
    if step.objective ~= nil then return "objective" end
    for _, verb in ipairs(verbs) do
        if step[verb] ~= nil then return verb end
    end
    if step.object ~= nil then return "interact" end
    -- `note` is a step of its own only when nothing else is on it.
    if step.note ~= nil then return "note" end
    return nil
end

local function joinNames(ids, describe)
    -- One creature can carry several IDs (a copy per phase); it is named once.
    local names, seen = {}, {}
    for _, id in ipairs(ids) do
        local name = describe(ns.modules.Names, id)
        if not seen[name] then seen[name] = true; table.insert(names, name) end
    end
    if #names <= 1 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- Where a quest item drops from. A collect step that also names its killers
-- is saying the item comes off those creatures, and the player reading
-- "Collect 8 Windfury Talon" has nowhere to go without it.
local function killSource(auto)
    if not auto or not auto.collect or not auto.kill then return nil end
    return auto.kill
end

-- The items a step asks the player to press, when pressing is the whole of
-- the step. A step that also counts something (smash the picks, collect the
-- tools) is titled by its count, because that is the part with an end to it.
local function pressedItems(node)
    local auto = node and node.auto
    if not auto or auto.collect or auto.kill then return nil end
    if not node.use or not node.use[1] then return nil end
    return node.use
end

-- Recomputed on every render so a name the client resolves later shows up.
-- `literal` asks for the step as authored -- the whole count, no live
-- fraction -- which is what a report about the guide itself wants: the audit
-- and the editor describe the step, not the moment.
function Steps:Title(node, literal)
    if not node then return "" end
    local auto = node.auto
    if not auto or node.customTitle then
        -- A note's title is only the generic "Note": its text is the real label.
        if node.kind == "note" and (node.title == nil or node.title == "" or node.title == "Note") and type(node.body) == "string" and node.body ~= "" then
            return node.body
        end
        return node.title or ""
    end
    local Names = ns.modules.Names
    local verb = auto.verb
    local suffix = auto.object and (" at " .. auto.object) or ""
    local source = killSource(auto)
    local sourceText = source and (" from " .. joinNames(source, Names.DescribeNPC)) or ""
    local press = (node.use and node.use[1] and (auto.collect or auto.kill)) and node.use or nil
    -- What the creatures drop is the thing that is pressed, where the step
    -- presses one: the diggers carry the picks, the tools come off the forge.
    local pressText = press and ("Use " .. joinNames(press, Names.DescribeItem) .. sourceText .. ", and ") or ""
    local fromText = not press and sourceText or ""
    if verb == "objective" and auto.part then
        local pressed = pressedItems(node)
        -- What the step is really asking for, in the order a player needs it:
        -- a count if there is one to keep, otherwise the item to press, and
        -- only then the client's own objective line. A line reading "Well
        -- cleansed: 0/1" is a status; "Use Thunderhorn Cleansing Totem" is the
        -- work. Naming the quest and an index is the last resort, and says
        -- nothing the step view has not already said.
        if not pressed then
            local Client = ns.modules.Client
            local _, text = Client and Client.GetQuestObjective and Client:GetQuestObjective(auto.quests[1], auto.part)
            if text and text ~= "" then return text end
        end
        -- On this path there is no " at ..." to say where the item is, so the
        -- object it comes out of is the source, the way the killers are.
        if auto.collect then
            local from = fromText ~= "" and fromText or (auto.object and (" from " .. auto.object)) or ""
            return pressText .. "Collect " .. Steps:CountText(node, literal) .. joinNames(auto.collect, Names.DescribeItem) .. from
        end
        if auto.kill then return pressText .. "Kill " .. Steps:CountText(node, literal) .. joinNames(auto.kill, Names.DescribeNPC) end
        if pressed then return "Use " .. joinNames(pressed, Names.DescribeItem) end
        if auto.object then return "Click " .. auto.object end
        if auto.npc then return "Talk to " .. joinNames(auto.npc, Names.DescribeNPC) end
        -- The creatures the work is done on (a beast to tame), with the
        -- quest, when the client has no line to give.
        if node.mark then return Names:DescribeQuest(auto.quests[1]) .. ": " .. joinNames(node.mark, Names.DescribeNPC) end
        return Names:DescribeQuest(auto.quests[1]) .. ", objective " .. tostring(auto.part)
    end
    if verb == "objective" or verb == "objectives" then
        local title = "Complete " .. joinNames(auto.quests, Names.DescribeQuest)
        if auto.kill then title = pressText .. "Kill " .. Steps:CountText(node, literal) .. joinNames(auto.kill, Names.DescribeNPC) end
        if auto.collect then title = pressText .. "Collect " .. Steps:CountText(node, literal) .. joinNames(auto.collect, Names.DescribeItem) .. fromText end
        return title .. suffix
    end
    if verb == "escort" then return "Escort " .. joinNames(auto.npc, Names.DescribeNPC) end
    if verb == "collect" then
        local Client = ns.modules.Client
        local have = Client and Client.GetItemCount and Client:GetItemCount(auto.collect[1])
        local title = pressText .. "Collect " .. Steps:CountText(node, literal) .. joinNames(auto.collect, Names.DescribeItem) .. fromText
        if not literal and have and auto.count and auto.count > 1 then title = title .. string.format(" (%d/%d)", have, auto.count) end
        return title .. suffix
    end
    if verb == "kill" then
        local title = pressText .. "Kill " .. Steps:CountText(node, literal) .. joinNames(auto.kill, Names.DescribeNPC)
        local have = Steps:KillCount(node)
        if not literal and have > 0 and auto.count and auto.count > 1 then title = title .. string.format(" (%d/%d)", math.min(have, auto.count), auto.count) end
        return title .. suffix
    end
    if verb == "train" then
        if auto.rank then return "Train " .. auto.skill .. " to " .. tostring(auto.rank) .. suffix end
        return "Train " .. auto.skill .. suffix
    end
    if verb == "learn" then
        local title = "Train " .. joinNames(auto.spells, Names.DescribeSpell)
        if auto.trainer then title = title .. " from " .. Names:DescribeNPC(auto.trainer) end
        return title .. suffix
    end
    if verb == "cast" then
        local title = "Cast " .. Names:DescribeSpell(auto.spell)
        if auto.count and auto.count > 1 then
            title = title .. " " .. tostring(auto.count) .. " times"
            local have = Steps:CastCount(node)
            if not literal and have > 0 then title = title .. string.format(" (%d/%d)", math.min(have, auto.count), auto.count) end
        end
        return title .. suffix
    end
    if verb == "skill" then
        local title = "Raise " .. auto.skill .. " to " .. tostring(auto.rank)
        local Client = ns.modules.Client
        local rank = Client and Client.GetSkillRank and Client:GetSkillRank(auto.skill)
        if not literal and rank then title = title .. string.format(" (%d/%d)", rank, auto.rank) end
        return title .. suffix
    end
    if verb == "craft" then
        local Client = ns.modules.Client
        local title = "Craft " .. Steps:CountText(node, literal) .. Names:DescribeItem(auto.item)
        if auto.skill then title = title .. " using " .. auto.skill end
        local have = Steps:CraftCount(node)
        local inBags = Client and Client.GetItemCount and Client:GetItemCount(auto.item) or 0
        have = math.max(have, inBags)
        if not literal and auto.count and auto.count > 1 and have > 0 then title = title .. string.format(" (%d/%d)", math.min(have, auto.count), auto.count) end
        return title .. suffix
    end
    if verb == "skillup" then
        local Client = ns.modules.Client
        local title = "Craft " .. Names:DescribeItem(auto.item) .. " until " .. auto.skill .. " " .. tostring(auto.rank)
        local rank = Client and Client.GetSkillRank and Client:GetSkillRank(auto.skill)
        if not literal and rank then title = title .. string.format(" (%d/%d)", rank, auto.rank) end
        return title .. suffix
    end
    if verb == "vendor" then
        local action = auto.action == "repair" and "Repair"
            or (auto.action == "sell and repair" and "Sell and repair") or "Sell your junk"
        if auto.vendor then return action .. " at " .. Names:DescribeNPC(auto.vendor) .. suffix end
        return action .. suffix
    end
    if verb == "buy" then
        local Client = ns.modules.Client
        local title = "Buy " .. Steps:CountText(node, literal) .. Names:DescribeItem(auto.item)
        -- Vendors sell different stock, so the one the guide means is named.
        if auto.vendor then title = title .. " from " .. Names:DescribeNPC(auto.vendor) end
        local have = Client and Client.GetItemCount and Client:GetItemCount(auto.item)
        if not literal and have and auto.count and auto.count > 1 then title = title .. string.format(" (%d/%d)", math.min(have, auto.count), auto.count) end
        return title .. suffix
    end
    if verb == "gather" then
        local Client = ns.modules.Client
        local title = "Gather " .. Steps:CountText(node, literal) .. Names:DescribeItem(auto.item)
        if auto.skill then title = title .. " with " .. auto.skill end
        local have = Client and Client.GetItemCount and Client:GetItemCount(auto.item)
        if not literal and have and auto.count and auto.count > 1 then title = title .. string.format(" (%d/%d)", math.min(have, auto.count), auto.count) end
        return title .. suffix
    end
    if verb == "equip" then return "Equip " .. Names:DescribeItem(auto.item) .. suffix end
    if verb == "reputation" then
        return "Reach " .. Names:DescribeStanding(auto.standing) .. " with " .. Names:DescribeFaction(auto.faction) .. suffix
    end
    if verb == "hearth" then return "Set your hearthstone at " .. auto.name end
    if verb == "flight" then return "Learn the " .. auto.name .. " flight path" end
    if verb == "track" then return "Meanwhile: " .. Names:DescribeQuest(auto.track) end
    if verb == "untrack" then return "Done tracking " .. Names:DescribeQuest(auto.untrack) end
    if verb == "interact" then return "Click " .. auto.object end
    if verb == "accept" then return "Accept " .. joinNames(auto.quests, Names.DescribeQuest) .. suffix end
    if verb == "turnin" then return "Turn in " .. joinNames(auto.quests, Names.DescribeQuest) .. suffix end
    if verb == "talk" and #auto.turnin + #auto.accept == 0 then
        return "Talk to " .. joinNames(node.refs and node.refs.npcs or {}, Names.DescribeNPC) .. suffix
    end
    if verb == "talk" then
        return "Turn in " .. joinNames(auto.turnin, Names.DescribeQuest) .. ", accept " .. joinNames(auto.accept, Names.DescribeQuest) .. suffix
    end
    if verb == "travel" then return "Travel to " .. auto.label end
    if verb == "level" then
        if type(auto.by) == "number" then return string.format("Reach level %d by step %d", auto.level, auto.by) end
        if auto.xp then return string.format("Reach level %d with %d XP", auto.level, auto.xp) end
        return "Reach level " .. tostring(auto.level)
    end
    return node.title or ""
end

-- Goal lines: one line per thing to do, each with a verb that picks its
-- icon, `parts` ({ text, role }) the tracker colours by role (quest, npc,
-- monster, item, location, count), and the
-- references GoalStatus() needs to say whether it is done yet. Title() stays
-- the one-line plain summary used everywhere else.
-- `id` is the thing the text names, where it has one: the tracker turns an
-- item part into a real item link, so the name carries its quality colour and
-- answers a hover and a click like any link in the game.
local function part(text, role, id) return { text = text, role = role or "plain", id = id } end

-- Kills of a step's targets, counted from the combat log by NPCTracking and
-- kept in the character's progress for the guide. Zero without a live client.
function Steps:KillCount(node)
    local Progress = ns.modules.Progress
    if not node or not node.index or not Progress or not Progress.KillCount then return 0 end
    local guide = Progress:GetActiveGuide()
    if not guide then return 0 end
    return Progress:KillCount(guide, node.index)
end

-- Items the player has made on this step, counted from the client's "You
-- create:" message. Like kills, it is session-only and says nothing about
-- what was crafted before the step was reached.
function Steps:CraftCount(node)
    local Progress = ns.modules.Progress
    if not node or not node.index or not Progress or not Progress.CraftCount then return 0 end
    local guide = Progress:GetActiveGuide()
    if not guide then return 0 end
    return Progress:CraftCount(guide, node.index)
end

-- Casts of the step's spell since the player reached it, counted by
-- ObservedProgress from UNIT_SPELLCAST_SUCCEEDED. Session-only, like kills.
function Steps:CastCount(node)
    local Progress = ns.modules.Progress
    if not node or not node.index or not Progress or not Progress.CastCount then return 0 end
    local guide = Progress:GetActiveGuide()
    if not guide then return 0 end
    return Progress:CastCount(guide, node.index)
end

-- True once the player has opened a dialog with every NPC the step names.
function Steps:HasTalkedTo(node, npcs)
    local Progress = ns.modules.Progress
    if not node or not node.index or not Progress or not Progress.HasTalked then return false end
    local guide = Progress:GetActiveGuide()
    if not guide then return false end
    for _, id in ipairs(npcs or {}) do
        if not Progress:HasTalked(guide, node.index, id) then return false end
    end
    return #(npcs or {}) > 0
end

local function nameParts(parts, ids, describe, role)
    for index, id in ipairs(ids) do
        if index > 1 then table.insert(parts, part(index == #ids and " and " or ", ")) end
        table.insert(parts, part(describe(ns.modules.Names, id), role, id))
    end
    return parts
end

local function fractionFrom(text)
    if type(text) ~= "string" then return nil end
    return tonumber(text:match("(%d+)%s*/%s*%d+"))
end

-- How far along a quest's objective is, read from the client's own line
-- ("Plainstrider Beak: 4/9"). `index` names the objective; without one the
-- first line carrying a fraction is taken, which is the only one a
-- single-objective quest has.
local function questProgress(Client, questID, index)
    if not Client or not Client.GetQuestObjective or type(questID) ~= "number" then return nil end
    if index then
        local _, text = Client:GetQuestObjective(questID, index)
        return fractionFrom(text)
    end
    for objective = 1, 10 do
        local finished, text = Client:GetQuestObjective(questID, objective)
        if finished == nil then return nil end
        local have = fractionFrom(text)
        if have then return have end
    end
    return nil
end

-- How many an objective needs, by "quest:objective". The client answers for
-- any quest, in the log or not, and the number never changes, so it is asked
-- once.
local objectiveNeeds = {}

-- The step's target count: the authored one, or for an objective step that
-- names none (an imported guide leaves the number to the quest) what the
-- client says the objective needs. Nil when neither says.
function Steps:Count(node)
    local auto = node and node.auto
    if not auto then return nil end
    if auto.count then return auto.count end
    if auto.verb ~= "objective" or not auto.part or not (auto.kill or auto.collect) then return nil end
    local questID = auto.quests and auto.quests[1]
    local key = tostring(questID) .. ":" .. tostring(auto.part)
    if objectiveNeeds[key] then return objectiveNeeds[key] end
    local Client = ns.modules.Client
    local lines = Client and Client.GetQuestObjectives and Client:GetQuestObjectives(questID)
    local need = type(lines) == "table" and lines[auto.part] and tonumber(lines[auto.part].need)
    if need and need > 0 then objectiveNeeds[key] = need end
    return objectiveNeeds[key]
end

-- What the player already has towards a step's count. Nil when the client
-- cannot say, and then the authored count stands.
function Steps:Have(node)
    local auto = node and node.auto
    if not auto or not self:Count(node) then return nil end
    local Client = ns.modules.Client
    local canCount = Client ~= nil and Client.GetItemCount ~= nil
    local verb = auto.verb
    if verb == "objective" and auto.part then
        return questProgress(Client, auto.quests and auto.quests[1], auto.part)
    end
    if verb == "objective" or verb == "objectives" then
        if not (auto.kill or auto.collect) then return nil end
        local quests = auto.quests or {}
        if #quests ~= 1 then return nil end
        return questProgress(Client, quests[1])
    end
    if verb == "collect" then
        return canCount and Client:GetItemCount(auto.collect and auto.collect[1]) or nil
    end
    if verb == "gather" or verb == "buy" then
        return canCount and Client:GetItemCount(auto.item) or nil
    end
    if verb == "craft" then
        return math.max(self:CraftCount(node), canCount and Client:GetItemCount(auto.item) or 0)
    end
    if verb == "kill" then return self:KillCount(node) end
    return nil
end

-- The number printed in front of the thing: what is left while the step is
-- under way, since the figure the player acts on is the one still owed. Once
-- the count is met the whole figure comes back, so a finished line never
-- reads "Collect 0".
function Steps:CountText(node, literal)
    local count = self:Count(node)
    if not count then return "" end
    local have = not literal and self:Have(node) or nil
    if type(have) == "number" and have > 0 and have < count then return (count - have) .. " " end
    return count .. " "
end

-- Plain or painted text of a goal. `paint(role, text, part)` returns the
-- decorated text for one part; without it the parts are joined as they are.
-- The whole part is passed so a painter can reach what it names, which is how
-- an item becomes a real link rather than a coloured string.
function Steps:GoalText(goal, paint)
    local out = {}
    for _, piece in ipairs(goal.parts or {}) do table.insert(out, paint and paint(piece.role, piece.text, piece) or piece.text) end
    return table.concat(out)
end

function Steps:Goals(node)
    local goals = {}
    if not node then return goals end
    local upto = node.auto and node.auto.upto
    local function add(verb, parts, extra)
        local goal = extra or {}
        goal.verb, goal.parts = verb, parts
        -- The rank that makes the goal moot is said on the line, not hidden,
        -- so a step going green early is never a mystery.
        if upto then
            goal.upto = upto
            table.insert(parts, part(" or "))
            table.insert(parts, part(upto.skill .. " " .. tostring(upto.rank), "count"))
        end
        table.insert(goals, goal)
        return goal
    end
    local auto = node.auto
    if not auto or node.customTitle then
        local verb = (node.kind == "end" or node.kind == "choice" or node.kind == "note") and node.kind or "note"
        add(verb, { part(node.title or "") })
        return goals
    end
    local Names = ns.modules.Names
    local verb = auto.verb
    local countText = Steps:CountText(node)
    local function withAt(parts)
        if auto.object then table.insert(parts, part(" at ")); table.insert(parts, part(auto.object, "location")) end
        return parts
    end
    -- The item the step asks the player to press, on the line with the count
    -- and in front of it, since it is what the player does first: the
    -- Lunardust summons Lunaclaw, the pick smashed at the forge yields the
    -- tool. The count still keeps the line, and the step still keeps one line.
    local press = (node.use and node.use[1] and (auto.collect or auto.kill)) and node.use or nil
    local function withPress(parts)
        if not press then return parts end
        local lead = nameParts({ part("Use ") }, press, Names.DescribeItem, "item")
        -- The creatures drop the thing that is pressed, not the thing the
        -- step counts: the diggers carry the picks, and the picks smashed at
        -- the forge are what make the tools.
        local source = killSource(auto)
        if source then
            table.insert(lead, part(" from "))
            nameParts(lead, source, Names.DescribeNPC, "monster")
        end
        table.insert(lead, part(", and "))
        for _, piece in ipairs(parts) do table.insert(lead, piece) end
        return lead
    end

    -- `object` only where the line has no " at ..." of its own: an objective
    -- step's collect line would otherwise be an item name and no way to it.
    local function withSource(parts, object)
        local source = not press and killSource(auto) or nil
        if source then
            table.insert(parts, part(" from "))
            return nameParts(parts, source, Names.DescribeNPC, "monster")
        end
        if object and auto.object then
            table.insert(parts, part(" from "))
            table.insert(parts, part(auto.object, "location"))
        end
        return parts
    end
    if verb == "accept" or verb == "turnin" or verb == "talk" then
        local npcs = node.refs and node.refs.npcs
        local turnins = verb == "turnin" and auto.quests or auto.turnin or {}
        local accepts = verb == "accept" and auto.quests or auto.accept or {}
        -- What the visit is for, hung on the "Talk to" line so it can be
        -- judged by the quests rather than by the dialog: opening a gossip
        -- window and walking away hands nothing in and takes nothing on.
        local settles
        for _, id in ipairs(turnins) do settles = settles or {}; table.insert(settles, { quest = id, state = "finished" }) end
        for _, id in ipairs(accepts) do settles = settles or {}; table.insert(settles, { quest = id, state = "acceptedOrFinished" }) end
        if npcs and #npcs > 0 then
            add("talk", withAt(nameParts({ part("Talk to ") }, npcs, Names.DescribeNPC, "npc")), { npcs = npcs, settles = settles })
        elseif auto.object then
            add("interact", { part("Click "), part(auto.object, "location") })
        end
        for _, id in ipairs(turnins) do add("turnin", { part("Turn in "), part(Names:DescribeQuest(id), "quest") }, { quest = id, state = "finished" }) end
        for _, id in ipairs(accepts) do add("accept", { part("Accept "), part(Names:DescribeQuest(id), "quest") }, { quest = id, state = "acceptedOrFinished" }) end
    elseif verb == "objective" and auto.part then
        local questID = auto.quests[1]
        local goal = { quest = questID, objective = { quest = questID, index = auto.part } }
        local pressed = pressedItems(node)
        if auto.collect then
            add("collect", withPress(withSource(nameParts({ part("Collect "), part(countText, "count") }, auto.collect, Names.DescribeItem, "item"), true)), goal)
        elseif auto.kill then
            add("kill", withPress(nameParts({ part("Kill "), part(countText, "count") }, auto.kill, Names.DescribeNPC, "monster")), goal)
        elseif pressed then
            -- The instruction, not the status: a quest met by pressing an
            -- item often has no objective line at all, and where it has one
            -- it only says whether the thing is done. As an item part the
            -- name wears its quality colour and answers a hover and a click,
            -- and the line takes the item's own icon.
            goal.useItem = pressed[1]
            add("use", nameParts({ part("Use ") }, pressed, Names.DescribeItem, "item"), goal)
        elseif auto.object then
            add("interact", { part("Click "), part(auto.object, "location") }, goal)
        elseif auto.npc and auto.npc[1] then
            -- An objective that is really a conversation: the step names the
            -- NPC, so the line says who to talk to rather than leaving the
            -- player with the client's status line or a quest and an index.
            add("talk", nameParts({ part("Talk to ") }, auto.npc, Names.DescribeNPC, "npc"), goal)
        else
            local Client = ns.modules.Client
            local _, text = Client and Client.GetQuestObjective and Client:GetQuestObjective(questID, auto.part)
            if text and text ~= "" then
                add("objective", { part(text) }, goal)
            elseif node.mark then
                add("objective", nameParts({ part(Names:DescribeQuest(questID), "quest"), part(": ") }, node.mark, Names.DescribeNPC, "monster"), goal)
            else
                add("objective", { part(Names:DescribeQuest(questID), "quest"), part(", objective " .. tostring(auto.part)) }, goal)
            end
        end
    elseif verb == "objective" or verb == "objectives" then
        local single = #auto.quests == 1 and auto.quests[1] or nil
        if auto.kill then
            add("kill", withAt(withPress(nameParts({ part("Kill "), part(countText, "count") }, auto.kill, Names.DescribeNPC, "monster"))), { quest = single, state = single and "readyToTurnIn" or nil })
        elseif auto.collect then
            add("collect", withAt(withPress(withSource(nameParts({ part("Collect "), part(countText, "count") }, auto.collect, Names.DescribeItem, "item")))), { quest = single, state = single and "readyToTurnIn" or nil })
        end
        if not (auto.kill or auto.collect) or not single then
            for _, id in ipairs(auto.quests) do
                local parts = { part("Complete "), part(Names:DescribeQuest(id), "quest") }
                if not (auto.kill or auto.collect) then withAt(parts) end
                add("objective", parts, { quest = id, state = "readyToTurnIn" })
            end
        end
    elseif verb == "escort" then
        add("escort", nameParts({ part("Escort ") }, auto.npc, Names.DescribeNPC, "npc"),
            { quest = auto.quests[1], state = "readyToTurnIn", escort = true })
    elseif verb == "collect" then
        add("collect", withAt(withPress(withSource(nameParts({ part("Collect "), part(countText, "count") }, auto.collect, Names.DescribeItem, "item")))),
            { item = auto.collect[1], count = auto.count or 1, quest = auto.starts or auto.quest, startsQuest = auto.starts ~= nil or nil })
    elseif verb == "kill" then
        add("kill", withAt(withPress(nameParts({ part("Kill "), part(countText, "count") }, auto.kill, Names.DescribeNPC, "monster"))), { kills = { npcs = auto.kill, count = auto.count or 1 } })
    elseif verb == "train" then
        local parts = { part("Train "), part(auto.skill, "item") }
        if auto.rank then table.insert(parts, part(" to ")); table.insert(parts, part(tostring(auto.rank), "count")) end
        add("train", withAt(parts), { skill = { name = auto.skill, atLeast = auto.rank or 1 } })
    elseif verb == "learn" then
        -- Painted as names only: a part's `id` would make the painter link an
        -- item of that number.
        local parts = { part("Train ") }
        for index, id in ipairs(auto.spells) do
            if index > 1 then table.insert(parts, part(index == #auto.spells and " and " or ", ")) end
            table.insert(parts, part(Names:DescribeSpell(id), "item"))
        end
        if auto.trainer then table.insert(parts, part(" from ")); table.insert(parts, part(Names:DescribeNPC(auto.trainer), "npc")) end
        add("train", withAt(parts), { spells = auto.spells })
    elseif verb == "cast" then
        local parts = { part("Cast "), part(Names:DescribeSpell(auto.spell), "item") }
        if auto.count and auto.count > 1 then table.insert(parts, part(" " .. tostring(auto.count) .. " times", "count")) end
        add("use", withAt(parts), { casts = { spell = auto.spell, count = auto.count or 1 } })
    elseif verb == "skill" then
        add("skill", withAt({ part("Raise "), part(auto.skill, "item"), part(" to "), part(tostring(auto.rank), "count") }),
            { skill = { name = auto.skill, atLeast = auto.rank } })
    elseif verb == "craft" then
        local parts = { part("Craft "), part(countText, "count"), part(Names:DescribeItem(auto.item), "item", auto.item) }
        if auto.skill then table.insert(parts, part(" using ")); table.insert(parts, part(auto.skill, "item")) end
        add("craft", withAt(parts), { crafted = { item = auto.item, count = auto.count or 1 } })
    elseif verb == "skillup" then
        -- The rank is the goal; the item is only how the player gets there,
        -- so a lucky run of skill-ups finishes the step early.
        add("craft", withAt({
            part("Craft "), part(Names:DescribeItem(auto.item), "item", auto.item),
            part(" until "), part(auto.skill, "item"), part(" "), part(tostring(auto.rank), "count"),
        }), { skill = { name = auto.skill, atLeast = auto.rank } })
    elseif verb == "buy" then
        local parts = { part("Buy "), part(countText, "count"), part(Names:DescribeItem(auto.item), "item", auto.item) }
        if auto.vendor then table.insert(parts, part(" from ")); table.insert(parts, part(Names:DescribeNPC(auto.vendor), "npc")) end
        add("buy", withAt(parts), { item = auto.item, count = auto.count or 1 })
    elseif verb == "vendor" then
        local action = auto.action == "repair" and "Repair" or (auto.action == "sell and repair" and "Sell and repair") or "Sell your junk"
        local parts = { part(action) }
        if auto.vendor then table.insert(parts, part(" at ")); table.insert(parts, part(Names:DescribeNPC(auto.vendor), "npc")) end
        add("vendor", withAt(parts))
    elseif verb == "gather" then
        local parts = { part("Gather "), part(countText, "count"), part(Names:DescribeItem(auto.item), "item", auto.item) }
        if auto.skill then table.insert(parts, part(" with ")); table.insert(parts, part(auto.skill, "item")) end
        add("gather", withAt(parts), { item = auto.item, count = auto.count or 1 })
    elseif verb == "equip" then
        add("equip", withAt({ part("Equip "), part(Names:DescribeItem(auto.item), "item", auto.item) }), { equipped = auto.item })
    elseif verb == "reputation" then
        add("reputation", withAt({ part("Reach "), part(Names:DescribeStanding(auto.standing), "count"), part(" with "), part(Names:DescribeFaction(auto.faction), "npc") }),
            { reputation = { faction = auto.faction, standing = auto.standing } })
    elseif verb == "hearth" then
        add("hearth", { part("Set your hearthstone at "), part(auto.name, "location") }, { observed = node.completion and node.completion.observed })
    elseif verb == "flight" then
        add("flight", { part("Learn the "), part(auto.name, "location"), part(" flight path") }, { observed = node.completion and node.completion.observed })
    elseif verb == "track" then
        add("reminder", { part("Meanwhile: "), part(Names:DescribeQuest(auto.track), "quest") }, { quest = auto.track })
    elseif verb == "untrack" then
        add("reminder", { part("Done tracking "), part(Names:DescribeQuest(auto.untrack), "quest") }, { quest = auto.untrack })
    elseif verb == "interact" then
        add("interact", { part("Click "), part(auto.object, "location") })
    elseif verb == "travel" then
        add("travel", { part("Travel to "), part(auto.label, "location") }, { observed = node.completion and node.completion.observed })
    elseif verb == "level" then
        local parts = { part("Reach level "), part(tostring(auto.level), "count") }
        if type(auto.by) == "number" then table.insert(parts, part(" by step ")); table.insert(parts, part(tostring(auto.by), "count"))
        elseif auto.xp then table.insert(parts, part(" with ")); table.insert(parts, part(auto.xp .. " XP", "count")) end
        add("level", parts, { observed = node.completion and node.completion.observed })
    else
        add("note", { part(node.title or "") })
    end
    return goals
end

-- A quest the player never took, or abandoned: the goal reads "moot" instead
-- of "todo", so the tracker can say the work is not there rather than asking
-- for it. Only the client decides; before the quest log is readable it says no.
local function moot(Client, questID)
    return Client.IsQuestMoot ~= nil and Client:IsQuestMoot(questID) == true
end

-- "done", "active" (started, not finished), "todo", "moot" (the quest is not
-- the player's to work on), "failed" (an escort that can only be taken
-- again), or nil for a goal that has no state of its own,
-- such as "Talk to ...". The second value is the client's progress figure,
-- "2/8", when it has one.
function Steps:GoalStatus(goal, node)
    local Client = ns.modules.Client
    if not Client or not goal then return nil end
    -- Whichever comes first: the rank settles the goal before anything else
    -- is read, since past it the work is not wanted at all.
    if goal.upto and Client:HasSkillRank(goal.upto.skill, goal.upto.rank) then return "done" end
    if goal.objective then
        if Client:IsQuestObjectiveComplete(goal.objective.quest, goal.objective.index) then return "done" end
        local _, text = Client:GetQuestObjective(goal.objective.quest, goal.objective.index)
        local have, need
        if type(text) == "string" then have, need = text:match("(%d+)%s*/%s*(%d+)") end
        local progress = have and (have .. "/" .. need) or nil
        if Client:IsQuestInLog(goal.objective.quest) then return "active", progress end
        return moot(Client, goal.objective.quest) and "moot" or "todo", progress
    end
    -- The escorted NPC died, or the escort timed out: the quest stays in the
    -- log but can never be ready, so waiting on it would wait forever.
    if goal.escort and Client.IsQuestFailed and Client:IsQuestFailed(goal.quest) then return "failed" end
    if goal.quest and goal.state then
        local inLog, finished = Client:IsQuestInLog(goal.quest), Client:IsQuestComplete(goal.quest)
        if goal.state == "finished" then
            if finished then return "done" end
            if inLog then return Client:IsQuestReadyToTurnIn(goal.quest) and "active" or "todo" end
            return moot(Client, goal.quest) and "moot" or "todo"
        elseif goal.state == "acceptedOrFinished" then
            -- An accept is never moot: the quest is there to be taken.
            return (inLog or finished) and "done" or "todo"
        elseif goal.state == "readyToTurnIn" then
            if finished or Client:IsQuestReadyToTurnIn(goal.quest) then return "done" end
            if inLog then return "active" end
            return moot(Client, goal.quest) and "moot" or "todo"
        end
    end
    if goal.item then
        local have, need = Client:GetItemCount(goal.item), goal.count or 1
        local progress = need > 1 and (math.min(have, need) .. "/" .. need) or nil
        if have >= need then return "done", progress end
        if goal.quest and goal.startsQuest then
            -- The item was used: the quest it begins is in the log or done.
            if Client:IsQuestInLog(goal.quest) or Client:IsQuestComplete(goal.quest) then return "done", progress end
        elseif goal.quest then
            if Client:IsQuestComplete(goal.quest) or Client:IsQuestReadyToTurnIn(goal.quest) then return "done", progress end
            if moot(Client, goal.quest) then return "moot", progress end
        end
        return have > 0 and "active" or "todo", progress
    end
    if goal.skill then
        local rank, maxRank = Client:GetSkillRank(goal.skill.name)
        local need = tonumber(goal.skill.atLeast) or 1
        if rank == nil then return "todo" end
        local progress = need > 1 and (math.min(rank, need) .. "/" .. need) or (maxRank and (rank .. "/" .. maxRank) or nil)
        if rank >= need then return "done", progress end
        return "active", progress
    end
    if goal.spells then
        local known = 0
        for _, id in ipairs(goal.spells) do
            if Client:IsSpellKnown(id) then known = known + 1 end
        end
        local need = #goal.spells
        local progress = need > 1 and (known .. "/" .. need) or nil
        if known >= need then return "done", progress end
        return known > 0 and "active" or "todo", progress
    end
    if goal.casts then
        local have, need = self:CastCount(node), goal.casts.count or 1
        local progress = need > 1 and (math.min(have, need) .. "/" .. need) or nil
        if have >= need then return "done", progress end
        return have > 0 and "active" or "todo", progress
    end
    if goal.crafted then
        local need = goal.crafted.count or 1
        local have = math.max(self:CraftCount(node), Client:GetItemCount(goal.crafted.item))
        local progress = need > 1 and (math.min(have, need) .. "/" .. need) or nil
        if have >= need then return "done", progress end
        return have > 0 and "active" or "todo", progress
    end
    if goal.equipped then
        if Client:IsItemEquipped(goal.equipped) then return "done" end
        -- In the bags but not on: the work left is one click, not a hunt.
        return Client:GetItemCount(goal.equipped) > 0 and "active" or "todo"
    end
    if goal.reputation then
        local standing, value, ceiling = Client:GetFactionStanding(goal.reputation.faction)
        local need = tonumber(goal.reputation.standing) or 8
        if standing == nil then return "todo" end
        local Names = ns.modules.Names
        local progress = Names:DescribeStanding(standing)
        if ceiling and ceiling > 0 then progress = progress .. " " .. tostring(value) .. "/" .. tostring(ceiling) end
        if standing >= need then return "done", progress end
        return "active", progress
    end
    if goal.kills then
        local have, need = self:KillCount(node), goal.kills.count or 1
        local progress = need > 1 and (math.min(have, need) .. "/" .. need) or nil
        if have >= need then return "done", progress end
        return have > 0 and "active" or "todo", progress
    end
    if goal.observed then
        if Client:MatchesObservedCompletion(goal.observed, node and node.location, node and node.index) then return "done" end
        -- A level to reach says what it still takes: the experience, and
        -- about how many kills at what the last few were worth.
        local Experience = ns.modules.Experience
        if goal.observed.type == "level" and Experience then
            local progress = Experience:Progress(goal.observed, node and node.index)
            if progress then return "active", progress end
        end
        return "todo"
    end
    -- "Talk to ..." on a quest visit is judged by the quests it is there for,
    -- the way the target strip already judges a quest NPC: talking is not
    -- turning in, and a dialog closed without handing the quest over leaves
    -- the visit outstanding. Having talked still shows as work under way.
    -- Without a readable quest log there is nothing to judge the visit by, so
    -- the dialog is all the evidence there is and the rule below stands.
    if goal.settles and Client.IsQuestInLog then
        for _, settle in ipairs(goal.settles) do
            local state = self:GoalStatus({ quest = settle.quest, state = settle.state }, node)
            if state ~= "done" and state ~= "moot" then
                return (goal.npcs and self:HasTalkedTo(node, goal.npcs)) and "active" or nil
            end
        end
        return "done"
    end
    -- A plain "Talk to ..." with no quest behind it has no state of its own
    -- until a dialog with that NPC was seen.
    if goal.npcs and self:HasTalkedTo(node, goal.npcs) then return "done" end
    return nil
end

local function fmtCoord(at)
    local x, y = at[1] or 0, at[2] or 0
    if x <= 1 and y <= 1 then x, y = x * 100, y * 100 end
    return string.format("%.1f, %.1f", x, y)
end

-- Coordinates above 1 are percentages, as Wowhead prints them.
local function normalize(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if x > 1 or y > 1 then return x / 100, y / 100 end
    return x, y
end

-- `at` is one point or a list of them: the first is the arrow's target and
-- the rest are map pins. A `map` on the point, or on the list, overrides the
-- section's map for that step alone.
-- The guide's places while Expand runs, so a step's `at = "cave.chamber"`
-- can be looked up.
local expandingPlaces
-- The guide's NPCs (`names.npcs`) and its map while Expand runs, so a visit
-- with no `at` of its own goes where the NPC stands.
local expandingNPCs, expandingMap

-- `{ "Tonga Runetotem", at = { 52.26, 31.93 }, note = "..." }` for an NPC the
-- guide visits; a monster is its name alone.
local function npcEntry(id)
    local entry = expandingNPCs and expandingNPCs[id]
    return type(entry) == "table" and entry or nil
end

-- "cave.chamber" (or "cave.3") -> the place and its point, or nil.
function Steps.FindPlacePoint(places, reference)
    if type(reference) ~= "string" then return nil end
    local placeID, pointRef = reference:match("^([^%.]+)%.(.+)$")
    if not placeID then return nil end
    for _, place in ipairs(type(places) == "table" and places or {}) do
        if type(place) == "table" and place.place == placeID and type(place.points) == "table" then
            local index = tonumber(pointRef)
            if not index then
                for candidate, point in ipairs(place.points) do
                    if type(point) == "table" and point.id == pointRef then index = candidate end
                end
            end
            local point = index and place.points[index]
            if type(point) == "table" then return place, point, index end
        end
    end
    return nil
end

local function placeLocation(step, verb, defaultMap)
    local place, point = Steps.FindPlacePoint(expandingPlaces, step.at)
    if not place then error("NuuRoad: no place point '" .. step.at .. "'") end
    local x, y = normalize(point.at and point.at[1], point.at and point.at[2])
    if not x then error("NuuRoad: place point '" .. step.at .. "' has no position") end
    return { mapID = point.map or place.map or defaultMap, x = x, y = y,
        arrivalRadiusNormalized = step.radius or radiusByVerb[verb], point = step.at }
end

local function location(step, verb, defaultMap)
    local at = step.at
    if type(at) == "string" then return placeLocation(step, verb, defaultMap) end
    if type(at) ~= "table" then return nil end
    local points, mapID = at, at.map or defaultMap
    if type(at[1]) ~= "table" then points = { at } end
    local x, y = normalize(points[1] and points[1][1], points[1] and points[1][2])
    if not x then return nil end
    mapID = (points[1].map) or mapID
    local spots
    for index = 2, #points do
        local sx, sy = normalize(points[index][1], points[index][2])
        if sx and sy then
            spots = spots or {}
            table.insert(spots, { x = sx, y = sy })
        end
    end
    -- The arrow takes whichever point is nearest; `loop` is kept only to say
    -- the points are a circuit, which changes nothing now.
    -- `near` says which part of a guide place the spot belongs to, so the
    -- planner joins it to that point's passages rather than guessing by
    -- distance (two levels of a cave can lie over each other on the map).
    local near = step.near
    if near ~= nil and not Steps.FindPlacePoint(expandingPlaces, near) then
        error("NuuRoad: no place point '" .. tostring(near) .. "'")
    end
    return { mapID = mapID, x = x, y = y, arrivalRadiusNormalized = step.radius or radiusByVerb[verb],
        spots = spots, loop = step.loop and true or nil, near = near }
end

local function questCompletion(state, ids, match)
    return { type = "observed", observed = { type = "quests", state = state, match = match, ids = ids } }
end

-- "Warrior or Shaman", "not Tauren", "Horde", "quest 858", "not quest 858 or Orc",
-- and one keyword per registered predicate: "season 2", "skill Mining 75",
-- "item 2495", "equipped 2495", "spell 8017", "level 10", "gold 5000",
-- "reputation 576 Honored", "profession Skinning", "zone 1412", "hardcore",
-- "instance". Positive terms are OR-ed, negated terms AND-ed, and `|`
-- separates groups so "not Warrior | not Druid" means neither.
--
-- Every keyword here names a predicate API/Client.lua registers. Adding a
-- condition is one entry in this table and one RegisterPredicate call; the
-- `when` field below is the escape hatch for the one-off that never will be.
local conditionTerms = {
    { "^quest%s+(%d+)%s+(%a+)$", function(id, state)
        local states = { accepted = "accepted", finished = "finished", readytoturnin = "readyToTurnIn" }
        local resolved = states[state:lower()]
        if not resolved then error("NuuRoad: unknown quest state '" .. state .. "'") end
        return { type = "quest", id = tonumber(id), state = resolved }
    end },
    { "^quest%s+(%d+)$", function(id) return { type = "quest", id = tonumber(id) } end },
    { "^season%s+(%d+)$", function(id) return { type = "season", id = tonumber(id) } end },
    { "^season$", function() return { type = "season" } end },
    { "^hardcore$", function() return { type = "hardcore" } end },
    { "^instance$", function() return { type = "instance" } end },
    { "^level%s+(%d+)$", function(level) return { type = "level", atLeast = tonumber(level) } end },
    { "^experience%s+(%d+)$", function(xp) return { type = "experience", atLeast = tonumber(xp) } end },
    { "^gold%s+(%d+)$", function(copper) return { type = "gold", atLeast = tonumber(copper) } end },
    { "^item%s+(%d+)%s+x(%d+)$", function(id, count) return { type = "item", id = tonumber(id), count = tonumber(count) } end },
    { "^item%s+(%d+)$", function(id) return { type = "item", id = tonumber(id) } end },
    { "^equipped%s+(%d+)$", function(id) return { type = "equippedItem", id = tonumber(id) } end },
    { "^spell%s+(%d+)$", function(id) return { type = "spell", id = tonumber(id) } end },
    { "^zone%s+(%d+)$", function(mapID) return { type = "zone", mapID = tonumber(mapID) } end },
    { "^skill%s+(.-)%s+(%d+)$", function(name, rank) return { type = "skill", name = name, atLeast = tonumber(rank) } end },
    { "^skill%s+(.+)$", function(name) return { type = "skill", name = name } end },
    { "^profession%s+(.+)$", function(name) return { type = "profession", name = name } end },
    { "^hearth%s+(.+)$", function(name) return { type = "hearth", name = name } end },
    { "^subzone%s+(.+)$", function(name) return { type = "subzone", name = name } end },
    { "^aura%s+(%d+)$", function(id) return { type = "aura", id = tonumber(id) } end },
    { "^cooldown%s+item%s+(%d+)$", function(id) return { type = "cooldown", id = tonumber(id), kind = "item" } end },
    { "^cooldown%s+(%d+)$", function(id) return { type = "cooldown", id = tonumber(id) } end },
    { "^xprate%s+<%s*([%d%.]+)$", function(rate) return { type = "xprate", below = tonumber(rate) } end },
    { "^xprate%s+>=?%s*([%d%.]+)$", function(rate) return { type = "xprate", atLeast = tonumber(rate) } end },
    { "^auctionhouse$", function() return { type = "auctionHouse" } end },
    { "^selffound$", function() return { type = "selfFound" } end },
    -- "slot 16 dps < 4.2": what the player already wears is worse than this.
    { "^slot%s+(%d+)%s+(%a+)%s*<%s*([%d%.]+)$", function(slot, stat, value)
        return { type = "slot", slot = tonumber(slot), stat = stat:lower(), below = tonumber(value) }
    end },
    { "^slot%s+(%d+)%s+(%a+)%s*>=?%s*([%d%.]+)$", function(slot, stat, value)
        return { type = "slot", slot = tonumber(slot), stat = stat:lower(), atLeast = tonumber(value) }
    end },
    { "^reputation%s+(%d+)%s+(.+)$", function(factionID, standing)
        local value = ns.modules.Names and ns.modules.Names:StandingValue(standing)
        if not value then error("NuuRoad: unknown reputation standing '" .. standing .. "'") end
        return { type = "reputation", factionID = tonumber(factionID), standing = value }
    end },
}

-- Keywords keep the author's capitalization, because a skill is named, not
-- tokenized; only the bare class, race, and faction words are folded.
local unpackList = table.unpack or unpack

local function parseTerm(piece)
    for _, term in ipairs(conditionTerms) do
        local captures = { piece:match(term[1]) }
        if captures[1] ~= nil then return term[2](unpackList(captures, 1, term[3] or #captures)) end
    end
    local body = piece:lower()
    if factionTokens[body] then return { type = "faction", values = { factionTokens[body] } } end
    if classTokens[body] then return { type = "class", values = { classTokens[body] } } end
    if raceTokens[body] then return { type = "race", values = { raceTokens[body] } } end
    error("NuuRoad: unknown condition term '" .. piece .. "'")
end

-- One term, with its `not` and `now` in front: "not quest 858", "now item
-- 247840", "not now aura 1254832".
local function parsePiece(piece)
    local negated = piece:match("^not%s+(.+)$")
    local body = negated or piece
    local now = body:match("^now%s+(.+)$")
    local predicate = parseTerm(now or body)
    if now then predicate = { type = "now", child = predicate } end
    if negated then predicate = { type = "not", child = predicate } end
    return predicate, negated ~= nil
end

-- `|` joins groups that must all hold; ` or ` joins the terms of one group,
-- any of which will do. Inside a group the negated terms are AND-ed, so
-- "not Tauren or Orc" is an Orc who is not a Tauren.
local function parseGroup(text)
    local positives, negatives = {}, {}
    for piece in (text .. " or "):gmatch("(.-) or ") do
        piece = piece:gsub("^%s+", ""):gsub("%s+$", "")
        local predicate, negated = parsePiece(piece)
        table.insert(negated and negatives or positives, predicate)
    end
    local parts = {}
    if #positives == 1 then table.insert(parts, positives[1]) elseif #positives > 1 then table.insert(parts, { type = "any", children = positives }) end
    for _, negative in ipairs(negatives) do table.insert(parts, negative) end
    return parts
end

local function parseCondition(text)
    if type(text) == "table" then return text end
    if type(text) ~= "string" then return nil end
    local parts = {}
    for group in text:gmatch("[^|]+") do
        group = group:gsub("^%s+", ""):gsub("%s+$", "")
        for _, part in ipairs(parseGroup(group)) do table.insert(parts, part) end
    end
    if #parts == 0 then return nil end
    if #parts == 1 then return parts[1] end
    return { type = "all", children = parts }
end

-- `only` and `when` are AND-ed: the keywords say what they can, the expression
-- says the rest. `when` is a Lua expression stored as a string and evaluated in
-- the client's sandbox; see the Lua fallback in API/Client.lua.
local function conditionOf(source)
    local condition = parseCondition(source.only)
    if source.when == nil then return condition end
    if type(source.when) ~= "string" or source.when == "" then
        error("NuuRoad: `when` is a Lua expression written as a string")
    end
    local expression = { type = "lua", body = source.when }
    if not condition then return expression end
    return { type = "all", children = { condition, expression } }
end

-- Renders a predicate back into the `only` text that produced it, so the
-- editor can show and re-parse a condition instead of dropping it. A `lua`
-- predicate is not `only` text and comes back separately.
function Steps:DescribeCondition(predicate)
    if type(predicate) ~= "table" then return nil end
    local kind = predicate.type
    if kind == "not" then
        local child = self:DescribeCondition(predicate.child)
        return child and ("not " .. child) or nil
    end
    if kind == "now" then
        local child = self:DescribeCondition(predicate.child)
        return child and ("now " .. child) or nil
    end
    if kind == "any" or kind == "all" then
        local parts = {}
        for _, child in ipairs(predicate.children or {}) do
            local text = self:DescribeCondition(child)
            if text then table.insert(parts, text) end
        end
        if #parts == 0 then return nil end
        return table.concat(parts, kind == "any" and " or " or " | ")
    end
    if kind == "lua" then return nil end
    if kind == "class" or kind == "race" or kind == "faction" then
        local names = {}
        for _, value in ipairs(predicate.values or {}) do
            table.insert(names, tostring(value):sub(1, 1):upper() .. tostring(value):sub(2):lower())
        end
        return table.concat(names, " or ")
    end
    if kind == "quest" then
        return "quest " .. tostring(predicate.id) .. (predicate.state and (" " .. predicate.state) or "")
    end
    if kind == "season" then return predicate.id and ("season " .. predicate.id) or "season" end
    if kind == "hardcore" then return "hardcore" end
    if kind == "instance" then return "instance" end
    if kind == "level" then return "level " .. tostring(predicate.atLeast) end
    if kind == "experience" then return "experience " .. tostring(predicate.atLeast) end
    if kind == "gold" then return "gold " .. tostring(predicate.atLeast) end
    if kind == "item" then
        return "item " .. tostring(predicate.id) .. (predicate.count and predicate.count > 1 and (" x" .. predicate.count) or "")
    end
    if kind == "equippedItem" then return "equipped " .. tostring(predicate.id) end
    if kind == "spell" then return "spell " .. tostring(predicate.id) end
    if kind == "zone" then return "zone " .. tostring(predicate.mapID) end
    if kind == "skill" then
        return "skill " .. tostring(predicate.name) .. (predicate.atLeast and (" " .. predicate.atLeast) or "")
    end
    if kind == "profession" then return "profession " .. tostring(predicate.name) end
    if kind == "hearth" then return "hearth " .. tostring(predicate.name) end
    if kind == "subzone" then return "subzone " .. tostring(predicate.name) end
    if kind == "aura" then return "aura " .. tostring(predicate.id) end
    if kind == "cooldown" then
        return "cooldown " .. (predicate.kind == "item" and "item " or "") .. tostring(predicate.id)
    end
    if kind == "xprate" then
        return "xprate " .. (predicate.below and ("< " .. predicate.below) or (">= " .. tostring(predicate.atLeast)))
    end
    if kind == "auctionHouse" then return "auctionhouse" end
    if kind == "selfFound" then return "selffound" end
    if kind == "slot" then
        return "slot " .. tostring(predicate.slot) .. " " .. tostring(predicate.stat) .. " "
            .. (predicate.below and ("< " .. predicate.below) or (">= " .. tostring(predicate.atLeast)))
    end
    if kind == "reputation" then
        local standing = ns.modules.Names and ns.modules.Names:DescribeStanding(predicate.standing) or predicate.standing
        return "reputation " .. tostring(predicate.factionID) .. " " .. tostring(standing)
    end
    return nil
end

-- Keeps a carried step's completion in step with the step it rides along
-- with. The import builds this once; the editor needs it again whenever an
-- author changes which step carries this one.
function Steps:ApplyCarried(node)
    local observed = node.completion and node.completion.type == "observed" and node.completion.observed
    local own = observed
    -- The step's own completion, with the carried half (a `step` child that
    -- ApplyCarried put there) taken off. An `any` with no such child is the
    -- step's own (an item or a rank, from `upto`) and is kept whole, so
    -- saving such a step keeps the item.
    if observed and observed.type == "any" and observed.children then
        local rest, carried = {}, false
        for _, child in ipairs(observed.children) do
            if child.type == "step" then carried = true else table.insert(rest, child) end
        end
        if carried then
            own = #rest > 1 and { type = "any", children = rest } or rest[1]
        end
    elseif observed and observed.type == "step" then
        own = nil
    end
    if not node.companionOf then
        node.completion = own and { type = "observed", observed = own } or { type = "manual" }
        return
    end
    local carried = { type = "step", index = node.companionOf }
    node.completion = { type = "observed", observed = own
        and { type = "any", children = { own, carried } } or carried }
end

-- The editor's write-back: the same two fields an author writes, parsed the
-- same way, so what the editor saves and what a packaged guide ships are one
-- format. Raises on a term it does not know; the caller reports that.
function Steps:ParseCondition(onlyText, whenText)
    local source = {}
    if type(onlyText) == "string" and onlyText:match("%S") then source.only = onlyText end
    if type(whenText) == "string" and whenText:match("%S") then source.when = whenText end
    if source.only == nil and source.when == nil then return nil end
    return conditionOf(source)
end

-- The `when` expression behind a condition, wherever it sits in the tree.
function Steps:LuaCondition(predicate)
    if type(predicate) ~= "table" then return nil end
    if predicate.type == "lua" then return predicate.body end
    if predicate.type == "not" or predicate.type == "now" then return self:LuaCondition(predicate.child) end
    for _, child in ipairs(predicate.children or {}) do
        local body = self:LuaCondition(child)
        if body then return body end
    end
    return nil
end

local function build(step, verb, defaultMap)
    local node = { kind = "action", completion = { type = "manual" } }
    local quests
    if verb == "note" then
        node.kind, node.title, node.body = "note", "Note", step.note
    elseif verb == "finish" then
        node.kind, node.title, node.body = "end", "Guide complete", step.finish
    elseif verb == "travel" then
        node.kind = "travel"
        node.auto = { verb = verb, label = type(step.travel) == "string" and step.travel or fmtCoord(step.at) }
        -- Arrival is normally a coordinate, but a zone or a subzone is what
        -- the player actually crosses into, and the client names those. A
        -- dungeon has no map the client reports, only its instance ID.
        if type(step.instance) == "number" then
            node.completion = { type = "observed", observed = { type = "instance", instanceID = step.instance } }
        elseif type(step.subzone) == "string" then
            node.completion = { type = "observed", observed = { type = "subzone", name = step.subzone } }
        elseif type(step.zone) == "number" then
            node.completion = { type = "observed", observed = { type = "zone", mapID = step.zone } }
        elseif type(step.zone) == "string" then
            node.completion = { type = "observed", observed = { type = "zone", name = step.zone } }
        else
            node.completion = { type = "observed", observed = { type = "location" } }
        end
    elseif verb == "accept" then
        quests = list(step.accept)
        node.kind, node.completion = "acceptQuest", questCompletion("acceptedOrFinished", quests, "all")
    elseif verb == "turnin" then
        quests = list(step.turnin)
        node.kind, node.completion = "turnInQuest", questCompletion("finished", quests, "all")
    elseif verb == "talk" then
        local turnin, accept = list(step.turnin), list(step.accept)
        node.kind = "talk"
        node.auto = { verb = verb, turnin = turnin, accept = accept }
        if #turnin + #accept > 0 then
            quests = {}
            for _, id in ipairs(turnin) do table.insert(quests, id) end
            for _, id in ipairs(accept) do table.insert(quests, id) end
            node.completion = { type = "observed", observed = { type = "all", children = {
                { type = "quests", state = "finished", match = "all", ids = turnin },
                { type = "quests", state = "acceptedOrFinished", match = "all", ids = accept },
            } } }
        elseif step.npc == nil then
            error("NuuRoad: a talk step with no quests names its NPC")
        end
    elseif verb == "objective" and step.part then
        quests = list(step.objective)
        node.kind = step.collect and "collect" or (step.kill and "kill") or (step.object and "interact") or "questObjective"
        node.completion = { type = "observed", observed = { type = "objective", questID = quests[1], index = step.part } }
        -- The NPC is carried so an objective that is really a conversation can
        -- say so when the client has no objective line to give.
        node.auto = { verb = verb, quests = quests, part = step.part,
            npc = step.npc and list(step.npc) or nil }
    elseif verb == "objective" or verb == "objectives" then
        quests = list(step[verb])
        node.kind = verb == "objective" and "questObjective" or "objectiveGroup"
        node.completion = questCompletion("readyToTurnIn", quests, step.any and "any" or "all")
        if step.any then for _, id in ipairs(list(step.any)) do table.insert(quests, id) end end
    elseif verb == "escort" then
        -- Follow and guard an NPC to `at`. Done the way an objective is, once
        -- the quest is ready to hand in; the NPC is named, since "Escort" is
        -- the whole instruction, and followed like any step's NPC.
        if type(step.escort) ~= "number" then error("NuuRoad: escort names one quest by ID") end
        if step.npc == nil then error("NuuRoad: an escort step names the NPC escorted in `npc`") end
        quests = { step.escort }
        node.kind = "escort"
        node.completion = questCompletion("readyToTurnIn", quests, "all")
        node.auto = { verb = verb, quests = quests, npc = list(step.npc) }
    elseif verb == "collect" then
        node.kind = "collect"
        node.auto = { verb = verb, collect = list(step.collect), count = step.count, starts = step.starts, quest = step.quest }
        -- An item that begins a quest is also done once that quest was ever
        -- accepted; a quest item is done once its quest is finished, and moot
        -- when the player has no such quest. Both tie the step to the quest
        -- log, so the resume scan can judge it instead of passing it over.
        node.completion = { type = "observed", observed = {
            type = "item", itemID = list(step.collect)[1], count = step.count or 1,
            startsQuestID = step.starts, questID = step.quest,
        } }
        if step.starts or step.quest then node.refs = { quests = { step.starts or step.quest } } end
    elseif verb == "kill" then
        node.kind = "kill"
        node.auto = { verb = verb, kill = list(step.kill), count = step.count }
        node.completion = { type = "observed", observed = { type = "kills", npcs = list(step.kill), count = step.count or 1 } }
    elseif verb == "train" then
        -- No rank given means "learn it at all": rank 1 is the first point in
        -- a skill the player does not have yet.
        node.kind = "train"
        node.auto = { verb = verb, skill = step.train, rank = step.rank }
        node.completion = { type = "observed", observed = { type = "skill", name = step.train, atLeast = step.rank or 1 } }
    elseif verb == "learn" then
        -- A class spell (or its next rank) from a trainer: done once the
        -- client knows every spell named. Professions are `train`, by name.
        local spells = list(step.learn)
        for _, id in ipairs(spells) do
            if type(id) ~= "number" then error("NuuRoad: learn names spells by ID") end
        end
        node.kind = "train"
        node.auto = { verb = verb, spells = spells, trainer = step.npc and list(step.npc)[1] or nil }
        node.completion = { type = "observed", observed = { type = "spell", ids = spells } }
    elseif verb == "cast" then
        -- A spell to cast here, such as Skysight beside a convergence: counted
        -- from the casts made while the guide is on the step.
        if type(step.cast) ~= "number" then error("NuuRoad: cast names one spell by ID") end
        if step.count ~= nil and (type(step.count) ~= "number" or step.count < 1) then error("NuuRoad: a cast count must be a positive number") end
        node.kind = "cast"
        node.auto = { verb = verb, spell = step.cast, count = step.count }
        node.completion = { type = "observed", observed = { type = "cast", spellID = step.cast, count = step.count or 1 } }
    elseif verb == "skill" then
        if type(step.rank) ~= "number" then error("NuuRoad: a skill step needs a rank") end
        node.kind = "skillTarget"
        node.auto = { verb = verb, skill = step.skill, rank = step.rank }
        node.completion = { type = "observed", observed = { type = "skill", name = step.skill, atLeast = step.rank } }
    elseif verb == "craft" then
        node.kind = "craft"
        node.auto = { verb = verb, item = step.craft, count = step.count, skill = step.skill }
        node.completion = { type = "observed", observed = { type = "crafted", itemID = step.craft, count = step.count or 1 } }
        node.refs = { items = { step.craft } }
    elseif verb == "skillup" then
        -- Crafting for the rank, the way a profession guide really reads:
        -- keep making them until the skill lands, however many that turns out
        -- to be. Use `craft` with a count when the output is the point.
        if type(step.skill) ~= "string" or type(step.rank) ~= "number" then
            error("NuuRoad: a skillup step needs a skill and a rank")
        end
        node.kind = "skillUp"
        node.auto = { verb = verb, item = step.skillup, skill = step.skill, rank = step.rank }
        node.completion = { type = "observed", observed = { type = "skill", name = step.skill, atLeast = step.rank } }
        node.refs = { items = { step.skillup } }
    elseif verb == "gather" then
        -- Picking it is the usual way; the auction house is the other one, so
        -- the step says both and completes on the item either way.
        node.kind = "gather"
        node.auto = { verb = verb, item = step.gather, count = step.count, skill = step.skill }
        node.completion = { type = "observed", observed = { type = "item", itemID = step.gather, count = step.count or 1 } }
        node.refs = { items = { step.gather } }
    elseif verb == "buy" then
        node.kind = "buy"
        -- One named vendor, since stock differs from one to the next.
        local vendor = list(step.npc)[1]
        node.auto = { verb = verb, item = step.buy, count = step.count, vendor = vendor }
        node.completion = { type = "observed", observed = { type = "item", itemID = step.buy, count = step.count or 1 } }
        node.refs = { items = { step.buy } }
    elseif verb == "vendor" then
        -- Selling and repairing are the player's business; the step only says
        -- where, so it is theirs to tick off.
        node.kind = "vendor"
        node.auto = { verb = verb, vendor = list(step.npc)[1], action = step.vendor }
    elseif verb == "equip" then
        node.kind = "equip"
        node.auto = { verb = verb, item = step.equip }
        node.completion = { type = "observed", observed = { type = "equipped", itemID = step.equip } }
        node.refs = { items = { step.equip } }
    elseif verb == "reputation" then
        local standing = ns.modules.Names:StandingValue(step.standing)
        if not standing then error("NuuRoad: a reputation step needs a standing such as 'Honored'") end
        node.kind = "reputationTarget"
        node.auto = { verb = verb, faction = step.reputation, standing = standing }
        node.completion = { type = "observed", observed = { type = "reputation", factionID = step.reputation, standing = standing } }
    elseif verb == "hearth" then
        node.kind = "hearth"
        node.auto = { verb = verb, name = step.hearth }
        node.completion = { type = "observed", observed = { type = "hearth", name = step.hearth } }
    elseif verb == "flight" then
        node.kind = "flight"
        node.auto = { verb = verb, name = step.flight }
        node.completion = { type = "observed", observed = { type = "flightpath", name = step.flight } }
    elseif verb == "track" or verb == "untrack" then
        node.kind = "reminder"
        node.auto = { verb = verb, track = step.track, untrack = step.untrack }
        node.completion = { type = "observed", observed = { type = "always" } }
        node.refs = { quests = { step.track or step.untrack } }
    elseif verb == "interact" then
        node.kind = "interact"
        node.auto = { verb = verb }
    elseif verb == "level" then
        node.kind = "levelTarget"
        node.auto = { verb = verb, level = step.level, xp = step.xp }
        node.completion = { type = "observed", observed = { type = "level", atLeast = step.level, xp = step.xp } }
        if step.by ~= nil then
            if type(step.by) ~= "string" or step.by == "" then error("NuuRoad: `by` names the step the level is needed by") end
            if step.xp ~= nil then error("NuuRoad: with `by`, the level is the one needed at that step; leave out `xp`") end
            -- Resolved to a position once every label is known.
            node.auto.by, node.completion.observed.by = step.by, step.by
        end
    elseif verb == "choice" then
        node.kind, node.title, node.choices = "choice", step.choice, {}
        for _, option in ipairs(step.options or {}) do
            table.insert(node.choices, { title = option[1] or option.title, ["next"] = option.goto })
        end
    end
    if quests then
        node.auto = node.auto or { verb = verb, quests = quests }
        node.refs = { quests = quests }
    end
    -- The quest a travel, buy, or escort step's work is for (the objective
    -- verb and a collect step read `quest` themselves). `{ id, n }` is one
    -- objective: the step is done when the client says it is, and a travel
    -- step only then, since the arrival starts a scene the objective ends.
    -- A whole quest finishes the step once it is ready to hand in.
    if step.quest ~= nil and verb ~= "objective" and verb ~= "collect" then
        local finishes
        if type(step.quest) == "table" and type(step.quest[1]) == "number" and type(step.quest[2]) == "number" then
            finishes = { type = "objective", questID = step.quest[1], index = step.quest[2] }
        elseif type(step.quest) == "number" then
            finishes = { type = "quests", state = "readyToTurnIn", match = "all", ids = { step.quest } }
        else
            error("NuuRoad: quest is a quest ID or { quest, objective }")
        end
        local own = node.completion.type == "observed" and node.completion.observed
        if verb == "travel" and finishes.type == "objective" or not own then
            node.completion = { type = "observed", observed = finishes }
        else
            node.completion = { type = "observed", observed = { type = "any", children = { own, finishes } } }
        end
        node.refs = node.refs or {}
        node.refs.quests = node.refs.quests or {}
        table.insert(node.refs.quests, finishes.questID or step.quest)
    end
    if node.auto then
        node.auto.object = step.object
        node.auto.count = node.auto.count or step.count
        if step.kill then node.auto.kill = list(step.kill) end
        if step.collect and verb ~= "collect" then node.auto.collect = list(step.collect) end
    end
    if step.kill then
        node.refs = node.refs or {}
        node.refs.npcs = list(step.kill)
    end
    if step.collect and verb ~= "collect" then
        node.refs = node.refs or {}
        node.refs.items = list(step.collect)
    end
    if step.npc then
        node.refs = node.refs or {}
        node.refs.npcs = list(step.npc)
    end
    if step.item then
        node.refs = node.refs or {}
        node.refs.items = list(step.item)
    end
    local escape = uptoRank(step)
    if escape then
        local observed = node.completion and node.completion.type == "observed" and node.completion.observed
        if not observed then error("NuuRoad: upto needs a step the client can judge on its own") end
        node.completion = { type = "observed", observed = { type = "any", children = {
            observed,
            { type = "skill", name = escape.skill, atLeast = escape.rank },
        } } }
        if node.auto then node.auto.upto = escape end
    end
    node.needs = materials(step)
    if node.needs then
        node.refs = node.refs or {}
        local items = node.refs.items or {}
        local seen = {}
        for _, id in ipairs(items) do seen[id] = true end
        for _, material in ipairs(node.needs) do
            if not seen[material.itemID] then seen[material.itemID] = true; table.insert(items, material.itemID) end
        end
        node.refs.items = items
    end
    -- The item the step asks the player to press, which is not always the
    -- item the step is counting. Smashing looted Prospector's Picks at a
    -- forge is what yields the Broken Tools the quest wants: only the guide
    -- knows the pick is the thing to use, since the client cannot be asked
    -- "which of these does this step mean". It gates nothing and completes
    -- nothing - it puts the item in the item panel, where the player can
    -- reach it, and NuuRoad never presses it for them.
    if step.use ~= nil then
        node.use = list(step.use)
        for _, itemID in ipairs(node.use) do
            if type(itemID) ~= "number" then error("NuuRoad: `use` names items by ID") end
        end
        node.refs = node.refs or {}
        local items = node.refs.items or {}
        local seen = {}
        for _, id in ipairs(items) do seen[id] = true end
        for _, id in ipairs(node.use) do
            if not seen[id] then seen[id] = true; table.insert(items, id) end
        end
        node.refs.items = items
    end
    -- How long the step keeps the player waiting: a scene playing out, or a
    -- timed quest starting. Shown, never enforced.
    if step.wait ~= nil then
        node.wait = tonumber(step.wait)
        if not node.wait then error("NuuRoad: wait is a number of seconds") end
    end
    -- A step that stays on screen alongside the ones after it until it is done.
    if step.sticky then node.sticky = true end
    -- Creatures to mark and list as targets without their kills counting for
    -- anything: the mobs of a grind spot, a creature an item is used on.
    if step.mark ~= nil then
        node.mark = list(step.mark)
        for _, id in ipairs(node.mark) do
            if type(id) ~= "number" then error("NuuRoad: `mark` names creatures by ID") end
        end
    end
    -- The dialog options to pick on a talk step, by gossip option ID, one per
    -- page. Kept on the step; nothing picks them yet.
    if step.say ~= nil then
        node.say = list(step.say)
        for _, id in ipairs(node.say) do
            if type(id) ~= "number" then error("NuuRoad: `say` names gossip options by ID") end
        end
    end
    node.location = location(step, verb, defaultMap)
    -- A visit with no point of its own goes where the guide says the NPC
    -- stands, on the guide's map unless the point names another, and carries
    -- what the guide says about the NPC above the step's own note.
    local visited = type(step.npc) == "table" and step.npc[1] or step.npc
    local stands = npcEntry(visited)
    if stands and stands.at ~= nil and step.at == nil then
        node.location = location({ at = stands.at, radius = step.radius, near = step.near }, verb, expandingMap)
        if node.location then node.location.npc = visited end
    end
    node.condition = conditionOf(step)
    if verb ~= "note" and verb ~= "finish" and type(step.note) == "string" then node.body = step.note end
    if stands and type(stands.note) == "string" and verb ~= "note" and verb ~= "finish" then
        node.body = node.body and (stands.note .. "\n" .. node.body) or stands.note
    end
    if node.auto then node.title = Steps:Title(node, true) end
    return node, quests
end

local function copyTable(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = copyTable(child) end
    return copy
end

local function slug(text)
    return (tostring(text):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

-- Sections and groups are wrappers: neither adds a step of its own, and each
-- records a span over the flattened node list. That list is the only place a
-- step position is ever written down -- authors name labels, and the labels
-- are resolved to positions here.
function Steps:Expand(guide)
    if type(guide) ~= "table" then return guide end
    if type(guide.steps) ~= "table" then return ns.modules.Schema:IndexNodes(guide) end
    if guide.schema ~= 2 then error("NuuRoad: a guide must declare schema = 2") end
    if guide.names ~= nil then
        if type(guide.names) ~= "table" then error("NuuRoad: names must be a table of names by kind") end
        -- Before any title is written, since titles carry the names.
        ns.modules.Names:Add(guide.names)
    end
    local expanded = {}
    for key, value in pairs(guide) do
        if key ~= "steps" and key ~= "map" then expanded[key] = value end
    end
    expanded.sections, expanded.nodes, expanded.groups = {}, {}, {}
    expanded.condition = conditionOf(guide)
    -- Guide places keep their authored shape (it is also what the editor
    -- edits and what SavedVariables stores); each is copied and handed the
    -- guide's map when it names none, since the guide's own map key does not
    -- survive the expansion.
    if guide.places ~= nil then
        if type(guide.places) ~= "table" then error("NuuRoad: places must be a list of places") end
        expanded.places = {}
        for index, place in ipairs(guide.places) do
            if type(place) ~= "table" then error("NuuRoad: each place must be a table") end
            local copy = copyTable(place)
            if copy.map == nil then copy.map = guide.map end
            expanded.places[index] = copy
        end
    end
    expandingPlaces = expanded.places
    expandingNPCs, expandingMap = type(guide.names) == "table" and guide.names.npcs or nil, guide.map

    -- label -> the step it stands in front of, and the choice options waiting
    -- for it. Both are resolved once every step has a position.
    local labels, pending = {}, {}
    -- Steps carried alongside a later one. Resolved with the labels, since
    -- "next" and a label both name a position that is only known once every
    -- step has one.
    local companions = {}
    -- Steps carried from an earlier label until they are done or reached.
    local carriedFrom = {}
    local section

    local function claim(name, index)
        if name == nil then return end
        if type(name) ~= "string" or name == "" then error("NuuRoad: a label is a name") end
        if labels[name] then error("NuuRoad: two things are labelled '" .. name .. "'") end
        labels[name] = index
    end

    local function append(step, inGroup, sectionMap)
        if type(step) ~= "table" then error("NuuRoad: each step must be a table") end
        if step.id ~= nil then error("NuuRoad: steps are named by label, not by ID") end
        if step.next ~= nil or step.goto ~= nil then error("NuuRoad: steps run in order; branch with a choice") end
        local verb = verbOf(step)
        if not verb then error("NuuRoad: step has no supported verb") end
        local node = build(step, verb, sectionMap)
        if inGroup and not ns.modules.Schema:IsGroupMember(node) then
            error("NuuRoad: group members must be quest visits or quest objectives")
        end
        node.index = #expanded.nodes + 1
        node.label = step.label
        claim(step.label, node.index)
        if step.with ~= nil then
            if type(step.with) ~= "string" or step.with == "" then
                error("NuuRoad: `with` names the step this one is carried alongside")
            end
            table.insert(companions, { node = node, target = step.with })
        end
        if step.from ~= nil then
            if type(step.from) ~= "string" or step.from == "" then
                error("NuuRoad: `from` names the earlier step this one is carried from")
            end
            table.insert(carriedFrom, { node = node, target = step.from })
        end
        for _, choice in ipairs(node.choices or {}) do
            if type(choice["next"]) ~= "string" then error("NuuRoad: a choice goes to a label") end
            table.insert(pending, choice)
        end
        table.insert(expanded.nodes, node)
        table.insert(section.nodeIndexes, node.index)
    end

    local function appendGroup(wrapper, sectionMap)
        for key in pairs(wrapper) do
            if key ~= "group" and key ~= "label" then error("NuuRoad: a group wrapper only supports group and label") end
        end
        if type(wrapper.group) ~= "table" then error("NuuRoad: group must be an array of steps") end
        local count = 0
        for key in pairs(wrapper.group) do
            if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then error("NuuRoad: group must be an array") end
            count = count + 1
        end
        if count ~= #wrapper.group or count < 2 then error("NuuRoad: a group needs at least two steps") end
        local first = #expanded.nodes + 1
        for _, member in ipairs(wrapper.group) do
            if type(member) == "table" and (member.group ~= nil or member.section ~= nil) then
                error("NuuRoad: groups hold only steps")
            end
            append(member, true, sectionMap)
        end
        claim(wrapper.label, first)
        table.insert(expanded.groups, { first = first, last = #expanded.nodes })
    end

    for _, wrapper in ipairs(guide.steps) do
        if type(wrapper) ~= "table" or type(wrapper.section) ~= "string" or type(wrapper.steps) ~= "table" then
            error("NuuRoad: a guide is a list of sections, each with section and steps")
        end
        for key in pairs(wrapper) do
            if key ~= "section" and key ~= "steps" and key ~= "map" and key ~= "label" then
                error("NuuRoad: a section only supports section, steps, map, and label")
            end
        end
        section = { id = slug(wrapper.section), title = wrapper.section, nodeIndexes = {} }
        table.insert(expanded.sections, section)
        local sectionMap = wrapper.map or guide.map
        local first = #expanded.nodes + 1
        for _, step in ipairs(wrapper.steps) do
            if type(step) == "table" and step.group ~= nil then
                appendGroup(step, sectionMap)
            else
                append(step, false, sectionMap)
            end
        end
        if #section.nodeIndexes == 0 then error("NuuRoad: section '" .. wrapper.section .. "' has no steps") end
        claim(wrapper.label, first)
    end

    expandingPlaces, expandingNPCs, expandingMap = nil, nil, nil
    for _, choice in ipairs(pending) do
        local target = labels[choice["next"]]
        if not target then error("NuuRoad: no step is labelled '" .. tostring(choice["next"]) .. "'") end
        choice["next"] = target
    end
    -- A level step's `by`: the turn-ins between it and that step count
    -- towards the level (Domain/Experience.lua).
    for _, node in ipairs(expanded.nodes) do
        local observed = node.auto and node.auto.verb == "level" and node.completion and node.completion.observed
        if observed and type(observed.by) == "string" then
            local target = labels[observed.by]
            if not target then error("NuuRoad: no step is labelled '" .. observed.by .. "'") end
            if target <= node.index then error("NuuRoad: `by` names a later step") end
            node.auto.by, observed.by = target, target
            node.title = Steps:Title(node, true)
        end
    end
    for _, companion in ipairs(companions) do
        local node = companion.node
        local target = companion.target == "next" and (node.index + 1) or labels[companion.target]
        if not target then
            error("NuuRoad: no step is labelled '" .. tostring(companion.target) .. "'")
        end
        if target <= node.index then
            error("NuuRoad: a step is carried alongside a later step, not an earlier one")
        end
        if not expanded.nodes[target] then
            error("NuuRoad: `with` names a step past the end of the guide")
        end
        node.companionOf = target
        -- Its own rule still counts: whichever lands first finishes it.
        local own = node.completion and node.completion.type == "observed" and node.completion.observed
        local carried = { type = "step", index = target }
        node.completion = { type = "observed", observed = own
            and { type = "any", children = { own, carried } } or carried }
    end
    -- Background work written once, where it is finished: the drops off
    -- creatures fought for other reasons, shown from the labelled step on.
    for _, entry in ipairs(carriedFrom) do
        local target = labels[entry.target]
        if not target then error("NuuRoad: no step is labelled '" .. tostring(entry.target) .. "'") end
        if target >= entry.node.index then error("NuuRoad: `from` names an earlier step") end
        entry.node.carriedFrom = target
    end
    return expanded
end

-- The creatures a step is about, split by how the player deals with them:
-- `kill` lists the targets to fight (from the step's kill IDs), `talk` the
-- NPCs to speak with or click (every other referenced NPC). NPCTracking marks
-- them and counts the kills; the tracker colours the "Talk to" line.
function Steps:NPCs(node)
    local kill, talk, isKill = {}, {}, {}
    if not node then return kill, talk end
    local killIDs = node.auto and node.auto.kill
    if not killIDs and node.completion and node.completion.observed and node.completion.observed.type == "kills" then
        killIDs = node.completion.observed.npcs
    end
    for _, id in ipairs(killIDs or {}) do
        if type(id) == "number" and not isKill[id] then isKill[id] = true; table.insert(kill, id) end
    end
    -- Marked and listed like targets; no kill of theirs counts for the step.
    for _, id in ipairs(node.mark or {}) do
        if type(id) == "number" and not isKill[id] then isKill[id] = true; table.insert(kill, id) end
    end
    for _, id in ipairs(node.refs and node.refs.npcs or {}) do
        if type(id) == "number" and not isKill[id] then table.insert(talk, id) end
    end
    return kill, talk
end

-- Sticky objectives: every `track` before `node` in guide order that no
-- `untrack` has closed. The caller decides whether the quest still matters.
function Steps:ActiveTracks(guide, node)
    local active, order = {}, {}
    for _, candidate in ipairs(guide.nodes or {}) do
        if candidate == node then break end
        local auto = candidate.auto
        if auto and auto.verb == "track" then
            if not active[auto.track] then table.insert(order, auto.track) end
            active[auto.track] = true
        elseif auto and auto.verb == "untrack" then
            active[auto.untrack] = nil
        end
    end
    -- A quest tracked again after an untrack is in `order` twice; it is one line.
    local result, seen = {}, {}
    for _, questID in ipairs(order) do
        if active[questID] and not seen[questID] then seen[questID] = true; table.insert(result, questID) end
    end
    return result
end

ns:RegisterModule("Steps", Steps)
