_G = _G or _ENV
-- Guides as players share them: the share schema Schema/Guide.lua, the codec
-- Data/GuideCodec.lua that NuuKit/Tools/Codec/Gen.lua generates from it, and
-- Data/GuideShare.lua between it and guide sources. Every packaged guide,
-- fixture and the worked example must come back from its bytes as the same value; the
-- schema must match the step types and fields GuideDraft knows; the
-- generated file must be the schema's.
local ns = NewNamespace()
Load(ns, "Data/GuideText.lua")
Load(ns, "Domain/GuideDraft.lua")
Load(ns, "Data/GuideCodec.lua")
Load(ns, "Data/GuideShare.lua")
LoadBuiltIns(ns)
local GuideShare, GuideCodec, GuideText = ns.modules.GuideShare, ns.modules.GuideCodec, ns.modules.GuideText
local GuideDraft = ns.modules.GuideDraft
local Gen = dofile("../NuuKit/Tools/Codec/Gen.lua")

local function same(a, b, path)
    path = path or "guide"
    if type(a) ~= "table" or type(b) ~= "table" then
        if a ~= b then return false, path .. ": " .. tostring(a) .. " ~= " .. tostring(b) end
        return true
    end
    for key, value in pairs(a) do
        local equal, where = same(value, b[key], path .. "." .. tostring(key))
        if not equal then return false, where end
    end
    for key in pairs(b) do
        if a[key] == nil then return false, path .. "." .. tostring(key) .. " is new" end
    end
    return true
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end

-- The generated file is the schema's.
do
    local source = Gen.Generate(Gen.Load("Schema/Guide.lua"), Gen.Header("Schema/Guide.lua", "Data/GuideCodec.lua"))
    local file = assert(io.open("Data/GuideCodec.lua", "rb"))
    local written = file:read("*a")
    file:close()
    assert(written == source, "Data/GuideCodec.lua is not Schema/Guide.lua's: generate it again"
        .. " (lua ../NuuKit/Tools/Codec/Gen.lua Schema/Guide.lua Data/GuideCodec.lua)")
    assert(not written:find("[^%z\1-\127]"), "the generated codec is ASCII")
end

-- The schema's step kinds and common fields are GuideDraft's: each type's
-- own fields, and what any step may carry. `item` is common in the schema
-- (one ID or a list, by type) and a type's own field in GuideDraft.
do
    local schema = Gen.Load("Schema/Guide.lua")
    local kinds, common = schema.names.StepKind, schema.names.StepCommon
    local seen = {}
    for _, variant in ipairs(kinds.variants) do
        local own = GuideDraft.typeFields[variant.name]
        assert(own, "the schema's step kind " .. variant.name .. " is a GuideDraft type")
        seen[variant.name] = true
        local want = {}
        for _, key in ipairs(own) do if key ~= "item" then want[key] = true end end
        local have = {}
        for _, field in ipairs(variant.type and variant.type.fields or {}) do have[field.key] = true end
        local equal, where = same(have, want, variant.name)
        assert(equal, "the schema's " .. variant.name .. " has GuideDraft's fields: " .. tostring(where))
    end
    for name in pairs(GuideDraft.typeFields) do assert(seen[name], "GuideDraft's type " .. name .. " is in the schema") end
    local have, want = {}, {}
    for _, field in ipairs(common.fields) do have[field.key] = true end
    for key in pairs(GuideDraft.commonFields) do if key ~= "type" then want[key] = true end end
    want.item = true
    local equal, where = same(have, want, "StepCommon")
    assert(equal, "StepCommon is GuideDraft's common fields and item: " .. tostring(where))
end

-- Every guide in Data/Guides is one the TOC lists, so the round trip below
-- reaches it.
do
    local listed, files = {}, 0
    for line in io.lines("NuuRoad.toc") do
        local name = line:match("^%s*Data/Guides/([^%s/]+%.lua)%s*$")
        if name then listed[name] = true end
    end
    local dir = io.popen and io.popen('ls "Data/Guides"')
    if dir then
        for name in dir:lines() do
            if name:match("%.lua$") then
                files = files + 1
                assert(listed[name], "Data/Guides/" .. name .. " is in NuuRoad.toc")
            end
        end
        dir:close()
        assert(files >= 20, "the packaged guides are found on disk")
    end
