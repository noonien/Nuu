-- Domain/ItemStats.lua: the client's stat table and tooltip lines into one set
-- of stat names.
local ns = NewNamespace()
Load(ns, "Domain/ItemStats.lua")
local ItemStats = ns.modules.ItemStats
local Parse = ItemStats.Parse

local function lines(...)
    local result = {}
    for _, text in ipairs({ ... }) do table.insert(result, { left = text }) end
    return result
end

-- The client's keys, with Forever's one Hit and one Crit whatever the flavour.
local stats = Parse({ ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3, RESISTANCE0_NAME = 120,
    ITEM_MOD_HIT_SPELL_RATING_SHORT = 1, ITEM_MOD_CRIT_MELEE_RATING_SHORT = 1, ITEM_MOD_UNKNOWN_SHORT = 9 }, nil)
assert(stats.Strength == 5 and stats.Stamina == 3 and stats.Armor == 120)
assert(stats.Hit == 1 and stats.Crit == 1, "every flavour of hit and crit is the one stat")
assert(stats.ITEM_MOD_UNKNOWN_SHORT == nil)

-- The tooltip fills in what the client's table left out; the client's
-- numbers stand where both say.
stats = Parse({ ITEM_MOD_INTELLECT_SHORT = 4 }, lines(
    "Thistlefur Robe", "Chest", "65 Armor", "+6 Intellect", "+4 Spirit",
    "Durability 70 / 70", "Requires Level 18",
    "Equip: Increases damage and healing done by magical spells and effects by up to 7.",
    "Equip: Improves your chance to get a critical strike by 1%.",
    "Equip: Restores 2 mana per 5 sec."))
assert(stats.Intellect == 4, "the client's own number stands")
assert(stats.Spirit == 4 and stats.Armor == 65)
assert(stats.SpellPower == 7 and stats.Crit == 1 and stats.MP5 == 2, "MP5 is the first number, not the 5 sec")

-- Weapons: damage per second; spell lines with a school; healing with its
-- own damage number.
stats = Parse(nil, lines("Main Hand", "Sword", "29 - 55 Damage", "Speed 2.60", "(16.2 damage per second)",
    "Equip: Improves your chance to hit by 1%.", "Chance on hit: Blasts the target for 40 Fire damage."))
assert(stats.DPS == 16.2 and stats.Hit == 1)
assert(stats.SpellDamage == nil and stats.Fire == nil, "weapon damage and procs are not spell power")
stats = Parse(nil, lines("Equip: Increases damage done by Shadow spells and effects by up to 8."))
assert(stats.Shadow == 8 and stats.SpellDamage == nil)
stats = Parse(nil, lines("Equip: Increases healing done by spells and effects by up to 48 and damage done by up to 16."))
assert(stats.Healing == 48 and stats.SpellDamage == 16)
stats = Parse(nil, lines("Equip: Increases healing done by spells and effects by up to 22."))
assert(stats.Healing == 22 and stats.SpellPower == nil)
stats = Parse(nil, lines("Equip: Increases damage done by magical spells and effects by up to 5."))
assert(stats.SpellDamage == 5)

-- Physical and tank lines.
stats = Parse(nil, lines("Equip: +12 Attack Power.", "Equip: +20 Attack Power in Cat, Bear, and Dire Bear forms only.",
    "Equip: +15 ranged Attack Power.", "Equip: Reduces the chance for your attacks to be dodged or parried by 1%.",
    "Equip: Increases your chance to dodge an attack by 1%.", "Equip: Increased Defense +5.",
    "38 Block", "Equip: Increases the block value of your shield by 6.", "Equip: Restores 3 health per 5 sec."))
assert(stats.AttackPower == 12 and stats.FeralAttackPower == 20 and stats.RangedAttackPower == 15)
assert(stats.Expertise == 1 and stats.Dodge == 1 and stats.Defense == 5 and stats.HP5 == 3)
assert(stats.BlockValue == 44, "the shield's own block and the bonus to it")

-- What only lasts a while, or only sometimes, is left out.
stats = Parse(nil, lines("Use: Increases attack power by 100 for 20 sec.", "(2) Set: +10 Stamina.",
    "\"Strength of the ancients: +50 Strength\"", "+10 Fire Resistance"))
assert(next(stats) == nil, "use effects, set bonuses, flavour text and resistances")

assert(Parse(nil, nil) == nil, "nothing to read")

-- Get keeps what it read per link until the tooltip data it came from is
-- updated, and reads nothing while the item is loading.
local client = dofile("Tests/Support/FakeClient.lua")
ns.modules.Client = client
local link = client:Item("Ring", "INVTYPE_FINGER", { ITEM_MOD_AGILITY_SHORT = 2 }, { loading = true })
assert(ItemStats:Get(link) == nil, "still loading")
client.items[link].loading = false
client.items[link].lines = { "Ring" }
client.items[link].instance = 77
assert(ItemStats:Get(link).Agility == 2)
client.items[link].lines = { "Ring", "Equip: Improves your chance to hit by 1%." }
assert(ItemStats:Get(link).Hit == nil, "kept from the first read")
assert(ItemStats:Updated(78) == nil, "another tooltip's update")
assert(ItemStats:Updated(77) == link)
assert(ItemStats:Get(link).Hit == 1, "read again once its tooltip came in full")
return true
