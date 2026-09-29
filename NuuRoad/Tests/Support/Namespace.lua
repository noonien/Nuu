-- What the suites and the tools load the addon with, outside the client. Run
-- from the NuuRoad folder.
--
--   local ns = NewNamespace()           -- a stand-in for the addon's ns
--   Load(ns, "Domain/Progress.lua")     -- one file, as the client runs it
--   LoadBuiltIns(ns)                    -- every Data/BuiltIn and Dev/Fixtures file the TOC lists
_G = _G or _ENV

local KIT = "../NuuKit/"

-- The kit the way the client loads it in development: every file
-- NuuKit.toc lists, in its order, into one table, except the
-- development-only NuuKit.lua and Dev/. Loaded once and shared, as the
-- addons share it in development.
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

-- The addon's ns as Core.lua makes it, without the client: the module
-- registry, the kit, and the logging calls. What is printed, recorded and
-- traced is kept on ns.printed, ns.records and ns.traces.
function NewNamespace()
    local ns = { name = "NuuRoad", modules = {}, moduleOrder = {}, Kit = LoadKit(),
        printed = {}, records = {}, traces = {} }
    function ns:RegisterModule(name, module)
        if self.modules[name] then error("module already registered: " .. name) end
        self.modules[name] = module
        table.insert(self.moduleOrder, name)
    end
    function ns:Print(message) table.insert(self.printed, tostring(message)) end
    function ns:Log() end
    function ns:Record(channel, data) table.insert(self.records, { channel = channel, data = data }) end
    function ns:RecordHere(channel, data) table.insert(self.records, { channel = channel, data = data }) end
    function ns:Trace(channel, data) table.insert(self.traces, { channel = channel, data = data }) end
    function ns:Tracing() return false end
    return ns
end

-- Runs one of the addon's files with (addon name, ns), as the client does.
function Load(ns, path)
    local chunk = assert(loadfile(path))
    return chunk("NuuRoad", ns)
end

-- Every packaged guide NuuRoad.toc lists (fixtures included), in its order.
function LoadBuiltIns(ns)
    for line in io.lines("NuuRoad.toc") do
        local file = line:match("^%s*(Data/BuiltIn/[^%s]*%.lua)%s*$") or line:match("^%s*(Dev/Fixtures/[^%s]*%.lua)%s*$")
        if file then Load(ns, file) end
    end
end
