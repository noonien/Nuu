local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Codec/Reader.lua: reads what Core/Codec/Writer.lua writes, field by
-- field, from a string of plain bytes.
--
--     local r = Kit.Codec.Reader(bytes)
--     local kind, name = r:U(), r:Bytes()
--     if not r:Ok() then return nil end
--
-- Field methods always return a value (0, false, ""); Ok() is false once a
-- read ran past the end or a field was malformed, and stays false. More() is
-- true while unread bytes remain; an unread tail is not an error. Fail()
-- marks the reader not ok, for a reader of a format on top of this one (a
-- value out of range); Left() is the bytes still unread, Rest() takes them.
--
-- A varint takes at most the groups the limits allow (Codec.LIMITS, or the
-- limits given) and must be as short as it can be.
local Codec = Kit.Codec or {}
Kit.Codec = Codec

local Reader = {}
Reader.__index = Reader
Codec.ReaderMethods = Reader

local byte, sub = string.byte, string.sub

-- Minimum value of an N-group varint; a smaller one is overlong.
local OVERLONG = { 0 }
for k = 2, 8 do OVERLONG[k] = 128 ^ (k - 1) end

function Codec.Reader(s, limits)
    limits = limits or Codec.LIMITS
    return setmetatable({ s = s, pos = 1, len = #s, err = false, umax = limits.umax, groups = limits.groups },
        Reader)
end

local function varint(self)
    local s, pos, len = self.s, self.pos, self.len
    if pos > len then return nil end
    local b = byte(s, pos)
    if b < 128 then
        self.pos = pos + 1
        return b
    end
    local n, groups, mul = b % 128, 1, 128
    pos = pos + 1
    while true do
        if pos > len then return nil end
        b = byte(s, pos)
        pos = pos + 1
        groups = groups + 1
        if groups > self.groups then return nil end
        n = n + (b % 128) * mul
        if b < 128 then break end
        mul = mul * 128
    end
    self.pos = pos
    if n > self.umax or n < OVERLONG[groups] then return nil end
    return n
end

-- Little-endian unsigned of 2 or 4 bytes, nil past the end.
local function le16(self)
    local pos = self.pos
    if pos + 1 > self.len then return nil end
    local a, b = byte(self.s, pos, pos + 1)
    self.pos = pos + 2
    return a + b * 256
end

local function le32(self)
    local pos = self.pos
    if pos + 3 > self.len then return nil end
    local a, b, c, d = byte(self.s, pos, pos + 3)
    self.pos = pos + 4
    return a + b * 256 + c * 65536 + d * 16777216
end

function Reader:Ok()
    return not self.err
end

function Reader:More()
    return not self.err and self.pos <= self.len
end

function Reader:Fail()
    self.err = true
end

function Reader:Left()
    if self.err then return 0 end
    return self.len - self.pos + 1
end

function Reader:Rest()
    if self.err then return "" end
    local rest = sub(self.s, self.pos)
    self.pos = self.len + 1
    return rest
end

function Reader:U()
    if self.err then return 0 end
    local n = varint(self)
    if n == nil then self.err = true return 0 end
    return n
end

function Reader:I()
    if self.err then return 0 end
    local z = varint(self)
    if z == nil then self.err = true return 0 end
    if z % 2 == 0 then return z / 2 end
    return -(z + 1) / 2
end

-- true = 0x01, false = 0x00. Any other byte, or no byte, is a failed read.
function Reader:Bool()
    if self.err then return false end
    local pos = self.pos
    local b = pos <= self.len and byte(self.s, pos)
    self.pos = pos + 1
    if b == 1 then return true end
    if b ~= 0 then self.err = true end
    return false
end

function Reader:U8()
    if self.err then return 0 end
    local pos = self.pos
    if pos > self.len then self.err = true return 0 end
    self.pos = pos + 1
    return byte(self.s, pos)
end

function Reader:I8()
    local n = self:U8()
    if n >= 128 then return n - 256 end
    return n
end

function Reader:U16()
    if self.err then return 0 end
    local n = le16(self)
    if n == nil then self.err = true return 0 end
    return n
end

function Reader:I16()
    local n = self:U16()
    if n >= 32768 then return n - 65536 end
    return n
end

function Reader:U32()
    if self.err then return 0 end
    local n = le32(self)
    if n == nil then self.err = true return 0 end
    return n
end

function Reader:I32()
    local n = self:U32()
    if n >= 2147483648 then return n - 4294967296 end
    return n
end

function Reader:U64()
    if self.err then return 0 end
    local lo, hi = le32(self), nil
    if lo then hi = le32(self) end
    if hi == nil then self.err = true return 0 end
    -- 2^53 is Lua's last consecutive integer; hi==2097152 is that value iff lo==0.
    if hi > 2097152 or (hi == 2097152 and lo ~= 0) then self.err = true return 0 end
    return lo + hi * 4294967296
end

function Reader:I64()
    if self.err then return 0 end
    local lo, hi = le32(self), nil
    if lo then hi = le32(self) end
    if hi == nil then self.err = true return 0 end
    if hi < 2147483648 then
        if hi > 2097152 or (hi == 2097152 and lo ~= 0) then self.err = true return 0 end
        return lo + hi * 4294967296
    end
    -- Two's complement below -2^53 (hi of -2^53 is 0xFFE00000 = 4292870144).
    if hi < 4292870144 then self.err = true return 0 end
    return (hi - 4294967296) * 4294967296 + lo
end

function Reader:Bytes()
    if self.err then return "" end
    local n = varint(self)
    if n == nil or self.pos + n - 1 > self.len then self.err = true return "" end
    local pos = self.pos
    self.pos = pos + n
    return sub(self.s, pos, pos + n - 1)
end
