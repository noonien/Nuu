-- NuuKit/Tools/Codec: the type helpers and the codecs Gen.lua writes from
-- them. Small schemas are generated here, loaded as an addon file would be,
-- and run: every type's bytes, values that round trip, values Encode
-- refuses, and bytes Decode refuses.
local Kit = _G.LoadKit().Kit
local W = dofile("Tests/Support/CommsWorld.lua")
local suite, test, ok, eq, errors = W.suite, W.test, W.ok, W.eq, W.errors

local Gen = dofile("Tools/Codec/Gen.lua")
local T = Gen.Types

local function hex(s)
    return (s:gsub(".", function(c) return ("%02X "):format(c:byte()) end):gsub(" $", ""))
end

-- The generated codec of a schema, loaded with the kit.
local function codec(root, names)
    local schema = T.Schema { id = 7, root = root, module = "TestCodec", names = names }
    local source = Gen.Generate(schema, { "A test codec." })
    local chunk = assert(loadstring(source, "=generated"))
    local ns = { Kit = Kit }
    function ns:RegisterModule(name, module) self[name] = module end
    chunk("Test", ns)
    return ns.TestCodec, source
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function roundTrip(c, value, name)
    local bytes, problem = c.Encode(value)
    ok(bytes ~= nil, name .. ": encodes (" .. tostring(problem) .. ")")
    local back, why = c.Decode(bytes)
    ok(same(back, value), name .. ": decodes to the same value (" .. tostring(why) .. ")")
    return bytes
end

local Point = T.Tuple { T.UInt, T.UInt, T.ZeroNil(T.UInt) }

-- The step of the proposal: its kind, then the fields any step may carry.
local function stepCodec()
    local IDs = T.List(T.UInt)
    local StepCommon = T.Object {
        { "note", T.String },
        { "npc", IDs },
        { "at", T.List(Point) },
        { "sticky", T.True },
    }
    local StepKind = T.Union {
        "note",
        { "finish", T.Object { { "next", T.String } } },
        { "travel", T.Object { { "to", T.String }, { "zone", T.UInt } } },
        { "accept", T.Object { { "quests", IDs }, { "level", T.UInt } } },
    }
    return codec(T.Tuple { StepKind, StepCommon }, { StepCommon = StepCommon, StepKind = StepKind, Point = Point })
end

--------------------------------------------------------------------------------

suite("The helpers", function()
    test("build plain tables", function()
        eq(T.List(T.UInt).kind, "list", "a list")
        eq(T.Extend(T.Object { { "a", T.UInt } }, { { "b", T.String } }).fields[2].key, "b", "extend adds keys after")
    end)

    test("refuse a schema that cannot be written", function()
        errors(function() T.Enum {} end, "an empty enum")
        errors(function() T.Enum { "a", "a" } end, "an enum value twice")
        errors(function() T.Object { { "a", T.UInt }, { "a", T.String } } end, "a key twice")
        errors(function() T.Object { { "a", "uint" } } end, "something that is not a type")
        errors(function() T.Extend(T.Object { { "a", T.UInt } }, { { "a", T.UInt } }) end, "extend repeating a key")
        errors(function() T.Union { "a", { "a", T.UInt } } end, "a variant twice")
        errors(function() T.List(T.True) end, "a list of flags")
        errors(function() T.Tuple { T.True } end, "a flag in a tuple")
        errors(function() T.Object { { "a", T.ZeroNil(T.UInt) } } end, "ZeroNil outside a tuple")
        errors(function() T.ZeroNil(T.String) end, "ZeroNil of text")
        errors(function() T.Map(T.List(T.UInt), T.UInt) end, "a map keyed by a list")
        local many = {}
        for i = 1, 53 do many[i] = { "k" .. i, T.UInt } end
        errors(function() T.Object(many) end, "more keys than a bitmap holds")
        errors(function() T.Schema { id = 0, root = T.UInt, module = "X" } end, "a schema id of 0")
    end)

    test("report at the schema line that called them", function()
        local _, message = pcall(function()
            local t = T.Object { { "a", T.UInt }, { "a", T.UInt } }
            return t
        end)
        ok(tostring(message):find("Tools/Codec/GenTests.lua", 1, true), "the message names the caller: " .. tostring(message))
    end)
end)

--------------------------------------------------------------------------------

