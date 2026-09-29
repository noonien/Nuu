local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Bug reports: the engine that builds and files them.
--
-- A player who hits a bug knows one thing - what went wrong - and the rest of
-- what it takes to fix it is on their screen and in the addon's own state at
-- that moment. So the player writes a line and picks a category, and
-- everything else is gathered here, in one pass, at the moment they press the
-- button.
--
-- There is no web service to send it to. A report goes on the `bug` channel
-- of the addon's session log (`Kit.NewRecorder`), which reaches disk with the
-- rest of the session at logout or /reload.
--
-- The kit knows how to build and file a report; what a report is about is the
-- addon's. Each addon makes its own reports object and registers on it:
--
--     local reports = Kit.NewBugReports({ name = "NuuRoad", version = ns.version,
--         recorder = ns.recorder, subject = function(request) ... end,
--         fields = function(subject) return { guide = ... } end, defaultKind = "addon" })
--     reports:AddSection("where", "Where", function(subject) return { "..." } end)
--     reports:AddKind("addon", { label = "Addon", sections = { "settings" }, categories = {
--         { key = "travel", label = "Travel route", tip = "...", sections = { "travel" } },
--         { key = "other", label = "Something else", tip = "..." },
--     } })
--     reports.leading = { "player", "where" }
--
-- A kind is what a report is about, and its categories are what the player
-- picks from; each names the sections it gathers on top of the kind's. Every
-- report also gathers `leading` first and `trailing` last. The kit brings
-- three sections of its own, which an addon may replace:
--
--     player    who was playing, on what client (the recorder's identity)
--     recorder  what the session log and the trace hold
--     recent    the last rows of the channel that says what the player did
--
-- Every section is gathered under pcall. A report is most wanted exactly when
-- some part of the addon is broken, so a section that throws becomes one line
-- saying so rather than the end of the report.
--
-- Pure apart from what the section builders read, so a report can be built
-- and checked outside the game.
local BugReport = {}
BugReport.__index = BugReport
Kit.BugReport = BugReport

-- How many rows of the `recent` section a report quotes.
BugReport.recentRows = 12

-- Colour codes and texture escapes are for the screen; a report is read as
-- plain text, pasted somewhere else.
local function plain(text)
    text = tostring(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
    return text
end
BugReport.Plain = plain

-- A string in quotes on one line: a newline in a note would otherwise break
-- the report's one-thing-per-line shape.
local function quote(text)
    return '"' .. (plain(text):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")) .. '"'
end
BugReport.Quote = quote

-- One value as a line of Lua-looking text, keys sorted so two reports of the
-- same thing read the same. Deep tables are cut, not followed forever.
function BugReport.Inline(value, depth)
    depth = depth or 0
    local kind = type(value)
    if kind == "string" then return quote(value) end
    if kind ~= "table" then return tostring(value) end
    if depth >= 4 then return "{...}" end
    local parts, keys = {}, {}
    local count = #value
    for index = 1, count do table.insert(parts, BugReport.Inline(value[index], depth + 1)) end
    for key in pairs(value) do
        if not (type(key) == "number" and key >= 1 and key <= count and key % 1 == 0) then table.insert(keys, key) end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local name = (type(key) == "string" and key:match("^[%a_][%w_]*$")) and key or ("[" .. BugReport.Inline(key, depth + 1) .. "]")
        table.insert(parts, name .. " = " .. BugReport.Inline(value[key], depth + 1))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end
local inline = BugReport.Inline

-- Now, or an epoch time, as the wall clock reads it.
local function clock(at)
    local ok, value = pcall(function() return at and date("%Y-%m-%d", at) or date("%Y-%m-%d %H:%M:%S") end)
    return ok and value or tostring(at or "?")
end
BugReport.Clock = clock

-- `options`:
--
--     name         the addon, as the report's header names it
--     version      the addon's version
--     recorder     the addon's recorder: reports are filed to it, and the
--                  kit's own sections read it
--     subject      function(request): what the report is pointed at (a
--                  guide and step, a plan), handed to every section; nil
--                  when there is nothing
--     fields       function(subject, request): extra fields for the log row,
--                  worth filtering on (`guide`, `step`)
--     defaultKind  the kind a request with an unknown kind becomes; the first
--                  kind added when not given
--     leading, trailing
--                  sections every report opens and closes with
--     recentChannel  the channel `recent` reads, "rec" unless given
--     describeRecord function(row): `{ text, time }` or a string for one row
--                  of that channel; the row's data inline when not given
function Kit.NewBugReports(options)
    options = options or {}
    local reports = setmetatable({
        name = options.name or "?",
        version = options.version,
        recorder = options.recorder,
        subjectSource = options.subject,
        fieldsSource = options.fields,
        defaultKind = options.defaultKind,
        leading = options.leading or { "player" },
        trailing = options.trailing or { "recent" },
        recentChannel = options.recentChannel or "rec",
        describeRecord = options.describeRecord,
        kinds = {},
        kindOrder = {},
        builders = {},
        sessionCount = 0,
    }, BugReport)
    reports:AddSection("player", "Player", BugReport.PlayerLines)
    reports:AddSection("recorder", "Session log", BugReport.RecorderLines)
    reports:AddSection("recent", "What the player did last", BugReport.RecentLines)
    return reports
end

-- Registers a section: its title, and a function(subject, reports) returning
-- its lines. A name already taken is replaced.
function BugReport:AddSection(name, title, build)
    assert(type(name) == "string" and type(title) == "string" and type(build) == "function", "AddSection(name, title, build)")
    self.builders[name] = { title, build }
end

-- Registers a kind: `{ label, sections, categories = { { key, label, tip,
-- sections }, ... } }`, and for the form (UI/Screens/BugReportForm.lua)
-- `caption` and `tooltip` for its button. The last category is where an unknown category lands,
-- so it is the "something else" one.
function BugReport:AddKind(key, kind)
    assert(type(key) == "string" and type(kind) == "table" and type(kind.label) == "string", "AddKind(key, { label = ... })")
    assert(type(kind.categories) == "table" and #kind.categories > 0, "AddKind: a kind needs at least one category")
    if not self.kinds[key] then table.insert(self.kindOrder, key) end
    self.kinds[key] = kind
end

function BugReport:Kind(kind)
    return self.kinds[kind]
end

-- The kinds in the order they were added, for a panel to list.
function BugReport:Kinds()
    local list = {}
    for _, key in ipairs(self.kindOrder) do table.insert(list, key) end
    return list
end

function BugReport:Category(kind, key)
    local entry = self.kinds[kind]
    for _, category in ipairs(entry and entry.categories or {}) do
        if category.key == key then return category end
    end
    return nil
end

-- The sections a report of this kind and category gathers, in order and each
-- once.
function BugReport:Sections(kind, key)
    local order, seen = {}, {}
    local function add(list)
        for _, name in ipairs(list or {}) do
            if not seen[name] then seen[name] = true; table.insert(order, name) end
        end
    end
    local entry, category = self.kinds[kind], self:Category(kind, key)
    add(self.leading)
    add(entry and entry.sections)
    add(category and category.sections)
    add(self.trailing)
    return order
end

function BugReport:Gather(name, subject)
    local builder = self.builders[name]
    if not builder then return name, { "(no such section)" } end
    local ok, result = pcall(builder[2], subject, self)
    if not ok then return builder[1], { "Could not be read: " .. plain(result) } end
    return builder[1], result or {}
end

-- The kit's own sections ------------------------------------------------------

function BugReport.PlayerLines(_, reports)
    local recorder = reports.recorder
    local session = recorder and recorder:Describe() or {}
    return {
        string.format("%s-%s: %s %s %s, level %s", tostring(session.character), tostring(session.realm), tostring(session.faction),
            tostring(session.race), tostring(session.class), tostring(session.level)),
        string.format("XP %s / %s", tostring(session.xp), tostring(session.xpMax)),
        string.format("Client %s build %s (%s), TOC %s, locale %s", tostring(session.client), tostring(session.build),
            tostring(session.buildDate), tostring(session.toc), tostring(session.locale)),
    }
end

function BugReport.RecorderLines(_, reports)
    local recorder = reports.recorder
    if not recorder then return { "No session log." } end
    return recorder:DiagnosticLines()
end

function BugReport.RecentLines(_, reports)
    local recorder = reports.recorder
    local rows = recorder and recorder:Records(reports.recentChannel) or {}
    if #rows == 0 then return { "Nothing recorded (the session log may be off in Options)." } end
    local lines = {}
    for position = math.max(1, #rows - BugReport.recentRows + 1), #rows do
        local row = rows[position]
        local described
        if reports.describeRecord then
            local ok, value = pcall(reports.describeRecord, row)
            if ok then described = value end
        end
        local text, stamp
        if type(described) == "table" then
            text, stamp = described.text, described.time
        elseif type(described) == "string" then
            text = described
        end
        text = text or inline(row.d)
        stamp = stamp or tostring(row.at)
        local at = type(row.d) == "table" and type(row.d.at) == "table" and row.d.at
        table.insert(lines, tostring(stamp) .. " " .. plain(text)
            .. (at and string.format(" @ %s %s, %s", tostring(row.d.map), tostring(at[1]), tostring(at[2])) or ""))
    end
    return lines
end

-- Building and filing ---------------------------------------------------------

-- Builds a report. `request` is `{ kind, category, description, ... }`; the
-- rest (a step number, say) is for the addon's `subject`. Returns the report
-- as `{ lines = { ... }, text = "...", data = { ... } }`; `data` is what goes
-- on the session log: the fields worth filtering on, and the lines themselves.
function BugReport:Build(request)
    request = request or {}
    local kind = self.kinds[request.kind] and request.kind or self.defaultKind or self.kindOrder[1]
    local entry = kind and self.kinds[kind]
    local category = self:Category(kind, request.category)
        or (entry and entry.categories[#entry.categories])
        or { key = "other", label = "Something else" }
    local description = tostring(request.description or ""):gsub("^%s+", ""):gsub("%s+$", "")

    -- The subject is read under pcall like any section: the part that says
    -- what the report is about can be the part that is broken.
    local subject, subjectError
    if self.subjectSource then
        local ok, value = pcall(self.subjectSource, request)
        if ok then subject = value else subjectError = value end
    end

    local lines = {
        string.format("%s %s report: %s", self.name, tostring(kind or "addon"), category.label),
        string.format("%s, %s %s", clock(), self.name, tostring(self.version)),
        "",
        description ~= "" and description or "(no description given)",
    }
    if subjectError then
        table.insert(lines, "")
        table.insert(lines, "What the report is about could not be read: " .. plain(subjectError))
    end
    for _, name in ipairs(self:Sections(kind, category.key)) do
        local title, body = self:Gather(name, subject)
        if #body > 0 then
            table.insert(lines, "")
            table.insert(lines, "== " .. title .. " ==")
            for _, line in ipairs(body) do table.insert(lines, tostring(line)) end
        end
    end

    local data = {
        kind = kind,
        category = category.key,
        description = description,
        version = self.version,
    }
    if self.fieldsSource then
        local ok, fields = pcall(self.fieldsSource, subject, request)
        if ok and type(fields) == "table" then
            for key, value in pairs(fields) do
                if data[key] == nil then data[key] = value end
            end
        end
    end
    -- The report as the player saw it, line for line, so the tools print it
    -- back in the same order.
    data.lines = lines
    return { lines = lines, text = table.concat(lines, "\n"), data = data }
end

-- Builds a report and writes it to the session log's `bug` channel.
function BugReport:File(request)
    local report = self:Build(request)
    report.record = self.recorder and self.recorder:RecordHere("bug", report.data) or nil
    self.sessionCount = self.sessionCount + 1
    return report
end
