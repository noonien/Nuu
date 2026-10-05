local addonName, ns = ...

-- Development only, never shipped. Each file in Experiments/ registers one
-- experiment with ns:Experiment; this file runs them and keeps what they saw
-- in NuuExperimentsDB.results[id], which the game writes to
-- WTF/Account/<account>/SavedVariables/NuuExperiments.lua on /reload or logout.
--
-- An experiment:
--   ns:Experiment({
--       id = "item-info",               -- key in NuuExperimentsDB.results
--       title = "Item info on a cold cache",
--       auto = "build",                 -- "build" (default): at login, once per client build
--                                       -- "login": at every login; false: only by /nuux run
--       combat = false,                 -- true lets it run in combat (default: waits until out)
--       run = function(t) ... end,      -- t: see Context below
--   })
--
-- Most experiments keep a few values in their result. One that collects data
-- in bulk (quest-scan, quest-record) keeps it in t:Data() instead: a plain
-- table under NuuExperimentsDB.data[id], not copied or cut, that outlives its
-- runs, so the next run carries on where the last one stopped.
--
-- Taking an experiment's file out of the TOC stops it loading and running;
-- its last results stay in the saved variables until /nuux prune.

ns.name = addonName
ns.version = "0.1.0-dev"
ns.experiments = {}
ns.order = {}

-- The one intentional global of this addon.
_G.NuuExperiments = ns

local MAX_DEPTH, MAX_ITEMS, MAX_LOG = 6, 200, 200
local DEFAULT_WAIT = 10
ns.LONG_RUN = 3 -- seconds a run may go on without saying how far it has got (t:Progress)

function ns:Print(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffNuuExperiments|r: " .. tostring(text))
    else
        print("NuuExperiments: " .. tostring(text))
    end
end

local function now()
    if type(debugprofilestop) == "function" then return debugprofilestop() end
    return os.clock() * 1000
end

ns.Now = now

local function stamp()
    if type(date) == "function" then return date("%Y-%m-%d %H:%M:%S") end
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- "1.60.1 (70058)", and the interface number.
function ns.Build()
    if type(GetBuildInfo) ~= "function" then return "unknown", nil end
    local version, build, _, interface = GetBuildInfo()
    return tostring(version) .. " (" .. tostring(build) .. ")", interface
end

local function character()
    if type(UnitName) ~= "function" then return nil end
    local name, realm = UnitName("player"), type(GetRealmName) == "function" and GetRealmName() or nil
    return realm and (tostring(name) .. "-" .. realm) or name
end

-- Saved variables hold only strings, numbers, booleans and tables of them:
-- anything else becomes its tostring with the type in front, and tables are
-- cut at MAX_DEPTH levels and MAX_ITEMS entries, cycles marked.
local function clean(value, depth, seen)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" or kind == "nil" then
        if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then
            return tostring(value)
        end
        return value
    end
    if kind ~= "table" then return "<" .. kind .. "> " .. tostring(value) end
    if seen[value] then return "<cycle>" end
    if depth >= MAX_DEPTH then return "<table, too deep>" end
    if type(value.GetObjectType) == "function" then
        local ok, objectType = pcall(value.GetObjectType, value)
        local okName, name = pcall(function() return value:GetName() end)
        return "<" .. (ok and tostring(objectType) or "widget") .. "> " .. tostring(okName and name or "")
    end
    seen[value] = true
    local out, count = {}, 0
    for k, v in pairs(value) do
        count = count + 1
        if count > MAX_ITEMS then
            out["<cut>"] = "more than " .. MAX_ITEMS .. " entries"
            break
        end
        local key = (type(k) == "string" or type(k) == "number") and k or tostring(k)
        out[key] = clean(v, depth + 1, seen)
    end
    seen[value] = nil
    return out
end
ns.Clean = function(value) return clean(value, 0, {}) end

local function pack(...) return { n = select("#", ...), ... } end

-- Every value returned, nils kept as the string "nil" so the count reads right.
local function returns(packed)
    local out = { n = packed.n }
    for i = 1, packed.n do
        local v = packed[i]
        out[i] = v == nil and "nil" or ns.Clean(v)
    end
    return out
end

local function trace(err)
    return tostring(err) .. "\n" .. ((debugstack and debugstack(2)) or (debug and debug.traceback and debug.traceback()) or "")
end

-- The events experiments wait on, shared by every run.
local listeners = {}
local eventFrame
local function eventFrameFor()
    if not eventFrame and type(CreateFrame) == "function" then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            local list = listeners[event]
            if not list then return end
            for i = #list, 1, -1 do
                local entry = list[i]
                if entry.ctx.finished then
                    table.remove(list, i)
                elseif entry.ctx:Call(entry.fn, event, ...) then
                    table.remove(list, i)
                end
            end
            if #list == 0 then
                listeners[event] = nil
                pcall(eventFrame.UnregisterEvent, eventFrame, event)
            end
        end)
    end
    return eventFrame
