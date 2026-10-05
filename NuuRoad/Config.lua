local _, ns = ...

local Config = {
    schemaVersion = 1,
    -- Every setting's default. A setting is saved only once the player
    -- chooses it (see "Settings" below): NuuRoadDB.settings holds those
    -- choices and nothing else, so a default changed here reaches everyone
    -- who never chose.
    settings = {
        debug = false,
        -- Where each window stands and how wide the tracker is are the kit's
        -- window placement (`NuuRoadDB.windows`), not settings; the
        -- tracker's height is always laid out from the step it is showing.
        -- `markWaiting` paints the steps the guide will wait on (a quest to
        -- take first, a level) amber on the progress bar; off, they read as
        -- the steps around them do. `upward` holds the tracker by its foot:
        -- its band at the bottom, it grows up, and its parts stack above
        -- the band in reverse.
        tracker = { shown = true, collapsed = false, scale = 1, markWaiting = false, upward = false },
        -- `mapPinsAhead` is how many steps past the current one get a
        -- numbered pin on the world map. `standalone` shows the arrow in
        -- its own window.
        navigation = { standalone = true, mapPinsAhead = 5,
            -- The travel planner (TRAVEL.md): whether it suggests routes
            -- at all, and which kinds of travel it may use. Guide places
            -- (caves) apply either way; they are part of the guide.
            travel = { suggest = true, flights = true, teleports = true, links = true, highlight = true } },
        -- The list of the whole guide under the current step. It scrolls a
        -- whole step at a time, so a row is never cut in half: `rows` is
        -- how many steps are on screen, and 0 puts the list away.
        stepList = { rows = 8 },
        minimap = { angle = 220 },
        -- NPC conveniences. Every one can be paused by holding Shift; a dialog
        -- touched with Shift stays the player's until it closes. `sellJunk`
        -- sells grey items at any vendor the player opens. `lootReminder`
        -- says so when a creature the guide wants an item from was killed
        -- and not looted (Domain/LootReminder.lua).
        automation = { markTargets = true, acceptQuests = true, turnInQuests = true, selectQuestInLog = true, sellJunk = true,
            lootReminder = true },
        -- The strip of the current step's creatures, beside the tracker.
        -- `inViewOnly` keeps it to the ones the client can actually see.
        npcPanel = { shown = true, inViewOnly = false },
        -- The strip of the current step's usable quest items.
        itemPanel = { shown = true },
        -- The guide's shopping list, beside the tracker. Off unless the
        -- guide asks for materials at all, so quest guides never see it.
        materials = { shown = true },
        -- The play recorder (`Domain/Recording.lua`). On unless the player
        -- turns it off: the session log is how play is read back outside
        -- the game. With it off nothing is watched and nothing is written,
        -- and what it writes is a record of their own play. `keepDays` is
        -- how long a record stays in the log (`Kit.NewRecorder`).
        recording = { enabled = true, keepDays = 10 },
        -- Whether the place recorder's walk (a developer tool) keeps outdoor
        -- samples too.
        placeRecorder = { outdoors = false },
        -- Three things nothing in the client can answer: how fast the
        -- realm gives experience (`xpRate`, which the level line's kill
        -- estimate scales by), and, which guides branch on, whether the
        -- player will use the auction house (`auctionHouse`) and whether
        -- they play self found (`selfFound`).
        -- They have no default: unanswered, a predicate reads nil, which is
        -- unknown, so an unanswered question hides nothing.
        realm = {},
    },
    -- The saved data's containers, made at load when missing. These hold what
    -- the player and the game made, not settings.
    defaults = {
        schemaVersion = 1,
        settings = {},
        account = { guides = {}, drafts = {}, history = {}, nextUserGuideNumber = 0 },
        -- One key per one-time migration that has run.
        migrationLog = {},
        audit = { findings = {} },
        -- `Domain/POILog.lua`'s evidence about the client's own quest POI
        -- data: what it answered per step, the maps it was swept from, the
        -- places the game confirmed things happened, and the NPC sightings.
        -- Emptied at every login, so it only ever holds one session; it lives
        -- here so the client writes the session's harvest to disk at logout.
        poi = { rows = {}, order = {} },
        -- What play teaches the travel planner, account-wide: measured flight
        -- times as `flightTimes["crossroads>ratchet"] = { seconds, ... }`,
        -- the last few of each kept.
        travel = { flightTimes = {} },
        -- Where the kit's windows stand and how big they are (the kit's
        -- window placement table). `look` (the kit look the player chose)
        -- belongs to the UI and is made there; `log` and `trace` belong to
        -- the recorder (ns.recorder).
        windows = {},
        -- Experience each quest gave, account-wide, `questXP[questID] = xp`:
        -- seen on the quest's offer or at its turn-in (Domain/Experience.lua),
        -- so a level step can count the turn-ins ahead of it.
        questXP = {},
    },
    -- A character's record lives in the per-character NuuRoadCharacterDB
    -- (see Config:CharacterStore) and is made when first needed, and so is
    -- everything in it: the guides open in tabs and the one shown, their
    -- saved resume steps and the flight paths learned (Domain/Progress.lua).
}