suite("Generated codecs", function()
    test("write a step as the proposal's bytes", function()
        local c = stepCodec()
        local bytes = roundTrip(c, { { "accept", { quests = { 363 } } }, { npc = { 1568 } } }, "accept")
        eq(hex(bytes), "03 01 01 EB 02 02 01 A0 0C", "variant, its bitmap and quests, the common bitmap and npc")
        bytes = roundTrip(c, { { "note" }, { at = { { 5226, 4410 } } } }, "note at a point")
        eq(hex(bytes), "00 04 01 EA 28 BA 22 00", "a bare variant takes no bitmap; a point is x, y, map + 1")
        bytes = roundTrip(c, { { "note" }, { at = { { 5226, 4410, 1454 } }, sticky = true } }, "with a map, sticky")
        eq(hex(bytes), "00 0C 01 EA 28 BA 22 AF 0B", "map 1454 is written as 1455; sticky is only its bit")
    end)

    test("keep a zero that ZeroNil holds apart from nil", function()
        local c = codec(T.Tuple { T.ZeroNil(T.UInt), T.ZeroNil(T.Enum { "a", "b" }) })
        eq(hex(roundTrip(c, { 0, "a" }, "zeros")), "01 01", "0 and the first enum value")
        eq(hex(roundTrip(c, {}, "nils")), "00 00", "both nil")
    end)

    test("round trip every kind of type", function()
        local Kind = T.Enum { "red", "green" }
        local c = codec(T.Object {
            { "u", T.UInt }, { "s", T.SInt }, { "text", T.String }, { "flag", T.True }, { "kind", Kind },
            { "pair", T.Tuple { T.String, T.SInt } },
            { "list", T.List(T.Object { { "name", T.String } }) },
            { "byID", T.Map(T.UInt, T.Map(T.String, T.UInt)) },
            { "byKind", T.Map(Kind, T.String) },
            { "either", T.Union { { "one", T.UInt }, { "many", T.List(T.UInt) }, "none" } },
        })
        roundTrip(c, {}, "an empty object")
        roundTrip(c, {
            u = 9007199254740992, s = -4503599627370496, text = "a\0b", flag = true, kind = "green",
            pair = { "", -1 }, list = { { name = "x" }, {} }, byID = { [3] = { a = 1 }, [1] = { b = 2, c = 0 } },
            byKind = { red = "r" }, either = { "many", { 1, 2, 3 } },
        }, "every field")
        roundTrip(c, { either = { "none" }, list = {} }, "a bare variant and an empty list")
    end)

    test("write maps with their keys sorted", function()
        local c = codec(T.Map(T.UInt, T.UInt))
        eq(hex(c.Encode({ [300] = 1, [2] = 3 })), "02 02 03 AC 02 01", "2 before 300")
    end)

    test("name the place a value is wrong", function()
        local c = stepCodec()
        local function refused(value, expect, name)
            local bytes, problem = c.Encode(value)
            ok(bytes == nil and problem and problem:find(expect, 1, true), name .. ": " .. tostring(problem))
        end
        refused({ { "accept", { quests = { 1, "x" } } }, {} }, "[1].accept.quests[2] is not a whole number", "a quest that is text")
        refused({ { "travel", { to = 5 } }, {} }, "[1].travel.to is not text", "to is a number")
        refused({ { "fly" }, {} }, "[1] has no variant fly", "an unknown variant")
        refused({ { "note", {} }, {} }, "[1].note takes no value", "a bare variant given a value")
        refused({ { "note" }, { colour = 1 } }, "[2].colour is not a field here", "a key the object has no field for")
        refused({ { "note" }, { sticky = 1 } }, "[2].sticky is not true", "a flag that is not true")
        refused({ { "note" }, { at = { { 1.5, 2 } } } }, "[2].at[1][1] is not a whole number", "a point off the grid")
        refused({ { "note" }, { at = { { 1 } } } }, "[2].at[1][2] is missing", "a point with no y")
        refused({ { "note" }, { at = { { 1, 2, map = 3 } } } }, "[2].at[1].map is not part of this tuple", "a named key in a tuple")
        local holed = { 1 }
        holed[3] = 3
        refused({ { "note" }, { npc = holed } }, "[2].npc[3] is not part of a list", "a list with a hole")
        refused({ { "note" } }, "[2] is missing", "no common part")
    end)

    test("refuse bytes that do not read as the schema", function()
        local c = stepCodec()
        local bytes = c.Encode({ { "accept", { quests = { 363 } } }, { npc = { 1568 } } })
        local function refused(input, expect, name)
            local value, problem = c.Decode(input)
            ok(value == nil and problem == expect, name .. ": " .. tostring(problem))
        end
        refused(bytes:sub(1, -2), "it is damaged", "cut short")
        refused(bytes .. "\0", "it has bytes left over", "a byte too many")
        refused("\9" .. bytes:sub(2), "it is damaged", "a variant past the last")
        refused("\0\16", "it is damaged", "a bit past the last field")
        refused("\0\2\200\1", "it is damaged", "a list longer than what is left")
        refused(nil, "there is nothing to read", "not a string")
    end)

    test("expose the keys of named objects and the variants of named unions", function()
        local c = stepCodec()
        ok(c.Keys.StepCommon.npc and c.Keys.StepCommon.sticky and not c.Keys.StepCommon.quests, "StepCommon's keys")
        eq(c.Variants.StepKind.note, false, "note takes no value")
        eq(c.Variants.StepKind.accept, true, "accept does")
        eq(c.SCHEMA, 7, "the schema's id")
    end)

    test("share one function for a type used in several places", function()
        local Shared = T.Object { { "a", T.UInt } }
        local _, source = codec(T.Object { { "x", Shared }, { "y", Shared } }, { Shared = Shared })
        local _, count = source:gsub("function W%.Shared%(", "")
        eq(count, 1, "one write function for Shared")
    end)
end)

print("NuuKit codec generator tests passed (" .. W.count .. " tests)")
return true
