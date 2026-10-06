local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Codec/Base64.lua: bytes as text and back, in base64url (RFC 4648
-- section 5: A-Z a-z 0-9 - _) with no padding. Those characters pass
-- through an edit box (no `|`), a URL, a chat code block and a forum post.
--
--     local text = Kit.Codec.ToBase64(bytes)
--     local bytes = Kit.Codec.FromBase64(text)   -- nil if it is not base64url
--
-- FromBase64 ignores whitespace, so text a chat or a forum wrapped onto
-- several lines still reads. It takes only the canonical form: no padding,
-- no other characters, and no stray bits in the last character. Both pause
-- every 4095 bytes, for a job (Core/Job.lua).
local Codec = Kit.Codec or {}
Kit.Codec = Codec

local byte, char, sub, floor, concat = string.byte, string.char, string.sub, math.floor, table.concat
local Pause = Kit.Job.Pause

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local ENC, DEC = {}, {}
for i = 0, 63 do
    ENC[i] = sub(ALPHABET, i + 1, i + 1)
    DEC[byte(ALPHABET, i + 1)] = i
end
-- Two characters for every 12 bits, so three bytes take two lookups.
local PAIR = {}
for i = 0, 4095 do PAIR[i] = ENC[floor(i / 64)] .. ENC[i % 64] end

function Codec.ToBase64(s)
    local out, k, n, i = {}, 0, #s, 1
    while i + 2 <= n do
        local a, b, c = byte(s, i, i + 2)
        local v = a * 65536 + b * 256 + c
        out[k + 1] = PAIR[floor(v / 4096)]
        out[k + 2] = PAIR[v % 4096]
        k = k + 2
        i = i + 3
        if i % 4095 == 1 then Pause() end
    end
    local left = n - i + 1
    if left == 1 then
        k = k + 1
        out[k] = PAIR[byte(s, i) * 16]
    elseif left == 2 then
        local a, b = byte(s, i, i + 1)
        local v = (a * 256 + b) * 4
        out[k + 1] = ENC[floor(v / 4096)]
        out[k + 2] = PAIR[v % 4096]
        k = k + 2
    end
    return concat(out, "", 1, k)
end

function Codec.FromBase64(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s+", "")
    if text:find("[^%w%-_]") then return nil end
    local n = #text
    if n % 4 == 1 then return nil end
    local out, k, i = {}, 0, 1
    while i + 3 <= n do
        local a, b, c, d = byte(text, i, i + 3)
        local v = DEC[a] * 262144 + DEC[b] * 4096 + DEC[c] * 64 + DEC[d]
        k = k + 1
        out[k] = char(floor(v / 65536), floor(v / 256) % 256, v % 256)
        i = i + 4
        if i % 5460 == 1 then Pause() end
    end
    local left = n - i + 1
    if left == 2 then
        local v = DEC[byte(text, i)] * 64 + DEC[byte(text, i + 1)]
        if v % 16 ~= 0 then return nil end
        k = k + 1
        out[k] = char(v / 16)
    elseif left == 3 then
        local a, b, c = byte(text, i, i + 2)
        local v = DEC[a] * 4096 + DEC[b] * 64 + DEC[c]
        if v % 4 ~= 0 then return nil end
        k = k + 1
        out[k] = char(floor(v / 1024), floor(v / 4) % 256)
    end
    return concat(out, "", 1, k)
end
