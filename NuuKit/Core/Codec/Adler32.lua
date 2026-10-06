local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Codec/Adler32.lua: the Adler-32 checksum of a string (RFC 1950), as
-- a number. Plain arithmetic: Lua 5.1 has no bit operations, and this needs
-- none. Core/Codec/Text.lua ends every shared string with it, so text cut
-- short or changed on the way is caught before it is read.
local Codec = Kit.Codec or {}
Kit.Codec = Codec

local byte = string.byte
local MOD = 65521
-- Bytes summed before taking the modulus; the sums stay far below 2^53.
local CHUNK = 4096

function Codec.Adler32(s)
    local a, b, n, i = 1, 0, #s, 1
    while i <= n do
        local last = i + CHUNK - 1
        if last > n then last = n end
        for j = i, last do
            a = a + byte(s, j)
            b = b + a
        end
        a, b = a % MOD, b % MOD
        i = last + 1
    end
    return b * 65536 + a
end