local function copyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                copyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            copyDefaults(target[key], value)
        end
    end
end

-- Settings -------------------------------------------------------------------
--
-- A setting is saved only when the player chooses it. Until then nothing is
-- stored and its default is read. Choosing a value stores it, even one equal
-- to the default; resetting removes it, so the default applies again. Nothing
-- at load or save writes a default.
--
-- `path` names one setting in a stored table and in its defaults, the two
-- the same shape: "tracker.scale", "navigation.travel.flights". Config.Read
-- and the functions after it work on any such pair; Config:Get and the
-- methods after them are the account-wide settings in NuuRoadDB.settings.
-- Code that reads settings whole goes through Config.Resolved
-- (Config:AllSettings), never the store.

local paths = {}
local function keysOf(path)
    local keys = paths[path]
    if not keys then
        keys = {}
        for key in string.gmatch(path, "[^%.]+") do table.insert(keys, key) end
        paths[path] = keys
    end
    return keys
end

local function lookup(tbl, path)
    for _, key in ipairs(keysOf(path)) do
        if type(tbl) ~= "table" then return nil end
        tbl = tbl[key]
    end
    return tbl
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

-- The setting as it applies: the stored choice, else the default. A path
-- naming a group of settings ("navigation.travel") gives a copy of the whole
-- group as it applies.
function Config.Read(store, defaults, path)
    local value, default = lookup(store, path), lookup(defaults, path)
    if type(default) == "table" then return Config.Resolved(value, default) end
    if value == nil then value = default end
    return value
end

-- Whether the player has chosen this setting.
function Config.Stored(store, path)
    return lookup(store, path) ~= nil
end

