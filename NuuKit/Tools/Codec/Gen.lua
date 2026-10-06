-- NuuKit/Tools/Codec/Gen.lua: writes the Lua encoder and decoder a codec
-- schema describes. Never shipped; what it writes is.
--
--   lua ../NuuKit/Tools/Codec/Gen.lua Schema/Guide.lua Data/GuideCodec.lua   (from NuuRoad/)
--
-- A schema file is ordinary Lua that builds its types with the helpers in
-- Types.lua (its argument: `local T = ...`) and returns T.Schema { id, root,
-- module, names }. The generated file is an addon file: it registers
-- `module` with ns:RegisterModule and reaches the kit as ns.Kit.Codec when
-- it runs. It holds:
--
--   M.SCHEMA          the schema's id, the number a shared string carries
--   M.Encode(value)   the bytes, or nil and where the value is wrong
--   M.Decode(bytes)   the value, or nil and what is wrong with the bytes
--   M.Keys[name]      { key = true } of each named object
--   M.Variants[name]  { variant = takes a value } of each named union
--
-- A value is what the schema says: an object a table of its keys, a tuple
-- { a, b, c }, a union { "name", value }, a list { v, ... }, a map { [k] = v }.
-- Encode refuses anything else (a key the object has no field for, a number
-- that is not whole, a value of the wrong kind) and names the place; Decode
-- refuses bytes that do not read as the schema to the last byte.
--
-- Each type with parts gets one write and one read function, shared by every
-- place that uses it (by table identity), named after the schema's `names`
-- or after the first place it is found. They live in tables (W, R), not
-- locals: a schema has more types than Lua 5.1 allows locals in one chunk. A
-- type that contained itself would be refused, though the helpers cannot
-- build one.
--
-- From Lua, dofile this file with no arguments for { Load(path), Generate(schema, header) }.

local Gen = {}

local here = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "")
local T = dofile(here .. "Types.lua")
Gen.Types = T

function Gen.Load(path)
    local chunk = assert(loadfile(path))
    local schema = chunk(T)
    assert(type(schema) == "table" and schema.kind == "schema", path .. " does not return T.Schema { ... }")
    return schema
end

local function quote(s) return ("%q"):format(s) end
local function number(n) return ("%.0f"):format(n) end

local COMPOSITE = { tuple = true, object = true, union = true, list = true, map = true }

