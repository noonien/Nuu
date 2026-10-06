local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Codec/Writer.lua: a bytestream writer. Plain bytes, no framing and no
-- size cap: Core/Comms/Frame.lua frames what it writes for an addon message,
-- Core/Codec/Text.lua for a string a player shares, and the codecs that
-- NuuKit/Tools/Codec/Gen.lua generates write their values with it.
--
--     local w = Kit.Codec.Writer()
--     w:U(7):Bytes("name"):True()
--     local bytes = w:Finish()
--
-- U/I are LEB128 varints, I zigzag. By default they take every whole number
-- a Lua number holds exactly (U to 2^53, I to +-2^52); Codec.Writer(limits)
-- narrows that (Comms keeps four groups of 7 bits). True/False are 0x01/0x00.
-- U8/I8 to U64/I64 are little-endian two's-complement bytes. Bytes is a
-- length and then the bytes. Mark() and Restore(mark) drop what was written
-- after the mark; Len() is the bytes written so far.
--
-- Pieces are kept as strings (interned 1-byte strings for single bytes) and
-- joined once, at Finish.
local Codec = Kit.Codec or {}
Kit.Codec = Codec

-- What U and I take: the varint groups a reader allows, and the ranges.
Codec.LIMITS = { groups = 8, umax = 9007199254740992, imin = -4503599627370496, imax = 4503599627370496 }

local Writer = {}
Writer.__index = Writer
-- For a writer of its own kind: a table whose __index reaches these
-- (Core/Comms/Frame.lua's frame writer).
Codec.WriterMethods = Writer

local CH, floor, concat = {}, math.floor, table.concat
for i = 0, 255 do CH[i] = string.char(i) end

-- limits: Codec.LIMITS or narrower. class: the metatable, Writer by default.
function Codec.Writer(limits, class)
    limits = limits or Codec.LIMITS
    return setmetatable({ buf = {}, n = 0, len = 0, umax = limits.umax, imin = limits.imin, imax = limits.imax },
        class or Writer)
end

local function put(self, piece, size)
    local n = self.n + 1
    self.n = n
    self.buf[n] = piece
    self.len = self.len + size
end

local function putVarint(self, n)
    repeat
        local b = n % 128
        n = floor(n / 128)
        if n > 0 then b = b + 128 end
        put(self, CH[b], 1)
    until n == 0
end

-- Little-endian two's complement. n may be negative: Lua's % yields the
-- unsigned byte and floor division sign-extends through the rest.
local function putLE(self, n, k)
    for _ = 1, k do
        put(self, CH[n % 256], 1)
        n = floor(n / 256)
    end
end

function Writer:Len()
    return self.len
end

function Writer:Mark()
    return { n = self.n, len = self.len }
end

function Writer:Restore(mark)
    self.n, self.len = mark.n, mark.len
    return self
end

function Writer:U(n)
    n = floor(n)
    assert(n >= 0 and n <= self.umax, "unsigned integer out of range")
    if n < 128 then put(self, CH[n], 1) else putVarint(self, n) end
    return self
end

function Writer:I(n)
    n = floor(n)
    assert(n >= self.imin and n <= self.imax, "signed integer out of range")
    n = n >= 0 and (2 * n) or (-2 * n - 1)
    if n < 128 then put(self, CH[n], 1) else putVarint(self, n) end
    return self
end

function Writer:True()
    put(self, CH[1], 1)
    return self
end

function Writer:False()
    put(self, CH[0], 1)
    return self
end

function Writer:U8(n)
    n = floor(n)
    assert(n >= 0 and n <= 255, "u8 out of range")
    put(self, CH[n], 1)
    return self
end

function Writer:I8(n)
    n = floor(n)
    assert(n >= -128 and n <= 127, "i8 out of range")
    put(self, CH[n % 256], 1)
    return self
end

function Writer:U16(n)
    n = floor(n)
    assert(n >= 0 and n <= 65535, "u16 out of range")
    putLE(self, n, 2)
    return self
end

function Writer:I16(n)
    n = floor(n)
    assert(n >= -32768 and n <= 32767, "i16 out of range")
    putLE(self, n, 2)
    return self
end

function Writer:U32(n)
    n = floor(n)
    assert(n >= 0 and n <= 4294967295, "u32 out of range")
    putLE(self, n, 4)
    return self
end

function Writer:I32(n)
    n = floor(n)
    assert(n >= -2147483648 and n <= 2147483647, "i32 out of range")
    putLE(self, n, 4)
    return self
end

-- Lua 5.1 numbers are doubles: every integer in +-2^53 is exact, and 64-bit
-- patterns outside that cannot round-trip. The wire is still eight bytes.
function Writer:U64(n)
    n = floor(n)
    assert(n >= 0 and n <= 9007199254740992, "u64 out of range")
    putLE(self, n, 8)
    return self
end

function Writer:I64(n)
    n = floor(n)
    assert(n >= -9007199254740992 and n <= 9007199254740992, "i64 out of range")
    putLE(self, n, 8)
    return self
end

function Writer:Bytes(s)
    assert(type(s) == "string", "bytes must be a string")
    local n = #s
    if n < 128 then put(self, CH[n], 1) else putVarint(self, n) end
    if n > 0 then put(self, s, n) end
    return self
end

function Writer:Finish()
    return concat(self.buf, "", 1, self.n)
end
