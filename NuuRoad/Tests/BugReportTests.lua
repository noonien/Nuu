_G = _G or _ENV
local ns = { modules = {}, db = { settings = { automation = { acceptQuests = true } } }, version = "test", name = "NuuRoad" }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Print() end
function ns:Log() end
ns.Kit = ns.Kit or LoadKit()
_G.time = function() return 1789862400 end
_G.date = function() return "2026-09-23 12:00:00" end

local recorded = {}
function ns:RecordHere(channel, data)
    table.insert(recorded, { channel = channel, data = data })
    return recorded[#recorded]
end

Load(ns, "Config.lua")
Load(ns, "Domain/BugReport.lua")
local BugReport = ns.modules.BugReport

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end
local function assertHas(text, fragment, message)
    if not text:find(fragment, 1, true) then error(message .. ": '" .. fragment .. "' not in report:\n" .. text, 2) end
end
local function assertLacks(text, fragment, message)
    if text:find(fragment, 1, true) then error(message .. ": '" .. fragment .. "' should not be in the report", 2) end
end

-- A guide of three steps, the player on the second, with the first passed.
local guide = {
    id = "nuuroad:test", updated = 1789000000,
    meta = { title = "Test Road", author = "NuuRoad", source = "fixture" },
    sections = { { title = "Crossroads", nodeIndexes = { 1, 2, 3 } } },
    nodes = {
        { index = 1, kind = "acceptQuest", title = "Accept A", completion = { type = "observed" } },
        { index = 2, kind = "turnInQuest", title = "Turn in B", body = "Inside the inn.\nUpstairs.",
            location = { mapID = 1413, x = 0.52, y = 0.31 }, refs = { quests = { 870 }, npcs = { 3448 } },
            completion = { type = "observed", observed = { type = "quest", quests = { 870 } } } },
        { index = 3, kind = "travel", title = "Go to |cffff0000Ratchet|r", completion = { type = "observed" } },
    },
}
local state = { statuses = { [1] = "completed" }, trail = { 1 }, currentStep = 2 }

ns.modules.Progress = {
    active = guide,
    GetActiveGuide = function(self) return self.active end,
    PeekState = function() return state end,
    IsAvailable = function() return true end,
}
ns.modules.Steps = {
    Title = function(_, node) return node.title end,
    Goals = function(_, node)
        if node.index == 2 then return { { quest = 870, parts = { { text = "Turn in " }, { text = "The Forgotten Pools" } } } } end
        return {}
    end,
    GoalText = function(_, goal) local out = {}; for _, part in ipairs(goal.parts) do table.insert(out, part.text) end; return table.concat(out) end,
    GoalStatus = function() return "active", "2/3" end,
    DescribeCondition = function() return "Horde" end,
}
ns.modules.Names = {
    DescribeQuest = function(_, id) return "The Forgotten Pools" end,
    DescribeNPC = function(_, id) return "Tonga Runetotem" end,
    DescribeItem = function(_, id) return "Item " .. id end,
}
ns.modules.GuideRepository = { IsBuiltIn = function() return true end }
ns.modules.Client = {
    GetCurrentMapID = function() return 1413 end,
    GetPlayerMapPosition = function() return 0.5, 0.3 end,
    GetMapName = function() return "The Barrens" end,
    GetZoneName = function() return "The Barrens" end,
    GetSubzone = function() return "The Crossroads" end,
    IsOnTaxi = function() return false end,
    IsPlayerGhost = function() return false end,
    UnitInCombat = function() return false end,
    UnitExists = function() return true end,
    GetUnitCreatureID = function() return 3448 end,
    GetUnitName = function() return "Tonga Runetotem" end,
    UnitIsDead = function() return false end,
    IsQuestInLog = function() return true end,
    IsQuestComplete = function() return false end,
    IsQuestReadyToTurnIn = function() return false end,
    GetQuestObjectives = function() return { { text = "Pools explored: 2/3", finished = false } } end,
    GetQuestLogEntries = function() return { { questID = 870, title = "The Forgotten Pools" } } end,
    GetDiagnosticLines = function() return { "Build 1.16.1 (99999)" } end,
}
-- A diagnostics source that breaks must not take the report with it.
ns.modules.Navigation = {
    DiagnosticLines = function() error("navigation exploded") end,
    Measure = function() return "40 yd NE" end,
}

-- Sections: the ones every report carries, the kind's, the category's, in
-- that order and each once.
local sections = BugReport:Sections("addon", "travel")
assertEquals(sections[1], "player", "every report opens with the player")
assertEquals(sections[#sections], "recent", "and closes with what they did last")
local seen = {}
for _, name in ipairs(sections) do
    assertEquals(seen[name], nil, "no section twice: " .. name)
    seen[name] = true
end
assert(seen.settings and seen.travel and seen.navigation and seen.step, "an addon travel report reads the travel state")
assertEquals(BugReport:Sections("guide", "stuck")[4], "step", "a guide report leads with the step")

-- A guide report on the current step.
local report = BugReport:Build({ kind = "guide", category = "stuck", description = "  It stays red.  " })
local text = report.text
assertHas(text, "NuuRoad guide report: Step will not finish", "the header names the kind and category")
assertHas(text, "It stays red.", "the player's words are in it")
assertLacks(text, "  It stays red.", "trimmed")
assertHas(text, 'Guide "Test Road" (nuuroad:test), built-in', "the guide is named")
assertHas(text, "Step 2 of 3, section \"Crossroads\" - the step in front of the player", "the step is placed")
assertHas(text, "goal [active] Turn in The Forgotten Pools  (2/3)", "each goal with its live status")
assertHas(text, 'Note: Inside the inn.', "the note")
assertHas(text, "Location: map 1413 (The Barrens) at 52.00, 31.00; 40 yd NE", "where the step is, and how far")
assertHas(text, "NPC 3448: Tonga Runetotem", "the creatures it names")
assertHas(text, 'Completion: { observed = { quests = { 870 }, type = "quest" }, type = "observed" }', "the rule that finishes it")
assertHas(text, "> #2 [HERE] Turn in B", "the steps around it, this one marked")
assertHas(text, "  #1 [completed] Accept A", "with the ones before")
assertHas(text, "#3 [ahead] Go to Ratchet", "and after, colour codes stripped")
assertHas(text, "Quest 870 The Forgotten Pools: in log true, turned in false, ready false", "the quest as the client sees it")
assertHas(text, "1. Pools explored: 2/3", "with its objectives")
assertHas(text, "Map 1413 (The Barrens) at 50.00, 30.00", "where the player stood")
assertHas(text, "Tonga Runetotem (NPC 3448)", "who they had targeted")
assertLacks(text, "== Settings ==", "a guide report leaves the settings out")
assertEquals(report.data.guide, "nuuroad:test", "the log row names the guide")
assertEquals(report.data.step, 2, "and the step")
assertEquals(report.data.description, "It stays red.", "and the words")

-- A step other than the current one, named by the player.
text = BugReport:Build({ kind = "guide", category = "location", step = 1 }).text
assertHas(text, "Step 1 of 3", "the named step is the subject")
assertHas(text, "the player is on step 2", "and the report says where the player really is")
assertHas(text, "(no description given)", "an empty description is said, not skipped")
text = BugReport:Build({ kind = "guide", category = "location", step = 9 }).text
assertHas(text, "Step 9 is not in this guide (3 steps)", "a step past the end says so")

-- An addon report: settings always, the category's diagnostics, and a
-- diagnostics source that throws becomes one line.
text = BugReport:Build({ kind = "addon", category = "navigation", description = "Arrow spins." }).text
assertHas(text, "NuuRoad addon report: Arrow and map pins", "addon header")
assertHas(text, "== Settings ==", "settings on every addon report")
assertHas(text, "automation = { acceptQuests = true }", "as inline Lua")
assertHas(text, "== Navigation ==\nCould not be read: ", "a broken section is one line")
assertHas(text, "navigation exploded", "saying why")
assertHas(text, "== What the player did last ==", "the report still reaches the end")

-- An unknown kind or category falls back rather than failing.
text = BugReport:Build({ kind = "nonsense", category = "nonsense" }).text
assertHas(text, "NuuRoad addon report: Other", "unknown input becomes an addon report of the last category")

-- No guide running: the step sections say so.
ns.modules.Progress.active = nil
text = BugReport:Build({ kind = "addon", category = "tracker" }).text
assertHas(text, "No guide is running.", "no guide is stated")
assertLacks(text, "== Steps around it ==", "and nothing empty is printed")
ns.modules.Progress.active = guide

-- The kinds in order for the panel, and the subject it shows before filing.
local kinds = BugReport:Kinds()
assertEquals(#kinds, 2, "two kinds")
assertEquals(kinds[1] .. "," .. kinds[2], "guide,addon", "the guide's first")
assertEquals(BugReport:Kind("guide").label, "Guide", "a kind by key")
assertEquals(BugReport:Subject().index, 2, "the subject is the current step")
assertEquals(BugReport:Subject(3).node.index, 3, "or the one named")

-- The kit's own sections: the session log, read from ns.recorder when there
-- is one.
text = BugReport:Build({ kind = "addon", category = "saved" }).text
assertHas(text, "== Session log ==\nNo session log.", "no recorder outside the game")
ns.recorder = { DiagnosticLines = function() return { "12 records" } end, Describe = function() return { character = "Tonga" } end,
    Records = function() return {} end }
text = BugReport:Build({ kind = "addon", category = "saved" }).text
assertHas(text, "== Session log ==\n12 records", "the recorder's lines")
assertHas(text, "Tonga-nil", "the player from the recorder's identity")
assertHas(text, "Realm answers: xpRate nil", "with the realm answers")
ns.recorder = nil

-- Inline keeps one value on one line.
assertEquals(BugReport.Inline("a\nb"), '"a\\nb"', "a newline is escaped")
assertEquals(BugReport.Inline({ 1, 2, x = "y" }), '{ 1, 2, x = "y" }', "list then sorted keys")

-- Filing writes one row to the bug channel.
local filed = BugReport:File({ kind = "guide", category = "text", description = "Typo." })
assertEquals(#recorded, 1, "one row")
assertEquals(recorded[1].channel, "bug", "on the bug channel")
assertEquals(recorded[1].data.category, "text", "with the category")
assertEquals(recorded[1].data.lines[1], "NuuRoad guide report: Text or note", "and the report line for line")
assertEquals(BugReport.sessionCount, 1, "counted for the session")
assert(filed.text:find("Typo.", 1, true), "the text comes back to show")

-- ASCII only in what the addon itself writes.
for _, kind in pairs(BugReport.kinds) do
    for _, category in ipairs(kind.categories) do
        assert(not (category.label .. category.tip):find("[\128-\255]"), "ASCII only: " .. category.key)
    end
end

print("bug report tests passed")
