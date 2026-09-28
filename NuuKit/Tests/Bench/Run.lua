-- Compares UI architectures on one sample screen: a title and Reset, three
-- toggles tied to settings, and 60 rows of name, count and a "+1" button.
-- From NuuKit/: nix-shell -p lua5_1 --run "lua Tests/Bench/Run.lua"
--
-- Per scenario: calls into the client's API (the stand-in counts them; in
-- game these dominate), Lua time (the architecture's own overhead, stand-in
-- included), and Lua memory allocated (garbage, with the collector stopped).

BENCH = "Tests/Bench/"
local Stand = dofile(BENCH .. "Stand.lua")
local C = dofile(BENCH .. "Common.lua")
local ITEMS = 60

local archs = {
    { key = "A", name = "A closures (today)", file = "A.lua" },
    { key = "B", name = "B shared methods", file = "B.lua" },
    { key = "B+pool", name = "B + pooling", file = "B.lua", opts = { pool = true } },
    { key = "C", name = "C props schema", file = "C.lua", base = "B.lua" },
    { key = "D", name = "D declarative", file = "D.lua", base = "B.lua" },
    { key = "E", name = "E widget objects", file = "E.lua" },
    { key = "K", name = "K real kit", file = "K.lua", screenFile = "A.lua", kit = true },
    { key = "T1", name = "T1 UI-Test1 as built", file = "T1.lua", screenFile = "B.lua", kit1 = true },
}
local only = arg and arg[1]
for index = #archs, 1, -1 do
    if only and archs[index].key ~= only then table.remove(archs, index) end
end
for _, arch in ipairs(archs) do arch.M = dofile(BENCH .. arch.file) end

local function fresh(arch)
    local M = arch.M
    local ui = M.NewUI(C.looks[1], arch.opts)
    local win = M.Window(ui, 420, 2400)
    local env = { ui = ui, win = win, db = {}, items = C.Items(ITEMS) }
    M.Screen(ui, win, env.db, env.items)
    M.Flush(ui)
    return env
end

-- Runs fn(i) reps times: µs, client calls and bytes allocated per run.
-- Calls and bytes come from the first round; time is the best of three.
local function measure(reps, fn)
    local out
    for round = 1, 3 do
        collectgarbage("collect")
        collectgarbage("collect")
        Stand.Reset()
        local objects = Stand.objects
        collectgarbage("stop")
        local m0, t0 = collectgarbage("count"), os.clock()
        for i = 1, reps do fn(i) end
        local t, m1 = os.clock() - t0, collectgarbage("count")
        collectgarbage("restart")
        if round == 1 then
            out = {
                us = t / reps * 1e6, calls = Stand.calls / reps, bytes = (m1 - m0) * 1024 / reps,
                objects = (Stand.objects - objects) / reps,
            }
        else
            out.us = math.min(out.us, t / reps * 1e6)
        end
    end
    return out
end

