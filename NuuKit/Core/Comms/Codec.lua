local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Comms/Codec.lua: the wire format of Kit.NewComms, a bytestream writer
-- and reader with COBS merged into both. Shared by every comms instance; it
-- keeps no state between frames. From Sonar's Comms/Codec.lua.
--
-- Wire: [version: u8] [COBS(fields)...]. The version byte is raw (not a
-- field, not COBS'd) so a future encoding can still be identified. Addon
-- messages cannot carry NUL, which is what COBS takes out.
--
-- Writer:U/I/True/False/U8..I64/Bytes write COBS blocks as they go; Finish()
-- is the SendAddonMessage payload (nil if the frame would exceed MAX_PAYLOAD,
-- an error if the COBS body is empty). Reader peels COBS as it reads fields.
-- Field methods always return a value (0, false, ""); Ok() is false once a
-- read ran past the buffer or a field was malformed. More() is true while
-- unread bytes remain. An unread tail is not an error.
--
-- U/I are LEB128 with at most four groups of 7 bits. True/False are 0x01/0x00.
-- U8/I8 to U64/I64 are little-endian two's-complement bytes.
--
--     local payload = Kit.Comms.Writer():U(MSG_HELLO):Bytes(name):Finish()
--     local r = Kit.Comms.Reader(payload)
--     local kind, name = r:U(), r:Bytes()
--     if not r:Ok() then return Kit.Comms.VIOLATION end
--
-- Lua 5.1 has no byte buffer. The writer stores interned 1-byte strings and
-- nonzero runs as slots, with a placeholder for the open COBS code byte, and
-- concatenates once at Finish. Incoming strings are split on NULs with
-- string.find and copied with string.sub (both C), never walked in Lua.
local Comms = Kit.Comms or {}
Kit.Comms = Comms

-- First wire byte, 1..255. An encoding version, not a message-schema version.
Comms.VERSION = 1
-- The client's addon-message cap. A longer message is cut to it and still
-- reported sent (WoW: Forever 1.60.1, 2026-10-05), so the cap is enforced here.
Comms.MAX_PAYLOAD = 255
-- Version byte + a non-empty COBS frame (code + at least one data byte).
Comms.MIN_PAYLOAD = 3
-- The receiver signal for a malformed or abusive message. Its identity, not a
-- truthy return, is what counts, so ordinary return values stay out of it.
Comms.VIOLATION = {}

local Reader = {}
local Writer = {}

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local CH, I_MAX, I_MIN, U_MAX, VARINT_GROUPS, VERSION_CH, _cobsByte, _cobsTake, _putByte
local _hasMore, _putLE, _putNonzero, _putVarint, _putZero, _rawTake, _readLE
local _readVarint, _readVarintCobs, _readVarintRun, _startRun, byte, concat, find, floor
local VERSION, MIN_PAYLOAD = Comms.VERSION, Comms.MIN_PAYLOAD

function Comms.Writer()
    return setmetatable({
        buf = { VERSION_CH, false }, n = 2, committed = 1, runLen = 0,
        open = true, codeSlot = 2,
    }, Writer)
end

-- Encoded size so far: version byte + COBS, including the open run's code byte.
-- Cram against MAX_PAYLOAD.
function Writer:Len()
    if self.open then return self.committed + 1 + self.runLen end
    return self.committed
end

-- Cursor. Restore(mark) drops everything written after that call.
function Writer:Mark()
    return {
        slot = self.n, -- Last occupied buffer slot; later slots are discarded on restore.
        len = self:Len(), -- Encoded frame length at this point, including version and an open COBS code byte.
        runLen = self.runLen, -- Number of nonzero data bytes in the current open COBS run.
        codeSlot = self.open and self.codeSlot or nil, -- Open run's code placeholder; nil means the run was closed.
    }
end

function Writer:Restore(mark)
    local slot, len, runLen, codeSlot = mark.slot, mark.len, mark.runLen, mark.codeSlot
    local open = codeSlot ~= nil
    self.n, self.runLen = slot, runLen
    self.committed = len - (open and runLen + 1 or 0)
    self.open, self.codeSlot = open, codeSlot or 0
    if open then self.buf[codeSlot] = false end
    return self
end

function Writer:U(n)
    n = floor(n)
    assert(n >= 0 and n <= U_MAX, "unsigned integer out of range")
    if n < 128 then
        _putByte(self, n)
        return self
    end
    _putVarint(self, n)
    return self
end

function Writer:I(n)
    n = floor(n)
    assert(n >= I_MIN and n <= I_MAX, "signed integer out of range")
    n = n >= 0 and (2 * n) or (-2 * n - 1)
    if n < 128 then
        _putByte(self, n)
        return self
    end
    _putVarint(self, n)
    return self
end

function Writer:True()
    _putByte(self, 1)
    return self
end

function Writer:False()
    _putZero(self)
    return self
end

function Writer:U8(n)
    n = floor(n)
    assert(n >= 0 and n <= 255, "u8 out of range")
    _putByte(self, n)
    return self
end

function Writer:I8(n)
    n = floor(n)
    assert(n >= -128 and n <= 127, "i8 out of range")
    _putByte(self, n % 256)
    return self
end

function Writer:U16(n)
    n = floor(n)
    assert(n >= 0 and n <= 65535, "u16 out of range")
    _putLE(self, n, 2)
    return self
end

function Writer:I16(n)
    n = floor(n)
    assert(n >= -32768 and n <= 32767, "i16 out of range")
    _putLE(self, n, 2)
    return self
end

function Writer:U32(n)
    n = floor(n)
    assert(n >= 0 and n <= 4294967295, "u32 out of range")
    _putLE(self, n, 4)
    return self
end

function Writer:I32(n)
    n = floor(n)
    assert(n >= -2147483648 and n <= 2147483647, "i32 out of range")
    _putLE(self, n, 4)
    return self
end

-- Lua 5.1 numbers are doubles: every integer in +-2^53 is exact, and 64-bit
-- patterns outside that cannot round-trip. The wire is still eight bytes.
function Writer:U64(n)
    n = floor(n)
    assert(n >= 0 and n <= 9007199254740992, "u64 out of range")
    _putLE(self, n, 8)
    return self
end

function Writer:I64(n)
    n = floor(n)
    assert(n >= -9007199254740992 and n <= 9007199254740992, "i64 out of range")
    _putLE(self, n, 8)
    return self
end

function Writer:Bytes(s)
    local n = #s
    if n < 128 then _putByte(self, n) else _putVarint(self, n) end
    local i = 1
    while i <= n do
        local z = find(s, "\0", i, true)
        if not z then
            _putNonzero(self, s, i, n)
            break
        end
        if z > i then _putNonzero(self, s, i, z - 1) end
        _putZero(self)
        i = z + 1
    end
    return self
end

function Writer:Finish()
    local total = self:Len()
    if total > Comms.MAX_PAYLOAD then return nil end
    assert(total >= MIN_PAYLOAD, "comms payload is empty")
    if not self.open then
        return concat(self.buf, "", 1, self.n)
    end
    local slot = self.codeSlot
    self.buf[slot] = CH[self.runLen + 1]
    local s = concat(self.buf, "", 1, self.n)
    self.buf[slot] = false
    return s
end

-- Wire header. nil = not this encoding (drop + session mute). VIOLATION = empty
-- COBS. true = ok. Transport calls this once before receivers; features do not.
function Comms.Accept(s)
    if byte(s, 1) ~= VERSION then return nil end
    if #s < MIN_PAYLOAD then return Comms.VIOLATION end
    return true
end

function Comms.Reader(s)
    local len = #s
    return setmetatable({
        s = s, pos = 2, len = len, cobs = true,
        blockLeft = 0, pendingZero = false,
        err = len < MIN_PAYLOAD or find(s, "\0", 1, true) and true or false,
    }, Reader)
end

-- False once a field ran past the buffer or failed to decode. Sticky.
function Reader:Ok()
    return not self.err
end

-- Unread logical bytes remain. False after a failed read; leftover tail is ok.
function Reader:More()
    return _hasMore(self)
end

function Reader:U()
    if self.err then return 0 end
    local n
    if not self.cobs then
        n = _readVarint(self, U_MAX)
    elseif self.blockLeft > 0 then
        n = _readVarintRun(self, U_MAX)
    else
        n = _readVarintCobs(self, U_MAX)
    end
    if n == nil then self.err = true return 0 end
    return n
end

function Reader:I()
    if self.err then return 0 end
    local z
    if not self.cobs then
        z = _readVarint(self, U_MAX)
    elseif self.blockLeft > 0 then
        z = _readVarintRun(self, U_MAX)
    else
        z = _readVarintCobs(self, U_MAX)
    end
    if z == nil then self.err = true return 0 end
    if z % 2 == 0 then return z / 2 end
    return -(z + 1) / 2
end

-- true = 0x01, false = 0x00. Any other byte, or no byte, is a failed read.
function Reader:Bool()
    if self.err then return false end
    local b
    if not self.cobs then
        if self.pos > self.len then self.err = true return false end
        b = byte(self.s, self.pos)
        self.pos = self.pos + 1
    else
        b = _cobsByte(self)
    end
    if b == 1 then return true end
    if b == 0 then return false end
    self.err = true
    return false
end

function Reader:U8()
    if self.err then return 0 end
    local b = _cobsByte(self)
    if b == nil then self.err = true return 0 end
    return b
end

function Reader:I8()
    if self.err then return 0 end
    local b = _cobsByte(self)
    if b == nil then self.err = true return 0 end
    if b >= 128 then return b - 256 end
    return b
end

function Reader:U16()
    if self.err then return 0 end
    local n = _readLE(self, 2)
    if n == nil then self.err = true return 0 end
    return n
end

function Reader:I16()
    if self.err then return 0 end
    local n = _readLE(self, 2)
    if n == nil then self.err = true return 0 end
    if n >= 32768 then return n - 65536 end
    return n
end

function Reader:U32()
    if self.err then return 0 end
    local n = _readLE(self, 4)
    if n == nil then self.err = true return 0 end
    return n
end

function Reader:I32()
    if self.err then return 0 end
    local n = _readLE(self, 4)
    if n == nil then self.err = true return 0 end
    if n >= 2147483648 then return n - 4294967296 end
    return n
end

function Reader:U64()
    if self.err then return 0 end
    local lo = _readLE(self, 4)
    if lo == nil then self.err = true return 0 end
    local hi = _readLE(self, 4)
    if hi == nil then self.err = true return 0 end
    -- 2^53 is Lua's last consecutive integer; hi==2097152 is that value iff lo==0.
    if hi > 2097152 or (hi == 2097152 and lo ~= 0) then self.err = true return 0 end
    return lo + hi * 4294967296
end

function Reader:I64()
    if self.err then return 0 end
    local lo = _readLE(self, 4)
    if lo == nil then self.err = true return 0 end
    local hi = _readLE(self, 4)
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
    local n = self:U()
    if self.err then return "" end
    local s
    if not self.cobs then
        s = _rawTake(self, n)
    else
        s = _cobsTake(self, n)
    end
    if s == nil then self.err = true return "" end
    return s
end

-- Four groups of 7 bits: every well-formed varint on this wire is encodable.
VARINT_GROUPS = 4
U_MAX = 268435455
I_MIN, I_MAX = -134217728, 134217727
local COBS_FULL_BLOCK = 0xFF
local COBS_MAX_RUN = COBS_FULL_BLOCK - 1
-- Minimum legal value for a N-byte varint; shorter would be overlong.
local OVERLONG = { 0, 128, 16384, 2097152 }

local char, sub
char, concat, find, sub, byte = string.char, table.concat, string.find, string.sub, string.byte
floor = math.floor

-- Interned 0..COBS_FULL_BLOCK. Built once; writes are pointer stores.
CH = {}
for i = 0, COBS_FULL_BLOCK do CH[i] = char(i) end
VERSION_CH = CH[VERSION]

local decParts, decN = {}, 0

--------------------------------------------------------------------------------
-- Writer. Always COBS. Finish() is the wire frame.
--------------------------------------------------------------------------------

Writer.__index = Writer

_putVarint = function(self, n)
    local runLen = self.runLen
    if self.open and runLen <= COBS_MAX_RUN - VARINT_GROUPS then
        local buf, i = self.buf, self.n
        repeat
            local b = n % 128
            n = floor(n / 128)
            if n > 0 then b = b + 128 end
            i = i + 1
            buf[i] = CH[b]
            runLen = runLen + 1
        until n == 0
        self.n, self.runLen = i, runLen
        if runLen == COBS_MAX_RUN then
            buf[self.codeSlot] = CH[COBS_FULL_BLOCK]
            self.committed = self.committed + COBS_FULL_BLOCK
            self.open = false
            self.runLen = 0
        end
        return
    end
    repeat
        local b = n % 128
        n = floor(n / 128)
        if n > 0 then b = b + 128 end
        _putByte(self, b)
    until n == 0
end

_putByte = function(self, b)
    if b == 0 then
        _putZero(self)
    else
        if not self.open then _startRun(self) end
        local i = self.n + 1
        self.n = i
        self.buf[i] = CH[b]
        self.runLen = self.runLen + 1
        if self.runLen == COBS_MAX_RUN then
            self.buf[self.codeSlot] = CH[COBS_FULL_BLOCK]
            self.committed = self.committed + COBS_FULL_BLOCK
            self.open = false
            self.runLen = 0
        end
    end
end

-- Little-endian two's complement. n may be negative; Lua's % yields the
-- unsigned byte, floor-division sign-extends through the remaining bytes.
_putLE = function(self, n, k)
    for _ = 1, k do
        _putByte(self, n % 256)
        n = floor(n / 256)
    end
end

-- Append nonzero bytes s[a..b]. Full runs flush with no implied NUL.
_putNonzero = function(self, s, a, b)
    local take = b - a + 1
    local room = COBS_MAX_RUN - self.runLen
    if self.open and take <= room then
        local i = self.n + 1
        self.n = i
        if take == 1 then
            self.buf[i] = CH[byte(s, a)]
        elseif a == 1 and b == #s then
            self.buf[i] = s
        else
            self.buf[i] = sub(s, a, b)
        end
        self.runLen = self.runLen + take
        if self.runLen == COBS_MAX_RUN then
            self.buf[self.codeSlot] = CH[COBS_FULL_BLOCK]
            self.committed = self.committed + COBS_FULL_BLOCK
            self.open = false
            self.runLen = 0
        end
        return
    end
    while a <= b do
        if not self.open then _startRun(self) end
        local room = COBS_MAX_RUN - self.runLen
        local take = b - a + 1
        if take > room then take = room end
        local i = self.n + 1
        self.n = i
        if take == 1 then
            self.buf[i] = CH[byte(s, a)]
        else
            self.buf[i] = sub(s, a, a + take - 1)
        end
        self.runLen = self.runLen + take
        a = a + take
        if self.runLen == COBS_MAX_RUN then
            self.buf[self.codeSlot] = CH[COBS_FULL_BLOCK]
            self.committed = self.committed + COBS_FULL_BLOCK
            self.open = false
            self.runLen = 0
        end
    end
end

-- Close the open run with an implied NUL (code = runLen+1) and start the next.
_putZero = function(self)
    if not self.open then _startRun(self) end
    self.buf[self.codeSlot] = CH[self.runLen + 1]
    self.committed = self.committed + 1 + self.runLen
    self.open = false
    self.runLen = 0
    _startRun(self)
end

_startRun = function(self)
    local i = self.n + 1
    self.n = i
    self.codeSlot = i
    self.buf[i] = false
    self.open = true
    self.runLen = 0
end

--------------------------------------------------------------------------------
-- Reader. Input is always a COBS frame and decoded bytes are pulled as fields
-- are read (merged), with no separate decode pass. Truncation or a bad field
-- sets err and the public method returns 0 / false / "". Unread tail is not
-- an error; More() reports it.
--------------------------------------------------------------------------------

Reader.__index = Reader

_readLE = function(self, k)
    local n, mul = 0, 1
    for _ = 1, k do
        local b = _cobsByte(self)
        if b == nil then return nil end
        n = n + b * mul
        mul = mul * 256
    end
    return n
end

_hasMore = function(self)
    if self.err then return false end
    if self.pendingZero or self.blockLeft > 0 then return true end
    if not self.cobs then return self.pos <= self.len end
    local pos, len = self.pos, self.len
    while pos <= len do
        local code = byte(self.s, pos)
        if not code or code == 0 then return false end
        local last = pos + code - 1
        if last > len then return true end
        if code > 1 then return true end
        pos = last + 1
        if code ~= COBS_FULL_BLOCK and pos <= len then return true end
    end
    return false
end

_readVarintCobs = function(self, max)
    local b = _cobsByte(self)
    if b == nil then return nil end
    if b < 128 then return b end
    local n, bytes, mul = b % 128, 1, 128
    while true do
        if self.cobs and self.blockLeft > 0 then
            local pos = self.pos
            b = byte(self.s, pos)
            if not b or b == 0 then self.err = true return nil end
            self.pos = pos + 1
            self.blockLeft = self.blockLeft - 1
        elseif not self.cobs then
            local pos = self.pos
            if pos > self.len then return nil end
            b = byte(self.s, pos)
            self.pos = pos + 1
        else
            b = _cobsByte(self)
        end
        if b == nil then return nil end
        bytes = bytes + 1
        if bytes > VARINT_GROUPS then return nil end
        n = n + (b % 128) * mul
        if b < 128 then break end
        mul = mul * 128
    end
    if n > max then return nil end
    if n < OVERLONG[bytes] then return nil end
    return n
end

-- Nonzero COBS run: those bytes are already a raw window. Read as such
-- without copying the rest of the packet (keeps prefix-only cheap).
_readVarintRun = function(self, max)
    local pos = self.pos
    local b = byte(self.s, pos)
    if b < 128 then
        self.pos = pos + 1
        self.blockLeft = self.blockLeft - 1
        return b
    end
    local cap = self.pos + self.blockLeft - 1
    local save = self.len
    self.len = cap
    local n = _readVarint(self, max)
    self.len = save
    -- _readVarint commits pos after a terminated varint before rejecting an
    -- overlong or out-of-range value. Keep the COBS cursor in sync on those
    -- failures too, or a later read can consume framing bytes as payload.
    self.blockLeft = cap - self.pos + 1
    return n
end

_readVarint = function(self, max)
    local s, pos, len = self.s, self.pos, self.len
    if pos > len then return nil end
    local b = byte(s, pos)
    if b < 128 then
        self.pos = pos + 1
        return b
    end
    local n, bytes, mul = b % 128, 1, 128
    pos = pos + 1
    while true do
        if pos > len then return nil end
        b = byte(s, pos)
        pos = pos + 1
        bytes = bytes + 1
        if bytes > VARINT_GROUPS then
            self.pos = pos
            return nil
        end
        n = n + (b % 128) * mul
        if b < 128 then break end
        mul = mul * 128
    end
    self.pos = pos
    if n > max then return nil end
    if n < OVERLONG[bytes] then return nil end
    return n
end

local _loadBlock
_cobsByte = function(self)
    if self.err then return nil end
    if not self.cobs then
        if self.pos > self.len then return nil end
        local b = byte(self.s, self.pos)
        self.pos = self.pos + 1
        return b
    end
    while true do
        if self.blockLeft > 0 then
            local pos = self.pos
            local b = byte(self.s, pos)
            if not b or b == 0 then self.err = true return nil end
            self.pos = pos + 1
            self.blockLeft = self.blockLeft - 1
            return b
        end
        if self.pendingZero then
            self.pendingZero = false
            return 0
        end
        if not _loadBlock(self) then return nil end
        if not self.cobs then
            if self.pos > self.len then return nil end
            local b = byte(self.s, self.pos)
            self.pos = self.pos + 1
            return b
        end
    end
end

_loadBlock = function(self)
    if self.err then return false end
    local pos, len = self.pos, self.len
    if pos > len then return false end
    local code = byte(self.s, pos)
    if not code or code == 0 then self.err = true return false end
    pos = pos + 1
    local left = code - 1
    if pos + left - 1 > len then self.err = true return false end
    self.blockLeft = left
    self.pendingZero = (code ~= COBS_FULL_BLOCK) and (pos + left <= len)
    self.pos = pos
    -- Tail run to EOF: remaining packet bytes are the payload. No copy.
    if left > 0 and not self.pendingZero and pos + left - 1 == len then
        self.cobs = false
        self.blockLeft = 0
    end
    return true
end

local _flattenCobs
_cobsTake = function(self, n)
    if n == 0 then return "" end
    if not self.cobs then return _rawTake(self, n) end
    if self.pendingZero or self.blockLeft < n then
        if not _flattenCobs(self) then return nil end
        return _rawTake(self, n)
    end
    local a = self.pos
    local last = a + n - 1
    local piece = sub(self.s, a, last)
    if find(piece, "\0", 1, true) then self.err = true return nil end
    self.pos = last + 1
    self.blockLeft = self.blockLeft - n
    return piece
end

local _cobsRest
_flattenCobs = function(self)
    local all = _cobsRest(self)
    if not all then return false end
    self.s, self.pos, self.len = all, 1, #all
    self.cobs, self.blockLeft, self.pendingZero, self.err = false, 0, false, false
    return true
end

local _cobsDecodeRange
_cobsRest = function(self)
    if self.err then return nil end
    if self.blockLeft == 0 and not self.pendingZero then
        if self.pos > self.len then return "" end
        local tail = _cobsDecodeRange(self.s, self.pos, self.len)
        if not tail then self.err = true return nil end
        self.pos = self.len + 1
        return tail
    end
    local t, k = {}, 0
    if self.blockLeft > 0 then
        local a = self.pos
        local last = a + self.blockLeft - 1
        local piece = sub(self.s, a, last)
        if find(piece, "\0", 1, true) then self.err = true return nil end
        k = 1
        t[1] = piece
        self.pos = last + 1
        self.blockLeft = 0
    end
    if self.pendingZero then
        k = k + 1
        t[k] = "\0"
        self.pendingZero = false
    end
    if self.pos <= self.len then
        local tail = _cobsDecodeRange(self.s, self.pos, self.len)
        if not tail then self.err = true return nil end
        self.pos = self.len + 1
        k = k + 1
        t[k] = tail
    end
    if k == 0 then return "" end
    if k == 1 then return t[1] end
    return concat(t, "", 1, k)
end

--------------------------------------------------------------------------------
-- COBS decode of a whole remaining range. The encoder lives in Writer: there
-- is no matching _cobsEncode of a finished logical string. A 254-byte
-- nonzero run uses COBS_FULL_BLOCK and no inferred NUL; at EOF that block is
-- the whole frame (255 bytes). Other codes insert a NUL after the run unless
-- the run ends the packet.
--------------------------------------------------------------------------------

-- Block-aligned COBS decode of data[read..n]. nil on truncation or a 0 code.
_cobsDecodeRange = function(data, read, n)
    if read > n then return "" end
    local t = decParts
    local k = 0
    while read <= n do
        local code = byte(data, read)
        if not code or code == 0 then return nil end
        local last = read + code - 1
        if last > n then return nil end
        if code > 1 then
            k = k + 1
            t[k] = sub(data, read + 1, last)
        end
        read = last + 1
        if code ~= COBS_FULL_BLOCK and read <= n then
            k = k + 1
            t[k] = "\0"
        end
    end
    for j = k + 1, decN do t[j] = nil end
    decN = k
    if k == 0 then return "" end
    if k == 1 then return t[1] end
    return concat(t, "", 1, k)
end

_rawTake = function(self, n)
    if self.pos + n - 1 > self.len then return nil end
    local s = sub(self.s, self.pos, self.pos + n - 1)
    self.pos = self.pos + n
    return s
end
