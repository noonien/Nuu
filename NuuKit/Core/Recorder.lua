local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- What the recent sessions saw, kept in an addon's saved variables.
--
-- Each addon makes its own recorder and keeps it in its own saved table; the
-- kit stores nothing. `options`:
--
--     db        function: the addon's account-wide saved table (`NuuRoadDB`),
--               or nil before it is loaded. The log goes in its `log` key
--               and the trace in its `trace` key.
--     keepDays  function: how many days of records the player keeps, read
--               from the addon's own settings. Nil or nonsense is read as
--               `defaultKeepDays`.
--     where     function: the player's map ID and position on it (0-1), or
--               nil. Without it, RecordHere records no position.
--     version   the addon's version, named in each session's identity.
--     log       function(message): where misuse is reported (`ns:Log`).
--     lasting   the channels age and Clear never drop (`lastingChannels`,
--               the bug reports, unless given).
--
-- The log runs across sessions: each login adds itself and carries on, and
-- records older than the days kept are dropped at login or when the player
-- asks. It is read from outside the game straight out of the saved file, and
-- in the game by diagnostics and bug reports.
--
-- The whole interface is one call (through `Kit.AddLogging`, from any file):
--
--     ns:Record("rec", { event = "accept", quest = 3091, npc = 3143 })
--     ns:Record("ui", "the browser was opened from the tracker")
--
-- A channel is a name. It does not have to be declared, it is created the
-- first time something is recorded to it, and it holds every record made to it
-- in the order they were made. Nothing is capped, and nothing is dropped but by
-- age: losing the row that explains a bug costs more than the bytes ever will.
--
-- A channel says which part of the addon spoke, not what kind of row it is.
-- The recorder itself writes `session` (logging in, reloading, logging out),
-- and bug reports write `bug`; every other name is the addon's.
--
-- A lasting channel is the exception to dropping by age: a bug report is read
-- whenever someone gets to it, which may be weeks later, so the `bug` channel
-- stays in the saved file until it is emptied by hand.
--
-- A record is two fields: when it happened, and what the caller had. There is
-- no sequence number and no offset into the session, because the position in
-- the list is the order and the wall clock is the time. What the caller had is
-- named the way a guide names it - `map`, `at`, `quest`, `npc` - so that a row
-- read months later reads like the thing it describes.
--
-- Nothing is written that could be worked out from what is already there. A
-- session begins with the identity record it puts on the `session` channel,
-- whose `at` is when it began, and the tools split the log into sessions there.
--
-- The trace
-- ---------
--
-- Beside the log sits a second, shorter-lived one: the trace, for what is
-- only worth reading while a bug is fresh.
--
--     ns:Trace("planner", { event = "plan", reason = "open", route = ... })
--
-- It takes the same channel names and the same data, through the same guard,
-- but it is kept by session: every login or reload opens a new trace session,
-- and when one opens the older ones are trimmed. A session that traced nothing
-- goes first, since it explains nothing and should not push out one that did.
-- Of the rest, every one begun in the last day is kept (`traceKeepHours`), so a
-- morning of reloads does not lose the morning's rows, and the last three are
-- kept however old (`traceSessions`), so a quiet week does not lose the last
-- bug. Over all that is a size guard: past `traceMaxRows` rows in the kept
-- sessions, the oldest go whatever their age, and the new session counts how
-- many sessions and rows went under its `trimmed`. The session being written
-- is never trimmed; whether it traced anything is judged at the next load.
-- `<db>.trace.sessions` holds them oldest first, each `{ at, identity,
-- channels = { [channel] = { {at, d}, ... } }, dropped = { [channel] = n },
-- trimmed = { sessions, rows } }`; the identity is a short one, since the
-- lasting log's `session` channel has the whole of it.
--
-- Which to use: Record for what should still explain something next week - a
-- session, a bug report, what the player did, a client read being measured.
-- Trace for the working of one part while it is being debugged: whole inputs,
-- whole results, every change - rows too big or too many to keep for days. A
-- trace channel is not capped, but one that runs away (more than
-- `traceRunaway` rows in a session) drops its oldest rows, a tenth at a time,
-- and counts them in `dropped`, so a loop cannot fill the saved file.
--
-- Pure apart from the client reads in `Describe` and whatever `where` does,
-- so the recording itself is testable outside the game.
local Recorder = {}
Recorder.__index = Recorder
Kit.Recorder = Recorder

