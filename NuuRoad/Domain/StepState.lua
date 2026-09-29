local _, ns = ...

-- What the step viewer is showing, and why, written down every time it changes.
--
-- A bug in the flow - a step not grouped with the work around it, a step for
-- another class on the card, a step that should have advanced and did not -
-- is only ever seen from the outside, a minute or an hour after it began. The
-- pointer moves already go on the `guide` channel (`Domain/Progress.lua`), but
-- a move says where the flow went, not what it saw, and nothing at all is
-- written while it sits still. So this module takes a snapshot of everything
-- the flow and the card decide from - the step, its condition read every way
-- the flow reads it, how the game reports it done, its group member by member,
-- what is carried with it, and where the flow would stop next - and records
-- it whenever it differs from the last one. A state is never lost, and a
-- quiet minute costs nothing.
--
-- Rows go on the lasting log's `guide` channel as `event = "state"`, kept by
-- age like the rest (ns.recorder, the kit's recorder), so they are still
-- there when the bug is looked at days later. `sessions.py --steps` prints them as a
-- timeline; a bug report quotes the current snapshot and the last few rows.
--
-- `auto` names what the flow will do with the step on its next look, in the
-- order `ObservedProgress:Refresh` asks: "held", "complete" (advances as
-- observed), "bypassed" and "passed" (passed over as skipped), "waiting",
-- "moot", "manual" (only SKIP moves it), or "incomplete". `stall` is set when
-- the step reads done by some measure and yet will not advance - the
-- auto-advance bug, caught in the act.
--
-- Pure apart from what the modules it reads do, so snapshots can be built and
-- compared outside the game.
local StepState = { lastKey = nil, ahead = 5, historyRows = 8 }

local function modules() return ns.modules end

-- A snapshot read in one pass; each reading is guarded, since the snapshot is
-- wanted most exactly when some part of the flow is throwing.
local function try(fn, ...)
    local ok, result, second = pcall(fn, ...)
    if not ok then return nil, nil end
    return result, second
end

local function title(node)
    local Steps = modules().Steps
    return Steps and try(Steps.Title, Steps, node) or node.title or node.kind
end

local function describe(condition)
    local Steps = modules().Steps
    return condition and Steps and try(Steps.DescribeCondition, Steps, condition) or nil
end

-- How the flow reads a step's `only`: in the guide for this character at all,
-- open now, waited on, or passed over.
local function openness(Progress, node)
    if not node.condition then return "open" end
    if Progress:IsRuledOut(node) then return "ruledOut" end
    if Progress:IsAvailable(node) then return "open" end
    if Progress:IsBypassed(node) then return "bypassed" end
    return "waiting"
end

local function observedOf(node)
    return node.completion and node.completion.type == "observed" and node.completion.observed or nil
end

-- The card's goal lines for a step, with the client's own status and count.
local function goals(node)
    local Steps = modules().Steps
    if not Steps or not Steps.Goals then return nil end
    local list = {}
    for _, goal in ipairs(try(Steps.Goals, Steps, node) or {}) do
        local status, progress = try(Steps.GoalStatus, Steps, goal, node)
        table.insert(list, (goal.verb or "?") .. "=" .. tostring(status) .. (progress and (" " .. progress) or ""))
    end
    return #list > 0 and list or nil
end

-- What the flow will do with the current step on its next look, in the order
-- `ObservedProgress:Refresh` asks.
function StepState:Auto(guide, node, held)
    local Progress, Client = modules().Progress, modules().Client
    local ObservedProgress, GuideScan = modules().ObservedProgress, modules().GuideScan
    if held then return "held" end
    local observed = observedOf(node)
    if observed and Client and Client:MatchesObservedCompletion(observed, node.location, node.index) then return "complete" end
    if Progress:IsBypassed(node) then return "bypassed" end
    if ObservedProgress and try(ObservedProgress.PassedTo, ObservedProgress, guide, node) then return "passed" end
    if Progress:IsWaiting(node) then return "waiting" end
    if GuideScan and try(GuideScan.NodeIsMoot, GuideScan, node) then return "moot" end
    if not observed then return "manual" end
    return "incomplete"
end

-- The authored group around the current step, member by member, with why the
-- card shows each or leaves it out - the same rules as `Progress:QuestGroup`
-- and the card's own filter in `MainWindow`.
function StepState:Group(guide, node, state)
    local Schema, Progress, GuideScan = modules().Schema, modules().Progress, modules().GuideScan
    local range = Schema and Schema.GroupAt and Schema:GroupAt(guide, node.index)
    if not range then return nil end
    local members = {}
    for index = range.first, range.last do
        local member = guide.nodes[index]
        local why
        if index == node.index then
            why = "current"
        elseif index < node.index then
            why = "before"
        elseif not Progress:IsAvailable(member) then
            why = "unavailable: " .. tostring(describe(member.condition))
        elseif GuideScan and try(GuideScan.NodeIsMoot, GuideScan, member) then
            why = "moot"
        elseif GuideScan and try(GuideScan.IsStepDone, GuideScan, guide, member, state) then
            why = "done"
        else
            why = "shown"
        end
        table.insert(members, { i = index, why = why, title = title(member) })
    end
    return { first = range.first, last = range.last, label = range.label, members = members }
end

-- Where the flow would stop next, and what it passes over on the way there.
function StepState:Ahead(guide, node)
    local Progress = modules().Progress
    local stops, passed, cursor = {}, {}, node
    local guard = 0
    while cursor and #stops < self.ahead and guard < #guide.nodes do
        guard = guard + 1
        local walk = cursor["next"] or cursor.index + 1
        -- Everything between here and the next stop is passed over; say why.
        local nextIndex = Progress:NextIndex(guide, cursor)
        if not nextIndex or not guide.nodes[nextIndex] then break end
        for index = walk, nextIndex - 1 do
            local skipped = guide.nodes[index]
            if skipped and #passed < 12 then
                local why = Progress:IsCarried(skipped) and "carried" or (Progress:IsRuledOut(skipped) and "ruledOut") or "bypassed"
                if why ~= "ruledOut" then table.insert(passed, { i = index, why = why }) end
            end
        end
        table.insert(stops, nextIndex)
        cursor = guide.nodes[nextIndex]
    end
    return stops, passed
end

-- The whole picture for the active guide, or nil when none is running.
function StepState:Snapshot(guide)
    local Progress = modules().Progress
    if not Progress then return nil end
    guide = guide or Progress:GetActiveGuide()
    if not guide then return nil end
    local state = Progress:PeekState(guide)
    if not state then return nil end
    local node = guide.nodes[state.currentStep]
    local snapshot = { guide = guide.id, step = state.currentStep, of = #guide.nodes }
    if not node then snapshot.finished = true; return snapshot end
    local Client, GuideScan, ObservedProgress = modules().Client, modules().GuideScan, modules().ObservedProgress
    local held = state.holdStep ~= nil and state.holdStep == state.currentStep
    snapshot.title, snapshot.kind = title(node), node.kind
    snapshot.status, snapshot.held = state.statuses[node.index], held or nil
    snapshot.only = describe(node.condition)
    snapshot.open = try(openness, Progress, node)
    local observed = observedOf(node)
    snapshot.completion = observed and observed.type or (node.completion and node.completion.type)
    if observed and Client then
        snapshot.observed = try(Client.MatchesObservedCompletion, Client, observed, node.location, node.index)
    end
    if GuideScan then
        snapshot.scanDone = try(GuideScan.NodeCompleted, GuideScan, node) or nil
        snapshot.settled = try(GuideScan.Settled, GuideScan, guide, node) or nil
    end
    snapshot.goals = goals(node)
    snapshot.auto = try(self.Auto, self, guide, node, held)
    local readsDone = ObservedProgress and try(ObservedProgress.StepReadsDone, ObservedProgress, guide, node)
    if readsDone and snapshot.auto ~= "complete" and snapshot.auto ~= "bypassed" and snapshot.auto ~= "passed" then
        snapshot.stall = snapshot.auto
    end
    snapshot.group = try(self.Group, self, guide, node, state)
    local carried = {}
    for _, companion in ipairs(try(Progress.Carried, Progress, guide, node) or {}) do
        table.insert(carried, { i = companion.index, sticky = companion.sticky or nil, title = title(companion) })
    end
    snapshot.carried = #carried > 0 and carried or nil
    local stops, passed = try(self.Ahead, self, guide, node)
    snapshot.ahead = stops
    snapshot.passed = passed and #passed > 0 and passed or nil
    return snapshot
end

-- The same value always reads the same: keys sorted, so two snapshots of one
-- state compare equal as text.
local function stable(value)
    local kind = type(value)
    if kind == "table" then
        local keys = {}
        for key in pairs(value) do table.insert(keys, key) end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, key in ipairs(keys) do table.insert(parts, tostring(key) .. "=" .. stable(value[key])) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(value)
end
StepState.Stable = stable

-- Records the snapshot when it differs from the last one recorded. `cause`
-- is what made the flow look (an event name, "poll", "arrival"); `moves` is
-- what the flow did on that look, `{ { from, to, why }, ... }`, and is
-- always recorded when there are any. Returns the row, or nil when nothing
-- changed.
function StepState:Observe(cause, moves)
    -- Nothing before the session log has opened this session: a row written
    -- ahead of the identity would be read as the end of the last one.
    local Recorder = ns.recorder
    if not Recorder or not Recorder.identity then return nil end
    -- A move the flow did not make itself (SKIP, BACK, a jump) is named in
    -- the cause of the first row after it.
    if self.lastMove and not (moves and #moves > 0) then cause = tostring(cause) .. " after " .. self.lastMove end
    self.lastMove = nil
    local snapshot = self:Snapshot()
    if not snapshot then
        if self.lastKey ~= nil then
            self.lastKey = nil
            ns:Record("guide", { event = "state", cause = cause, none = true })
        end
        return nil
    end
    local key = stable(snapshot)
    if key == self.lastKey and not (moves and #moves > 0) then return nil end
    self.lastKey = key
    snapshot.event, snapshot.cause = "state", cause
    snapshot.moves = moves and #moves > 0 and moves or nil
    return ns:Record("guide", snapshot)
end

-- A snapshot as report lines.
function StepState:Describe(snapshot)
    if type(snapshot) ~= "table" then return { "No guide is running." } end
    if snapshot.none then return { "No guide is running." } end
    if snapshot.finished then return { string.format("Guide %s finished (%d steps).", tostring(snapshot.guide), snapshot.of or 0) } end
    local lines = {
        string.format("Step %s of %s: %s [%s]%s", tostring(snapshot.step), tostring(snapshot.of),
            tostring(snapshot.title), tostring(snapshot.kind), snapshot.held and " HELD" or ""),
        string.format("Only: %s -> %s; completion %s, observed %s, scan %s, settled %s",
            tostring(snapshot.only or "-"), tostring(snapshot.open), tostring(snapshot.completion),
            tostring(snapshot.observed), tostring(snapshot.scanDone or false), tostring(snapshot.settled or false)),
        "Flow: " .. tostring(snapshot.auto) .. (snapshot.stall and (" - STALLED: reads done but " .. snapshot.stall) or ""),
    }
    if snapshot.goals then table.insert(lines, "Goals: " .. table.concat(snapshot.goals, "; ")) end
    if snapshot.group then
        local parts = {}
        for _, member in ipairs(snapshot.group.members or {}) do
            table.insert(parts, "#" .. member.i .. " " .. member.why)
        end
        table.insert(lines, string.format("Group %d-%d: %s", snapshot.group.first, snapshot.group.last, table.concat(parts, ", ")))
    else
        table.insert(lines, "Group: none authored")
    end
    if snapshot.carried then
        local parts = {}
        for _, entry in ipairs(snapshot.carried) do table.insert(parts, "#" .. entry.i .. (entry.sticky and " sticky" or "")) end
        table.insert(lines, "Carried: " .. table.concat(parts, ", "))
    end
    local ahead = {}
    for _, index in ipairs(snapshot.ahead or {}) do table.insert(ahead, "#" .. index) end
    local passed = {}
    for _, entry in ipairs(snapshot.passed or {}) do table.insert(passed, "#" .. entry.i .. " " .. entry.why) end
    table.insert(lines, "Next stops: " .. (#ahead > 0 and table.concat(ahead, ", ") or "-")
        .. (#passed > 0 and ("; passing " .. table.concat(passed, ", ")) or ""))
    if snapshot.moves then
        local parts = {}
        for _, move in ipairs(snapshot.moves) do
            table.insert(parts, "#" .. tostring(move.from) .. "->#" .. tostring(move.to) .. " " .. tostring(move.why))
        end
        table.insert(lines, "Moved (" .. tostring(snapshot.cause) .. "): " .. table.concat(parts, ", "))
    end
    return lines
end

-- The last few rows of the `guide` channel, one line each, for a bug report.
function StepState:HistoryLines(count)
    local Recorder = ns.recorder
    local rows = Recorder and Recorder:Records("guide") or {}
    local lines = {}
    count = count or self.historyRows
    for position = math.max(1, #rows - count + 1), #rows do
        local row, d = rows[position], rows[position].d
        local stamp = type(row.at) == "number" and date and date("%H:%M:%S", row.at) or tostring(row.at)
        if type(d) == "table" and d.event == "state" then
            if d.none or d.finished then
                table.insert(lines, stamp .. " state: " .. (d.finished and "finished" or "no guide"))
            else
                table.insert(lines, string.format("%s state (%s): #%s %s, %s%s%s", stamp, tostring(d.cause), tostring(d.step),
                    tostring(d.title), tostring(d.auto), d.stall and (" STALLED " .. d.stall) or "",
                    d.group and string.format(", group %d-%d", d.group.first, d.group.last) or ""))
            end
        elseif type(d) == "table" and d.event == "step" then
            table.insert(lines, string.format("%s move %s: #%s -> #%s", stamp, tostring(d.how), tostring(d.from), tostring(d.to)))
        end
    end
    if #lines == 0 then return { "Nothing recorded yet." } end
    return lines
end

function StepState:Initialize()
    -- A guide chosen, reset, or edited shows up on the next poll; this only
    -- makes sure the first state of the session is written at once.
    self.lastKey = nil
    self:Observe("login")
end

ns:RegisterModule("StepState", StepState)
