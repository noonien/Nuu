-- Lists steps in NuuRoad's built-in guides that could share one card as a
-- group but stand alone: neighbouring kill, collect, and objective steps on
-- the same mobs or at the same spots. With --visits it also lists
-- neighbouring quest visits at the same NPC or a few steps apart, which is
-- noisier: a chain handed from one NPC to the next reads well as separate
-- steps. It only reports; whether a pair belongs on one card is the author's
-- call (NuuRoad/docs/guide-schema.md, groups). Run from the repository root:
--
--   lua Tools/GroupCheck.lua [--visits] [guide.lua ...]
--
-- With no files it reads every guide under NuuRoad/Data/BuiltIn. A pair may
-- have track or untrack steps between it; those are named, since they have to
-- move out from between the members. Pairs no one character can see both of
-- (two classes, two factions) are left out.

local SAME_SPOT = 0.015 -- field steps this close share a camp (map fraction)
local VISIT_REACH = 0.02 -- talk steps' default arrival radius

local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local FACTIONS = { "Horde", "Alliance" }

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

-- Names, for a readable report.
local names = {}
do
    local ns = { RegisterModule = function(_, _, module) names = module end }
    local chunk = assert(loadfile("NuuRoad/Data/Names.lua"))
    chunk(nil, ns)
end

local function npcName(id) return names.npcs and names.npcs[id] or ("npc " .. id) end
local function itemName(id) return names.items and names.items[id] or ("item " .. id) end
local function questName(id) return names.quests and names.quests[id] or ("quest " .. id) end

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
-- "visit" at an NPC, a "reminder" that can move out of the way, or "other".
local function kind(step)
    if step.track or step.untrack then return "reminder" end
    if step.group or step.section or step.choice or step.finish or step.travel or step.hearth or step.flight
        or step.level or step.train or step.learn or step.buy or step.vendor or step.craft or step.gather
        or step.skillup or step.equip or step.cast or step.skill or step.reputation or step.objectives then
        return "other"
    end
    if step.objective or step.collect or step.kill then return "field" end
    if step.accept or step.turnin then return "visit" end
    if step.object and step.at then return "field" end
    return "other"
end

local function points(step, map)
    local at = step.at
    if type(at) ~= "table" then return {} end
    if type(at[1]) == "number" then at = { at } end
    local out = {}
    for _, p in ipairs(at) do
        local x, y = p[1], p[2]
        if x > 1 or y > 1 then x, y = x / 100, y / 100 end
        map = p.map or map
        table.insert(out, { x = x, y = y, map = map })
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

-- Which of the words a step's condition limits it to, or nil when it names
-- none of them.
local function limitedTo(step, words)
    if type(step.only) ~= "string" then return nil end
    local found
    for _, word in ipairs(words) do
        local s = " " .. step.only .. " "
        if s:find("[^%a]" .. word .. "[^%a]") and not s:find("not " .. word .. "[^%a]") then
            found = found or {}
            found[word] = true
        end
    end
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
    if step.objective or step.collect or step.kill then
        local what = step.collect and ("collect " .. itemName(step.collect))
            or step.objective and ("objective " .. questName(step.objective) .. (step.part and (" #" .. step.part) or ""))
            or "kill"
        local mobs = {}
        for _, id in ipairs(list(step.kill)) do table.insert(mobs, npcName(id)) end
        if #mobs > 0 then what = what .. " (" .. table.concat(mobs, ", ") .. ")" end
        return what
    end
    if step.accept or step.turnin then
        local parts = {}
        if step.turnin then table.insert(parts, "turn in " .. questName(list(step.turnin)[1])) end
        if step.accept then table.insert(parts, "accept " .. questName(list(step.accept)[1])) end
        return table.concat(parts, ", ") .. (step.npc and (" at " .. npcName(list(step.npc)[1])) or "")
    end
    return step.object or "step"
end

-- Why two standalone steps could share a card, or nil.
local function reason(a, b)
    local k = kind(a.step)
    if k ~= kind(b.step) or not (k == "field" or (k == "visit" and visits)) then return nil end
    if disjoint(limitedTo(a.step, CLASSES), limitedTo(b.step, CLASSES))
        or disjoint(limitedTo(a.step, FACTIONS), limitedTo(b.step, FACTIONS)) then
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
    for _, section in ipairs(guide.steps or {}) do
        local entries = { title = section.section or "?" }
        local map = section.map or guide.map
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
    local ns = { builtInGuides = {} }
    loadTagged(path, ns)
    local short = path:match("[^/]+$")
    local found = 0
    for id, guide in pairs(ns.builtInGuides) do
        for _, entries in ipairs(sections(guide)) do
            for i, a in ipairs(entries) do
                -- The next entry that is not a reminder, and the reminders passed.
                local j, between = i + 1, {}
                while entries[j] and entries[j].step and kind(entries[j].step) == "reminder" do
                    local r = entries[j].step
                    table.insert(between, (r.track and "track " or "untrack ") .. (r.track or r.untrack)
                        .. " (step " .. entries[j].number .. ")")
                    j = j + 1
                end
                local b = entries[j]
                if b and not (a.step and kind(a.step) == "reminder") and not (a.group and b.group) then
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
                        if #between > 0 then print("    move out from between: " .. table.concat(between, ", ")) end
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
    local ls = io.popen('ls NuuRoad/Data/BuiltIn/*.lua')
    for path in ls:lines() do table.insert(files, path) end
    ls:close()
end

local total = 0
for _, path in ipairs(files) do total = total + check(path) end
print(total == 0 and "No steps to group." or (total .. " possible groupings."))