-- What arbitrary data is allowed to be. The client's serializer will write
-- anything, so this bound is ours: it stops one careless call from nesting
-- past reading. There is no cap on how many entries a table may hold: a place
-- recorder's trail is thousands of samples, and a record is only as big as
-- what its caller chose to keep.
Recorder.maxDepth = 6
Recorder.defaultKeepDays = 10
Recorder.traceSessions = 3
Recorder.traceKeepHours = 24
Recorder.traceRunaway = 5000
-- Two runaway channels' worth: many times a day of ordinary debugging, and a
-- bound on the saved file when something runs away in session after session.
Recorder.traceMaxRows = 10000
Recorder.lastingChannels = { "bug" }

function Kit.NewRecorder(options)
    options = options or {}
    local lasting = {}
    for _, channel in ipairs(options.lasting or Recorder.lastingChannels) do lasting[channel] = true end
    return setmetatable({
        lasting = lasting,
        dbSource = options.db,
        keepDaysSource = options.keepDays,
        whereSource = options.where,
        version = options.version,
        logSink = options.log,
    }, Recorder)
end

local function round(value, places)
    local factor = 10 ^ (places or 1)
    return math.floor(value * factor + 0.5) / factor
end

Recorder.Round = round

-- The wall clock, which is the one thing a record cannot be given afterwards.
-- `time` is seconds since the epoch; the tools sort by it and pruning ages by it.
local function epoch()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return nil
end

function Recorder:DB()
    local source = self.dbSource
    if not source then return nil end
    local ok, db = pcall(source)
    if ok and type(db) == "table" then return db end
    return nil
end

function Recorder:Log(message)
    if self.logSink then pcall(self.logSink, message) end
end

function Recorder:Store()
    local db = self:DB()
    if not db then return nil end
    local store = db.log
    if type(store) ~= "table" then
        store = { channels = {} }
        db.log = store
    end
    store.channels = store.channels or {}
    return store
end

-- A channel name is read back by the tools as a plain word, so it is kept to
-- letters, digits, dash and underscore rather than trusted.
function Recorder:ValidChannel(channel)
    return type(channel) == "string" and channel ~= "" and #channel <= 40 and channel:match("^[%w_%-]+$") ~= nil
end

function Recorder:Records(channel)
    local store = self:Store()
    if not store or not self:ValidChannel(channel) then return nil end
    store.channels[channel] = store.channels[channel] or {}
    return store.channels[channel]
end

-- Makes arbitrary data safe to hand to the client's serializer.
--
-- Three things would otherwise cost a whole session's log at the moment it is
-- written. A cycle makes the writer recurse forever. A secret value throws the
-- moment it is used, and the throw happens at the write, not here. A function,
-- a frame or a userdata cannot be written at all. So the value is copied into
-- something known to be writable, and anything that is not becomes a short
-- word saying what was dropped.
function Recorder:Sanitize(value, depth, seen)
    depth = depth or 1
    if Kit.IsSecret(value) then return "<secret>" end
    local kind = type(value)
    if kind == "string" or kind == "boolean" then
        return value
    elseif kind == "number" then
        -- Neither of these survives a round trip through the saved file.
        if value ~= value then return "<nan>" end
        if value == math.huge or value == -math.huge then return "<inf>" end
        return value
    elseif kind == "nil" then
        return nil
    elseif kind ~= "table" then
        return "<" .. kind .. ">"
    end
    if depth > self.maxDepth then return "<deep>" end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local copy = {}
    for key, item in pairs(value) do
        local keyKind = type(key)
        if keyKind == "string" or keyKind == "number" then
            copy[key] = self:Sanitize(item, depth + 1, seen)
        end
    end
    seen[value] = nil
    return copy
end

-- The one call. Everything else here exists to serve it.
--
-- `data` is whatever the caller has; it is stored under `d` so it can never
-- collide with the stamp, and so a record can be a bare string or number as
-- easily as a table.
function Recorder:Record(channel, data)
    if not self:ValidChannel(channel) then
        self:Log("Record: '" .. tostring(channel) .. "' is not a usable channel name")
        return nil
    end
    local records = self:Records(channel)
    if not records then return nil end
    local record = { at = epoch(), d = self:Sanitize(data) }
    table.insert(records, record)
    return record
end

-- The trace ------------------------------------------------------------------

function Recorder:TraceStore()
    local db = self:DB()
    if not db then return nil end
    local store = db.trace
    if type(store) ~= "table" then
        store = { sessions = {} }
        db.trace = store
    end
    if type(store.sessions) ~= "table" then store.sessions = {} end
    return store
