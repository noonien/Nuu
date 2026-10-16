local _, ns = ...

local GuideCheck = {}

local nodeKinds = {
    section = true, action = true, note = true, choice = true, checkpoint = true, ["end"] = true,
    travel = true, hearth = true, flight = true, portal = true, instance = true,
    acceptQuest = true, questObjective = true, turnInQuest = true, abandonQuest = true,
    talk = true, kill = true, loot = true, collect = true, useItem = true, interact = true,
    equip = true, buy = true, sell = true, bank = true, arrow = true, poi = true,
    targetMarker = true, mobRoute = true, travelRoute = true, levelTarget = true,
    xpTarget = true, train = true, talent = true, skillTarget = true, professionRecipe = true,
    craft = true, skillUp = true, gather = true, achievement = true, reputationTarget = true, currencyTarget = true,
    collectionTarget = true, itemCountTarget = true, waitFor = true, dailyReset = true,
    weeklyReset = true, cooldownReady = true, eventWindow = true,
    -- Sell and repair at a named vendor. `sell` already existed for the
    -- kind; `vendor` is the step an author writes.
    vendor = true,
    -- Cast a named spell where the step stands.
    cast = true,
    -- Follow and guard a quest NPC to where the quest ends.
    escort = true,
}

local completionTypes = { manual = true, observed = true, allChildren = true, anyChild = true }
local observedCompletionTypes = {
    always = true, location = true, level = true, quests = true, objective = true, all = true, item = true,
    hearth = true, flightpath = true, kills = true, skill = true, crafted = true, equipped = true, reputation = true,
    any = true,
    -- A step finished because a later step it belongs to was: an instruction
    -- carried alongside the step it prepares for rather than blocking on its
    -- own.
    step = true,
    -- Arrival judged by the zone or subzone the client names, not by a
    -- coordinate, or by entering a dungeon (its instance ID).
    zone = true, subzone = true, instance = true,
    -- Spells known (a class trainer visit) and a spell cast on the step.
    spell = true, cast = true,
}
-- The kinds a guide may name. This list used to be the whole story, and it
-- drifted: most of it validated fine and then evaluated to "yes" forever,
-- because nothing implemented it. It is now only the fallback for when
-- API/Client.lua is not loaded (the pure-data tests); when the client is
-- there, its predicate registry is what a condition is checked against, and
-- PredicateTests asserts every name below is registered.
local predicateKinds = {
    faction = true, race = true, class = true, season = true, hardcore = true,
    profession = true, auctionHouse = true, selfFound = true,
    -- What a step works out from its own fields: an optional turn-in's
    -- quests, an item accept's item.
    quest = true, item = true,
}

-- Exposed so PredicateTests can hold this list and the client's registry to
-- each other; a name here that nothing implements is the drift the registry
-- was introduced to stop.
GuideCheck.predicateKinds = predicateKinds

local function supportedPredicate(kind)
    local Client = ns.modules and ns.modules.Client
    if Client and Client.HasPredicate then return Client:HasPredicate(kind) end
    return predicateKinds[kind] == true
end

-- Where a material comes from. Declared by the guide, never looked up.
local materialSources = { gather = true, vendor = true, ah = true, drop = true, craft = true }

local function isNonEmptyString(value)
    return type(value) == "string" and #value > 0
end

-- A category is a path of folders split on "/": "Leveling/The Barrens".
-- Every folder needs a name, so no leading, trailing, or doubled slash.
local function hasUnnamedFolder(category)
    for part in (category .. "/"):gmatch("(.-)/") do
        if not part:match("%S") then return true end
    end
    return false
end

local function isArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
    end
    return count == #value
end

local function addError(errors, path, message)
    table.insert(errors, path .. ": " .. message)
end

