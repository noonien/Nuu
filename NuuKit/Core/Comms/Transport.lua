local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Comms/Transport.lua: the outbound token bucket and the inbound
-- defenses of one Kit.NewComms instance. From Sonar's Comms/Transport.lua.
--
-- Outbound payloads are Writer frames (version + COBS), throttled per
-- destination. Inbound, Transport accepts the comms version and rejects empty
-- frames before receivers run. Wrong versions and repeated violations mute
-- that sender on that source until reload. Message types stay opaque.
local Comms = Kit.Comms or {}
Kit.Comms = Comms

local SEND_RATE = 1
local SEND_BURST = 4
local QUEUE_MAX = 40
local BUDGET_WINDOW = 60
local BUDGET_MAX = 20
local VIOLATION_WINDOW = 300
local VIOLATION_MAX = 10

local function Now()
    return (GetServerTime and GetServerTime()) or time()
end

local function SendAddonMessageFn()
    return (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
end

local Sender = {}
Sender.__index = Sender

function Comms._attachTransport(C, P)
    local MIN_PAYLOAD, MAX_PAYLOAD = Comms.MIN_PAYLOAD, Comms.MAX_PAYLOAD
    local _addJob, _draw, _lane

    ----------------------------------------------------------------------------
    -- Public API
    ----------------------------------------------------------------------------

    -- One message: comms:Send(payload, "PARTY"), comms:Send(payload, "WHISPER", name).
    function C:Send(payload, distribution, target)
        return self:Sender(distribution, target):Send(payload)
    end

    function C:Sender(distribution, target, options)
        assert(type(distribution) == "string", "comms distribution is required")
        distribution = distribution:upper()
        assert(Comms.DISTRIBUTIONS[distribution], "comms cannot send to " .. distribution)
        if distribution == "WHISPER" then
            assert(type(target) == "string" and target ~= "", "a comms whisper needs a target")
        else
            target = nil
        end
        options = options or {}
        return setmetatable({
            lane = _lane(distribution, target),
            addJob = _addJob,
            draw = _draw,
            initialDelay = options.initialDelay or 0,
            initialJitter = options.initialJitter or 0,
            repeatDelay = options.repeatDelay or 0,
            repeatJitter = options.repeatJitter or 0,
        }, Sender)
    end

    -- Outbound work is queued per destination, not as finished payloads. A
    -- producer is run when its destination can send; one payload keeps it
    -- alive for another turn, and nil finishes it. Jobs go to the back after
    -- every payload, so a producer's own delay never blocks unrelated work on
    -- the same destination.
    local lanes = {}
    local queued = 0

    local budget = {}
    local violations = {}
    -- Wrong-version and auto-muted peers, keyed by sender and source. In
    -- memory only; a reload clears it. Not wiped when comms is toggled, and
    -- never written to the addon's own muted list (that list is the player's).
    local sessionMuted = {}
    local lastSweep = 0

    local function _sourceKey(key, source)
        return key .. "\1" .. source
    end

    local _pump

    local function _schedule(lane, at)
        if lane.timer then lane.timer:Cancel() end
        lane.timer = C_Timer.NewTimer(math.max(0.01, at - GetTime()), function()
            lane.timer = nil
            _pump(lane)
        end)
    end

    -- A sender is only a reusable delay policy and destination. All senders
    -- for the same distribution/target share one lane and therefore one
    -- throttle.
    local function _laneKey(distribution, target)
        return distribution .. "\1" .. (target or "")
    end

    -- A whisper's lane is found by the name's key and sends to the spelling
    -- it was first given.
    _lane = function(distribution, target)
        local key = _laneKey(distribution, target and P.key(target))
        local lane = lanes[key]
        if lane then return lane end
        lane = {
            distribution = distribution, target = target, jobs = {},
            tokens = SEND_BURST, lastRefill = GetTime(), timer = nil,
        }
        lanes[key] = lane
        return lane
    end

    -- The ordinary one-message path shares the destination throttle with
    -- producers, but bypasses their optional settle/jitter policy: it goes now
    -- if the lane has a token, or waits only for that lane's throttle.
    _addJob = function(sender, producer, readyAt, repeatDelay, repeatJitter, oneShot)
        if not P.enabled then return false end
        if queued >= QUEUE_MAX then return false end
        local lane = sender.lane
        lane.jobs[#lane.jobs + 1] = {
            producer = producer,
            readyAt = readyAt,
            repeatDelay = repeatDelay,
            repeatJitter = repeatJitter,
            oneShot = oneShot,
        }
        queued = queued + 1
        _pump(lane)
        return true
    end

    local _transmit
    _pump = function(lane)
        if not P.enabled or #lane.jobs == 0 then return end

        local now = GetTime()
        lane.tokens = math.min(SEND_BURST,
            lane.tokens + (now - lane.lastRefill) * SEND_RATE)
        lane.lastRefill = now

        while #lane.jobs > 0 and lane.tokens >= 1 do
            local readyIndex, nextReady
            for i = 1, #lane.jobs do
                local at = lane.jobs[i].readyAt
                if at <= now then
                    readyIndex = i
                    break
                end
                if not nextReady or at < nextReady then nextReady = at end
            end
            if not readyIndex then
                _schedule(lane, nextReady)
                return
            end

            local job = table.remove(lane.jobs, readyIndex)
            local ok, payload = pcall(job.producer)
            if not ok then
                queued = queued - 1
                error("comms outbound producer failed: " .. tostring(payload))
            elseif payload == nil then
                queued = queued - 1
            elseif type(payload) ~= "string" then
                queued = queued - 1
                error("comms outbound producer must return a string or nil")
            elseif #payload < MIN_PAYLOAD then
                queued = queued - 1
                error("comms outbound producer returned an empty payload")
            elseif #payload > MAX_PAYLOAD then
                queued = queued - 1
                error(("comms outbound producer returned %d bytes; maximum is %d")
                    :format(#payload, MAX_PAYLOAD))
            else
                _transmit(lane, payload)
                lane.tokens = lane.tokens - 1
                if job.oneShot then
                    queued = queued - 1
                else
                    job.readyAt = now + _draw(job.repeatDelay, job.repeatJitter)
                    lane.jobs[#lane.jobs + 1] = job
                end
            end
            now = GetTime()
        end

        if #lane.jobs == 0 then return end
        local tokenAt = now + math.max(0, 1 - lane.tokens) / SEND_RATE
        local jobAt
        for i = 1, #lane.jobs do
            local at = lane.jobs[i].readyAt
            if not jobAt or at < jobAt then jobAt = at end
        end
        _schedule(lane, math.max(tokenAt, jobAt))
    end

    _draw = function(base, jitter)
        return (base or 0) + (jitter and jitter > 0 and math.random() * jitter or 0)
    end

    _transmit = function(lane, payload)
        SendAddonMessageFn()(P.prefix, payload, lane.distribution, lane.target)
        if P.log then
            P.debug("-> %d bytes [%s]", #payload,
                lane.distribution:lower() .. (lane.target and (":" .. lane.target) or ""))
        end
    end

    function P.resetTransport()
        for _, lane in pairs(lanes) do
            wipe(lane.jobs)
            if lane.timer then lane.timer:Cancel() end
            lane.timer = nil
            lane.tokens = SEND_BURST
            lane.lastRefill = GetTime()
        end
        queued = 0
        wipe(budget)
        wipe(violations)
    end

    ----------------------------------------------------------------------------
    -- Inbound
    ----------------------------------------------------------------------------

    local _onAddonMessage
    function P.bindTransport()
        P.on("CHAT_MSG_ADDON", _onAddonMessage)
    end

    local none = {}

    local _dropped, _overBudget, _sessionMute, _sweep, _violation
    _onAddonMessage = function(prefix, payload, source, sender)
        if prefix ~= P.prefix or not P.enabled or not payload or not source then return end
        local listeners = P.receivers[source] or none
        local any = P.receivers["*"] or none
        if #listeners == 0 and #any == 0 then return end

        -- Receivers get both forms: the key for every lookup and comparison,
        -- and the realm-less name for anything they store or show.
        local who = P.normalize(sender)
        if not who or P.isPlayer(who.key) then return end
        local key = who.key

        local now = Now()
        _sweep(now)

        local route = _sourceKey(key, source)
        if sessionMuted[route] then
            _dropped(key, "muted", payload)
            return
        end
        local okMuted, muted = pcall(P.muted, key)
        if okMuted and muted then
            _dropped(key, "refused", payload)
            return
        end

        local frame = Comms.Accept(payload)
        if frame ~= true then
            if frame == Comms.VIOLATION then
                _dropped(key, "empty", payload)
                _violation(route, now)
            else
                _sessionMute(route, "version")
                _dropped(key, "version", payload)
            end
            return
        end

        if _overBudget(route, now) then
            _dropped(key, "over budget", payload)
            _violation(route, now)
            return
        end

        if P.log then
            P.debug("<- %s [%s] %d bytes", key, source:lower(), #payload)
        end

        local violated = false
        for _, list in ipairs({ listeners, any }) do
            for i = 1, #list do
                local ok, result = pcall(list[i], who, payload, source)
                if not ok then
                    P.debug("receiver error from %s: %s", key, tostring(result))
                elseif result == Comms.VIOLATION then
                    violated = true
                end
            end
        end
        if violated then _violation(route, now) end
    end

    _sweep = function(now)
        if now - lastSweep < 30 then return end
        lastSweep = now
        for k, v in pairs(budget) do
            if now - v.start > BUDGET_WINDOW * 2 then budget[k] = nil end
        end
        for k, v in pairs(violations) do
            if now - v.first > VIOLATION_WINDOW then violations[k] = nil end
        end
    end

    _sessionMute = function(route, why)
        sessionMuted[route] = true
        P.debug("session-muting %s (%s)", (route:gsub("\1", " on ")), why)
    end

    _violation = function(route, now)
        local v = violations[route]
        if not v or now - v.first > VIOLATION_WINDOW then
            violations[route] = { first = now, count = 1 }
            return
        end
        v.count = v.count + 1
        if v.count > VIOLATION_MAX then
            violations[route] = nil
            _sessionMute(route, "violations")
        end
    end

    _overBudget = function(route, now)
        local v = budget[route]
        if not v or now - v.start > BUDGET_WINDOW then
            budget[route] = { start = now, count = 1 }
            return false
        end
        v.count = v.count + 1
        return v.count > BUDGET_MAX
    end

    _dropped = function(key, why, payload)
        if P.log then
            P.debug("xx %s (%s) %d bytes", key, why, #payload)
        end
    end
end

--------------------------------------------------------------------------------
-- Sender
--------------------------------------------------------------------------------

function Sender:SendMultiple(producer)
    assert(type(producer) == "function", "comms producer must be a function")
    return self.addJob(self, producer,
        GetTime() + self.draw(self.initialDelay, self.initialJitter),
        self.repeatDelay, self.repeatJitter)
end

function Sender:Send(payload)
    assert(type(payload) == "string", "comms payload must be a string")
    assert(#payload >= Comms.MIN_PAYLOAD, "comms payload is empty")
    assert(#payload <= Comms.MAX_PAYLOAD,
        ("comms payload is %d bytes; maximum is %d"):format(#payload, Comms.MAX_PAYLOAD))
    return self.addJob(self, function() return payload end, GetTime(), 0, 0, true)
end
