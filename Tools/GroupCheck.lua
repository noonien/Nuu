-- Lists steps in NuuRoad's packaged guides that could share one card as a
-- group but stand alone: neighbouring kill, collect, and objective steps on
-- the same mobs or at the same spots. With --visits it also lists
-- neighbouring quest visits at the same NPC or a few steps apart, which is
-- noisier: a chain handed from one NPC to the next reads well as separate
-- steps. It only reports; whether a pair belongs on one card is the author's
-- call (NuuRoad/docs/guide-schema.md, groups). Run from the repository root:
--
--   lua Tools/GroupCheck.lua [--visits] [guide.lua ...]
--
-- With no files it reads every guide under NuuRoad/Data/Guides (the export
-- format, NuuRoad/docs/examples/guide-export.lua). Pairs no one character can
-- see both of (two classes, two factions) are left out.

local SAME_SPOT = 0.015 -- field steps this close share a camp (map fraction)
local VISIT_REACH = 0.02 -- talk steps' default arrival radius


-- Source with every table constructor tagged by its line, so a step can be
-- reported where it is written: "{" becomes "{__line=N;". Strings and
-- comments are copied untouched.
local function tagLines(src)
    local out, i, line, n = {}, 1, 1, #src
    local function copyTo(j)
        local piece = src:sub(i, j)
        for _ in piece:gmatch("\n") do line = line + 1 end
        table.insert(out, piece)
        i = j + 1
    end
    while i <= n do
        local c = src:sub(i, i)
        if c == "{" then
            table.insert(out, "{__line=" .. line .. ";")
            i = i + 1
        elseif c == "\n" then
            copyTo(i)
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n and src:sub(j, j) ~= c do
                if src:sub(j, j) == "\\" then j = j + 1 end
                j = j + 1
            end
            copyTo(j)
        elseif src:sub(i, i + 1) == "--" or c == "[" then
            local level = src:match("^%-?%-?%[(=*)%[", i)
            if level then
                local _, close = src:find("]" .. level .. "]", i, true)
                copyTo(close or n)
            elseif src:sub(i, i + 1) == "--" then
                local close = src:find("\n", i, true)
                copyTo((close or n + 1) - 1)
            else
                copyTo(i)
            end
        else
            local j = src:find("[{\n\"'%-%[]", i + 1) or n + 1
            copyTo(j - 1)
        end
    end
    return table.concat(out)
end

local function loadTagged(path, ns)
    local file = assert(io.open(path, "rb"))
    local src = file:read("*a")
    file:close()
    local chunk = assert(loadstring(tagLines(src), "@" .. path))
    chunk(nil, ns)
end

-- NPC names, from the guide being checked; the client names the rest.
local npcNames = {}
local function npcName(id) return npcNames[id] or ("npc " .. id) end
local function itemName(id) return "item " .. id end
local function questName(id) return "quest " .. id end

local function list(v)
    if v == nil then return {} end
    if type(v) == "table" then
        local out = {}
        for _, x in ipairs(v) do table.insert(out, x) end
        return out
    end
    return { v }
end

-- What a step is, as far as grouping goes: "field" work in a camp, a quest
-- "visit" at an NPC, or "other".
local function kind(step)
    if step.type == "kill" or step.type == "collect" then return "field" end
    if step.type == "interact" and step.at then return "field" end
    if step.type == "accept" or step.type == "turnin" or step.type == "talk" then return "visit" end
    return "other"
end

-- Points are hundredths of a map percent, each on its own map or the section's.
local function points(step, map)
    local out = {}
    for _, p in ipairs(type(step.at) == "table" and step.at or {}) do
        table.insert(out, { x = p[1] / 10000, y = p[2] / 10000, map = p.map or map })
    end
    return out
end

-- The nearest two points of the steps, as a map fraction, or nil.
local function nearest(a, b)
    local best
    for _, p in ipairs(a.points) do
        for _, q in ipairs(b.points) do
            if p.map == q.map then
                local d = math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2)
                if not best or d < best then best = d end
            end
        end
    end
    return best
end

-- Which classes or factions a step's `cond` limits it to (its `key`), or
-- nil when it names none.
local function limitedTo(step, key)
    local value = type(step.cond) == "table" and step.cond[key]
    if value == nil then return nil end
    local found = {}
    for _, word in ipairs(type(value) == "table" and value or { value }) do found[word] = true end
    return found
end

local function disjoint(a, b)
    if not a or not b then return false end
    for class in pairs(a) do
        if b[class] then return false end
    end
    return true
end

local visits = false