local function validatePredicate(predicate, path, errors, depth)
    if type(predicate) ~= "table" then
        addError(errors, path, "must be a table")
        return
    end
    if (depth or 0) > 8 then
        addError(errors, path, "is nested too deeply")
        return
    end
    if predicate.type == "all" or predicate.type == "any" then
        if not isArray(predicate.children) or #predicate.children == 0 then
            addError(errors, path .. ".children", "must be a non-empty array")
            return
        end
        for index, child in ipairs(predicate.children) do
            validatePredicate(child, path .. ".children[" .. index .. "]", errors, (depth or 0) + 1)
        end
    elseif predicate.type == "not" or predicate.type == "now" then
        validatePredicate(predicate.child, path .. ".child", errors, (depth or 0) + 1)
    elseif not supportedPredicate(predicate.type) then
        addError(errors, path .. ".type", "is not a supported predicate")
    elseif predicate.type == "class" or predicate.type == "race" then
        if not isArray(predicate.values) or #predicate.values == 0 then addError(errors, path .. ".values", "must be a non-empty array") end
    elseif predicate.type == "quest" and type(predicate.id) ~= "number" then
        addError(errors, path .. ".id", "must be a quest ID")
    end
end

local function validateNoExecutableValues(value, path, errors, seen)
    if type(value) == "function" or type(value) == "userdata" or type(value) == "thread" then
        addError(errors, path, "contains a non-serializable executable value")
        return
    end
    if type(value) ~= "table" then return end
    seen = seen or {}
    if seen[value] then
        addError(errors, path, "contains a cycle")
        return
    end
    seen[value] = true
    for key, child in pairs(value) do
        validateNoExecutableValues(child, path .. "." .. tostring(key), errors, seen)
    end
    seen[value] = nil
end

