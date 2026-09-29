local addonName, ns = ...

ns.name = addonName
ns.version = "0.1.0-dev"
ns.modules = {}
ns.moduleOrder = {}

-- In a release the embedded kit files have already filled ns.Kit; in
-- development it comes from the NuuKit addon.
ns.Kit = ns.Kit or _G.NuuKit
assert(ns.Kit, addonName .. ": NuuKit is not loaded")

-- The one intentional global of this addon.
_G.NuuRoad = ns

-- ns:Print, ns:Log (only while the `debug` setting is on), ns:Record,
-- ns:RecordHere, ns:Trace, ns:Tracing (Kit.AddLogging). The records go to
-- ns.recorder, made below, into NuuRoadDB.log and .trace, and are read
-- outside the game by Tools/SessionLog.
ns.Kit.AddLogging(ns, {
    label = "NuuRoad",
    debug = function()
        local Config = ns.modules.Config
        return Config and Config:Get("debug") or false
    end,
})

ns.recorder = ns.Kit.NewRecorder({
    db = function() return rawget(_G, "NuuRoadDB") end,
    version = ns.version,
    log = function(message) ns:Log(message) end,
    keepDays = function()
        local Config = ns.modules.Config
        return Config and Config:Get("recording.keepDays")
    end,
    where = function()
        local Client = ns.modules.Client
        if Client and Client.GetPlayerPosition then return Client:GetPlayerPosition() end
        return nil
    end,
})

-- Every file registers what it makes through here, and finds the others in
-- ns.modules. A module's Initialize, if any, runs at PLAYER_LOGIN in load
-- order, once the saved variables are in.
function ns:RegisterModule(name, module)
    if self.modules[name] then
        error(addonName .. " module already registered: " .. name)
    end
    self.modules[name] = module
    table.insert(self.moduleOrder, name)
end

function ns:Initialize()
    if self.initialized then return end
    self.initialized = true
    local function run(name, module)
        local ok, err = xpcall(function() module:Initialize() end, geterrorhandler())
        if not ok then
            self:Print("Could not initialize " .. name .. ".")
            self:Log(err)
        end
    end
    -- Config first: every other module reads the saved variables through it.
    -- The recorder next, so the session's identity opens the log before any
    -- module records.
    local Config = self.modules.Config
    if Config and Config.Initialize then run("Config", Config) end
    if self.recorder then run("the session log", self.recorder) end
    for _, name in ipairs(self.moduleOrder) do
        local module = self.modules[name]
        if name ~= "Config" and module and module.Initialize then run(name, module) end
    end
end

-- The addon's UI (NuuKit), made the first time a window needs it, with the
-- look the player chose (NuuRoadDB.look).
function ns:GetUI()
    if not self.UI then
        local db = rawget(_G, "NuuRoadDB")
        self.UI = self.Kit.NewUI(self, db and db.look)
    end
    return self.UI
end

if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ns:Initialize()
    end)
end

--@debug@
ns.Kit.Loaded(addonName, "Core.lua")
--@end-debug@
