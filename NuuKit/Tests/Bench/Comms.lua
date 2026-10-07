-- The comms' cost (Core/Comms/): a frame written and read, one message sent
-- and one received through an instance, and whole transfers between players
-- on a stand-in network (Tests/Support/CommsWorld.lua).
-- From NuuKit/: nix-shell -p lua5_1 --run "lua Tests/Bench/Comms.lua"
--
-- Per call: Lua time and the bytes it allocates. A transfer also gives what
-- went over the wire and how long it takes at the comms' rates; its time
-- includes the Deflate and Inflate that Tests/Bench/Codec.lua times alone.

BENCH = "Tests/Bench/"
local B = dofile(BENCH .. "Measure.lua")
local Kit = B.LoadKit()
local W = dofile("Tests/Support/CommsWorld.lua")
local Codec, Comms = Kit.Codec, Kit.Comms

print(("Comms bench (%s)"):format(_VERSION))

-- Frames ------------------------------------------------------------------------

local function hello(w) return w:U(1):U(4321):Bytes("Dill"):I(-300):True() end
local CHUNK = Comms.TRANSFER_CHUNK
local chunk = B.Body(Codec, CHUNK):sub(1, CHUNK)
local function data(w) return w:U(4):U(123456):U(80):Raw(chunk) end
-- The most a frame's body holds, all NULs: COBS's longest work.
local zeros = string.rep("\0", Comms.MAX_PAYLOAD - 2)

local helloFrame, dataFrame = hello(Comms.Writer()):Finish(), data(Comms.Writer()):FinishTransfer()
local zeroFrame = Comms.Writer():Raw(zeros):Finish()