local function validateObservedCompletion(observed, path, errors)
    if type(observed) ~= "table" or not observedCompletionTypes[observed.type] then
        addError(errors, path, "must declare a supported observed completion")
        return
    end
    if observed.type == "level" and (type(observed.atLeast) ~= "number" or observed.atLeast < 1) then
        addError(errors, path .. ".atLeast", "must be a positive level")
    elseif observed.type == "level" and observed.xp ~= nil and (type(observed.xp) ~= "number" or observed.xp < 0) then
        addError(errors, path .. ".xp", "must be a non-negative number")
    elseif observed.type == "level" and observed.by ~= nil and (type(observed.by) ~= "number" or observed.by < 1 or observed.by % 1 ~= 0) then
        addError(errors, path .. ".by", "must be a step position")
    elseif observed.type == "objective" then
        if type(observed.questID) ~= "number" then addError(errors, path .. ".questID", "must be a number") end
        if type(observed.index) ~= "number" or observed.index < 1 or observed.index % 1 ~= 0 then
            addError(errors, path .. ".index", "must be a positive integer")
        end
    elseif observed.type == "item" then
        if type(observed.itemID) ~= "number" then addError(errors, path .. ".itemID", "must be a number") end
        if observed.count ~= nil and (type(observed.count) ~= "number" or observed.count < 1) then addError(errors, path .. ".count", "must be a positive number") end
        if observed.questID ~= nil and type(observed.questID) ~= "number" then addError(errors, path .. ".questID", "must be a number") end
        if observed.startsQuestID ~= nil and type(observed.startsQuestID) ~= "number" then addError(errors, path .. ".startsQuestID", "must be a number") end
    elseif observed.type == "skill" then
        if not isNonEmptyString(observed.name) then addError(errors, path .. ".name", "must be a skill name") end
        if type(observed.atLeast) ~= "number" or observed.atLeast < 1 then addError(errors, path .. ".atLeast", "must be a positive rank") end
    elseif observed.type == "crafted" then
        if type(observed.itemID) ~= "number" then addError(errors, path .. ".itemID", "must be a number") end
        if observed.count ~= nil and (type(observed.count) ~= "number" or observed.count < 1) then addError(errors, path .. ".count", "must be a positive number") end
    elseif observed.type == "spell" then
        if not isArray(observed.ids) or #observed.ids == 0 then
            addError(errors, path .. ".ids", "must be a non-empty array of spell IDs")
        else
            for index, id in ipairs(observed.ids) do
                if type(id) ~= "number" then addError(errors, path .. ".ids[" .. index .. "]", "must be a spell ID") end
            end
        end
    elseif observed.type == "cast" then
        if type(observed.spellID) ~= "number" then addError(errors, path .. ".spellID", "must be a spell ID") end
        if observed.count ~= nil and (type(observed.count) ~= "number" or observed.count < 1) then addError(errors, path .. ".count", "must be a positive number") end
    elseif observed.type == "equipped" then
        if type(observed.itemID) ~= "number" then addError(errors, path .. ".itemID", "must be a number") end
    elseif observed.type == "reputation" then
        if type(observed.factionID) ~= "number" then addError(errors, path .. ".factionID", "must be a faction ID") end
        if type(observed.standing) ~= "number" or observed.standing < 1 or observed.standing > 8 then
            addError(errors, path .. ".standing", "must be a standing from 1 (Hated) to 8 (Exalted)")
        end
    elseif observed.type == "zone" then
        if observed.mapID == nil and not isNonEmptyString(observed.name) then addError(errors, path, "needs a mapID or a zone name") end
        if observed.mapID ~= nil and type(observed.mapID) ~= "number" then addError(errors, path .. ".mapID", "must be a map ID") end
    elseif observed.type == "instance" then
        if type(observed.instanceID) ~= "number" then addError(errors, path .. ".instanceID", "must be an instance ID") end
    elseif observed.type == "hearth" or observed.type == "flightpath" then
        if not isNonEmptyString(observed.name) then addError(errors, path .. ".name", "must be a non-empty string") end
    elseif observed.type == "kills" then
        if not isArray(observed.npcs) or #observed.npcs == 0 then
            addError(errors, path .. ".npcs", "must be a non-empty array of creature IDs")
        else
            for index, id in ipairs(observed.npcs) do
                if type(id) ~= "number" then addError(errors, path .. ".npcs[" .. index .. "]", "must be a creature ID") end
            end
        end
        if observed.count ~= nil and (type(observed.count) ~= "number" or observed.count < 1) then addError(errors, path .. ".count", "must be a positive number") end
    elseif observed.type == "all" or observed.type == "any" then
        if not isArray(observed.children) or #observed.children == 0 then
            addError(errors, path .. ".children", "must be a non-empty array")
        else
            for index, child in ipairs(observed.children) do
                validateObservedCompletion(child, path .. ".children[" .. index .. "]", errors)
            end
        end
    elseif observed.type == "quests" then
        if not isArray(observed.ids) or #observed.ids == 0 then
            addError(errors, path .. ".ids", "must be a non-empty array")
        end
        if observed.state ~= "accepted" and observed.state ~= "readyToTurnIn" and observed.state ~= "finished" and observed.state ~= "acceptedOrFinished" then
            addError(errors, path .. ".state", "must be accepted, readyToTurnIn, finished, or acceptedOrFinished")
        end
        if observed.match and observed.match ~= "all" and observed.match ~= "any" then
            addError(errors, path .. ".match", "must be all or any")
        end
    end
end

