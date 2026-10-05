local _, ns = ...

-- Guides are written in guide format v1 (docs/examples/guide-v1.lua, which
-- documents every field). Expand() reads one once, here, and everything
-- downstream sees ordinary runtime nodes; anything derived -- titles, step
-- positions, section and group spans, reference lists, completion rules -- is
-- built on the way in and never written in a guide.
local Steps = {}

local radiusByVerb = {
    accept = 0.02, turnin = 0.02, talk = 0.02, travel = 0.03, objective = 0.05, escort = 0.05,
    level = 0.025, collect = 0.04, kill = 0.05, hearth = 0.02, interact = 0.02,
    train = 0.02, learn = 0.02, cast = 0.03, buy = 0.02, vendor = 0.02, craft = 0.03, skillup = 0.03, equip = 0.03, skill = 0.05, reputation = 0.05,
    gather = 0.05, flight = 0.02, finish = 0.02,
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
    if verb == "objective" then
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
    if verb == "objective" then
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
        -- The level the quests are taken from, on the line before them and
        -- after the turn-ins, which may be what brings it.
        if auto.level and #accepts > 0 then
            add("level", { part("Reach level "), part(tostring(auto.level), "count") },
                { observed = { type = "level", atLeast = auto.level } })
        end
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
    elseif verb == "objective" then
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

-- READING A GUIDE
--
-- Expand() reads a guide in format v1 and builds the runtime guide. Errors
-- name the field they are about: "NuuRoad: data.sections[2].steps[4].quest:
-- must be { quest, objective }".

local function fail(path, message)
    error("NuuRoad: " .. path .. ": " .. message, 0)
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t) do table.insert(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
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

local function positive(value)
    return type(value) == "number" and value >= 1 and value % 1 == 0
end

-- Points are hundredths of a map percent in a guide: { 5226, 3193 } is
-- 52.26, 31.93. `map` stands in for a point that names none, where the
-- format says whose map it is on.
local function point(value, path, map)
    if type(value) ~= "table" or type(value[1]) ~= "number" or type(value[2]) ~= "number" then
        fail(path, "a point is { x, y }")
    end
    return { value[1] / 100, value[2] / 100, map = value.map or map }
end

local function points(value, path, map)
    if type(value) ~= "table" or #value == 0 then fail(path, "must be a list of points") end
    local out = {}
    for index, entry in ipairs(value) do out[index] = point(entry, path .. "[" .. index .. "]", map) end
    return out
end

-- Names for the IDs the client cannot be asked about by ID.
local function idName(kind, id, path)
    local names = ns.idNames and ns.idNames[kind]
    local name = names and names[id]
    if not name then fail(path, "no name for " .. kind .. " " .. tostring(id) .. " (Tools/IDNames.py)") end
    return name
end

local function areaName(id, path)
    if type(id) ~= "number" then fail(path, "an area is an AreaTable ID") end
    local Client = ns.modules and ns.modules.Client
    local live = Client and Client.GetAreaName and Client:GetAreaName(id)
    return live or idName("areas", id, path)
end

local function skillName(id, path)
    if type(id) ~= "number" then fail(path, "a skill is a SkillLine ID") end
    return idName("skills", id, path)
end

-- CONDITIONS

local function combine(kind, parts)
    if #parts == 0 then return nil end
    if #parts == 1 then return parts[1] end
    return { type = kind, children = parts }
end

local function tokens(value, path)
    if type(value) == "string" then return { value } end
    if type(value) == "table" and #value > 0 then return value end
    fail(path, "must be a token or a list of them")
end

-- A condition table -> a predicate, and whether it asks anything `show` asks
-- (a profession, a realm answer), which makes it a `now` term.
local predicate
local function predicates(entries, conds, path, seen)
    if type(entries) ~= "table" or #entries == 0 then fail(path, "must be a list of conditions") end
    local out, show = {}, false
    for index, entry in ipairs(entries) do
        local child, childShow = predicate(entry, conds, path .. "[" .. index .. "]", seen)
        table.insert(out, child)
        show = show or childShow
    end
    return out, show
end

predicate = function(condition, conds, path, seen)
    if type(condition) ~= "table" then fail(path, "a condition is a table") end
    local parts, show = {}, false
    for _, key in ipairs(sortedKeys(condition)) do
        local value, at = condition[key], path .. "." .. tostring(key)
        if key == "class" or key == "race" or key == "faction" then
            table.insert(parts, { type = key, values = tokens(value, at) })
        elseif key == "season" then
            table.insert(parts, value == true and { type = "season" } or { type = "season", id = value })
        elseif key == "hardcore" then
            table.insert(parts, { type = "hardcore" })
        elseif key == "skill" then
            local each = {}
            for index, id in ipairs(type(value) == "table" and value or { value }) do
                table.insert(each, { type = "profession", name = skillName(id, at .. "[" .. index .. "]") })
            end
            table.insert(parts, combine("any", each))
            show = true
        elseif key == "ah" then
            table.insert(parts, { type = "auctionHouse" })
            show = true
        elseif key == "selffound" then
            table.insert(parts, { type = "selfFound" })
            show = true
        elseif key == "any" or key == "all" then
            local children, childShow = predicates(value, conds, at, seen)
            table.insert(parts, combine(key, children))
            show = show or childShow
        elseif key == "none" then
            local children, childShow = predicates(value, conds, at, seen)
            table.insert(parts, { type = "not", child = combine("any", children) })
            show = show or childShow
        elseif key == "is" then
            local named = conds and conds[value]
            if named == nil then fail(at, "no condition named '" .. tostring(value) .. "' in data.conds") end
            if seen[value] then fail(at, "condition '" .. value .. "' names itself") end
            seen[value] = true
            local child, childShow = predicate(named, conds, "data.conds." .. value, seen)
            seen[value] = nil
            table.insert(parts, child)
            show = show or childShow
        else
            fail(at, "is not a condition")
        end
    end
    if #parts == 0 then fail(path, "an empty condition") end
    return combine("all", parts), show
end

-- The predicates a guide's, section's, group's or step's `cond` and `show`
-- put on everything inside it. `show` (and a `cond` that asks what `show`
-- asks) is wrapped in `now`: read when the guide reaches the step, which is
-- passed over if it does not hold.
local function conditions(source, conds, path)
    local out = {}
    for _, field in ipairs({ "cond", "show" }) do
        if source[field] ~= nil then
            local tree, show = predicate(source[field], conds, path .. "." .. field, {})
            if show or field == "show" then tree = { type = "now", child = tree } end
            table.insert(out, tree)
        end
    end
    return out
end

local function append(target, source)
    local out = {}
    for _, entry in ipairs(target) do table.insert(out, entry) end
    for _, entry in ipairs(source) do table.insert(out, entry) end
    return out
end

-- A condition table, as a guide writes one, as the predicate a node carries.
function Steps:Condition(condition, conds)
    if condition == nil then return nil end
    local tree, show = predicate(condition, conds, "cond", {})
    return show and { type = "now", child = tree } or tree
end

-- THE EDITOR'S CONDITIONS
--
-- The editor takes a condition as text that says what a guide's `cond` and
-- `show` can: "Warrior or Shaman", "not Tauren", "Horde", "season 2",
-- "hardcore", "skill Mining" (or "skill 186"), "ah", "selffound". ` or `
-- joins terms any of which will do, `not` in front of a term turns that term
-- alone around, and `|` joins groups that must all hold: "Horde | not Tauren
-- | Warrior or skill Mining". Every condition a guide can write has such a
-- text (DescribeCondition finds it), so the editor reads back what it shows.

local classTokens = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
    shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID",
}
local factionTokens = { horde = "Horde", alliance = "Alliance" }
local raceTokens = {
    orc = "orc", troll = "troll", tauren = "tauren", undead = "scourge", scourge = "scourge",
    ["blood elf"] = "bloodelf", bloodelf = "bloodelf", human = "human", dwarf = "dwarf",
    ["night elf"] = "nightelf", nightelf = "nightelf", gnome = "gnome", draenei = "draenei",
    -- Forever's own race, either faction. Matches the client's
    -- UnitRace token "Skyborne"; unverified here, see docs/api-compatibility.md.
    skyborne = "skyborne",
}

