local _, ns = ...

-- `version` moves whenever the set of guides changes, so indexes built over
-- the guides (QuestIndex) know when to rebuild.
-- `session` holds guides built while playing: they run like any other guide but are never saved.
local Repository = { builtIns = {}, session = {}, pendingID = "user:pending", version = 0 }

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local clone = {}
    seen[value] = clone
    for key, child in pairs(value) do clone[copy(key, seen)] = copy(child, seen) end
    return clone
end

-- The packaged guides (and, in development, the fixtures) put themselves in
-- ns.packagedGuides as they load, in guide format v1; each is expanded and
-- checked here. One that cannot be read is reported and left out.
function Repository:Initialize()
    for _, source in ipairs(ns.packagedGuides or {}) do
        local id = type(source) == "table" and source.id or "?"
        local expanded, result = pcall(ns.modules.Steps.Expand, ns.modules.Steps, source)
        local valid, errors
        if expanded then
            valid, errors = ns.modules.Schema:Validate(result)
        else
            errors = { tostring(result) }
        end
        if valid then
            self.builtIns[result.id] = result
        else
            ns:Print("Packaged guide '" .. tostring(id) .. "' was rejected: " .. table.concat(errors, "; "))
        end
    end
    ns.packagedGuides = nil
    local count = 0
    for _ in pairs(self.builtIns) do count = count + 1 end
    self.version = self.version + 1
    ns:Log("repository: " .. count .. " built-in guides loaded")
end

function Repository:Get(id)
    return self.builtIns[id] or self.session[id] or ns.db.account.guides[id]
end

function Repository:IsBuiltIn(id)
    return self.builtIns[id] ~= nil
end

-- A guide built this session: like a packaged one, the editor copies it
-- rather than saving over it.
function Repository:IsSessionGuide(id)
    return self.session[id] ~= nil
end

-- Registers a guide (format v1) for this session only, replacing one with the same ID.
-- Returns the runtime guide, or nil and the problems found.
function Repository:SetSessionGuide(guide)
    local expanded, result = pcall(ns.modules.Steps.Expand, ns.modules.Steps, guide)
    if not expanded then return nil, { tostring(result) } end
    local valid, errors = ns.modules.Schema:Validate(result)
    if not valid then return nil, errors end
    if self.builtIns[result.id] then return nil, { "guide.id: packaged guide IDs are immutable" } end
    ns.modules.Schema:IndexNodes(result)
    self.session[result.id] = result
    self.version = self.version + 1
    return result
end

function Repository:List()
    local guides = {}
    for _, guide in pairs(self.builtIns) do table.insert(guides, guide) end
    for _, guide in pairs(self.session) do table.insert(guides, guide) end
    for _, guide in pairs(ns.db.account.guides) do table.insert(guides, guide) end
    table.sort(guides, function(a, b) return a.meta.title < b.meta.title end)
    return guides
end

-- IDs are allocated on first save, so opening the editor and cancelling never
-- consumes a number.
local function allocateID()
    local account = ns.db.account
    account.nextUserGuideNumber = (account.nextUserGuideNumber or 0) + 1
    return "user:guide-" .. account.nextUserGuideNumber
end

-- Seconds since the epoch, from the client where there is one.
local function now()
    local clock = _G.time or os.time
    return clock and clock() or 0
end

function Repository:SaveUserGuide(guide)
    local valid, errors = ns.modules.Schema:Validate(guide)
    if not valid then return false, errors end
    if self.builtIns[guide.id] then return false, { "guide.id: packaged guide IDs are immutable" } end
    if guide.id == self.pendingID then guide.id = allocateID() end
    ns.modules.Schema:IndexNodes(guide)
    local previous = ns.db.account.guides[guide.id]
    -- Saving stamps the guide, which is what tells two copies apart and what
    -- the saved resume step is checked against.
    if previous then guide.updated = now() end
    ns.db.account.guides[guide.id] = copy(guide)
    -- Positional references have no identity across edits. A fresh scan places
    -- the player again when the editor selects the newly saved guide.
    local Progress = ns.modules.Progress
    if Progress then Progress.session[guide.id] = nil end
    self.version = self.version + 1
    return true
end

function Repository:CreateUserGuide()
    return {
        schema = ns.modules.Schema.currentVersion,
        id = self.pendingID,
        updated = now(),
        meta = { title = "Untitled guide", author = "Player", category = "Personal", tags = { "personal" } },
        sections = { { id = "main", title = "Guide", nodeIndexes = { 1 } } },
        nodes = {
            { index = 1, kind = "action", title = "First step", body = "Describe what the player should do.", completion = { type = "manual" } },
        },
    }
end

function Repository:CloneToUserGuide(source)
    local guide = copy(source)
    guide.id = self.pendingID
    guide.updated = now()
    guide.meta.author = "Player"
    guide.meta.title = "Copy of " .. source.meta.title
    guide.meta.tags = guide.meta.tags or {}
    table.insert(guide.meta.tags, "personal")
    return guide
end

function Repository:CopyGuide(guide)
    return copy(guide)
end

ns:RegisterModule("GuideRepository", Repository)
