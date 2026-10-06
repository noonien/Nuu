-- The comms transport: how a payload leaves, how one arrives, and what the
-- destinations, the budgets and the defenses do to both. From Sonar's
-- tests/test_transport.lua; Sonar's realm route was its hidden channel, which
-- the kit does not have, so those tests use the party instead.
local Kit = _G.LoadKit().Kit
local W = dofile("Tests/Support/CommsWorld.lua")
local suite, test, before, after = W.suite, W.test, W.before, W.after
local ok, eq, errors = W.ok, W.eq, W.errors

local PREFIX = "NuuTest"
local world, comms, P, sent, mutedKeys, logs

-- Every test gets a world and an instance of its own, switched on, so a mute,
-- an echo or a budget from one cannot reach the next.
local function loadTransport(options)
    world = W.new(options)
    sent, mutedKeys, logs = world.sent, {}, {}
    comms = Kit.NewComms({
        prefix = PREFIX,
        log = function(message) logs[#logs + 1] = message end,
        muted = function(key) return mutedKeys[key] end,
    })
    P = comms._p
    comms:SetEnabled(true)
end

local function removeWorld() world:remove() end

local function transportSuite(name, body)
    suite(name, function()
        before(function() loadTransport() end)
        after(removeWorld)
        body()
    end)
end

local function frame(n) return Kit.Comms.Writer():U(n):Finish() end

local function inbound(payload, source, sender)
    world:inbound(PREFIX, payload, source, sender)
end

--------------------------------------------------------------------------------

transportSuite("A sender", function()
    test("needs a distribution", function()
        errors(function() comms:Sender(nil) end, "sender requires distribution")
        errors(function() comms:Send(frame(1)) end, "a send with no distribution is refused")
    end)

    test("goes only where an addon message can go", function()
        errors(function() comms:Sender("CHANNEL") end, "the channel is not a distribution")
        errors(function() comms:Send(frame(1), "CHANNEL", 7) end, "nor for a send")
        errors(function() comms:Sender("SAY") end, "say is not a distribution")
        for name in pairs(Kit.Comms.DISTRIBUTIONS) do
            ok(comms:Sender(name, name == "WHISPER" and "Zed" or nil), name .. " is a distribution")
        end
        local count = 0
        for _ in pairs(Kit.Comms.DISTRIBUTIONS) do count = count + 1 end
        eq(count, 7, "there are seven distributions")
        for _, name in ipairs({ "WHISPER", "PARTY", "RAID", "GUILD", "OFFICER",
            "BATTLEGROUND", "INSTANCE_CHAT" }) do
            ok(Kit.Comms.DISTRIBUTIONS[name], name .. " is listed")
        end
    end)

    test("needs a target to whisper", function()
        errors(function() comms:Sender("WHISPER") end, "a whisper with no target is refused")
        errors(function() comms:Sender("WHISPER", "") end, "a whisper to an empty name is refused")
        errors(function() comms:Sender("WHISPER", 12) end, "a whisper to a number is refused")
    end)

    test("drops the target of every other distribution", function()
        local party = comms:Sender("party", "Zed")
        eq(party.lane.distribution, "PARTY", "distribution normalized")
        eq(party.lane.target, nil, "the party has no target")
        ok(party:Send(frame(1)), "party accepted")
        eq(sent[1].distribution, "PARTY", "party route")
        eq(sent[1].target, nil, "the target is not passed on")
        ok(comms:Send(frame(2), "GUILD", "Zed"), "guild accepted")
        eq(sent[2].target, nil, "nor for a guild send")
    end)

    test("takes a payload of the size an addon message allows", function()
        errors(function() comms:Sender("PARTY"):Send(false) end, "send requires string")
        errors(function() comms:Sender("PARTY"):Send("x") end, "send rejects short payload")
        errors(function() comms:Sender("PARTY"):Send(string.rep("x", 256)) end,
            "send rejects oversized payload")
        local full = string.rep("x", 255)
        ok(comms:Sender("PARTY"):Send(full), "a payload at the cap is accepted")
        eq(#sent, 1, "a payload at the cap is transmitted")
        eq(sent[1].prefix, PREFIX, "a payload at the cap carries the addon prefix")
        eq(sent[1].payload, full, "all 255 bytes leave unchanged")
    end)

    test("refuses a payload while the transport is switched off", function()
        comms:SetEnabled(false)
        eq(comms:Send(frame(1), "PARTY"), false, "a disabled transport refuses outbound work")
        eq(comms:Sender("WHISPER", "Zed"):SendMultiple(function() return frame(1) end),
            false, "a disabled transport refuses a producer")
        eq(#sent, 0, "a disabled transport transmits nothing")
    end)

    test("refuses a forty-first job", function()
        -- Four go at once on the burst; the rest wait for tokens.
        for i = 1, 44 do
            eq(comms:Send(frame(i), "PARTY"), true, "job " .. i .. " is queued")
        end
        eq(#sent, 4, "the burst went out")
        eq(comms:Send(frame(45), "PARTY"), false, "the queue refuses work beyond QUEUE_MAX")
        eq(comms:Send(frame(45), "WHISPER", "Zed"), false, "the cap is across every destination")
        eq(#sent, 4, "a refused job does not transmit")
    end)

    test("needs a producer to send several", function()
        errors(function() comms:Sender("PARTY"):SendMultiple(false) end,
            "multiple requires producer")
    end)

    test("whispers the name as first given and shares one lane per name", function()
        local whisper = comms:Sender("whisper", "BoB")
        eq(whisper.lane.distribution, "WHISPER", "distribution normalized")
        eq(whisper.lane.target, "BoB", "the target keeps its spelling")
        local payload = frame(1)
        ok(whisper:Send(payload), "whisper accepted")
        eq(#sent, 1, "whisper sent immediately")
        eq(sent[1].prefix, PREFIX, "whisper carries the addon prefix")
        eq(sent[1].payload, payload, "whisper carries the frame unchanged")
        eq(sent[1].distribution, "WHISPER", "whisper route")
        eq(sent[1].target, "BoB", "the whisper goes to the name as given")
        local again = comms:Sender("WHISPER", "bob")
        eq(again.lane, whisper.lane, "another spelling of the name shares the lane")
        again:Send(frame(2))
        eq(sent[2].target, "BoB", "and sends to the first spelling")
        ok(comms:Sender("WHISPER", "Zed").lane ~= whisper.lane, "another name has its own lane")
    end)

    test("sends one message with Send", function()
        local payload = frame(1)
        ok(comms:Send(payload, "WHISPER", "Zed"), "a whisper send is accepted")
        eq(sent[1].distribution, "WHISPER", "Send takes the distribution")
        eq(sent[1].target, "Zed", "and the target")
        eq(sent[1].payload, payload, "and the payload")
    end)
end)

--------------------------------------------------------------------------------

transportSuite("The token bucket", function()
    test("sends the burst it has tokens for and schedules the rest", function()
        local frames = {}
        for i = 1, 5 do
            frames[i] = frame(i)
            ok(comms:Send(frames[i], "PARTY"), "burst message accepted " .. i)
        end
        eq(#sent, 4, "token bucket sends initial burst only")
        for i = 1, 4 do
            eq(sent[i].prefix, PREFIX, "burst prefix " .. i)
            eq(sent[i].payload, frames[i], "burst frame " .. i .. " leaves in order")
        end
        eq(#world.timers.timers, 1, "token exhaustion schedules retry")
        eq(world.timers:lastTimer().delay, 1, "token retry waits one second")
        world.clock:advance(world.timers:lastTimer().delay)
        world.timers:lastTimer().fn()
        eq(#sent, 5, "scheduled retry sends after refill")
        eq(sent[5].prefix, PREFIX, "fifth burst prefix")
        eq(sent[5].payload, frames[5], "fifth frame follows the first four")
    end)

    test("throttles each destination apart", function()
        for i = 1, 5 do comms:Send(frame(i), "PARTY") end
        eq(#sent, 4, "the party is out of tokens")
        ok(comms:Send(frame(9), "GUILD"), "a guild send is accepted")
        eq(#sent, 5, "and goes at once on its own bucket")
        eq(sent[5].distribution, "GUILD", "the fifth message is the guild one")
    end)

    test("drops what is queued when switched off", function()
        for i = 1, 6 do comms:Send(frame(i), "PARTY") end
        local retry = world.timers:lastTimer()
        comms:SetEnabled(false)
        ok(retry.cancelled, "the retry timer is cancelled")
        comms:SetEnabled(true)
        world.clock:advance(10)
        retry.fn()
        eq(#sent, 4, "nothing queued before the switch goes out")
        for i = 1, 4 do comms:Send(frame(i), "PARTY") end
        eq(#sent, 8, "the bucket is full again after the reset")
    end)
end)

--------------------------------------------------------------------------------
-- What SendAddonMessage answers, for the suites below: answer(entry) gives
-- the client's result (nil, taken, when there is no answer).
--------------------------------------------------------------------------------

local answer
local function answering()
    answer = nil
    world:set("SendAddonMessage", function(prefix, payload, distribution, target)
        local entry = { prefix = prefix, payload = payload, distribution = distribution, target = target,
            at = world.clock.now }
        sent[#sent + 1] = entry
        if answer then return answer(entry) end
    end)
end

-- Answers each send from a list in turn, then takes the rest.
local function answers(list)
    answer = function() return table.remove(list, 1) end
end

local ENUM = { SendAddonMessageResult = {
    Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4,
    NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9,
} }

-- Whether no window of the sends holds more than the burst and the rate allow.
local function withinRate(list, burst, rate)
    for i = 1, #list do
        for j = i, #list do
            local span = list[j].at - list[i].at
            if j - i + 1 > burst + rate * span + 1e-9 then
                return false, ("%d sends in %.2f s"):format(j - i + 1, span)
            end
        end
    end
    return true
end

--------------------------------------------------------------------------------

transportSuite("The shared bucket", function()
    before(answering)

    test("lets the instance's burst out across destinations, no more", function()
        for i = 1, 4 do comms:Send(frame(i), "PARTY") end
        for i = 1, 4 do comms:Send(frame(i), "GUILD") end
        for i = 1, 4 do comms:Send(frame(i), "RAID") end
        eq(#sent, Kit.Comms.SEND_BURST, "the burst went out")
        world:run(30)
        eq(#sent, 12, "and the rest later")
    end)

    test("refills at its rate, not the lane's", function()
        for i = 1, 4 do comms:Send(frame(i), "PARTY") end
        for i = 1, 4 do comms:Send(frame(i), "GUILD") end
        for i = 1, 3 do comms:Send(frame(i), "RAID") end
        eq(#sent, 10, "the raid lane still has tokens, the instance none")
        eq(world.timers:lastTimer().delay, 1 / Kit.Comms.SEND_RATE, "it waits for one shared token")
        world:run(1 / Kit.Comms.SEND_RATE)
        eq(#sent, 11, "then the raid message goes")
    end)

    test("keeps every destination together within the rate over time", function()
        for i = 1, 10 do
            comms:Send(frame(i), "PARTY")
            comms:Send(frame(i), "GUILD")
            comms:Send(frame(i), "RAID")
            comms:Send(frame(i), "WHISPER", "Zed")
        end
        world:run(60)
        eq(#sent, 40, "everything went")
        local fine, why = withinRate(sent, Kit.Comms.SEND_BURST, Kit.Comms.SEND_RATE)
        ok(fine, "within the shared rate: " .. tostring(why))
        local party = {}
        for _, entry in ipairs(sent) do
            if entry.distribution == "PARTY" then party[#party + 1] = entry end
        end
        fine, why = withinRate(party, 4, 1)
        ok(fine, "and each lane within its own: " .. tostring(why))
    end)

    test("is each instance's own", function()
        local other = Kit.NewComms({ prefix = "NuuOther" })
        other:SetEnabled(true)
        for i = 1, 4 do comms:Send(frame(i), "PARTY") end
        for i = 1, 4 do comms:Send(frame(i), "GUILD") end
        for i = 1, 4 do other:Send(frame(i), "PARTY") end
        for i = 1, 4 do other:Send(frame(i), "GUILD") end
        eq(#sent, 16, "another prefix draws on its own bucket")
    end)

    test("is full again, and any hold lifted, after comms is switched off and on", function()
        answers({ 3 })
        comms:Send(frame(1), "PARTY")
        comms:SetEnabled(false)
        comms:SetEnabled(true)
        for i = 1, 10 do comms:Send(frame(i), i % 2 == 0 and "PARTY" or "GUILD") end
        eq(#sent, 9, "no hold, and a full burst (the lanes' four each, one refused before)")
        world:run(30)
        eq(#sent, 11, "the held message was dropped with the rest")
    end)
end)

--------------------------------------------------------------------------------

transportSuite("A lane", function()
    test("is let go once idle, and a sender kept past it takes up the new one", function()
        local a = comms:Sender("WHISPER", "Ann")
        a:Send(frame(1))
        world.clock:advance(10)
        comms:Sender("WHISPER", "Zed")
        ok(comms:Sender("WHISPER", "Ann").lane ~= a.lane, "a new lane let the idle one go")
        a:Send(frame(2))
        eq(comms:Sender("WHISPER", "Ann").lane, a.lane, "the kept sender shares the new lane")
        eq(sent[2].target, "Ann", "and still whispers")
    end)

    test("is kept while its bucket is still refilling", function()
        for i = 1, 4 do comms:Send(frame(i), "WHISPER", "Ann") end
        world.clock:advance(1)
        comms:Sender("WHISPER", "Zed")
        comms:Send(frame(5), "WHISPER", "Ann")
        comms:Send(frame(6), "WHISPER", "Ann")
        eq(#sent, 5, "one token back, so one more goes, not a fresh burst")
    end)

    test("is kept while it has work queued", function()
        local ann = comms:Sender("WHISPER", "Ann")
        for i = 1, 5 do ann:Send(frame(i)) end
        world.clock:advance(10)
        comms:Sender("WHISPER", "Zed")
        eq(comms:Sender("WHISPER", "Ann").lane, ann.lane, "the busy lane stays")
        world:run(0)
        eq(#sent, 5, "and its queued message goes")
    end)
end)

--------------------------------------------------------------------------------

transportSuite("A refused message", function()
    before(answering)

    test("holds every destination for a second when throttled, then goes as it was", function()
        answers({ 3 })
        comms:Send(frame(1), "PARTY")
        comms:Send(frame(2), "GUILD")
        eq(#sent, 1, "the throttle holds the guild message too")
        eq(world.timers:lastTimer().delay, 1, "for a second")
        world:run(1)
        eq(#sent, 3, "both go after it")
        eq(sent[2].payload, frame(1), "the refused payload, unchanged")
        eq(sent[3].payload, frame(2), "and the guild one")
    end)

    test("keeps its place ahead of what was queued behind it", function()
        answers({ 3 })
        for i = 1, 3 do comms:Send(frame(i), "PARTY") end
        world:run(5)
        eq(#sent, 4, "three taken, one refused")
        eq(sent[2].payload, frame(1), "the refused one first")
        eq(sent[3].payload, frame(2), "then the second")
        eq(sent[4].payload, frame(3), "then the third")
    end)

    test("from a producer is sent again without asking the producer twice", function()
        answers({ 3 })
        local calls = 0
        comms:Sender("PARTY", nil, { repeatDelay = 5 }):SendMultiple(function()
            calls = calls + 1
            if calls <= 2 then return frame(calls) end
        end)
        world:run(1)
        eq(calls, 1, "the producer ran once")
        eq(sent[2].payload, frame(1), "its payload went again")
        world:run(20)
        eq(calls, 3, "then it went on as before")
        eq(sent[3].payload, frame(2), "with its next payload")
        eq(#sent, 3, "and nothing else")
    end)

    test("starts its tries afresh once a message goes", function()
        local tries = Kit.Comms.SEND_TRIES
        local list = {}
        for _ = 1, tries - 1 do list[#list + 1] = 3 end
        list[#list + 1] = 0
        for _ = 1, tries - 1 do list[#list + 1] = 3 end
        answers(list)
        local calls = 0
        comms:Sender("PARTY"):SendMultiple(function()
            calls = calls + 1
            if calls <= 2 then return frame(calls) end
        end)
        world:run(60)
        eq(#sent, 2 * tries, "every try made, none past")
        eq(sent[tries].payload, frame(1), "the first taken on its last try")
        eq(sent[#sent].payload, frame(2), "the second taken on its last try")
    end)

    test("gives up once its tries run out, and the lane goes on", function()
        answer = function(entry) if entry.payload == frame(1) then return 3 end end
        comms:Send(frame(1), "PARTY")
        comms:Send(frame(2), "PARTY")
        world:run(60)
        local first, second = 0, 0
        for _, entry in ipairs(sent) do
            if entry.payload == frame(1) then first = first + 1 else second = second + 1 end
        end
        eq(first, Kit.Comms.SEND_TRIES, "tried SEND_TRIES times")
        eq(second, 1, "the one behind it went once")
        eq(sent[#sent].payload, frame(2), "after it")
    end)

    test("is dropped at once when the client names a refusal that is not a throttle", function()
        world:set("Enum", ENUM)
        answers({ 5 })
        comms:Send(frame(1), "PARTY")
        comms:Send(frame(2), "GUILD")
        eq(#sent, 2, "no hold: the next one goes")
        world:run(30)
        eq(#sent, 2, "and the refused one is not tried again")
    end)

    test("is tried again on the client's channel throttle too", function()
        world:set("Enum", ENUM)
        answers({ 8 })
        comms:Send(frame(1), "PARTY")
        world:run(1)
        eq(#sent, 2, "tried again")
    end)

    test("is tried again on any refusal where the client names no throttle", function()
        world:set("Enum", { SendAddonMessageResult = { Success = 0 } })
        answers({ 5, false })
        comms:Send(frame(1), "PARTY")
        world:run(5)
        eq(#sent, 3, "tried until taken")
    end)

    test("is taken when the client answers nothing or true, as older clients do", function()
        answers({ true, nil, true })
        for i = 1, 3 do comms:Send(frame(i), "PARTY") end
        world:run(10)
        eq(#sent, 3, "each sent once")
    end)

    test("spends no token when refused", function()
        world:set("Enum", ENUM)
        answers({ 5, 5, 5, 5 })
        for i = 1, 8 do comms:Send(frame(i), "PARTY") end
        eq(#sent, 8, "four refused and four taken, all at once")
    end)

    test("survives a send call that raises", function()
        local raised = false
        world:set("SendAddonMessage", function(prefix, payload, distribution, target)
            sent[#sent + 1] = { payload = payload, at = world.clock.now }
            if not raised then
                raised = true
                error("client boom")
            end
        end)
        ok(pcall(comms.Send, comms, frame(1), "PARTY"), "the send does not raise")
        world:run(5)
        eq(#sent, 2, "it is tried again")
    end)

    test("from a producer that raises leaves the rest of its lane going", function()
        for i = 1, 4 do comms:Send(frame(i), "PARTY") end
        comms:Sender("PARTY"):SendMultiple(function() error("producer boom") end)
        comms:Send(frame(9), "PARTY")
        local timer = world.timers:lastTimer()
        world.clock:advance(timer.delay)
        timer.cancelled = true
        ok(not pcall(timer.fn), "the producer's error is raised")
        world:run(5)
        eq(sent[#sent].payload, frame(9), "the message behind it still goes")
    end)
end)

--------------------------------------------------------------------------------

transportSuite("A producer job", function()
    test("runs again after its delay and retires on the first nil", function()
        local produced = 0
        local sender = comms:Sender("WHISPER", "Target", { repeatDelay = 2 })
        ok(sender:SendMultiple(function()
            produced = produced + 1
            if produced <= 2 then return frame(produced) end
            return nil
        end), "producer job accepted")
        eq(produced, 1, "producer runs for first payload")
        eq(#sent, 1, "producer first payload sent")
        eq(sent[1].prefix, PREFIX, "producer first prefix")
        eq(sent[1].payload, frame(1), "producer first frame leaves first")
        world.clock:advance(2)
        world.timers:lastTimer().fn()
        eq(produced, 2, "producer runs again after delay")
        eq(#sent, 2, "producer second payload sent")
        eq(sent[2].prefix, PREFIX, "producer second prefix")
        eq(sent[2].payload, frame(2), "producer second frame leaves second")
        world.clock:advance(2)
        world.timers:lastTimer().fn()
        eq(produced, 3, "nil producer result retires job")
        eq(#sent, 2, "nil producer result sends nothing")
    end)

    test("waits for its initial delay", function()
        local produced = 0
        comms:Sender("PARTY", nil, { initialDelay = 5 }):SendMultiple(function()
            produced = produced + 1
            if produced == 1 then return frame(1) end
        end)
        eq(produced, 0, "the producer does not run before its delay")
        eq(world.timers:lastTimer().delay, 5, "it is scheduled for its delay")
        world.clock:advance(5)
        world.timers:lastTimer().fn()
        eq(#sent, 1, "it runs once the delay has passed")
    end)

    -- A producer that misbehaves is a programming error, not wire input, so
    -- the pump raises rather than dropping the payload quietly.

    test("that raises is reported", function()
        errors(function()
            comms:Sender("PARTY"):SendMultiple(function() error("producer boom") end)
        end, "a producer that raises is reported")
    end)

    test("that returns something other than a frame is reported", function()
        errors(function() comms:Sender("PARTY"):SendMultiple(function() return 17 end) end,
            "a producer returning a non-string is reported")
        P.resetTransport()
        errors(function() comms:Sender("PARTY"):SendMultiple(function() return "x" end) end,
            "a producer returning an empty frame is reported")
        P.resetTransport()
        errors(function()
            comms:Sender("PARTY"):SendMultiple(function() return string.rep("x", 256) end)
        end, "a producer returning an oversized frame is reported")
    end)

    test("that is reported leaves no queue slot behind", function()
        for _ = 1, 40 do
            pcall(function() comms:Sender("PARTY"):SendMultiple(function() return 17 end) end)
        end
        world.clock:advance(60)
        ok(comms:Send(frame(1), "GUILD"), "failed producers do not fill the queue")
    end)
end)

--------------------------------------------------------------------------------
-- Receivers here are named for PARTY and WHISPER; Sonar's tests used CHANNEL.
--------------------------------------------------------------------------------

transportSuite("An inbound packet", function()
    local received, secondCalls, onPacket, onSecond

    local function alsoListen(source)
        comms:RegisterReceiver(onPacket, source)
        comms:RegisterReceiver(onSecond, source)
    end

    before(function()
        received, secondCalls = {}, 0
        onPacket = function(who, _, source)
            received[#received + 1] = who.key .. ":" .. source
            if who.key == "eve" then return Kit.Comms.VIOLATION end
            if who.key == "crash" then error("receiver crash") end
        end
        onSecond = function() secondCalls = secondCalls + 1 end
        alsoListen("PARTY")
    end)

    test("arrives on a handler the transport registered", function()
        ok(world.events.CHAT_MSG_ADDON ~= nil, "addon-message handler registered")
    end)

    test("of another addon, our own echo, or a stranger, is dropped", function()
        world:inbound("Other", frame(1), "PARTY", "Alice-Spineshatter")
        eq(#received, 0, "other addon prefix ignored")
        inbound(frame(1), "PARTY", "Me")
        eq(#received, 0, "own echo ignored")
        inbound(frame(1), "PARTY", "Xarly-Thunderstrike")
        eq(#received, 0, "a sender from another realm is ignored")
        inbound(frame(1), "PARTY", "-Spineshatter")
        eq(#received, 0, "a sender with no name is ignored")
    end)

    test("reaches the receivers with a normalized sender", function()
        local who
        comms:RegisterReceiver(function(sender) who = sender end, "PARTY")
        inbound(frame(1), "PARTY", "Alice")
        eq(#received, 1, "valid packet delivered")
        eq(received[1], "alice:PARTY", "receiver gets normalized sender and source")
        eq(who.name, "Alice", "the receiver gets the name as the client spelled it")
        inbound(frame(1), "PARTY", "Alice")
        eq(#received, 2, "the same payload is delivered again")
        inbound(frame(1), "GUILD", "Alice")
        eq(#received, 2, "a source with no listener is discarded")
    end)

    test("with no listener is discarded before defenses", function()
        inbound(string.char(3, 2, 1), "WHISPER", "Bob")
        inbound(frame(3), "WHISPER", "Bob")
        alsoListen("WHISPER")
        inbound(frame(3), "WHISPER", "Bob")
        eq(#received, 1, "a source with no listener does not session-mute the sender")
        eq(received[1], "bob:WHISPER", "the whisper arrives once there is a listener")
    end)

    test("reaches a receiver for every source", function()
        local any = {}
        comms:RegisterReceiver(function(who, _, source) any[#any + 1] = who.key .. ":" .. source end)
        inbound(frame(1), "GUILD", "Alice")
        eq(#any, 1, "a receiver with no source hears a source nobody named")
        eq(any[1], "alice:GUILD", "with the source it came on")
        eq(#received, 0, "the party receiver does not")
        inbound(frame(2), "PARTY", "Alice")
        eq(#received, 1, "the party receiver hears the party")
        eq(#any, 2, "and so does the receiver for every source")
    end)

    test("counts a violation from a receiver for every source", function()
        comms:RegisterReceiver(function() return Kit.Comms.VIOLATION end)
        for i = 1, 12 do inbound(frame(i), "GUILD", "Gus") end
        local heard = 0
        comms:RegisterReceiver(function() heard = heard + 1 end, "GUILD")
        inbound(frame(13), "GUILD", "Gus")
        eq(heard, 0, "violations reported there mute the sender on that source")
    end)

    test("from a sender with no realm on it is still accepted", function()
        world:fire("CHAT_MSG_ADDON", PREFIX, frame(7), "PARTY", "Bareword")
        eq(#received, 1, "a sender that arrives with no realm is still accepted")
        eq(received[1], "bareword:PARTY", "the bare sender keys the same way")
    end)

    -- Sonar checked its ignore list and its muted hook apart; the kit has one
    -- muted(key) in the spec for both.
    test("from a muted sender is dropped", function()
        mutedKeys.dan = true
        inbound(frame(2), "PARTY", "Dan")
        eq(#received, 0, "muted sender dropped")
        inbound(frame(2), "PARTY", "Carl")
        eq(#received, 1, "another sender still arrives")
        mutedKeys.dan = nil
        inbound(frame(2), "PARTY", "Dan")
        eq(#received, 2, "the muted list is asked on every packet")
    end)

    test("arrives where the muted list raises", function()
        P.muted = function() error("muted list broken") end
        inbound(frame(2), "PARTY", "Dan")
        eq(#received, 1, "a muted list that raises mutes nobody")
    end)

    test("of another encoding mutes that source for the session", function()
        alsoListen("WHISPER")
        inbound(string.char(3, 2, 1), "PARTY", "Bob")
        inbound(frame(3), "PARTY", "Bob")
        eq(#received, 0, "wrong version session-mutes that source")
        inbound(frame(4), "WHISPER", "Bob")
        eq(#received, 1, "a party version-mute leaves whisper traffic")
    end)

    test("still reaches the later receivers where one raises", function()
        inbound(frame(4), "PARTY", "Crash")
        eq(received[#received], "crash:PARTY", "failing receiver was invoked")
        eq(secondCalls, 1, "receiver error does not block later receiver")
    end)

    test("mutes a sender who keeps sending violations", function()
        alsoListen("WHISPER")
        for i = 1, 11 do inbound(frame(100 + i), "WHISPER", "Eve") end
        eq(#received, 11, "violations delivered through threshold")
        inbound(frame(200), "WHISPER", "Eve")
        eq(#received, 11, "repeated violator session-muted on that source")
        inbound(frame(201), "PARTY", "Eve")
        eq(#received, 12, "a whisper mute leaves party traffic")
    end)

    test("keeps a session mute when comms is switched off and on", function()
        alsoListen("WHISPER")
        for i = 1, 12 do inbound(frame(100 + i), "WHISPER", "Eve") end
        eq(#received, 11, "the violator is muted")
        comms:SetEnabled(false)
        comms:SetEnabled(true)
        inbound(frame(200), "WHISPER", "Eve")
        eq(#received, 11, "switching off and on does not lift a session mute")
    end)

    test("counts against a per-source receive budget", function()
        alsoListen("WHISPER")
        for i = 1, 21 do inbound(frame(300 + i), "WHISPER", "Frank") end
        eq(#received, 20, "per-source receive budget enforced")
        eq(secondCalls >= 20, true, "ordinary receiver processed budgeted packets")
        inbound(frame(400), "PARTY", "Frank")
        eq(#received, 21, "a spent whisper budget leaves party traffic")
    end)

    -- A frame that carries the right version but no body is a violation, not
    -- a foreign encoding, so the sender keeps its voice.
    test("with our version and no body leaves the sender its voice", function()
        inbound(string.char(Kit.Comms.VERSION), "PARTY", "Hollow")
        eq(#received, 0, "an empty frame reaches no receiver")
        inbound(frame(12), "PARTY", "Hollow")
        eq(#received, 1, "one empty frame does not mute the sender")
    end)

    test("is ignored while the transport is switched off", function()
        comms:SetEnabled(false)
        inbound(frame(999), "PARTY", "Disabled")
        eq(#received, 0, "disabled transport ignores inbound traffic")
    end)
end)

--------------------------------------------------------------------------------
-- Housekeeping. The sweep runs at most every 30 seconds and drops budget
-- and violation rows that have aged out.
--------------------------------------------------------------------------------

transportSuite("The housekeeping sweep", function()
    test("forgets a spent budget once its window has passed", function()
        local received = {}
        comms:RegisterReceiver(function(who, _, source)
            received[#received + 1] = who.key .. ":" .. source
        end, "WHISPER")
        for i = 1, 21 do inbound(frame(300 + i), "WHISPER", "Frank") end
        eq(#received, 20, "the receive budget is spent")
        world.clock:advance(121)
        inbound(frame(400), "WHISPER", "Frank")
        eq(#received, 21, "a budget older than two windows is forgotten")
    end)
end)

--------------------------------------------------------------------------------
-- The log names the route it used. Sonar logged only with its debug setting
-- on; the kit logs whenever the addon gave it a log, prefixed "comms: ".
--------------------------------------------------------------------------------

transportSuite("The log", function()
    local function lastLog() return logs[#logs] end

    test("names an outbound route", function()
        comms:Send(frame(1), "PARTY")
        ok(lastLog():find("[party]", 1, true), "the party route is logged")
        eq(lastLog():sub(1, 7), "comms: ", "a line starts with comms:")
    end)

    test("names the target of a whisper", function()
        comms:Sender("WHISPER", "Zed"):Send(frame(5))
        ok(lastLog():find("whisper:Zed", 1, true), "a whisper is logged with its target")
    end)

    test("names an accepted packet", function()
        comms:RegisterReceiver(function() end, "PARTY")
        inbound(frame(11), "PARTY", "Logger")
        ok(lastLog():find("<- logger [party]", 1, true), "an accepted packet is logged")
    end)

    test("names a dropped packet and a session mute", function()
        comms:RegisterReceiver(function() end)
        inbound(string.char(3, 2, 1), "PARTY", "Bob")
        local found
        for _, line in ipairs(logs) do
            if line:find("session-muting bob on PARTY (version)", 1, true) then found = true end
        end
        ok(found, "the session mute is logged with its sender and source")
        ok(lastLog():find("xx bob (version)", 1, true), "the drop is logged with its reason")
    end)

    test("keeps quiet where the addon gave no log", function()
        local quiet = Kit.NewComms({ prefix = "NuuQuiet" })
        quiet:SetEnabled(true)
        local count = #logs
        ok(quiet:Send(frame(1), "PARTY"), "a send without a log still goes")
        eq(sent[#sent].prefix, "NuuQuiet", "and is transmitted")
        eq(#logs, count, "and logs nothing")
    end)
end)

--------------------------------------------------------------------------------
-- Anniversary clients send through C_ChatInfo; the bare global is the fallback.
--------------------------------------------------------------------------------

suite("The modern send path", function()
    before(function() loadTransport({ modern = true }) end)
    after(removeWorld)

    test("prefers C_ChatInfo over the legacy global", function()
        local cSent = world.cSent
        local partyPayload = frame(1)
        ok(comms:Send(partyPayload, "PARTY"), "modern party send accepted")
        eq(#sent, 0, "legacy SendAddonMessage is not used")
        eq(#cSent, 1, "C_ChatInfo.SendAddonMessage carries the party copy")
        eq(cSent[1].prefix, PREFIX, "modern party prefix")
        eq(cSent[1].payload, partyPayload, "modern party message")
        eq(cSent[1].distribution, "PARTY", "modern party chatType")
        eq(cSent[1].target, nil, "modern party has no target")

        local whisperPayload = frame(2)
        ok(comms:Sender("WHISPER", "Zed"):Send(whisperPayload), "modern whisper accepted")
        eq(#sent, 0, "a modern whisper still skips the legacy global")
        eq(#cSent, 2, "C_ChatInfo.SendAddonMessage carries the whisper")
        eq(cSent[2].prefix, PREFIX, "modern whisper prefix")
        eq(cSent[2].payload, whisperPayload, "modern whisper message")
        eq(cSent[2].distribution, "WHISPER", "modern whisper chatType")
        eq(cSent[2].target, "Zed", "modern whisper target")
    end)
end)

print("NuuKit comms transport tests passed (" .. W.count .. " tests)")
return true
