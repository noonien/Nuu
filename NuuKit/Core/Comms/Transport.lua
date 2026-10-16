local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Comms/Transport.lua: the outbound token bucket and the inbound
-- defenses of one Kit.NewComms instance. From Sonar's Comms/Transport.lua.
--
-- Outbound payloads are Writer frames (version + COBS), throttled per
-- destination and, since the client throttles a prefix as a whole, across the
-- instance too: every lane and every transfer draws on one shared bucket
-- (Comms.SEND_RATE). A message the client refuses as throttled holds them all
-- for a second and is tried again, Comms.SEND_TRIES times at most; any other
-- refusal drops it. Inbound, Transport accepts the comms version and rejects empty
-- frames before receivers run. Wrong versions and repeated violations mute
-- that sender on that source until reload. Message types stay opaque.
-- Transfer frames (Comms.TRANSFER) go to Core/Comms/Transfer.lua instead of
-- the receivers, outside the budget: a transfer keeps its own.
local Comms = Kit.Comms or {}
Kit.Comms = Comms

local SEND_RATE = 1
local SEND_BURST = 4
local QUEUE_MAX = 40
local BUDGET_WINDOW = 60
local BUDGET_MAX = 20
local VIOLATION_WINDOW = 300
local VIOLATION_MAX = 10

-- Across one instance (one prefix): every lane and transfer together. A guess
-- until it is measured in the client (docs/api-compatibility.md).
Comms.SEND_RATE = 4
Comms.SEND_BURST = 10
Comms.SEND_TRIES = 8

local function Now()
    return (GetServerTime and GetServerTime()) or time()
end

