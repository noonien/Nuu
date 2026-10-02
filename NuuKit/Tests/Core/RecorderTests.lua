local Kit = _G.LoadKit().Kit

-- The wall clock is the recorder's only reading of the world besides position,
-- so the test owns it.
_G.time = function() return 1789862400 end
_G.date = function(format) return format == "%z" and "+0300" or "2026-09-21 19:00:00" end

local frames = {}
local previousCreateFrame = CreateFrame
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(name, handler) self.scripts[name] = handler end
    table.insert(frames, frame)
    return frame
end

-- One value the client keeps secret, the way the real one does for anything
-- an addon is not meant to know.
local secretValue = setmetatable({}, {})
_G.issecretvalue = function(value) return value == secretValue end

-- What the addon hands the recorder: its saved table, its setting for the
-- days kept, where the player stands, its version, and its debug log.
local db, settings, logs = {}, {}, {}
local place = { map = 1411, x = 0.432, y = 0.601 }
local Recorder = Kit.NewRecorder({
    db = function() return db end,
    keepDays = function() return settings.keepDays end,
    where = function() return place.map, place.x, place.y end,
    version = "test",
    log = function(message) table.insert(logs, message) end,
})

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

-- The trace is written only into a session this UI load opened: before one
-- is, tracing keeps nothing and says so.
assertEquals(Recorder:Trace("planner", { event = "early" }), nil, "a trace before its session opens is not kept")
assertEquals(Recorder:Tracing(), false, "and tracing says it is off")
assertEquals(db.trace, nil, "nor does it make a store")

-- Before the addon's saved table exists nothing is kept, and nothing throws.
local early = Kit.NewRecorder({ db = function() return nil end })
assertEquals(early:Record("rec", { x = 1 }), nil, "no saved table, no record")
assertEquals(early:Prune(), 0, "and nothing to prune")
assertEquals(Kit.NewRecorder():Record("rec", 1), nil, "a recorder given nothing keeps nothing")

-- The whole interface: a channel name and whatever the caller has. A record is
-- two fields, and neither of them is a number the reader has to decode.
local record = Recorder:Record("rec", { event = "accept", quest = 3091 })
assertEquals(record.at, 1789862400, "the record is stamped with the wall clock")
assertEquals(record.seq, nil, "there is no sequence number")
assertEquals(record.t, nil, "and no offset into the session")
assertEquals(record.d.quest, 3091, "the caller's data is kept under d")
assertEquals(record.d.event, "accept", "all of it")
assertEquals(db.log.channels.rec[1], record, "in the addon's own saved table")

