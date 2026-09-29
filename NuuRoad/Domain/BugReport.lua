local _, ns = ...

-- Bug reports, for the guide and for the addon itself.
--
-- A player who hits a bug knows one thing - what went wrong - and the rest of
-- what it takes to fix it is on their screen and in the addon's own state at
-- that moment: which guide, which step, what that step was waiting for, what
-- the quest log said about it, where they stood, what they did just before.
-- So the player writes a line and picks a category, and everything else is
-- gathered in one pass, at the moment they press the button.
--
-- Building and filing is the kit's (Kit.NewBugReports, NuuKit/Core/BugReport.lua):
-- this file is what a NuuRoad report is about - its kinds, categories and
-- sections. A report goes on the `bug` channel of the session log
-- (ns.recorder), which reaches disk with the rest of the session at logout
-- or /reload and is read by `Tools/SessionLog/sessions.py --bugs`.
--
-- The module is the kit's reports object itself, so Build, File, Kind, Kinds,
-- Category, Sections, Inline and Plain are the kit's; Subject is NuuRoad's.
-- Every section is gathered under pcall by the kit: a section that throws
-- becomes one line saying so rather than the end of the report.
--
-- Pure apart from what the modules it reads do, so a report can be built and
-- checked outside the game.
local Kit = ns.Kit
local plain, quote, inline, clock = Kit.BugReport.Plain, Kit.BugReport.Quote, Kit.BugReport.Inline, Kit.BugReport.Clock

local function modules() return ns.modules end
local function client() return ns.modules.Client end

-- The active guide and where the report is pointed in it. `stepIndex` is the
-- step the player named, which defaults to the one in front of them.
local function subjectOf(stepIndex)
    local Progress = modules().Progress
    local guide = Progress and Progress:GetActiveGuide()
    if not guide then return nil end
    local state = Progress:PeekState(guide)
    local current = state and state.currentStep
    local index = tonumber(stepIndex) or current
    return { guide = guide, state = state, current = current, index = index, node = index and guide.nodes[index] or nil }
end

local BugReport = Kit.NewBugReports({
    name = "NuuRoad",
    version = ns.version,
    -- Looked up again at every Build (below): outside the game this file can
    -- load before there is a session log.
    recorder = ns.recorder,
    subject = function(request) return subjectOf(request.step) end,
    -- The fields of the log row worth filtering on.
    fields = function(subject)
        return {
            guide = subject and subject.guide.id or nil,
            guideUpdated = subject and subject.guide.updated or nil,
            step = subject and subject.index or nil,
            current = subject and subject.current or nil,
        }
    end,
    defaultKind = "addon",
    -- What every report carries whatever it is about, first and last.
    leading = { "player", "where", "target" },
    trailing = { "recent" },
    recentChannel = "rec",
    describeRecord = function(row)
        local Recording = modules().Recording
        return Recording and Recording:Describe(row) or nil
    end,
})

function BugReport:Subject(stepIndex)
    return subjectOf(stepIndex)
end

-- What a report is about. A guide report is about the content: the step is
-- the evidence. An addon report is about the machinery: each category names
-- the diagnostics that bear on it, on top of the ones every report carries.
BugReport:AddKind("guide", {
    label = "Guide",
    -- The form's button for it (the kit's BugReportWindow).
    caption = "The guide",
    tooltip = "Something about the guide's content: a wrong place, a wrong ID, a step that will not finish, the order,"
        .. " the text.",
    categories = {
        { key = "location", label = "Wrong place", tip = "The arrow, a map pin, or the coordinates point somewhere the step is not." },
        { key = "ids", label = "Wrong quest, NPC or item", tip = "The step names the wrong quest, creature, item, or count." },
        { key = "stuck", label = "Step will not finish", tip = "You did what the step asks and it did not go green." },
        { key = "early", label = "Finished or skipped early", tip = "The step went green or was skipped before you did it." },
        { key = "order", label = "Order or missing step", tip = "Steps in a poor order, a missing step, or a step you could not do yet." },
        { key = "text", label = "Text or note", tip = "The wording, a note, or advice that is wrong or unclear." },
        { key = "other", label = "Other", tip = "Anything else about this guide." },
    },
    sections = { "step", "neighbours", "trail", "stepQuests", "stepState", "stepHistory", "findings" },
})
BugReport:AddKind("addon", {
    label = "Addon",
    caption = "The addon",
    tooltip = "Something about NuuRoad itself: the tracker, the arrow, travel routes, quest automation, marks, the"
        .. " editor, an error.",
    categories = {
        { key = "tracker", label = "Tracker and step list", tip = "The tracker window, its step list, buttons, or layout.",
            sections = { "step", "neighbours", "trail", "stepState", "stepHistory" } },
        { key = "navigation", label = "Arrow and map pins", tip = "The waypoint arrow, the distance, or the pins on the map.",
            sections = { "step", "navigation" } },
        { key = "travel", label = "Travel route", tip = "The suggested route: flights, boats, zeppelins, teleports, caves.",
            sections = { "step", "navigation", "travel" } },
        { key = "quests", label = "Quest accept and turn-in", tip = "Quests accepted or turned in when they should not be, or not when they should.",
            sections = { "step", "stepQuests", "questLog" } },
        { key = "marking", label = "Target marks and NPC panel", tip = "Raid marks on step creatures, or the NPC strip beside the tracker.",
            sections = { "step", "marking" } },
        { key = "items", label = "Items, materials, junk", tip = "The quest item buttons, the materials list, or selling junk.",
            sections = { "step", "neighbours" } },
        { key = "editor", label = "Editor and places", tip = "The guide editor, its places tab, or the place recorder.",
            sections = { "editor" } },
        { key = "saved", label = "Saved data and resume", tip = "Settings or progress not kept, or the guide not picking up where you were.",
            sections = { "step", "saved", "recorder" } },
        { key = "error", label = "Lua error", tip = "An error message popped up. Paste its text into the description.",
            sections = { "step", "neighbours", "trail", "api" } },
        { key = "other", label = "Other", tip = "Anything else about the addon.",
            sections = { "step", "api" } },
    },
    -- Every addon report says how the addon was set up.
    sections = { "settings" },
})

