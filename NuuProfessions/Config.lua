local _, ns = ...

-- The saved variables: NuuProfessionsDB (account-wide) and
-- NuuProfessionsCharacterDB (one record per character). Nothing is carried
-- over from OpenRoad's saved variables: the planner may not read them.
local Config = {
    schemaVersion = 1,
    -- Every setting's default. A setting is saved only once the player
    -- chooses it (see "Settings" below): NuuProfessionsDB.settings holds
    -- those choices and nothing else, so a default changed here reaches
    -- everyone who never chose.
    settings = {
        debug = false,
        -- What weapons and armour disenchant into, and its auction value,
        -- in the game's item tooltips (UI/Tooltip.lua).
        disenchantTooltip = true,
    },
    -- The saved data's containers, made at load when missing. These hold what
    -- the player and the game made, not settings.
    defaults = {
        schemaVersion = 1,
        settings = {},
        -- The price book, account-wide (Domain/Prices.lua): `prices[itemID]`
        -- holds the vendor and auction facts with where each came from;
        -- `trainers[npcID][spellID] = { cost, skill, level, seen }` and
        -- `merchants[npcID][itemID] = { price, count, currency = { [id] = n }, seen }`
        -- are what trainer and merchant windows showed (API/Client.lua writes
        -- them, read-only calls), and `names[npcID]` what the game called
        -- that trainer or merchant; `revision` counts changes so a plan can
        -- tell it is stale.
        professions = { prices = {}, trainers = {}, merchants = {}, revision = 0 },
        -- Where the kit's windows stand (the kit's window placement table).
        windows = {},
        -- `look` (the kit look the player chose) belongs to the UI and is
        -- made there; `log` and `trace` belong to the recorder (ns.recorder).
    },
    -- A character's record lives in the per-character NuuProfessionsCharacterDB
    -- (see Config:CharacterStore) and is made when first needed, and so is
    -- everything in it: `knownRecipes[profession][spellID] = true` from the
    -- trade skill window (API/Client.lua), and the planner's inputs per
    -- profession, `professionPlanner` (Domain/ProfessionPlanner.lua,
    -- Planner:CharacterRecord), `shoppingList` (UI/ShoppingList.lua):
    -- each profession's last plan's lists, the one picked, and whether the
    -- panel is shown, and `planChanges` (Domain/PlanChanges.lua): each
    -- profession's change history and the last plan it compares with.
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
-- the same shape: "debug", "a.b.c". Config.Read and the functions after it
-- work on any such pair (the planner keeps one per profession); Config:Get
-- and the methods after them are the account-wide settings in
-- NuuProfessionsDB.settings. Code that reads settings whole goes through
-- Config.Resolved (Config:AllSettings), never the store.

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
-- naming a group of settings gives a copy of the whole group as it applies.
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
end

function Config:Reset(path)
    if not (ns.db and ns.db.settings) then return end
    Config.Write(ns.db.settings, path, nil)
end

-- Every account-wide setting as it applies, as a copy (Config.Resolved).
function Config:AllSettings()
    return Config.Resolved(ns.db and ns.db.settings, self.settings)
end

-- Characters ------------------------------------------------------------------

-- "Macewindu Thruawindow - Classic Beta PvP (Player-4619-00FF18A0)": the key
-- of this character's record in NuuProfessionsCharacterDB. The client may
-- file a character's saved variables under its first name alone, and Forever
-- characters can share a first name, so the file itself may hold another
-- character's record too.
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
    local db = rawget(_G, "NuuProfessionsDB")
    self.loadReport = { hadTable = type(db) == "table", keys = 0 }
    if self.loadReport.hadTable then
        for _ in pairs(db) do self.loadReport.keys = self.loadReport.keys + 1 end
    end
    local characters = rawget(_G, "NuuProfessionsCharacterDB")
    if type(characters) ~= "table" then
        characters = {}
        _G.NuuProfessionsCharacterDB = characters
    end
    ns.characterDB = characters
    self.characterKey, self.characterStore = nil, nil
    if type(db) ~= "table" then
        db = {}
        _G.NuuProfessionsDB = db
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
    ns:Log("saved data: " .. (self.loadReport.hadTable and ("table with " .. self.loadReport.keys .. " keys") or "nil")
        .. ", session " .. db.sessionCount)
end

ns:RegisterModule("Config", Config)
