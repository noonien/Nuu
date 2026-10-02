local _, ns = ...

-- The colour audit (development only): every recipe the open profession
-- window lists, its colour there against the one the recipe data gives at the
-- window's skill (SkillUp:Color over the data's { orange, yellow, green, grey }).
-- The planner checks only its route's recipes, one at a time
-- (Panel:CheckColors); this looks at the whole window at once, to see whether
-- the data's bands are off by a pattern (the session log had Linen Belt green
-- at 67 with green at 68, and Reinforced Linen Cape green at 77 with 78).
--
--   /nuuprof coloraudit                 the open window, against the beta data
--   /nuuprof coloraudit full            against the full-scope set where it has the profession
--   /nuuprof coloraudit <profession>    the window last read this session, when none is open
--
-- Each run is one `coloraudit` row on the `prof` channel, kept whole for
-- reading offline, and a few lines in chat. Run it at several skills: each
-- run says what its own skill shows.

local Audit = {}

local function Client() return ns.modules.Client end
local function Planner() return ns.modules.ProfessionPlanner end
local function SkillUp() return ns.Kit.SkillUp end

-- The colours in band order; a band's index is also the index of the skill
-- level it starts at, so "green" starts at skills[3].
local RANK = { unknown = 0, orange = 1, yellow = 2, green = 3, grey = 4 }
local BAND = { "orange", "yellow", "green", "grey" }
local LETTER = { orange = "O", yellow = "Y", green = "G", grey = "R" }
Audit.rank, Audit.bands = RANK, BAND

local function forever(recipe)
    return type(recipe.forever) == "string" and recipe.forever or "unknown"
end

local function bump(counts, key, by)
    counts[key] = (counts[key] or 0) + (by or 1)
end

-- The data's recipes by spell, and by the item they make for a window row
-- with no spell (the Classic window links only the product). Two spells
-- making one item: the lowest is taken, and the match says so.
local function byItem(data)
    local found, twice = {}, {}
    for spell, recipe in pairs(data.recipes or {}) do
        local item = recipe.makes
        if item then
            if found[item] then twice[item] = true end
            if not found[item] or spell < found[item] then found[item] = spell end
        end
    end
    return found, twice
end

-- Where a disagreement puts the game's band edge. The game showing a later
-- colour than the data (live green where the data says yellow) is early: the
-- live colour's band starts at or before this skill, `offset` = skill -
-- skills[band] (Linen Belt at 67 with green at 68: "green -1"). An earlier
-- colour (live yellow where the data says green) is late: the expected band
-- starts after this skill, `offset` = skill + 1 - skills[band] ("green +1").
-- `jump` is how many bands apart the two colours are.
function Audit:Edge(skills, skill, expected, live)
    local e, l = RANK[expected], RANK[live]
    if not e or not l or e == l then return nil end
    local band = l > e and l or e
    local start = skills[band]
    local offset
    if type(start) == "number" then offset = l > e and (skill - start) or (skill + 1 - start) end
    return BAND[band], offset, l > e and "early" or "late", math.abs(l - e)
end

-- A pattern's name: "green -1", "grey +2", or "green ?" when the data has no
-- skill for the band.
function Audit.PatternName(band, offset)
    if offset == nil then return band .. " ?" end
    return string.format("%s %+d", band, offset)
end