local function SendAddonMessageFn()
    return (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
end

-- Whether a refusal is the client's throttle, so worth trying again. Where the
-- client names its results, only its throttles are; where it does not, any
-- refusal might be, and the tries run out.
local function Throttled(result)
    local codes = Enum and Enum.SendAddonMessageResult
    if type(codes) ~= "table" or (codes.AddonMessageThrottle == nil and codes.ChannelThrottle == nil) then
        return true
    end
    return result == codes.AddonMessageThrottle or result == codes.ChannelThrottle
end

local Sender = {}
Sender.__index = Sender

function Comms._attachTransport(C, P)
    local MIN_PAYLOAD, MAX_PAYLOAD = Comms.MIN_PAYLOAD, Comms.MAX_PAYLOAD
    local _addJob, _draw, _lane, _queue
    local NO_OPTIONS = {}

    local function _destination(distribution, target)
        assert(type(distribution) == "string", "comms distribution is required")
        distribution = distribution:upper()
        assert(Comms.DISTRIBUTIONS[distribution], "comms cannot send to " .. distribution)
        if distribution == "WHISPER" then
            assert(type(target) == "string" and target ~= "", "a comms whisper needs a target")
        else
            target = nil
        end
        return distribution, target
    end

    ----------------------------------------------------------------------------
    -- Public API
    ----------------------------------------------------------------------------

    -- One message: comms:Send(payload, "PARTY"), comms:Send(payload, "WHISPER", name).
    -- As a Sender's Send, without making the Sender.
    function C:Send(payload, distribution, target)
        Comms._checkPayload(payload)
        distribution, target = _destination(distribution, target)
        return _queue(_lane(distribution, target), nil, GetTime(), 0, 0, payload)
    end

    function C:Sender(distribution, target, options)
        distribution, target = _destination(distribution, target)
        options = options or NO_OPTIONS
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

    -- The instance's shared bucket, and the time a throttle holds it to.
    local shared = { tokens = Comms.SEND_BURST, refilled = nil, heldUntil = 0 }

    local function _refillShared(now)
        if shared.refilled then
            shared.tokens = math.min(Comms.SEND_BURST, shared.tokens + (now - shared.refilled) * Comms.SEND_RATE)
        end
        shared.refilled = now
    end

    -- Whether the instance may send now; Transfer asks before each message.
    function P.sendable(now)
        _refillShared(now)
        return shared.tokens >= 1 and now >= shared.heldUntil
    end

    -- When it may send next.
    function P.sendableAt(now)
        _refillShared(now)
        return math.max(shared.heldUntil, now + math.max(0, 1 - shared.tokens) / Comms.SEND_RATE)
    end

    function P.spend()
        shared.tokens = shared.tokens - 1
    end

    -- The client throttled us: nothing goes for a second.
    function P.hold(now)
        shared.heldUntil = now + 1
    end

    -- A sender is only a reusable delay policy and destination. All senders
    -- for the same distribution/target share one lane and therefore one
    -- throttle.
    local function _laneKey(distribution, target)
        return distribution .. "\1" .. (target or "")
    end

    -- A lane with nothing queued whose bucket has refilled is the same as a
    -- new one, so it is let go: whispers to many names leave nothing behind.
    local function _pruneLanes(now)
        for key, lane in pairs(lanes) do
            if #lane.jobs == 0 and not lane.timer
                and lane.tokens + (now - lane.lastRefill) * SEND_RATE >= SEND_BURST then
                lanes[key] = nil
            end
        end
    end

    -- A whisper's lane is found by the name's key and sends to the spelling
    -- it was first given.
    _lane = function(distribution, target)
        local key = _laneKey(distribution, target and P.key(target))
        local lane = lanes[key]
        if lane then return lane end
        local now = GetTime()
        _pruneLanes(now)
        lane = {
            key = key, distribution = distribution, target = target, jobs = {},
            tokens = SEND_BURST, lastRefill = now, timer = nil,
        }
        lanes[key] = lane
        return lane
    end

    -- The ordinary one-message path shares the destination throttle with
    -- producers, but bypasses their optional settle/jitter policy: it goes now
    -- if the lane has a token, or waits only for that lane's throttle. A
    -- single message is its payload, kept as pending (no producer), and goes
    -- once.
    _queue = function(lane, producer, readyAt, repeatDelay, repeatJitter, payload)
        if not P.enabled then return false end
        if queued >= QUEUE_MAX then return false end
        lane.jobs[#lane.jobs + 1] = {
            producer = producer,
            pending = payload,
            readyAt = readyAt,
            repeatDelay = repeatDelay,
            repeatJitter = repeatJitter,
            oneShot = payload ~= nil,
        }
        queued = queued + 1
        _pump(lane)
        return true
    end

    _addJob = function(sender, producer, readyAt, repeatDelay, repeatJitter, payload)
        local lane = sender.lane
        -- A sender kept past its lane's pruning takes up the current one.
        if lanes[lane.key] ~= lane then
            lane = _lane(lane.distribution, lane.target)
            sender.lane = lane
        end
        return _queue(lane, producer, readyAt, repeatDelay, repeatJitter, payload)
    end

    local _send

    -- The lane's next turn: when it has a token, the instance has one, and a
    -- job is ready.
    local function _later(lane, now)
        if #lane.jobs == 0 then return end
        local at = now + math.max(0, 1 - lane.tokens) / SEND_RATE
        local jobAt
        for i = 1, #lane.jobs do
            local ready = lane.jobs[i].readyAt
            if not jobAt or ready < jobAt then jobAt = ready end
        end
        _schedule(lane, math.max(at, jobAt, P.sendableAt(now)))
    end

    -- What is wrong with a producer's answer, or nil.
    local function _problem(ok, payload)
        if not ok then return "comms outbound producer failed: " .. tostring(payload) end
        if payload == nil then return nil end
        if type(payload) ~= "string" then return "comms outbound producer must return a string or nil" end
        if #payload < MIN_PAYLOAD then return "comms outbound producer returned an empty payload" end
        if #payload > MAX_PAYLOAD then
            return ("comms outbound producer returned %d bytes; maximum is %d"):format(#payload, MAX_PAYLOAD)
        end
    end

    _pump = function(lane)
        if not P.enabled or #lane.jobs == 0 then return end

        local now = GetTime()
        lane.tokens = math.min(SEND_BURST,
            lane.tokens + (now - lane.lastRefill) * SEND_RATE)
        lane.lastRefill = now

        while #lane.jobs > 0 and lane.tokens >= 1 and P.sendable(now) do
            local readyIndex, nextReady
            for i = 1, #lane.jobs do
                local at = lane.jobs[i].readyAt
                if at <= now then
                    readyIndex = i
                    break
                end
                if not nextReady or at < nextReady then nextReady = at end
            end
            if not readyIndex then break end

            local job = lane.jobs[readyIndex]
            -- A single message, or a payload the client refused as throttled
            -- and that is sent again as it was.
            local payload = job.pending
            if payload == nil then
                local ok
                ok, payload = pcall(job.producer)
                local problem = _problem(ok, payload)
                if problem then
                    table.remove(lane.jobs, readyIndex)
                    queued = queued - 1
                    -- The rest of the lane still goes.
                    _later(lane, now)
                    error(problem)
                end
            end

            if payload == nil then
                table.remove(lane.jobs, readyIndex)
                queued = queued - 1
            else
                local taken, result = _send(lane.distribution, lane.target, payload)
                job.tries = (job.tries or 0) + 1
                if not taken and Throttled(result) and job.tries < Comms.SEND_TRIES then
                    job.pending = payload
                    P.hold(now)
                else
                    if taken then
                        lane.tokens = lane.tokens - 1
                        P.spend()
                    end
                    job.pending, job.tries = nil, nil
                    table.remove(lane.jobs, readyIndex)
                    if job.oneShot then
                        queued = queued - 1
                    else
                        job.readyAt = now + _draw(job.repeatDelay, job.repeatJitter)
                        lane.jobs[#lane.jobs + 1] = job
                    end
                end
            end
            now = GetTime()
        end

        _later(lane, now)
    end

    _draw = function(base, jitter)
        return (base or 0) + (jitter and jitter > 0 and math.random() * jitter or 0)
    end

    -- Whether the client took the message, and what it answered:
    -- SendAddonMessage answers nothing or true on older clients,
    -- Enum.SendAddonMessageResult (0 is Success) on newer ones, and anything
    -- else (throttled, not in a group) is refused.
    _send = function(distribution, target, payload)
        local ok, result = pcall(SendAddonMessageFn(), P.prefix, payload, distribution, target)
        local taken = ok and (result == nil or result == true or result == 0)
        if P.log then
            P.debug("-> %d bytes [%s]%s", #payload,
                distribution:lower() .. (target and (":" .. target) or ""),
                taken and "" or (" refused: " .. tostring(result)))
        end
        return taken, result
    end

    -- For transfers, which pace their own data: sends now, outside the lanes
    -- (the caller asked P.sendable first), and says whether the client took
    -- it and, if not, whether to try again (a throttle).
    function P.transmit(distribution, target, payload)
        local taken, result = _send(distribution, target, payload)
        if taken then P.spend() end
        return taken, not taken and Throttled(result)
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
        shared.tokens, shared.refilled, shared.heldUntil = Comms.SEND_BURST, nil, 0
        wipe(budget)
        wipe(violations)
        P.resetTransfers()
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

    -- Hands a message to each receiver in list; whether one called it a
    -- violation.
    local function _deliver(list, who, payload, source)
        local violated = false
        for i = 1, #list do
            local ok, result = pcall(list[i], who, payload, source)
            if not ok then
                P.debug("receiver error from %s: %s", who.key, tostring(result))
            elseif result == Comms.VIOLATION then
                violated = true
            end
        end
        return violated
    end
    _onAddonMessage = function(prefix, payload, source, sender)
        if prefix ~= P.prefix or not P.enabled or not payload or not source then return end
        local listeners = P.receivers[source] or none
        local any = P.receivers["*"] or none
        if #listeners == 0 and #any == 0 and not P.transferring() then return end

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

        if payload:byte(1) == Comms.TRANSFER then
            if not P.transferring() then return end
            local ok, result = pcall(P.onTransfer, who, payload, source)
            if not ok then
                P.debug("transfer error from %s: %s", key, tostring(result))
            elseif result == Comms.VIOLATION then
                _dropped(key, "transfer violation", payload)
                _violation(route, now)
            end
            return
        end
        if #listeners == 0 and #any == 0 then return end

        if _overBudget(route, now) then
            _dropped(key, "over budget", payload)
            _violation(route, now)
            return
        end

        if P.log then
            P.debug("<- %s [%s] %d bytes", key, source:lower(), #payload)
        end

        local violated = _deliver(listeners, who, payload, source)
        violated = _deliver(any, who, payload, source) or violated
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

function Comms._checkPayload(payload)
    assert(type(payload) == "string", "comms payload must be a string")
    assert(#payload >= Comms.MIN_PAYLOAD, "comms payload is empty")
    assert(#payload <= Comms.MAX_PAYLOAD,
        ("comms payload is %d bytes; maximum is %d"):format(#payload, Comms.MAX_PAYLOAD))
end

function Sender:Send(payload)
    Comms._checkPayload(payload)
    return self.addJob(self, nil, GetTime(), 0, 0, payload)
end