function GuideCheck:Validate(guide)
    local errors = {}
    validateNoExecutableValues(guide, "guide", errors)
    if #errors > 0 then return false, errors end
    if type(guide) ~= "table" then
        addError(errors, "guide", "must be a table")
        return false, errors
    end
    if not isNonEmptyString(guide.id) then addError(errors, "guide.id", "must be a non-empty string") end
    -- Seconds since the epoch: it says which copy is newer and when the guide
    -- last changed, where a counter needed its own prior value to increment.
    if type(guide.updated) ~= "number" or guide.updated < 1 or guide.updated % 1 ~= 0 then
        addError(errors, "guide.updated", "must be a time in seconds since the epoch")
    end
    if type(guide.meta) ~= "table" then
        addError(errors, "guide.meta", "must be a table")
    elseif not isNonEmptyString(guide.meta.title) or not isNonEmptyString(guide.meta.category) then
        addError(errors, "guide.meta", "requires title and category")
    elseif hasUnnamedFolder(guide.meta.category) then
        addError(errors, "guide.meta.category", "every folder in the path needs a name")
    elseif guide.meta.levels ~= nil and (not isArray(guide.meta.levels) or #guide.meta.levels ~= 2
        or type(guide.meta.levels[1]) ~= "number" or type(guide.meta.levels[2]) ~= "number") then
        addError(errors, "guide.meta.levels", "must be { from, to }")
    elseif guide.meta.materials ~= nil and guide.meta.materials ~= "section" and guide.meta.materials ~= "guide" then
        addError(errors, "guide.meta.materials", "must be \"section\" or \"guide\"")
    end
    if not isArray(guide.sections) or #guide.sections == 0 then
        addError(errors, "guide.sections", "must be a non-empty array")
    end
    if not isArray(guide.nodes) or #guide.nodes == 0 then
        addError(errors, "guide.nodes", "must be a non-empty array")
        return #errors == 0, errors
    end

    for index, node in ipairs(guide.nodes) do
        local path = "guide.nodes[" .. index .. "]"
        if type(node) ~= "table" then
            addError(errors, path, "must be a table")
        else
            if node.id ~= nil then addError(errors, path .. ".id", "steps use array indexes, not IDs") end
            if not nodeKinds[node.kind] then addError(errors, path .. ".kind", "is not supported") end
            if not isNonEmptyString(node.title) then addError(errors, path .. ".title", "must be a non-empty string") end
            if node.completion and (type(node.completion) ~= "table" or not completionTypes[node.completion.type]) then
                addError(errors, path .. ".completion.type", "is not supported")
            elseif node.completion and node.completion.type == "observed" then
                validateObservedCompletion(node.completion.observed, path .. ".completion.observed", errors)
                if type(node.completion.observed) == "table" and node.completion.observed.type == "location" and type(node.location) ~= "table" then
                    addError(errors, path .. ".location", "is required by an observed location completion")
                end
            end
            if node.location then
                local location = node.location
                if type(location) ~= "table" or type(location.mapID) ~= "number" then
                    addError(errors, path .. ".location", "requires a numeric mapID")
                elseif type(location.x) ~= "number" or location.x < 0 or location.x > 1 or type(location.y) ~= "number" or location.y < 0 or location.y > 1 then
                    addError(errors, path .. ".location", "requires x and y between 0 and 1")
                elseif location.arrivalRadiusNormalized and (type(location.arrivalRadiusNormalized) ~= "number" or location.arrivalRadiusNormalized < 0) then
                    addError(errors, path .. ".location.arrivalRadiusNormalized", "must be a non-negative number")
                end
                if type(location) == "table" and location.spots ~= nil then
                    if not isArray(location.spots) then
                        addError(errors, path .. ".location.spots", "must be an array")
                    else
                        for spotIndex, spot in ipairs(location.spots) do
                            if type(spot) ~= "table" or type(spot.x) ~= "number" or type(spot.y) ~= "number" or spot.x < 0 or spot.x > 1 or spot.y < 0 or spot.y > 1 then
                                addError(errors, path .. ".location.spots[" .. spotIndex .. "]", "requires x and y between 0 and 1")
                            end
                        end
                    end
                end
            end
            if node.needs ~= nil then
                if not isArray(node.needs) or #node.needs == 0 then
                    addError(errors, path .. ".needs", "must be a non-empty array of materials")
                else
                    for needIndex, material in ipairs(node.needs) do
                        local needPath = path .. ".needs[" .. needIndex .. "]"
                        if type(material) ~= "table" or type(material.itemID) ~= "number" then
                            addError(errors, needPath .. ".itemID", "must be an item ID")
                        elseif type(material.count) ~= "number" or material.count < 1 or material.count % 1 ~= 0 then
                            addError(errors, needPath .. ".count", "must be a positive whole number")
                        elseif not materialSources[material.source] then
                            addError(errors, needPath .. ".source", "must be gather, vendor, ah, drop, or craft")
                        end
                    end
                end
            end
            if node.use ~= nil then
                if not isArray(node.use) or #node.use == 0 then
                    addError(errors, path .. ".use", "must be a non-empty array of item IDs")
                else
                    for useIndex, itemID in ipairs(node.use) do
                        if type(itemID) ~= "number" or itemID < 1 or itemID % 1 ~= 0 then
                            addError(errors, path .. ".use[" .. useIndex .. "]", "must be an item ID")
                        end
                    end
                end
            end
            if node.condition then validatePredicate(node.condition, path .. ".condition", errors) end
        end
    end
    for index, node in ipairs(guide.nodes) do
        if type(node) == "table" then
            local path = "guide.nodes[" .. index .. "]"
            if node["next"] ~= nil and not self:IsStepIndex(guide, node["next"]) then addError(errors, path .. ".next", "does not reference a node") end
            if node.choices then
                if not isArray(node.choices) then
                    addError(errors, path .. ".choices", "must be an array")
                else
                    for choiceIndex, choice in ipairs(node.choices) do
                        if type(choice) ~= "table" or not self:IsStepIndex(guide, choice["next"]) then
                            addError(errors, path .. ".choices[" .. choiceIndex .. "]", "must reference a node")
                        elseif choice.condition then
                            validatePredicate(choice.condition, path .. ".choices[" .. choiceIndex .. "].condition", errors)
                        end
                    end
                end
            end
        end
    end
    if isArray(guide.sections) then
        for index, section in ipairs(guide.sections) do
            local path = "guide.sections[" .. index .. "]"
            if type(section) ~= "table" or not isNonEmptyString(section.id) or not isNonEmptyString(section.title) then
                addError(errors, path, "requires id and title")
            elseif not isArray(section.nodeIndexes) then
                addError(errors, path .. ".nodeIndexes", "must be an array of step indexes")
            else
                for nodeIndex, stepIndex in ipairs(section.nodeIndexes) do
                    if not self:IsStepIndex(guide, stepIndex) then addError(errors, path .. ".nodeIndexes[" .. nodeIndex .. "]", "does not reference a node") end
                end
            end
        end
    end
    self:ValidateGroups(guide, errors)
    self:ValidatePlaces(guide, errors)
    self:ValidateNames(guide, errors)
    return #errors == 0, errors
