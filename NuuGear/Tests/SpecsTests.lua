-- Data/Weights.lua and Domain/Specs.lua: every class has its specs, and the
-- spec in use is the player's pick, else the talents', else the first.
local ns, client = NewDomain()
local Specs = ns.modules.Specs

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local KNOWN = {}
for stat in pairs({ Strength = 1, Agility = 1, Stamina = 1, Intellect = 1, Spirit = 1, Armor = 1, AttackPower = 1,
    RangedAttackPower = 1, FeralAttackPower = 1, SpellPower = 1, SpellDamage = 1, Healing = 1, Hit = 1, Crit = 1,
    Haste = 1, Expertise = 1, Defense = 1, Dodge = 1, Parry = 1, Block = 1, BlockValue = 1, MP5 = 1, HP5 = 1,
    WeaponDPS = 1, RangedDPS = 1, Arcane = 1, Fire = 1, Frost = 1, Holy = 1, Nature = 1, Shadow = 1 }) do
    KNOWN[stat] = true
end
for _, class in ipairs(CLASSES) do
    local specs = Specs:ForClass(class)
    assert(specs and #specs >= 3, class .. " has its specs")
    local tabs, keys = {}, {}
    for _, spec in ipairs(specs) do
        assert(spec.key and spec.name and spec.tab, class .. " spec fields")
        assert(not keys[spec.key], class .. " " .. spec.key .. " twice")
        keys[spec.key] = true
        tabs[spec.tab] = true
        for stat, weight in pairs(spec.weights) do
            assert(KNOWN[stat], class .. " " .. spec.key .. ": unknown stat " .. stat)
            assert(type(weight) == "number" and weight >= 0, class .. " " .. spec.key .. " " .. stat)
        end
        assert(spec.name:sub(2) == spec.name:sub(2):lower(), "sentence case: " .. spec.name)
    end
    assert(tabs[1] and tabs[2] and tabs[3], class .. " covers its three trees")
end

-- No talents: the first spec. Points: the tree with the most.
client.class = "MAGE"
local spec, how = Specs:Active()
assert(spec.key == "arcane" and how == "default")
client.talents = { 2, 0, 9 }
spec, how = Specs:Active()
assert(spec.key == "frost" and how == "talents")

-- A pick stands over the talents, by key or name in any case, until "auto".
assert(Specs:Pick("FIRE").key == "fire")
spec, how = Specs:Active()
assert(spec.key == "fire" and how == "picked")
assert(Specs:Pick("holy") == nil, "not a mage spec")
assert(Specs:Active().key == "fire", "a bad name changes nothing")
Specs:Pick(nil)
assert(Specs:Active().key == "frost")

-- The druid's feral tree guesses the cat; the bear is picked by name.
client.class, client.talents = "DRUID", { 0, 11, 0 }
assert(Specs:Active().key == "feral")
assert(Specs:Pick("feral (bear)").key == "bear")

client.class = "DEATHKNIGHT"
assert(Specs:Active() == nil, "no weights for a class Forever does not have")
return true
