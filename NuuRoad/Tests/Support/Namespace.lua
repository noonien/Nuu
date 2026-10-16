-- What the suites and the tools load the addon with, outside the client. Run
-- from the NuuRoad folder.
--
--   local ns = NewNamespace()           -- a stand-in for the addon's ns
--   Load(ns, "Domain/Progress.lua")     -- one file, as the client runs it
--   LoadBuiltIns(ns)                    -- every packaged guide and fixture the TOC lists
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

-- Every packaged guide NuuRoad.toc lists (fixtures included), in its order,
-- in ns.builtInGuides by ID, as the guide source the file holds: what
-- GuideRepository expands at login.
function LoadBuiltIns(ns)
    if not ns.idNames then Load(ns, "Data/IDNames.lua") end
    ns.builtInGuides = ns.builtInGuides or {}
    ns.packagedGuides = {}
    for line in io.lines("NuuRoad.toc") do
        local file = line:match("^%s*(Data/Guides/[^%s]*%.lua)%s*$") or line:match("^%s*(Dev/Fixtures/[^%s]*%.lua)%s*$")
        if file then Load(ns, file) end
    end
    for _, guide in ipairs(ns.packagedGuides) do ns.builtInGuides[guide.id] = guide end
    ns.packagedGuides = nil
end

-- The names a player would see once every guide has loaded: the NPCs the
-- packaged guides name, and what the client names (quests, items, spells;
-- Tests/Support/ClientNames.lua stands in for it). For suites whose own
-- guides use the packaged guides' IDs; ns.builtInGuides is left as it was.
function AddBuiltInNames(ns)
    local guides = ns.builtInGuides
    ns.builtInGuides = {}
    LoadBuiltIns(ns)
    for _, guide in pairs(ns.builtInGuides) do
        local npcs = {}
        for _, byID in pairs(guide.data and guide.data.npcs or {}) do
            for id, npc in pairs(byID) do npcs[id] = type(npc) == "table" and npc.name or npc end
        end
        ns.modules.Names:Add({ npcs = npcs })
    end
    ns.modules.Names:Add(dofile("Tests/Support/ClientNames.lua"))
    ns.builtInGuides = guides
end
