-- Run from the NuuExperiments folder with a standalone Lua 5.1 interpreter:
--   nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"
-- A small stand-in for the client: flush(seconds) moves the clock on (by
-- default far enough for every timer) and runs the timers then due, but not
-- the ones they start; events are fired by hand.

local timers, frames = {}, {}
local clockNow = 0
local function flush(seconds)
    clockNow = clockNow + (seconds or 1e6)
    local due, later = {}, {}
    for _, timer in ipairs(timers) do
        table.insert(timer.at <= clockNow and due or later, timer)
    end
    timers = later
    for _, timer in ipairs(due) do timer.fn() end
end

C_Timer = { After = function(delay, fn) table.insert(timers, { at = clockNow + delay, fn = fn }) end }
GetTime = function() return clockNow end
debugprofilestop = function() return clockNow * 1000 end
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

-- Titles once loaded; quest 5 is in the client's cache from the start.
local titles = { [871] = "Disrupt the Attacks", [5] = "Jitters' Growling Gut" }
C_QuestLog.GetTitleForQuestID = function(id) if loadedQuests[id] or id == 5 then return titles[id] end end
C_QuestLog.GetQuestDifficultyLevel = function(id) if id == 871 then return 15 end end
HaveQuestData = function(id) return id == 5 end
load("Experiments/QuestScanIDs.lua")
assert(#ns.QuestScanIDs > 100, "the client's quest IDs")
ns.QuestScanIDs = { { 5, 6 }, { 871, 871 }, { 999999, 999999 } }
load("Experiments/QuestScan.lua")
load("Experiments/QuestRecord.lua")

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

-- quest-scan: a cached quest is read as it is, the rest asked at a steady
-- rate; an ID never answered is left for the next run, which carries on.
requestedQuests = {}
loadedQuests[871] = nil
ns:Run("quest-scan")
local scan = NuuExperimentsDB.data["quest-scan"]
check(results["quest-scan"].status == "running", "the scan waits for answers")
check(scan.build == "1.60.1 (70058)", "the scan is for this build")
check(scan.quests[5].title == "Jitters' Growling Gut" and not requestedQuests[5], "a cached quest is read, not asked")
check(requestedQuests[6] and requestedQuests[871] and requestedQuests[999999], "the rest are asked")
loadedQuests[871] = true
fire("QUEST_DATA_LOAD_RESULT", 871, true)
fire("QUEST_DATA_LOAD_RESULT", 999999, false)
local found = scan.quests[871]
check(found.title == "Disrupt the Attacks" and found.level == 15, "title and level")
check(found.objectives[1].required == 8 and found.objectives[1].type == "monster", "objectives kept")
check(scan.missing[999999] and not scan.quests[999999], "a quest the server lacks")
for _ = 1, 6 do flush(6) end -- 6 never answers: asked three times, with a pause after each slow-down
check(scan.silent[6] == 3, "an ID never answered is left")
check(results["quest-scan"].status == "ok", "the scan ends: " .. tostring(results["quest-scan"].status))
check(results["quest-scan"].values.progress.quests == 2, "progress counts")
requestedQuests = {}
ns:Run("quest-scan")
check(requestedQuests[6] and not requestedQuests[871] and not requestedQuests[999999], "the next run asks only what is left")
check(scan.quests[871] ~= nil, "and keeps the rest")
SlashCmdList.NUUEXPERIMENTS("stop quest-scan")
check(results["quest-scan"].status == "stopped" and not ns.running["quest-scan"], "/nuux stop ends a run")
scan.silent[6] = nil
scan.quests[6] = { title = "Answered at last" }
requestedQuests = {}
ns:Run("quest-scan")
check(requestedQuests[871] and requestedQuests[6] and not scan.quests[871], "a run after a full scan starts over")
check(results["quest-scan"].log[1]:find("starting over", 1, true), "and says so")
SlashCmdList.NUUEXPERIMENTS("stop quest-scan")

-- quest-record: watching since login, merging what the player meets.
local guids = { npc = "Creature-0-1-2-3-3143-0000F1", target = "Creature-0-1-2-3-3101-0000A2" }
local unitNames = { player = "Tester", npc = "Gornek", target = "Vile Familiar" }
UnitGUID = function(unit) return guids[unit] end
UnitName = function(unit) return unitNames[unit] end
UnitLevel = function(unit) return unit == "player" and 3 or 5 end
UnitCanAttack = function(_, unit) return unit == "target" end
UnitIsDead = function() return false end
C_Map = {
    GetBestMapForUnit = function() return 1411 end,
    GetPlayerMapPosition = function() return { x = 0.4211, y = 0.6834 } end,
}
local windowQuestID, windowTitle = 792, "Vile Familiars"
GetQuestID = function() return windowQuestID end
GetTitleText = function() return windowTitle end
local logEntries, familiars = {}, 0
C_QuestLog.GetNumQuestLogEntries = function() return #logEntries end
C_QuestLog.GetInfo = function(i) return logEntries[i] end
local objectivesOf = C_QuestLog.GetQuestObjectives
C_QuestLog.GetQuestObjectives = function(id)
    if id ~= 792 then return objectivesOf(id) end
    return { { type = "monster", text = familiars .. "/8 Vile Familiar slain", numRequired = 8,
        numFulfilled = familiars, finished = false } }
end
C_GossipInfo = {
    GetAvailableQuests = function() return { { questID = 794, title = "Burning Blade Medallion" } } end,
    GetActiveQuests = function() return {} end,
}

local rec = NuuExperimentsDB.data["quest-record"]
check(results["quest-record"].status == "watching", "the recorder watches from login")
fire("QUEST_DETAIL", 0)
local q = rec.quests[792]
check(q.title == "Vile Familiars" and q.starts["npc:3143"], "who offered it")
check(q.offered[1] == 3 and q.offered[2] == 3, "at which player level")
local gornek = rec.npcs[3143]
check(gornek.name == "Gornek" and gornek.level == 5, "the NPC's name and level")
check(gornek.points[1][1] == 1411 and gornek.points[1][2] == 42.11 and gornek.points[1][3] == 68.34, "where it stands")

logEntries = { { questID = 792, title = "Vile Familiars", level = 2 } }
fire("QUEST_ACCEPTED", 792)
check(rec.order[1] == 792 and q.level == 2, "accepted, with its level from the log")
check(q.objectives[1].required == 8 and q.objectives[1].type == "monster", "its objectives")
fire("PLAYER_TARGET_CHANGED")
familiars = 1
fire("QUEST_LOG_UPDATE")
local objective = q.objectives[1]
check(objective.points[1][1] == 1411 and objective.points[1][2] == 42 and objective.points[1][3] == 68.5,
    "where it went up, to half a unit")
check(objective.targets[3101] == 1 and rec.npcs[3101].name == "Vile Familiar", "the mob targeted gets a vote")
fire("QUEST_LOG_UPDATE")
check(objective.targets[3101] == 1, "no vote without progress")

fire("GOSSIP_SHOW")
check(rec.quests[794].starts["npc:3143"] and rec.quests[794].title == "Burning Blade Medallion", "gossip quests")
fire("QUEST_COMPLETE")
check(q.ends["npc:3143"], "who took it in")
fire("QUEST_TURNED_IN", 792, 115, 35)
check(q.turnins[1].xp == 115 and q.turnins[1].money == 35 and q.turnins[1].level == 3, "the reward at this level")
check(rec.order[2] == -792, "turned in")

guids.questnpc = "Player-1-0000ABCD"
windowQuestID, windowTitle = 793, "Shared"
fire("QUEST_DETAIL", 0)
check(rec.quests[793].shared and not rec.quests[793].starts, "a shared quest names no one")
guids.questnpc = "GameObject-0-1-2-3-3076-0000B3"
windowQuestID, windowTitle = 794, "Burning Blade Medallion"
fire("QUEST_DETAIL", 4881)
check(rec.quests[794].starts["object:3076"] and rec.quests[794].startItem == 4881, "objects and items start quests")
guids.questnpc = nil
check(results["quest-record"].values.session.quests == 3, "the session's counts")

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

-- A reload cuts off what was running: it says so, and a "build" experiment
-- runs again; a manual one waits for its Run.
results.client.status = "running"
results["quest-scan"].status = "running"
fire("PLAYER_LOGIN")
check(results["quest-scan"].status == "interrupted" and results["quest-scan"].log[#results["quest-scan"].log]:find("reloaded"),
    "a run cut off says so")
check(results.slow.status == "running", "a run going now is left alone")
flush()
check(results.client ~= clientDate and results.client.status == "ok", "an interrupted build experiment runs again")
check(results["quest-scan"].status == "interrupted", "a manual one waits")
clientDate = results.client

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
check(table.concat(ids, " ") == "client quest-data quest-scan quest-record sync async slow bytes*", "loaded, then retired: " .. table.concat(ids, " "))
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
check(ns:Prune() == 1 and #Window.list:GetItems() == 7, "pruned from the window too")
check(Window.list:GetSelected().id == "client", "the choice moves on when its result goes")

-- Progress: a bar while a run says how far it has got; a long run that does
-- not say gets a line in its log.
local long, silent
ns:Experiment({ id = "long", auto = false, run = function(t) long = t; t:Wait(60) end })
ns:Experiment({ id = "silent", auto = false, run = function(t) silent = t; t:Wait(60) end })
ns:OpenWindow("long")
Window.run:Click()
check(not Window.progress:IsShown(), "no bar before the run says how far")
long:Progress(2, 8, "2 of 8 steps")
check(Window.progress:IsShown() and Window.progress:GetValue() == 2 and Window.progress:GetMax() == 8, "how far")
ns:OpenWindow("client")
check(not Window.progress:IsShown(), "only for the experiment chosen")
ns:OpenWindow("long")
check(Window.progress:IsShown() and Window.progress:GetValue() == 2, "back on it")
SlashCmdList.NUUEXPERIMENTS("stop long")
check(not Window.progress:IsShown(), "gone when the run ends")
ns:Run("silent")
flush(3)
check(results.silent.log and results.silent.log[1]:find("without t:Progress", 1, true), "a long run without progress is told")
check(not results.long.log, "one with progress is not")
SlashCmdList.NUUEXPERIMENTS("stop silent")
check(results["quest-record"].status == "watching", "the recorder is watching")
ns:OpenWindow("quest-record")
check(not Window.progress:IsShown(), "no bar for a run watching all session")

-- quest-data counts the answers over its wait.
ns:OpenWindow("quest-data")
ns:Run("quest-data") -- the last login's run may still be waiting: this one replaces it
check(Window.progress:IsShown() and Window.progress:GetValue() == 0 and Window.progress:GetMax() == 10, "the wait as a bar")
fire("QUEST_DATA_LOAD_RESULT", 871, true)
flush(1)
check(Window.progress:GetValue() == 1, "a second on")
check(ns.running["quest-data"].progress.label:find("1 of 7 quests answered", 1, true), "the answers counted")
for _ = 1, 9 do flush(1) end
check(results["quest-data"].status == "ok" and not Window.progress:IsShown(), "done at the end of the wait")

print("NuuExperiments tests passed")