local function skillID(text)
    if tonumber(text) then return tonumber(text) end
    for id, name in pairs(ns.idNames and ns.idNames.skills or {}) do
        if name:lower() == text:lower() then return id end
    end
    error("NuuRoad: no skill called '" .. text .. "'", 0)
end

local function termCondition(piece)
    local body = piece:lower()
    if factionTokens[body] then return { faction = factionTokens[body] } end
    if classTokens[body] then return { class = classTokens[body] } end
    if raceTokens[body] then return { race = raceTokens[body] } end
    if body == "season" then return { season = true } end
    local season = body:match("^season%s+(%d+)$")
    if season then return { season = tonumber(season) } end
    if body == "hardcore" then return { hardcore = true } end
    if body == "ah" then return { ah = true } end
    if body == "selffound" then return { selffound = true } end
    local skill = piece:match("^[Ss][Kk][Ii][Ll][Ll]%s+(.+)$")
    if skill then return { skill = skillID(skill) } end
    error("NuuRoad: unknown condition term '" .. piece .. "'", 0)
end

local function trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Text -> the condition table a guide would write, or nil for none.
local function conditionFromText(text)
    local groups = {}
    for group in text:gmatch("[^|]+") do
        local terms = {}
        for piece in (trim(group) .. " or "):gmatch("(.-) or ") do
            piece = trim(piece)
            local negated = piece:match("^[Nn][Oo][Tt]%s+(.+)$")
            local term = termCondition(negated or piece)
            table.insert(terms, negated and { none = { term } } or term)
        end
        table.insert(groups, #terms == 1 and terms[1] or { any = terms })
    end
    if #groups == 0 then return nil end
    if #groups == 1 then return groups[1] end
    return { all = groups }
end

-- The editor's write-back. Raises on a term it does not know; the caller
-- reports that.
function Steps:ParseCondition(text)
    if type(text) ~= "string" or not text:match("%S") then return nil end
    return self:Condition(conditionFromText(text))
end

-- A step's condition split into what was written (`cond`, `show`) and the
-- terms Expand worked out from the step's own fields (`derived`), which the
-- editor keeps as they are.
function Steps:SplitCondition(condition)
    if type(condition) ~= "table" then return nil, {} end
    if condition.derived then return nil, { condition } end
    if condition.type ~= "all" then return condition, {} end
    local written, derived = {}, {}
    for _, child in ipairs(condition.children or {}) do
        table.insert(child.derived and derived or written, child)
    end
    return combine("all", written), derived
end

-- The two halves back together.
function Steps:JoinCondition(written, derived)
    local parts = {}
    if written then table.insert(parts, written) end
    for _, term in ipairs(derived or {}) do table.insert(parts, term) end
    return combine("all", parts)
end

-- One leaf's words, or nil for a kind the text has none for.
local function leafWords(predicate, value)
    local kind = predicate.type
    if kind == "class" or kind == "race" or kind == "faction" then
        return tostring(value):sub(1, 1):upper() .. tostring(value):sub(2):lower()
    end
    if kind == "season" then return predicate.id and ("season " .. predicate.id) or "season" end
    if kind == "hardcore" then return "hardcore" end
    if kind == "profession" then return "skill " .. tostring(predicate.name) end
    if kind == "auctionHouse" then return "ah" end
    if kind == "selfFound" then return "selffound" end
    if kind == "quest" then
        return "quest " .. tostring(predicate.id) .. (predicate.state and (" " .. predicate.state) or "")
    end
    if kind == "item" then return "item " .. tostring(predicate.id) end
    return nil
end

-- A predicate as clauses that must all hold, each a list of terms any of
-- which will do: `not` is pushed down to the terms, and an `all` inside an
-- `any` is spread over it. `now` is said only on the terms a step works out
-- for itself (quest, item); a `show` key is read that way already.
local function clauses(predicate, negated, now)
    if type(predicate) ~= "table" then return {} end
    local kind = predicate.type
    if kind == "now" then return clauses(predicate.child, negated, true) end
    if kind == "not" then return clauses(predicate.child, not negated, now) end
    if kind == "all" or kind == "any" then
        local joined = (kind == "all") ~= negated
        if joined then
            local out = {}
            for _, child in ipairs(predicate.children or {}) do
                for _, clause in ipairs(clauses(child, negated, now)) do table.insert(out, clause) end
            end
            return out
        end
        local out = { {} }
        for _, child in ipairs(predicate.children or {}) do
            local spread = {}
            for _, left in ipairs(out) do
                for _, right in ipairs(clauses(child, negated, now)) do
                    local clause = {}
                    for _, term in ipairs(left) do table.insert(clause, term) end
                    for _, term in ipairs(right) do table.insert(clause, term) end
                    table.insert(spread, clause)
                end
            end
            out = spread
        end
        return out
    end
    local values = (kind == "class" or kind == "race" or kind == "faction") and (predicate.values or {}) or { false }
    local terms = {}
    for _, value in ipairs(values) do
        local words = leafWords(predicate, value)
        if words then
            if now and (kind == "quest" or kind == "item") then words = "now " .. words end
            table.insert(terms, negated and ("not " .. words) or words)
        end
    end
    if #terms == 0 then return {} end
    -- "not Warrior or Druid" read as one term each: a class that is neither.
    if negated then
        local out = {}
        for _, term in ipairs(terms) do table.insert(out, { term }) end
        return out
    end
    return { terms }
end

-- A predicate as the text the editor reads (see "The editor's conditions"),
-- for the editor, the tracker and reports.
function Steps:DescribeCondition(predicate)
    if type(predicate) ~= "table" then return nil end
    local parts = {}
    for _, clause in ipairs(clauses(predicate, false, false)) do
        local seen, terms = {}, {}
        for _, term in ipairs(clause) do
            if not seen[term] then seen[term] = true; table.insert(terms, term) end
        end
        if #terms > 0 then table.insert(parts, table.concat(terms, " or ")) end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " | ")
end

-- Keeps a carried step's completion in step with the step it rides along
-- with. Expand builds this once; the editor needs it again whenever an
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

-- STEPS

-- `needs = { { item = 2840, count = 10, source = "ah" } }` -> the node's
-- material list. Counts are the whole step's, not per item made, so what a
-- guide writes is what the list asks for.
local function materials(step, path)
    if step.needs == nil then return nil end
    if type(step.needs) ~= "table" then fail(path .. ".needs", "is { { item, count, source }, ... }") end
    local out = {}
    for index, need in ipairs(step.needs) do
        local at = path .. ".needs[" .. index .. "]"
        if type(need) ~= "table" or type(need.item) ~= "number" then fail(at, "is { item, count, source }") end
        local source = need.source or "gather"
        if not Steps.materialSources[source] then fail(at .. ".source", "unknown material source '" .. tostring(source) .. "'") end
        table.insert(out, { itemID = need.item, count = need.count or 1, source = source })
    end
    if #out == 0 then return nil end
    return out
end

-- The profession rank that makes the step moot. A materials step in a
-- profession guide is only ever a means to a rank, so reaching the rank
-- finishes it however few were gathered, bought, or made.
local function uptoRank(step, path)
    if step.upto == nil then return nil end
    if type(step.upto) ~= "table" or type(step.upto.rank) ~= "number" then fail(path .. ".upto", "is { skill, rank }") end
    return { skill = skillName(step.upto.skill, path .. ".upto.skill"), rank = step.upto.rank }
end

local function questPair(quest)
    return type(quest) == "table" and type(quest[1]) == "number" and type(quest[2]) == "number"
end

local function questCompletion(state, ids, match)
    return { type = "observed", observed = { type = "quests", state = state, match = match, ids = ids } }
end

-- The guide's places and NPCs and its map while Expand runs, so a step's
-- `stand = "cave.chamber"` can be looked up and a visit with no `at` of its
-- own goes where the NPC stands.
local expandingPlaces, expandingNPCs, expandingMap

-- { "Tonga Runetotem", at = { 52.26, 31.93 }, note = "..." } for an NPC the
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
                for candidate, entry in ipairs(place.points) do
                    if type(entry) == "table" and entry.id == pointRef then index = candidate end
                end
            end
            local found = index and place.points[index]
            if type(found) == "table" then return place, found, index end
        end
    end
    return nil
end

local function placeLocation(at, radius, verb, defaultMap)
    local place, entry = Steps.FindPlacePoint(expandingPlaces, at)
    if not place then error("NuuRoad: no place point '" .. at .. "'", 0) end
    local x, y = normalize(entry.at and entry.at[1], entry.at and entry.at[2])
    if not x then error("NuuRoad: place point '" .. at .. "' has no position", 0) end
    return { mapID = entry.map or place.map or defaultMap, x = x, y = y,
        arrivalRadiusNormalized = radius or radiusByVerb[verb], point = at }
end

-- `at` is a place point ("cave.chamber"), one point, or a list of them: the
-- first is the arrow's target and the rest are map pins; the arrow takes
-- whichever is nearest. `near` says which part of a guide place the spot
-- belongs to, so the planner joins it to that point's passages rather than
-- guessing by distance (two levels of a cave can lie over each other).
local function location(where, verb, defaultMap)
    local at = where.at
    if type(at) == "string" then return placeLocation(at, where.radius, verb, defaultMap) end
    if type(at) ~= "table" then return nil end
    local list, mapID = at, at.map or defaultMap
    if type(at[1]) ~= "table" then list = { at } end
    local x, y = normalize(list[1] and list[1][1], list[1] and list[1][2])
    if not x then return nil end
    mapID = list[1].map or mapID
    local spots
    for index = 2, #list do
        local sx, sy = normalize(list[index][1], list[index][2])
        if sx and sy then
            spots = spots or {}
            table.insert(spots, { x = sx, y = sy })
        end
    end
    local near = where.near
    if near ~= nil and not Steps.FindPlacePoint(expandingPlaces, near) then
        error("NuuRoad: no place point '" .. tostring(near) .. "'", 0)
    end
    return { mapID = mapID, x = x, y = y, arrivalRadiusNormalized = where.radius or radiusByVerb[verb],
        spots = spots, loop = where.loop and true or nil, near = near }
end

local vendorActions = { [1] = "sell", [2] = "repair", [3] = "sell and repair" }

-- A quest objective's step: kill, collect, interact, or a talk, by the
-- objective's number in the quest log, or the whole quest.
local function objectiveNode(node, step, verbHint)
    local quest = step.quest
    local quests = { questPair(quest) and quest[1] or quest }
    if questPair(quest) then
        node.kind = (step.type == "collect" and step.item) and "collect" or (step.kill and "kill")
            or (step.object and "interact") or "questObjective"
        node.completion = { type = "observed", observed = { type = "objective", questID = quest[1], index = quest[2] } }
        -- The NPC is carried so an objective that is really a conversation can
        -- say so when the client has no objective line to give.
        node.auto = { verb = "objective", quests = quests, part = quest[2], npc = step.npc and list(step.npc) or nil }
    else
        node.kind = "questObjective"
        node.completion = questCompletion("readyToTurnIn", quests, "all")
        node.auto = { verb = "objective", quests = quests }
    end
    if verbHint == "collect" then node.auto.collect = { step.item } end
    return quests
end

-- One step -> its node, and the quests it is about.
local function build(step, path, defaultMap)
    local kind = step.type
    local node = { kind = "action", completion = { type = "manual" } }
    local quests, verb = nil, kind
    if step.quest ~= nil and type(step.quest) == "table" and not questPair(step.quest) then
        fail(path .. ".quest", "must be { quest, objective }")
    end
    if step.quest ~= nil and type(step.quest) ~= "table" and type(step.quest) ~= "number" then
        fail(path .. ".quest", "is a quest ID or { quest, objective }")
    end
    local objective = false
    if kind == "note" then
        node.kind, node.title, node.body = "note", "Note", step.note or ""
    elseif kind == "finish" then
        node.kind, node.title, node.body = "end", "Guide complete", step.note or ""
    elseif kind == "travel" then
        node.kind = "travel"
        local first = type(step.at) == "table" and step.at[1]
        node.auto = { verb = verb, label = type(step.to) == "string" and step.to
            or (type(first) == "table" and fmtCoord({ first[1] / 100, first[2] / 100 })) or "there" }
        -- Arrival is normally a coordinate, but a zone or an area is what the
        -- player actually crosses into, and the client names those. A
        -- dungeon has no map the client reports, only its instance ID.
        if type(step.instance) == "number" then
            node.completion = { type = "observed", observed = { type = "instance", instanceID = step.instance } }
        elseif step.area ~= nil then
            node.completion = { type = "observed", observed = { type = "subzone", name = areaName(step.area, path .. ".area") } }
        elseif type(step.zone) == "number" then
            node.completion = { type = "observed", observed = { type = "zone", mapID = step.zone } }
        else
            node.completion = { type = "observed", observed = { type = "location" } }
        end
    elseif kind == "accept" then
        quests = list(step.quests)
        node.kind, node.completion = "acceptQuest", questCompletion("acceptedOrFinished", quests, "all")
        node.auto = { verb = verb, quests = quests, kill = step.kill and list(step.kill) or nil }
    elseif kind == "turnin" then
        quests = list(step.quests)
        node.kind, node.completion = "turnInQuest", questCompletion("finished", quests, "all")
    elseif kind == "talk" then
        local turnin, accept = list(step.turnin), list(step.accept)
        if #turnin + #accept > 0 then
            node.kind = "talk"
            node.auto = { verb = verb, turnin = turnin, accept = accept }
            quests = {}
            for _, id in ipairs(turnin) do table.insert(quests, id) end
            for _, id in ipairs(accept) do table.insert(quests, id) end
            node.completion = { type = "observed", observed = { type = "all", children = {
                { type = "quests", state = "finished", match = "all", ids = turnin },
                { type = "quests", state = "acceptedOrFinished", match = "all", ids = accept },
            } } }
        elseif questPair(step.quest) then
            quests, objective, verb = objectiveNode(node, step), true, "objective"
        elseif step.quest ~= nil then
            fail(path .. ".quest", "must be { quest, objective }")
        elseif step.npc == nil then
            fail(path .. ".npc", "a talk step with no quests names its NPC")
        else
            node.kind = "talk"
            node.auto = { verb = verb, turnin = turnin, accept = accept }
        end
    elseif kind == "escort" then
        -- Follow and guard an NPC to `at`. Done the way an objective is, once
        -- the quest is ready to hand in; the NPC is named, since "Escort" is
        -- the whole instruction, and followed like any step's NPC.
        if step.npc == nil then fail(path .. ".npc", "an escort names the NPC escorted") end
        local id = questPair(step.quest) and step.quest[1] or step.quest
        if type(id) ~= "number" then fail(path .. ".quest", "an escort names its quest") end
        quests = { id }
        node.kind = "escort"
        node.completion = questCompletion("readyToTurnIn", quests, "all")
        node.auto = { verb = verb, quests = quests, npc = list(step.npc) }
    elseif kind == "collect" then
        if questPair(step.quest) then
            quests, objective, verb = objectiveNode(node, step, step.item and "collect"), true, "objective"
        elseif step.item == nil and type(step.quest) == "number" then
            -- The item is not known yet: the whole quest is the work.
            quests, objective, verb = objectiveNode(node, step), true, "objective"
        else
            if type(step.item) ~= "number" then fail(path .. ".item", "a collect step names its item") end
            node.kind = "collect"
            node.auto = { verb = verb, collect = { step.item }, count = step.count, starts = step.starts, quest = step.quest }
            -- An item that begins a quest is also done once that quest was
            -- ever accepted; a quest item is done once its quest is finished,
            -- and moot when the player has no such quest. Both tie the step
            -- to the quest log, so the resume scan can judge it instead of
            -- passing it over.
            node.completion = { type = "observed", observed = {
                type = "item", itemID = step.item, count = step.count or 1,
                startsQuestID = step.starts, questID = step.quest,
            } }
            if step.starts or step.quest then node.refs = { quests = { step.starts or step.quest } } end
        end
    elseif kind == "kill" then
        if step.quest ~= nil then
            quests, objective, verb = objectiveNode(node, step), true, "objective"
        else
            if step.kill == nil then fail(path .. ".kill", "a kill step names its creatures") end
            node.kind = "kill"
            node.auto = { verb = verb, kill = list(step.kill), count = step.count }
            node.completion = { type = "observed", observed = { type = "kills", npcs = list(step.kill), count = step.count or 1 } }
        end
    elseif kind == "interact" then
        if step.quest ~= nil then
            quests, objective, verb = objectiveNode(node, step), true, "objective"
        else
            if step.object == nil then fail(path .. ".object", "an interact step names its object") end
            node.kind = "interact"
            node.auto = { verb = verb }
        end
    elseif kind == "train" then
        -- No rank given means "learn it at all": rank 1 is the first point in
        -- a skill the player does not have yet.
        local skill = skillName(step.skill, path .. ".skill")
        node.kind = "train"
        node.auto = { verb = verb, skill = skill, rank = step.rank }
        node.completion = { type = "observed", observed = { type = "skill", name = skill, atLeast = step.rank or 1 } }
    elseif kind == "learn" then
        -- A class spell (or its next rank) from a trainer: done once the
        -- client knows every spell named. Professions are `train`.
        local spells = list(step.spells)
        if #spells == 0 then fail(path .. ".spells", "a learn step names its spells") end
        for index, id in ipairs(spells) do
            if type(id) ~= "number" then fail(path .. ".spells[" .. index .. "]", "a spell is named by ID") end
        end
        node.kind = "train"
        node.auto = { verb = verb, spells = spells, trainer = step.npc and list(step.npc)[1] or nil }
        node.completion = { type = "observed", observed = { type = "spell", ids = spells } }
    elseif kind == "cast" then
        -- A spell to cast here, such as Skysight beside a convergence: counted
        -- from the casts made while the guide is on the step.
        if type(step.spell) ~= "number" then fail(path .. ".spell", "a cast step names one spell by ID") end
        if step.count ~= nil and not positive(step.count) then fail(path .. ".count", "must be a positive number") end
        node.kind = "cast"
        node.auto = { verb = verb, spell = step.spell, count = step.count }
        node.completion = { type = "observed", observed = { type = "cast", spellID = step.spell, count = step.count or 1 } }
    elseif kind == "skill" then
        if type(step.rank) ~= "number" then fail(path .. ".rank", "a skill step needs a rank") end
        local skill = skillName(step.skill, path .. ".skill")
        node.kind = "skillTarget"
        node.auto = { verb = verb, skill = skill, rank = step.rank }
        node.completion = { type = "observed", observed = { type = "skill", name = skill, atLeast = step.rank } }
    elseif kind == "craft" then
        node.kind = "craft"
        node.auto = { verb = verb, item = step.item, count = step.count,
            skill = step.skill and skillName(step.skill, path .. ".skill") or nil }
        node.completion = { type = "observed", observed = { type = "crafted", itemID = step.item, count = step.count or 1 } }
        node.refs = { items = { step.item } }
    elseif kind == "skillup" then
        -- Crafting for the rank, the way a profession guide really reads:
        -- keep making them until the skill lands, however many that turns out
        -- to be. Use `craft` with a count when the output is the point.
        if type(step.rank) ~= "number" then fail(path .. ".rank", "a skillup step needs a rank") end
        local skill = skillName(step.skill, path .. ".skill")
        node.kind = "skillUp"
        node.auto = { verb = verb, item = step.item, skill = skill, rank = step.rank }
        node.completion = { type = "observed", observed = { type = "skill", name = skill, atLeast = step.rank } }
        node.refs = { items = { step.item } }
    elseif kind == "gather" then
        -- Picking it is the usual way; the auction house is the other one, so
        -- the step says both and completes on the item either way.
        node.kind = "gather"
        node.auto = { verb = verb, item = step.item, count = step.count,
            skill = step.skill and skillName(step.skill, path .. ".skill") or nil }
        node.completion = { type = "observed", observed = { type = "item", itemID = step.item, count = step.count or 1 } }
        node.refs = { items = { step.item } }
    elseif kind == "buy" then
        -- One named vendor, since stock differs from one to the next.
        node.kind = "buy"
        node.auto = { verb = verb, item = step.item, count = step.count, vendor = list(step.npc)[1] }
        node.completion = { type = "observed", observed = { type = "item", itemID = step.item, count = step.count or 1 } }
        node.refs = { items = { step.item } }
    elseif kind == "vendor" then
        -- Selling and repairing are the player's business; the step only says
        -- where, so it is theirs to tick off.
        local action = vendorActions[(step.sell and 1 or 0) + (step.repair and 2 or 0)]
        if not action then fail(path, "a vendor step sells, repairs, or both") end
        node.kind = "vendor"
        node.auto = { verb = verb, vendor = list(step.npc)[1], action = action }
    elseif kind == "equip" then
        node.kind = "equip"
        node.auto = { verb = verb, item = step.item }
        node.completion = { type = "observed", observed = { type = "equipped", itemID = step.item } }
        node.refs = { items = { step.item } }
    elseif kind == "reputation" then
        local standing = ns.modules.Names:StandingValue(step.standing)
        if not standing then fail(path .. ".standing", "a standing from 1 (Hated) to 8 (Exalted)") end
        node.kind = "reputationTarget"
        node.auto = { verb = verb, faction = step.faction, standing = standing }
        node.completion = { type = "observed", observed = { type = "reputation", factionID = step.faction, standing = standing } }
    elseif kind == "hearth" then
        local name = areaName(step.area, path .. ".area")
        node.kind = "hearth"
        node.auto = { verb = verb, name = name }
        node.completion = { type = "observed", observed = { type = "hearth", name = name } }
    elseif kind == "flight" then
        if type(step.node) ~= "number" then fail(path .. ".node", "a flight step names its TaxiNodes ID") end
        local name = idName("taxiNodes", step.node, path .. ".node")
        node.kind = "flight"
        node.auto = { verb = verb, name = name }
        node.completion = { type = "observed", observed = { type = "flightpath", name = name } }
    elseif kind == "level" then
        if not positive(step.level) then fail(path .. ".level", "must be a positive level") end
        node.kind = "levelTarget"
        node.auto = { verb = verb, level = step.level, xp = step.xp }
        node.completion = { type = "observed", observed = { type = "level", atLeast = step.level, xp = step.xp } }
        if step.by ~= nil then
            if type(step.by) ~= "string" or step.by == "" then fail(path .. ".by", "names the step the level is needed by") end
            if step.xp ~= nil then fail(path .. ".by", "with `by`, the level is the one needed at that step; leave out `xp`") end
            -- Resolved to a position once every label is known.
            node.auto.by, node.completion.observed.by = step.by, step.by
        end
    elseif kind == "choice" then
        node.kind, node.title, node.choices = "choice", step.text, {}
        for index, option in ipairs(step.options or {}) do
            if type(option) ~= "table" then fail(path .. ".options[" .. index .. "]", "is { text, go }") end
            if type(option.go) ~= "string" then fail(path .. ".options[" .. index .. "].go", "a choice goes to a label") end
            table.insert(node.choices, { title = option.text, ["next"] = option.go })
        end
    else
        fail(path .. ".type", "unknown step type '" .. tostring(kind) .. "'")
    end
    if quests then
        node.auto = node.auto or { verb = verb, quests = quests }
        node.refs = { quests = quests }
    end
    -- The level a pickup's quests are taken from. It gates nothing: the
    -- client will not give them any sooner, so the accept waits as it is.
    if step.level ~= nil and kind ~= "level" then
        if kind ~= "accept" and kind ~= "talk" then fail(path .. ".level", "is for level, accept and talk steps") end
        if kind == "talk" and #(node.auto and node.auto.accept or {}) == 0 then
            fail(path .. ".level", "is for a talk that accepts quests")
        end
        if not positive(step.level) then fail(path .. ".level", "must be a positive level") end
        node.auto.level = step.level
    end
    -- The quest a travel, buy, escort, or any other step's work is for (an
    -- objective step and a collect read `quest` themselves). `{ id, n }` is
    -- one objective: the step is done when the client says it is, and a
    -- travel step only then, since the arrival starts a scene the objective
    -- ends. A whole quest finishes the step once it is ready to hand in.
    -- An escort's whole quest is its own rule already.
    if step.quest ~= nil and not objective and kind ~= "collect" and not (kind == "escort" and not questPair(step.quest)) then
        local finishes
        if questPair(step.quest) then
            finishes = { type = "objective", questID = step.quest[1], index = step.quest[2] }
        else
            finishes = { type = "quests", state = "readyToTurnIn", match = "all", ids = { step.quest } }
        end
        local own = node.completion.type == "observed" and node.completion.observed
        if kind == "travel" and finishes.type == "objective" or not own then
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
    end
    if step.kill then
        node.refs = node.refs or {}
        node.refs.npcs = list(step.kill)
    end
    if objective and node.auto.collect then
        node.refs = node.refs or {}
        node.refs.items = list(node.auto.collect)
    end
    if step.npc then
        node.refs = node.refs or {}
        node.refs.npcs = list(step.npc)
    end
    -- The item the step is about: the one that starts an accept's quest, or
    -- any step's `item = { ... }`, which the item panel offers.
    local about = (kind == "accept" and type(step.item) == "number") and { step.item }
        or (type(step.item) == "table" and step.item) or nil
    if about then
        node.refs = node.refs or {}
        node.refs.items = list(about)
    end
    local escape = uptoRank(step, path)
    if escape then
        local observed = node.completion and node.completion.type == "observed" and node.completion.observed
        if not observed then fail(path .. ".upto", "needs a step the client can judge on its own") end
        node.completion = { type = "observed", observed = { type = "any", children = {
            observed,
            { type = "skill", name = escape.skill, atLeast = escape.rank },
        } } }
        if node.auto then node.auto.upto = escape end
    end
    node.needs = materials(step, path)
    local function addItems(ids)
        node.refs = node.refs or {}
        local items = node.refs.items or {}
        local seen = {}
        for _, id in ipairs(items) do seen[id] = true end
        for _, id in ipairs(ids) do
            if not seen[id] then seen[id] = true; table.insert(items, id) end
        end
        node.refs.items = items
    end
    if node.needs then
        local ids = {}
        for _, material in ipairs(node.needs) do table.insert(ids, material.itemID) end
        addItems(ids)
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
        for index, itemID in ipairs(node.use) do
            if type(itemID) ~= "number" then fail(path .. ".use[" .. index .. "]", "an item is named by ID") end
        end
        addItems(node.use)
    end
    -- How long the step keeps the player waiting: a scene playing out, or a
    -- timed quest starting. Shown, never enforced.
    if step.wait ~= nil then
        node.wait = tonumber(step.wait)
        if not node.wait then fail(path .. ".wait", "is a number of seconds") end
    end
    -- A step that stays on screen alongside the ones after it until it is done.
    if step.sticky then node.sticky = true end
    -- Creatures to mark and list as targets without their kills counting for
    -- anything: the mobs of a grind spot, a creature an item is used on.
    if step.mark ~= nil then
        node.mark = list(step.mark)
        for index, id in ipairs(node.mark) do
            if type(id) ~= "number" then fail(path .. ".mark[" .. index .. "]", "a creature is named by ID") end
        end
    end
    -- The dialog options to pick on a talk step, by gossip option ID, one per
    -- page. Kept on the step; nothing picks them yet.
    if step.say ~= nil then
        node.say = list(step.say)
        for index, id in ipairs(node.say) do
            if type(id) ~= "number" then fail(path .. ".say[" .. index .. "]", "a gossip option is named by ID") end
        end
    end
    if step.at ~= nil and step.stand ~= nil then fail(path, "a step has `at` or `stand`, not both") end
    local where = { radius = step.radius and step.radius / 10000 or nil, near = step.near, loop = step.loop }
    if step.at ~= nil then where.at = points(step.at, path .. ".at") end
    if step.stand ~= nil then where.at = step.stand end
    node.location = location(where, verb, defaultMap)
    -- A visit with no point of its own goes where the guide says the NPC
    -- stands, on the guide's map unless the point names another, and carries
    -- what the guide says about the NPC above the step's own note.
    local visited = type(step.npc) == "table" and step.npc[1] or step.npc
    local stands = npcEntry(visited)
    if stands and stands.at ~= nil and where.at == nil then
        node.location = location({ at = stands.at, radius = where.radius, near = step.near }, verb, expandingMap)
        if node.location then node.location.npc = visited end
    end
    if kind ~= "note" and kind ~= "finish" and type(step.note) == "string" then node.body = step.note end
    if stands and type(stands.note) == "string" and kind ~= "note" and kind ~= "finish" then
        node.body = node.body and (stands.note .. "\n" .. node.body) or stands.note
    end
    if node.auto then node.title = Steps:Title(node, true) end
    return node
