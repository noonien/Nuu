local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Comms/Frame.lua: the wire format of Kit.NewComms. One addon message
-- is a frame: a version byte, then the fields a Core/Codec/Writer.lua writes,
-- COBS-encoded so the frame holds no NUL (addon messages cannot carry one).
-- Shared by every comms instance; it keeps no state between frames.
--
-- Wire: [version: u8] [COBS(fields)]. The version byte is raw (not a field,
-- not COBS'd) so a future encoding can still be identified. Byte 1 is the
-- addon's own messages; byte 2 (Comms.TRANSFER) is the kit's transfers
-- (Core/Comms/Transfer.lua), which Transport hands to them and never to the
-- addon's receivers.
--
--     local payload = Kit.Comms.Writer():U(MSG_HELLO):Bytes(name):Finish()
--     local r = Kit.Comms.Reader(payload)
--     local kind, name = r:U(), r:Bytes()
--     if not r:Ok() then return Kit.Comms.VIOLATION end
--
-- Writer is the codec's writer with the comms limits (U/I in four groups of
-- 7 bits). Len() is the frame's length; Finish() is the SendAddonMessage
-- payload, nil if the frame would exceed MAX_PAYLOAD, an error if no field
-- was written. FinishTransfer() is the same with the transfer byte. Reader
-- takes a frame apart: a frame that is not well-formed COBS reads as not ok
-- from its first field. The codec's reader does the rest: field methods
-- return 0, false or "" once a read fails, Ok() says so, and an unread tail
-- is not an error.
local Comms = Kit.Comms or {}
Kit.Comms = Comms
local Codec = Kit.Codec

-- First wire byte, 1..255. An encoding version, not a message-schema version.
Comms.VERSION = 1
Comms.TRANSFER = 2
-- The client's addon-message cap. A longer message is cut to it and still
-- reported sent (WoW: Forever 1.60.1, 2026-10-05), so the cap is enforced here.
Comms.MAX_PAYLOAD = 255
-- Version byte + a non-empty COBS frame (code + at least one data byte).
Comms.MIN_PAYLOAD = 3
-- The receiver signal for a malformed or abusive message. Its identity, not a
-- truthy return, is what counts, so ordinary return values stay out of it.
Comms.VIOLATION = {}

-- Four groups of 7 bits: every well-formed varint on this wire is encodable.
local LIMITS = { groups = 4, umax = 268435455, imin = -134217728, imax = 134217727 }
local VERSION, MIN_PAYLOAD, MAX_PAYLOAD = Comms.VERSION, Comms.MIN_PAYLOAD, Comms.MAX_PAYLOAD
local COBS_FULL_BLOCK = 0xFF
local COBS_MAX_RUN = COBS_FULL_BLOCK - 1

local byte, char, sub, find, floor, concat = string.byte, string.char, string.sub, string.find, math.floor, table.concat
local TRANSFER = Comms.TRANSFER
local VERSION_CH, TRANSFER_CH, FULL_CH = char(VERSION), char(TRANSFER), char(COBS_FULL_BLOCK)

--------------------------------------------------------------------------------
-- COBS. A run of up to 254 nonzero bytes follows a code byte of its length
-- + 1, and a NUL is implied after it unless it ends the frame. A 254-byte run
-- uses the full-block code and implies no NUL. With a body of at most 253
-- bytes there is no full block, so a frame is exactly the body + 2 bytes.
--------------------------------------------------------------------------------

local function cobsEncode(s)
    local out, k, i, n = {}, 0, 1, #s
    local endsFull = false
    while true do
        local zero = find(s, "\0", i, true)
        local stop = zero and zero - 1 or n
        while stop - i + 1 >= COBS_MAX_RUN do
            out[k + 1], out[k + 2] = FULL_CH, sub(s, i, i + COBS_MAX_RUN - 1)
            k = k + 2
            i = i + COBS_MAX_RUN
            endsFull = true
        end
        if not zero then
            -- A body ending on a full block needs no closing code.
            if stop >= i or not endsFull then
                out[k + 1], out[k + 2] = char(stop - i + 2), sub(s, i, stop)
                k = k + 2
            end
            break
        end
        out[k + 1], out[k + 2] = char(stop - i + 2), sub(s, i, stop)
        k = k + 2
        i = zero + 1
        endsFull = false
    end
    return concat(out, "", 1, k)
end

-- The body of data[read..n], or nil on a 0 code or a block cut short.
local function cobsDecode(data, read, n)
    local t, k = {}, 0
    while read <= n do
        local code = byte(data, read)
        if code == 0 then return nil end
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
    return concat(t, "", 1, k)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- The codec's methods copied in, not inherited, so a field is one lookup.
local FrameWriter = {}
for name, method in pairs(Codec.WriterMethods) do FrameWriter[name] = method end
FrameWriter.__index = FrameWriter

function Comms.Writer()
    return Codec.Writer(LIMITS, FrameWriter)
end

-- The frame's length: version + COBS code + the body, and a code for each
-- full block past the first 254 bytes. Exact up to the cap; above it, never
-- less than the frame Finish would make. Cram against MAX_PAYLOAD.
function FrameWriter:Len()
    local n = self.len
    if n <= COBS_MAX_RUN then return n + 2 end
    return n + 2 + floor((n - 1) / COBS_MAX_RUN)
end

local function finish(self, first)
    local n = self.len
    if n + 2 > MAX_PAYLOAD then return nil end
    assert(n >= 1, "comms payload is empty")
    return first .. cobsEncode(Codec.WriterMethods.Finish(self))
end

function FrameWriter:Finish()
    return finish(self, VERSION_CH)
end

function FrameWriter:FinishTransfer()
    return finish(self, TRANSFER_CH)
end

-- Wire header. nil = not this encoding (drop + session mute). VIOLATION = empty
-- COBS. true = ok, for a message or a transfer (byte(s, 1) says which).
-- Transport calls this once before receivers; features do not.
function Comms.Accept(s)
    local first = byte(s, 1)
    if first ~= VERSION and first ~= TRANSFER then return nil end
    if #s < MIN_PAYLOAD then return Comms.VIOLATION end
    return true
end

function Comms.Reader(s)
    local body
    if #s >= MIN_PAYLOAD and not find(s, "\0", 1, true) then body = cobsDecode(s, 2, #s) end
    local reader = Codec.Reader(body or "", LIMITS)
    if not body then reader:Fail() end
    return reader
end
