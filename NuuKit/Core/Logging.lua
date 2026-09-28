local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Gives an addon's `ns` the logging calls every file of it uses:
--
--     ns:Print("shown in chat")
--     ns:Log("shown in chat only while debugging")
--     ns:Record("rec", { event = "accept", quest = 3091 })
--     ns:RecordHere("mark", { npc = 3143 })  -- adds map and position
--     ns:Trace("planner", { event = "plan", reason = "open" })
--     if ns:Tracing() then ... end            -- whether a trace row is kept
--
-- The last four go to `ns.recorder` (a `Kit.NewRecorder`), and are safe before
-- it is set and if it never is. `options`:
--
--     label   the chat prefix, `ns.name` unless given
--     debug   function: whether `Log` prints; the addon reads its own setting
--
-- Everything is kept on the addon's table, never on the kit, so two addons
-- sharing one kit in development keep their own prefix and debug switch.
function Kit.AddLogging(target, options)
    options = options or {}
    local prefix = "|cff4cc9f0" .. tostring(options.label or target.name or "?") .. "|r"
    local debug = options.debug

    function target:Print(message)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(prefix .. ": " .. tostring(message))
        end
    end

    function target:Log(message)
        if not debug then return end
        local ok, on = pcall(debug)
        if ok and on then
            self:Print("|cff8899aa[debug]|r " .. tostring(message))
        end
    end

    function target:Record(channel, data)
        local recorder = self.recorder
        if not recorder then return nil end
        return recorder:Record(channel, data)
    end

    function target:RecordHere(channel, data)
        local recorder = self.recorder
        if not recorder then return nil end
        return recorder:RecordHere(channel, data)
    end

    function target:Trace(channel, data)
        local recorder = self.recorder
        if not recorder then return nil end
        return recorder:Trace(channel, data)
    end

    function target:Tracing()
        local recorder = self.recorder
        return recorder and recorder:Tracing() or false
    end

    return target
end
