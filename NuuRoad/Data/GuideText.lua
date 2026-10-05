local _, ns = ...

-- A guide in format v1 (docs/examples/guide-v1.lua) as Lua text and back:
-- the editor's Copy as text, Import from text and Edit as text. The text is
-- the same value a file in Data/Guides holds, written the way those files
-- are: the wrapper's fields one to a line, a section's steps one to a line,
-- keys in the order the format lists them.
--
-- Reading runs the text with nothing in reach (no globals, no functions to
-- call), so a pasted guide can only ever be a value. Touches no frame:
-- Tests/GuideTextTests.lua runs it outside the client.
local GuideText = {}

-- The order fields are written in; anything else follows, sorted.
local WRAPPER = { "kind", "schema", "id", "updated", "title", "category", "author", "tags", "levels", "cond", "source",
    "materials", "data" }
local DATA = { "map", "conds", "sections", "places", "npcs" }
local SECTION = { "title", "map", "label", "cond", "show", "steps" }
local GROUP = { "label", "cond", "show", "group" }
local STEP = { "type", "quests", "turnin", "accept", "quest", "optional", "item", "count", "kill", "object", "spells",
    "spell", "skill", "rank", "faction", "standing", "level", "xp", "by", "to", "zone", "area", "instance", "node",
    "sell", "repair", "starts", "text", "options", "next", "npc", "at", "stand", "near", "radius", "loop", "say", "use", "mark",
    "wait", "needs", "upto", "sticky", "with", "from", "label", "cond", "show", "note" }

local function rank(order)
    local out = {}
    for index, key in ipairs(order) do out[key] = index end
    return out
end
local RANKS = { wrapper = rank(WRAPPER), data = rank(DATA), section = rank(SECTION), group = rank(GROUP), step = rank(STEP) }

local function isList(value)
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count == #value
end

local IDENT = "^[%a_][%w_]*$"
local RESERVED = { ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true, ["end"] = true,
    ["false"] = true, ["for"] = true, ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true,
    ["not"] = true, ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true }

local function keyText(key)
    if type(key) == "string" and key:match(IDENT) and not RESERVED[key] then return key end
    if type(key) == "string" then return "[" .. string.format("%q", key) .. "]" end
    return "[" .. tostring(key) .. "]"
end

