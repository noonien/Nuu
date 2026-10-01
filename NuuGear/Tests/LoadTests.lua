-- Every file NuuGear.toc lists, in its order, on the development kit (as the
-- client does with NuuKit installed), then PLAYER_LOGIN's Initialize: the
-- modules are registered, the one global is the addon's ns, and the saved
-- variables are made. Outside the client the hooks are skipped.
local kit = LoadKit()
local saved = { NuuKit = rawget(_G, "NuuKit"), geterrorhandler = rawget(_G, "geterrorhandler") }
_G.NuuKit = kit
_G.geterrorhandler = function() return function(err) error(err, 0) end end

local ns = {}
local files = 0
for line in io.lines("NuuGear.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file then
        assert(loadfile(file))("NuuGear", ns)
        files = files + 1
    end
end
assert(files == 9, "the TOC lists the addon's files")
assert(rawget(_G, "NuuGear") == ns, "the one global is the addon's ns")
for _, name in ipairs({ "Config", "Client", "ItemStats", "Specs", "Upgrades", "Markers", "Commands" }) do
    assert(ns.modules[name], name .. " is registered")
end
assert(ns.moduleOrder[1] == "Config", "Config loads first")
assert(ns.weights and ns.weights.WARRIOR, "the weights")

ns:Initialize()
local db = rawget(_G, "NuuGearDB")
assert(ns.db == db and type(db.settings) == "table" and db.sessionCount == 1)
assert(ns.modules.Config:Get("markers.bags") == true and not ns.modules.Config:IsSet("markers.bags"))
ns.modules.Config:Set("markers.loot", false)
assert(ns.modules.Config:Get("markers.loot") == false and db.settings.markers.loot == false)
ns.modules.Config:Reset("markers.loot")
assert(ns.modules.Config:Get("markers.loot") == true)
local store = ns.modules.Config:CharacterStore()
assert(type(store) == "table" and rawget(_G, "NuuGearCharacterDB")["unknown - unknown (no GUID)"] == store)
assert(ns.modules.Specs:Active() == nil, "no class outside the client")

_G.NuuGear, _G.NuuGearDB, _G.NuuGearCharacterDB = nil, nil, nil
_G.NuuKit, _G.geterrorhandler = saved.NuuKit, saved.geterrorhandler
return true