end


-- Guide places (caves, tunnels, one-door buildings): see docs/guide-source.md.
-- Points and connections are plain lists, so a connection names a point by its
-- position or by its `id`. Fields this does not know are left alone.
local function isASCII(value)
    return type(value) ~= "string" or not value:find("[\128-\255]")
end

local function pointIndex(place, ref)
    if type(ref) == "number" then
        if ref % 1 == 0 and type(place.points[ref]) == "table" then return ref end
        return nil
    end
    if type(ref) ~= "string" then return nil end
    for index, point in ipairs(place.points) do
        if type(point) == "table" and point.id == ref then return index end
    end
    return nil
end

-- A place's connections as { a, b, oneWay } with duplicates merged, plus
-- the problems found, and the duplicates (the editor reports those as a
-- warning; they change nothing).
function GuideCheck:PlaceConnections(place)
    local list, problems, duplicates, seen = {}, {}, {}, {}
    for index, connection in ipairs(isArray(place.connections) and place.connections or {}) do
        local path = ".connections[" .. index .. "]"
        if not isArray(connection) or #connection < 2 or #connection > 3 then
            table.insert(problems, { path, "must be { a, b } or { a, b, true }" })
        else
            local a, b = pointIndex(place, connection[1]), pointIndex(place, connection[2])
            if not a or not b then
                table.insert(problems, { path, "names a point the place does not have" })
            elseif a == b then
                table.insert(problems, { path, "joins a point to itself" })
            elseif connection[3] ~= nil and connection[3] ~= true then
                table.insert(problems, { path, "third value must be true (one-way) or left out" })
            else
                local oneWay = connection[3] == true
                local key = math.min(a, b) .. "-" .. math.max(a, b)
                local earlier = seen[key]
                if earlier then
                    if earlier.oneWay ~= oneWay or (oneWay and earlier.a ~= a) then
                        table.insert(problems, { path, "joins the same two points as another connection, one way and both ways" })
                    else
                        table.insert(duplicates, index)
                    end
                else
                    seen[key] = { a = a, b = b, oneWay = oneWay }
                    table.insert(list, { a = a, b = b, oneWay = oneWay })
                end
            end
        end
    end
    return list, problems, duplicates
