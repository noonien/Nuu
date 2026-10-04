-- Kit.NewComms itself: the spec it takes, what it registers and binds when it
-- is made, the receiver list, the enabled switch and names. From Sonar's
-- tests/test_comms_init.lua.
local Kit = _G.LoadKit().Kit
local W = dofile("Tests/Support/CommsWorld.lua")
local suite, test, before, after = W.suite, W.test, W.before, W.after
local ok, eq, errors, spy = W.ok, W.eq, W.errors, W.spy

local world, comms, P, logs

local function build(options)
    world = W.new(options)
    logs = {}
    comms = Kit.NewComms({
        prefix = "NuuTest",
        log = function(message) logs[#logs + 1] = message end,
    })
    P = comms._p
    return comms
end

local function removeWorld() world:remove() end

local function receivers(source) return P.receivers[source] or {} end

--------------------------------------------------------------------------------

suite("The spec", function()
    before(function() world = W.new() end)
    after(removeWorld)

    test("needs a table", function()
        errors(function() Kit.NewComms() end, "no spec is refused")
    end)

    test("needs a prefix of one to sixteen characters", function()
        errors(function() Kit.NewComms({}) end, "no prefix is refused")
        errors(function() Kit.NewComms({ prefix = "" }) end, "an empty prefix is refused")
        errors(function() Kit.NewComms({ prefix = string.rep("x", 17) }) end,
            "a prefix over sixteen characters is refused")
        ok(Kit.NewComms({ prefix = string.rep("x", 16) }), "a sixteen-character prefix is taken")
    end)

    test("needs nothing else", function()
        local made = Kit.NewComms({ prefix = "NuuTest" })
        eq(made.prefix, "NuuTest", "the instance keeps its prefix")
        eq(made:IsEnabled(), false, "and starts switched off")
    end)
end)

--------------------------------------------------------------------------------
-- Sonar registered the prefix and bound the transport at login; the kit does
-- it when the instance is made.
--------------------------------------------------------------------------------

suite("Making an instance", function()
    after(removeWorld)

    test("registers the prefix through C_ChatInfo where there is one", function()
        build({ modern = true })
        eq(world.prefixes[1], "NuuTest", "the prefix is registered through C_ChatInfo")
        eq(#world.legacyPrefixes, 0, "and not through the older call")
    end)

    test("falls back to the older prefix call where there is not", function()
        build()
        eq(world.legacyPrefixes[1], "NuuTest", "the prefix is registered through the legacy call")
    end)

    test("binds the transport", function()
        build()
        eq(#world.frames, 1, "one frame for the instance's events")
        ok(world:registered("CHAT_MSG_ADDON"), "the transport listens for addon messages")
        eq(next(P.receivers), nil, "nothing is registered as a receiver")
    end)

    test("binds nothing on a client without the calls it needs", function()
        world = W.new()
        world:set("CreateFrame", nil)
        local supported, missing = Kit.Comms.Supported()
        eq(supported, false, "the client is not supported")
        eq(missing[1], "CreateFrame", "the missing call is named")
        comms = Kit.NewComms({ prefix = "NuuTest" })
        eq(#world.frames, 0, "no frame is made")
        eq(#world.legacyPrefixes, 1, "the prefix is still registered")
    end)

    test("needs only a timer, the time, a frame and a send call", function()
        world = W.new()
        eq(Kit.Comms.Supported(), true, "C_Timer.NewTimer alone of C_Timer is enough")
        for _, name in ipairs({ "GetTime", "C_Timer" }) do
            local saved = _G[name]
            _G[name] = nil
            eq(Kit.Comms.Supported(), false, name .. " is needed")
            _G[name] = saved
        end
        world:set("SendAddonMessage", nil)
        local supported, missing = Kit.Comms.Supported()
        eq(supported, false, "no send call is not supported")
        eq(missing[1], "SendAddonMessage", "the missing send call is named")
        world:remove()
        world = W.new({ modern = true })
        world:set("SendAddonMessage", nil)
        eq(Kit.Comms.Supported(), true, "C_ChatInfo.SendAddonMessage alone is enough")
    end)

    test("keeps two instances apart", function()
        build()
        local other = Kit.NewComms({ prefix = "NuuOther" })
        local mine, theirs = 0, 0
        comms:RegisterReceiver(function() mine = mine + 1 end)
        other:RegisterReceiver(function() theirs = theirs + 1 end)
        comms:SetEnabled(true)
        other:SetEnabled(true)
        world:inbound("NuuOther", Kit.Comms.Writer():U(1):Finish(), "PARTY", "Alice")
        eq(mine, 0, "a message under the other prefix does not reach this instance")
        eq(theirs, 1, "it reaches the other one")
        eq(#world.frames, 2, "each instance has its own frame")
    end)
end)

--------------------------------------------------------------------------------

suite("The receiver list", function()
    before(function() build() end)
    after(removeWorld)

    test("takes a function and nothing else", function()
        errors(function() comms:RegisterReceiver(false) end, "receiver must be a function")
    end)

    test("keeps a receiver with no source for every source", function()
        local receiver = function() end
        comms:RegisterReceiver(receiver)
        eq(receivers("*")[1], receiver, "a receiver with no source is kept under every source")
        eq(#receivers("CHANNEL"), 0, "there is no channel default any more")
    end)

    test("keeps a receiver on the source it was named for", function()
        local party, whisper = function() end, function() end
        comms:RegisterReceiver(party, "PARTY")
        comms:RegisterReceiver(whisper, "whisper")
        eq(receivers("PARTY")[1], party, "party receiver is on PARTY")
        eq(receivers("WHISPER")[1], whisper, "whisper receiver is on WHISPER, upper-cased")
        eq(#receivers("GUILD"), 0, "an unnamed source has no listeners")
    end)

    test("needs a string source when one is given", function()
        errors(function() comms:RegisterReceiver(function() end, 1) end,
            "a non-string source is refused")
    end)
end)

--------------------------------------------------------------------------------

suite("The enabled switch", function()
    local reset

    before(function()
        build()
        reset = spy()
        P.resetTransport = reset
    end)
    after(removeWorld)

    test("turns on", function()
        eq(comms:SetEnabled(true), true, "enable says it is on")
        eq(comms:IsEnabled(), true, "enable updates state")
        eq(reset.calls, 0, "turning on resets nothing")
    end)

    test("does nothing on a repeated enable", function()
        comms:SetEnabled(true)
        eq(comms:SetEnabled(true), true, "a repeated enable still says it is on")
        eq(reset.calls, 0, "repeated enable is no-op")
    end)

    test("resets the transport on the way down", function()
        comms:SetEnabled(true)
        eq(comms:SetEnabled(false), false, "disable says it is off")
        eq(comms:IsEnabled(), false, "disable updates state")
        eq(reset.calls, 1, "disable resets transport")
    end)

    test("does nothing on a repeated disable", function()
        comms:SetEnabled(true)
        comms:SetEnabled(false)
        comms:SetEnabled(false)
        eq(reset.calls, 1, "repeated disable is no-op")
        eq(comms:SetEnabled(false), false, "and says it is off")
    end)

    test("refuses on a client without the calls it needs", function()
        world:set("GetTime", nil)
        eq(comms:SetEnabled(true), false, "enable refuses")
        eq(comms:IsEnabled(), false, "and stays off")
        eq(logs[#logs], "comms: not supported on this client", "the refusal is logged")
    end)

    test("has no status any more", function()
        eq(comms.Status, nil, "Status went with the channel")
    end)
end)

--------------------------------------------------------------------------------
-- Names. Sonar's NormalizeName lived in its Data.lua; the kit's instance reads
-- the realm and the player itself.
--------------------------------------------------------------------------------

suite("Names", function()
    before(function() build() end)
    after(removeWorld)

    test("drop our own realm and refuse another", function()
        local who = P.normalize("Alice-Spineshatter")
        eq(who.key, "alice", "the key is lower case")
        eq(who.name, "Alice", "the name keeps its spelling, realm dropped")
        eq(P.normalize("Alice-Thunderstrike"), nil, "another realm is refused")
        eq(P.normalize("-Spineshatter"), nil, "no name is refused")
        eq(P.normalize("Bare").key, "bare", "a bare name is taken")
        eq(P.normalize(""), nil, "an empty name is refused")
        eq(P.normalize(nil), nil, "no name at all is refused")
    end)

    test("know the player", function()
        ok(P.isPlayer("me"), "the player is the lower-case unit name")
        ok(not P.isPlayer("alice"), "and no one else")
    end)

    test("know the player by a surname, as WoW: Forever names them", function()
        world:set("UnitName", function(unit) if unit == "player" then return "Dill", "Douse" end end)
        P = Kit.NewComms({ prefix = "NuuTest" })._p
        ok(P.isPlayer("dill douse"), "the sender spelling the client uses")
        ok(P.isPlayer("dill"), "the bare name")
        local who = P.normalize("Dill Douse")
        eq(who.key, "dill douse", "a name with a space is one key")
        eq(who.name, "Dill Douse", "and keeps its spelling")
    end)

    test("read the realm from its plain name where there is no normalized one", function()
        world:set("GetNormalizedRealmName", nil)
        world:set("GetRealmName", function() return "Spine Shat-ter" end)
        P = Kit.NewComms({ prefix = "NuuTest" })._p
        eq(P.realm(), "SpineShatter", "spaces and dashes are taken out")
        eq(P.normalize("Alice-SpineShatter").key, "alice", "and senders are matched against it")
    end)
end)

print("NuuKit comms tests passed (" .. W.count .. " tests)")
return true
