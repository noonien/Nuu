local _, ns = ...

local Kit = ns.Kit
local UI = Kit.UI
local Custom, has = UI.Custom, UI.HasFlag
local EVENTS, PARTS, FRAME = Custom.events, Custom.parts, Custom.frame
-- A flag's name, for the log.
local NAMES = { [EVENTS] = "Custom.events", [PARTS] = "Custom.parts", [FRAME] = "Custom.frame" }

-- Development only, never shipped: the reset audit. A released widget is
-- reset only as far as its marks ask (w:Customize, UI/Base/Core.lua). While
-- the audit is on, every client method that changes a widget is watched,
-- and a call from outside the kit's UI files is noted with the reset it
-- needs. On release the notes are held against the marks, and the log gets
--   missing    a change the marks do not undo: it reaches the next use
--   unneeded   a mark that nothing in that use needed: a reset for nothing
--   broader    Custom.frame where Custom.events would do
--   never      a change no reset undoes (an animation group)
--   released   a widget changed after it was cleared
-- Every finding is an error, every time, and is counted in the log too.
-- What is found at a call (bad flags to Customize, a change no reset
-- undoes, a change after a clear) is raised with error() at the addon's
-- line. What is found on release goes to the client's error handler
-- (geterrorhandler: the error frame, or BugSack), which does not unwind:
-- an error() there would stop a Clear half-way and leave its stack and the
-- pools broken. On from NuuKit.lua; `/nuukit audit` lists the log, `on`,
-- `off`, `clear`. It needs debugstack and shared methods, and slows every
-- change made to a widget.

UI.audit = false
UI.auditLog = {}
local byKey = {}

-- The reset each method needs: a flag, false for none (the kit sets it on
-- every use), "never" for none that could. Unlisted changes need FRAME.
-- SetAlpha and SetScale are the widget's own (UI/Base/Core.lua), and need
-- no mark: the audit never sees them.
local NEEDS = {
    RegisterEvent = EVENTS, RegisterUnitEvent = EVENTS, RegisterAllEvents = EVENTS,
    UnregisterEvent = EVENTS, UnregisterAllEvents = EVENTS,
    CreateTexture = PARTS, CreateFontString = PARTS, CreateLine = PARTS, CreateMaskTexture = PARTS,
    CreateAnimationGroup = "never",
    SetPoint = false, ClearAllPoints = false, SetAllPoints = false, ClearPoint = false,
    SetSize = false, SetWidth = false, SetHeight = false,
    SetParent = false, SetFrameLevel = false, Raise = false, Lower = false,
}
local CREATES = { CreateTexture = true, CreateFontString = true, CreateLine = true, CreateMaskTexture = true }
-- Methods that change a frame, by their names.
local CHANGES = { "^Set", "^Enable", "^Disable", "^Register", "^Unregister", "^Hook", "^Create", "^Clear",
    "^Lock", "^Unlock", "^Raise$", "^Lower$" }

local function changes(name)
    for _, pattern in ipairs(CHANGES) do
        if name:find(pattern) then return true end
    end
    return false
end

-- The kit's UI files, from where this file sits: "NuuKit/UI/" (only the
-- last folder, as the client may shorten a long path at its start).
local kitUI
do
    local line = debugstack and (debugstack(1, 1, 0) or ""):gsub("\\", "/") or ""
    local before = line:match("^(.-)Dev/Audit%.lua")
    local root = before and before:match("([^/%[\"@]+/)$")
    kitUI = root and (root:gsub("^%.+", "") .. "UI/")
end

-- A C function or a tail call counts as the kit's: nothing to answer for.
local function isKit(line)
    line = line:gsub("\\", "/")
    if not line:find("%.lua") then return true end
    return line:find(kitUI, 1, true) ~= nil
end

-- "NuuRoad/UI/Tracker.lua:120" from a line of debugstack.
local function place(line)
    line = line:gsub("\\", "/")
    local at = line:match("([^%s\"%[%]@]+%.lua\"?%]?:%d+)")
    if not at then return line end
    return (at:gsub("\"%]", ""):gsub("^Interface/AddOns/", ""))
end

-- Where the addon's code called in from: the first line of the stack
-- outside the kit, from the caller of the function that asks.
function UI.AuditCaller()
    for line in (debugstack(3, 12, 0) or ""):gmatch("[^\n]+") do
        if line:find("%.lua") and not isKit(line) then return place(line) end
    end
    return "the kit"
end

local PREFIX = "NuuKit audit: "