end

-- Every packaged guide and fixture, and the worked example, round trip:
-- as bytes, as the nuu: string a player shares, and to the same bytes again.
do
    local Codec = ns.Kit.Codec
    local guides, ids = {}, {}
    for id, guide in pairs(ns.builtInGuides) do
        guides[id] = guide
        ids[#ids + 1] = id
    end
    local example = dofile("docs/examples/guide-source.lua")
    guides[example.id] = example
    ids[#ids + 1] = example.id
    table.sort(ids)
    local text, binary = 0, 0
    for _, id in ipairs(ids) do
        local guide = guides[id]
        local before = copy(guide)
        local bytes, problem = GuideShare:Encode(guide)
        assert(bytes, id .. " encodes: " .. tostring(problem))
        assert(same(guide, before), id .. ": encoding leaves the guide as it was")
        local back, why = GuideShare:Decode(bytes)
        assert(back, id .. " decodes: " .. tostring(why))
        local equal, where = same(back, guide)
        assert(equal, id .. " comes back as it was: " .. tostring(where))
        assert(GuideShare:Encode(back) == bytes, id .. ": the guide it comes back as encodes to the same bytes")
        local shared = Codec.ToText(GuideCodec.SCHEMA, bytes)
        assert(Codec.IsText(shared) and not shared:find("[^%w%-_:]"), id .. " shares as one plain line")
        local schema, body = Codec.FromText(shared)
        assert(schema == GuideCodec.SCHEMA and body == bytes, id .. " comes back from its string: " .. tostring(body))
        local damaged = shared:sub(1, -2) .. (shared:sub(-1) == "A" and "B" or "A")
        assert(Codec.FromText(damaged) == nil, id .. ": its string with a character changed is refused")
        text, binary = text + #GuideText:Write(guide), binary + #bytes
    end
    assert(#ids >= 30, "the packaged guides, the fixtures and the example")
    -- Guide text is the editor's Copy as text; bytes are the codec's.
    print(("NuuRoad guide share: %d guides, %d KB as guide text, %d KB as bytes"):format(#ids, text / 1024, binary / 1024))
end

-- What a guide holds that the format has no place for is refused, by name.
do
    local function guide(step, extra)
        local value = { kind = "guide", id = "test:wire", title = "Wire",
            data = { map = 1411, sections = { { title = "One", steps = { step } } } } }
        for key, v in pairs(extra or {}) do value[key] = v end
        return value
    end
    local function refused(value, expect, name)
        local bytes, problem = GuideShare:Encode(value)
        assert(bytes == nil and problem and problem:find(expect, 1, true), name .. ": " .. tostring(problem))
    end
    assert(GuideShare:Encode(guide({ type = "note", note = "Fine." })), "a plain note encodes")
    refused(guide({ type = "note", colour = "red" }), "steps[1].step[2].colour is not a field here", "a key no step has")
    refused(guide({ type = "travel", quests = { 1 } }), "steps[1].step[1].travel.quests is not a field here",
        "a field of another type")
    refused(guide({ type = "fly" }), "steps[1].step[1] has no variant fly", "a type the format does not have")
    refused(guide({ type = "note", cond = { class = "BARD" } }), "cond.class.one cannot be BARD", "a class that is not one")
    refused(guide({ type = "note", at = { { 10.5, 20 } } }), "at[1][1] is not a whole number", "a point off the grid")
    refused(guide({ type = "note", cond = { any = { { none = { { any = { { ah = true } } } } } } } }),
        "conditions nest two deep at most", "conditions three deep")
    refused({ kind = "place" }, "not a guide source", "not a guide")
    refused(guide({ type = "note" }, { colour = "red" }), "colour is not a field here", "a key the wrapper does not have")
end

-- Damaged bytes are refused, never read as a guide.
do
    local bytes = assert(GuideShare:Encode(ns.builtInGuides[next(ns.builtInGuides)]))
    assert(GuideShare:Decode(bytes:sub(1, -2)) == nil, "cut short")
    assert(GuideShare:Decode(bytes .. "x") == nil, "a byte too many")
    assert(GuideShare:Decode("") == nil, "nothing")
end

print("NuuRoad guide share tests passed")
return true
