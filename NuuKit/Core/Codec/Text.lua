local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Codec/Text.lua: a value encoded by a generated codec, as a line of
-- text a player can paste in game, in chat or on the web, and back.
--
--     nuu:  base64url( [container version: U] [schema: U] [deflate(body)] [Adler-32: U32] )
--
--     local text = Kit.Codec.ToText(GuideCodec.SCHEMA, body)
--     local schema, body = Kit.Codec.FromText(text)   -- or nil and what is wrong
--
-- The schema number names what the body is (the codec's SCHEMA: 1 is a
-- NuuRoad guide); the body is compressed with DEFLATE at level 9
-- (Core/Codec/LibDeflate.lua) and runs to the checksum, which covers
-- everything before it, so a damaged string is refused before it is
-- inflated. A body inflates to Codec.TEXT_MAX_BODY at most. Leading and
-- trailing whitespace, and whitespace inside the base64, are ignored. The
-- problems FromText answers are sentences for the player.
--
-- Compressing the largest guide takes longer than a frame: called from a job
-- (Core/Job.lua) both calls pause as they go, so the game does not stall.
local Codec = Kit.Codec or {}
Kit.Codec = Codec

Codec.TEXT_PREFIX = "nuu:"
Codec.TEXT_VERSION = 1
Codec.TEXT_MAX_BODY = 1048576

local PREFIX = Codec.TEXT_PREFIX

-- Whether text looks like a shared string (it may still be damaged).
function Codec.IsText(text)
    return type(text) == "string" and text:match("^%s*(....)") == PREFIX
end

function Codec.ToText(schema, body)
    local head = Codec.Writer():U(Codec.TEXT_VERSION):U(schema):Finish() .. Codec.Deflate(body)
    return PREFIX .. Codec.ToBase64(head .. Codec.Writer():U32(Codec.Adler32(head)):Finish())
end

function Codec.FromText(text)
    if not Codec.IsText(text) then return nil, "That is not a shared string: it starts with " .. PREFIX end
    local bytes = Codec.FromBase64(text:match("^%s*....(.*)$"))
    if not bytes or #bytes < 6 then return nil, "The string is damaged: some of it is missing or changed." end
    local head = bytes:sub(1, -5)
    if Codec.Reader(bytes:sub(-4)):U32() ~= Codec.Adler32(head) then
        return nil, "The string is damaged: some of it is missing or changed."
    end
    local r = Codec.Reader(head)
    local version, schema = r:U(), r:U()
    if not r:Ok() then return nil, "The string is damaged: some of it is missing or changed." end
    if version > Codec.TEXT_VERSION then return nil, "The string was made by a newer version." end
    if version ~= Codec.TEXT_VERSION then return nil, "The string is damaged: some of it is missing or changed." end
    local body, problem = Codec.Inflate(r:Rest(), Codec.TEXT_MAX_BODY)
    if not body then
        if problem == "too big" then return nil, "The string holds more than this version reads." end
        return nil, "The string is damaged: some of it is missing or changed."
    end
    return schema, body
end