-- The audit itself, without the client: `snapshot` as
-- Client:ReadTradeSkillWindow makes it, `data` a profession's recipe data.
-- Returns the record:
--   { event = "coloraudit", profession, skill, maxSkill, api, partial, dataSet,
--     recipes (rows the window lists), compared, agree, disagree,
--     unmatched (rows the data lacks), noColor (rows without a colour),
--     byForever = { [forever] = { agree, disagree } },
--     patterns = { ["green -1"] = { total, [forever] = n } },
--     edges = { [band] = { before, beforeEarly, at, atLate,
--       byForever = { [forever] = { before, beforeEarly, at, atLate } } } },
--     mismatches = { { spell, item, name, skill, expected, live, skills,
--       forever, band, offset, kind = "early"|"late", jump, byItem } },
--     missing = { { name, spell, item, live } } }
-- An edge counts the rows that sit one point before a band's start in the
-- data (`before`; `beforeEarly` of them already show the band) and at it
-- (`at`; `atLate` of them do not show it yet): "green at G-1" is every
-- `before` early and no `at` late. A band starting where the one before it
-- does never shows, and has no edge.
function Audit:Compare(snapshot, data, dataSet)
    local skill = tonumber(snapshot.skill) or 0
    local result = { event = "coloraudit", profession = snapshot.profession, skill = snapshot.skill,
        maxSkill = snapshot.maxSkill, api = snapshot.api, partial = snapshot.partial, dataSet = dataSet,
        recipes = #(snapshot.order or {}), compared = 0, agree = 0, disagree = 0, unmatched = 0, noColor = 0,
        byForever = {}, patterns = {}, edges = {}, mismatches = {}, missing = {} }
    local recipes = type(data) == "table" and data.recipes or {}
    local items, twice = byItem({ recipes = recipes })
    local S = SkillUp()
    for _, row in ipairs(snapshot.order or {}) do
        local spell = row.spellID and recipes[row.spellID] and row.spellID or nil
        local viaItem = false
        if not spell and row.itemID and items[row.itemID] then spell, viaItem = items[row.itemID], true end
        local recipe = spell and recipes[spell]
        if not recipe or type(recipe.skills) ~= "table" then
            result.unmatched = result.unmatched + 1
            table.insert(result.missing, { name = row.name, spell = row.spellID, item = row.itemID, live = row.color })
        elseif not RANK[row.color] then
            -- No colour, or one only a trainer shows.
            result.noColor = result.noColor + 1
        else
            local skills, kind = recipe.skills, forever(recipe)
            local expected = S:Color(skills, skill)
            local split = result.byForever[kind] or { agree = 0, disagree = 0 }
            result.byForever[kind] = split
            result.compared = result.compared + 1
            if expected == row.color then
                result.agree = result.agree + 1
                split.agree = split.agree + 1
            else
                result.disagree = result.disagree + 1
                split.disagree = split.disagree + 1
                local band, offset, side, jump = self:Edge(skills, skill, expected, row.color)
                local name = self.PatternName(band, offset)
                local pattern = result.patterns[name] or { total = 0 }
                result.patterns[name] = pattern
                bump(pattern, "total")
                bump(pattern, kind)
                table.insert(result.mismatches, { spell = spell, item = row.itemID or recipe.makes, name = row.name,
                    skill = skill, expected = expected, live = row.color,
                    skills = { skills[1], skills[2], skills[3], skills[4] }, forever = kind,
                    band = band, offset = offset, kind = side, jump = jump,
                    byItem = viaItem or nil, twice = viaItem and twice[row.itemID] or nil })
            end
            local live = RANK[row.color]
            for band = 2, 4 do
                local start = skills[band]
                if type(start) == "number" and start ~= skills[band - 1] then
                    local edge = result.edges[BAND[band]] or { before = 0, beforeEarly = 0, at = 0, atLate = 0, byForever = {} }
                    result.edges[BAND[band]] = edge
                    local own = edge.byForever[kind] or { before = 0, beforeEarly = 0, at = 0, atLate = 0 }
                    edge.byForever[kind] = own
                    if skill == start - 1 then
                        edge.before, own.before = edge.before + 1, own.before + 1
                        if live >= band then edge.beforeEarly, own.beforeEarly = edge.beforeEarly + 1, own.beforeEarly + 1 end
                    elseif skill == start then
                        edge.at, own.at = edge.at + 1, own.at + 1
                        if live < band then edge.atLate, own.atLate = edge.atLate + 1, own.atLate + 1 end
                    end
                end
            end
        end
    end
    for band, edge in pairs(result.edges) do
        if edge.before == 0 and edge.at == 0 then result.edges[band] = nil end
    end
    table.sort(result.mismatches, function(a, b)
        if a.band ~= b.band then return tostring(a.band) < tostring(b.band) end
        return (a.spell or 0) < (b.spell or 0)
    end)
    return result
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do table.insert(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function split(counts)
    local parts = {}
    for _, key in ipairs(sortedKeys(counts)) do
        if key ~= "total" and type(counts[key]) == "number" then table.insert(parts, key .. " " .. counts[key]) end
    end
    return table.concat(parts, ", ")
end

-- The few chat lines a result makes: the counts, one line per pattern, and
-- one per band edge the window's skill sits on.
function Audit:Lines(result)
    local lines = { string.format("Colour audit: %s %s, %d agree, %d disagree, %d not in the data%s.",
        tostring(result.profession), tostring(result.skill), result.agree, result.disagree, result.unmatched,
        result.partial and " (a header is folded)" or "") }
    local names = sortedKeys(result.patterns)
    table.sort(names, function(a, b)
        local x, y = result.patterns[a].total, result.patterns[b].total
        if x ~= y then return x > y end
        return a < b
    end)
    for _, name in ipairs(names) do
        local pattern = result.patterns[name]
        table.insert(lines, string.format("  %s: %d (%s)", name, pattern.total, split(pattern)))
    end
    for _, band in ipairs(BAND) do
        local edge = result.edges[band]
        if edge then
            local letter = LETTER[band]
            table.insert(lines, string.format("  %s: at %s-1 %d of %d already %s; at %s %d of %d not yet", band,
                letter, edge.beforeEarly, edge.before, band, letter, edge.atLate, edge.at))
        end
    end
    return lines
end

-- The window to audit: the open one read now, else (named) the one read
-- last this session.
function Audit:Snapshot(professionName)
    local api = Client()
    local snapshot = api:ReadTradeSkillWindow("tradeskill") or api:ReadTradeSkillWindow("craft")
    if snapshot and #snapshot.order > 0 then return snapshot end
    if professionName and professionName ~= "" then return api:GetTradeSkillSnapshot(professionName) end
    return nil
end

-- One run: reads, compares, records and says. Returns the record, or nil and
-- why not.
function Audit:Run(text)
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    local full = text:lower() == "full"
    local snapshot = self:Snapshot(not full and text or nil)
    local why
    if not snapshot then
        why = "Open a profession window first."
    elseif snapshot.linked then
        why = "That is another player's window."
    end
    local key = snapshot and Planner():DataKey(snapshot.profession)
    local dataSet, data = "beta", nil
    if not why then
        if full and type(ns.professionDataFull) == "table" and ns.professionDataFull[key] then
            dataSet, data = "full", ns.professionDataFull[key]
        else
            data = type(ns.professionData) == "table" and ns.professionData[key] or nil
        end
        if not data then why = "No recipe data for " .. tostring(snapshot.profession) .. "." end
    end
    if why then
        ns:Print(why)
        return nil, why
    end
    local result = self:Compare(snapshot, data, dataSet)
    ns:Record("prof", result)
    for _, line in ipairs(self:Lines(result)) do ns:Print(line) end
    return result
end

-- `/nuuprof coloraudit`, ahead of the planner's own command (PlannerPanel,
-- whose Initialize runs first: this file loads after it).
function Audit:Initialize()
    local slash = rawget(_G, "SlashCmdList")
    if type(slash) ~= "table" then return end
    _G.SLASH_NUUPROFESSIONS1 = _G.SLASH_NUUPROFESSIONS1 or "/nuuprofessions"
    _G.SLASH_NUUPROFESSIONS2 = _G.SLASH_NUUPROFESSIONS2 or "/nuuprof"
    local before = slash.NUUPROFESSIONS
    slash.NUUPROFESSIONS = function(text)
        local rest = type(text) == "string" and text:lower():match("^%s*colou?raudit") and text:match("^%s*%S+%s*(.-)%s*$")
        if rest then
            Audit:Run(rest)
        elseif before then
            before(text)
        end
    end
end

ns:RegisterModule("ColorAudit", Audit)
