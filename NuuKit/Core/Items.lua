local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Item names, which the client loads on demand. On the Forever client (1.60.1,
-- docs/api-compatibility.md, "Item data loading") the global GetItemInfo is
-- gone, GET_ITEM_INFO_RECEIVED never comes, and RequestLoadItemDataByID is
-- answered by ITEM_DATA_LOAD_RESULT every time, within half a second (false
-- for an ID the server does not have). Both events are heard here, for any
-- client. Three calls:
--
--   Items:Preload(ids)   asks for the items not loaded yet; nothing back
--   Items:Name(id)       the name, or "Item <id>" while there is none (and
--                        the item is asked for)
--   Items:Track(fn)      runs fn; when a name it read through Name was not
--                        there, runs fn again once every one of them is in,
--                        and again while a run still misses one
--
-- Each item is asked for once a session, and asked again once if no answer
-- comes within ASK_AGAIN seconds; then it is given up. An item answered or
-- given up is settled: it is never asked for again and waits for nothing, so
-- Track's runs end. Answers to items not asked for here (tooltips, the
-- auction house, other addons) are ignored.
local Items = {}

local ASK_AGAIN, TRIES = 2, 2

-- itemID -> how many times asked, while its answer is awaited;
-- settled[itemID] once it came or was given up.
local pending, settled = {}, {}
-- Track: fn -> { [itemID] = true } its last run missed; itemID -> { [fn] = true }.
local missedBy, waitingOn = {}, {}
-- fn -> true while its next run is scheduled.
local scheduled = {}
-- The Track runs under way, innermost last.
local running = {}
local frame

local function C_ItemCall(name)
    local api = rawget(_G, "C_Item")
    return type(api) == "table" and api[name] or nil
end

local function after(seconds, fn)
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        timer.After(seconds, fn)
        return true
    end
    return false
end

local function report(err)
    local handler = rawget(_G, "geterrorhandler")
    if type(handler) == "function" then handler()(err) end
end

local function cachedName(itemID)
    local name = Kit.Read(C_ItemCall("GetItemNameByID"), itemID) or Kit.Read(rawget(_G, "GetItemInfo"), itemID)
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- What stands in for a name the client does not have.
function Items:StandIn(itemID)
    return "Item " .. tostring(itemID)
end

-- Forgets what fn's last run missed.
local function forget(fn)
    local missed = missedBy[fn]
    if not missed then return end
    for itemID in pairs(missed) do
        local fns = waitingOn[itemID]
        if fns then
            fns[fn] = nil
            if not next(fns) then waitingOn[itemID] = nil end
        end
    end
    missedBy[fn] = nil
end

-- fn runs again on the next tick, once however many answers came by then
-- (at once without C_Timer).
local function schedule(fn)
    if scheduled[fn] then return end
    scheduled[fn] = true
    local function again()
        if not scheduled[fn] then return end
        local ok, err = pcall(Items.Track, Items, fn)
        if not ok then report(err) end
    end
    if not after(0, again) then again() end
end

-- The item's answer came (or it was given up): every Track run that waited
-- on nothing else runs again.
local function settle(itemID)
    if settled[itemID] then return end
    pending[itemID], settled[itemID] = nil, true
    local tracked = waitingOn[itemID]
    waitingOn[itemID] = nil
    for fn in pairs(tracked or {}) do
        local missed = missedBy[fn]
        if missed then
            missed[itemID] = nil
            if not next(missed) then
                missedBy[fn] = nil
                schedule(fn)
            end
        end
    end
end

local function listen()
    if frame or type(CreateFrame) ~= "function" then return end
    frame = CreateFrame("Frame")
    pcall(frame.RegisterEvent, frame, "ITEM_DATA_LOAD_RESULT")
    pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(_, _, itemID)
        if pending[itemID] then settle(itemID) end
    end)
end

-- Sends the request; with no answer in time, the name may have come without
-- one, else it is asked again, then given up. False when it could not be sent.
local function send(itemID)
    local request = C_ItemCall("RequestLoadItemDataByID")
    if not request or not pcall(request, itemID) then return false end
    local tries = (pending[itemID] or 0) + 1
    pending[itemID] = tries
    after(ASK_AGAIN, function()
        if pending[itemID] ~= tries then return end
        if cachedName(itemID) or tries >= TRIES or not send(itemID) then settle(itemID) end
    end)
    return true
end

-- Asks for an item not loaded yet, once a session. True while its answer is
-- to come, false when there is nothing to wait for.
local function ask(itemID)
    if settled[itemID] then return false end
    if pending[itemID] then return true end
    listen()
    if send(itemID) then return true end
    settled[itemID] = true
    return false
end

function Items:Preload(ids)
    for _, itemID in ipairs(ids or {}) do
        if type(itemID) == "number" and not cachedName(itemID) then ask(itemID) end
    end
end

function Items:Name(itemID)
    if type(itemID) ~= "number" then return self:StandIn(itemID) end
    local name = cachedName(itemID)
    if name then return name end
    local fn = running[#running]
    if ask(itemID) and fn then
        local missed = missedBy[fn] or {}
        missedBy[fn] = missed
        missed[itemID] = true
        waitingOn[itemID] = waitingOn[itemID] or {}
        waitingOn[itemID][fn] = true
    end
    return self:StandIn(itemID)
end

-- fn is the key of its wait: pass the same function each time (a window's
-- draw, made once), so a run before the answers came replaces the last
-- run's wait instead of adding another. A name missed counts for the
-- innermost Track only. An error in fn is raised again once the run is
-- closed.
function Items:Track(fn)
    forget(fn)
    scheduled[fn] = nil
    running[#running + 1] = fn
    local ok, err = pcall(fn)
    running[#running] = nil
    if not ok then error(err, 0) end
end

Kit.Items = Items