end

-- How many rows a trace session holds, across its channels.
local function traceRows(session)
    local rows = 0
    for _, records in pairs(type(session) == "table" and type(session.channels) == "table" and session.channels or {}) do
        if type(records) == "table" then rows = rows + #records end
    end
    return rows
end

-- Trims the sessions already kept, before this load's is added: the empty
-- ones go, then whatever is neither among the newest `traceSessions` nor
-- begun within `traceKeepHours` of `now`. Returns what is left, oldest first.
function Recorder:KeptTraces(sessions, now)
    local cutoff = now and now - self.traceKeepHours * 3600
    local kept, count = {}, 0
    for index = #sessions, 1, -1 do
        local session = sessions[index]
        if traceRows(session) > 0 then
            count = count + 1
            local at = session.at
            if count <= self.traceSessions or (cutoff and type(at) == "number" and at >= cutoff) then
                table.insert(kept, 1, session)
            end
        end
    end
    return kept
end

-- Opens a trace session for this UI load and trims the older ones (see the
-- trace, above). `identity` is what the session says about itself.
function Recorder:BeginTrace(identity)
    local store = self:TraceStore()
    if not store then return nil end
    local now = epoch()
    local kept = self:KeptTraces(store.sessions, now)
    -- The size guard: the oldest go first, whatever the rules above kept.
    local rows = 0
    for _, older in ipairs(kept) do rows = rows + traceRows(older) end
    local trimmed, trimmedRows = 0, 0
    while rows > self.traceMaxRows and #kept > 0 do
        local gone = traceRows(table.remove(kept, 1))
        rows = rows - gone
        trimmed, trimmedRows = trimmed + 1, trimmedRows + gone
    end
    local session = { at = now, identity = self:Sanitize(identity or {}), channels = {}, dropped = {} }
    if trimmed > 0 then
        session.trimmed = { sessions = trimmed, rows = trimmedRows }
        self:Log("trace: dropped the oldest " .. trimmed .. " sessions (" .. trimmedRows .. " rows) to keep the trace under " .. self.traceMaxRows .. " rows")
    end
    kept[#kept + 1] = session
    -- In place, so a reader holding the list sees the trimmed one.
    local sessions = store.sessions
    for index = #sessions, 1, -1 do sessions[index] = nil end
    for index, older in ipairs(kept) do sessions[index] = older end
    self.traceSession = session
    return session
end

-- The trace session this UI load writes to: nil before BeginTrace, and nil if
-- the store was replaced under it (the saved data reset).
function Recorder:CurrentTrace()
    local session = self.traceSession
    local db = session and self:DB()
    local store = db and db.trace
    if type(store) ~= "table" or type(store.sessions) ~= "table" then return nil end
    if store.sessions[#store.sessions] ~= session then return nil end
    return session
end

-- True while a trace would be kept, so a caller can skip building a big row.
function Recorder:Tracing()
    return self:CurrentTrace() ~= nil
end

-- Record's twin for the trace. Returns the record, whose `d` is the caller's
-- own copy: a field set on it afterwards is kept.
function Recorder:Trace(channel, data)
    if not self:ValidChannel(channel) then
        self:Log("Trace: '" .. tostring(channel) .. "' is not a usable channel name")
        return nil
    end
    local session = self:CurrentTrace()
    if not session then return nil end
    session.channels = session.channels or {}
    local records = session.channels[channel]
    if not records then
        records = {}
        session.channels[channel] = records
    end
    local record = { at = epoch(), d = self:Sanitize(data) }
    records[#records + 1] = record
    local cap = self.traceRunaway
    if #records > cap then
        -- A tenth at once, so a runaway channel does not shift the whole list
        -- at every row.
        local drop = #records - cap + math.floor(cap / 10)
        local kept = {}
        for index = drop + 1, #records do kept[#kept + 1] = records[index] end
        session.channels[channel] = kept
        session.dropped = session.dropped or {}
        session.dropped[channel] = (session.dropped[channel] or 0) + drop
    end
    return record
end

-- The trace session's own short identity, from the lasting log's.
local function traceIdentity(identity)
    identity = identity or {}
    return { character = identity.character, realm = identity.realm, level = identity.level,
        client = identity.client, build = identity.build, addon = identity.addon }
end

-- The same as Record, with where the player was standing folded into the
-- data. Position is the other thing a record cannot be given afterwards.
function Recorder:RecordHere(channel, data)
    local at = self:Where()
    if type(data) == "table" then
        for key, value in pairs(at) do
            if data[key] == nil then data[key] = value end
        end
        return self:Record(channel, data)
    elseif data ~= nil then
        at.what = data
    end
    return self:Record(channel, at)
end

-- Where the player stands, when the addon's `where` will say: a map ID and a
-- point on it, spelled `map` and `at = { x, y }` as a guide step spells them,
-- in map percent to two decimals.
function Recorder:Where()
    local fields = {}
    if not self.whereSource then return fields end
    local ok, mapID, x, y = pcall(self.whereSource)
    if not ok or type(mapID) ~= "number" then return fields end
    fields.map = mapID
    if type(x) == "number" and type(y) == "number" then
        fields.at = { round(x * 100, 2), round(y * 100, 2) }
    end
    return fields
end

-- How many records the log holds, and how many sessions they span.
function Recorder:Survey()
    local store = self:Store()
    local kept, sessions = 0, 0
    for channel, records in pairs(store and store.channels or {}) do
        kept = kept + #records
        if channel == "session" then
            for _, record in ipairs(records) do
                if type(record.d) == "table" and record.d.event == nil then sessions = sessions + 1 end
            end
        end
    end
    return kept, sessions
end

-- Adds this session to the log without disturbing what is there. Returns the
-- session block and the number of records it found already written.
function Recorder:Begin(identity)
    local store = self:Store()
    if not store then return nil end
    return identity or {}, (self:Survey())
end

-- How many days of records the player keeps; a nonsense value is read as
-- the default.
function Recorder:KeepDays()
    local days
    if self.keepDaysSource then
        local ok, value = pcall(self.keepDaysSource)
        if ok then days = tonumber(value) end
    end
    if not days or days < 1 then days = self.defaultKeepDays end
    return math.floor(days)
end

-- Drops every record older than `days` (the player's setting when omitted).
-- A channel is in the order its records were made, so what goes is a run at
-- its front: everything up to the last record stamped before the cutoff,
-- including an unstamped one among them. A channel left empty goes too.
-- A lasting channel is left as it is. Returns how many records were dropped.
function Recorder:Prune(days, now)
    local store = self:Store()
    now = now or epoch()
    if not store or not now then return 0 end
    local cutoff = now - (days or self:KeepDays()) * 86400
    local dropped = 0
    for channel, records in pairs(store.channels) do
        -- A lasting channel is kept whatever its age.
        if not self.lasting[channel] then
            local last = 0
            for index, record in ipairs(records) do
                local at = type(record) == "table" and record.at
                if type(at) == "number" then
                    if at >= cutoff then break end
                    last = index
                end
            end
            if last > 0 then
                local kept = {}
                for index = last + 1, #records do kept[#kept + 1] = records[index] end
                store.channels[channel] = kept
                dropped = dropped + last
            end
            if #store.channels[channel] == 0 then store.channels[channel] = nil end
        end
    end
    return dropped
end

-- Empties the log (not the trace), but for the lasting channels. Returns how
-- many records went.
function Recorder:Clear()
    local store = self:Store()
    if not store then return 0 end
    local before = self:Survey()
    local kept = {}
    for channel in pairs(self.lasting) do kept[channel] = store.channels[channel] end
    self:DB().log = nil
    self:Store().channels = kept
    return before - (self:Survey())
end

-- Who was playing, on what, and when. Read once at login.
--
-- Three groups, in this order: the player, the client, the addon. Lua does
-- not keep the order a table was written in, so the order here is for whoever
-- reads the code.
--
-- Every read is guarded: a client that will not answer leaves the field out
-- rather than failing the login.
function Recorder:Describe()
    local read = Kit.Read
    -- Both answer the printed name first and the token second, and the token
    -- is the one worth keeping: it is the same in every locale.
    local class, race
    if type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, "player")
        if ok and not Kit.IsSecret(token) then class = token end
    end
    if type(UnitRace) == "function" then
        local ok, _, token = pcall(UnitRace, "player")
        if ok and not Kit.IsSecret(token) then race = token end
    end

    local version, build, buildDate, toc
    if type(GetBuildInfo) == "function" then
        local ok, a, b, c, d = pcall(GetBuildInfo)
        if ok then version, build, buildDate, toc = a, b, c, d end
    end

    return {
        -- When this happened is the record's own `at`, and the session is named
        -- from it, so nothing here says the time again.
        --
        -- The player. The GUID is the only name that survives a rename, which
        -- is what ties one character's sessions together across the log.
        character = read(rawget(_G, "UnitName"), "player"),
        realm = read(rawget(_G, "GetRealmName")),
        guid = read(rawget(_G, "UnitGUID"), "player"),
        faction = read(rawget(_G, "UnitFactionGroup"), "player"),
        race = race,
        class = class,
        level = read(rawget(_G, "UnitLevel"), "player"),
        -- Experience is only readable against the bar it sits in, so both.
        xp = read(rawget(_G, "UnitXP"), "player"),
        xpMax = read(rawget(_G, "UnitXPMax"), "player"),

        -- The client, and which build of the addon was talking to it.
        client = version,
        build = build,
        buildDate = buildDate,
        toc = toc,
        locale = read(rawget(_G, "GetLocale")),
        addon = self.version,
    }
end

-- Starts this UI load's session: prunes the log, records who is playing,
-- opens a trace session, and watches arriving and leaving. Call once, at
-- PLAYER_LOGIN, after the addon's saved variables are loaded.
function Recorder:Initialize()
    local dropped = self:Prune()
    if dropped > 0 then self:Log("session log: dropped " .. dropped .. " records older than " .. self:KeepDays() .. " days") end
    local identity = self:Begin(self:Describe())
    self.identity = identity
    -- The identity, first of all: it opens the session, and its clock is when
    -- the session began.
    self:Record("session", identity)
    -- A new trace session: login or reload is filled in when the client
    -- says which, at the first PLAYER_ENTERING_WORLD.
    local trace = self:BeginTrace(traceIdentity(identity))

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function(_, event, first, second)
        if event == "PLAYER_ENTERING_WORLD" then
            -- The client says outright whether this was a fresh login or a
            -- reload, so a session labels itself rather than being matched up
            -- afterwards with what the player remembers doing.
            self:RecordHere("session", { event = "entering", login = first and true or false, reload = second and true or false })
            if trace and trace.identity and trace.identity.login == nil then
                trace.identity.login = first and true or false
                trace.identity.reload = second and true or false
            end
        elseif event == "PLAYER_LOGOUT" then
            self:RecordHere("session", { event = "logout" })
        end
    end)
    self.frame = frame
end

-- What the log and the trace hold, for a diagnostics command or a bug report.
function Recorder:DiagnosticLines()
    local store = self:Store()
    local session = self.identity or {}
    local kept, sessions = self:Survey()
    local lines = {
        "Character: " .. tostring(session.character) .. "-" .. tostring(session.realm) .. " (" .. tostring(session.faction) .. " " .. tostring(session.race) .. " " .. tostring(session.class) .. " " .. tostring(session.level) .. ")",
        "Client: " .. tostring(session.client) .. " build " .. tostring(session.build) .. ", addon " .. tostring(session.addon),
        "Sessions in this log: " .. tostring(sessions) .. ", records older than " .. self:KeepDays() .. " days are dropped",
        "Records in the log: " .. tostring(kept),
    }
    local names = {}
    for channel in pairs((store and store.channels) or {}) do table.insert(names, channel) end
    table.sort(names)
    for _, channel in ipairs(names) do
        table.insert(lines, string.format("  %-12s %5d kept%s", channel, #store.channels[channel],
            self.lasting[channel] and " (never dropped)" or ""))
    end
    local traces = self:TraceStore()
    local keptTraces = traces and #traces.sessions or 0
    table.insert(lines, "Trace sessions kept: " .. keptTraces .. " (the last " .. self.traceKeepHours .. " hours, at least "
        .. self.traceSessions .. " that traced something, at most " .. self.traceMaxRows .. " rows)")
    local current = self:CurrentTrace()
    if current then
        local trimmed = current.trimmed
        if trimmed then
            table.insert(lines, "  " .. tostring(trimmed.sessions) .. " oldest sessions (" .. tostring(trimmed.rows) .. " rows) dropped for size at this load")
        end
        local traced = {}
        for channel in pairs(current.channels or {}) do table.insert(traced, channel) end
        table.sort(traced)
        if #traced == 0 then table.insert(lines, "  nothing traced this session") end
        for _, channel in ipairs(traced) do
            local dropped = current.dropped and current.dropped[channel]
            table.insert(lines, string.format("  %-12s %5d traced this session%s", channel, #current.channels[channel],
                dropped and (", " .. dropped .. " oldest dropped") or ""))
        end
    end
    table.insert(lines, "SavedVariables reach disk at logout or /reload.")
    return lines
end
