local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Codec/Adler32.lua: the Adler-32 checksum of a string (RFC 1950), as
-- a number. Plain arithmetic: Lua 5.1 has no bit operations, and this needs
-- none. Core/Codec/Text.lua ends every shared string with it, so text cut
-- short or changed on the way is caught before it is read. Pauses between
-- chunks, for a job (Core/Job.lua).
local Codec = Kit.Codec or {}
Kit.Codec = Codec

local byte = string.byte
local Pause = Kit.Job.Pause
local MOD = 65521
-- Bytes summed before taking the modulus; the sums stay far below 2^53.
local CHUNK = 4096

-- Sixteen bytes a step: b gains a for each of them and each byte for every
-- later one, so a step is two sums.
function Codec.Adler32(s)
    local a, b, n, i = 1, 0, #s, 1
    while i <= n do
        local last = i + CHUNK - 1
        if last > n then last = n end
        local j = i
        while j + 15 <= last do
            local x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16 = byte(s, j, j + 15)
            b = b + 16 * a + 16 * x1 + 15 * x2 + 14 * x3 + 13 * x4 + 12 * x5 + 11 * x6 + 10 * x7 + 9 * x8 + 8 * x9 + 7 * x10 + 6 * x11 + 5 * x12 + 4 * x13 + 3 * x14 + 2 * x15 + x16
            a = a + x1 + x2 + x3 + x4 + x5 + x6 + x7 + x8 + x9 + x10 + x11 + x12 + x13 + x14 + x15 + x16
            j = j + 16
        end
        for k = j, last do
            a = a + byte(s, k)
            b = b + a
        end
        a, b = a % MOD, b % MOD
        i = last + 1
        Pause()
    end
    return b * 65536 + a
end
