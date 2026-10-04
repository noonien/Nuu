local _, ns = ...

-- What NuuKit's comms (Kit.NewComms, from Sonar) needs from this client: the
-- addon-message calls and how its own messages come back (sender spelling,
-- echo, which bytes survive). Whispers itself (as "Name Surname", Name-Realm
-- and Name), and sends to the party and the guild when it is in one. The
-- guild hands our own messages back (2026-10-05), so the byte tests go there.
local PREFIX = "NuuX"

ns:Experiment({
    id = "addon-comms",
    title = "Addon messages: whisper, party, guild",
    run = function(t)
        t:Exists({
            "C_ChatInfo.SendAddonMessage", "SendAddonMessage",
            "C_ChatInfo.RegisterAddonMessagePrefix", "RegisterAddonMessagePrefix",
            "C_ChatInfo.IsAddonMessagePrefixRegistered",
            "GetNormalizedRealmName", "GetRealmName", "GetServerTime", "C_Timer.NewTimer",
            "IsInGroup", "IsInGuild",
        })
        t:Try("realm", GetNormalizedRealmName)
        t:Try("player", UnitName, "player")
        t:Set("SendAddonMessageResult", Enum and Enum.SendAddonMessageResult)

        local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
        local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
        t:Try("register", register, PREFIX)
        if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered then
            t:Try("registered", C_ChatInfo.IsAddonMessagePrefixRegistered, PREFIX)
        end

        -- t:Set copies a table, so these are kept once the run is over.
        local received, system = {}, {}
        t:On("CHAT_MSG_SYSTEM", function(_, text)
            system[#system + 1] = text
        end)
        t:On("CHAT_MSG_ADDON", function(_, prefix, message, source, sender, target)
            if prefix ~= PREFIX then return end
            local row = { source = source, sender = sender, target = target, length = #message }
            if #message > 32 or message:find("[^\32-\126]") then
                row.message = "(" .. #message .. " bytes)"
            else
                row.message = message
            end
            row.raw = message
            received[#received + 1] = row
        end)

        -- A NUL cannot ride an addon message; COBS keeps it out. This checks
        -- that every other byte value 1..255 arrives as sent ("|" included).
        local bytes = {}
        for i = 1, 255 do bytes[i] = string.char(i) end
        local allBytes = table.concat(bytes)

        local me, surname = UnitName("player")
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        local spaced = surname and (me .. " " .. surname) or me
        local full = realm and (me .. "-" .. realm) or me
        t:Try("whisperSpaced", send, PREFIX, "\1\2spaced", "WHISPER", spaced)
        t:Try("whisperFull", send, PREFIX, "\1\2full", "WHISPER", full)
        t:Try("whisperBare", send, PREFIX, "\1\2bare", "WHISPER", me)
        if IsInGroup and IsInGroup() then
            t:Try("party", send, PREFIX, "\1\2party", "PARTY")
        end
        if IsInGuild and IsInGuild() then
            t:Try("guild", send, PREFIX, "\1\2guild", "GUILD")
            t:Try("guildPipe", send, PREFIX, "a|b", "GUILD")
            t:Try("guildEscape", send, PREFIX, "a|cffff0000b|r", "GUILD")
            t:Try("guildHigh", send, PREFIX, "\128\200\255", "GUILD")
            t:Try("guildAllBytes", send, PREFIX, allBytes, "GUILD")
            t:Try("guildTooLong", send, PREFIX, allBytes .. "x", "GUILD")
        end

        t:Wait(15)
        t:After(5, function()
            for _, row in ipairs(received) do
                if row.length >= 255 then
                    row.allBytesIntact = row.raw:sub(1, 255) == allBytes
                    -- The first byte that differs, when one does.
                    for i = 1, math.min(#row.raw, 255) do
                        if row.raw:byte(i) ~= i then row.firstBad = i break end
                    end
                elseif row.message:find("bytes") then
                    local codes = {}
                    for i = 1, math.min(#row.raw, 16) do codes[i] = row.raw:byte(i) end
                    row.bytes = codes
                end
                row.raw = nil
            end
            t:Set("received", received)
            t:Set("system", system)
            t:Done()
        end)
    end,
})
