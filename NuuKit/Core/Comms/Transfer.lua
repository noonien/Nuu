local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Comms/Transfer.lua: data too big for one addon message, offered to one
-- player or a whole channel and sent only to those who accept. Part of every
-- Kit.NewComms instance.
--
--     local transfer, problem = comms:Offer("Dill Douse", info, bytes, {  -- or "PARTY", "RAID", "GUILD"
--         onAnswer = function(who, accepted, reason) end,
--         onProgress = function(sent, total) end,   -- chunks gone out
--         onReceived = function(who) end,           -- a receiver has all of it
--         onEnd = function(why) end,                -- "done", "declined", "expired", "failed", "cancelled", "too big"
--     })
--     transfer:Cancel()
--
--     comms:OnOffer(function(offer)
--         -- offer.who, offer.source, offer.info, offer.size (sent), offer.rawSize
--         offer:Accept({
--             onProgress = function(got, total) end,
--             onDone = function(ok, bytesOrWhy) end,   -- the bytes as offered, or why not
--         })
--         offer:Decline("have it")   -- or neither: the offer is ignored
--     end)
--
-- A target in capitals is a channel (any of Comms.DISTRIBUTIONS but WHISPER);
-- anything else is a player's name. info is what a receiver decides on, the
-- addon's own bytes (at most Comms.TRANSFER_INFO_MAX, so the offer is one
-- message); bytes is the data, compressed here with DEFLATE in a job
-- (Core/Job.lua) and inflated the same way on arrival.
--
-- The wire, transfer frames (Comms.TRANSFER), each [kind: U] [id: U] ...:
--
--   OFFER    chunks, size, raw size, Adler-32 of the compressed bytes, info
--   ACCEPT   (receiver to sender, whispered)
--   DECLINE  reason (whispered)
--   DATA     index, the chunk's bytes (to the target; a repair is whispered)
--   MISSING  first, count, ... ranges of chunks a receiver lacks (whispered)
--   DONE     (whispered: the receiver has it all)
--   CANCEL   (sender to the target: the transfer is off)
--   ABANDON  (receiver to sender, whispered: it stops receiving)
--
-- The id is always the sender's: OFFER, DATA and CANCEL come from it, the
-- rest answer it.
--
-- A whisper starts as soon as it is accepted. A channel starts
-- Comms.TRANSFER_START seconds after the first accept, so quick answers share
-- the stream; a later accepter reads the rest of it and asks for what it
-- missed. The data goes out Comms.TRANSFER_RATE messages a second at most,
-- within the instance's shared bucket (Core/Comms/Transport.lua). A message
-- the client refuses as throttled is tried again a second later, up to
-- Comms.SEND_TRIES times; past that, or refused for any other reason (the
-- player left the party), the transfer fails, or for a repair, that repair
-- is dropped and its receiver asks again.
-- A receiver that hears nothing for a while asks for what it lacks, a few
-- times, then gives up.
--
-- Defenses: an offer past the size limits is declined unread; a sender gets a
-- few offers a minute and one accepted transfer at a time; data is kept only
-- for a transfer the player accepted, up to a few times its chunks; malformed
-- frames, too many answers and data past that allowance are violations, which
-- mute that sender as other violations do. Data or an answer for a transfer
-- this side does not know (a stream joined late, a reload) is dropped quietly.
local Comms = Kit.Comms or {}
Kit.Comms = Comms
local Codec = Kit.Codec

Comms.TRANSFER_MAX = 65536      -- compressed bytes in one offer
Comms.TRANSFER_INFO_MAX = 220   -- info bytes: the offer fits one message
Comms.TRANSFER_REASON_MAX = 32  -- bytes of a decline's reason
Comms.TRANSFER_RATE = 2         -- data messages a second (to measure in the client)
Comms.TRANSFER_BURST = 4
Comms.TRANSFER_START = 3        -- seconds from a channel's first accept to its data
Comms.TRANSFER_TTL = 60         -- seconds an offer stays open
Comms.TRANSFER_QUIET = 6        -- seconds without data before a receiver asks
Comms.TRANSFER_ASKS = 6         -- times a receiver asks before it gives up
Comms.TRANSFER_HOLD = 60        -- seconds a finished transfer is remembered