-- A channel does not have to be declared: recording to it creates it.
assertEquals(db.log.channels.somethingNew, nil, "an unused channel does not exist")
Recorder:Record("somethingNew", "a bare string is data too")
assertEquals(#Recorder:Records("somethingNew"), 1, "recording to a channel creates it")
assertEquals(Recorder:Records("somethingNew")[1].d, "a bare string is data too", "and the data need not be a table")

-- A channel name is read back as a plain word, so it is checked here.
assertEquals(Recorder:Record("../escape", { x = 1 }), nil, "a name that is not a plain word is refused")
assertEquals(Recorder:Record("", {}), nil, "and so is an empty one")
assertEquals(Recorder:Record(nil, {}), nil, "and so is no name at all")
assertEquals(#logs, 3, "each refusal is logged for the addon's debug output")

-- Arbitrary data means arbitrary depth. Nesting is kept as it was given.
local deep = Recorder:Record("any", { a = { b = { c = { d = "bottom" } } }, list = { 1, 2, 3 } })
assertEquals(deep.d.a.b.c.d, "bottom", "nested tables are kept")
assertEquals(deep.d.list[2], 2, "and so are arrays")

-- Three things would otherwise cost the whole log at the moment it is written.
-- A cycle would make the client's serializer recurse forever.
local loop = { name = "loop" }
loop.self = loop
local cycled = Recorder:Record("any", loop)
assertEquals(cycled.d.name, "loop", "a cycle does not stop the rest being kept")
assertEquals(cycled.d.self, "<cycle>", "and the loop itself is named rather than followed")

-- A secret value throws when it is used, and it would be used at the write.
local hidden = Recorder:Record("any", { marker = secretValue, plain = 7 })
assertEquals(hidden.d.marker, "<secret>", "a secret value is dropped before it can throw")
assertEquals(hidden.d.plain, 7, "without taking the rest of the record with it")

-- A function or a frame cannot be written to the saved file at all.
local odd = Recorder:Record("any", { fn = function() end, ok = "kept" })
assertEquals(odd.d.fn, "<function>", "what cannot be saved is named")
assertEquals(odd.d.ok, "kept", "and the rest survives")

-- Neither of these survives a round trip through the saved file.
local numbers = Recorder:Record("any", { nan = 0 / 0, big = math.huge })
assertEquals(numbers.d.nan, "<nan>", "not a number is written as a word")
assertEquals(numbers.d.big, "<inf>", "and neither is infinity")

-- Depth is bounded, so one careless call cannot fill the file.
local nested, leaf = {}, nil
leaf = nested
for _ = 1, 20 do leaf.next = {}; leaf = leaf.next end
leaf.bottom = true
local bounded = Recorder:Record("any", nested)
local walk, depth = bounded.d, 0
while type(walk) == "table" and walk.next do walk = walk.next; depth = depth + 1 end
assert(depth < 20, "the copy stops before the data does")
assertEquals(walk.next or walk, "<deep>", "and says where it stopped")

-- Position is the other thing a record cannot be given afterwards.
local here = Recorder:RecordHere("npc", { npc = 3143 })
assertEquals(here.d.npc, 3143, "the caller's data is kept")
assertEquals(here.d.map, 1411, "with the map folded in, named as a guide names it")
assertEquals(here.d.at[1], 43.2, "and the point, as map percent")
assertEquals(here.d.at[2], 60.1, "to two decimals")
local said = Recorder:RecordHere("npc", "a word")
assertEquals(said.d.what, "a word", "data that is not a table is kept beside the position")
place.x = nil
assertEquals(Recorder:RecordHere("npc", {}).d.at, nil, "a map without a position records the map alone")
place.map = nil
assertEquals(Recorder:RecordHere("npc", {}).d.map, nil, "and no map records neither")
local nowhere = Kit.NewRecorder({ db = function() return db end })
assertEquals(nowhere:RecordHere("npc", { npc = 1 }).d.map, nil, "an addon that gives no `where` records no position")
local throwing = Kit.NewRecorder({ db = function() return db end, where = function() error("no map yet") end })
assertEquals(throwing:RecordHere("npc", { npc = 2 }).d.npc, 2, "and a `where` that throws does not lose the record")
place.map, place.x = 1411, 0.432

-- Nothing is capped and nothing is dropped: a chatty channel keeps every row
-- it was given, in the order it was given them.
for index = 1, 5000 do Recorder:Record("chatty", { n = index }) end
local chatty = Recorder:Records("chatty")
assertEquals(#chatty, 5000, "every record is kept")
assertEquals(chatty[1].d.n, 1, "the oldest is still the first")
assertEquals(chatty[#chatty].d.n, 5000, "and the newest is still the last")

-- The log runs across sessions: a new one keeps what it finds.
local carriedRecords = Recorder:Survey()
assert(carriedRecords > 0, "there is something to find")
local identity, carried = Recorder:Begin({})
assertEquals(carried, carriedRecords, "the new session is told what it found")
assertEquals(identity.new, nil, "and says nothing about the load")
assertEquals(#Recorder:Records("chatty"), 5000, "nothing is dropped by beginning")

-- Records older than the days kept are dropped, oldest first, channel by
-- channel; what is left keeps its order and an emptied channel goes.
do
    local day = 86400
    local saved = db.log
    db.log = { channels = {
        old = { { at = 1000, d = 1 }, { at = 2000, d = 2 } },
        mixed = { { at = 1000, d = "a" }, { d = "unstamped" }, { at = 1000 + 5 * day, d = "b" }, { at = 1000 + 20 * day, d = "c" } },
        fresh = { { at = 1000 + 20 * day, d = "x" } },
        bug = { { at = 1000, d = "an old report" } },
    } }
    local now = 1000 + 20 * day
    assertEquals(Recorder:Prune(10, now), 5, "everything older than ten days goes")
    assertEquals(#db.log.channels.bug, 1, "but for a bug report, which is kept whatever its age")
    assertEquals(db.log.channels.old, nil, "a channel left empty goes too")
    assertEquals(#db.log.channels.mixed, 1, "an unstamped record among the old ones goes with them")
    assertEquals(db.log.channels.mixed[1].d, "c", "and the recent one stays")
    assertEquals(#db.log.channels.fresh, 1, "a recent channel is untouched")
    assertEquals(Recorder:Prune(10, now), 0, "pruning twice drops nothing more")
    assertEquals(Recorder:KeepDays(), 10, "with no setting chosen, ten days are kept")
    settings.keepDays = 30
    assertEquals(Recorder:KeepDays(), 30, "the addon's setting is used")
    settings.keepDays = 0
    assertEquals(Recorder:KeepDays(), 10, "and a nonsense one falls back to ten days")
    settings.keepDays = "7.9"
    assertEquals(Recorder:KeepDays(), 7, "a number in words is read, whole days only")
    settings.keepDays = nil
    db.log = saved
end

-- Who was playing, on what, and when. Read once at login.
_G.GetBuildInfo = function() return "1.60.1", "69913", "Sep 21 2026", 16001 end
_G.UnitName = function() return "Dill Douse" end
_G.UnitGUID = function() return "Player-1-0000ABCD" end
_G.UnitClass = function() return "Druid", "DRUID", 11 end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
_G.UnitLevel = function() return 13 end
_G.UnitXP = function() return 4210 end
_G.UnitXPMax = function() return 9400 end
_G.UnitFactionGroup = function() return "Horde" end
_G.GetRealmName = function() return "Classic Beta PvP" end
_G.GetLocale = function() return "enUS" end
-- Nothing in the block says when it happened or what it is called: the record
-- carries the clock, and the session is split out of the log there.
local about = Recorder:Describe()
assertEquals(about.id, nil, "the session does not name itself")
assertEquals(about.started, nil, "nor time itself")
assertEquals(about.character, "Dill Douse", "the character is named")
assertEquals(about.realm, "Classic Beta PvP", "with its realm")
assertEquals(about.guid, "Player-1-0000ABCD", "and the one name that survives a rename")
assertEquals(about.faction, "Horde", "the faction")
assertEquals(about.race, "Tauren", "the race token")
assertEquals(about.class, "DRUID", "the class token rather than the printed word")
assertEquals(about.level, 13, "the level")
assertEquals(about.xp, 4210, "the experience")
assertEquals(about.xpMax, 9400, "against the bar it sits in")
assertEquals(about.client, "1.60.1", "the client version")
assertEquals(about.build, "69913", "the build a bug report is indexed by")
assertEquals(about.buildDate, "Sep 21 2026", "when that build was made")
assertEquals(about.toc, 16001, "the interface number")
assertEquals(about.locale, "enUS", "the locale")
assertEquals(about.addon, "test", "and which build of the addon was running")

-- A client that will not answer leaves the field out rather than failing the
-- login.
_G.UnitName = function() return secretValue end
_G.UnitClass = function() return "Druid", secretValue end
_G.GetRealmName = nil
local guarded = Recorder:Describe()
assertEquals(guarded.character, nil, "a secret answer is left out")
assertEquals(guarded.class, nil, "a secret token too")
assertEquals(guarded.realm, nil, "and so is a call the client does not have")
_G.UnitName = function() return "Dill Douse" end
_G.UnitClass = function() return "Druid", "DRUID", 11 end
_G.GetRealmName = function() return "Classic Beta PvP" end

-- Clearing is the one thing that empties the log, and it leaves the bug
-- reports.
Recorder:Record("bug", { description = "kept" })
local before = Recorder:Survey()
local cleared = Recorder:Clear()
assertEquals(cleared, before - 1, "clearing reports what it threw away")
assertEquals(Recorder:Survey(), 1, "and the log is empty afterwards but for the report")
assertEquals(Recorder:Records("bug")[1].d.description, "kept", "which is kept as it was")
db.log.channels.bug = nil
local lastingNone = Kit.NewRecorder({ db = function() return db end, lasting = {} })
lastingNone:Record("bug", "gone")
lastingNone:Clear()
assertEquals(lastingNone:Survey(), 0, "an addon can say no channel lasts")

-- Initialize registers for events rather than assuming any of them fire.
Recorder:Initialize()
local frame = frames[#frames]
assert(frame.events.PLAYER_LOGOUT, "logout is watched")
assert(frame.events.PLAYER_ENTERING_WORLD, "entering the world is watched")

-- The session's own description is recorded first of all: it opens the
-- session, and its clock is when the session began.
local sessionRows = Recorder:Records("session")
assertEquals(sessionRows[1].d.character, "Dill Douse", "the identity is recorded as well as stored")
assertEquals(sessionRows[1].at, 1789862400, "and it is the first thing on the channel")

-- The client's own word for what kind of arrival this was.
frame.scripts.OnEvent(frame, "PLAYER_ENTERING_WORLD", false, true)
sessionRows = Recorder:Records("session")
assertEquals(sessionRows[#sessionRows].d.event, "entering", "arriving is recorded")
assertEquals(sessionRows[#sessionRows].d.reload, true, "and the client says it was a reload")
assertEquals(sessionRows[#sessionRows].d.map, 1411, "with where it happened")

frame.scripts.OnEvent(frame, "PLAYER_LOGOUT")
sessionRows = Recorder:Records("session")
assertEquals(sessionRows[#sessionRows].d.event, "logout", "and leaving is recorded")
assertEquals(#sessionRows, 3, "the session is three rows")
assertEquals(frame.scripts.OnUpdate, nil, "and nothing samples a position")

-- The trace ---------------------------------------------------------------

-- Initialize opened a trace session, with a short identity of its own that
-- learns login or reload when the client says which.
local traces = db.trace.sessions
assertEquals(#traces, 1, "the load opened one trace session")
assertEquals(traces[1].identity.character, "Dill Douse", "which names the character")
assertEquals(traces[1].identity.build, "69913", "and the build")
assertEquals(traces[1].identity.xp, nil, "and keeps the identity short")
assertEquals(traces[1].identity.reload, true, "and learned it was a reload")
assertEquals(traces[1].at, 1789862400, "and is stamped with when it began")

-- Tracing writes to the current session, on its own channels, apart from the
-- lasting log.
assertEquals(Recorder:Tracing(), true, "tracing is on once a session is open")
local traced = Recorder:Trace("planner", { event = "plan", fn = function() end, deep = { secret = secretValue } })
assertEquals(traced.at, 1789862400, "a trace row is stamped like a record")
assertEquals(traced.d.event, "plan", "and keeps the caller's data under d")
assertEquals(traced.d.fn, "<function>", "through the same guard")
assertEquals(traced.d.deep.secret, "<secret>", "all of it")
assertEquals(traces[1].channels.planner[1], traced, "it lands on the session's channel")
assertEquals(db.log.channels.planner, nil, "and not in the lasting log")
traced.d.message = "said afterwards"
assertEquals(traces[1].channels.planner[1].d.message, "said afterwards", "a field set on the returned row is kept")
assertEquals(Recorder:Trace("../nope", {}), nil, "a bad channel name is refused as for Record")

-- Each load opens another, and tracing writes to the newest.
local first = Recorder:CurrentTrace()
_G.time = function() return 1789862401 end
Recorder:BeginTrace({ n = 2 })
Recorder:Trace("planner", "into the second")
assertEquals(#db.trace.sessions, 2, "a second load keeps the first")
assertEquals(db.trace.sessions[1], first, "oldest first")
assertEquals(db.trace.sessions[2].channels.planner[1].d, "into the second", "tracing writes to the newest")
assertEquals(#first.channels.planner, 1, "and leaves the older ones alone")

-- A session that traced nothing is dropped at the next load, and does not
-- count toward the sessions kept, so reloads that traced nothing cannot push
-- out one that did.
Recorder.traceKeepHours = 0
for n = 3, 8 do
    _G.time = function() return 1789862400 + n end
    Recorder:BeginTrace({ n = n })
end
local sessions = db.trace.sessions
assertEquals(#sessions, 3, "empty sessions are dropped and the current is kept")
assertEquals(sessions[1], first, "the first, which traced, survives six empty loads")
assertEquals(sessions[2].identity.n, 2, "and so does the second")
assertEquals(sessions[3].identity.n, 8, "beside the current, empty as it is")
assertEquals(Recorder:CurrentTrace(), sessions[3], "which is the one written to")

-- Past the day kept, the newest three that traced something are kept.
Recorder:Trace("planner", "into the eighth")
_G.time = function() return 1789862409 end
Recorder:BeginTrace({ n = 9 })
Recorder:Trace("planner", "into the ninth")
_G.time = function() return 1789862410 end
Recorder:BeginTrace({ n = 10 })
sessions = db.trace.sessions
assertEquals(#sessions, 4, "three that traced, and the current")
assertEquals(sessions[1].identity.n, 2, "the oldest that traced goes first")
assertEquals(sessions[3].identity.n, 9, "the newest that traced last")
assertEquals(sessions[4].identity.n, 10, "then the current")
Recorder.traceKeepHours = nil

-- Within the day kept, every session that traced is kept, however many.
local timeDB = {}
local timed = Kit.NewRecorder({ db = function() return timeDB end })
local hour = 3600
for n = 1, 8 do
    _G.time = function() return 1789862400 + n * hour end
    timed:BeginTrace({ n = n })
    timed:Trace("planner", n)
end
_G.time = function() return 1789862400 + 24 * hour end
timed:BeginTrace({ n = 9 })
assertEquals(#timeDB.trace.sessions, 9, "eight sessions in the last day are kept, with the current")
_G.time = function() return 1789862400 + 25 * hour + 1 end
timed:BeginTrace({ n = 10 })
-- The tenth found the ninth empty, and the first older than a day; the next
-- seven are within it.
sessions = timeDB.trace.sessions
assertEquals(#sessions, 8, "a session older than the day goes once three newer traced")
assertEquals(sessions[1].identity.n, 2, "the oldest left is within the day")
assertEquals(sessions[8].identity.n, 10, "and the current is last")

-- Older than the day, it is trimmed to the newest three that traced.
_G.time = function() return 1789862400 + 100 * hour end
timed:BeginTrace({ n = 11 })
sessions = timeDB.trace.sessions
assertEquals(#sessions, 4, "a day later, three that traced and the current")
assertEquals(sessions[1].identity.n, 6, "the newest three")
assertEquals(sessions[3].identity.n, 8, "that traced")
assertEquals(sessions[4].identity.n, 11, "and the current")

-- The size guard drops the oldest sessions past the rows kept, even within
-- the day and even below three, says so on the new session, and never drops
-- the current.
local sizeDB, sizeLogs = {}, {}
local sized = Kit.NewRecorder({ db = function() return sizeDB end, log = function(message) table.insert(sizeLogs, message) end })
sized.traceMaxRows = 10
for n = 1, 3 do
    _G.time = function() return 1789862400 + n end
    sized:BeginTrace({ n = n })
    for row = 1, 4 do sized:Trace("planner", row) end
end
assertEquals(#sizeDB.trace.sessions[3].channels.planner, 4, "the current session is written past the cap")
_G.time = function() return 1789862404 end
local fourth = sized:BeginTrace({ n = 4 })
sessions = sizeDB.trace.sessions
assertEquals(#sessions, 3, "twelve rows over ten drops the oldest session")
assertEquals(sessions[1].identity.n, 2, "the oldest goes first")
assertEquals(fourth.trimmed.sessions, 1, "the new session says how many sessions went")
assertEquals(fourth.trimmed.rows, 4, "and how many rows")
assert(sizeLogs[1] and sizeLogs[1]:find("dropped the oldest 1 sessions", 1, true), "and the log says so")
for row = 1, 30 do sized:Trace("planner", row) end
_G.time = function() return 1789862405 end
local fifth = sized:BeginTrace({ n = 5 })
sessions = sizeDB.trace.sessions
assertEquals(#sessions, 1, "a session past the cap on its own drops every older one at the next load")
assertEquals(sessions[1], fifth, "leaving only the current")
assertEquals(fifth.trimmed.sessions, 3, "counted")
assertEquals(fifth.trimmed.rows, 38, "with their rows")
for row = 1, 30 do sized:Trace("planner", row) end
assertEquals(sized:CurrentTrace(), fifth, "and the current is never dropped, however big")
assertEquals(#fifth.channels.planner, 30, "nor cut but by the runaway mark")
assertEquals(Kit.Recorder.traceMaxRows, 10000, "setting one recorder's cap leaves the others'")
_G.time = function() return 1789862400 end

-- A trace channel is not capped, but one that runs away drops its oldest
-- rows and counts them. The limit is per recorder.
Recorder.traceRunaway = 100
assertEquals(Kit.Recorder.traceRunaway, 5000, "setting one recorder's limit leaves the others'")
for index = 1, 100 do Recorder:Trace("loop", index) end
local current = Recorder:CurrentTrace()
assertEquals(#current.channels.loop, 100, "up to the runaway mark everything is kept")
assertEquals(current.dropped.loop, nil, "and nothing is counted dropped")
Recorder:Trace("loop", 101)
local loopRows = current.channels.loop
assert(#loopRows <= 100, "past it the channel is cut back")
assertEquals(loopRows[#loopRows].d, 101, "keeping the newest")
assertEquals(loopRows[1].d, 101 - #loopRows + 1, "and dropping from the front")
assertEquals(current.dropped.loop, 101 - #loopRows, "and the count says how many went")
for index = 102, 150 do Recorder:Trace("loop", index) end
assertEquals(current.channels.loop[#current.channels.loop].d, 150, "writing carries on")
assertEquals(current.dropped.loop + #current.channels.loop, 150, "and every row is either kept or counted")
Recorder.traceRunaway = nil

-- The store replaced under it (the saved data reset) stops tracing rather
-- than writing into a table nothing will save.
local savedTrace = db.trace
db.trace = nil
assertEquals(Recorder:Trace("planner", "lost"), nil, "a replaced store is not written to")
db.trace = savedTrace

-- Two addons, two recorders, two saved tables: neither writes into the other.
local otherDB = {}
local other = Kit.NewRecorder({ db = function() return otherDB end, version = "other" })
other:Record("rec", "theirs")
assertEquals(#otherDB.log.channels.rec, 1, "the other addon's record is in its own table")
assertEquals(db.log.channels.rec, nil, "and not in this one, whose `rec` was cleared")
assertEquals(other:Tracing(), false, "and its trace is its own")

-- The diagnostics name the sessions kept and this session's channels.
local diagnostic = table.concat(Recorder:DiagnosticLines(), "\n")
assert(diagnostic:find("Trace sessions kept: 4 (the last 24 hours, at least 3 that traced something, at most 10000 rows)", 1, true), "the diagnostics count the trace sessions")
assert(diagnostic:find("loop", 1, true) and diagnostic:find("oldest dropped", 1, true), "and this session's channels")

CreateFrame = previousCreateFrame
_G.issecretvalue = nil
print("NuuKit recorder tests passed")