-- Stores a choice, making the tables on the way. `value` nil removes it
-- instead, and any table that leaves empty goes too.
function Config.Write(store, path, value)
    local keys = keysOf(path)
    local chain, tbl = {}, store
    for index = 1, #keys - 1 do
        local key = keys[index]
        if type(tbl[key]) ~= "table" then
            if value == nil then return end
            tbl[key] = {}
        end
        chain[index] = tbl
        tbl = tbl[key]
    end
    tbl[keys[#keys]] = value
    if value ~= nil then return end
    for index = #keys - 1, 1, -1 do
        if next(chain[index][keys[index]]) ~= nil then break end
        chain[index][keys[index]] = nil
    end
end

-- Every setting as it applies, as a copy: the defaults with the choices laid
-- over them, and anything stored the defaults do not name. For code that
-- reads the settings whole (a bug report, a plan).
function Config.Resolved(store, defaults)
    local result = copy(defaults) or {}
    local function overlay(target, source)
        for key, value in pairs(source) do
            if type(value) == "table" and type(target[key]) == "table" then overlay(target[key], value)
            else target[key] = copy(value) end
        end
    end
    if type(store) == "table" then overlay(result, store) end
    return result
end

-- Drops every stored value equal to its default, and every table left
-- empty. Returns how many values went.
function Config.DropDefaults(store, defaults)
    local dropped = 0
    for key, value in pairs(store) do
        local default
        if type(defaults) == "table" then default = defaults[key] end
        if type(value) == "table" then
            dropped = dropped + Config.DropDefaults(value, default)
            if next(value) == nil then store[key] = nil end
        elseif default ~= nil and value == default then
            store[key] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

function Config:Get(path)
    return Config.Read(ns.db and ns.db.settings, self.settings, path)
end

function Config:Default(path)
    return lookup(self.settings, path)
end

function Config:IsSet(path)
    return Config.Stored(ns.db and ns.db.settings, path)
end

function Config:Set(path, value)
    if not ns.db then return end
    ns.db.settings = ns.db.settings or {}
    Config.Write(ns.db.settings, path, value)
    self:Changed(path)
end

function Config:Reset(path)
    if not (ns.db and ns.db.settings) then return end
    Config.Write(ns.db.settings, path, nil)
    self:Changed(path)
end

-- Every account-wide setting as it applies, as a copy (Config.Resolved).
function Config:AllSettings()
    return Config.Resolved(ns.db and ns.db.settings, self.settings)
end

-- Whatever shows a setting hears that it changed, by a choice or a reset:
-- every module with an OnSettingChanged(path) is told, in load order, and
-- picks out the paths it shows.
function Config:Changed(path)
    for _, name in ipairs(ns.moduleOrder or {}) do
        local module = ns.modules[name]
        if module ~= self and type(module) == "table" and module.OnSettingChanged then
            local ok, err = pcall(module.OnSettingChanged, module, path)
            if not ok then ns:Log("setting " .. path .. ": " .. name .. ": " .. tostring(err)) end
        end
    end
end

-- The realm answers are the player's, and a guide only ever reads them. An
-- xpRate that is not a positive number, or a nil answer, leaves the question
-- unanswered.
function Config:SetRealmSetting(key, value)
    if key ~= "xpRate" and key ~= "auctionHouse" and key ~= "selfFound" then return false end
    if key == "xpRate" then
        value = tonumber(value)
        if not (value and value > 0) then value = nil end
    elseif value ~= nil then
        value = value and true or false
    end
    self:Set("realm." .. key, value)
    return true
end

-- How many days the session log keeps. Anything but a whole number of at
-- least one leaves the setting as it was. Takes effect at the next login or
-- clean-up.
function Config:SetRecordingKeepDays(value)
    local days = tonumber(value)
    if not days or days < 1 then return false end
    self:Set("recording.keepDays", math.floor(days))
    return true
end

-- How many steps of the guide list are on screen at once. Zero puts it away.
function Config:SetStepListRows(rows)
    rows = math.floor(tonumber(rows) or 0)
    if rows < 0 then rows = 0 elseif rows > 30 then rows = 30 end
    self:Set("stepList.rows", rows)
end

-- How many steps past the current one get a pin on the world map; 0 keeps
-- the map to the step the player is on.
function Config:SetMapPinsAhead(count)
    count = math.floor(tonumber(count) or 0)
    if count < 0 then count = 0 elseif count > 15 then count = 15 end
    self:Set("navigation.mapPinsAhead", count)
end

-- "Macewindu Thruawindow - Classic Beta PvP (Player-4619-00FF18A0)": the key
-- of this character's record in NuuRoadCharacterDB. The client may file a
-- character's saved variables under its first name alone (it did before the
-- `70/<First>-<Surname>/` folders), and Forever characters can share a first
-- name, so the file itself may hold another character's record too.
function Config:CharacterKey()
    local Client = ns.modules.Client
    local name = Client and Client:GetPlayerFullName()
    local realm = ns.Kit.Read(rawget(_G, "GetRealmName"))
    local guid = Client and Client:GetUnitGUID("player")
    return (name or "unknown") .. " - " .. (type(realm) == "string" and realm or "unknown") .. " (" .. (guid or "no GUID") .. ")", guid
end

-- This character's saved record, created if missing. It is found by the GUID
-- at the end of its key, so a key whose name reads differently now (a surname
-- the client started answering, a rename) is carried over to the new key.
function Config:CharacterStore()
    if self.characterStore then return self.characterStore end
    local saved = ns.characterDB
    if not saved then return nil end
    local key, guid = self:CharacterKey()
    local record = saved[key]
    if not record and guid then
        local tail = "(" .. guid .. ")"
        for oldKey, value in pairs(saved) do
            if type(value) == "table" and type(oldKey) == "string" and oldKey:sub(-#tail) == tail then
                record, saved[oldKey] = value, nil
                break
            end
        end
    end
    saved[key] = record or { schemaVersion = 1 }
    self.characterKey, self.characterStore = key, saved[key]
    return self.characterStore
end

function Config:Initialize()
    -- Snapshot what the client handed us before defaults hide the difference.
    local db, characters = rawget(_G, "NuuRoadDB"), rawget(_G, "NuuRoadCharacterDB")
    self.loadReport = { hadTable = type(db) == "table", keys = 0, characters = {} }
    if self.loadReport.hadTable then
        for _ in pairs(db) do self.loadReport.keys = self.loadReport.keys + 1 end
    end
    for key, entry in pairs(type(characters) == "table" and characters or {}) do
        self.loadReport.characters[key] = type(entry) == "table" and entry.activeGuideID or false
    end
    if type(characters) ~= "table" then
        characters = {}
        _G.NuuRoadCharacterDB = characters
    end
    ns.characterDB = characters
    self.characterKey, self.characterStore = nil, nil
    if type(db) ~= "table" then
        db = {}
        _G.NuuRoadDB = db
    end
    copyDefaults(db, self.defaults)

    -- Future migrations must be idempotent and append a short entry here.
    db.schemaVersion = self.schemaVersion
    -- Counts logins that found saved data. A value of 1 on every login means the
    -- client is not handing the saved file back, and nothing can persist.
    db.sessionCount = (db.sessionCount or 0) + 1
    ns.db = db
    if db.sessionCount == 1 then
        ns:Print("No saved data was loaded; starting fresh. If this shows on every login, the client is not restoring SavedVariables.")
    end
    ns:Log("saved data: " .. (self.loadReport.hadTable and ("table with " .. self.loadReport.keys .. " keys") or "nil") .. ", session " .. db.sessionCount)
end

-- Plain-text summary of the saved-data state for `/nuuroad db`.
function Config:GetSavedDataLines()
    local report = self.loadReport or {}
    local lines = {
        "Saved data at login: " .. (report.hadTable and ("table with " .. tostring(report.keys) .. " keys") or "nil (nothing restored)"),
        "Sessions counted in saved data: " .. tostring(ns.db.sessionCount),
    }
    local Progress = ns.modules.Progress
    if Progress and self.characterStore then
        local store = self.characterStore
        local guide = Progress:GetActiveGuide()
        table.insert(lines, "This character: " .. self.characterKey)
        local Client = ns.modules.Client
        for _, line in ipairs(Client and Client.DescribePlayerNames and Client:DescribePlayerNames() or {}) do
            table.insert(lines, "  " .. line)
        end
        table.insert(lines, "Active guide ID: " .. tostring(store.activeGuideID) .. (store.activeGuideID and (guide and " (resolved)" or " (NOT FOUND in repository)") or ""))
        local count = 0
        for _ in pairs(Progress.session or {}) do count = count + 1 end
        table.insert(lines, "Guides with progress this session (never saved): " .. count)
        local open = {}
        for _, id in ipairs(type(store.openGuides) == "table" and store.openGuides or {}) do table.insert(open, tostring(id)) end
        table.insert(lines, "Open guides (tabs): " .. (#open > 0 and table.concat(open, ", ") or "none"))
        local resumes, Repository = {}, ns.modules.GuideRepository
        for id, resume in pairs(type(store.resumes) == "table" and store.resumes or {}) do
            local guide = Repository and Repository:Get(id)
            local used = guide and Progress:ResumeStep(guide)
            table.insert(resumes, tostring(type(resume) == "table" and resume.step) .. " of " .. tostring(id)
                .. (used and "" or " (not used: guide changed or gone)"))
        end
        table.sort(resumes)
        table.insert(lines, "Saved resume steps: " .. (#resumes > 0 and table.concat(resumes, "; ") or "none"))
    end
    local names = {}
    for name, active in pairs(report.characters or {}) do table.insert(names, name .. " -> " .. tostring(active or "no active guide")) end
    table.sort(names)
    table.insert(lines, "Characters in this character's saved file at login: " .. (#names > 0 and table.concat(names, "; ") or "none"))
    local Repository = ns.modules.GuideRepository
    if Repository then
        local builtIns, users = 0, 0
        for _ in pairs(Repository.builtIns) do builtIns = builtIns + 1 end
        for _ in pairs(ns.db.account.guides) do users = users + 1 end
        table.insert(lines, "Guides in repository: " .. builtIns .. " built-in, " .. users .. " personal")
    end
    return lines
end

ns:RegisterModule("Config", Config)
