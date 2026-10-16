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
-- every 1020 pieces or bytes, for a job (Core/Job.lua).
local Codec = Kit.Codec or {}
Kit.Codec = Codec

local byte, char, sub, find, floor, concat, unpack = string.byte, string.char, string.sub, string.find, math.floor,
    table.concat, unpack
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

-- Both directions keep at most BLOCK pieces or bytes in a table they reuse
-- and join them there, so the table stays small and a short string is the
-- one string. Even and a multiple of 3 (a group's two pieces, its three
-- bytes), so a group never straddles it; they pause there, for a job.
local BLOCK = 1020

function Codec.ToBase64(s)
    local out, buf, k, m, n, i = {}, {}, 0, 0, #s, 1
    while i + 2 <= n do
        local a, b, c = byte(s, i, i + 2)
        local v = a * 65536 + b * 256 + c
        buf[m + 1] = PAIR[floor(v / 4096)]
        buf[m + 2] = PAIR[v % 4096]
        m = m + 2
        i = i + 3
        if m == BLOCK then
            k = k + 1
            out[k] = concat(buf, "", 1, m)
            m = 0
            Pause()
        end
    end
    local left = n - i + 1
    if left == 1 then
        m = m + 1
        buf[m] = PAIR[byte(s, i) * 16]
    elseif left == 2 then
        local a, b = byte(s, i, i + 1)
        local v = (a * 256 + b) * 4
        buf[m + 1] = ENC[floor(v / 4096)]
        buf[m + 2] = PAIR[v % 4096]
        m = m + 2
    end
    if k == 0 then return concat(buf, "", 1, m) end
    if m > 0 then
        k = k + 1
        out[k] = concat(buf, "", 1, m)
    end
    return concat(out, "", 1, k)
end

-- Bytes as numbers, made a string by string.char.
function Codec.FromBase64(text)
    if type(text) ~= "string" then return nil end
    if find(text, "%s") then text = text:gsub("%s+", "") end
    if find(text, "[^%w%-_]") then return nil end
    local n = #text
    if n % 4 == 1 then return nil end
    local out, buf, k, m, i = {}, {}, 0, 0, 1
    while i + 3 <= n do
        local a, b, c, d = byte(text, i, i + 3)
        local v = DEC[a] * 262144 + DEC[b] * 4096 + DEC[c] * 64 + DEC[d]
        buf[m + 1], buf[m + 2], buf[m + 3] = floor(v / 65536), floor(v / 256) % 256, v % 256
        m = m + 3
        i = i + 4
        if m == BLOCK then
            k = k + 1
            out[k] = char(unpack(buf, 1, m))
            m = 0
            Pause()
        end
    end
    local left = n - i + 1
    if left == 2 then
        local v = DEC[byte(text, i)] * 64 + DEC[byte(text, i + 1)]
        if v % 16 ~= 0 then return nil end
        m = m + 1
        buf[m] = v / 16
    elseif left == 3 then
        local a, b, c = byte(text, i, i + 2)
        local v = DEC[a] * 4096 + DEC[b] * 64 + DEC[c]
        if v % 4 ~= 0 then return nil end
        buf[m + 1], buf[m + 2] = floor(v / 1024), floor(v / 4) % 256
        m = m + 2
    end
    if k == 0 then return char(unpack(buf, 1, m)) end
    if m > 0 then
        k = k + 1
        out[k] = char(unpack(buf, 1, m))
    end
    return concat(out, "", 1, k)
end
