-- Comms transfers: offers, answers, data, repairs and the defenses, between
-- players stood in for by comms instances in one world. Each player has its
-- own prefix, so the network below knows who sent what; it hands a whisper
-- to its target and a party message to everyone else, as the client does.
local Kit = _G.LoadKit().Kit
local W = dofile("Tests/Support/CommsWorld.lua")
local suite, test, before, after = W.suite, W.test, W.before, W.after
local ok, eq = W.ok, W.eq

local Comms, Codec = Kit.Comms, Kit.Codec
local CHUNK = Comms.TRANSFER_CHUNK

local world, players, byPrefix, byName, delivered, timers
-- What the network drops: fn(entry, to) returns true to lose that delivery.
local drop
-- What SendAddonMessage answers: fn(entry) returns the client's result.
local answer

local function newPlayer(name)
    local prefix = "T" .. name
    local before = #world.frames
    local logs = {}
    local comms = Kit.NewComms({ prefix = prefix, log = function(m) logs[#logs + 1] = m end })
    local player = { name = name, prefix = prefix, comms = comms, frame = world.frames[before + 1], logs = logs }
    comms:SetEnabled(true)
    players[#players + 1] = player
    byPrefix[prefix] = player
    byName[name:lower()] = player
    return player
end

-- The client's timers, with the time each is due.
local function installTimers()
    timers = {}
    world:set("C_Timer", {
        NewTimer = function(delay, fn)
            local entry = { at = world.clock.now + delay, fn = fn }
            function entry:Cancel() self.cancelled = true end
            timers[#timers + 1] = entry
            return entry
        end,
    })
end

local function deliver(to, entry, from)
    if drop and drop(entry, to) then return end
    to.frame.scripts.OnEvent(to.frame, "CHAT_MSG_ADDON", to.prefix, entry.payload, entry.distribution,
        from.name .. "-" .. W.REALM)
end

-- Hands on everything sent since the last pump, until nothing new is sent.
local function pump()
    while delivered < #world.sent do
        delivered = delivered + 1
        local entry = world.sent[delivered]
        local from = byPrefix[entry.prefix]
        if not entry.refused then
            if entry.distribution == "WHISPER" then
                local to = byName[entry.target:lower()]
                if to then deliver(to, entry, from) end
            else
                for _, to in ipairs(players) do
                    if to ~= from then deliver(to, entry, from) end
                end
            end
        end
    end
end

-- Runs the world for `seconds`, firing timers as they fall due.
local function run(seconds)
    local stop = world.clock.now + seconds
    pump()
    while true do
        local soonest
        for _, entry in ipairs(timers) do
            if not entry.cancelled and (not soonest or entry.at < soonest.at) then soonest = entry end
        end
        if not soonest or soonest.at > stop then break end
        world.clock.now = math.max(world.clock.now, soonest.at)
        soonest.cancelled = true
        soonest.fn()
        pump()
    end
    world.clock.now = stop
end

local function setup()
    world = W.new()
    players, byPrefix, byName, delivered, drop, answer = {}, {}, {}, 0, nil, nil
    installTimers()
    -- SendAddonMessage keeps every call; a refused one is never delivered.
    world:set("SendAddonMessage", function(prefix, payload, distribution, target)
        local entry = { prefix = prefix, payload = payload, distribution = distribution, target = target,
            at = world.clock.now }
        local result = answer and answer(entry)
        entry.refused = result ~= nil and result ~= 0 and result ~= true
        world.sent[#world.sent + 1] = entry
        return result
    end)
end

-- Data that compresses to a few chunks.
local function data(lines, seed)
    local out, x = {}, seed or 1
    for i = 1, lines do
        x = (x * 1103515245 + 12345) % 2147483648
        out[i] = ("step %d: kill %d at %d, %d\n"):format(i, x % 1000, x % 97, x % 89)
    end
    return table.concat(out)
end

-- Every transfer frame of `kind` sent so far, with where it went.
local function sentOf(kind)
    local list = {}
    for _, entry in ipairs(world.sent) do
        if entry.payload:byte(1) == Comms.TRANSFER then
            local r = Comms.Reader(entry.payload)
            if r:U() == kind then list[#list + 1] = entry end
        end
    end
    return list
end
local DATA, MISSING, DECLINE = 4, 5, 3

-- A recorder of a sender's handlers.
local function sendHandlers()
    local h = { answers = {}, progress = {}, received = {}, ended = nil }
    h.onAnswer = function(who, accepted, reason) h.answers[#h.answers + 1] = { who.key, accepted, reason } end
    h.onProgress = function(sent, total) h.progress[#h.progress + 1] = { sent, total } end
    h.onReceived = function(who) h.received[#h.received + 1] = who.key end
    h.onEnd = function(why) h.ended = why end
    return h
end

local function receiveHandlers()
    local h = { progress = {} }
    h.onProgress = function(got, total) h.progress[#h.progress + 1] = { got, total } end
    h.onDone = function(okDone, result) h.ok, h.result = okDone, result end
    return h
end

-- Takes every offer to `player`, keeping them in a list.
local function collect(player)
    local offers = {}
    player.comms:OnOffer(function(offer) offers[#offers + 1] = offer end)
    return offers
end

--------------------------------------------------------------------------------

suite("A whispered transfer", function()
    before(setup)
    after(function() world:remove() end)

    test("arrives as it was offered, once accepted", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local bytes = data(400)
        local sh = sendHandlers()
        local transfer = assert(alice.comms:Offer("Bob", "the info", bytes, sh))
        run(1)
        eq(#offers, 1, "the offer reaches Bob")
        local offer = offers[1]
        eq(offer.who.key, "alice", "from Alice")
        eq(offer.source, "WHISPER", "by whisper")
        eq(offer.info, "the info", "with its info")
        eq(offer.rawSize, #bytes, "and the size it will be")
        ok(offer.size < #bytes, "sent compressed: " .. offer.size .. " of " .. #bytes)
        eq(#sentOf(DATA), 0, "no data before an answer")
        local rh = receiveHandlers()
        ok(offer:Accept(rh), "accepted")
        run(60)
        eq(rh.ok, true, "done")
        eq(rh.result, bytes, "the same bytes")
        local chunks = math.ceil(offer.size / CHUNK)
        eq(#sentOf(DATA), chunks, "each chunk sent once")
        eq(rh.progress[#rh.progress][1], chunks, "progress to the last chunk")
        eq(sh.answers[1][1], "bob", "Alice hears Bob's answer")
        eq(sh.answers[1][2], true, "an accept")
        eq(sh.progress[#sh.progress][1], chunks, "Alice's progress")
        eq(sh.received[1], "bob", "Alice hears Bob has it")
        eq(sh.ended, "done", "and the transfer ends done")
        eq(transfer:State(), "ended", "its state")
    end)

    test("sends no faster than the rate allows", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        alice.comms:Offer("Bob", "", data(1500, 3))
        run(1)
        offers[1]:Accept(receiveHandlers())
        run(120)
        local sends = sentOf(DATA)
        ok(#sends > 2 * Comms.TRANSFER_BURST, "enough chunks to see the rate: " .. #sends)
        local span = sends[#sends].at - sends[1].at
        local least = (#sends - Comms.TRANSFER_BURST) / Comms.TRANSFER_RATE
        ok(span >= least - 0.01, ("%d chunks over %.1f s, at least %.1f s"):format(#sends, span, least))
    end)

    test("ends declined, with the reason", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local sh = sendHandlers()
        alice.comms:Offer("Bob", "", data(100), sh)
        run(1)
        ok(offers[1]:Decline("have it"), "declined")
        run(1)
        eq(sh.answers[1][2], false, "a decline")
        eq(sh.answers[1][3], "have it", "with its reason")
        eq(sh.ended, "declined", "the transfer ends")
        eq(#sentOf(DATA), 0, "and nothing was sent")
    end)

    test("expires unanswered, and cannot be accepted after", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local sh = sendHandlers()
        alice.comms:Offer("Bob", "", data(100), sh)
        run(Comms.TRANSFER_TTL + 1)
        eq(sh.ended, "expired", "Alice's offer expires")
        local accepted, why = offers[1]:Accept(receiveHandlers())
        eq(accepted, false, "too late to accept")
        eq(why, "expired", "and why")
    end)

    test("asks again for chunks lost on the way", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local bytes = data(400, 5)
        local lost = 0
        drop = function(entry)
            if entry.payload:byte(1) ~= Comms.TRANSFER then return false end
            local r = Comms.Reader(entry.payload)
            if r:U() == DATA and r:U() and r:U() % 3 == 1 and lost < 3 then
                lost = lost + 1
                return true
            end
        end
        alice.comms:Offer("Bob", "", bytes)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(120)
        eq(lost, 3, "three chunks lost")
        ok(#sentOf(MISSING) >= 1, "Bob asked for them")
        eq(rh.result, bytes, "and has it all")
    end)

    test("asks for more gaps than one frame holds, a frame at a time", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        -- Bytes that do not compress, so the transfer is near its limit.
        local x, parts = 7, {}
        for i = 1, 60000 do
            x = x * 48271 % 2147483647
            parts[i] = string.char(x % 256)
        end
        local bytes = table.concat(parts)
        -- Every other chunk of the stream is lost, once.
        local lostAt = {}
        drop = function(entry)
            if entry.payload:byte(1) ~= Comms.TRANSFER then return false end
            local r = Comms.Reader(entry.payload)
            if r:U() ~= DATA then return false end
            r:U()
            local index = r:U()
            if index % 2 == 1 and not lostAt[index] then
                lostAt[index] = true
                return true
            end
        end
        alice.comms:Offer("Bob", "", bytes)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(600)
        local frames = sentOf(MISSING)
        ok(#frames >= 2, "Bob asked in more than one frame: " .. #frames)
        for _, entry in ipairs(frames) do
            ok(#entry.payload <= Comms.MAX_PAYLOAD, "each one fits a message")
        end
        eq(rh.result, bytes, "and has it all")
    end)

    test("waits out a client that refuses to send", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local bytes = data(400, 7)
        local refused = 0
        answer = function(entry)
            local r = Comms.Reader(entry.payload)
            if entry.payload:byte(1) == Comms.TRANSFER and r:U() == DATA and refused < 4 then
                refused = refused + 1
                return 3
            end
            return 0
        end
        alice.comms:Offer("Bob", "", bytes)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(120)
        eq(refused, 4, "four sends refused")
        eq(rh.result, bytes, "the bytes arrive all the same")
        eq(#sentOf(MISSING), 0, "with nothing to ask for")
    end)

    test("counts only the stream as the sender's progress, not its repairs", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local bytes = data(400, 5)
        local lost = 0
        drop = function(entry)
            if entry.payload:byte(1) ~= Comms.TRANSFER then return false end
            local r = Comms.Reader(entry.payload)
            if r:U() == DATA and r:U() and r:U() % 3 == 1 and lost < 3 then
                lost = lost + 1
                return true
            end
        end
        local sh = sendHandlers()
        alice.comms:Offer("Bob", "", bytes, sh)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(120)
        eq(rh.result, bytes, "repaired")
        local chunks = math.ceil(offers[1].size / CHUNK)
        ok(#sentOf(DATA) > chunks, "some chunks went twice")
        eq(#sh.progress, chunks, "one progress call a chunk")
        eq(sh.progress[#sh.progress][1], chunks, "ending at the count")
        eq(sh.ended, "done", "and the transfer ends done")
    end)

    test("fails when the client will not send its data, and lets the next one go", function()
        world:set("Enum", { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, NotInGroup = 5 } })
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local blocked = true
        answer = function(entry)
            local r = Comms.Reader(entry.payload)
            if blocked and entry.payload:byte(1) == Comms.TRANSFER and r:U() == DATA then return 5 end
            return 0
        end
        local first = sendHandlers()
        alice.comms:Offer("Bob", "", data(400, 1), first)
        run(1)
        offers[1]:Accept(receiveHandlers())
        run(5)
        eq(first.ended, "failed", "the first transfer fails")
        blocked = false
        -- Bob hears nothing more and gives up on it.
        run(Comms.TRANSFER_START + Comms.TRANSFER_QUIET * (Comms.TRANSFER_ASKS + 2))
        local bytes = data(400, 2)
        alice.comms:Offer("Bob", "", bytes)
        run(1)
        local rh = receiveHandlers()
        ok(offers[2]:Accept(rh), "the second is accepted")
        run(60)
        eq(rh.result, bytes, "and arrives")
    end)

    test("gives up on a throttle that never lifts", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        answer = function(entry)
            local r = Comms.Reader(entry.payload)
            if entry.payload:byte(1) == Comms.TRANSFER and r:U() == DATA then return 3 end
            return 0
        end
        local sh = sendHandlers()
        alice.comms:Offer("Bob", "", data(400, 1), sh)
        run(1)
        offers[1]:Accept(receiveHandlers())
        run(Comms.SEND_TRIES + 5)
        eq(sh.ended, "failed", "the transfer fails")
        eq(#sentOf(DATA), Comms.SEND_TRIES, "after SEND_TRIES tries")
    end)

    test("stops when the sender cancels", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local sh = sendHandlers()
        local transfer = alice.comms:Offer("Bob", "", data(1500, 9), sh)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(2)
        transfer:Cancel()
        local sent = #sentOf(DATA)
        run(30)
        eq(sh.ended, "cancelled", "Alice's ends cancelled")
        eq(rh.ok, false, "Bob's fails")
        eq(rh.result, "cancelled", "cancelled")
        eq(#sentOf(DATA), sent, "nothing sent after")
    end)

    test("stops when the receiver cancels", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local sh = sendHandlers()
        alice.comms:Offer("Bob", "", data(1500, 9), sh)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(2)
        ok(offers[1]:Cancel(), "Bob cancels")
        run(30)
        eq(rh.result, "cancelled", "Bob's ends")
        eq(sh.ended, "failed", "and Alice's")
    end)

    test("fails when the data was changed on the way", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local changed = false
        drop = function(entry, to)
            if entry.payload:byte(1) ~= Comms.TRANSFER or changed then return false end
            local r = Comms.Reader(entry.payload)
            if r:U() ~= DATA then return false end
            changed = true
            local id, index, bytes = r:U(), r:U(), r:Rest()
            bytes = string.char((bytes:byte(1) + 1) % 256) .. bytes:sub(2)
            local payload = Comms.Writer():U(DATA):U(id):U(index):Raw(bytes):FinishTransfer()
            deliver(to, { payload = payload, distribution = entry.distribution }, byPrefix[entry.prefix])
            return true
        end
        alice.comms:Offer("Bob", "", data(400, 11))
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(60)
        eq(rh.ok, false, "refused")
        eq(rh.result, "damaged", "as damaged")
    end)

    test("ends with comms switched off", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local sh = sendHandlers()
        alice.comms:Offer("Bob", "", data(1500), sh)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(2)
        bob.comms:SetEnabled(false)
        alice.comms:SetEnabled(false)
        eq(sh.ended, "cancelled", "Alice's")
        eq(rh.result, "cancelled", "Bob's")
    end)
end)

suite("A transfer to the party", function()
    before(setup)
    after(function() world:remove() end)

    test("sends its data once for everyone who accepts", function()
        local alice, bob, cara, dan = newPlayer("Alice"), newPlayer("Bob"), newPlayer("Cara"), newPlayer("Dan")
        local bobOffers, caraOffers, danOffers = collect(bob), collect(cara), collect(dan)
        local bytes = data(400, 13)
        local sh = sendHandlers()
        alice.comms:Offer("PARTY", "party info", bytes, sh)
        run(1)
        eq(bobOffers[1].source, "PARTY", "Bob hears it in the party")
        local bh, ch = receiveHandlers(), receiveHandlers()
        bobOffers[1]:Accept(bh)
        caraOffers[1]:Accept(ch)
        danOffers[1]:Decline("no")
        run(Comms.TRANSFER_TTL + 10)
        eq(bh.result, bytes, "Bob has it")
        eq(ch.result, bytes, "Cara has it")
        local chunks = math.ceil(bobOffers[1].size / CHUNK)
        local party, whispered = 0, 0
        for _, entry in ipairs(sentOf(DATA)) do
            if entry.distribution == "PARTY" then party = party + 1 else whispered = whispered + 1 end
        end
        eq(party, chunks, "each chunk once, to the party")
        eq(whispered, 0, "none whispered")
        eq(#sh.received, 2, "Alice hears both have it")
        eq(#sh.answers, 3, "and three answers")
        for _, entry in ipairs(sentOf(DECLINE)) do eq(entry.distribution, "WHISPER", "answers are whispered") end
        eq(sh.ended, "done", "done once the offer closes")
    end)

    test("repairs a late accepter by whisper", function()
        local alice, bob, cara = newPlayer("Alice"), newPlayer("Bob"), newPlayer("Cara")
        local bobOffers, caraOffers = collect(bob), collect(cara)
        local bytes = data(400, 15)
        local sh = sendHandlers()
        alice.comms:Offer("PARTY", "", bytes, sh)
        run(1)
        local bh, ch = receiveHandlers(), receiveHandlers()
        bobOffers[1]:Accept(bh)
        run(20)
        eq(bh.result, bytes, "Bob has it from the stream")
        caraOffers[1]:Accept(ch)
        run(Comms.TRANSFER_TTL + 30)
        eq(ch.result, bytes, "Cara has it too")
        local whispered = 0
        for _, entry in ipairs(sentOf(DATA)) do
            if entry.distribution == "WHISPER" then
                whispered = whispered + 1
                eq(entry.target, "Cara", "whispered to Cara")
            end
        end
        ok(whispered > 0, "the start whispered to her")
        eq(sh.ended, "done", "done")
    end)

    test("ends expired when nobody accepts", function()
        local alice = newPlayer("Alice")
        newPlayer("Bob")
        local sh = sendHandlers()
        alice.comms:Offer("PARTY", "", data(100), sh)
        run(Comms.TRANSFER_TTL + 5)
        eq(sh.ended, "expired", "expired")
        eq(#sentOf(DATA), 0, "no data")
    end)
end)

-- The client's result codes, where it names them.
local ENUM = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, NotInGroup = 5, ChannelThrottle = 8 } }

-- Whether a frame is transfer DATA, and whether it was whispered.
local function isData(entry)
    if entry.payload:byte(1) ~= Comms.TRANSFER then return false end
    return Comms.Reader(entry.payload):U() == DATA
end

-- Every message a player sent, in order.
local function sentBy(player)
    local list = {}
    for _, entry in ipairs(world.sent) do
        if entry.prefix == player.prefix then list[#list + 1] = entry end
    end
    return list
end

suite("A refused transfer", function()
    before(setup)
    after(function() world:remove() end)

    test("tries a throttled repair again", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local bytes = data(400, 5)
        local lost, throttled = 0, 0
        drop = function(entry)
            if not isData(entry) then return false end
            local r = Comms.Reader(entry.payload)
            r:U()
            if r:U() and r:U() == 1 and lost == 0 then
                lost = 1
                return true
            end
        end
        answer = function(entry)
            if isData(entry) and #sentOf(MISSING) > 0 and throttled < 2 then
                throttled = throttled + 1
                return 3
            end
        end
        local sh = sendHandlers()
        alice.comms:Offer("Bob", "", bytes, sh)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(120)
        eq(throttled, 2, "the repair was throttled twice")
        eq(rh.result, bytes, "and still arrived")
        eq(sh.ended, "done", "done")
    end)

    test("drops a repair the client will not send, and the receiver asks again", function()
        world:set("Enum", ENUM)
        local alice, bob, cara = newPlayer("Alice"), newPlayer("Bob"), newPlayer("Cara")
        local bobOffers, caraOffers = collect(bob), collect(cara)
        local bytes = data(400, 15)
        local refused = 0
        answer = function(entry)
            if isData(entry) and entry.distribution == "WHISPER" and refused < 2 then
                refused = refused + 1
                return 5
            end
        end
        local sh = sendHandlers()
        alice.comms:Offer("PARTY", "", bytes, sh)
        run(1)
        local bh, ch = receiveHandlers(), receiveHandlers()
        bobOffers[1]:Accept(bh)
        run(20)
        caraOffers[1]:Accept(ch)
        run(Comms.TRANSFER_TTL + 60)
        eq(refused, 2, "two repairs refused")
        ok(#sentOf(MISSING) >= 2, "Cara asked again")
        eq(bh.result, bytes, "Bob has it")
        eq(ch.result, bytes, "and Cara")
        eq(sh.ended, "done", "the transfer did not fail")
    end)

    test("fails a party transfer the client will not send, and lets the next one go", function()
        world:set("Enum", ENUM)
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        answer = function(entry)
            if isData(entry) and entry.distribution == "PARTY" then return 5 end
        end
        local first = sendHandlers()
        alice.comms:Offer("PARTY", "", data(400, 1), first)
        run(1)
        offers[1]:Accept(receiveHandlers())
        run(Comms.TRANSFER_START + 1)
        eq(first.ended, "failed", "the party transfer fails at its first refusal")
        eq(#sentOf(DATA), 1, "after one try")
        local bytes = data(400, 2)
        local second = sendHandlers()
        alice.comms:Offer("Cara", "", bytes, second)
        local cara = newPlayer("Cara")
        local caraOffers = collect(cara)
        run(1)
        local ch = receiveHandlers()
        caraOffers[1]:Accept(ch)
        run(60)
        eq(ch.result, bytes, "a whisper after it goes through")
        eq(second.ended, "done", "done")
    end)

    test("sends nothing more once cancelled while the client throttles it", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        answer = function(entry) if isData(entry) then return 3 end end
        local sh = sendHandlers()
        local transfer = alice.comms:Offer("Bob", "", data(400), sh)
        run(1)
        offers[1]:Accept(receiveHandlers())
        run(2)
        local before = #sentOf(DATA)
        ok(before >= 1, "data was tried")
        transfer:Cancel()
        run(30)
        eq(#sentOf(DATA), before, "and no more after the cancel")
        eq(sh.ended, "cancelled", "cancelled")
    end)

    test("ends cancelled when comms is switched off while the client throttles it", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        answer = function(entry) if isData(entry) then return 3 end end
        local sh = sendHandlers()
        alice.comms:Offer("Bob", "", data(400), sh)
        run(1)
        offers[1]:Accept(receiveHandlers())
        run(2)
        alice.comms:SetEnabled(false)
        local before = #sentOf(DATA)
        run(30)
        eq(sh.ended, "cancelled", "cancelled")
        eq(#sentOf(DATA), before, "nothing more tried")
    end)
end)

suite("A transfer beside the addon's own messages", function()
    before(setup)
    after(function() world:remove() end)

    test("shares the prefix's rate with them, and both get through", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local got = 0
        bob.comms:RegisterReceiver(function() got = got + 1 end)
        local bytes = data(1500, 3)
        alice.comms:Offer("Bob", "", bytes)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        run(0.5)
        for i = 1, 20 do alice.comms:Send(Comms.Writer():U(i):Finish(), "WHISPER", "Bob") end
        run(120)
        eq(rh.result, bytes, "the transfer arrives")
        eq(got, 20, "and every message")
        local list = sentBy(alice)
        for i = 1, #list do
            for j = i, #list do
                local span = list[j].at - list[i].at
                ok(j - i + 1 <= Comms.SEND_BURST + Comms.SEND_RATE * span + 1e-9,
                    ("%d of Alice's sends in %.2f s"):format(j - i + 1, span))
            end
        end
    end)

    test("holds the addon's messages while the client throttles the transfer", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local refusedAt
        answer = function(entry)
            if isData(entry) and not refusedAt then
                refusedAt = world.clock.now
                return 3
            end
        end
        alice.comms:Offer("Bob", "", data(400))
        run(1)
        offers[1]:Accept(receiveHandlers())
        run(0.5)
        ok(refusedAt, "the data was refused")
        local message = Comms.Writer():U(77):Finish()
        alice.comms:Send(message, "WHISPER", "Bob")
        run(10)
        for _, entry in ipairs(world.sent) do
            if entry.payload == message then
                ok(entry.at >= refusedAt + 1 - 1e-9, "the message waited out the hold")
            end
        end
    end)
end)

suite("A flooded receiver", function()
    before(setup)
    after(function() world:remove() end)

    test("gives up, tells the sender, and the sender's transfer fails", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local sh = sendHandlers()
        local transfer = alice.comms:Offer("Bob", "", data(1500, 4), sh)
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        local count = math.ceil(offers[1].size / CHUNK)
        local payload = Comms.Writer():U(DATA):U(transfer.id):U(0):Raw(string.rep("x", CHUNK)):FinishTransfer()
        for _ = 1, count * 3 + 21 do deliver(bob, { payload = payload, distribution = "WHISPER" }, alice) end
        eq(rh.ok, false, "Bob gives up")
        eq(rh.result, "failed", "as failed")
        run(5)
        local abandoned = false
        for _, entry in ipairs(sentBy(bob)) do
            if entry.payload:byte(1) == Comms.TRANSFER and Comms.Reader(entry.payload):U() == 8 then
                abandoned = true
                eq(entry.target, "Alice", "whispered to Alice")
            end
        end
        ok(abandoned, "Bob told Alice")
        eq(sh.ended, "failed", "Alice's transfer fails")
    end)
end)

suite("Transfer defenses", function()
    before(setup)
    after(function() world:remove() end)

    test("refuse what an offer cannot carry", function()
        local alice = newPlayer("Alice")
        local transfer, problem = alice.comms:Offer("Bob", string.rep("i", Comms.TRANSFER_INFO_MAX + 1), "x")
        eq(transfer, nil, "info too big")
        eq(problem, "info too big", "and why")
        transfer, problem = alice.comms:Offer("Bob", "", string.rep("x", Codec.INFLATE_MAX + 1))
        eq(problem, "too big", "bytes past what a receiver inflates")
        alice.comms:SetEnabled(false)
        transfer, problem = alice.comms:Offer("Bob", "", "x")
        eq(problem, "comms is off", "comms off")
    end)

    test("decline an offer past the limits without asking", function()
        local bob = newPlayer("Bob")
        local offers = collect(bob)
        local big = Comms.TRANSFER_MAX + 1
        local payload = Comms.Writer():U(1):U(5):U(math.ceil(big / CHUNK)):U(big):U(big):U32(0):FinishTransfer()
        world:inbound("TBob", payload, "WHISPER", "Eve")
        eq(#offers, 0, "the player is not asked")
        local declines = sentOf(DECLINE)
        eq(#declines, 1, "declined")
        eq(declines[1].target, "Eve", "to Eve")
    end)

    test("drop data for a transfer the player did not accept, without muting", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        alice.comms:Offer("Bob", "", data(400))
        run(1)
        for index = 0, 30 do
            local payload = Comms.Writer():U(DATA):U(999):U(index):Raw(string.rep("x", CHUNK)):FinishTransfer()
            deliver(bob, { payload = payload, distribution = "WHISPER" }, alice)
        end
        local rh = receiveHandlers()
        ok(offers[1]:Accept(rh), "Alice's offer can still be accepted")
        run(60)
        ok(rh.ok, "and arrives: Alice was not muted")
    end)

    test("call malformed data a violation, and mute after enough", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        local transfer = alice.comms:Offer("Bob", "", data(400))
        run(1)
        local rh = receiveHandlers()
        offers[1]:Accept(rh)
        for _ = 1, 12 do
            local payload = Comms.Writer():U(DATA):U(transfer.id):U(0):Raw("short"):FinishTransfer()
            deliver(bob, { payload = payload, distribution = "WHISPER" }, alice)
        end
        local muted = false
        for _, line in ipairs(bob.logs) do
            if line:find("session-muting alice", 1, true) then muted = true end
        end
        ok(muted, "Alice is muted on the whisper")
    end)

    test("show a sender a few offers a minute", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        for _ = 1, 8 do alice.comms:Offer("Bob", "", "small") end
        run(1)
        eq(#offers, 4, "four of eight")
    end)

    test("take one transfer at a time from a sender", function()
        local alice, bob = newPlayer("Alice"), newPlayer("Bob")
        local offers = collect(bob)
        alice.comms:Offer("Bob", "", data(1500, 1))
        alice.comms:Offer("Bob", "", data(1500, 2))
        run(1)
        ok(offers[1]:Accept(receiveHandlers()), "the first")
        local accepted, why = offers[2]:Accept(receiveHandlers())
        eq(accepted, false, "not the second")
        eq(why, "busy", "busy")
    end)

    test("leave transfer frames unread when nobody wants them", function()
        local bob = newPlayer("Bob")
        local payload = Comms.Writer():U(DATA):U(1):U(0):Raw("x"):FinishTransfer()
        for _ = 1, 20 do world:inbound("TBob", payload, "WHISPER", "Eve") end
        local count = 0
        for _, line in ipairs(bob.logs) do
            if line:find("eve", 1, true) then count = count + 1 end
        end
        eq(count, 0, "not even logged")
    end)
end)

print("NuuKit comms transfer tests passed (" .. W.count .. " tests)")
return true
