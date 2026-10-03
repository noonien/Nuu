local _, ns = ...

-- NuuRoad's optional API for other addons. The profession planner
-- (NuuProfessions) calls it for "take me there" on a trainer or vendor row,
-- and anyone may: it is `_G.NuuRoad.API`, looked up when a feature is used,
-- never at load, and skipped when missing or when `apiVersion` differs.
--
-- Plain functions taking and returning IDs, numbers, strings and plain
-- tables: no frames, no module objects. Each reaches the module that does
-- the work when it is called, so a missing module (a stripped build, a load
-- error) makes the call answer nil or false rather than fail. A new function
-- is a minor change; changing or removing one bumps `apiVersion`.
--
-- Nothing here starts, changes or finishes a guide on its own: the player
-- does that in NuuRoad's windows. StartGuideAt opens the guide browser on
-- the guide and leaves the start to them.
local API = { apiVersion = 1 }

local function find(name)
    local modules = ns.modules
    return modules and modules[name] or nil
end

local function safe(func, ...)
    local ok, a, b = pcall(func, ...)
    if not ok then
        if ns.Log then ns:Log("API: " .. tostring(a)) end
        return nil
    end
    return a, b
end

-- Routes the player to a place through the travel planner, the arrow
-- pointed at it until they arrive. `target = { mapID, x, y, label, npcID }`,
-- x and y as 0-1 or map percent. True, or false and why not. A route is a
-- suggestion like every other: the player walks it.
function API.Route(target)
    local Route = find("TravelRoute")
    if type(target) ~= "table" or not (Route and Route.RouteTo) then return false, "NuuRoad cannot route" end
    local ok, why = safe(Route.RouteTo, Route, target)
    return ok == true, why
end

-- Clears the route Route started, if it is still the one followed. True when
-- there was one to clear.
function API.StopRoute()
    local Route = find("TravelRoute")
    if not (Route and Route.StopRoute) then return false end
    return safe(Route.StopRoute, Route) == true
end

-- Where an NPC stands, from NuuRoad's own data: the travel data's flight
-- masters first, then the first step of any guide that sends the player to
-- talk to it (a step that only kills it says where it roams, not where it
-- stands, and is passed over). `{ mapID, x, y, label, npcID, source }` with
-- x and y from 0 to 1, ready to hand to Route, or nil when NuuRoad does not
-- know.
local function travelLocation(npcID)
    for _, flight in ipairs(ns.travel and ns.travel.flights or {}) do
        if flight.npc == npcID and type(flight.map) == "number" and type(flight.at) == "table" then
            local x, y = tonumber(flight.at[1]), tonumber(flight.at[2])
            if x and y then
                return { mapID = flight.map, x = x / 100, y = y / 100, label = flight.name, npcID = npcID, source = "travel" }
            end
        end
    end
    return nil
end

local function contains(list, id)
    for _, value in ipairs(type(list) == "table" and list or {}) do
        if value == id then return true end
    end
    return false
end

local function killedOn(node, npcID)
    local auto, completion = node.auto, node.completion
    if auto and contains(auto.kill, npcID) then return true end
    local observed = completion and completion.observed
    return type(observed) == "table" and observed.type == "kills" and contains(observed.npcs, npcID)
end

local function guideLocation(npcID)
    local Repository = find("GuideRepository")
    if not (Repository and Repository.List) then return nil end
    local Names = find("Names")
    for _, guide in ipairs(Repository:List() or {}) do
        for _, node in ipairs(guide.nodes or {}) do
            local location = node.location
            -- Map 0 is a fixture's "wherever the player is", no place at all.
            if location and type(location.mapID) == "number" and location.mapID ~= 0
                and type(location.x) == "number" and type(location.y) == "number"
                and contains(node.refs and node.refs.npcs, npcID) and not killedOn(node, npcID) then
                return { mapID = location.mapID, x = location.x, y = location.y,
                    label = Names and Names.NPC and Names:NPC(npcID) or nil, npcID = npcID, source = "guide",
                    guideID = guide.id, step = node.index }
            end
        end
    end
    return nil
end

function API.NPCLocation(npcID)
    npcID = tonumber(npcID)
    if not npcID then return nil end
    return safe(travelLocation, npcID) or safe(guideLocation, npcID)
end

-- The guides that handle a quest, as `{ { guideID, title, steps = { { index,
-- role } }, first = index }, ... }` in title order (role: accept, turnin,
-- objective, collect, track or step). An empty list when none does.
function API.QuestGuides(questID)
    questID = tonumber(questID)
    local Index = find("QuestIndex")
    if not (questID and Index and Index.GuidesFor) then return {} end
    local entries = safe(Index.GuidesFor, Index, questID) or {}
    local result = {}
    for _, entry in ipairs(entries) do
        local steps = {}
        for _, step in ipairs(entry.steps or {}) do table.insert(steps, { index = step.index, role = step.role }) end
        local first = Index.FirstStep and Index:FirstStep(entry)
        table.insert(result, { guideID = entry.guide.id, title = entry.guide.meta and entry.guide.meta.title or nil,
            steps = steps, first = first and first.index or nil })
    end
    return result
end

-- Offers a guide to the player: the guide browser opens searched for the
-- quest (when one is given) with the guide chosen and its details shown,
-- and the player starts it there, or not. Never starts or switches a guide
-- itself. True when the browser opened.
function API.StartGuideAt(guideID, questID)
    local Repository, Browser = find("GuideRepository"), find("GuideBrowser")
    if not (Repository and Browser) then return false end
    local guide = guideID ~= nil and safe(Repository.Get, Repository, guideID) or nil
    questID = tonumber(questID)
    if not guide and not questID then return false end
    if questID and Browser.ShowQuest then
        safe(Browser.ShowQuest, Browser, questID)
    elseif Browser.Show then
        safe(Browser.Show, Browser)
    end
    local shown = Browser.IsShown and safe(Browser.IsShown, Browser)
    if shown and guide and Browser.Pick then safe(Browser.Pick, Browser, guide) end
    return shown == true
end

ns.API = API
