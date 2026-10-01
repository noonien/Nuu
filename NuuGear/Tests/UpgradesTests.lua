-- Domain/Upgrades.lua: an item against what it would replace, slot by slot.
local ns, client = NewDomain()
local Upgrades = ns.modules.Upgrades

local function state(link)
    Upgrades:Forget()
    return Upgrades:Evaluate(link).state
end

-- One slot: higher score is an upgrade, an empty slot takes anything that
-- scores, gear that scores nothing is not an upgrade.
client.class = "WARRIOR"
local worn = client:Item("Worn belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 3 })
local better = client:Item("Strong belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 5 })
local worse = client:Item("Weak belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 1 })
local casterBelt = client:Item("Cloth belt", "INVTYPE_WAIST", { ITEM_MOD_INTELLECT_SHORT = 8 })
client.worn[6] = worn
assert(state(better) == "upgrade" and state(worse) == "downgrade" and state(worn) == "downgrade")
assert(state(casterBelt) == "downgrade", "intellect is nothing to an arms warrior")
local result = Upgrades:Evaluate(better)
assert(result.slot == 6 and result.score == 5 and result.replaced == 3 and result.spec.key == "arms")
client.worn[6] = nil
assert(state(worse) == "upgrade", "an empty slot")
assert(state(client:Item("Plain belt", "INVTYPE_WAIST", {})) == "same")

-- Not gear, not wearable, or not loaded yet.
assert(state(client:Item("Shirt", "INVTYPE_BODY", { ITEM_MOD_STRENGTH_SHORT = 9 })) == "none")
assert(state(client:Item("Linen", nil, {})) == "none")
assert(state(client:Item("Plate", "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 9 }, { usable = false })) == "unusable")
local loading = client:Item("New boots", "INVTYPE_FEET", { ITEM_MOD_STRENGTH_SHORT = 9 }, { loading = true })
assert(state(loading) == "unknown")
assert(Upgrades.cache[loading] == nil, "unknown is asked again, not kept")
client.items[loading].loading = false
assert(state(loading) == "upgrade")
local wornLoading = client:Item("Worn boots", "INVTYPE_FEET", { ITEM_MOD_STRENGTH_SHORT = 1 }, { loading = true })
client.worn[8] = wornLoading
assert(state(loading) == "unknown", "what it replaces is not loaded")
client.worn[8] = nil

-- Rings and trinkets: against the weaker one worn, or an empty one.
local ring5 = client:Item("Ring 5", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 5 })
local ring2 = client:Item("Ring 2", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 2 })
local ring3 = client:Item("Ring 3", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 3 })
client.worn[11], client.worn[12] = ring5, ring2
assert(state(ring3) == "upgrade" and Upgrades:Evaluate(ring3).slot == 12)
client.worn[12] = nil
assert(state(ring2) == "upgrade", "the second ring slot is empty")

-- Weapons. 7 Strength per point of weapon DPS for an arms warrior.
local twoHander = client:Item("Greatsword", "INVTYPE_2HWEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 14 })
local sword = client:Item("Sword", "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 })
local shield = client:Item("Shield", "INVTYPE_SHIELD", { RESISTANCE0_NAME = 300, ITEM_MOD_STRENGTH_SHORT = 2 })
local offSword = client:Item("Off sword", "INVTYPE_WEAPONOFFHAND", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 })
client.worn[16], client.worn[17] = sword, shield
-- 14 * 7 = 98 against 10 * 7 + (300 * 0.01 + 2) = 75.
assert(state(twoHander) == "upgrade", "a two-hander against both hands")
client.worn[16], client.worn[17] = twoHander, nil
assert(state(sword) == "downgrade")
assert(state(shield) == "blocked", "no off hand under a two-hander")
assert(state(offSword) == "blocked")

-- Dual wield: a one-hander may go in either hand, its damage counting half
-- in the off hand.
client.class, client.dualWield = "ROGUE", true
local dagger = client:Item("Dagger", "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9 })
local mainDagger = client:Item("Main dagger", "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 })
local offDagger = client:Item("Off dagger", "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8 })
client.worn[16], client.worn[17] = mainDagger, offDagger
result = Upgrades:Evaluate(dagger)
Upgrades:Forget()
result = Upgrades:Evaluate(dagger)
assert(result.state == "upgrade" and result.slot == 17, "better than the off hand")
assert(math.abs(result.delta - (9 - 8) * 10 * 0.5) < 1e-9, "off-hand damage counts half")
client.dualWield = false
assert(state(offSword) == "blocked", "an off-hand weapon needs dual wield")
assert(state(dagger) == "downgrade", "only the main hand without dual wield")

-- A caster weighs a wand in the ranged slot and ignores melee damage.
client.class, client.talents = "PRIEST", { 0, 0, 5 }
local wand = client:Item("Wand", "INVTYPE_RANGEDRIGHT", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15 })
local oldWand = client:Item("Old wand", "INVTYPE_RANGEDRIGHT", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 })
local mace = client:Item("Mace", "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 })
client.worn[18], client.worn[16], client.worn[17] = oldWand, nil, nil
assert(state(wand) == "upgrade")
assert(state(mace) == "same", "melee damage is nothing to a shadow priest")

-- The spec decides: a healing robe is an upgrade for holy, not shadow.
local robe = client:Item("Healing robe", "INVTYPE_ROBE", nil,
    { lines = { "Equip: Increases healing done by spells and effects by up to 20." } })
local shadowRobe = client:Item("Shadow robe", "INVTYPE_CHEST", nil,
    { lines = { "Equip: Increases damage done by Shadow spells and effects by up to 10." } })
client.worn[5] = shadowRobe
assert(state(robe) == "downgrade", "shadow: 20 healing is 6.6 against 10 shadow")
ns.modules.Specs:Pick("holy")
assert(state(robe) == "upgrade")

-- Verdicts are kept until Forget, or until a tooltip of ours comes in full.
client.class = "WARRIOR"
client.worn[6] = worn
local lateBelt = client:Item("Late belt", "INVTYPE_WAIST", {}, { lines = { "Late belt" }, instance = 5 })
Upgrades:Forget()
assert(Upgrades:Evaluate(lateBelt).state == "downgrade")
client.items[lateBelt].lines = { "Late belt", "+9 Strength" }
assert(Upgrades:Evaluate(lateBelt).state == "downgrade", "kept")
assert(not Upgrades:TooltipUpdated(6))
assert(Upgrades:TooltipUpdated(5))
assert(Upgrades:Evaluate(lateBelt).state == "upgrade", "read again")
return true