B.Header("Frames")
B.Row("Writer: a message (5 fields) + Finish", B.Measure(function() hello(Comms.Writer()):Finish() end), nil,
    #helloFrame)
B.Row("Reader: the message", B.Measure(function()
    local r = Comms.Reader(helloFrame)
    r:U(); r:U(); r:Bytes(); r:I(); r:Bool()
end), #helloFrame)
B.Row("Writer: a transfer's data + Finish", B.Measure(function() data(Comms.Writer()):FinishTransfer() end), nil,
    #dataFrame)
B.Row("Reader: the data", B.Measure(function()
    local r = Comms.Reader(dataFrame)
    r:U(); r:U(); r:U(); r:Rest()
end), #dataFrame)
B.Row("Writer: 253 NULs + Finish", B.Measure(function() Comms.Writer():Raw(zeros):Finish() end), nil, #zeroFrame)
B.Row("Reader: 253 NULs", B.Measure(function() Comms.Reader(zeroFrame):Rest() end), #zeroFrame)

-- One message through an instance --------------------------------------------------

-- The clock moves on between calls so no throttle or budget is reached:
-- this is the cost of the path, not of waiting.
do
    local world = W.new()
    local sent = 0
    world:set("SendAddonMessage", function() sent = sent + 1 end)
    local comms = Kit.NewComms({ prefix = "NuuBench" })
    comms:SetEnabled(true)
    local frame = world.frames[#world.frames]
    comms:RegisterReceiver(function(_, payload)
        local r = Comms.Reader(payload)
        r:U(); r:U(); r:Bytes(); r:I(); r:Bool()
        if not r:Ok() then return Comms.VIOLATION end
    end, "PARTY")
    local party = comms:Sender("PARTY")

    B.Header("One message")
    B.Row("Send: to the party", B.Measure(function()
        world.clock:advance(61)
        comms:Send(helloFrame, "PARTY")
    end))
    B.Row("Send: through a kept Sender", B.Measure(function()
        world.clock:advance(61)
        party:Send(helloFrame)
    end))
    B.Row("Receive: CHAT_MSG_ADDON to a reader", B.Measure(function()
        world.clock:advance(61)
        frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", "NuuBench", helloFrame, "PARTY", "Dill-" .. W.REALM)
    end))
    B.Row("Receive: another addon's prefix", B.Measure(function()
        frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", "Other", helloFrame, "PARTY", "Dill-" .. W.REALM)
    end))
    assert(sent > 0, "the bench sent through the stand-in")
    world:remove()
end

-- Transfers -----------------------------------------------------------------------

-- Players on one network, each its own comms instance and prefix (as in
-- Tests/Core/Comms/TransferTests.lua): a whisper reaches its target, a party
-- message everyone else. Every receiver accepts at once. Returns the stats.
local function transfer(bytes, receivers)
    local world = W.new()
    local timers, players, byPrefix, byName, wire = {}, {}, {}, {}, { messages = 0, bytes = 0, data = 0 }
    world:set("C_Timer", {
        NewTimer = function(delay, fn)
            local entry = { at = world.clock.now + delay, fn = fn }
            function entry:Cancel() self.cancelled = true end
            timers[#timers + 1] = entry
            return entry
        end,
    })
    local queue = {}
    world:set("SendAddonMessage", function(prefix, payload, distribution, target)
        wire.messages = wire.messages + 1
        wire.bytes = wire.bytes + #payload
        if payload:byte(1) == Comms.TRANSFER and Comms.Reader(payload):U() == 4 then wire.data = wire.data + 1 end
        queue[#queue + 1] = { prefix, payload, distribution, target }
    end)
    local function deliver(to, payload, distribution, from)
        to.frame.scripts.OnEvent(to.frame, "CHAT_MSG_ADDON", to.prefix, payload, distribution, from .. "-" .. W.REALM)
    end
    local function pump()
        local i = 1
        while i <= #queue do
            local prefix, payload, distribution, target = unpack(queue[i])
            local from = byPrefix[prefix]
            if distribution == "WHISPER" then
                deliver(byName[target:lower()], payload, distribution, from.name)
            else
                for _, to in ipairs(players) do
                    if to ~= from then deliver(to, payload, distribution, from.name) end
                end
            end
            i = i + 1
        end
        for k = #queue, 1, -1 do queue[k] = nil end
    end

    local done = 0
    local function player(name)
        local comms = Kit.NewComms({ prefix = "T" .. name })
        local p = { name = name, prefix = "T" .. name, comms = comms, frame = world.frames[#world.frames] }
        comms:SetEnabled(true)
        players[#players + 1], byPrefix[p.prefix], byName[name:lower()] = p, p, p
        comms:OnOffer(function(offer)
            offer:Accept({ onDone = function(ok, back)
                assert(ok and back == bytes, "a transfer arrives as it was offered")
                done = done + 1
            end })
        end)
        return p
    end
    local sender = player("Alice")
    local names = {}
    for i = 1, receivers do names[i] = player("Bob" .. i).name end

    local start = world.clock.now
    sender.comms:Offer(receivers == 1 and names[1] or "PARTY", "info", bytes)
    pump()
    while done < receivers do
        local soonest
        for _, entry in ipairs(timers) do
            if not entry.cancelled and (not soonest or entry.at < soonest.at) then soonest = entry end
        end
        assert(soonest and soonest.at - start < 600, "a transfer finishes")
        world.clock.now = math.max(world.clock.now, soonest.at)
        soonest.cancelled = true
        soonest.fn()
        pump()
    end
    world:remove()
    wire.seconds = world.clock.now - start
    return wire
end

local function transfers(name, bytes)
    local packed = #Codec.Deflate(bytes)
    B.Header(("Transfers of %s (%d B, %d deflated)"):format(name, #bytes, packed))
    for _, receivers in ipairs({ 1, 4 }) do
        local wire = transfer(bytes, receivers)
        local label = receivers == 1 and "Whispered to one player" or ("To the party, %d accept"):format(receivers)
        B.Row(label, B.Measure(function() transfer(bytes, receivers) end), #bytes)
        print(("  %d messages (%d of data), %d B on the wire, done in %.1f s"):format(wire.messages, wire.data,
            wire.bytes, wire.seconds))
    end
end
transfers("4 KB", B.Body(Codec, 4 * 1024))
transfers("30 KB", B.Body(Codec, 30 * 1024))