end

-- The terms a step gets from its own fields rather than from `cond`: an
-- `optional` turn-in passes unless one of its quests is ready, and an accept
-- from an item the player never looted passes (the rare that drops it was
-- never met). Carried, an item accept waits like any carried step.
local function derivedTerms(step, path)
    local terms = {}
    if step.optional then
        if step.type ~= "turnin" and step.type ~= "talk" then fail(path .. ".optional", "is for turn-ins") end
        local ready = {}
        for _, id in ipairs(step.type == "turnin" and list(step.quests) or list(step.turnin)) do
            table.insert(ready, { type = "quest", id = id, state = "readyToTurnIn" })
        end
        if #ready == 0 then fail(path .. ".optional", "the step turns in no quest") end
        table.insert(terms, { type = "now", child = combine("any", ready) })
    end
    if step.type == "accept" and type(step.item) == "number" and step.npc == nil
        and not (step.sticky or step.with or step.from) then
        table.insert(terms, { type = "now", child = { type = "item", id = step.item } })
    end
    return terms
end

-- Steps.derived: true on a predicate Expand works out from a step's own
-- fields, which the editor keeps as it is rather than showing as the step's
-- condition.
local function markDerived(terms)
    for _, term in ipairs(terms) do term.derived = true end
    return terms
end

