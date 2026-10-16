local _, ns = ...

-- `version` moves whenever the set of guides changes, so indexes built over
-- the guides (QuestIndex) know when to rebuild.
-- `session` holds guides built while playing: they run like any other guide but are never saved.
-- `sources` keeps each packaged guide's source, as written, which the
-- editor copies; `user` holds the player's guides built for play, from the
-- sources kept in NuuRoadDB.account.guides.
local Repository = { builtIns = {}, session = {}, sources = {}, user = {}, pendingID = "user:pending", version = 0 }

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
-- ns.packagedGuides as they load, as guide sources; each is expanded and
-- checked here. One that cannot be read is reported and left out.
function Repository:Initialize()
    for _, source in ipairs(ns.packagedGuides or {}) do
        local id = type(source) == "table" and source.id or "?"
        local expanded, result = pcall(ns.modules.Steps.Expand, ns.modules.Steps, source)
        local valid, errors
        if expanded then
            valid, errors = ns.modules.GuideCheck:Validate(result)
        else
            errors = { tostring(result) }
        end
        if valid then
            self.builtIns[result.id] = result
            self.sources[result.id] = source
        else
            ns:Print("Packaged guide '" .. tostring(id) .. "' was rejected: " .. table.concat(errors, "; "))
        end
    end
    ns.packagedGuides = nil
    self:BuildUserGuides()
    local count = 0
    for _ in pairs(self.builtIns) do count = count + 1 end
    self.version = self.version + 1
    ns:Log("repository: " .. count .. " built-in guides loaded")
end

-- The player's guides, each built the way the editor builds it: a step
-- that cannot be read is left out and the rest plays. A guide kept by an
-- older editor (a runtime guide, not a source) plays as it is.
function Repository:BuildUserGuides()
    self.user = {}
    local Draft = ns.modules.GuideDraft
    for id, value in pairs(ns.db.account.guides or {}) do
        if type(value) == "table" and value.kind == "guide" and Draft then
            local built = Draft:Open(value).built
            if built then self.user[id] = built else ns:Log("user guide '" .. tostring(id) .. "' has no step that can be read") end
        elseif type(value) == "table" and type(value.nodes) == "table" then
            self.user[id] = ns.modules.GuideCheck:IndexNodes(value) or value
        end
    end
end

function Repository:Get(id)
    return self.builtIns[id] or self.session[id] or self.user[id]
end

-- The guide's source, as written, for the editor: a packaged guide's
-- source or a guide of the player's. Nil for a session guide or one kept by
-- an older editor.
function Repository:Source(id)
    if self.sources[id] then return self.sources[id] end
    local value = ns.db.account.guides[id]
    if type(value) == "table" and value.kind == "guide" then return value end
    return nil
end

function Repository:IsUserGuide(id)
    return ns.db.account.guides[id] ~= nil
end

function Repository:IsBuiltIn(id)
    return self.builtIns[id] ~= nil
end

-- A guide built this session: like a packaged one, the editor copies it
-- rather than saving over it.
function Repository:IsSessionGuide(id)
    return self.session[id] ~= nil
end

-- Registers a guide source for this session only, replacing one with the same ID.
-- Returns the runtime guide, or nil and the problems found.
function Repository:SetSessionGuide(guide)
    local expanded, result = pcall(ns.modules.Steps.Expand, ns.modules.Steps, guide)
    if not expanded then return nil, { tostring(result) } end
    local valid, errors = ns.modules.GuideCheck:Validate(result)
    if not valid then return nil, errors end
    if self.builtIns[result.id] then return nil, { "guide.id: packaged guide IDs are immutable" } end
    ns.modules.GuideCheck:IndexNodes(result)
    self.session[result.id] = result
    self.sources[result.id] = guide
    self.version = self.version + 1
    return result
end

function Repository:List()
    local guides = {}
    for _, guide in pairs(self.builtIns) do table.insert(guides, guide) end
    for _, guide in pairs(self.session) do table.insert(guides, guide) end
    for _, guide in pairs(self.user) do table.insert(guides, guide) end
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

-- Keeps a draft (Domain/GuideDraft.lua): its source on the account, and
-- its runtime guide for play. A draft of a packaged guide becomes a guide
-- of the player's own here, with an ID of its own, on its first save.
-- Answers the runtime guide that was played before (nil for a new guide)
-- and the one to play now (nil when no step can be read yet, which keeps
-- the old one playing).
function Repository:SaveDraft(draft)
    local guide = draft.guide
    local previous = self:Get(draft.id)
    if draft.copyOf or guide.id == self.pendingID or self.builtIns[guide.id] or self.session[guide.id] then
        guide.id = allocateID()
        if draft.copyOf then
            guide.title = tostring(guide.title or "Guide") .. " (my copy)"
            guide.author = "Player"
            guide.tags = guide.tags or {}
            table.insert(guide.tags, "personal")
        end
        draft.copyOf, draft.isNew = nil, nil
        draft:Rebuild()
    end
    guide.updated = now()
    draft.id = guide.id
    ns.db.account.guides[guide.id] = copy(guide)
    local built = draft.built
    if built then
        built.id, built.updated = guide.id, guide.updated
        self.user[guide.id] = built
    end
    self.version = self.version + 1
    return previous, built or self.user[guide.id]
end

-- Takes one of the player's guides off the account.
function Repository:DeleteUserGuide(id)
    if not ns.db.account.guides[id] then return false end
    ns.db.account.guides[id] = nil
    self.user[id] = nil
    self.version = self.version + 1
    return true
end

-- A guide source read from text, kept as a guide of the player's own
-- under a new ID. Answers the runtime guide, or nil and what is wrong.
function Repository:Import(value)
    local Draft = ns.modules.GuideDraft
    local draft = Draft:Open(value)
    draft.guide.id = self.pendingID
    if not draft.built then
        return nil, draft.guideProblems[1] or "No step of it can be read."
    end
    local _, built = self:SaveDraft(draft)
    return built, nil, draft
end

ns:RegisterModule("GuideRepository", Repository)