-- A data frame: kind, an id below 2^21 and an index below 2^14 take 6 bytes
-- of the 253 a frame's body may hold (Core/Comms/Frame.lua).
Comms.TRANSFER_CHUNK = 247

local OFFER, ACCEPT, DECLINE, DATA, MISSING, DONE, CANCEL, ABANDON = 1, 2, 3, 4, 5, 6, 7, 8
local CHUNK = Comms.TRANSFER_CHUNK
local ID_LIMIT = 2097152
local OFFERS_PER_MINUTE = 4
local CONTROL_PER_MINUTE = 40
local INCOMING_MAX = 4

local floor, ceil, sub, concat = math.floor, math.ceil, string.sub, table.concat

local function chunksOf(size)
    return size == 0 and 1 or ceil(size / CHUNK)
end

local function channelOf(target)
    if Comms.DISTRIBUTIONS[target] and target ~= "WHISPER" then return target end
end

function Comms._attachTransfer(C, P)
    local outgoing, incoming = {}, {}
    local queue, tokens, refilled = {}, Comms.TRANSFER_BURST, 0
    local offerHandler
    local nextId = math.random(1, ID_LIMIT / 2)
    local counts = {}
    local timer, timerAt

    local function now() return GetTime() end

    -- An addon's callback: its error is reported, never raised into ours.
    local function call(fn, ...)
        if not fn then return end
        local ok, err = pcall(fn, ...)
        if not ok then
            local handler = type(geterrorhandler) == "function" and geterrorhandler()
            if handler then pcall(handler, err) else P.debug("transfer callback error: %s", tostring(err)) end
        end
    end

    local function frame(kind, id)
        return Comms.Writer():U(kind):U(id)
    end

    -- A control message, through the lanes like the addon's own.
    local function control(payload, distribution, target)
        if payload then C:Send(payload, distribution, target) end
    end

    -- How many of `what` a sender has had this minute, counting this one.
    local function counted(what, key, limit)
        local route, t = what .. "\1" .. key, now()
        local v = counts[route]
        if not v or t - v.start > 60 then
            v = { start = t, count = 0 }
            counts[route] = v
        end
        v.count = v.count + 1
        return v.count <= limit
    end

    -- The service: one timer to the earliest thing due -----------------------

    local service
    local function wake(at)
        if timer and timerAt <= at then return end
        if timer then timer:Cancel() end
        timerAt = at
        timer = C_Timer.NewTimer(math.max(0.01, at - now()), function()
            timer = nil
            service()
        end)
    end

    -- Sending ---------------------------------------------------------------

    local function endOutgoing(t, why)
        if t.state == "ended" then return end
        t.state = "ended"
        t.why = why
        t.forgetAt = now() + Comms.TRANSFER_HOLD
        for i = #queue, 1, -1 do
            if queue[i].t == t then table.remove(queue, i) end
        end
        call(t.handlers.onEnd, why)
    end

    -- A chunk to send: to the transfer's target (the stream), or whispered
    -- to one receiver that asked for it (a repair).
    local function enqueue(t, index, distribution, target, repair)
        local item = { t = t, index = index, distribution = distribution, target = target, repair = repair, tries = 0 }
        queue[#queue + 1] = item
        return item
    end

    local function streamQueued(t, index)
        for i = 1, #queue do
            local item = queue[i]
            if item.t == t and item.index == index and not item.repair then return true end
        end
        return false
    end

    local function startStream(t)
        if t.streaming then return end
        t.streaming = true
        for i = 0, t.count - 1 do enqueue(t, i, t.distribution, t.target, false) end
        wake(now())
    end

    local function dataFrame(t, index)
        return frame(DATA, t.id):U(index):Raw(sub(t.packed, index * CHUNK + 1, (index + 1) * CHUNK)):FinishTransfer()
    end

    local function pumpQueue(t0)
        tokens = math.min(Comms.TRANSFER_BURST, tokens + (t0 - refilled) * Comms.TRANSFER_RATE)
        refilled = t0
        while #queue > 0 and tokens >= 1 and P.sendable(t0) do
            local item = queue[1]
            local t = item.t
            local taken, again = P.transmit(item.distribution, item.target, dataFrame(t, item.index))
            item.tries = item.tries + 1
            if taken then
                table.remove(queue, 1)
                tokens = tokens - 1
                t.lastActivity = t0
                if not item.repair then
                    t.sent = t.sent + 1
                    call(t.handlers.onProgress, t.sent, t.count)
                end
            elseif again and item.tries < Comms.SEND_TRIES then
                P.hold(t0)
            elseif item.repair then
                table.remove(queue, 1)
            else
                endOutgoing(t, "failed")
            end
        end
        if #queue > 0 then
            return math.max(P.sendableAt(t0), t0 + math.max(0, 1 - tokens) / Comms.TRANSFER_RATE)
        end
    end

    local function checkOutgoing(t, t0)
        if t.state ~= "offered" then return end
        if t.startAt and t0 >= t.startAt then
            t.startAt = nil
            startStream(t)
        end
        local open = t0 < t.expiresAt
        local accepted, done, waiting = 0, 0, 0
        for _, r in pairs(t.receivers) do
            if r.state == "accepted" then
                accepted = accepted + 1
                waiting = waiting + 1
            elseif r.state == "done" then
                accepted = accepted + 1
                done = done + 1
            end
        end
        local busy = streamQueued(t, t.count - 1) or t.startAt
        if t.whisper then
            if accepted == 0 and not open then return endOutgoing(t, "expired") end
            if done > 0 then return endOutgoing(t, "done") end
        elseif not open and waiting == 0 and not busy then
            return endOutgoing(t, done > 0 and "done" or accepted > 0 and "failed" or "expired")
        end
        if accepted > 0 and waiting > 0 and not busy and t0 - t.lastActivity > Comms.TRANSFER_HOLD then
            return endOutgoing(t, done > 0 and "done" or "failed")
        end
        return t.startAt or (open and t.expiresAt) or (t.lastActivity + Comms.TRANSFER_HOLD)
    end

    function C:Offer(target, info, bytes, handlers)
        assert(type(target) == "string" and target ~= "", "an offer needs a target")
        assert(type(info) == "string", "an offer's info must be a string")
        assert(type(bytes) == "string", "an offer's bytes must be a string")
        handlers = handlers or {}
        if not P.enabled then return nil, "comms is off" end
        if #info > Comms.TRANSFER_INFO_MAX then return nil, "info too big" end
        if #bytes > Codec.INFLATE_MAX then return nil, "too big" end
        local channel = channelOf(target)
        local id = nextId
        nextId = nextId % (ID_LIMIT - 1) + 1
        local t = {
            id = id, info = info, handlers = handlers, receivers = {}, sent = 0, rawSize = #bytes,
            distribution = channel or "WHISPER", target = not channel and target or nil, whisper = not channel,
            targetKey = not channel and P.key(target) or nil, state = "preparing",
        }
        outgoing[id] = t
        local handle = { id = id }
        function handle:Cancel()
            if t.state == "ended" then return end
            if t.state == "offered" then control(frame(CANCEL, id):FinishTransfer(), t.distribution, t.target) end
            endOutgoing(t, "cancelled")
        end
        function handle:State() return t.state, t.why end
        Kit.Job.Start(function()
            local packed = Codec.Deflate(bytes)
            return packed, Codec.Adler32(packed)
        end, function(ok, packed, adler)
            if t.state ~= "preparing" then return end
            if not ok then return endOutgoing(t, "failed") end
            if not P.enabled then return endOutgoing(t, "cancelled") end
            if #packed > Comms.TRANSFER_MAX then return endOutgoing(t, "too big") end
            t.packed, t.adler, t.count = packed, adler, chunksOf(#packed)
            local payload = frame(OFFER, id):U(t.count):U(#packed):U(t.rawSize):U32(adler):Raw(info):FinishTransfer()
            if not payload then return endOutgoing(t, "too big") end
            t.state = "offered"
            t.expiresAt = now() + Comms.TRANSFER_TTL
            t.lastActivity = now()
            control(payload, t.distribution, t.target)
            wake(t.expiresAt)
        end)
        return handle
    end

    -- Receiving ---------------------------------------------------------------

    local function routeOf(key, id) return key .. "\1" .. id end

    local function endIncoming(r, why, bytes)
        if r.state == "ended" then return end
        local accepted = r.state == "accepted" or r.state == "inflating"
        r.state = "ended"
        r.got = nil
        r.forgetAt = now() + Comms.TRANSFER_HOLD
        if accepted and r.handlers then
            if bytes then call(r.handlers.onDone, true, bytes) else call(r.handlers.onDone, false, why) end
        end
    end

    local function activeFrom(key)
        local from, all = 0, 0
        for _, r in pairs(incoming) do
            if r.state == "accepted" or r.state == "inflating" then
                all = all + 1
                if r.key == key then from = from + 1 end
            end
        end
        return from, all
    end

    local function reply(r, payload)
        control(payload, "WHISPER", r.name)
    end

    -- MISSING with as many ranges of the chunks r lacks as one frame holds.
    local function missingFrame(r)
        local w, i = frame(MISSING, r.id), 0
        while i < r.count do
            if not r.got[i] then
                local first = i
                while i < r.count and not r.got[i] do i = i + 1 end
                local mark = w:Mark()
                w:U(first):U(i - first)
                if w:Len() > Comms.MAX_PAYLOAD then
                    w:Restore(mark)
                    break
                end
            else
                i = i + 1
            end
        end
        return w:FinishTransfer()
    end

    local function finishIncoming(r)
        r.state = "inflating"
        local parts = {}
        for i = 0, r.count - 1 do parts[i + 1] = r.got[i] end
        local packed = concat(parts)
        r.got = nil
        Kit.Job.Start(function()
            if #packed ~= r.size or Codec.Adler32(packed) ~= r.adler then return nil end
            return Codec.Inflate(packed, r.rawSize)
        end, function(ok, bytes)
            if r.state ~= "inflating" then return end
            if not ok or not bytes or #bytes ~= r.rawSize then
                reply(r, frame(ABANDON, r.id):FinishTransfer())
                return endIncoming(r, "damaged")
            end
            reply(r, frame(DONE, r.id):FinishTransfer())
            endIncoming(r, nil, bytes)
        end)
    end

    local function checkIncoming(r, t0)
        if r.state == "offered" then
            if t0 >= r.expiresAt then r.state = "ended"; r.forgetAt = t0 + Comms.TRANSFER_HOLD end
            return r.expiresAt
        end
        if r.state ~= "accepted" then return end
        local quiet = r.asks == 0 and Comms.TRANSFER_QUIET + Comms.TRANSFER_START or Comms.TRANSFER_QUIET
        if t0 - r.last < quiet then return r.last + quiet end
        if r.asks >= Comms.TRANSFER_ASKS then
            reply(r, frame(ABANDON, r.id):FinishTransfer())
            return endIncoming(r, "timed out")
        end
        r.asks = r.asks + 1
        r.last = t0
        reply(r, missingFrame(r))
        return t0 + Comms.TRANSFER_QUIET
    end

    function C:OnOffer(fn)
        assert(fn == nil or type(fn) == "function", "OnOffer takes a function")
        offerHandler = fn
    end

    local Offer = {}
    Offer.__index = Offer

    function Offer:Accept(handlers)
        local r = self._r
        if r.state ~= "offered" then return false, r.state == "ended" and "expired" or "answered" end
        if now() >= r.expiresAt then return false, "expired" end
        local from, all = activeFrom(r.key)
        if from > 0 or all >= INCOMING_MAX then return false, "busy" end
        r.state, r.handlers = "accepted", handlers or {}
        r.got, r.have, r.frames, r.asks, r.last = {}, 0, 0, 0, now()
        reply(r, frame(ACCEPT, r.id):FinishTransfer())
        wake(r.last + Comms.TRANSFER_QUIET + Comms.TRANSFER_START)
        return true
    end

    function Offer:Decline(reason)
        local r = self._r
        if r.state ~= "offered" then return false end
        reason = sub(tostring(reason or ""), 1, Comms.TRANSFER_REASON_MAX)
        reply(r, frame(DECLINE, r.id):Raw(reason):FinishTransfer())
        r.state = "ended"
        r.forgetAt = now() + Comms.TRANSFER_HOLD
        return true
    end

    function Offer:Cancel()
        local r = self._r
        if r.state ~= "accepted" and r.state ~= "inflating" then return false end
        reply(r, frame(ABANDON, r.id):FinishTransfer())
        endIncoming(r, "cancelled")
        return true
    end

    local function onOffer(who, source, r, id)
        local count, size, rawSize, adler = r:U(), r:U(), r:U(), r:U32()
        local info = r:Rest()
        if not r:Ok() or count ~= chunksOf(size) then return Comms.VIOLATION end
        local route = routeOf(who.key, id)
        if incoming[route] then return end
        local rec = {
            key = who.key, name = who.name, id = id, source = source, count = count, size = size,
            rawSize = rawSize, adler = adler, state = "offered", expiresAt = now() + Comms.TRANSFER_TTL,
        }
        incoming[route] = rec
        wake(rec.expiresAt)
        -- Past the limit, or with nobody to ask: remembered, so its data is
        -- known and dropped, and never answered.
        if not counted("offer", who.key, OFFERS_PER_MINUTE) or not offerHandler then
            rec.state = "ended"
            rec.forgetAt = rec.expiresAt + Comms.TRANSFER_HOLD
            return
        end
        local offer = setmetatable({ _r = rec, who = who, source = source, info = info, size = size,
            rawSize = rawSize }, Offer)
        if size > Comms.TRANSFER_MAX or rawSize > Codec.INFLATE_MAX then
            offer:Decline("too big")
            return
        end
        call(offerHandler, offer)
    end

    local function onData(who, r, id)
        local rec = incoming[routeOf(who.key, id)]
        if not rec or rec.state ~= "accepted" then return end
        local index = r:U()
        local bytes = r:Rest()
        if not r:Ok() or index >= rec.count then return Comms.VIOLATION end
        local want = index == rec.count - 1 and rec.size - index * CHUNK or CHUNK
        if #bytes ~= want then return Comms.VIOLATION end
        rec.frames = rec.frames + 1
        if rec.frames > rec.count * 3 + 20 then
            reply(rec, frame(ABANDON, rec.id):FinishTransfer())
            endIncoming(rec, "failed")
            return Comms.VIOLATION
        end
        rec.last = now()
        if rec.got[index] then return end
        rec.got[index] = bytes
        rec.have = rec.have + 1
        call(rec.handlers.onProgress, rec.have, rec.count)
        if rec.have == rec.count then finishIncoming(rec) end
    end

    -- Answers to our offers.
    local function onAnswer(who, kind, r, id)
        local t = outgoing[id]
        if not t or t.state == "preparing" then return end
        if t.whisper and who.key ~= t.targetKey then return Comms.VIOLATION end
        if t.state ~= "offered" then return end
        local receiver = t.receivers[who.key]
        local t0 = now()
        if kind == ACCEPT then
            if receiver then return end
            if t0 >= t.expiresAt then
                control(frame(CANCEL, id):FinishTransfer(), "WHISPER", who.name)
                return
            end
            t.receivers[who.key] = { name = who.name, state = "accepted", asks = 0, askedAt = 0 }
            t.lastActivity = t0
            call(t.handlers.onAnswer, who, true)
            if t.whisper then
                startStream(t)
            elseif not t.streaming and not t.startAt then
                t.startAt = t0 + Comms.TRANSFER_START
                wake(t.startAt)
            end
        elseif kind == DECLINE then
            if receiver then return end
            t.receivers[who.key] = { name = who.name, state = "declined" }
            call(t.handlers.onAnswer, who, false, r:Rest())
            if t.whisper then endOutgoing(t, "declined") end
        elseif kind == MISSING then
            if not receiver or receiver.state ~= "accepted" then return Comms.VIOLATION end
            receiver.asks = receiver.asks + 1
            if receiver.asks > Comms.TRANSFER_ASKS * 2 then return Comms.VIOLATION end
            if t0 - receiver.askedAt < 1 or not t.streaming then return end
            receiver.askedAt = t0
            t.lastActivity = t0
            local total = 0
            while r:More() do
                local first, count = r:U(), r:U()
                if not r:Ok() or count < 1 or first + count > t.count then return Comms.VIOLATION end
                total = total + count
                if total > t.count then return Comms.VIOLATION end
                for index = first, first + count - 1 do
                    if not streamQueued(t, index) then enqueue(t, index, "WHISPER", receiver.name, true) end
                end
            end
            wake(t0)
        elseif kind == DONE then
            if not receiver or receiver.state ~= "accepted" then return end
            receiver.state = "done"
            t.lastActivity = t0
            call(t.handlers.onReceived, who)
            wake(t0)
        elseif kind == ABANDON then
            if not receiver or receiver.state ~= "accepted" then return end
            receiver.state = "abandoned"
            if t.whisper then return endOutgoing(t, "failed") end
            wake(t0)
        end
    end

    function P.onTransfer(who, payload, source)
        local r = Comms.Reader(payload)
        local kind, id = r:U(), r:U()
        if not r:Ok() then return Comms.VIOLATION end
        if kind ~= DATA and not counted("control", who.key, CONTROL_PER_MINUTE) then return Comms.VIOLATION end
        if kind == OFFER then return onOffer(who, source, r, id) end
        if kind == DATA then return onData(who, r, id) end
        if kind == CANCEL then
            local rec = incoming[routeOf(who.key, id)]
            if rec then endIncoming(rec, "cancelled") end
            return
        end
        if kind == ACCEPT or kind == DECLINE or kind == MISSING or kind == DONE or kind == ABANDON then
            return onAnswer(who, kind, r, id)
        end
        return Comms.VIOLATION
    end

    -- The service -------------------------------------------------------------

    service = function()
        local t0 = now()
        local soonest = pumpQueue(t0)
        local function due(at)
            if at and (not soonest or at < soonest) then soonest = at end
        end
        for id, t in pairs(outgoing) do
            if t.state == "ended" then
                if t0 >= t.forgetAt then outgoing[id] = nil end
            else
                due(checkOutgoing(t, t0))
            end
        end
        due(pumpQueue(t0))
        for route, r in pairs(incoming) do
            if r.state == "ended" then
                if t0 >= r.forgetAt then incoming[route] = nil end
            else
                due(checkIncoming(r, t0))
            end
        end
        for route, v in pairs(counts) do
            if t0 - v.start > 120 then counts[route] = nil end
        end
        if soonest then wake(math.max(soonest, t0 + 0.05)) end
    end

    -- Whether transfer frames are wanted: an addon takes offers, or a
    -- transfer is under way. Otherwise Transport drops them unread.
    function P.transferring()
        return offerHandler ~= nil or next(outgoing) ~= nil or next(incoming) ~= nil
    end

    -- Comms switched off: everything ends where it stands, unsent.
    function P.resetTransfers()
        for _, t in pairs(outgoing) do endOutgoing(t, "cancelled") end
        for _, r in pairs(incoming) do endIncoming(r, "cancelled") end
        wipe(queue)
        wipe(outgoing)
        wipe(incoming)
        if timer then timer:Cancel() end
        timer = nil
    end
end