-- PLACES AND NPCS

local function convertPlace(place, path)
    if type(place) ~= "table" then fail(path, "a place is a table") end
    local out = { place = place.id, name = place.name, width = place.width, map = place.map, points = {}, connections = {} }
    for index, entry in ipairs(place.points or {}) do
        local at = point(entry.at, path .. ".points[" .. index .. "].at")
        out.points[index] = { at = { at[1], at[2] }, map = at.map, kind = entry.kind, label = entry.label, id = entry.id }
    end
    for index, link in ipairs(place.links or {}) do
        out.connections[index] = { link.from, link.to, link.oneway and true or nil }
    end
    return out
end

-- "cave" (any point of the place) -> every point of it, for the arrow to take
-- the nearest; "cave.chamber" stays a reference.
local function placeSpots(places, reference, path)
    for _, place in ipairs(places or {}) do
        if place.place == reference then
            local spots = {}
            for _, entry in ipairs(place.points) do
                table.insert(spots, { entry.at[1], entry.at[2], map = entry.map or place.map })
            end
            return spots
        end
    end
    fail(path, "no place '" .. reference .. "'")
end

-- { [map] = { [id] = npc } } -> { [id] = "Name" or { "Name", at, note, instance } },
-- with the map the NPC is listed under put on each of its points.
local function convertNPCs(npcs, places, guideMap)
    local out = {}
    if npcs == nil then return out end
    for _, map in ipairs(sortedKeys(npcs)) do
        local path = "data.npcs[" .. tostring(map) .. "]"
        if type(npcs[map]) ~= "table" then fail(path, "is { [id] = npc }") end
        for _, id in ipairs(sortedKeys(npcs[map])) do
            local entry, at = npcs[map][id], path .. "[" .. tostring(id) .. "]"
            local converted
            if type(entry) == "string" then
                converted = entry
            elseif type(entry) == "table" then
                converted = { entry.name, note = entry.note, instance = entry.instance }
                local where = entry.at
                local stamp = map ~= guideMap and map or nil
                if type(where) == "string" then
                    converted.at = where:find(".", 1, true) and where or placeSpots(places, where, at .. ".at")
                elseif type(where) == "table" and type(where[1]) == "table" then
                    converted.at = points(where, at .. ".at", stamp)
                elseif where ~= nil then
                    converted.at = point(where, at .. ".at", stamp)
                end
            else
                fail(at, "is a name or { name, at, note, instance }")
            end
            -- An NPC listed twice keeps the entry that says where it stands.
            if out[id] == nil or type(out[id]) == "string" then out[id] = converted end
        end
    end
    return out
