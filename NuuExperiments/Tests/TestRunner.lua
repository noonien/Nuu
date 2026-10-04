-- Run from the NuuExperiments folder with a standalone Lua 5.1 interpreter:
--   nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"
-- A small stand-in for the client: timers run when flush() is called, events
-- are fired by hand.

local timers, frames = {}, {}
local function flush()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
GetBuildInfo = function() return "1.60.1", "70058", "Sep 30 2026", 16001 end
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
InCombatLockdown = function() return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
SlashCmdList = {}
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    table.insert(frames, frame)
    return frame
end
local function fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) table.insert(printed, text) end }

local ns = {}
local function load(path) assert(loadfile(path))("NuuExperiments", ns) end
load("Core.lua")
load("Show.lua")
load("Window.lua")
load("Commands.lua")
load("Experiments/Client.lua")

-- A quest log that knows quest 871 only once asked to load it.
local loadedQuests, requestedQuests = {}, {}
C_QuestLog = {
    RequestLoadQuestByID = function(id) requestedQuests[id] = true end,
    GetQuestObjectives = function(id)
        if not loadedQuests[id] then return {} end
        return { { type = "monster", numRequired = 8, numFulfilled = 0, finished = false, text = "Razormane: 0/8" } }
    end,
    IsOnQuest = function() return false end,
}
load("Experiments/QuestData.lua")

local function check(cond, message) if not cond then error(message, 2) end end

-- Sync, with Try, Set, Exists and an error kept.
ns:Experiment({ id = "sync", run = function(t)
    t:Set("fn", print)
    t:Set("nested", { a = { b = 1 }, [true] = "x" })
    t:Try("returns", function() return 1, nil, 3 end)
    t:Try("fails", function() error("boom") end)
    t:Exists({ "C_Timer.After", "C_Nope.Thing" })
    error("late")
end })

-- Async: ends on an event.
ns:Experiment({ id = "async", auto = false, run = function(t)
    t:Wait(5)
    t:On("ITEM_READY", function(_, id)
        t:Set("id", id)
        t:Done()
        return true
    end)
end })

-- Async: never ends, times out.
ns:Experiment({ id = "slow", auto = "login", run = function(t) t:Wait(1) end })

fire("PLAYER_LOGIN")
flush() -- the login delay: runs client, sync and slow (async is manual)
local results = NuuExperimentsDB.results
check(results.client.status == "ok", "client: " .. tostring(results.client.status) .. " " .. tostring(results.client.errors and results.client.errors[1]))
check(results.client.values.globals["C_Timer.After"] == "function", "client globals")
check(results.client.build == "1.60.1 (70058)", "build")
check(results.client.character == "Tester-Realm", "character")

-- Quest data: read before loading, asked to load, read again when it answers.
local questData = results["quest-data"]
check(questData.status == "running", "quest-data waits for the client")
check(requestedQuests[871] and requestedQuests[999999], "every quest is asked for")
check(questData.values.quests[871].before.objectives.n == nil and next(questData.values.quests[871].before.objectives) == nil,
    "nothing before loading")
check(questData.values.globals["GetQuestObjectiveInfo"] == "nil", "missing globals reported")
loadedQuests[871] = true
fire("QUEST_DATA_LOAD_RESULT", 871, true)
check(questData.values.quests[871].event.success == true, "the answer is kept")
check(questData.values.quests[871].loaded.objectives[1].numRequired == 8, "objectives read after loading")
check(questData.values.quests[871].loaded.objective1 == "<missing>", "a missing function is said so")

