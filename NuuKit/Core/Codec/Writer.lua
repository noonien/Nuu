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
-- length and then the bytes; Raw is the bytes alone, for a last field the
-- reader takes with Rest(). Mark() and Restore(mark) drop what was written
-- after the mark (local mark = w:Mark() ... w:Restore(mark)); Len() is the
-- bytes written so far.
--
-- Pieces are kept as strings, one a field (interned 1-byte strings for single
-- bytes). Every BLOCK pieces they are joined into one, so the table of pieces
-- stays small however long the value, and Finish joins those.
local Codec = Kit.Codec or {}
Kit.Codec = Codec

-- What U and I take: the varint groups a reader allows, and the ranges.
Codec.LIMITS = { groups = 8, umax = 9007199254740992, imin = -4503599627370496, imax = 4503599627370496 }

local Writer = {}
Writer.__index = Writer
-- For a writer of its own kind: a table whose __index reaches these
-- (Core/Comms/Frame.lua's frame writer).
Codec.WriterMethods = Writer

local CH, floor, char, concat = {}, math.floor, string.char, table.concat
for i = 0, 255 do CH[i] = string.char(i) end
local BLOCK = 1024

-- limits: Codec.LIMITS or narrower. class: the metatable, Writer by default.
-- buf holds the last n pieces; done (made on first use) the k strings joined
-- before them, base bytes in all.
function Codec.Writer(limits, class)
    limits = limits or Codec.LIMITS
    return setmetatable({ buf = {}, n = 0, len = 0, k = 0, base = 0, umax = limits.umax, imin = limits.imin,
        imax = limits.imax }, class or Writer)
end

-- Joins the pieces into done; the next piece is buf[1].
local function join(self)
    local done, k = self.done or {}, self.k + 1
    done[k] = concat(self.buf, "", 1, self.n)
    self.done, self.k, self.base = done, k, self.len
    return 1
end

local function put(self, piece, size)
    local n = self.n + 1
    if n > BLOCK then n = join(self) end
    self.n = n
    self.buf[n] = piece
    self.len = self.len + size
end

-- A varint of 128 or more as one piece, and its length.
local function varint(n)
    if n < 16384 then return char(n % 128 + 128, floor(n / 128)), 2 end
    if n < 2097152 then
        return char(n % 128 + 128, floor(n / 128) % 128 + 128, floor(n / 16384)), 3
    end
    local t, k = {}, 0
    repeat
        local b = n % 128
        n = floor(n / 128)
        if n > 0 then b = b + 128 end
        k = k + 1
        t[k] = b
    until n == 0
    return char(unpack(t, 1, k)), k
end

-- Little-endian two's complement, 2, 4 or 8 bytes as one piece. n may be
-- negative: Lua's % yields the unsigned byte and floor division
-- sign-extends through the rest.
local function le(n, k)
    local b1 = n % 256
    n = floor(n / 256)
    if k == 2 then return char(b1, n % 256) end
    local b2 = n % 256
    n = floor(n / 256)
    local b3 = n % 256
    n = floor(n / 256)
    if k == 4 then return char(b1, b2, b3, n % 256) end
    local b4 = n % 256
    n = floor(n / 256)
    local b5 = n % 256
    n = floor(n / 256)
    local b6 = n % 256
    n = floor(n / 256)
    local b7 = n % 256
    return char(b1, b2, b3, b4, b5, b6, b7, floor(n / 256) % 256)
end

-- One byte, the writer's commonest piece.
local function byte1(self, b)
    local n = self.n + 1
    if n > BLOCK then n = join(self) end
    self.n = n
    self.buf[n] = CH[b]
    self.len = self.len + 1
    return self
end

function Writer:Len()
    return self.len
end

function Writer:Mark()
    return self.len
end

-- Back to the mark, a length: in buf, the pieces after it are let go; in
-- what was joined, that is cut there and kept as the one string.
function Writer:Restore(mark)
    assert(type(mark) == "number" and mark >= 0 and mark <= self.len, "Restore takes what Mark returned")
    if mark < self.base then
        local done = self.done
        local kept = concat(done, "", 1, self.k):sub(1, mark)
        for i = 2, self.k do done[i] = nil end
        done[1], self.k, self.base, self.n = kept, 1, mark, 0
    else
        local buf, n, at = self.buf, self.n, self.len
        while at > mark do
            at = at - #buf[n]
            n = n - 1
        end
        assert(at == mark, "Restore takes what Mark returned")
        self.n = n
    end
    self.len = mark
    return self
end

function Writer:U(n)
    n = floor(n)
    assert(n >= 0 and n <= self.umax, "unsigned integer out of range")
    if n < 128 then return byte1(self, n) end
    put(self, varint(n))
    return self
end

function Writer:I(n)
    n = floor(n)
    assert(n >= self.imin and n <= self.imax, "signed integer out of range")
    n = n >= 0 and (2 * n) or (-2 * n - 1)
    if n < 128 then return byte1(self, n) end
    put(self, varint(n))
    return self
end

function Writer:True()
    return byte1(self, 1)
end

function Writer:False()
    return byte1(self, 0)
end

function Writer:U8(n)
    n = floor(n)
    assert(n >= 0 and n <= 255, "u8 out of range")
    return byte1(self, n)
end

function Writer:I8(n)
    n = floor(n)
    assert(n >= -128 and n <= 127, "i8 out of range")
    return byte1(self, n % 256)
end

function Writer:U16(n)
    n = floor(n)
    assert(n >= 0 and n <= 65535, "u16 out of range")
    put(self, le(n, 2), 2)
    return self
end

function Writer:I16(n)
    n = floor(n)
    assert(n >= -32768 and n <= 32767, "i16 out of range")
    put(self, le(n, 2), 2)
    return self
end

function Writer:U32(n)
    n = floor(n)
    assert(n >= 0 and n <= 4294967295, "u32 out of range")
    put(self, le(n, 4), 4)
    return self
end

function Writer:I32(n)
    n = floor(n)
    assert(n >= -2147483648 and n <= 2147483647, "i32 out of range")
    put(self, le(n, 4), 4)
    return self
end

-- Lua 5.1 numbers are doubles: every integer in +-2^53 is exact, and 64-bit
-- patterns outside that cannot round-trip. The wire is still eight bytes.
function Writer:U64(n)
    n = floor(n)
    assert(n >= 0 and n <= 9007199254740992, "u64 out of range")
    put(self, le(n, 8), 8)
    return self
end

function Writer:I64(n)
    n = floor(n)
    assert(n >= -9007199254740992 and n <= 9007199254740992, "i64 out of range")
    put(self, le(n, 8), 8)
    return self
end

function Writer:Bytes(s)
    assert(type(s) == "string", "bytes must be a string")
    local n = #s
    if n < 128 then byte1(self, n) else put(self, varint(n)) end
    if n > 0 then put(self, s, n) end
    return self
end

function Writer:Raw(s)
    assert(type(s) == "string", "raw bytes must be a string")
    if #s > 0 then put(self, s, #s) end
    return self
end

-- The bytes so far. The writer is unchanged and can go on.
function Writer:Finish()
    local last, k = concat(self.buf, "", 1, self.n), self.k
    if k == 0 then return last end
    local done = self.done
    done[k + 1] = last
    local bytes = concat(done, "", 1, k + 1)
    done[k + 1] = nil
    return bytes
end
