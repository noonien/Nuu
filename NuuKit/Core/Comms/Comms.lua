local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Comms/Comms.lua: addon messages between players of one addon, in a
-- whisper, the party, the raid or the guild. From Sonar's Comms module.
--
--     local comms = ns.Kit.NewComms({
--         prefix = "NuuRoad",                          -- addon-message prefix, at most 16 characters
--         log = function(message) ns:Log(message) end, -- optional
--         muted = function(key) return ... end,        -- optional: the player's refused senders
--     })
--     comms:RegisterReceiver(function(who, payload, source) ... end, "PARTY")  -- every source if none
--     comms:SetEnabled(true)
--     comms:Send(Kit.Comms.Writer():U(MSG_HELLO):Finish(), "PARTY")
--     comms:Send(payload, "WHISPER", "Name")
--
-- A receiver gets who = { key, name } (key lower case, for lookups; name as
-- the client spelled it, realm dropped), the payload, and how the client
-- delivered it (WHISPER, PARTY, RAID, GUILD...). It reads with
-- Kit.Comms.Reader(payload) and may return Kit.Comms.VIOLATION; repeated
-- violations mute that sender on that source for the session. Message types
-- are the addon's: the comms knows senders and limits only.
--
-- comms:Sender(distribution, target, options) is a reusable destination with
-- an optional delay policy (initialDelay, initialJitter, repeatDelay,
-- repeatJitter). Sender:Send(payload) queues one message; SendMultiple(fn)
-- calls fn whenever the destination can send, until fn returns nil. All
-- senders to one destination share one throttle.
--
-- Each instance keeps its own queues and mutes, so two addons sharing the kit
-- in development stay apart; give each its own prefix. Nothing is sent or
-- received until SetEnabled(true), and it refuses (returns false) on a client
-- without the calls it needs (Kit.Comms.Supported()).

local Comms = Kit.Comms or {}
Kit.Comms = Comms

-- Where a message can go. CHANNEL (a custom chat channel) is left out.
Comms.DISTRIBUTIONS = {
    WHISPER = true, PARTY = true, RAID = true, GUILD = true, OFFICER = true,
    BATTLEGROUND = true, INSTANCE_CHAT = true,
}

local function Global(path)
    local value = _G
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

-- The client calls the comms cannot work without, missing ones by name.
local REQUIRED = { "C_Timer.NewTimer", "GetTime", "CreateFrame" }

function Comms.Supported()
    local missing = {}
    for _, name in ipairs(REQUIRED) do
        if type(Global(name)) ~= "function" then missing[#missing + 1] = name end
    end
    if type(Global("C_ChatInfo.SendAddonMessage")) ~= "function"
        and type(Global("SendAddonMessage")) ~= "function" then
        missing[#missing + 1] = "SendAddonMessage"
    end
    return #missing == 0, missing
end

local Instance = {}
Instance.__index = Instance

function Kit.NewComms(spec)
    assert(type(spec) == "table", "NewComms needs a spec")
    assert(type(spec.prefix) == "string" and #spec.prefix >= 1 and #spec.prefix <= 16,
        "comms prefix must be 1 to 16 characters")

    local C = setmetatable({ prefix = spec.prefix }, Instance)
    -- What the parts of one instance share and the addon never sees.
    local P = {
        prefix = spec.prefix,
        enabled = false,
        receivers = {},
        log = spec.log,
        muted = spec.muted or function() return false end,
    }
    C._p = P

    function P.debug(message, ...)
        if not P.log then return end
        if select("#", ...) > 0 then message = message:format(...) end
        pcall(P.log, "comms: " .. message)
    end

    -- Events, one frame per instance, made on first use.
    local handlers, frame = {}, nil
    function P.on(event, fn)
        if not frame then
            frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", function(_, name, ...)
                local list = handlers[name]
                for i = 1, #list do list[i](...) end
            end)
        end
        if not handlers[event] then
            handlers[event] = {}
            frame:RegisterEvent(event)
        end
        local list = handlers[event]
        list[#list + 1] = fn
    end

    -- Names. The client hands addon senders over as Name-Realm. A sender from
    -- another realm is refused (nil): the key has no realm in it.
    local realm
    function P.realm()
        if realm then return realm end
        local name = Kit.Read(GetNormalizedRealmName)
        if not name then
            name = Kit.Read(GetRealmName)
            name = name and name:gsub("[%s%-]", "")
        end
        if name and name ~= "" then realm = name end
        return realm
    end

    function P.key(name)
        return name:lower()
    end

    -- Whether a sender is the player, so our own messages that the client
    -- hands back are dropped. On WoW: Forever UnitName("player") gives a
    -- surname as its second value ("Dill", "Douse") and senders arrive as
    -- "Dill Douse" (addon-comms, 1.60.1, 2026-10-05); elsewhere the second
    -- value is a realm or nil.
    local playerKeys
    function P.isPlayer(key)
        if not playerKeys then
            local ok, name, second = pcall(UnitName, "player")
            if not ok or type(name) ~= "string" or name == "" or Kit.IsSecret(name) then return false end
            playerKeys = { [P.key(name)] = true }
            if type(second) == "string" and second ~= "" and not Kit.IsSecret(second) then
                playerKeys[P.key(name .. " " .. second)] = true
                playerKeys[P.key(name .. "-" .. second)] = true
            end
        end
        return playerKeys[key] == true
    end

    function P.normalize(name)
        if type(name) ~= "string" or name == "" then return nil end
        local base = name
        local dash = name:find("-", 1, true)
        if dash then
            base = name:sub(1, dash - 1)
            if base == "" or name:sub(dash + 1) ~= P.realm() then return nil end
        end
        return { key = P.key(base), name = base }
    end

    Comms._attachTransport(C, P)

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, P.prefix)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, P.prefix)
    end
    if Comms.Supported() then
        P.bindTransport()
    end
    return C
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

Instance.VIOLATION = Comms.VIOLATION

-- source: the one distribution fn hears, or nil for every one.
function Instance:RegisterReceiver(fn, source)
    assert(type(fn) == "function", "comms receiver must be a function")
    if source == nil then
        source = "*"
    else
        assert(type(source) == "string", "comms source must be a string")
        source = source:upper()
    end
    local receivers = self._p.receivers
    local list = receivers[source]
    if not list then
        list = {}
        receivers[source] = list
    end
    list[#list + 1] = fn
end

-- Returns whether comms is on afterwards: false on a client without the calls
-- it needs. Switching off drops what is still queued.
function Instance:SetEnabled(on)
    local P = self._p
    on = on and true or false
    if on == P.enabled then return P.enabled end
    if on and not Comms.Supported() then
        P.debug("not supported on this client")
        return false
    end
    P.enabled = on
    if not on then P.resetTransport() end
    return on
end

function Instance:IsEnabled()
    return self._p.enabled
end