-- generate(schema, header) -> the generated file's text.
function Gen.Generate(schema, header)
    local names, used = {}, {}
    local order, enums = {}, {}
    local done, visiting = {}, {}

    local named = {}
    for name in pairs(schema.names) do named[#named + 1] = name end
    table.sort(named)
    for _, name in ipairs(named) do
        local t = schema.names[name]
        if names[t] then error("the schema names one type both " .. names[t] .. " and " .. name, 0) end
        names[t] = name
        used[name] = true
    end

    local function nameOf(t, suggestion)
        if names[t] then return names[t] end
        local base = suggestion:gsub("[^%w_]", "_")
        local name, i = base, 2
        while used[name] do
            name = base .. "_" .. i
            i = i + 1
        end
        used[name] = true
        names[t] = name
        return name
    end

    local function visit(t, suggestion, path)
        if t.kind == "zeronil" then return visit(t.of, suggestion, path) end
        if t.kind == "enum" then
            nameOf(t, suggestion)
            if not done[t] then
                done[t] = true
                enums[#enums + 1] = t
            end
            return
        end
        if not COMPOSITE[t.kind] or done[t] then return end
        if visiting[t] then error("the schema's " .. path .. " contains itself", 0) end
        visiting[t] = true
        local own = nameOf(t, suggestion)
        if t.kind == "object" then
            for _, field in ipairs(t.fields) do visit(field.type, own .. "_" .. field.key, path .. "." .. field.key) end
        elseif t.kind == "tuple" then
            for i, item in ipairs(t.items) do visit(item, own .. "_" .. i, path .. "[" .. i .. "]") end
        elseif t.kind == "union" then
            for _, variant in ipairs(t.variants) do
                if variant.type then visit(variant.type, own .. "_" .. variant.name, path .. "." .. variant.name) end
            end
        elseif t.kind == "list" then
            visit(t.of, own .. "_item", path .. "[]")
        elseif t.kind == "map" then
            visit(t.key, own .. "_key", path .. "{}")
            visit(t.value, own .. "_value", path .. "{}")
        end
        visiting[t] = nil
        done[t] = true
        order[#order + 1] = t
    end
    visit(schema.root, names[schema.root] or "Root", "root")

    local out = {}
    local function emit(line) out[#out + 1] = line end

    -- The statement that writes value expression x of type t; at and key
    -- (Lua expressions) are where it sits, for the error.
    local function write(t, x, at, key)
        local kind = t.kind
        if kind == "uint" then return ("putU(w, %s, %s, %s)"):format(x, at, key) end
        if kind == "sint" then return ("putI(w, %s, %s, %s)"):format(x, at, key) end
        if kind == "string" then return ("putS(w, %s, %s, %s)"):format(x, at, key) end
        if kind == "enum" then return ("putE(w, %s, E.%s, %s, %s)"):format(x, names[t], at, key) end
        if kind == "zeronil" then
            if t.of.kind == "uint" then return ("putZU(w, %s, %s, %s)"):format(x, at, key) end
            return ("putZE(w, %s, E.%s, %s, %s)"):format(x, names[t.of], at, key)
        end
        return ("W.%s(w, %s, { %s, %s })"):format(names[t], x, at, key)
    end

    -- The expression that reads a value of type t.
    local function read(t)
        local kind = t.kind
        if kind == "uint" then return "r:U()" end
        if kind == "sint" then return "r:I()" end
        if kind == "string" then return "r:Bytes()" end
        if kind == "enum" then return ("getE(r, N.%s)"):format(names[t]) end
        if kind == "zeronil" then
            if t.of.kind == "uint" then return "getZU(r)" end
            return ("getZE(r, N.%s)"):format(names[t.of])
        end
        return ("R.%s(r)"):format(names[t])
    end

    header = header or {}
    for _, line in ipairs(header) do emit(line == "" and "--" or "-- " .. line) end
    emit("local _, ns = ...")
    emit("")
    emit(("local M = { SCHEMA = %d, Keys = {}, Variants = {} }"):format(schema.id))
    emit("-- Each type's write and read function, and the enums, keys and variants they use.")
    emit("local W, R, E, N, K, U, V = {}, {}, {}, {}, {}, {}, {}")
    emit([[
local type, pairs, tostring, error, pcall, concat, sort = type, pairs, tostring, error, pcall, table.concat, table.sort
local MAX = 9007199254740992

-- Where a value is wrong: `at` is a chain of { parent, key }, built as the
-- encoder goes down into a part.
local function fail(at, key, message) error({ codecAt = at, codecKey = key, codecMessage = message }, 0) end

local function where(at, key)
    local keys = { key }
    while at do
        keys[#keys + 1] = at[2]
        at = at[1]
    end
    local parts = {}
    for i = #keys, 1, -1 do
        local k = keys[i]
        if type(k) == "number" then parts[#parts + 1] = "[" .. k .. "]"
        elseif #parts == 0 then parts[1] = tostring(k)
        else parts[#parts + 1] = "." .. tostring(k) end
    end
    return concat(parts)
end

local function whole(x) return type(x) == "number" and x >= 0 and x <= MAX and x % 1 == 0 end
local function missing(x, otherwise) if x == nil then return "is missing" end return otherwise end

local function putU(w, x, at, key)
    if not whole(x) then fail(at, key, missing(x, "is not a whole number of 0 or more")) end
    w:U(x)
end
local function putI(w, x, at, key)
    if type(x) ~= "number" or x % 1 ~= 0 or x < -MAX / 2 or x > MAX / 2 then fail(at, key, missing(x, "is not a whole number")) end
    w:I(x)
end
local function putS(w, x, at, key)
    if type(x) ~= "string" then fail(at, key, missing(x, "is not text")) end
    w:Bytes(x)
end
local function putE(w, x, enum, at, key)
    local i = enum[x]
    if not i then fail(at, key, missing(x, "cannot be " .. tostring(x))) end
    w:U(i)
end
local function putZU(w, x, at, key)
    if x == nil then w:U(0) return end
    if not whole(x) or x >= MAX then fail(at, key, "is not a whole number of 0 or more") end
    w:U(x + 1)
end
local function putZE(w, x, enum, at, key)
    if x == nil then w:U(0) return end
    local i = enum[x]
    if not i then fail(at, key, "cannot be " .. tostring(x)) end
    w:U(i + 1)
end
local function getE(r, names)
    local s = names[r:U()]
    if s == nil then r:Fail() end
    return s
end
local function getZU(r)
    local z = r:U()
    if z > 0 then return z - 1 end
end
local function getZE(r, names)
    local z = r:U()
    if z == 0 then return nil end
    local s = names[z - 1]
    if s == nil then r:Fail() end
    return s
end
local function isTable(v, at, what) if type(v) ~= "table" then fail(at, nil, missing(v, "is not " .. what)) end end
local function onlyPositions(v, n, at, what)
    for key in pairs(v) do
        if type(key) ~= "number" or key < 1 or key > n or key % 1 ~= 0 then fail(at, key, "is not part of " .. what) end
    end
end]])

    for _, t in ipairs(enums) do
        local name = names[t]
        local values, list = {}, {}
        for i, value in ipairs(t.values) do
            values[#values + 1] = ("[%s] = %d"):format(quote(value), i - 1)
            list[#list + 1] = (i == 1 and "[0] = " or "") .. quote(value)
        end
        emit("")
        emit(("E.%s = { %s }"):format(name, table.concat(values, ", ")))
        emit(("N.%s = { %s }"):format(name, table.concat(list, ", ")))
    end

    for _, t in ipairs(order) do
        local name = names[t]
        emit("")
        if t.kind == "object" then
            local keys = {}
            for _, field in ipairs(t.fields) do keys[#keys + 1] = ("[%s] = true"):format(quote(field.key)) end
            emit(("K.%s = { %s }"):format(name, table.concat(keys, ", ")))
            emit(("function W.%s(w, v, at)"):format(name))
            emit("    isTable(v, at, \"a table\")")
            emit(("    for key in pairs(v) do if not K.%s[key] then fail(at, key, \"is not a field here\") end end"):format(name))
            emit("    local bits, x = 0, nil")
            for i, field in ipairs(t.fields) do
                local bit = number(2 ^ (i - 1))
                if field.type.kind == "true" then
                    emit(("    x = v[%s] if x ~= nil then if x ~= true then fail(at, %s, \"is not true\") end bits = bits + %s end")
                        :format(quote(field.key), quote(field.key), bit))
                else
                    emit(("    if v[%s] ~= nil then bits = bits + %s end"):format(quote(field.key), bit))
                end
            end
            emit("    w:U(bits)")
            for _, field in ipairs(t.fields) do
                if field.type.kind ~= "true" then
                    emit(("    x = v[%s] if x ~= nil then %s end"):format(quote(field.key), write(field.type, "x", "at", quote(field.key))))
                end
            end
            emit("end")
            emit(("function R.%s(r)"):format(name))
            emit("    local v, bits, b = {}, r:U(), 0")
            emit(("    if bits >= %s then r:Fail() return v end"):format(number(2 ^ #t.fields)))
            for _, field in ipairs(t.fields) do
                local value = field.type.kind == "true" and "true" or read(field.type)
                emit(("    b = bits %% 2 bits = (bits - b) / 2 if b == 1 then v[%s] = %s end"):format(quote(field.key), value))
            end
            emit("    return v")
            emit("end")
        elseif t.kind == "tuple" then
            local n = #t.items
            emit(("function W.%s(w, v, at)"):format(name))
            emit("    isTable(v, at, \"a table\")")
            emit(("    onlyPositions(v, %d, at, \"this tuple\")"):format(n))
            for i, item in ipairs(t.items) do emit("    " .. write(item, ("v[%d]"):format(i), "at", tostring(i))) end
            emit("end")
            emit(("function R.%s(r)"):format(name))
            local reads = {}
            for i, item in ipairs(t.items) do reads[i] = read(item) end
            if n == 1 then
                emit(("    return { %s }"):format(reads[1]))
            else
                local locals = {}
                for i = 1, n do locals[i] = "x" .. i end
                emit(("    local %s = %s"):format(locals[1], reads[1]))
                for i = 2, n do emit(("    local %s = %s"):format(locals[i], reads[i])) end
                emit(("    return { %s }"):format(table.concat(locals, ", ")))
            end
            emit("end")
        elseif t.kind == "union" then
            local index, takes = {}, {}
            for i, variant in ipairs(t.variants) do
                index[#index + 1] = ("[%s] = %d"):format(quote(variant.name), i - 1)
                takes[#takes + 1] = ("[%s] = %s"):format(quote(variant.name), tostring(variant.type ~= nil))
            end
            emit(("U.%s = { %s }"):format(name, table.concat(index, ", ")))
            emit(("V.%s = { %s }"):format(name, table.concat(takes, ", ")))
            emit(("function W.%s(w, v, at)"):format(name))
            emit("    isTable(v, at, \"a table\")")
            emit("    onlyPositions(v, 2, at, \"a union\")")
            emit(("    local i = U.%s[v[1]]"):format(name))
            emit("    if not i then fail(at, nil, missing(v[1], \"has no variant \" .. tostring(v[1]))) end")
            emit("    w:U(i)")
            for i, variant in ipairs(t.variants) do
                local test = (i == 1 and "    if" or "    elseif") .. (" i == %d then "):format(i - 1)
                if variant.type then
                    emit(test .. write(variant.type, "v[2]", "at", quote(variant.name)))
                else
                    emit(test .. ("if v[2] ~= nil then fail(at, %s, \"takes no value\") end"):format(quote(variant.name)))
                end
            end
            emit("    end")
            emit("end")
            emit(("function R.%s(r)"):format(name))
            emit("    local i = r:U()")
            for i, variant in ipairs(t.variants) do
                local test = (i == 1 and "    if" or "    elseif") .. (" i == %d then "):format(i - 1)
                if variant.type then
                    emit(test .. ("return { %s, %s }"):format(quote(variant.name), read(variant.type)))
                else
                    emit(test .. ("return { %s }"):format(quote(variant.name)))
                end
            end
            emit("    end")
            emit("    r:Fail()")
            emit("    return {}")
            emit("end")
        elseif t.kind == "list" then
            emit(("function W.%s(w, v, at)"):format(name))
            emit("    isTable(v, at, \"a list\")")
            emit("    local n = #v")
            emit("    onlyPositions(v, n, at, \"a list\")")
            emit("    w:U(n)")
            emit(("    for i = 1, n do %s end"):format(write(t.of, "v[i]", "at", "i")))
            emit("end")
            emit(("function R.%s(r)"):format(name))
            emit("    local n, v = r:U(), {}")
            emit("    if n > r:Left() then r:Fail() return v end")
            emit(("    for i = 1, n do v[i] = %s end"):format(read(t.of)))
            emit("    return v")
            emit("end")
        elseif t.kind == "map" then
            local key = t.key
            local check
            if key.kind == "uint" then
                check = "if not whole(key) then fail(at, key, \"is not a whole number of 0 or more\") end"
            elseif key.kind == "string" then
                check = "if type(key) ~= \"string\" then fail(at, key, \"is not text\") end"
            else
                check = ("if not E.%s[key] then fail(at, key, \"is not a key here\") end"):format(names[key])
            end
            emit(("function W.%s(w, v, at)"):format(name))
            emit("    isTable(v, at, \"a table\")")
            emit("    local keys, n = {}, 0")
            emit(("    for key in pairs(v) do %s n = n + 1 keys[n] = key end"):format(check))
            emit("    sort(keys)")
            emit("    w:U(n)")
            emit("    for i = 1, n do")
            emit("        local key = keys[i]")
            emit("        " .. write(key, "key", "at", "key"))
            emit("        " .. write(t.value, "v[key]", "at", "key"))
            emit("    end")
            emit("end")
            emit(("function R.%s(r)"):format(name))
            emit("    local n, v = r:U(), {}")
            emit("    if n * 2 > r:Left() then r:Fail() return v end")
            emit("    for _ = 1, n do")
            emit(("        local key = %s"):format(read(key)))
            emit("        if key == nil or v[key] ~= nil then r:Fail() return v end")
            emit(("        v[key] = %s"):format(read(t.value)))
            emit("    end")
            emit("    return v")
            emit("end")
        end
    end

    for _, name in ipairs(named) do
        local t = schema.names[name]
        if t.kind == "object" and done[t] then emit(("M.Keys.%s = K.%s"):format(name, name)) end
        if t.kind == "union" and done[t] then emit(("M.Variants.%s = V.%s"):format(name, name)) end
    end

    local root = schema.root
    emit("")
    emit("function M.Encode(value)")
    emit("    local w = ns.Kit.Codec.Writer()")
    emit(("    local ok, err = pcall(function() %s end)"):format(write(root, "value", "nil", "nil"):gsub("{ nil, nil }", "nil")))
    emit("    if ok then return w:Finish() end")
    emit("    if type(err) == \"table\" and err.codecMessage then")
    emit("        local path = where(err.codecAt, err.codecKey)")
    emit("        return nil, (path ~= \"\" and path .. \" \" or \"\") .. err.codecMessage")
    emit("    end")
    emit("    return nil, tostring(err)")
    emit("end")
    emit("")
    emit("function M.Decode(bytes)")
    emit("    if type(bytes) ~= \"string\" then return nil, \"there is nothing to read\" end")
    emit("    local r = ns.Kit.Codec.Reader(bytes)")
    emit(("    local value = %s"):format(read(root)))
    emit("    if not r:Ok() then return nil, \"it is damaged\" end")
    emit("    if r:More() then return nil, \"it has bytes left over\" end")
    emit("    return value")
    emit("end")
    emit("")
    emit(("ns:RegisterModule(%s, M)"):format(quote(schema.module)))
    return table.concat(out, "\n") .. "\n"
end

-- The standard header: what wrote the file, and how to write it again.
function Gen.Header(schemaPath, outPath)
    return {
        outPath .. ". Generated by NuuKit/Tools/Codec/Gen.lua from " .. schemaPath .. ": do not edit it.",
        "Change the schema and generate it again, from the addon's folder:",
        "  lua ../NuuKit/Tools/Codec/Gen.lua " .. schemaPath .. " " .. outPath,
        "",
    }
end

if select("#", ...) > 0 then
    local schemaPath, outPath = ...
    assert(schemaPath and outPath, "usage: lua Gen.lua <schema.lua> <out.lua>")
    local source = Gen.Generate(Gen.Load(schemaPath), Gen.Header(schemaPath, outPath))
    local file = assert(io.open(outPath, "wb"))
    file:write(source)
    file:close()
    print("wrote " .. outPath)
end

return Gen