-- How much of the neighbourhood and the history a report quotes.
BugReport.around, BugReport.trailLength, BugReport.recentRows, BugReport.travelRows = 3, 10, 12, 15

-- A step's line in a report: its number, how far along it is, and what it says.
local function stepLine(node, state, current)
    local Steps = modules().Steps
    local status = state and state.statuses[node.index]
    local mark = node.index == current and "HERE" or (status and tostring(status)) or (current and node.index < current and "passed" or "ahead")
    local Progress = modules().Progress
    if Progress and Progress.IsAvailable and not Progress:IsAvailable(node) then mark = mark .. ",gated" end
    local title = Steps and Steps:Title(node) or node.title
    return string.format("#%d [%s] %s", node.index, mark, plain(title or node.kind or "?"))
end

local function sectionOf(guide, index)
    for _, section in ipairs(guide.sections or {}) do
        for _, nodeIndex in ipairs(section.nodeIndexes or {}) do
            if nodeIndex == index then return section end
        end
    end
    return nil
end

local function describeLocation(location)
    if type(location) ~= "table" or type(location.x) ~= "number" or type(location.y) ~= "number" then return nil end
    local Client = client()
    local mapName = Client and Client.GetMapName and Client:GetMapName(location.mapID)
    return string.format("map %s%s at %.2f, %.2f", tostring(location.mapID), mapName and (" (" .. mapName .. ")") or "",
        location.x * 100, location.y * 100)
end

-- The quests a step names, gathered from its goals and its references.
local function stepQuests(node)
    local quests, seen = {}, {}
    local function add(id)
        if type(id) == "number" and not seen[id] then seen[id] = true; table.insert(quests, id) end
    end
    local Steps = modules().Steps
    for _, goal in ipairs(Steps and Steps:Goals(node) or {}) do add(goal.quest) end
    for _, id in ipairs(node.refs and node.refs.quests or {}) do add(id) end
    return quests
end

-- Each section: a title and a function returning its lines. `subject` is what
-- Subject() found, or nil when no guide is running.
local function section(name, title, build) BugReport:AddSection(name, title, build) end

-- The kit's player lines, and the realm answers a guide branches on.
section("player", "Player", function(subject, reports)
    local lines = Kit.BugReport.PlayerLines(subject, reports)
    local Config = modules().Config
    table.insert(lines, string.format("Realm answers: xpRate %s, auctionHouse %s, selfFound %s",
        tostring(Config:Get("realm.xpRate")), tostring(Config:Get("realm.auctionHouse")), tostring(Config:Get("realm.selfFound"))))
    return lines
end)

section("where", "Where", function()
    local Client = client()
    local lines = {}
    local mapID = Client:GetCurrentMapID()
    local x, y
    if mapID then x, y = Client:GetPlayerMapPosition(mapID) end
    table.insert(lines, string.format("Map %s (%s)%s", tostring(mapID), tostring(mapID and Client:GetMapName(mapID)),
        x and string.format(" at %.2f, %.2f", x * 100, y * 100) or ", position unknown"))
    table.insert(lines, "Zone " .. tostring(Client:GetZoneName()) .. ", subzone " .. tostring(Client:GetSubzone()))
    local states = {}
    if Client.IsOnTaxi and Client:IsOnTaxi() then table.insert(states, "on a flight") end
    if Client.IsPlayerGhost and Client:IsPlayerGhost() then table.insert(states, "dead (ghost)") end
    if Client.UnitInCombat and Client:UnitInCombat("player") then table.insert(states, "in combat") end
    if #states > 0 then table.insert(lines, "Player is " .. table.concat(states, ", ")) end
    return lines
end)

