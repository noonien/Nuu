local _, ns = ...

local Kit = ns.Kit

-- Development only, never shipped: every Lua error a Nuu addon raises, kept
-- in that addon's session log on the `error` channel, so a session's errors
-- can be read back with the rest of it (`sessions.py --errors`) instead of
-- only while the error frame or BugSack is open.
--
-- Each addon hands over its recorder from a debug block in its Core.lua:
--
--     if ns.Kit.Errors then ns.Kit.Errors.Watch(addonName, ns.recorder) end
--
-- and NuuKit.lua turns the watch on (Errors.Install). An error belongs to the
-- first watched addon whose folder its message and stack name, innermost
-- first; one raised in the kit's own files with no addon further up the
-- stack goes to every watched addon. Errors from anyone else are left alone.
--
-- Where the errors come from: !BugGrabber, when it is loaded, owns the error
-- handler and makes seterrorhandler do nothing, but announces every error it
-- grabs on EventRegistry ("BugGrabber.BugGrabbed"), stack and locals and all.
-- Without it the client's handler is wrapped, and still called. Either way
-- the error frame or BugSack shows the error as before. ADDON_ACTION_BLOCKED
-- and ADDON_ACTION_FORBIDDEN name the addon outright and are watched too.
--
-- One row per error message per session: the same error again (an OnUpdate
-- that throws every frame) adds to the row's `count` and moves its `last`,
-- rather than filling the log. An error before the addon's recorder has
-- opened this session (Recorder:Initialize, at login) waits, and is written
-- once it has, so it is not filed under the session before.
local Errors = {
    watched = {},   -- addon name -> recorder
    order = {},     -- the watched names, in the order they asked
    rows = {},      -- addon name -> { [message] = the row written this session }
    pending = {},   -- { addon, data } waiting for a saved table
}
Kit.Errors = Errors

-- How much of an error's locals a row keeps; the stack is kept whole.
Errors.maxLocals = 4000

local function epoch()
    local ok, value = pcall(time)
    return ok and value or nil
end

function Errors.Watch(addon, recorder)
    if type(addon) ~= "string" or type(recorder) ~= "table" then return end
    if not Errors.watched[addon] then table.insert(Errors.order, addon) end
    Errors.watched[addon] = recorder
    Errors.rows[addon] = Errors.rows[addon] or {}
end

-- Where `name`'s folder first appears in `text`, or nil.
local function position(text, name)
    local slash = text:find(name .. "/", 1, true)
    local back = text:find(name .. "\\", 1, true)
    if slash and back then return math.min(slash, back) end
    return slash or back
end

-- The addons an error belongs to, from its message and stack.
function Errors.Owners(message, stack)
    local text = tostring(message) .. "\n" .. tostring(stack or "")
    local best, at
    for _, name in ipairs(Errors.order) do
        local found = position(text, name)
        if found and (not at or found < at) then best, at = name, found end
    end
    if best then return { best } end
    if position(text, "NuuKit") then
        local all = {}
        for _, name in ipairs(Errors.order) do all[#all + 1] = name end
        return all
    end
    return {}
end

-- Writes (or counts again) one error on one addon's log. False while its
-- recorder has not opened this session.
local function write(addon, data)
    local recorder = Errors.watched[addon]
    if not recorder.identity then return false end
    local seen = Errors.rows[addon]
    local row = seen[data.message]
    if row and type(row.d) == "table" then
        row.d.count = (row.d.count or 1) + 1
        row.d.last = epoch()
        return true
    end
    row = recorder:RecordHere("error", data)
    if not row then return false end
    seen[data.message] = row
    return true
end

function Errors.Flush()
    local waiting = Errors.pending
    Errors.pending = {}
    for _, entry in ipairs(waiting) do
        if not write(entry[1], entry[2]) then table.insert(Errors.pending, entry) end
    end
end

-- One error, from wherever it was caught. `kind` says which (`lua`,
-- `blocked`); `locals` is optional.
function Errors.Capture(message, stack, locals, kind)
    if Kit.IsSecret(message) then return end
    message = tostring(message)
    if Kit.IsSecret(stack) then stack = "<secret>" end
    if Kit.IsSecret(locals) then locals = nil end
    local owners = Errors.Owners(message, stack)
    if #owners == 0 then return end
    Errors.Flush()
    locals = type(locals) == "string" and locals ~= "" and locals:sub(1, Errors.maxLocals) or nil
    for _, addon in ipairs(owners) do
        local data = { message = message, stack = type(stack) == "string" and stack or nil, locals = locals,
            kind = kind or "lua", count = 1 }
        if not write(addon, data) then table.insert(Errors.pending, { addon, data }) end
    end
end

-- A blocked or forbidden call, named by the client: to that addon, or to
-- every watched one when it names the kit.
function Errors.Blocked(event, addon, func)
    addon = tostring(addon)
    local message = string.format("%s: %s tried to call %s", tostring(event), addon, tostring(func))
    local owners
    if Errors.watched[addon] then
        owners = { addon }
    elseif addon == "NuuKit" then
        owners = Errors.order
    else
        return
    end
    Errors.Flush()
    local stack = type(debugstack) == "function" and debugstack(2) or nil
    for _, name in ipairs(owners) do
        local data = { message = message, stack = stack, kind = "blocked", count = 1 }
        if not write(name, data) then table.insert(Errors.pending, { name, data }) end
    end
end

-- One BugGrabber error object, by the id it announces.
local function grabbed(id)
    local grabber = rawget(_G, "BugGrabber")
    local db = grabber and grabber.GetDB and grabber:GetDB()
    for index = #(db or {}), 1, -1 do
        local object = db[index]
        if tostring(object) == id then return object end
    end
    return nil
end

-- Turns the watch on, once. Called from NuuKit.lua.
function Errors.Install()
    if Errors.via then return Errors.via end
    local registry = rawget(_G, "EventRegistry")
    if rawget(_G, "BugGrabber") and registry and registry.RegisterCallback then
        registry:RegisterCallback("BugGrabber.BugGrabbed", function(_, id)
            pcall(function()
                local object = grabbed(id)
                if object then Errors.Capture(object.message, object.stack, object.locals, "lua") end
            end)
        end, Errors)
        Errors.via = "BugGrabber"
    elseif type(geterrorhandler) == "function" and type(seterrorhandler) == "function" then
        local previous = geterrorhandler()
        seterrorhandler(function(message, ...)
            -- Level 2 is where the error was raised. No locals: only
            -- BugGrabber reads them at the right level.
            local stack = type(debugstack) == "function" and debugstack(2) or nil
            pcall(Errors.Capture, message, stack, nil, "lua")
            if previous then return previous(message, ...) end
        end)
        Errors.via = "error handler"
    else
        Errors.via = "nothing"
    end

    if type(CreateFrame) == "function" then
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("ADDON_ACTION_BLOCKED")
        frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
        -- After every addon's PLAYER_LOGIN, so their recorders have begun.
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:SetScript("OnEvent", function(_, event, addon, func)
            if event == "PLAYER_ENTERING_WORLD" then
                pcall(Errors.Flush)
            else
                pcall(Errors.Blocked, event, addon, func)
            end
        end)
        Errors.frame = frame
    end
    return Errors.via
end
