-- Every file NuuProfessions.toc lists, but the UI's, loaded in its order on
-- the development kit (as the client does with NuuKit installed), then
-- PLAYER_LOGIN's Initialize: each file finds what it needs, the modules are
-- registered, the one global is the addon's ns, and the saved variables are
-- made.
local kit = LoadKit()
local saved = { NuuKit = rawget(_G, "NuuKit"), geterrorhandler = rawget(_G, "geterrorhandler") }
_G.NuuKit = kit
_G.geterrorhandler = function() return function(err) error(err, 0) end end

local ns = {}
local files = 0
for line in io.lines("NuuProfessions.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and not file:match("^UI/") then
        assert(loadfile(file))("NuuProfessions", ns)
        files = files + 1
    end
end
assert(files > 20, "the TOC lists the addon's files")
assert(rawget(_G, "NuuProfessions") == ns, "the one global is the addon's ns")
assert(ns.Kit == kit and ns.Kit.SkillUp and ns.Kit.Crafting, "the kit, with the planner's pure parts")
for _, name in ipairs({ "Config", "Client", "ProfessionTiers", "Prices", "ProfessionPlanner" }) do
    assert(ns.modules[name], name .. " is registered")
end
assert(ns.moduleOrder[1] == "Config", "Config loads first")
assert(ns.professionData and ns.professionData.Leatherworking and ns.professionData.Mining, "the recipe data")
assert(ns.professionDataFull and ns.professionDataFull.Leatherworking, "the full-scope set")
assert(ns.professionRecorded and ns.professionRecorded.trainers, "the recorded trainers")

ns:Initialize()
local db = rawget(_G, "NuuProfessionsDB")
assert(ns.db == db and type(db.professions.prices) == "table" and db.professions.revision == 0, "the price book")
assert(type(db.windows) == "table" and type(db.settings) == "table" and db.sessionCount == 1)
assert(ns.modules.Config:Get("debug") == false and not ns.modules.Config:IsSet("debug"))
ns.modules.Config:Set("debug", true)
assert(ns.modules.Config:Get("debug") == true and db.settings.debug == true)
ns.modules.Config:Reset("debug")
assert(db.settings.debug == nil)
local store = ns.modules.Config:CharacterStore()
assert(type(store) == "table" and rawget(_G, "NuuProfessionsCharacterDB")["unknown - unknown (no GUID)"] == store)
assert(ns.modules.Prices:Book() == db.professions)
assert(ns.modules.Prices:FormatMoney(12005) == "1g 20s")
assert(ns.modules.Client:GetPlayerPosition() == nil, "no map outside the client")

_G.NuuProfessions, _G.NuuProfessionsDB, _G.NuuProfessionsCharacterDB = nil, nil, nil
_G.NuuKit, _G.geterrorhandler = saved.NuuKit, saved.geterrorhandler
return true
