-- Every file NuuRoad.toc lists, but the UI's, loaded in its order on the
-- development kit (as the client does with NuuKit installed), then
-- PLAYER_LOGIN's Initialize: each file finds what it needs, the modules are
-- registered, the one global is the addon's ns, and the saved variables are
-- made. Loading needs no frame API: the files load before the kit's
-- stand-in for it is put in _G. Initialize makes the event frames (and the
-- arrow window), so it runs on the stand-in, which is taken out of _G again
-- at the end, since the suites after this one run without it.
local kit = LoadKit()
local before = {}
for key, value in pairs(_G) do before[key] = value end
_G.NuuKit = kit
-- What reaches the error handler: ns:Initialize runs each module through it.
local errors = {}
_G.geterrorhandler = function() return function(err) table.insert(errors, tostring(err)) end end

local ns = {}
local files = 0
for line in io.lines("NuuRoad.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and not file:match("^UI/") then
        assert(loadfile(file))("NuuRoad", ns)
        files = files + 1
    end
end
assert(files > 40, "the TOC lists the addon's files")
assert(rawget(_G, "NuuRoad") == ns, "the one global is the addon's ns")
assert(ns.Kit == kit and ns.Kit.Crafting and ns.Kit.NewBugReports, "the kit")
assert(ns.recorder and ns.recorder.Records, "the session log is the kit's recorder")
for _, name in ipairs({ "Config", "Client", "Schema", "Names", "Steps", "Travel", "GuideText", "GuideDraft", "GuideRepository",
    "PlaceEditing", "Progress", "Experience", "ObservedProgress", "Materials", "GuideScan", "QuestIndex", "GuideCatalog",
    "GuideAudit", "NPCTracking", "TargetMarking", "QuestDialog", "QuestSelection", "JunkSelling", "LootReminder", "POILog", "Recording",
    "GuideCorrections", "Navigation", "BugReport", "StepState" }) do
    assert(ns.modules[name], name .. " is registered")
end
assert(ns.moduleOrder[1] == "Config", "Config loads first")
assert(ns.modules.Recorder == nil and ns.modules.Prices == nil and ns.modules.ProfessionPlanner == nil
    and ns.modules.Crafting == nil, "what moved to the kit or to NuuProfessions is not here")
local shipped = 0
for _, guide in ipairs(ns.packagedGuides or {}) do
    assert(guide.kind == "guide" and guide.schema == 1, tostring(guide.id) .. " is in guide format v1")
    if not guide.id:find("^nuuroad:fixture:") then shipped = shipped + 1 end
end
assert(shipped == 22, "the packaged guides, in guide format v1")
assert(ns.API and ns.API.apiVersion == 1, "the optional API")

dofile("../NuuKit/Tests/Support/Frames.lua")
ns:Initialize()
assert(#errors == 0, "every module starts: " .. table.concat(errors, "\n"))
local db = rawget(_G, "NuuRoadDB")
assert(ns.db == db and type(db.windows) == "table" and type(db.settings) == "table" and db.sessionCount == 1)
assert(type(db.account.guides) == "table" and type(db.poi.rows) == "table" and type(db.travel.flightTimes) == "table")
assert(db.professions == nil, "no price book: that is NuuProfessions'")
local Config = ns.modules.Config
assert(Config:Get("debug") == false and not Config:IsSet("debug"))
Config:Set("debug", true)
assert(Config:Get("debug") == true and db.settings.debug == true)
Config:Reset("debug")
assert(db.settings.debug == nil)
local store = Config:CharacterStore()
assert(type(store) == "table" and rawget(_G, "NuuRoadCharacterDB")["unknown - unknown (no GUID)"] == store)
assert(ns.modules.Client:GetPlayerPosition() == nil, "no map outside the client")
local packaged = 0
for id in pairs(ns.modules.GuideRepository.builtIns) do
    if not id:find("^nuuroad:fixture:") then packaged = packaged + 1 end
end
assert(packaged == 22 and ns.packagedGuides == nil, "the repository has the packaged guides, read at login: " .. packaged)

-- The optional API (API.lua), on the loaded addon. The UI is not loaded here,
-- so the travel planner and the guide browser are missing: the calls that
-- need them say no rather than fail.
local API = _G.NuuRoad.API
assert(API == ns.API and API.apiVersion == 1)
local flight = API.NPCLocation(3615)
assert(flight and flight.source == "travel" and flight.mapID == 1413 and math.abs(flight.x - 0.515) < 0.001, "a flight master")
local giver = API.NPCLocation(3448)
assert(giver and giver.source == "guide" and giver.mapID == 1413 and math.abs(giver.y - 0.3193) < 0.001
    and giver.npcID == 3448, "a quest giver where a guide sends the player to talk")
assert(API.NPCLocation(1) == nil and API.NPCLocation("x") == nil, "an NPC no data places")
local guides = API.QuestGuides(870)
assert(#guides >= 1 and type(guides[1].guideID) == "string" and #guides[1].steps >= 2 and guides[1].first, "the guides for a quest")
assert(guides[1].steps[1].role and guides[1].guide == nil, "plain tables only")
assert(#API.QuestGuides(999999) == 0 and #API.QuestGuides(nil) == 0)
assert(API.Route({ mapID = 1413, x = 0.5, y = 0.5 }) == false and API.StopRoute() == false, "no travel planner: no route")
assert(API.StartGuideAt(guides[1].guideID, 870) == false, "no browser: nothing offered")
-- With them there: the calls reach them, and nothing starts a guide.
local routed, picked, stopped = nil, nil, 0
ns.modules.TravelRoute = { RouteTo = function(_, target) routed = target; return true end,
    StopRoute = function() stopped = stopped + 1; return true end }
local shown = false
ns.modules.GuideBrowser = { ShowQuest = function(_, questID) shown = questID end, IsShown = function() return shown ~= false end,
    Pick = function(_, guide) picked = guide end }
assert(API.Route(giver) == true and routed == giver and API.StopRoute() == true and stopped == 1)
local active = ns.modules.Progress:GetActiveGuide()
assert(API.StartGuideAt(guides[1].guideID, 870) == true and shown == 870 and picked.id == guides[1].guideID)
assert(ns.modules.Progress:GetActiveGuide() == active, "offered, not started")
ns.modules.TravelRoute.RouteTo = function() error("broken") end
assert(API.Route(giver) == false, "a module that throws is a no")
ns.modules.TravelRoute, ns.modules.GuideBrowser = nil, nil

-- Every global as it was: the stand-in, the saved variables and the addon's
-- global go.
for key in pairs(_G) do
    if before[key] == nil then _G[key] = nil end
end
for key, value in pairs(before) do _G[key] = value end
return true
