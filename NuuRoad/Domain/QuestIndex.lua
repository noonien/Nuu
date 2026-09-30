local _, ns = ...

-- Which guides a quest appears in, and at which steps, answering "is this
-- quest in a guide?". The index is rebuilt from the repository whenever a
-- guide is saved
-- and is read by the quest log button, the quest offer dialog, and the guide
-- picker's search.
--
-- Pure logic: no frames, no Blizzard API. A quest's role on a step is one of
-- accept, turnin, objective, collect (a quest item or an item that begins the
-- quest), track (a sticky reminder), or step for a hand-written node whose
-- completion names the quest without saying how.
local QuestIndex = {}

local roleWords = { accept = "accepted", turnin = "turned in", objective = "worked on", collect = "item picked up", track = "kept in view", step = "named" }
local roleOrder = { accept = 1, objective = 2, collect = 3, track = 4, turnin = 5, step = 6 }

local function add(found, id, role)
    if type(id) ~= "number" then return end
    for _, entry in ipairs(found) do
        if entry.id == id then
            -- A talk step both turns in and accepts; keep the more specific role.
            if entry.role == "step" then entry.role = role end
            return
        end
    end
    table.insert(found, { id = id, role = role })
end

local stateRoles = { accepted = "accept", acceptedOrFinished = "accept", readyToTurnIn = "objective", finished = "turnin" }

local function walkObserved(observed, found)
    if type(observed) ~= "table" then return end
    if observed.type == "all" or observed.type == "any" then
        for _, child in ipairs(observed.children or {}) do walkObserved(child, found) end
    elseif observed.type == "quests" then
        for _, id in ipairs(observed.ids or {}) do add(found, id, stateRoles[observed.state] or "step") end
    elseif observed.type == "objective" then
        add(found, observed.questID, "objective")
    elseif observed.type == "item" then
        add(found, observed.startsQuestID, "collect")
        add(found, observed.questID, "collect")
    end
end

-- Every quest a node refers to, as { id, role }, in the order they are named.
function QuestIndex:NodeQuests(node)
    local found = {}
    if type(node) ~= "table" then return found end
    local auto = node.auto
    if auto then
        local verb = auto.verb
        if verb == "accept" or verb == "turnin" then
            for _, id in ipairs(auto.quests or {}) do add(found, id, verb) end
        elseif verb == "talk" then
            for _, id in ipairs(auto.turnin or {}) do add(found, id, "turnin") end
            for _, id in ipairs(auto.accept or {}) do add(found, id, "accept") end
        elseif verb == "objective" or verb == "objectives" or verb == "escort" then
            for _, id in ipairs(auto.quests or {}) do add(found, id, "objective") end
        elseif verb == "collect" then
            add(found, auto.starts, "collect")
            add(found, auto.quest, "collect")
        elseif verb == "track" or verb == "untrack" then
            add(found, auto.track or auto.untrack, "track")
        end
    end
    if node.completion and node.completion.type == "observed" then walkObserved(node.completion.observed, found) end
    for _, id in ipairs(node.refs and node.refs.quests or {}) do add(found, id, "step") end
    return found
end

local function repository() return ns.modules and ns.modules.GuideRepository end

-- { [questID] = { { guide, steps = { { index, role } } } } }, rebuilt
-- when the repository's version moves (a guide saved or deleted).
function QuestIndex:Build()
    local Repository = repository()
    local version = Repository and Repository.version or 0
    if self.cache and self.cacheVersion == version then return self.cache end
    local byQuest, searchText = {}, {}
    for _, guide in ipairs(Repository and Repository:List() or {}) do
        local perGuide = {}
        for index, node in ipairs(guide.nodes or {}) do
            for _, quest in ipairs(self:NodeQuests(node)) do
                local entry = perGuide[quest.id]
                if not entry then
                    entry = { guide = guide, steps = {} }
                    perGuide[quest.id] = entry
                    byQuest[quest.id] = byQuest[quest.id] or {}
                    table.insert(byQuest[quest.id], entry)
                end
                table.insert(entry.steps, { index = index, role = quest.role })
            end
        end
        searchText[guide.id] = perGuide
    end
    for _, entries in pairs(byQuest) do
        table.sort(entries, function(a, b) return (a.guide.meta.title or "") < (b.guide.meta.title or "") end)
    end
    self.cache, self.cacheVersion, self.questsByGuide = byQuest, version, searchText
    return byQuest
end

function QuestIndex:Invalidate()
    self.cache = nil
end

-- The guides that mention a quest, alphabetically, each with its steps in
-- guide order. An empty list when no guide does.
function QuestIndex:GuidesFor(questID)
    if type(questID) ~= "number" then return {} end
    return self:Build()[questID] or {}
end

-- The quest a title stands for among the quests any guide names, for clients
-- that hand the addon a quest title but no ID.
function QuestIndex:QuestIDByTitle(title)
    if type(title) ~= "string" then return nil end
    title = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if #title == 0 then return nil end
    local Names = ns.modules.Names
    for id in pairs(self:Build()) do
        local name = Names and Names:Quest(id)
        if type(name) == "string" and name:lower() == title then return id end
    end
    return nil
end

-- "accepted at step 3, worked on at step 5, turned in at step 7": one clause
-- per step of a guide entry, in guide order.
function QuestIndex:DescribeSteps(entry)
    local clauses = {}
    for _, step in ipairs(entry.steps or {}) do
        table.insert(clauses, (roleWords[step.role] or roleWords.step) .. " at step " .. tostring(step.index))
    end
    return table.concat(clauses, ", ")
end

-- The first step of a guide entry that does anything with the quest: the
-- accept when there is one, otherwise the earliest step.
function QuestIndex:FirstStep(entry)
    local best
    for _, step in ipairs(entry.steps or {}) do
        if not best or (roleOrder[step.role] or 9) < (roleOrder[best.role] or 9) or ((roleOrder[step.role] or 9) == (roleOrder[best.role] or 9) and step.index < best.index) then
            best = step
        end
    end
    return best
end

-- Lower-case text of every quest a guide names, its titles and "quest:<id>"
-- tokens, for the guide picker's search box.
function QuestIndex:SearchText(guide)
    self:Build()
    local perGuide = guide and self.questsByGuide and self.questsByGuide[guide.id]
    if not perGuide then return "" end
    local Names = ns.modules.Names
    local words = {}
    for id in pairs(perGuide) do
        table.insert(words, "quest:" .. tostring(id))
        local name = Names and Names:Quest(id)
        if type(name) == "string" then table.insert(words, name:lower()) end
    end
    table.sort(words)
    return table.concat(words, " ")
end

ns:RegisterModule("QuestIndex", QuestIndex)
