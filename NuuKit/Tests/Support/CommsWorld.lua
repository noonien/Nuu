-- A stand-in for the client calls Kit.NewComms reaches, and the small test
-- harness the comms suites share. From Sonar's tests/lib (framework and wow).
--
--     local W = dofile("Tests/Support/CommsWorld.lua")
--     local world = W.new({ modern = true })
--     world:inbound("NuuTest", payload, "PARTY", "Alice")
--     world.clock:advance(30)
--     world.timers:lastTimer().fn()
--     world:remove()
--
-- new() installs every call in _G and remove() puts back what was there, so
-- the suites that follow (the UI smoke suite installs its own frame API) see
-- the globals as they were. Nothing fires on its own: a test runs the timer it
-- wants and fires the event it wants.
--
-- Names are as the client gives them: the realm is "Spineshatter", the player
-- is "Me", and an addon-message sender is always Name-Realm.

local M = {}

M.REALM = "Spineshatter"
M.PLAYER = "Me"

--------------------------------------------------------------------------------
-- Suites and checks. A suite groups tests; before and after run around each
-- test of the suite (after runs even when the test failed). The first failure
-- stops the file with the suite and test named.
--------------------------------------------------------------------------------

local current
M.count = 0

function M.suite(name, body)
    current = { name = name, before = {}, after = {} }
    body()
    current = nil
end

function M.before(fn) table.insert(current.before, fn) end
function M.after(fn) table.insert(current.after, fn) end

local function trace(message)
    return debug.traceback(tostring(message), 2)
end

function M.test(name, body)
    M.count = M.count + 1
    local suite = current or { before = {}, after = {} }
    local ok, err = true, nil
    for _, fn in ipairs(suite.before) do
        ok, err = xpcall(fn, trace)
        if not ok then break end
    end
    if ok then ok, err = xpcall(body, trace) end
    for _, fn in ipairs(suite.after) do
        local afterOk, afterErr = xpcall(fn, trace)
        if ok and not afterOk then ok, err = false, afterErr end
    end
    if not ok then
        error((suite.name and (suite.name .. " / ") or "") .. name .. ": " .. tostring(err), 0)
    end
end

function M.ok(condition, message)
    if not condition then error(message or "assertion failed", 2) end
    return true
end

function M.eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s (got %s, expected %s)", message or "values differ",
            tostring(actual), tostring(expected)), 2)
    end
    return true
end

function M.errors(fn, message)
    if pcall(fn) then error((message or "call was expected to raise") .. " (it returned)", 2) end
    return true
end

-- A recorder that stands in for a callback: calls, and the arguments of each.
function M.spy(fn)
    return setmetatable({ calls = 0, args = {} }, {
        __call = function(self, ...)
            self.calls = self.calls + 1
            self.args[self.calls] = { ... }
            if fn then return fn(...) end
        end,
    })
end

--------------------------------------------------------------------------------
-- The world
--------------------------------------------------------------------------------

local World = {}
World.__index = World

function World:set(name, value)
    if self._saved[name] == nil then self._saved[name] = { _G[name] } end
    _G[name] = value
end

function World:remove()
    for name, box in pairs(self._saved) do _G[name] = box[1] end
    self._saved = {}
end

-- Runs the clock `seconds` on, firing each timer as it falls due, in the
-- order they fall due (one made while running fires too, if it is due).
function World:run(seconds)
    local stop = self.clock.now + (seconds or 0)
    while true do
        local soonest
        for _, entry in ipairs(self.timers.timers) do
            if not entry.cancelled and (not soonest or entry.at < soonest.at) then soonest = entry end
        end
        if not soonest or soonest.at > stop then break end
        self.clock.now = math.max(self.clock.now, soonest.at)
        soonest.cancelled = true
        soonest.fn()
    end
    self.clock.now = stop
end

-- Every frame that registered the event gets it, in the order they were made.
function World:fire(event, ...)
    for _, frame in ipairs(self.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

function World:registered(event)
    for _, frame in ipairs(self.frames) do
        if frame.events[event] then return true end
    end
    return false
end

-- An addon message as the client hands it over: the sender qualified with
-- our realm unless it already carries one.
function World:inbound(prefix, payload, source, sender)
    if sender and not sender:find("-", 1, true) then sender = sender .. "-" .. M.REALM end
    self:fire("CHAT_MSG_ADDON", prefix, payload, source, sender)
end

local function newClock()
    local clock = { now = 1000 }
    function clock:advance(seconds)
        self.now = self.now + (seconds or 1)
        return self.now
    end
    return clock
end

local function newTimers(clock)
    local timers = { timers = {} }

    local function handle(list, delay, fn)
        local entry = { delay = delay, at = clock.now + delay, fn = fn, cancelled = false }
        function entry:Cancel() self.cancelled = true end
        list[#list + 1] = entry
        return entry
    end

    function timers:lastTimer(delay)
        for i = #self.timers, 1, -1 do
            if delay == nil or self.timers[i].delay == delay then return self.timers[i] end
        end
    end

    -- Only the call the comms uses, so a test can see it needs no other.
    timers.api = {
        NewTimer = function(delay, fn) return handle(timers.timers, delay, fn) end,
    }
    return timers
end

-- options.modern: C_ChatInfo carries addon messages and prefixes beside the
-- bare globals, as on the anniversary client.
function M.new(options)
    options = options or {}
    local w = setmetatable({
        _saved = {},
        frames = {},
        sent = {},        -- SendAddonMessage calls
        cSent = {},       -- C_ChatInfo.SendAddonMessage calls
        prefixes = {},    -- C_ChatInfo.RegisterAddonMessagePrefix calls
        legacyPrefixes = {}, -- RegisterAddonMessagePrefix calls
    }, World)
    w.clock = newClock()
    w.timers = newTimers(w.clock)
    local clock = w.clock

    -- events.NAME(...) fires NAME; it is nil while no frame registered NAME.
    w.events = setmetatable({}, { __index = function(_, event)
        if not w:registered(event) then return nil end
        return function(...) w:fire(event, ...) end
    end })

    w:set("wipe", function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end)
    w:set("GetServerTime", function() return clock.now end)
    w:set("GetTime", function() return clock.now end)
    w:set("time", function() return clock.now end)
    w:set("C_Timer", w.timers.api)
    w:set("GetNormalizedRealmName", function() return M.REALM end)
    w:set("UnitName", function(unit) if unit == "player" then return M.PLAYER end end)

    w:set("CreateFrame", function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(name, fn) self.scripts[name] = fn end
        w.frames[#w.frames + 1] = frame
        return frame
    end)

    local function recorder(list)
        return function(prefix, payload, distribution, target)
            list[#list + 1] = {
                prefix = prefix, payload = payload, distribution = distribution, target = target,
            }
        end
    end
    w:set("SendAddonMessage", recorder(w.sent))
    w:set("RegisterAddonMessagePrefix", function(prefix)
        w.legacyPrefixes[#w.legacyPrefixes + 1] = prefix
    end)
    if options.modern then
        w:set("C_ChatInfo", {
            SendAddonMessage = recorder(w.cSent),
            RegisterAddonMessagePrefix = function(prefix) w.prefixes[#w.prefixes + 1] = prefix end,
        })
    else
        w:set("C_ChatInfo", nil)
    end
    return w
end

return M