end

---------------------------------------------------------------------------
-- Context: the `t` an experiment's run gets.
---------------------------------------------------------------------------
local Context = {}
Context.__index = Context

-- Keep a value under a name (tables are copied into the saved variables).
function Context:Set(key, value)
    self.result.values[key] = ns.Clean(value)
    return value
end

-- A line for the run's log, string.format style.
function Context:Log(fmt, ...)
    local log = self.result.log
    if #log >= MAX_LOG then return end
    local text = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    log[#log + 1] = string.format("%.0fms %s", now() - self.started, text)
end

-- Call fn(...) and keep { ok, returns = {...} } or { ok = false, error } under
-- key. Returns what pcall returns, so the experiment can go on with the values.
function Context:Try(key, fn, ...)
    if type(fn) ~= "function" then
        self.result.values[key] = { ok = false, error = "not a function: " .. type(fn) }
        return false, "not a function"
    end
    local packed = pack(pcall(fn, ...))
    local entry = { ok = packed[1] }
    if packed[1] then
        entry.returns = returns(pack(select(2, unpack(packed, 1, packed.n))))
    else
        entry.error = tostring(packed[2])
    end
    self.result.values[key] = entry
    return unpack(packed, 1, packed.n)
end

-- What a dotted global name ("C_Item.GetItemInfo") is: its type, or "nil".
function ns.Lookup(path)
    local value = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

-- For each dotted name, keep its type under values.globals[name].
function Context:Exists(names)
    local globals = self.result.values.globals or {}
    self.result.values.globals = globals
    local found = {}
    for _, name in ipairs(names) do
        local value = ns.Lookup(name)
        globals[name] = value == nil and "nil" or type(value)
        found[name] = value ~= nil
    end
    return found
end

-- Run fn(self, ...) and keep its error, if any; true when it ran clean.
function Context:Call(fn, ...)
    local args = pack(...)
    local packed = pack(xpcall(function() return fn(unpack(args, 1, args.n)) end, trace))
    if not packed[1] then
        table.insert(self.result.errors, packed[2])
        return false
    end
    return unpack(packed, 2, packed.n)
end

-- The run goes on after run() returns: it ends at t:Done(), or as a
-- "timeout" after `seconds` (default 10).
function Context:Wait(seconds)
    self.waiting = true
    local token = {}
    self.waitToken = token
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(seconds or DEFAULT_WAIT, function()
            if not self.finished and self.waitToken == token then self:Finish("timeout") end
        end)
    end
end

-- How far a long run has got, for the window's progress bar: `done` of
-- `total`, and a line saying what ("120 of 6605 quests answered"). Every
-- experiment known to take longer than LONG_RUN seconds calls it; one that
-- does not gets a line in its log saying so.
function Context:Progress(done, total, label)
    self.progress = { done = done, total = total, label = label }
    if ns.Progressed then ns:Progressed(self.experiment.id) end
end

-- The run stays open for the rest of the session, listening, with no
-- timeout: status "watching" until logout or /nuux stop.
function Context:Keep()
    self.waiting = true
    self.waitToken = {}
    self.result.status = "watching"
end

-- This experiment's bulk data (NuuExperimentsDB.data[id]), kept across runs.
-- Only strings, numbers, booleans and tables of them belong in it.
function Context:Data()
    local data = ns:DB().data
    local id = self.experiment.id
    data[id] = type(data[id]) == "table" and data[id] or {}
    return data[id]
end

function Context:Done()
    if not self.finished then self:Finish() end
end

-- fn() after a delay, its errors kept on the run.
function Context:After(seconds, fn)
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        table.insert(self.result.errors, "C_Timer.After is missing")
        return
    end
    C_Timer.After(seconds, function()
        if not self.finished then self:Call(fn) end
    end)
end

-- fn(event, ...) on each event until it returns true or the run ends.
function Context:On(event, fn)
    local frame = eventFrameFor()
    if not frame then
        table.insert(self.result.errors, "CreateFrame is missing")
        return false
    end
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok then
        table.insert(self.result.errors, "RegisterEvent(" .. event .. "): " .. tostring(err))
        return false
    end
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], { ctx = self, fn = fn })
    return true
end

