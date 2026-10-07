-- The codec's cost per call (Core/Codec/): fields written and read, base64,
-- Adler-32, DEFLATE and the shared string, at the sizes the kit sees: one
-- addon message, a small guide and the largest (about 30 KB of bytes).
-- From NuuKit/: nix-shell -p lua5_1 --run "lua Tests/Bench/Codec.lua [file]"
-- With a file, its bytes are the large body instead of the stand-in.
--
-- Per call: Lua time, the rate through it, and the bytes it allocates
-- (garbage the collector must take later). Outside a job Kit.Job.Pause does
-- nothing, so this is the work alone; in game a job spreads it over frames.

BENCH = "Tests/Bench/"
local B = dofile(BENCH .. "Measure.lua")
local Kit = B.LoadKit()
local Codec = Kit.Codec

local large
if arg and arg[1] then
    local file = assert(io.open(arg[1], "rb"))
    large = file:read("*a")
    file:close()
else
    large = B.Body(Codec, 30 * 1024)
end
local bodies = {
    { name = "message", bytes = B.Body(Codec, 247):sub(1, 247) },
    { name = "4 KB", bytes = B.Body(Codec, 4 * 1024) },
    { name = arg and arg[1] and "file" or "30 KB", bytes = large },
}

print(("Codec bench (%s). Bodies: %s"):format(_VERSION, (function()
    local list = {}
    for _, body in ipairs(bodies) do list[#list + 1] = body.name .. " " .. #body.bytes .. " B" end
    return table.concat(list, ", ")
end)()))

-- Fields ----------------------------------------------------------------------

-- A guide step's fields, as Body writes them.
local function step(w)
    return w:U(7):U(4321):U(1):U(14):I(5123):I(-6789):U(12345):Bytes("Speak to Bloodhoof")
end
local stepBytes = step(Codec.Writer()):Finish()

B.Header("Fields")
B.Row("Writer: a step (8 fields) + Finish", B.Measure(function() step(Codec.Writer()):Finish() end), nil,
    #stepBytes)
B.Row("Reader: the step back", B.Measure(function()
    local r = Codec.Reader(stepBytes)
    r:U(); r:U(); r:U(); r:U(); r:I(); r:I(); r:U(); r:Bytes()
end), #stepBytes)

-- A thousand of one kind of field, written and read back.
local N = 1000
local fields = {
    { "U below 128", "U", function(w, i) w:U(i % 128) end },
    { "U of 3 bytes", "U", function(w, i) w:U(20000 + i) end },
    { "I of 2 bytes", "I", function(w, i) w:I(-1000 - i) end },
    { "U32", "U32", function(w, i) w:U32(i * 4099) end },
    { "Bytes of 18", "Bytes", function(w) w:Bytes("Speak to Bloodhoof") end },
}
for _, field in ipairs(fields) do
    local label, method, write = field[1], field[2], field[3]
    local function written()
        local w = Codec.Writer()
        for i = 1, N do write(w, i) end
        return w:Finish()
    end
    local s = written()
    B.Row("Writer: 1000 " .. label .. " + Finish", B.Measure(written), nil, #s)
    B.Row("Reader: 1000 " .. label, B.Measure(function()
        local r = Codec.Reader(s)
        local read = r[method]
        for _ = 1, N do read(r) end
    end), #s)
end

-- Whole bodies -----------------------------------------------------------------

for _, body in ipairs(bodies) do
    local bytes = body.bytes
    local text = Codec.ToBase64(bytes)
    local packed = Codec.Deflate(bytes)
    local shared = Codec.ToText(1, bytes)
    assert(Codec.FromBase64(text) == bytes and Codec.Inflate(packed) == bytes, "the codec reads back what it wrote")
    assert(select(2, Codec.FromText(shared)) == bytes, "the shared string reads back")

    B.Header(("A body of %s (deflated to %d%%)"):format(body.name, math.floor(#packed * 100 / #bytes + 0.5)))
    B.Row("ToBase64", B.Measure(function() Codec.ToBase64(bytes) end), #bytes, #text)
    B.Row("FromBase64", B.Measure(function() Codec.FromBase64(text) end), #text, #bytes)
    B.Row("Adler32", B.Measure(function() Codec.Adler32(bytes) end), #bytes, 4)
    B.Row("Deflate", B.Measure(function() Codec.Deflate(bytes) end), #bytes, #packed)
    B.Row("Inflate", B.Measure(function() Codec.Inflate(packed) end), #packed, #bytes)
    B.Row("ToText (the nuu: string)", B.Measure(function() Codec.ToText(1, bytes) end), #bytes, #shared)
    B.Row("FromText", B.Measure(function() Codec.FromText(shared) end), #shared, #bytes)
end