-- Counts the finding, and answers its error message.
local function log(key, text)
    local entry = byKey[key]
    if entry then
        entry.count = entry.count + 1
    else
        entry = { key = key, text = text, count = 1 }
        byKey[key] = entry
        UI.auditLog[#UI.auditLog + 1] = entry
    end
    return PREFIX .. text
end

-- A finding on release: to the error handler, and the release goes on.
local function report(key, text)
    local message = log(key, text)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(message) else error(message, 0) end
end

-- Customize's flags, from Core.lua: a number made of Custom's flags, each
-- once, or nothing. Raised at the addon's line.
function UI.AuditFlags(flags)
    if flags == nil then return end
    local ok = type(flags) == "number" and flags >= 1 and flags <= EVENTS + PARTS + FRAME and flags % 1 == 0
    if not ok then
        error(log("flags|" .. tostring(flags), string.format(
            "Customize(%s) at %s: flags are ui.Custom's (events, parts, frame), each added once",
            tostring(flags), UI.AuditCaller())), 3)
    end
end

local function note(w, name, need, line)
    local what = name .. " at " .. place(line)
    if w.kitPooled then
        return log("released|" .. what, string.format(
            "%s: %s after it was cleared; the frame may already be another widget", w.kitType, what))
    end
    if need == false then return end
    if need == "never" then
        return log("never|" .. what, string.format(
            "%s: %s is never undone on release; make it on a frame of your own", w.kitType, what))
    end
    local touched = w.kitTouched
    if not touched then
        touched = {}
        w.kitTouched = touched
    end
    touched[need] = touched[need] or what
end

-- The kit's own texture or text, made after the widget was: marked, so the
-- look for an addon's parts on release passes over it. One per client
-- method.
local marking = {}
local function markingFor(fn)
    local marker = marking[fn]
    if not marker then
        marker = function(self, ...)
            local part = fn(self, ...)
            if part then part.kitOwn = true end
            return part
        end
        marking[fn] = marker
    end
    return marker
end

-- No wrapping: while the audit is on, a class's metatable answers through
-- an __index function instead of its method table. Lua runs it in the frame
-- of the code looking the method up, so debugstack names the caller, and
-- it gets the widget itself. A change from outside the kit is noted on the
-- widget, and the client's own method goes back unchanged. The kit's own
-- methods (those in the class's table) pass straight through. A lookup
-- counts as a call: `if w.SetBackdrop then` from an addon is noted too.
local watched = {}
local isChange = {}

local function watch(class)
    if watched[class] then return end
    local index = class.__index
    if type(index) ~= "table" then return end
    watched[class] = index
    class.__index = function(frame, name)
        local fn = index[name]
        if type(fn) ~= "function" or type(name) ~= "string" or rawget(index, name) ~= nil then return fn end
        local change = isChange[name]
        if change == nil then
            change = changes(name)
            isChange[name] = change
        end
        if not change then return fn end
        local line = debugstack(2, 1, 0) or ""
        if isKit(line) then
            if CREATES[name] then return markingFor(fn) end
            return fn
        end
        local need = NEEDS[name]
        if need == nil then need = FRAME end
        -- A change no reset undoes, or one after a clear: raised at the
        -- addon's line, before the change is made.
        local problem = note(frame, name, need, line)
        if problem then error(problem, 2) end
        return fn
    end
end

local function unwatch(class)
    local index = watched[class]
    if not index then return end
    class.__index = index
    watched[class] = nil
end

UI.OnClass = function(class)
    if UI.audit then watch(class) end
end

-- Turns the audit on or off; answers whether it is on. Off without
-- debugstack, and with methods copied onto frames (nothing to watch).
function UI.SetAudit(on)
    on = on and debugstack ~= nil and kitUI ~= nil and UI.sharedMethods ~= false
    UI.audit = on and true or false
    for _, byBase in pairs(UI.classes) do
        for _, class in pairs(byBase) do
            if on then watch(class) else unwatch(class) end
        end
    end
    return UI.audit
end

-- On release, before any reset: the notes of this use (by flag) against
-- its marks (a number of flags).
function UI.AuditRelease(w, marks)
    local touched, markedAt = w.kitTouched, w.kitMarkedAt
    w.kitTouched = nil
    -- A frame or text made on it some other way (CreateFrame with it as the
    -- parent) is found by looking.
    if not (touched and touched[PARTS]) and UI.HasStrays(w) then
        touched = touched or {}
        touched[PARTS] = "a frame or region made on it outside the kit (the widget made at "
            .. tostring(w.kitMadeAt) .. ")"
    end
    touched = touched or {}
    local kind = w.kitType
    for need, what in pairs(touched) do
        if not has(marks, need) and not (need == EVENTS and has(marks, FRAME)) then
            report("missing|" .. need .. "|" .. what, string.format("%s: %s, not marked: w:Customize(ui.%s) before it",
                kind, what, NAMES[need]))
        end
    end
    for _, flag in ipairs({ EVENTS, PARTS, FRAME }) do
        if has(marks, flag) and not touched[flag] then
            local where = markedAt and markedAt[flag] or "?"
            if flag == FRAME and touched[EVENTS] then
                report("broader|" .. where, string.format("%s: marked Custom.frame at %s; Custom.events is enough",
                    kind, where))
            else
                report("unneeded|" .. flag .. "|" .. where, string.format(
                    "%s: marked %s at %s, and nothing in that use needed it", kind, NAMES[flag], where))
            end
        end
    end
end

function UI.ClearAudit()
    UI.auditLog = {}
    byKey = {}
end

-- The log as lines, most frequent first.
function UI.AuditLines()
    local entries = {}
    for index, entry in ipairs(UI.auditLog) do entries[index] = entry end
    table.sort(entries, function(a, b) return a.count > b.count end)
    local lines = {}
    for _, entry in ipairs(entries) do lines[#lines + 1] = string.format("%dx %s", entry.count, entry.text) end
    return lines
end

-- `/nuukit audit [on | off | clear]`; anything else goes to the handlers
-- before this one.
if type(SlashCmdList) == "table" then
    local before = SlashCmdList.NUUKIT
    SLASH_NUUKIT1 = SLASH_NUUKIT1 or "/nuukit"
    SlashCmdList.NUUKIT = function(message)
        local command, rest = (message or ""):lower():match("^%s*(%S*)%s*(%S*)")
        if command ~= "audit" then
            if before then before(message) end
            return
        end
        if rest == "on" or rest == "off" then
            print("NuuKit audit: " .. (UI.SetAudit(rest == "on") and "on" or "off"))
        elseif rest == "clear" then
            UI.ClearAudit()
            print("NuuKit audit: log cleared")
        else
            local lines = UI.AuditLines()
            print(string.format("NuuKit audit (%s): %d entries", UI.audit and "on" or "off", #lines))
            for _, line in ipairs(lines) do print("  " .. line) end
        end
    end
end
