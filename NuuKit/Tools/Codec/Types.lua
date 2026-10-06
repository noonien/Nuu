-- NuuKit/Tools/Codec/Types.lua: the helpers a codec schema is written with.
-- Never shipped. NuuKit/Tools/Codec/Gen.lua loads a schema file with these as
-- its argument (`local T = ...`), and writes the Lua encoder and decoder the
-- schema describes.
--
-- Each helper returns a plain table, a type; a schema is ordinary Lua that
-- builds types and combines them. A type is shared by keeping it in a local;
-- one that is written inline has no name. Since a type can only use types
-- made before it, none can contain itself.
--
--   T.UInt, T.SInt, T.String     whole number >= 0, any whole number, text
--   T.True                       a flag: an object's field is true or absent
--   T.Enum { "a", "b", ... }     one of these strings
--   T.ZeroNil(t)                 in a tuple, a UInt or Enum that may be nil
--   T.Tuple { t1, t2, ... }      fixed positions: { a, b, c }
--   T.Object { { "key", t }, ... }        named keys, each optional, in this order
--   T.Extend(object, { { "key", t } })    a new object: that one's keys, then these
--   T.Union { "name", { "name", t }, ... }  { "name", value }; a bare name has no value
--   T.List(t)                    { v, v, ... }
--   T.Map(k, t)                  { [k] = v }, k a UInt, String or Enum
--   T.Schema { id, root, module, names }  what a schema file returns
--
-- How each is written (all varints are the kit's, Core/Codec/Writer.lua):
--
--   UInt, Enum      varint (an enum as its position, from 0)
--   SInt            zigzag varint
--   String          length, then the bytes
--   True            nothing: the object's bitmap says it
--   ZeroNil         0 for nil, the value + 1 otherwise
--   Tuple           each element in order
--   Object          a bitmap of the keys present (bit 0 the first key), then
--                   their values in order
--   Union           the variant's position, from 0, then its value
--   List            count, then the items
--   Map             count, then key and value pairs, keys sorted
--
-- Every helper checks what it is given and reports at the schema line that
-- called it.
local T = {}

local function fail(message, level) error(message, (level or 2) + 1) end

local function scalar(kind) return { kind = kind } end
T.UInt = scalar("uint")
T.SInt = scalar("sint")
T.String = scalar("string")
T.True = scalar("true")

local KINDS = { uint = true, sint = true, string = true, ["true"] = true, enum = true, zeronil = true, tuple = true,
    object = true, union = true, list = true, map = true }

local function isType(t) return type(t) == "table" and KINDS[t.kind] ~= nil end

-- A type that takes bytes of its own, so it can stand in a tuple, a list, a
-- union or a map: anything but True (only an object's bitmap can hold it) and
-- ZeroNil (only a tuple can).
local function checkValue(t, what, level)
    if not isType(t) then fail(what .. " is not a type", level + 1) end
    if t.kind == "true" then fail(what .. " cannot be T.True: only an object's field can", level + 1) end
    if t.kind == "zeronil" then fail(what .. " cannot be T.ZeroNil: only a tuple's element can", level + 1) end
end

local IDENT = "^[%a_][%w_]*$"

function T.Enum(values)
    if type(values) ~= "table" or #values == 0 then fail("T.Enum takes a list of strings") end
    local seen, out = {}, {}
    for i, value in ipairs(values) do
        if type(value) ~= "string" then fail("T.Enum value " .. i .. " is not a string") end
        if seen[value] then fail("T.Enum has '" .. value .. "' twice") end
        seen[value] = true
        out[i] = value
    end
    return { kind = "enum", values = out }
end

function T.ZeroNil(t)
    if not isType(t) or (t.kind ~= "uint" and t.kind ~= "enum") then fail("T.ZeroNil takes T.UInt or a T.Enum") end
    return { kind = "zeronil", of = t }
end

function T.Tuple(items)
    if type(items) ~= "table" or #items == 0 then fail("T.Tuple takes a list of types") end
    local out = {}
    for i, item in ipairs(items) do
        if not (isType(item) and item.kind == "zeronil") then checkValue(item, "tuple element " .. i, 2) end
        out[i] = item
    end
    return { kind = "tuple", items = out }
end

-- A bitmap is one varint, so an object holds at most 52 keys.
local MAX_FIELDS = 52

local function object(fields, level)
    if type(fields) ~= "table" or #fields == 0 then fail("T.Object takes a list of { key, type }", level + 1) end
    if #fields > MAX_FIELDS then fail("an object holds at most " .. MAX_FIELDS .. " keys", level + 1) end
    local seen, out = {}, {}
    for i, field in ipairs(fields) do
        if type(field) ~= "table" or type(field[1]) ~= "string" or not field[1]:match(IDENT) then
            fail("object field " .. i .. " is not { \"key\", type }", level + 1)
        end
        local key, t = field[1], field[2]
        if seen[key] then fail("object key '" .. key .. "' is there twice", level + 1) end
        seen[key] = true
        if not (isType(t) and t.kind == "true") then checkValue(t, "object key '" .. key .. "'", level + 1) end
        out[i] = { key = key, type = t }
    end
    return { kind = "object", fields = out }
end

-- Not tail calls: the error levels count the helper's own frame.
function T.Object(fields)
    local t = object(fields, 2)
    return t
end

function T.Extend(base, fields)
    if not isType(base) or base.kind ~= "object" then fail("T.Extend takes an object first") end
    if type(fields) ~= "table" then fail("T.Extend takes a list of { key, type } second") end
    local all = {}
    for _, field in ipairs(base.fields) do all[#all + 1] = { field.key, field.type } end
    for _, field in ipairs(fields) do all[#all + 1] = field end
    local t = object(all, 2)
    return t
end

function T.Union(variants)
    if type(variants) ~= "table" or #variants == 0 then fail("T.Union takes a list of variants") end
    local seen, out = {}, {}
    for i, variant in ipairs(variants) do
        local name, t
        if type(variant) == "string" then
            name = variant
        elseif type(variant) == "table" and type(variant[1]) == "string" then
            name, t = variant[1], variant[2]
            checkValue(t, "union variant '" .. name .. "'", 2)
        else
            fail("union variant " .. i .. " is not \"name\" or { \"name\", type }")
        end
        if seen[name] then fail("union variant '" .. name .. "' is there twice") end
        seen[name] = true
        out[i] = { name = name, type = t }
    end
    return { kind = "union", variants = out }
end

function T.List(t)
    checkValue(t, "a list's item", 2)
    return { kind = "list", of = t }
end

function T.Map(key, t)
    if not isType(key) or (key.kind ~= "uint" and key.kind ~= "string" and key.kind ~= "enum") then
        fail("a map's key is T.UInt, T.String or a T.Enum")
    end
    checkValue(t, "a map's value", 2)
    return { kind = "map", key = key, value = t }
end

function T.Schema(spec)
    if type(spec) ~= "table" then fail("T.Schema takes { id, root, module, names }") end
    if type(spec.id) ~= "number" or spec.id < 1 or spec.id % 1 ~= 0 then fail("a schema's id is a whole number from 1") end
    if not isType(spec.root) then fail("a schema's root is a type") end
    if type(spec.module) ~= "string" or not spec.module:match(IDENT) then fail("a schema's module is a name") end
    local names = {}
    for name, t in pairs(spec.names or {}) do
        if type(name) ~= "string" or not name:match(IDENT) then fail("a schema's names are names") end
        if not isType(t) then fail("the schema names '" .. name .. "' but it is not a type") end
        names[name] = t
    end
    return { kind = "schema", id = spec.id, root = spec.root, module = spec.module, names = names }
end

return T
