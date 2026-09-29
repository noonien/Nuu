_G = _G or _ENV
local ns = { modules = {}, printed = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Print(message) table.insert(self.printed, message) end
function ns:Log() end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
local Config = ns.modules.Config

local function count(tbl)
    local n = 0
    for _ in pairs(tbl or {}) do n = n + 1 end
    return n
end

-- Nothing chosen: nothing stored, every default read.
ns.db = { settings = {} }
assert(Config:Get("tracker.scale") == 1 and Config:Get("automation.markTargets") == true, "an unset setting reads its default")
assert(Config:Get("realm.xpRate") == nil, "a setting with no default reads nil")
assert(not Config:IsSet("tracker.scale"))
assert(Config:Get("navigation.travel").flights == true, "a group reads whole")

-- Choosing stores, even the default; resetting removes it and the tables it
-- leaves empty.
Config:Set("tracker.scale", 1)
assert(ns.db.settings.tracker.scale == 1 and Config:IsSet("tracker.scale"), "the default chosen is stored")
Config:Set("navigation.travel.flights", false)
assert(Config:Get("navigation.travel.flights") == false and Config:Get("navigation.travel.links") == true)
local group = Config:Get("navigation.travel")
assert(group.flights == false and group.suggest == true, "a group read lays the choices over the defaults")
group.suggest = false
assert(Config:Get("navigation.travel.suggest") == true, "and is a copy")
Config:Reset("tracker.scale")
assert(ns.db.settings.tracker == nil and Config:Get("tracker.scale") == 1, "reset removes the value and the empty table")
Config:Reset("navigation.travel.flights")
assert(ns.db.settings.navigation == nil, "every table on the way that is left empty")
Config:Reset("debug")
assert(next(ns.db.settings) == nil, "resetting an unset setting stores nothing")

-- A later default reaches whoever never chose.
Config.settings.laterDefault = 0.8
assert(Config:Get("laterDefault") == 0.8)
Config.settings.laterDefault = nil

-- Reading the settings whole goes through the accessor: the copy has the
-- defaults and the choices, the store only the choices.
Config:Set("automation.sellJunk", false)
Config:Set("placeRecorder.outdoors", true)
local resolved = Config:AllSettings()
assert(resolved.automation.sellJunk == false and resolved.automation.markTargets == true and resolved.tracker.scale == 1)
assert(resolved.placeRecorder.outdoors == true)
assert(count(ns.db.settings) == 2 and count(ns.db.settings.automation) == 1, "the store holds only the choices")
resolved.automation.sellJunk = true
assert(ns.db.settings.automation.sellJunk == false, "the resolved settings are a copy")

-- The four functions work on any store and defaults: a flat one, as the
-- profession planner's options are.
local defaults = { confidence = "safe", useBags = true }
local options = {}
assert(Config.Read(options, defaults, "confidence") == "safe" and not Config.Stored(options, "confidence"))
Config.Write(options, "useBags", true)
assert(options.useBags == true and Config.Stored(options, "useBags"))
Config.Write(options, "useBags", nil)
assert(next(options) == nil)
assert(Config.Read(nil, defaults, "useBags") == true, "no store at all reads the defaults")

-- Window placement is the kit's (NuuRoadDB.windows), not a setting.
assert(Config.SetPlacement == nil and Config:Default("tracker.width") == nil and Config:Default("npcPanel.point") == nil)
ns.db = { settings = {} }

-- Validating setters store what they accept and nothing else.
assert(Config:SetRecordingKeepDays("0") == false and not Config:IsSet("recording.keepDays"))
assert(Config:SetRecordingKeepDays("10") and ns.db.settings.recording.keepDays == 10, "the default typed is chosen")
Config:SetRealmSetting("xpRate", "abc")
assert(not Config:IsSet("realm.xpRate"), "an xpRate that is not a number leaves the question unanswered")
Config:SetRealmSetting("auctionHouse", false)
assert(ns.db.settings.realm.auctionHouse == false, "no is an answer")
Config:SetRealmSetting("auctionHouse", nil)
assert(ns.db.settings.realm == nil, "nil takes it back")

-- Saved data from an earlier session: the player's choices are kept as they
-- were, and the data containers are made. NuuRoad starts from its own saved
-- variables, so there is no migration from OpenRoad's to run.
_G.NuuRoadDB = {
    sessionCount = 4,
    settings = { tracker = { scale = 1.2 }, automation = { acceptQuests = false }, realm = { selfFound = true },
        retired = { thing = 1 } },
}
Config:Initialize()
local db = ns.db
local settings = db.settings
assert(db == NuuRoadDB and db.sessionCount == 5, "the session is counted")
assert(Config:Get("tracker.scale") == 1.2 and Config:Get("tracker.shown") == true, "the player's values are kept")
assert(settings.automation.acceptQuests == false and count(settings.automation) == 1, "and nothing is added to them")
assert(settings.realm.selfFound == true, "an answer has no default to equal")
assert(settings.retired.thing == 1, "what the defaults do not name is left alone")
assert(db.account and db.audit and db.poi and db.travel and db.windows and db.questXP, "the data containers are made")
assert(db.professions == nil, "the planner's price book is NuuProfessions'")

-- A fresh save stores no setting at all.
_G.NuuRoadDB = nil
Config:Initialize()
assert(next(ns.db.settings) == nil, "nothing at load writes a default")
assert(#ns.printed == 1, "and the player hears that nothing was restored")

-- A character's record: in the per-character saved variables, under its full
-- name, realm, and GUID, found again by the GUID.
local playerName, playerGUID = "Macewindu Thruawindow", "Player-4619-00FF18A0"
ns.modules.Client = {
    GetPlayerFullName = function() return playerName end,
    GetUnitGUID = function(_, unit) return unit == "player" and playerGUID or nil end,
}
_G.GetRealmName = function() return "Classic Beta PvP" end
local key = "Macewindu Thruawindow - Classic Beta PvP (Player-4619-00FF18A0)"
-- The client may file both Macewindus under one first name: the other's
-- record shares the file and is left alone.
local other = "Macewindu Feloutawindu - Classic Beta PvP (Player-4619-01053196)"
_G.NuuRoadCharacterDB = { [other] = { activeGuideID = "theirs" } }
Config:Initialize()
local store = Config:CharacterStore()
assert(Config.characterKey == key and NuuRoadCharacterDB[key] == store, "keyed by full name, realm, and GUID")
assert(store.activeGuideID == nil and store.knownRecipes == nil and store.professionPlanner == nil,
    "a new character's record holds nothing yet, whoever shares the file")
assert(NuuRoadCharacterDB[other].activeGuideID == "theirs")
assert(Config:CharacterStore() == store, "found once per session")
store.activeGuideID = "mine"

-- The name reads differently next session: the GUID finds the record.
playerName = "Macewindu"
Config:Initialize()
local renamed = Config:CharacterStore()
assert(renamed.activeGuideID == "mine" and Config.characterKey == "Macewindu - Classic Beta PvP (Player-4619-00FF18A0)")
assert(NuuRoadCharacterDB[key] == nil, "carried over to the new key, not copied")
assert(Config.loadReport.characters[key] == "mine" and Config.loadReport.characters[other] == "theirs",
    "the load report lists the file's records")

print("NuuRoad settings tests passed")