end

-- THE GUIDE

local function onlyKeys(value, allowed, path, what)
    for key in pairs(value) do
        if not allowed[key] then fail(path .. "." .. tostring(key), "is not a field of " .. what) end
    end
end

local sectionKeys = { title = true, map = true, label = true, cond = true, show = true, steps = true }
local groupKeys = { label = true, cond = true, show = true, group = true }

-- Sections and groups are wrappers: neither adds a step of its own, and each
-- records a span over the flattened node list. That list is the only place a
-- step position is ever written down -- guides name labels, and the labels
-- are resolved to positions here.
--
-- A runtime guide (one the editor saved) is passed through with its nodes
-- indexed.
function Steps:Expand(value)
    if type(value) ~= "table" then return value end
    if value.kind ~= "guide" and type(value.nodes) == "table" then return ns.modules.Schema:IndexNodes(value) end
    if value.kind ~= "guide" then fail("guide", "is not a guide") end
    if value.schema ~= 1 then fail("guide.schema", "must be 1") end
    local data = value.data
    if type(data) ~= "table" or type(data.sections) ~= "table" then fail("guide.data", "has no sections") end
    local conds = data.conds
    local levels = value.levels
    if levels ~= nil and (type(levels) ~= "table" or type(levels.from) ~= "number" or type(levels.to) ~= "number") then
        fail("guide.levels", "is { from, to }")
    end
    local expanded = {
        schema = ns.modules.Schema.currentVersion, id = value.id, updated = value.updated,
        meta = {
            title = value.title, author = value.author, category = value.category, tags = value.tags,
            levels = levels and { levels.from, levels.to } or nil,
            source = value.source, materials = value.materials,
        },
        sections = {}, nodes = {}, groups = {},
    }
    if value.cond ~= nil then expanded.condition = combine("all", conditions({ cond = value.cond }, conds, "guide")) end
    if data.places ~= nil then
        if type(data.places) ~= "table" then fail("data.places", "must be a list of places") end
        expanded.places = {}
        for index, place in ipairs(data.places) do
            local converted = convertPlace(place, "data.places[" .. index .. "]")
            if converted.map == nil then converted.map = data.map end
            expanded.places[index] = converted
        end
    end
    expanded.names = { npcs = convertNPCs(data.npcs, expanded.places, data.map) }
    -- Before any title is written, since titles carry the names.
    ns.modules.Names:Add(expanded.names)
    expandingPlaces, expandingNPCs, expandingMap = expanded.places, expanded.names.npcs, data.map

    -- label -> the step it stands in front of, and the choice options waiting
    -- for it. Both are resolved once every step has a position.
    local labels, pending = {}, {}
    -- Steps carried alongside a later one, and steps carried from an earlier
    -- label until they are done or reached. Resolved with the labels.
    local companions, carriedFrom = {}, {}
    local section

    local function claim(name, index, path)
        if name == nil then return end
        if type(name) ~= "string" or name == "" then fail(path .. ".label", "a label is a name") end
        if labels[name] then fail(path .. ".label", "two things are labelled '" .. name .. "'") end
        labels[name] = index
    end

    local function addStep(step, path, inGroup, sectionMap, inherited)
        if type(step) ~= "table" then fail(path, "a step is a table") end
        local node = build(step, path, sectionMap)
        if inGroup and not ns.modules.Schema:IsGroupMember(node) then
            fail(path, "group members are quest visits or quest objectives")
        end
        local terms = append(append(inherited, conditions(step, conds, path)), markDerived(derivedTerms(step, path)))
        node.condition = combine("all", terms)
        node.index = #expanded.nodes + 1
        node.label = step.label
        claim(step.label, node.index, path)
        if step.with ~= nil then
            if type(step.with) ~= "string" or step.with == "" then fail(path .. ".with", "names the step this one is carried alongside") end
            table.insert(companions, { node = node, target = step.with, path = path })
        end
        if step.from ~= nil then
            if type(step.from) ~= "string" or step.from == "" then fail(path .. ".from", "names the earlier step this one is carried from") end
            table.insert(carriedFrom, { node = node, target = step.from, path = path })
        end
        for _, choice in ipairs(node.choices or {}) do table.insert(pending, { choice = choice, path = path }) end
        table.insert(expanded.nodes, node)
        table.insert(section.nodeIndexes, node.index)
    end

    for sectionIndex, wrapper in ipairs(data.sections) do
        local path = "data.sections[" .. sectionIndex .. "]"
        if type(wrapper) ~= "table" or type(wrapper.title) ~= "string" or type(wrapper.steps) ~= "table" then
            fail(path, "is { title, steps }")
        end
        onlyKeys(wrapper, sectionKeys, path, "a section")
        section = { id = slug(wrapper.title), title = wrapper.title, nodeIndexes = {} }
        table.insert(expanded.sections, section)
        local sectionMap = wrapper.map or data.map
        local inherited = conditions(wrapper, conds, path)
        local first = #expanded.nodes + 1
        for stepIndex, entry in ipairs(wrapper.steps) do
            local at = path .. ".steps[" .. stepIndex .. "]"
            if type(entry) == "table" and entry.group ~= nil then
                onlyKeys(entry, groupKeys, at, "a group")
                if type(entry.group) ~= "table" or #entry.group < 2 then fail(at .. ".group", "a group holds two or more steps") end
                local groupTerms = append(inherited, conditions(entry, conds, at))
                local groupFirst = #expanded.nodes + 1
                for memberIndex, member in ipairs(entry.group) do
                    local memberPath = at .. ".group[" .. memberIndex .. "]"
                    if type(member) == "table" and member.group ~= nil then fail(memberPath, "groups do not nest") end
                    addStep(member, memberPath, true, sectionMap, groupTerms)
                end
                claim(entry.label, groupFirst, at)
                table.insert(expanded.groups, { first = groupFirst, last = #expanded.nodes })
            else
                addStep(entry, at, false, sectionMap, inherited)
            end
        end
        if #section.nodeIndexes == 0 then fail(path, "has no steps") end
        claim(wrapper.label, first, path)
    end
    expandingPlaces, expandingNPCs, expandingMap = nil, nil, nil

    for _, entry in ipairs(pending) do
        local target = labels[entry.choice["next"]]
        if not target then fail(entry.path, "no step is labelled '" .. tostring(entry.choice["next"]) .. "'") end
        entry.choice["next"] = target
    end
    -- A level step's `by`: the turn-ins between it and that step count
    -- towards the level (Domain/Experience.lua).
    for _, node in ipairs(expanded.nodes) do
        local observed = node.auto and node.auto.verb == "level" and node.completion and node.completion.observed
        if observed and type(observed.by) == "string" then
            local target = labels[observed.by]
            if not target then fail("by", "no step is labelled '" .. observed.by .. "'") end
            if target <= node.index then fail("by", "`by` names a later step") end
            node.auto.by, observed.by = target, target
            node.title = Steps:Title(node, true)
        end
    end
    for _, companion in ipairs(companions) do
        local node = companion.node
        local target = labels[companion.target]
        if not target then fail(companion.path .. ".with", "no step is labelled '" .. tostring(companion.target) .. "'") end
        if target <= node.index then fail(companion.path .. ".with", "a step is carried alongside a later step, not an earlier one") end
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
        if not target then fail(entry.path .. ".from", "no step is labelled '" .. tostring(entry.target) .. "'") end
        if target >= entry.node.index then fail(entry.path .. ".from", "`from` names an earlier step") end
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

ns:RegisterModule("Steps", Steps)
