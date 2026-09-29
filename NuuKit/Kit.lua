local addonName, ns = ...

-- Every kit file adds itself to ns.Kit, creating it if missing. In development
-- ns is NuuKit's own table; in a release it is the host addon's.
local Kit = ns.Kit or {}
ns.Kit = Kit

--@debug@
-- Load probe for the split scaffolding. In development all addons share this
-- one list; in a release each addon's embedded kit has its own.
Kit.loadOrder = Kit.loadOrder or {}

function Kit.Loaded(owner, file)
    table.insert(Kit.loadOrder, owner .. "/" .. file)
end

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
end

-- Checks at PLAYER_LOGIN that the kit loaded before the addon's first file and
-- that the addon's global is its ns, then prints the result and the order.
function Kit.ReportLoad(owner, addonNS, firstFile)
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        local order = Kit.loadOrder
        local problems = {}

        local kitAt
        for i, entry in ipairs(order) do
            if entry:match("/Kit%.lua$") then kitAt = i break end
        end
        local firstAt = IndexOf(order, owner .. "/" .. firstFile)
        if not kitAt then
            table.insert(problems, "kit never loaded")
        elseif not firstAt then
            table.insert(problems, firstFile .. " never recorded")
        elseif kitAt > firstAt then
            table.insert(problems, "kit loaded after " .. firstFile)
        end
        if _G[owner] ~= addonNS then
            table.insert(problems, "_G." .. owner .. " is not the addon table")
        end

        local copy = (_G.NuuKit == Kit) and "shared dev kit" or "embedded kit"
        local verdict = #problems == 0 and "|cff44dd44load order OK|r"
            or ("|cffff4444" .. table.concat(problems, "; ") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage(("|cff4cc9f0%s|r: %s (%s)"):format(owner, verdict, copy))
        DEFAULT_CHAT_FRAME:AddMessage("  " .. table.concat(order, " > "))
    end)
end

Kit.Loaded(addonName, "Kit.lua")
--@end-debug@
