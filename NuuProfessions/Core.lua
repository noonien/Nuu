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
_G.NuuProfessions = ns

-- ns:Print, ns:Log (only while the `debug` setting is on), ns:Record,
-- ns:RecordHere, ns:Trace, ns:Tracing (Kit.AddLogging). The records go to
-- ns.recorder, made below, into NuuProfessionsDB.log and .trace.
ns.Kit.AddLogging(ns, {
    label = "NuuProfessions",
    debug = function()
        local Config = ns.modules.Config
        return Config and Config:Get("debug") or false
    end,
})

ns.recorder = ns.Kit.NewRecorder({
    db = function() return rawget(_G, "NuuProfessionsDB") end,
    version = ns.version,
    log = function(message) ns:Log(message) end,
    where = function()
        local Client = ns.modules.Client
        if Client and Client.GetPlayerPosition then return Client:GetPlayerPosition() end
        return nil
    end,
})

--@debug@
-- Development builds keep every Lua error of this addon on the session log's
-- `error` channel (NuuKit/Dev/Errors.lua).
if ns.Kit.Errors then ns.Kit.Errors.Watch(addonName, ns.recorder) end
--@end-debug@

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
    -- Config first: every other module reads the saved variables through it.
    local order = { "Config" }
    for _, name in ipairs(self.moduleOrder) do
        if name ~= "Config" then table.insert(order, name) end
    end
    for _, name in ipairs(order) do
        local module = self.modules[name]
        if module and module.Initialize then
            local ok, err = xpcall(function() module:Initialize() end, geterrorhandler())
            if not ok then
                self:Print("Could not initialize " .. name .. ".")
                self:Log(err)
            end
        end
    end
    if self.recorder then pcall(self.recorder.Initialize, self.recorder) end
end

-- The addon's UI (NuuKit), made the first time a window needs it, with the
-- look the player chose (NuuProfessionsDB.look).
function ns:GetUI()
    if not self.UI then
        local db = rawget(_G, "NuuProfessionsDB")
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
