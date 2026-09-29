local Kit = _G.LoadKit().Kit
local Errors = Kit.Errors

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local clock = 1789862400
_G.time = function() return clock end

local roadDB, profDB = {}, {}
local road = Kit.NewRecorder({ db = function() return roadDB end })
local prof = Kit.NewRecorder({ db = function() return profDB end })
Errors.Watch("NuuRoad", road)
Errors.Watch("NuuProfessions", prof)

-- Whose an error is: the innermost watched addon its message or stack names.
local owners = Errors.Owners("Interface/AddOns/NuuRoad/UI/Tracker.lua:12: boom",
    "Interface/AddOns/NuuProfessions/Core.lua:3: in function")
assertEquals(#owners, 1, "one owner")
assertEquals(owners[1], "NuuRoad", "the addon the error was raised in")
owners = Errors.Owners("Interface/AddOns/NuuKit/UI/Base/Core.lua:5: bad", "...AddOns\\NuuProfessions\\UI\\Planner.lua:9: in function")
assertEquals(owners[1], "NuuProfessions", "a kit error goes to the addon that called the kit")
owners = Errors.Owners("Interface/AddOns/NuuKit/UI/Base/Core.lua:5: bad", "[C]: in function")
assertEquals(#owners, 2, "a kit error with no addon on the stack goes to every watched addon")
assertEquals(#Errors.Owners("Interface/AddOns/Details/boot.lua:1: nope", ""), 0, "anyone else's error is left alone")

-- Before the recorder opens its session the error waits, so it is not filed
-- under the session before.
Errors.Capture("Interface/AddOns/NuuRoad/Core.lua:1: early", "stack", nil, "lua")
assertEquals(road:Records("error") and #road:Records("error") or 0, 0, "nothing written before the session opens")
assertEquals(#Errors.pending, 1, "the error waits")
road.identity, prof.identity = {}, {}
Errors.Flush()
assertEquals(#Errors.pending, 0, "and is written once it opens")
assertEquals(road:Records("error")[1].d.message, "Interface/AddOns/NuuRoad/Core.lua:1: early", "on the error channel")

-- The same error again counts on its row rather than adding one.
local message = "Interface/AddOns/NuuRoad/UI/Tracker.lua:12: attempt to index a nil value"
Errors.Capture(message, "Interface/AddOns/NuuRoad/UI/Tracker.lua:12: in function <...>", string.rep("x", 5000), "lua")
clock = clock + 5
Errors.Capture(message, "another stack", nil, "lua")
local rows = road:Records("error")
assertEquals(#rows, 2, "one row per error message")
assertEquals(rows[2].d.count, 2, "counted twice")
assertEquals(rows[2].d.last, clock, "with when it was last seen")
assertEquals(#rows[2].d.locals, Errors.maxLocals, "locals are cut short")
assertEquals(rows[2].d.stack, "Interface/AddOns/NuuRoad/UI/Tracker.lua:12: in function <...>", "the first stack is kept")
assertEquals(prof:Records("error") and #prof:Records("error") or 0, 0, "the other addon's log is untouched")

-- A blocked call names the addon itself.
Errors.Blocked("ADDON_ACTION_BLOCKED", "NuuProfessions", "CastSpellByName()")
assertEquals(prof:Records("error")[1].d.kind, "blocked", "a blocked call on its addon's log")
Errors.Blocked("ADDON_ACTION_FORBIDDEN", "SomeoneElse", "Jump()")
assertEquals(#prof:Records("error"), 1, "and not someone else's")

-- With BugGrabber loaded, its announcements are read.
local callbacks = {}
_G.EventRegistry = { RegisterCallback = function(_, event, fn) callbacks[event] = fn end }
local grabbed = { message = "Interface/AddOns/NuuProfessions/UI/Planner.lua:40: bad plan", stack = "the stack",
    locals = "self = <table>", counter = 1 }
_G.BugGrabber = { GetDB = function() return { grabbed } end }
assertEquals(Errors.Install(), "BugGrabber", "BugGrabber's announcements when it is there")
callbacks["BugGrabber.BugGrabbed"](nil, tostring(grabbed))
local last = prof:Records("error")[#prof:Records("error")].d
assertEquals(last.message, grabbed.message, "a grabbed error is kept")
assertEquals(last.locals, "self = <table>", "with its locals")
callbacks["BugGrabber.BugGrabbed"](nil, "table: nowhere")
assertEquals(Errors.Install(), "BugGrabber", "installing twice does nothing")

-- Without it, the client's handler is wrapped and still called.
_G.BugGrabber = nil
Errors.via = nil
local shown, handler = {}, nil
_G.geterrorhandler = function() return handler or function(text) table.insert(shown, text) end end
_G.seterrorhandler = function(fn) handler = fn end
_G.debugstack = function() return "Interface/AddOns/NuuRoad/UI/Arrow.lua:7: in function" end
assertEquals(Errors.Install(), "error handler", "the handler is wrapped")
handler("Interface/AddOns/NuuRoad/UI/Arrow.lua:7: no arrow")
assertEquals(shown[1], "Interface/AddOns/NuuRoad/UI/Arrow.lua:7: no arrow", "the client still shows it")
rows = road:Records("error")
assertEquals(rows[#rows].d.message, "Interface/AddOns/NuuRoad/UI/Arrow.lua:7: no arrow", "and it is kept")

_G.time, _G.EventRegistry, _G.geterrorhandler, _G.seterrorhandler, _G.debugstack = nil, nil, nil, nil, nil
print("NuuKit errors tests passed")