local function sortedKeys(value, ranks)
    local keys = {}
    for key in pairs(value) do
        if not (type(key) == "number" and key >= 1 and key <= #value and key % 1 == 0) then table.insert(keys, key) end
    end
    table.sort(keys, function(a, b)
        local ra, rb = ranks and ranks[a], ranks and ranks[b]
        if ra and rb then return ra < rb end
        if ra or rb then return ra ~= nil end
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    return keys
end

local inline

-- One value on one line.
inline = function(value, ranks)
    local kind = type(value)
    if kind == "string" then return (string.format("%q", value):gsub("\\\n", "\\n")) end
    if kind ~= "table" then return tostring(value) end
    local parts = {}
    for index = 1, #value do parts[#parts + 1] = inline(value[index]) end
    for _, key in ipairs(sortedKeys(value, ranks)) do
        parts[#parts + 1] = keyText(key) .. " = " .. inline(value[key])
    end
    if #parts == 0 then return "{}" end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function write(out, text) out[#out + 1] = text end

-- A table spread over lines, its fields in `ranks` order; `child(key, value, indent)`
-- answers a field's text, or nil to write it inline.
local function block(out, value, indent, ranks, child)
    write(out, "{\n")
    local inner = indent .. "    "
    for index = 1, #value do
        local text = child and child(index, value[index], inner)
        write(out, inner .. (text or inline(value[index])) .. ",\n")
    end
    for _, key in ipairs(sortedKeys(value, ranks)) do
        local text = child and child(key, value[key], inner)
        write(out, inner .. keyText(key) .. " = " .. (text or inline(value[key])) .. ",\n")
    end
    write(out, indent .. "}")
end

local function blockText(value, indent, ranks, child)
    local out = {}
    block(out, value, indent, ranks, child)
    return table.concat(out)
end

local function stepText(step, indent)
    if type(step) == "table" and step.group ~= nil then
        return blockText(step, indent, RANKS.group, function(key, value, inner)
            if key == "group" and type(value) == "table" then
                return blockText(value, inner, nil, function(_, member) return inline(member, RANKS.step) end)
            end
        end)
    end
    return inline(step, RANKS.step)
end

local function sectionText(section, indent)
    return blockText(section, indent, RANKS.section, function(key, value, inner)
        if key == "steps" and type(value) == "table" then
            return blockText(value, inner, nil, function(_, step, stepIndent) return stepText(step, stepIndent) end)
        end
    end)
end

-- The guide as text: `{ kind = "guide", ... }`, a value a file can return.
function GuideText:Write(guide)
    return blockText(guide, "", RANKS.wrapper, function(key, value, inner)
        if key ~= "data" or type(value) ~= "table" then return nil end
        return blockText(value, inner, RANKS.data, function(dataKey, dataValue, dataInner)
            if dataKey == "sections" and type(dataValue) == "table" then
                return blockText(dataValue, dataInner, nil, function(_, section, sectionIndent)
                    return sectionText(section, sectionIndent)
                end)
            end
            if dataKey == "npcs" and type(dataValue) == "table" and not isList(dataValue) then
                return blockText(dataValue, dataInner, nil, function(_, byMap, mapIndent)
                    return blockText(byMap, mapIndent, nil)
                end)
            end
            if (dataKey == "places" or dataKey == "conds") and type(dataValue) == "table" then
                return blockText(dataValue, dataInner, nil)
            end
        end)
    end)
end

-- One step as text, for the editor's text view of a step.
function GuideText:WriteStep(step)
    return stepText(step, "")
end

-- A value v1 allows: strings, whole numbers, true, and tables of those.
local function checkValue(value, path, seen)
    local kind = type(value)
    if kind == "string" or kind == "boolean" and value == true then return nil end
    if kind == "number" then
        if value % 1 ~= 0 then return path .. ": numbers are whole (hundredths of a percent for points)" end
        return nil
    end
    if kind == "boolean" then return path .. ": leave the field out instead of false" end
    if kind ~= "table" then return path .. ": a " .. kind .. " is not allowed" end
    if seen[value] then return path .. ": a table is used twice" end
    seen[value] = true
    for key, child in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then return path .. ": keys are names or numbers" end
        local problem = checkValue(child, path .. "." .. tostring(key), seen)
        if problem then return problem end
    end
    return nil
end

-- Text -> the value it holds, or nil and what is wrong. `text` is a whole
-- guide or one step (the text view of a step); a leading "return" is
-- allowed, as a guide file has none but a pasted value may.
function GuideText:Read(text)
    if type(text) ~= "string" or not text:match("%S") then return nil, "There is no text." end
    local load = rawget(_G, "loadstring") or rawget(_G, "load")
    if not load then return nil, "This client cannot read text as a guide." end
    local body = text:gsub("^%s*return%s+", "")
    local chunk, problem = load("return " .. body, "guide")
    if not chunk then return nil, "The text does not read: " .. tostring(problem):gsub("^%[string.-%]:", "line ") end
    local setEnv = rawget(_G, "setfenv")
    if setEnv then setEnv(chunk, {}) end
    local ran, value = pcall(chunk)
    if not ran then return nil, "The text does not read: " .. tostring(value):gsub("^%[string.-%]:", "line ") end
    if type(value) ~= "table" then return nil, "The text is not a table." end
    local wrong = checkValue(value, value.kind == "guide" and "guide" or "step", {})
    if wrong then return nil, wrong end
    return value
end

ns:RegisterModule("GuideText", GuideText)