function Context:Finish(status)
    if self.finished then return end
    self.finished = true
    local result = self.result
    result.status = status or (#result.errors > 0 and "error" or "ok")
    result.ms = math.floor((now() - self.started) * 10 + 0.5) / 10
    if #result.errors == 0 then result.errors = nil end
    if #result.log == 0 then result.log = nil end
    ns.running[self.experiment.id] = nil
    local count = 0
    for _ in pairs(result.values) do count = count + 1 end
    ns:Print(string.format("%s: %s, %d value%s%s", self.experiment.id, result.status, count, count == 1 and "" or "s",
        result.errors and (", " .. #result.errors .. " error" .. (#result.errors == 1 and "" or "s")) or ""))
    if ns.Finished then ns:Finished(self.experiment.id) end
    if ns.Changed then ns:Changed() end
end

---------------------------------------------------------------------------
-- Registry and runs.
---------------------------------------------------------------------------
ns.running = {}

function ns:Experiment(spec)
    assert(type(spec) == "table" and type(spec.id) == "string", "an experiment needs an id")
    assert(type(spec.run) == "function", "experiment " .. spec.id .. " needs a run function")
    assert(not self.experiments[spec.id], "experiment registered twice: " .. spec.id)
    if spec.auto == nil then spec.auto = "build" end
    self.experiments[spec.id] = spec
    table.insert(self.order, spec.id)
    return spec
end

function ns:DB()
    NuuExperimentsDB = type(NuuExperimentsDB) == "table" and NuuExperimentsDB or {}
    NuuExperimentsDB.results = NuuExperimentsDB.results or {}
    NuuExperimentsDB.data = NuuExperimentsDB.data or {}
    return NuuExperimentsDB
end

-- Run one experiment now; its results replace the last ones.
function ns:Run(id)
    local experiment = self.experiments[id]
    if not experiment then
        self:Print("no experiment called \"" .. tostring(id) .. "\"")
        return nil
    end
    if self.running[id] then self.running[id]:Finish("replaced") end
    local build, interface = ns.Build()
    local result = {
        title = experiment.title,
        status = "running",
        build = build,
        interface = interface,
        date = stamp(),
        character = character(),
        inCombat = inCombat(),
        values = {},
        log = {},
        errors = {},
    }
    self:DB().results[id] = result
    local t = setmetatable({ experiment = experiment, result = result, started = now() }, Context)
    self.running[id] = t
    if self.Changed then self:Changed() end
    t:Call(experiment.run, t)
    if not t.waiting then
        t:Finish()
    elseif type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(ns.LONG_RUN, function()
            if self.running[id] == t and t.result.status == "running" and not t.progress then
                t:Log("still running after %d s without t:Progress: give it a progress bar", ns.LONG_RUN)
            end
        end)
    end
    return t
end

-- Ends a run that is still going (waiting, or watching): status "stopped".
function ns:Stop(id)
    local t = self.running[id]
    if not t then return false end
    t:Finish("stopped")
    return true
end

-- A run saved as still going ("running", "watching") was cut off by a reload
-- or logout: it says so, instead of looking busy forever. Runs going now
-- (none, after a real reload) are left alone.
function ns:MarkInterrupted()
    for id, result in pairs(self:DB().results) do
        if (result.status == "running" or result.status == "watching") and not self.running[id] then
            result.status = "interrupted"
            result.log = type(result.log) == "table" and result.log or {}
            table.insert(result.log, "the client reloaded or logged out before it ended")
        end
    end
end

local function due(experiment, results, build)
    if experiment.auto == "login" then return true end
    if experiment.auto ~= "build" then return false end
    local last = results[experiment.id]
    return not last or last.build ~= build or last.status == "interrupted"
end

-- The experiments due at login, out of combat unless they say otherwise.
local pending = {}
function ns:RunDue()
    local results, build = self:DB().results, ns.Build()
    for _, id in ipairs(self.order) do
        local experiment = self.experiments[id]
        if due(experiment, results, build) then
            if inCombat() and not experiment.combat then
                pending[id] = true
            else
                self:Run(id)
            end
        end
    end
    if next(pending) then self:Print("in combat: the rest run when it ends") end
end

function ns:RunPending()
    local ids = {}
    for _, id in ipairs(self.order) do
        if pending[id] then ids[#ids + 1] = id end
    end
    pending = {}
    for _, id in ipairs(ids) do self:Run(id) end
end

if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            ns:MarkInterrupted()
            -- A moment after login, so the experiments see a settled client.
            if type(C_Timer) == "table" and C_Timer.After then
                C_Timer.After(2, function() ns:RunDue() end)
            else
                ns:RunDue()
            end
        elseif next(pending) then
            ns:RunPending()
        end
    end)
end
