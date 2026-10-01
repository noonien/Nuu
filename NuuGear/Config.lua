local _, ns = ...

-- The saved variables: NuuGearDB (account-wide) and NuuGearCharacterDB (one
-- record per character). Same scheme as NuuProfessions' Config.lua.
local Config = {
    schemaVersion = 1,
    -- Every setting's default. A setting is saved only once the player
    -- chooses it, so a default changed here reaches everyone who never chose.
    settings = {
        debug = false,
        -- Where the upgrade arrow is drawn (UI/Markers.lua).
        markers = { bags = true, quests = true, loot = true, rolls = true },
    },
    -- The saved data's containers, made at load when missing.
    defaults = {
        schemaVersion = 1,
        settings = {},
        -- `log` and `trace` belong to the recorder (ns.recorder).
    },
    -- A character's record (Config:CharacterStore) holds `spec`, the spec
    -- the player picked for scoring (Domain/Specs.lua); without one the spec
    -- is guessed from talents each time.
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

function Config:Get(path)
    local value = lookup(ns.db and ns.db.settings, path)
    if value == nil then value = lookup(self.settings, path) end
    return value
end

function Config:IsSet(path)
    return lookup(ns.db and ns.db.settings, path) ~= nil
end

-- Stores a choice, making the tables on the way; nil removes it.
function Config:Set(path, value)
    if not ns.db then return end
    ns.db.settings = ns.db.settings or {}
    local keys = keysOf(path)
    local tbl = ns.db.settings
    for index = 1, #keys - 1 do
        local key = keys[index]
        if type(tbl[key]) ~= "table" then
            if value == nil then return end
            tbl[key] = {}
        end
        tbl = tbl[key]
    end
    tbl[keys[#keys]] = value
end

function Config:Reset(path)
    self:Set(path, nil)
end

-- Characters ------------------------------------------------------------------

-- "Name - Realm (GUID)": the key of this character's record in
-- NuuGearCharacterDB, as NuuProfessions keys its own (Forever characters can
-- share a first name, so the GUID is what tells them apart).
function Config:CharacterKey()
    local Client = ns.modules.Client
    local name = Client and Client:GetUnitName("player")
    local realm = ns.Kit.Read(rawget(_G, "GetRealmName"))
    local guid = Client and Client:GetUnitGUID("player")
    return (name or "unknown") .. " - " .. (type(realm) == "string" and realm or "unknown") .. " (" .. (guid or "no GUID") .. ")", guid
end

-- This character's saved record, created if missing, found by the GUID at the
-- end of its key so a renamed key carries over.
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
    local characters = rawget(_G, "NuuGearCharacterDB")
    if type(characters) ~= "table" then
        characters = {}
        _G.NuuGearCharacterDB = characters
    end
    ns.characterDB = characters
    self.characterKey, self.characterStore = nil, nil
    local db = rawget(_G, "NuuGearDB")
    if type(db) ~= "table" then
        db = {}
        _G.NuuGearDB = db
    end
    copyDefaults(db, self.defaults)
    db.schemaVersion = self.schemaVersion
    db.sessionCount = (db.sessionCount or 0) + 1
    ns.db = db
end

ns:RegisterModule("Config", Config)