section("target", "Target", function()
    local Client = client()
    if not Client:UnitExists("target") then return { "No target" } end
    local id = Client:GetUnitCreatureID("target")
    local line = tostring(Client:GetUnitName("target")) .. (id and (" (NPC " .. id .. ")") or " (not a creature)")
    if Client:UnitIsDead("target") then line = line .. ", dead" end
    return { line }
end)

section("step", "Guide and step", function(subject)
    if not subject then return { "No guide is running." } end
    local guide, node = subject.guide, subject.node
    local Steps, Names = modules().Steps, modules().Names
    local Repository = modules().GuideRepository
    local meta = guide.meta or {}
    local lines = {
        string.format("Guide %s (%s), %s", quote(meta.title or "?"), tostring(guide.id),
            Repository and Repository:IsBuiltIn(guide.id) and "built-in" or "personal"),
        string.format("By %s; updated %s; source %s", tostring(meta.author), guide.updated and clock(guide.updated) or "never", tostring(meta.source)),
    }
    if not node then
        table.insert(lines, "Step " .. tostring(subject.index) .. " is not in this guide (" .. #guide.nodes .. " steps); the guide may be finished.")
        return lines
    end
    local section = sectionOf(guide, node.index)
    table.insert(lines, string.format("Step %d of %d%s%s", node.index, #guide.nodes,
        section and (", section " .. quote(section.title)) or "",
        node.index == subject.current and " - the step in front of the player"
            or (" - the player is on step " .. tostring(subject.current))))
    table.insert(lines, "Title: " .. plain(Steps:Title(node)))
    for _, goal in ipairs(Steps:Goals(node)) do
        local ok, status, progress = pcall(Steps.GoalStatus, Steps, goal, node)
        if not ok then status, progress = "error: " .. tostring(status), nil end
        table.insert(lines, string.format("  goal [%s] %s%s", tostring(status or "todo"), plain(Steps:GoalText(goal)),
            progress and ("  (" .. plain(progress) .. ")") or ""))
    end
    if node.body and node.body ~= "" then table.insert(lines, "Note: " .. plain(node.body)) end
    local location = describeLocation(node.location)
    if location then
        local Navigation = modules().Navigation
        local away = Navigation and Navigation.Measure and Navigation:Measure(node.location)
        table.insert(lines, "Location: " .. location .. (away and away ~= "" and ("; " .. plain(away)) or ""))
    end
    local refs = node.refs or {}
    for _, id in ipairs(refs.npcs or {}) do table.insert(lines, "NPC " .. id .. ": " .. plain(Names:DescribeNPC(id))) end
    for _, id in ipairs(refs.items or {}) do table.insert(lines, "Item " .. id .. ": " .. plain(Names:DescribeItem(id))) end
    if node.condition then table.insert(lines, "Only: " .. plain(Steps:DescribeCondition(node.condition))) end
    if node.label then table.insert(lines, "Label: " .. tostring(node.label)) end
    if node.companionOf then table.insert(lines, "Carried alongside step " .. tostring(node.companionOf)) end
    local state = subject.state
    table.insert(lines, "Status: " .. tostring(state and state.statuses[node.index] or "none")
        .. (state and state.holdStep == node.index and ", held (moved here by hand)" or ""))
    table.insert(lines, "Kind: " .. tostring(node.kind))
    table.insert(lines, "Completion: " .. inline(node.completion))
    if node.auto then table.insert(lines, "Auto: " .. inline(node.auto)) end
    return lines
end)

section("neighbours", "Steps around it", function(subject)
    if not subject or not subject.node then return {} end
    local guide, index = subject.guide, subject.node.index
    local lines = {}
    for position = math.max(1, index - BugReport.around), math.min(#guide.nodes, index + BugReport.around) do
        local line = stepLine(guide.nodes[position], subject.state, subject.current)
        table.insert(lines, (position == index and "> " or "  ") .. line)
    end
    return lines
end)

section("trail", "How the player got here", function(subject)
    local trail = subject and subject.state and subject.state.trail
    if not trail or #trail == 0 then return { "No steps passed this session." } end
    local lines, first = {}, math.max(1, #trail - BugReport.trailLength + 1)
    if first > 1 then table.insert(lines, "(" .. (first - 1) .. " earlier steps left out)") end
    for position = first, #trail do
        local node = subject.guide.nodes[trail[position]]
        if node then table.insert(lines, stepLine(node, subject.state, subject.current)) end
    end
    return lines
end)

section("stepQuests", "Quests on the step", function(subject)
    if not subject or not subject.node then return {} end
    local Client, Names = client(), modules().Names
    local lines = {}
    for _, id in ipairs(stepQuests(subject.node)) do
        table.insert(lines, string.format("Quest %d %s: in log %s, turned in %s, ready %s", id, plain(Names:DescribeQuest(id)),
            tostring(Client:IsQuestInLog(id)), tostring(Client:IsQuestComplete(id)), tostring(Client:IsQuestReadyToTurnIn(id))))
        for part, objective in ipairs(Client:GetQuestObjectives(id)) do
            table.insert(lines, string.format("  %d. %s%s", part, plain(objective.text or "?"), objective.finished and " (done)" or ""))
        end
    end
    if #lines == 0 then return { "The step names no quest." } end
    return lines
end)

section("questLog", "Quest log", function()
    local lines = {}
    for _, entry in ipairs(client():GetQuestLogEntries()) do
        table.insert(lines, entry.questID .. " " .. plain(entry.title or "?")
            .. (client():IsQuestReadyToTurnIn(entry.questID) and " (ready)" or ""))
    end
    if #lines == 0 then return { "Empty, or the client did not answer." } end
    return lines
end)

section("findings", "Audit findings for this guide", function(subject)
    local GuideAudit = modules().GuideAudit
    if not subject or not GuideAudit then return {} end
    local lines = {}
    for _, finding in ipairs(GuideAudit:Findings()) do
        if finding.guideID == subject.guide.id then table.insert(lines, plain(finding.text)) end
    end
    return lines
end)

-- Every setting as it applies, then the ones the player chose.
section("settings", "Settings", function()
    local Config = modules().Config
    local lines = {}
    local function list(settings)
        local keys = {}
        for key in pairs(settings) do table.insert(keys, key) end
        table.sort(keys)
        for _, key in ipairs(keys) do table.insert(lines, key .. " = " .. inline(settings[key])) end
    end
    list(Config:AllSettings())
    local chosen = ns.db and ns.db.settings or {}
    table.insert(lines, next(chosen) and "Chosen by the player:" or "Chosen by the player: nothing, every default")
    list(chosen)
    return lines
end)

section("navigation", "Navigation", function()
    return modules().Navigation:DiagnosticLines()
end)

section("travel", "Travel", function()
    local lines = {}
    local Route = modules().TravelRoute
    if Route then for _, line in ipairs(Route:DiagnosticLines()) do table.insert(lines, line) end end
    local rows = ns.recorder and ns.recorder:Records("travel") or {}
    if #rows > 0 then
        table.insert(lines, "Last travel log rows:")
        for position = math.max(1, #rows - BugReport.travelRows + 1), #rows do
            table.insert(lines, "  " .. tostring(rows[position].at) .. " " .. inline(rows[position].d))
        end
    end
    return lines
end)

section("marking", "Target marking", function()
    return modules().GuideAudit:MarkingDiagnostics()
end)

section("editor", "Editor", function()
    local Editor = modules().Editor
    local working = Editor and Editor.working
    if not working then return { "Nothing is open in the editor." } end
    local lines = { string.format("Editing %s (%s), %d steps, step %s selected", quote(working.meta and working.meta.title or "?"),
        tostring(working.id), #(working.nodes or {}), tostring(Editor.stepIndex)) }
    local node = working.nodes and working.nodes[Editor.stepIndex]
    if node then table.insert(lines, "Selected: " .. inline(node)) end
    if working.places then table.insert(lines, #working.places .. " places") end
    return lines
end)

section("saved", "Saved data", function()
    return modules().Config:GetSavedDataLines()
end)

-- What the flow sees at the step the player is on, and what it saw before
-- (`Domain/StepState.lua`): the group member by member, the condition read
-- every way, and whether the step reads done but will not advance.
section("stepState", "Step state", function()
    local StepState = modules().StepState
    if not StepState then return { "The step-state recorder is not loaded." } end
    return StepState:Describe(StepState:Snapshot())
end)

section("stepHistory", "Step history", function()
    local StepState = modules().StepState
    if not StepState then return {} end
    return StepState:HistoryLines()
end)

-- The kit brings `recorder` (the session log's state) and `recent` (the last
-- rows of the `rec` channel, described by Recording:Describe).

-- Building and filing are the kit's; the session log is looked up when used,
-- since this file loads before the recorder may exist (outside the game).
local build = BugReport.Build
function BugReport:Build(request)
    self.recorder = ns.recorder
    return build(self, request)
end

-- Builds a report and writes it to the session log's `bug` channel, through
-- ns:RecordHere like every other row NuuRoad writes.
function BugReport:File(request)
    local report = self:Build(request)
    report.record = ns:RecordHere("bug", report.data)
    self.sessionCount = self.sessionCount + 1
    return report
end

ns:RegisterModule("BugReport", BugReport)