local function describe(step)
    if step.type == "kill" or step.type == "collect" then
        local quest = type(step.quest) == "table" and step.quest or nil
        local what = step.type == "collect" and ("collect " .. itemName(step.item))
            or quest and ("objective " .. questName(quest[1]) .. " #" .. quest[2])
            or "kill"
        local mobs = {}
        for _, id in ipairs(list(step.kill)) do table.insert(mobs, npcName(id)) end
        if #mobs > 0 then what = what .. " (" .. table.concat(mobs, ", ") .. ")" end
        return what
    end
    if kind(step) == "visit" then
        local parts = {}
        local turnin = step.type == "turnin" and step.quests or step.turnin
        local accept = step.type == "accept" and step.quests or step.accept
        if turnin then table.insert(parts, "turn in " .. questName(turnin[1])) end
        if accept then table.insert(parts, "accept " .. questName(accept[1])) end
        if #parts == 0 then table.insert(parts, "talk") end
        return table.concat(parts, ", ") .. (step.npc and (" at " .. npcName(step.npc[1])) or "")
    end
    return step.object or step.type or "step"
end

-- Why two standalone steps could share a card, or nil.
local function reason(a, b)
    local k = kind(a.step)
    if k ~= kind(b.step) or not (k == "field" or (k == "visit" and visits)) then return nil end
    if disjoint(limitedTo(a.step, "class"), limitedTo(b.step, "class"))
        or disjoint(limitedTo(a.step, "faction"), limitedTo(b.step, "faction")) then
        return nil
    end
    local d = nearest(a, b)
    if k == "field" then
        local shared = {}
        local mobs = {}
        for _, id in ipairs(list(a.step.kill)) do mobs[id] = true end
        for _, id in ipairs(list(b.step.kill)) do
            if mobs[id] then table.insert(shared, npcName(id)) end
        end
        if #shared > 0 then return "same mobs: " .. table.concat(shared, ", ") end
        if d and d <= SAME_SPOT then return "same spots" end
    else
        local npcs = {}
        for _, id in ipairs(list(a.step.npc)) do npcs[id] = true end
        for _, id in ipairs(list(b.step.npc)) do
            if npcs[id] then return "same NPC: " .. npcName(id) end
        end
        if d and d <= VISIT_REACH then return string.format("NPCs %.1f%% apart", d * 100) end
    end
    return nil
end

-- Every section as a list of entries: a standalone step, or a group with its
-- members. Each carries its step number, the guide's own count.
local function sections(guide)
    local out, number = {}, 0
    for _, section in ipairs(guide.data.sections or {}) do
        local entries = { title = section.title or "?" }
        local map = section.map or guide.data.map
        for _, step in ipairs(section.steps or {}) do
            if step.group then
                local members = {}
                for _, member in ipairs(step.group) do
                    number = number + 1
                    table.insert(members, { step = member, number = number, points = points(member, map) })
                end
                table.insert(entries, { group = members, line = step.__line, number = members[1].number })
            else
                number = number + 1
                table.insert(entries, { step = step, number = number, points = points(step, map) })
            end
        end
        table.insert(out, entries)
    end
    return out
end

local function check(path)
    local ns = {}
    loadTagged(path, ns)
    local short = path:match("[^/]+$")
    local found = 0
    for _, guide in ipairs(ns.packagedGuides or {}) do
        npcNames = {}
        -- Every table carries its `__line`, which is no NPC.
        for map, byID in pairs(guide.data.npcs or {}) do
            if map ~= "__line" then
                for id, npc in pairs(byID) do
                    if id ~= "__line" then npcNames[id] = type(npc) == "table" and npc.name or npc end
                end
            end
        end
        for _, entries in ipairs(sections(guide)) do
            for i, a in ipairs(entries) do
                local b = entries[i + 1]
                if b and not (a.group and b.group) then
                    -- A standalone step beside a group is compared with its nearest member.
                    local left = a.group and a.group[#a.group] or a
                    local right = b.group and b.group[1] or b
                    local why = reason(left, right)
                    if why then
                        found = found + 1
                        local line = a.line or a.step.__line
                        local how = a.group and "join the group before it"
                            or b.group and "join the group after it" or "group"
                        print(string.format("%s:%d  %s, steps %d and %d: %s", short, line, entries.title,
                            left.number, right.number, how))
                        print("    " .. describe(left.step))
                        print("    " .. describe(right.step))
                        print("    " .. why)
                    end
                end
            end
        end
    end
    return found
end

local files = {}
for _, a in ipairs({ ... }) do
    if a == "--visits" then visits = true else table.insert(files, a) end
end
if #files == 0 then
    local ls = io.popen('ls NuuRoad/Data/Guides/*.lua')
    for path in ls:lines() do table.insert(files, path) end
    ls:close()
end

local total = 0
for _, path in ipairs(files) do total = total + check(path) end
print(total == 0 and "No steps to group." or (total .. " possible groupings."))
