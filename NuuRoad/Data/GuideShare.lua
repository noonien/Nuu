local _, ns = ...

-- A guide source (docs/examples/guide-source.lua) as the bytes players share
-- and back, through the codec Data/GuideCodec.lua generates from the share
-- schema, Schema/Guide.lua. The share schema is what two players' addons must
-- agree on; the guide source is the addon's own and changes with it.
--
--     local bytes, problem = GuideShare:Encode(guide)
--     local guide, problem = GuideShare:Decode(bytes)
--
-- The codec knows the share schema's values and nothing of guide sources;
-- this is the one place that knows a source's shapes and turns them into
-- those values and back:
--
--   * a step is { kind, common }: its type with that type's own fields, and
--     the fields any step may carry (the codec's Keys.StepCommon);
--   * a section's entry is { "step", step } or { "group", group }, and a
--     group's `group` is its `steps`;
--   * a value that is one thing or a list ({ "one", v } / { "list", v }), a
--     quest or an objective, a season that is true or a number, an NPC that
--     is a name or a table and stands at a point, points or a place, are
--     unions;
--   * a point { x, y, map = } is the tuple { x, y, map };
--   * kind = "guide" is the share schema's id, not written.
--
-- Every other key goes through as it is, so a key the schema has no place for is
-- refused by the codec, which names it. Decoding a guide that was encoded
-- gives back the same value. Touches no frame: Tests/GuideShareTests.lua runs
-- it outside the client.
local GuideShare = {}

local function codec() return ns.modules.GuideCodec end

local function oneOrList(v)
    if type(v) == "table" then return { "list", v } end
    return { "one", v }
end

local function unwrap(u)
    if type(u) == "table" then return u[2] end
    return u
end

-- Every key of v, with the ones in `change` changed: change[key](value).
local function reshape(v, change)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do
        local fn = change[key]
        if fn then out[key] = fn(value) else out[key] = value end
    end
    return out
end

local function each(fn)
    return function(list)
        if type(list) ~= "table" then return list end
        local out = {}
        for key, value in pairs(list) do out[key] = fn(value) end
        return out
    end
end

-- POINTS

local function point(p)
    if type(p) ~= "table" then return p end
    local out = { p[1], p[2], p.map }
    for key, value in pairs(p) do
        if key ~= 1 and key ~= 2 and key ~= "map" then out[key] = value end
    end
    return out
end

local function pointBack(t)
    return { t[1], t[2], map = t[3] }
end

-- CONDITIONS, two deep (Schema/Guide.lua).

local CONDITION_DEPTH = 3

local function cond(c, depth)
    depth = depth or 1
    if type(c) ~= "table" then return c end
    local nested = function(list)
        if depth >= CONDITION_DEPTH then
            error("conditions nest two deep at most: name the inner one in the guide's conds and use it with is", 0)
        end
        return each(function(inner) return cond(inner, depth + 1) end)(list)
    end
    return reshape(c, {
        class = oneOrList, race = oneOrList, faction = oneOrList, skill = oneOrList,
        season = function(v) if v == true then return { "any" } end return { "number", v } end,
        any = nested, none = nested, all = nested,
    })
end

local function condBack(c)
    if c == nil then return nil end
    local nested = each(condBack)
    return reshape(c, {
        class = unwrap, race = unwrap, faction = unwrap, skill = unwrap,
        season = function(u) if u[1] == "any" then return true end return u[2] end,
        any = nested, none = nested, all = nested,
    })
end

-- STEPS

local function quest(q)
    if type(q) == "table" then return { "objective", q } end
    return { "quest", q }
end

local COMMON = {
    cond = cond, show = cond, quest = quest, item = oneOrList, at = each(point),
}
local COMMON_BACK = {
    cond = condBack, show = condBack, quest = unwrap, item = unwrap, at = each(pointBack),
}
local OWN = { next = oneOrList }
local OWN_BACK = { next = unwrap }

local function step(s)
    if type(s) ~= "table" then return s end
    local commonKeys, takes = codec().Keys.StepCommon, codec().Variants.StepKind
    local common, own = {}, {}
    for key, value in pairs(s) do
        if key ~= "type" then
            if commonKeys[key] then
                common[key] = COMMON[key] and COMMON[key](value) or value
            else
                own[key] = OWN[key] and OWN[key](value) or value
            end
        end
    end
    -- A type with no fields of its own takes no value: a key it is given
    -- anyway goes with the common ones, for the codec to refuse by name.
    if takes[s.type] == false then
        for key, value in pairs(own) do common[key] = value end
        return { { s.type }, common }
    end
    return { { s.type, own }, common }
end

local function stepBack(t)
    local kind, common = t[1], t[2]
    local s = { type = kind[1] }
    for key, value in pairs(kind[2] or {}) do s[key] = OWN_BACK[key] and OWN_BACK[key](value) or value end
    for key, value in pairs(common) do s[key] = COMMON_BACK[key] and COMMON_BACK[key](value) or value end
    return s
end

local function entry(e)
    if type(e) ~= "table" or e.group == nil then return { "step", step(e) } end
    if e.steps ~= nil then error("a group's steps are its `group`, not `steps`", 0) end
    local group = reshape(e, { cond = cond, show = cond })
    group.group, group.steps = nil, each(step)(e.group)
    return { "group", group }
end

local function entryBack(u)
    if u[1] == "step" then return stepBack(u[2]) end
    local group = reshape(u[2], { cond = condBack, show = condBack })
    group.steps, group.group = nil, each(stepBack)(u[2].steps)
    return group
end

-- NPCS AND PLACES

local function npcAt(at)
    if type(at) == "string" then return { "place", at } end
    if type(at) == "table" and type(at[1]) == "table" then return { "points", each(point)(at) } end
    return { "point", point(at) }
end

local function npc(n)
    if type(n) == "table" then return { "npc", reshape(n, { at = npcAt }) } end
    return { "name", n }
end

local function npcBack(u)
    if u[1] == "name" then return u[2] end
    return reshape(u[2], {
        at = function(at)
            if at[1] == "points" then return each(pointBack)(at[2]) end
            if at[1] == "point" then return pointBack(at[2]) end
            return at[2]
        end,
    })
end

local function place(p)
    return reshape(p, { points = each(function(pt) return reshape(pt, { at = point }) end) })
end

local function placeBack(p)
    return reshape(p, { points = each(function(pt) return reshape(pt, { at = pointBack }) end) })
end

-- THE GUIDE

local function section(s)
    return reshape(s, { cond = cond, show = cond, steps = each(entry) })
end

local function sectionBack(s)
    return reshape(s, { cond = condBack, show = condBack, steps = each(entryBack) })
end

-- The share schema's value of a guide source. Raises on what cannot be turned
-- into one.
function GuideShare:ToWire(guide)
    if type(guide) ~= "table" or guide.kind ~= "guide" then
        error("it is not a guide source (kind = \"guide\")", 0)
    end
    local wire = reshape(guide, {
        cond = cond,
        data = function(data)
            return reshape(data, {
                conds = each(cond), sections = each(section), places = each(place), npcs = each(each(npc)),
            })
        end,
    })
    wire.kind = nil
    return wire
end

-- The guide source of a value the codec decoded.
function GuideShare:FromWire(wire)
    local guide = reshape(wire, {
        cond = condBack,
        data = function(data)
            return reshape(data, {
                conds = each(condBack), sections = each(sectionBack), places = each(placeBack),
                npcs = each(each(npcBack)),
            })
        end,
    })
    guide.kind = "guide"
    return guide
end

-- The guide as bytes, or nil and what is wrong with it.
function GuideShare:Encode(guide)
    local ok, wire = pcall(self.ToWire, self, guide)
    if not ok then return nil, tostring(wire) end
    return codec().Encode(wire)
end

-- The guide the bytes hold, or nil and what is wrong with them.
function GuideShare:Decode(bytes)
    local wire, problem = codec().Decode(bytes)
    if not wire then return nil, problem end
    return self:FromWire(wire)
end

ns:RegisterModule("GuideShare", GuideShare)