end

local function isPoint(at)
    return type(at) == "table" and type(at[1]) == "number" and type(at[2]) == "number"
        and (at.map == nil or type(at.map) == "number")
end

-- An NPC the guide visits: { "Name", at = ..., note = "...", instance = id }.
-- `at` is one point { x, y } (with map when it is not the guide's), a list
-- of them (the spots it may be at; the arrow takes the nearest), or a place
-- point "cave.chamber". `instance` is the dungeon it is inside.
local function validateNPCEntry(entry, path, errors)
    if not isNonEmptyString(entry[1]) or not isASCII(entry[1]) then addError(errors, path, "must start with a non-empty ASCII name") end
    for key in pairs(entry) do
        if key ~= 1 and key ~= "at" and key ~= "note" and key ~= "instance" then
            addError(errors, path .. "." .. tostring(key), "is not at, note, or instance")
        end
    end
    local at = entry.at
    local valid = at == nil or isPoint(at) or (type(at) == "string" and at:find(".", 1, true) ~= nil)
    if not valid and type(at) == "table" and #at > 0 then
        valid = true
        for _, spot in ipairs(at) do valid = valid and isPoint(spot) end
    end
    if not valid then
        addError(errors, path .. ".at", "must be a point { x, y }, a list of them, or a place point")
    end
    if entry.instance ~= nil and type(entry.instance) ~= "number" then
        addError(errors, path .. ".instance", "must be an instance ID")
    end
    if entry.note ~= nil and (not isNonEmptyString(entry.note) or not isASCII(entry.note)) then
        addError(errors, path .. ".note", "must be non-empty ASCII text")
    end
end

-- The guide's names for its IDs: { npcs = { [id] = "Name" }, ... }.
local nameKinds = { npcs = true, quests = true, items = true, factions = true, spells = true }
function GuideCheck:ValidateNames(guide, errors)
    local names = guide.names
    if names == nil then return end
    if type(names) ~= "table" then
        addError(errors, "guide.names", "must be a table of names by kind")
        return
    end
    for kind, entries in pairs(names) do
        local path = "guide.names." .. tostring(kind)
        if not nameKinds[kind] then
            addError(errors, path, "is not npcs, quests, items, factions or spells")
        elseif type(entries) ~= "table" then
            addError(errors, path, "must map IDs to names")
        else
            for id, name in pairs(entries) do
                if type(id) ~= "number" or id < 1 or id % 1 ~= 0 then
                    addError(errors, path, "has a key that is not an ID: " .. tostring(id))
                elseif kind == "npcs" and type(name) == "table" then
                    validateNPCEntry(name, path .. "[" .. id .. "]", errors)
                elseif not isNonEmptyString(name) or not isASCII(name) then
                    addError(errors, path .. "[" .. id .. "]", "must be a non-empty ASCII name")
                end
            end
        end
    end
end

function GuideCheck:ValidatePlaces(guide, errors)
    local places = guide.places
    if places == nil then return end
    if not isArray(places) then
        addError(errors, "guide.places", "must be a list of places")
        return
    end
    local ids = {}
    for placeIndex, place in ipairs(places) do
        local path = "guide.places[" .. placeIndex .. "]"
        if type(place) ~= "table" then
            addError(errors, path, "must be a table")
        else
            if not isNonEmptyString(place.place) or place.place:find("%.") or not isASCII(place.place) then
                addError(errors, path .. ".place", "must be an ASCII ID without a dot")
            elseif ids[place.place] then
                addError(errors, path .. ".place", "repeats the ID of another place")
            else
                ids[place.place] = true
            end
            if place.name ~= nil and (not isNonEmptyString(place.name) or not isASCII(place.name)) then
                addError(errors, path .. ".name", "must be ASCII text")
            end
            if place.width ~= nil and (type(place.width) ~= "number" or place.width < 5 or place.width > 60) then
                addError(errors, path .. ".width", "must be 5 to 60 yards")
            end
            if place.map ~= nil and type(place.map) ~= "number" then addError(errors, path .. ".map", "must be a map ID") end
            if not isArray(place.points) or #place.points == 0 then
                addError(errors, path .. ".points", "must be a non-empty list of points")
            else
                local pointIDs, entrances = {}, 0
                for pointIndexValue, point in ipairs(place.points) do
                    local pointPath = path .. ".points[" .. pointIndexValue .. "]"
                    if type(point) ~= "table" then
                        addError(errors, pointPath, "must be a table")
                    else
                        local at = point.at
                        if not isArray(at) or #at ~= 2 or type(at[1]) ~= "number" or type(at[2]) ~= "number"
                            or at[1] < 0 or at[2] < 0 or at[1] > 100 or at[2] > 100 then
                            addError(errors, pointPath .. ".at", "must be { x, y } map percentages")
                        end
                        if point.kind ~= nil and point.kind ~= "entrance" and point.kind ~= "exit" then
                            addError(errors, pointPath .. ".kind", "must be entrance or exit, or left out")
                        end
                        if point.kind == "entrance" then entrances = entrances + 1 end
                        if point.map ~= nil and type(point.map) ~= "number" then addError(errors, pointPath .. ".map", "must be a map ID") end
                        if point.label ~= nil and (type(point.label) ~= "string" or not isASCII(point.label)) then
                            addError(errors, pointPath .. ".label", "must be ASCII text")
                        end
                        if point.id ~= nil then
                            if not isNonEmptyString(point.id) or point.id:find("%.") or not isASCII(point.id) or tonumber(point.id) then
                                addError(errors, pointPath .. ".id", "must be an ASCII name without a dot")
                            elseif pointIDs[point.id] then
                                addError(errors, pointPath .. ".id", "repeats another point's ID in this place")
                            else
                                pointIDs[point.id] = true
                            end
                        end
                    end
                end
                if entrances == 0 then addError(errors, path, "needs at least one entrance") end
                if place.connections ~= nil and not isArray(place.connections) then
                    addError(errors, path .. ".connections", "must be a list")
                else
                    local connections, problems = self:PlaceConnections(place)
                    for _, problem in ipairs(problems) do addError(errors, path .. problem[1], problem[2]) end
                    -- Every point is reachable from an entrance, and every
                    -- point has a way back out.
                    local forward, backward = {}, {}
                    for _, connection in ipairs(connections) do
                        forward[connection.a] = forward[connection.a] or {}
                        table.insert(forward[connection.a], connection.b)
                        backward[connection.b] = backward[connection.b] or {}
                        table.insert(backward[connection.b], connection.a)
                        if not connection.oneWay then
                            forward[connection.b] = forward[connection.b] or {}
                            table.insert(forward[connection.b], connection.a)
                            backward[connection.a] = backward[connection.a] or {}
                            table.insert(backward[connection.a], connection.b)
                        end
                    end
                    local function spread(starts, edges)
                        local reached, queue = {}, {}
                        for _, index in ipairs(starts) do reached[index] = true; table.insert(queue, index) end
                        while #queue > 0 do
                            local index = table.remove(queue)
                            for _, other in ipairs(edges[index] or {}) do
                                if not reached[other] then reached[other] = true; table.insert(queue, other) end
                            end
                        end
                        return reached
                    end
                    local ins, outs = {}, {}
                    for index, point in ipairs(place.points) do
                        if type(point) == "table" and point.kind == "entrance" then table.insert(ins, index) end
                        if type(point) == "table" and point.kind then table.insert(outs, index) end
                    end
                    local reachable, leaving = spread(ins, forward), spread(outs, backward)
                    for index, point in ipairs(place.points) do
                        if type(point) == "table" and entrances > 0 then
                            if not reachable[index] then
                                addError(errors, path .. ".points[" .. index .. "]", "cannot be reached from an entrance")
                            elseif not leaving[index] then
                                addError(errors, path .. ".points[" .. index .. "]", "has no way to an entrance or exit")
                            end
                        end
                    end
                end
            end
        end
    end
    -- Steps that name a place's point.
    local Steps = ns.modules.Steps
    for index, node in ipairs(isArray(guide.nodes) and guide.nodes or {}) do
        local location = type(node) == "table" and node.location
        if type(location) == "table" then
            for _, key in ipairs({ "point", "near" }) do
                local reference = location[key]
                if reference ~= nil and not (Steps and Steps.FindPlacePoint(places, reference)) then
                    addError(errors, "guide.nodes[" .. index .. "].location." .. key, "names no place point: " .. tostring(reference))
                end
            end
        end
    end
end

function GuideCheck:IsStepIndex(guide, index)
    return type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #guide.nodes
end

-- Derived positions, never authored identities. Refresh after structural edits.
function GuideCheck:IndexNodes(guide)
    for index, node in ipairs(guide.nodes) do node.index = index end
    return guide
end

function GuideCheck:IsQuestVisit(node)
    return type(node) == "table" and (node.kind == "acceptQuest" or node.kind == "turnInQuest" or node.kind == "talk")
end

-- What a group may hold: quest visits, and the quest work done in one place
-- (three kinds of mob in one camp) that the player does in whatever order
-- the mobs come.
GuideCheck.groupKinds = { acceptQuest = true, turnInQuest = true, talk = true,
    kill = true, collect = true, interact = true, questObjective = true }

-- Any other step that finishes a quest objective is quest work too: the
-- thread bought for one, the graveyard an escort's scene starts at.
local function finishesObjective(observed)
    if type(observed) ~= "table" then return false end
    if observed.type == "objective" then return true end
    for _, child in ipairs(observed.type == "any" and observed.children or {}) do
        if finishesObjective(child) then return true end
    end
    return false
end

function GuideCheck:IsGroupMember(node)
    if type(node) ~= "table" or node["next"] ~= nil or node.choices ~= nil then return false end
    if self.groupKinds[node.kind] == true then return true end
    return node.completion ~= nil and node.completion.type == "observed" and finishesObjective(node.completion.observed)
end

function GuideCheck:GroupAt(guide, index)
    if not index then return nil end
    for _, group in ipairs(guide.groups or {}) do
        if index >= group.first and index <= group.last then return group end
    end
end

function GuideCheck:ValidateGroups(guide, errors)
    if guide.groups == nil then return end
    if not isArray(guide.groups) then
        addError(errors, "guide.groups", "must be an array of step ranges")
        return
    end
    local last = 0
    for index, group in ipairs(guide.groups) do
        local path = "guide.groups[" .. index .. "]"
        if type(group) ~= "table" or not self:IsStepIndex(guide, group.first) or not self:IsStepIndex(guide, group.last) or group.first >= group.last then
            addError(errors, path, "requires first and last indexes covering at least two steps")
        else
            for key in pairs(group) do
                if key ~= "first" and key ~= "last" then addError(errors, path, "only first and last are supported") end
            end
            if group.first <= last then addError(errors, path, "groups must be ordered and must not overlap") end
            last = group.last
            for member = group.first, group.last do
                if not self:IsGroupMember(guide.nodes[member]) then
                    addError(errors, path, "members must be quest visits or quest objectives without next or choice edges")
                end
            end
            -- A section break is an author-visible group boundary.
            local sectionMatch = false
            for _, section in ipairs(isArray(guide.sections) and guide.sections or {}) do
                if type(section) == "table" and isArray(section.nodeIndexes) then
                    local included = {}
                    for _, member in ipairs(section.nodeIndexes) do included[member] = true end
                    local containsAll = true
                    for member = group.first, group.last do if not included[member] then containsAll = false end end
                    if containsAll then sectionMatch = true end
                end
            end
            if not sectionMatch then addError(errors, path, "must belong to one section") end
        end
    end
end

ns:RegisterModule("GuideCheck", GuideCheck)