local sync = results.sync
check(sync.status == "error" and #sync.errors == 1, "sync keeps the run's error")
check(type(sync.values.fn) == "string" and sync.values.fn:find("^<function>"), "functions saved as text")
check(sync.values.nested.a.b == 1 and sync.values.nested["true"] == "x", "tables copied")
local r = sync.values.returns
check(r.ok and r.returns.n == 3 and r.returns[2] == "nil" and r.returns[3] == 3, "Try keeps every return")
check(sync.values.fails.ok == false and sync.values.fails.error:find("boom"), "Try keeps the error")
check(sync.values.globals["C_Nope.Thing"] == "nil", "Exists reports missing")

check(results.slow.status == "running", "slow still running")
check(results.async == nil, "manual experiment does not auto-run")
flush()
check(results.slow.status == "timeout", "slow times out")

-- The results window is the kit's copy window; a stand-in records what it shows.
local shown = {}
NuuKit = { NewUI = function() return { CopyWindow = function()
    return { Show = function(_, text, title) shown[#shown + 1] = { text = text, title = title } end }
end } end }

SlashCmdList.NUUEXPERIMENTS("run async")
check(results.async.status == "running", "async waits")
check(#shown == 0, "the window waits for the run to end")
fire("ITEM_READY", 6948)
check(results.async.status == "ok" and results.async.values.id == 6948, "async ends on its event")
check(#shown == 1 and shown[1].title == "Experiment: async", "a run shows its results when it ends")
check(shown[1].text:find("async: ok", 1, true) and shown[1].text:find("id = 6948", 1, true), "the results as text")
flush() -- its timeout fires after Done: no change
check(results.async.status == "ok", "timeout after Done changes nothing")

-- Next login on the same build: only "login" experiments run again.
local clientDate = results.client
fire("PLAYER_LOGIN")
flush()
check(results.client == clientDate, "build experiment not rerun on the same build")
check(results.slow ~= nil and results.slow.status == "running", "login experiment rerun")

-- A new build reruns "build" experiments; retired results stay until prune.
GetBuildInfo = function() return "1.60.2", "70100", "Oct 9 2026", 16001 end
results.retired = { status = "ok" }
fire("PLAYER_LOGIN")
flush()
check(results.client ~= clientDate and results.client.build == "1.60.2 (70100)", "new build reruns")
SlashCmdList.NUUEXPERIMENTS("prune")
check(results.retired == nil and results.client ~= nil, "prune drops only retired results")

SlashCmdList.NUUEXPERIMENTS("list")
SlashCmdList.NUUEXPERIMENTS("show sync")
local text = shown[#shown].text
check(text:find("sync: error", 1, true) and text:find("errors = {", 1, true), "show opens the last results, errors too")
check(text:find("nested = {", 1, true) and text:find("b = 1", 1, true), "nested values are written out")
results.bytes = { status = "ok", values = { s = "a\1|\n\255\"" } }
SlashCmdList.NUUEXPERIMENTS("show bytes")
check(shown[#shown].text:find('s = "a\\001\\124\\n\\255\\""', 1, true), "bytes are escaped, | too: " .. shown[#shown].text)
local before = #shown
SlashCmdList.NUUEXPERIMENTS("show nothing")
check(#shown == before, "no results, no window")
NuuKit = nil
ns.ui, ns.copyWindow = nil, nil
SlashCmdList.NUUEXPERIMENTS("show sync")
check(printed[#printed]:find("Results.py", 1, true), "without the kit chat says where the results are")
local listed = #printed
SlashCmdList.NUUEXPERIMENTS("")
check(#printed > listed and printed[listed + 1]:find("client (build)", 1, true), "without the kit /nuux lists in chat")

-- The experiments window, on the kit's stand-in for the client (last: it
-- installs the stand-in in _G).
local slash = SlashCmdList.NUUEXPERIMENTS
local stand = dofile("../NuuKit/Tests/Support/Frames.lua")
SlashCmdList.NUUEXPERIMENTS = slash
local kit = {}
for line in io.lines("../NuuKit/NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" and not file:match("^Dev/") then
        assert(loadfile("../NuuKit/" .. file))("NuuKit", kit)
    end
end
NuuKit = kit.Kit
local Window = ns.Window

SlashCmdList.NUUEXPERIMENTS("")
check(Window.win:IsShown(), "/nuux opens the window")
local ids = {}
for _, item in ipairs(Window.list:GetItems()) do ids[#ids + 1] = item.id .. (item.retired and "*" or "") end
check(table.concat(ids, " ") == "client quest-data sync async slow bytes*", "loaded, then retired: " .. table.concat(ids, " "))
check(Window.list:GetSelected().id == "client", "the first is chosen")

ns:OpenWindow("sync")
check(Window.list:GetSelected().id == "sync", "opened on sync")
check(Window.title:GetText() == "sync" and Window.meta:GetText():find("error: build 1.60.2 (70100)", 1, true),
    "the meta line: " .. Window.meta:GetText())
check(Window.body:GetText():find("errors = {", 1, true) and Window.body:GetText():find("b = 1", 1, true), "the results")
Window.copy:Click()
check(ns.copyWindow:IsShown() and ns.copyWindow:GetText():find("sync: error", 1, true), "Copy opens the copy window")

-- Run from the window: the tag follows the run, and the window updates when it ends.
ns:OpenWindow("async")
Window.run:Click()
check(results.async.status == "running" and not Window.run:IsEnabled(), "running: Run waits")
check(Window.body:GetText():find("values = {}", 1, true), "nothing yet")
fire("ITEM_READY", 7)
check(results.async.status == "ok" and Window.body:GetText():find("id = 7", 1, true), "the window shows the end")
check(Window.run:IsEnabled(), "Run again")

-- Clear asks twice; Prune forgets the retired one.
Window.clear:Click()
check(results.async ~= nil, "Clear asks first")
Window.clear:Click()
check(results.async == nil and Window.body:GetText() == "Not run yet.", "cleared")
ns:OpenWindow("bytes")
check(not Window.run:IsEnabled(), "a retired experiment cannot run")
check(ns:Prune() == 1 and #Window.list:GetItems() == 5, "pruned from the window too")
check(Window.list:GetSelected().id == "client", "the choice moves on when its result goes")
print("NuuExperiments tests passed")
