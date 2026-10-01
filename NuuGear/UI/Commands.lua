local _, ns = ...

-- /nuugear (/ngear):
--   /nuugear               the spec items are scored for, and the others
--   /nuugear spec <name>   score for that spec ("auto": back to the talents)
--   /nuugear check <item>  how an item (shift-click it in) compares, and why
--   /nuugear debug         the debug log on or off
local Commands = {}

local function Specs() return ns.modules.Specs end

local HOW = { picked = "picked by you", talents = "from your talents", default = "no talents spent yet" }

local function round(value)
    return string.format("%.1f", value)
end

function Commands:ShowSpec()
    local spec, how = Specs():Active()
    if not spec then
        ns:Print("No stat weights for this class.")
        return
    end
    ns:Print("Scoring gear as " .. spec.name .. " (" .. HOW[how] .. ").")
    local names = {}
    for _, other in ipairs(Specs():ForClass(ns.modules.Client:GetPlayerClass()) or {}) do
        table.insert(names, other.key)
    end
    ns:Print("Change it with /nuugear spec <" .. table.concat(names, "|") .. "|auto>.")
end

function Commands:PickSpec(name)
    if name == "" then return self:ShowSpec() end
    local spec = Specs():Pick(name ~= "auto" and name or nil)
    if not spec then
        ns:Print("No spec called \"" .. name .. "\" for this class.")
        return self:ShowSpec()
    end
    ns.modules.Markers:Changed()
    self:ShowSpec()
end

-- The verdict, the score against what it would replace, and the stats read.
function Commands:Check(link)
    local result = ns.modules.Upgrades:Compare(link)
    if result.state == "upgrade" or result.state == "downgrade" or result.state == "same" then
        ns:Print(link .. ": " .. result.state .. ", " .. round(result.score) .. " against " .. round(result.replaced)
            .. " (" .. result.spec.name .. ", slot " .. result.slot .. ").")
    else
        ns:Print(link .. ": " .. result.state .. ".")
    end
    local stats = ns.modules.ItemStats:Get(link)
    if stats then
        local parts = {}
        for stat, value in pairs(stats) do table.insert(parts, stat .. " " .. value) end
        table.sort(parts)
        ns:Print("Stats read: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
    end
end

function Commands:Run(input)
    input = input or ""
    local command, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()
    if command == "" then
        self:ShowSpec()
    elseif command == "spec" then
        self:PickSpec(rest:lower())
    elseif command == "check" then
        local link = rest:match("|H.-|h.-|h") and rest
        if link then self:Check(link) else ns:Print("Shift-click an item after /nuugear check.") end
    elseif command == "debug" then
        local Config = ns.modules.Config
        Config:Set("debug", not Config:Get("debug"))
        ns:Print("Debug log " .. (Config:Get("debug") and "on" or "off") .. ".")
    else
        ns:Print("/nuugear, /nuugear spec <name>, /nuugear check <item>, /nuugear debug")
    end
end

function Commands:Initialize()
    -- Only our own key: assigning SlashCmdList itself would taint it.
    local slash = rawget(_G, "SlashCmdList")
    if type(slash) ~= "table" then return end
    _G.SLASH_NUUGEAR1 = "/nuugear"
    _G.SLASH_NUUGEAR2 = "/ngear"
    slash.NUUGEAR = function(input) Commands:Run(input) end
end

ns:RegisterModule("Commands", Commands)