local results = {}
for _, arch in ipairs(archs) do
    local M, r = arch.M, {}
    results[arch.key] = r

    r.build = measure(10, function() fresh(arch) end)

    -- What a build keeps, less the stand-in's own frame state (which the
    -- client keeps in C): measured on a build used for nothing else.
    do
        collectgarbage("collect")
        collectgarbage("collect")
        local m0 = collectgarbage("count")
        Stand.recording = {}
        local kept = fresh(arch)
        local made = Stand.recording
        Stand.recording = nil
        collectgarbage("collect")
        collectgarbage("collect")
        local total = (collectgarbage("count") - m0) * 1024
        local stand = Stand.StateBytes(made)
        -- The recording list itself is not the kit's either.
        -- Less the recording list and the [1] slot of each frame.
        r.retained = total - stand - #made * 32
        r.standPerObject = stand / #made
        r.keptEnv = kept
    end

    local env = fresh(arch)

    local buttons = env.ui.track
    r.hover = measure(2000, function(i)
        local b = buttons[i % #buttons + 1]
        b = rawget(b, "frame") or b
        Stand.Fire(b, "OnEnter")
        Stand.Fire(b, "OnLeave")
    end)
    r.click = measure(300, function(i)
        local b = buttons[2 + (i % ITEMS)]
        Stand.Fire(rawget(b, "frame") or b, "OnClick", "LeftButton")
        M.Flush(env.ui)
    end)
    r.look = measure(20, function(i)
        M.SetLook(env.ui, C.looks[i % 2 + 1])
        M.Flush(env.ui)
    end)
    r.resize = measure(50, function(i)
        env.win:SetWidth(400 + (i % 2) * 40)
        M.Flush(env.ui)
    end)

    collectgarbage("collect")
    local before, madeBefore = collectgarbage("count"), Stand.objects
    r.rebuild = measure(20, function()
        M.Clear(env.ui, env.win)
        M.Screen(env.ui, env.win, env.db, env.items)
        M.Flush(env.ui)
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    -- Less the stand-in's state for the frames made (three rounds of 20).
    local made = Stand.objects - madeBefore
    r.rebuildGrowth = ((collectgarbage("count") - before) * 1024 - made * (r.standPerObject + 16)) / 60
end

-- Ease of use: the sample screen's code, and the architecture's own size.
local function source(file)
    local text = assert(io.open(BENCH .. file)):read("*a")
    local screen = text:match("%-%- screen:begin\n(.-)%-%- screen:end") or ""
    local function lines(s)
        local n = 0
        for line in s:gmatch("[^\n]+") do
            if line:match("%S") and not line:match("^%s*%-%-") then n = n + 1 end
        end
        return n
    end
    local tokens = 0
    for _ in screen:gsub("%-%-[^\n]*", ""):gmatch("[%w_]+") do tokens = tokens + 1 end
    for _ in screen:gsub("%-%-[^\n]*", ""):gmatch("[^%w_%s]") do tokens = tokens + 1 end
    local updates = 0
    for _ in screen:gmatch(":SetText%(") do updates = updates + 1 end
    for _ in screen:gmatch(":SetValue%(") do updates = updates + 1 end
    for _ in screen:gmatch(":Set{") do updates = updates + 1 end
    for _ in screen:gmatch("Update%(%)") do updates = updates + 1 end
    for _ in screen:gmatch(":Reset%(%)") do updates = updates + 1 end
    return lines(screen), tokens, updates, lines(text) - lines(screen)
end

local function row(label, fmt, get)
    local cells = {}
    for _, arch in ipairs(archs) do cells[#cells + 1] = string.format(fmt, get(results[arch.key], arch)) end
    print(string.format("%-34s", label) .. table.concat(cells, ""))
end

local header = {}
for _, arch in ipairs(archs) do header[#header + 1] = string.format("%12s", arch.key) end
print(string.format("%-34s", "") .. table.concat(header, ""))
local W = "%12s"
local function n(v, d) return string.format("%." .. (d or 0) .. "f", v) end
local function scenario(title, key, per)
    print(title)
    row("  client calls / " .. per, W, function(r) return n(r[key].calls) end)
    row("  Lua time us / " .. per, W, function(r) return n(r[key].us, 1) end)
    row("  bytes allocated / " .. per, W, function(r) return n(r[key].bytes) end)
end
scenario("Build the screen (~250 widgets)", "build", "build")
row("  frames and regions made", W, function(r) return n(r.build.objects) end)
row("  Lua memory kept by the kit, KB", W, function(r) return n(r.retained / 1024, 1) end)
scenario("Hover a button (enter + leave)", "hover", "hover")
scenario("Click +1 (count changes) + layout", "click", "click")
scenario("Change the look + layout", "look", "change")
scenario("Resize the window + layout", "resize", "resize")
scenario("Clear and build again", "rebuild", "rebuild")
row("  frames and regions made", W, function(r) return n(r.rebuild.objects) end)
row("  Lua memory kept, KB / rebuild", W, function(r) return n(r.rebuildGrowth / 1024, 1) end)
print("Ease of use")
local function kitLines(prefix)
    local total = 0
    for line in io.lines("NuuKit.toc") do
        local file = line:match("^%s*(" .. (prefix or "UI/") .. "[^%s]*%.lua)%s*$")
        if file then
            for text in io.lines(file) do
                if text:match("%S") and not text:match("^%s*%-%-") then total = total + 1 end
            end
        end
    end
    return total
end
local function screenOf(arch) return source(arch.screenFile or arch.file) end
row("  screen code, lines", W, function(_, arch) local l = screenOf(arch); return l end)
row("  screen code, tokens", W, function(_, arch) local _, t = screenOf(arch); return t end)
row("  manual update calls", W, function(_, arch) local _, _, u = screenOf(arch); return u end)
row("  architecture code, lines", W, function(_, arch)
    if arch.kit then return kitLines() end
    if arch.kit1 then return kitLines("UI%-Test1/") end
    local _, _, _, own = source(arch.file)
    if arch.base then own = own + select(4, source(arch.base)) end
    return own
end)
