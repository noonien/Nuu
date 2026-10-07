-- What the codec and comms benches share: the kit loaded from NuuKit.toc,
-- the time and garbage of one call, a guide-sized body, and their tables.
-- Times are this machine's Lua, not the client's: compare runs on one
-- machine, before and after a change. /nuukit report times the codec in game.

local M = {}

-- Seconds a round runs for; a call is timed over the best of three rounds.
M.ROUND = 0.1

-- The kit as the client loads it, without the development-only files.
function M.LoadKit()
    local ns = {}
    for line in io.lines("NuuKit.toc") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file and file ~= "NuuKit.lua" and not file:match("^Dev/") then
            assert(loadfile(file))("NuuKit", ns)
        end
    end
    return ns.Kit
end

-- fn() run until a round fills M.ROUND: us per call (the best of three
-- rounds) and bytes allocated per call (the first, the collector stopped).
function M.Measure(fn)
    local reps, elapsed = 1, 0
    while true do
        local t0 = os.clock()
        for _ = 1, reps do fn() end
        elapsed = os.clock() - t0
        if elapsed >= M.ROUND / 4 then break end
        reps = reps * 4
    end
    reps = math.max(1, math.floor(reps * M.ROUND / elapsed))
    local us, bytes
    for round = 1, 3 do
        collectgarbage("collect")
        collectgarbage("collect")
        collectgarbage("stop")
        local m0, t0 = collectgarbage("count"), os.clock()
        for _ = 1, reps do fn() end
        local t, m1 = os.clock() - t0, collectgarbage("count")
        collectgarbage("restart")
        if round == 1 then bytes = (m1 - m0) * 1024 / reps end
        us = math.min(us or math.huge, t / reps * 1e6)
    end
    return { us = us, bytes = bytes }
end

-- A deterministic stand-in for a guide's codec bytes, `size` bytes or a
-- little over: per step a kind, quest, objective, map, coordinates, and
-- sometimes an NPC and a note. Real guides repeat more, so they deflate
-- smaller (NuuRoad/Tools/GuideSizes.lua).
local WORDS = {
    "Kill", "boars", "Collect", "Speak to", "Return to", "Bloodhoof", "Thunder Bluff", "quills", "the Barrens",
    "Take the flight", "Hearth", "Sell junk", "Train skills", "near the lake", "kodo", "plainstrider", "beaks",
    "Accept", "Turn in", "the cave", "north of", "Crossroads", "Camp Taurajo", "loot", "Grind to level",
}
function M.Body(Codec, size)
    local seed = 1
    local function rand(n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return math.floor(seed / 65536) % n
    end
    local w = Codec.Writer():U(1):Bytes("nuuroad:leveling:bench"):Bytes("Bench guide")
    while w:Len() < size do
        w:U(rand(12)):U(100 + rand(9000)):U(rand(3)):U(rand(40)):I(rand(10000)):I(rand(10000))
        if rand(4) == 0 then w:U(1000 + rand(20000)) end
        if rand(3) == 0 then
            local note = {}
            for i = 1, 2 + rand(5) do note[i] = WORDS[1 + rand(#WORDS)] end
            w:Bytes(table.concat(note, " "))
        end
    end
    return w:Finish()
end

-- Tables -----------------------------------------------------------------------

local COLUMNS = "%-44s %9s %10s %9s %11s %9s"

function M.Header(title)
    print("")
    print(COLUMNS:format(title, "in B", "us/call", "MB/s", "alloc B", "out B"))
end

-- One call measured: `size` is the bytes it reads (for MB/s), `out` what it
-- makes, either nil.
function M.Row(label, r, size, out)
    local rate = size and r.us > 0 and ("%.2f"):format(size / r.us) or "-"
    print(COLUMNS:format(label, size or "-", ("%.2f"):format(r.us), rate, ("%.0f"):format(r.bytes), out or "-"))
end

return M
