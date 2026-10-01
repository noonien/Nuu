-- What the suites load the addon with, outside the client. Run from the
-- NuuGear folder.
--
--   local ns = NewNamespace()           -- a stand-in for the addon's ns
--   Load(ns, "Domain/Upgrades.lua")     -- one file, as the client runs it
_G = _G or _ENV

local KIT = "../NuuKit/"

-- The kit the way the client loads it in development: every file
-- NuuKit.toc lists, in its order, except NuuKit.lua and Dev/. Loaded once.
local kit
function LoadKit()
    if kit then return kit end
    local ns = {}
    for line in io.lines(KIT .. "NuuKit.toc") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file and file ~= "NuuKit.lua" and not file:match("^Dev/") then
            assert(loadfile(KIT .. file))("NuuKit", ns)
        end
    end
    kit = ns.Kit
    return kit
end

-- The addon's ns as Core.lua makes it, without the client. What is printed
-- is kept on ns.printed.
function NewNamespace()
    local ns = { name = "NuuGear", modules = {}, moduleOrder = {}, Kit = LoadKit(), printed = {} }
    function ns:RegisterModule(name, module)
        if self.modules[name] then error("module already registered: " .. name) end
        self.modules[name] = module
        table.insert(self.moduleOrder, name)
    end
    function ns:Print(message) table.insert(self.printed, tostring(message)) end
    function ns:Log() end
    return ns
end

function Load(ns, path)
    local chunk = assert(loadfile(path))
    return chunk("NuuGear", ns)
end

-- The domain on a fake client (Tests/Support/FakeClient.lua): weights,
-- Config with a character record, ItemStats, Specs and Upgrades.
function NewDomain()
    local ns = NewNamespace()
    for _, file in ipairs({ "Config.lua", "Data/Weights.lua", "Domain/ItemStats.lua", "Domain/Specs.lua",
        "Domain/Upgrades.lua" }) do
        Load(ns, file)
    end
    local client = dofile("Tests/Support/FakeClient.lua")
    ns.modules.Client = client
    ns.modules.Config.characterStore = {}
    return ns, client
end
