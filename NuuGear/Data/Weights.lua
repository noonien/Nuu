local _, ns = ...

-- Stat weights per class and spec, for the level 20 beta. Our own numbers:
-- nobody has published Forever weights yet (no Pawn scale, no sim output as
-- of 2026-10-01), so they are worked out from Forever's stat conversions and
-- checked against each spec's published level 20 priority (Icy Veins'
-- Forever guides, as leprestore.com repeats them). See status.md for the
-- sources and the method.
--
-- Each spec's weights are in its own unit: 1 point of its main stat
-- (Strength, Agility, spell power or healing) is 1. Only items scored by the
-- same spec are ever compared, so the units never meet.
--
-- How the numbers were reached:
--   * Attack power: Strength gives 2 AP to warriors, paladins, shamans and
--     druids, 1 to the rest; Agility 1 AP to rogues, hunters and cats, 2
--     ranged AP to hunters. 14 AP is 1 damage per second.
--   * WeaponDPS is the melee weapon's damage per second, worth 14 AP: 7
--     Strength for a 2-AP class. An off-hand weapon's counts half
--     (Domain/Upgrades.lua). RangedDPS is the ranged slot's (bow, gun,
--     thrown, wand).
--   * Hit and Crit are Forever's single shared stats (melee, ranged and
--     spells alike), on gear as a percentage, so their weight is per 1%.
--     Expertise is per 1% less dodged or parried. Haste is on no gear yet.
--   * SpellPower is "damage and healing done by magical spells", SpellDamage
--     the damage-only form, the schools their own lines. Bonus healing also
--     gives a third of itself as spell damage, so damage casters weigh
--     Healing at a third.
--   * Armor is per point, a tie-breaker for most specs and a real stat for
--     tanks.
--
-- `tab` is the spec's talent tree, used to guess the spec from talents when
-- the player has not picked one (Domain/Specs.lua): the first spec of a tree
-- is the guess.

local function melee(extra)
    local weights = { Strength = 1, Agility = 0.45, Stamina = 0.3, AttackPower = 0.5, Hit = 2.5, Crit = 2,
        Expertise = 2.2, WeaponDPS = 7, RangedDPS = 0.3, Armor = 0.01, HP5 = 0.3 }
    for key, value in pairs(extra or {}) do weights[key] = value end
    return weights
end

local function caster(school, extra)
    local weights = { SpellPower = 1, SpellDamage = 1, Healing = 0.33, Intellect = 0.5, Spirit = 0.4,
        Stamina = 0.25, Hit = 3.5, Crit = 3, MP5 = 1, RangedDPS = 2, Armor = 0.005 }
    weights[school] = 1
    for key, value in pairs(extra or {}) do weights[key] = value end
    return weights
end

local function healer(extra)
    local weights = { Healing = 1, SpellPower = 1, Intellect = 0.6, Spirit = 0.45, MP5 = 1.3, Crit = 2.5,
        Stamina = 0.2, RangedDPS = 0.5, Armor = 0.005 }
    for key, value in pairs(extra or {}) do weights[key] = value end
    return weights
end

ns.weights = {
    WARRIOR = {
        -- Weapon Damage > Hit > Crit > Strength > Agility > Stamina
        { key = "arms", name = "Arms", tab = 1, weights = melee() },
        { key = "fury", name = "Fury", tab = 2, weights = melee() },
        -- Weapon Damage > Hit > Armor > Stamina > Agility > Crit > Strength
        { key = "protection", name = "Protection", tab = 3, role = "tank", weights = melee({
            WeaponDPS = 6, Strength = 0.6, Agility = 0.8, Stamina = 1, Crit = 1.5, Armor = 0.05,
            Defense = 0.8, Dodge = 5, Parry = 5, Block = 3, BlockValue = 0.3, HP5 = 0.8 }) },
    },
    PALADIN = {
        -- Healing Power > Intellect > MP5 > Spell Crit > Spirit
        { key = "holy", name = "Holy", tab = 1, role = "healer", weights = healer({
            Intellect = 0.7, MP5 = 1.4, Crit = 3, Spirit = 0.35, Holy = 0.1 }) },
        -- Weapon Damage > Hit > Stamina > Strength > Armor > Agility > Crit
        { key = "protection", name = "Protection", tab = 2, role = "tank", weights = melee({
            WeaponDPS = 6, Stamina = 1, Strength = 0.9, Agility = 0.6, Crit = 1.2, Armor = 0.04,
            Defense = 0.8, Dodge = 5, Parry = 5, Block = 3, BlockValue = 0.3, SpellPower = 0.4,
            Holy = 0.4, Intellect = 0.35, HP5 = 0.8 }) },
        -- Weapon Damage > Hit > Crit > Stamina > Spirit > Intellect > Strength > Agility > Spell Power
        { key = "retribution", name = "Retribution", tab = 3, weights = melee({
            Agility = 0.4, Stamina = 0.4, Spirit = 0.25, Intellect = 0.3, SpellPower = 0.35, Holy = 0.35,
            Healing = 0.1, MP5 = 0.4 }) },
    },
    HUNTER = {
        -- Ranged Weapon Damage > Hit > Agility > Crit > Spirit > Intellect > Stamina
        { key = "beastmastery", name = "Beast mastery", tab = 1, weights = {
            Agility = 1, RangedDPS = 6.5, WeaponDPS = 1, RangedAttackPower = 0.45, AttackPower = 0.1,
            Hit = 3, Crit = 2.5, Expertise = 0.3, Spirit = 0.3, Intellect = 0.3, Stamina = 0.25, MP5 = 0.6,
            Strength = 0.05, Armor = 0.01 } },
        -- The same; Careful Aim turns Intellect into attack power.
        { key = "marksmanship", name = "Marksmanship", tab = 2, weights = {
            Agility = 1, RangedDPS = 6.5, WeaponDPS = 1, RangedAttackPower = 0.45, AttackPower = 0.1,
            Hit = 3, Crit = 2.5, Expertise = 0.3, Spirit = 0.3, Intellect = 0.45, Stamina = 0.25, MP5 = 0.6,
            Strength = 0.05, Armor = 0.01 } },
        -- Weapon Damage > Hit > Agility > Crit > Spirit > Intellect > Stamina; played mostly at range at 20.
        { key = "survival", name = "Survival", tab = 3, weights = {
            Agility = 1, RangedDPS = 6, WeaponDPS = 2, RangedAttackPower = 0.45, AttackPower = 0.3,
            Hit = 3, Crit = 2.5, Expertise = 0.8, Spirit = 0.3, Intellect = 0.3, Stamina = 0.25, MP5 = 0.6,
            Strength = 0.3, Armor = 0.01 } },
    },
    ROGUE = {
        -- Weapon Damage > Hit > Agility > Crit > Strength > Stamina
        { key = "assassination", name = "Assassination", tab = 1, weights = {
            Agility = 1, Strength = 0.75, AttackPower = 0.75, WeaponDPS = 10, RangedDPS = 0.5, Hit = 4.5,
            Crit = 3.5, Expertise = 3.5, Stamina = 0.3, Armor = 0.005, HP5 = 0.3 } },
        { key = "combat", name = "Combat", tab = 2, weights = {
            Agility = 1, Strength = 0.75, AttackPower = 0.75, WeaponDPS = 10, RangedDPS = 0.5, Hit = 4.5,
            Crit = 3.5, Expertise = 3.5, Stamina = 0.3, Armor = 0.005, HP5 = 0.3 } },
        -- Weapon Damage > Hit > Expertise > Agility > Crit > Strength > Stamina
        { key = "subtlety", name = "Subtlety", tab = 3, weights = {
            Agility = 1, Strength = 0.75, AttackPower = 0.75, WeaponDPS = 10, RangedDPS = 0.5, Hit = 4.5,
            Crit = 3.5, Expertise = 4, Stamina = 0.3, Armor = 0.005, HP5 = 0.3 } },
    },
    PRIEST = {
        -- Healing Power > MP5 > Spirit > Intellect > Crit
        { key = "discipline", name = "Discipline", tab = 1, role = "healer", weights = healer({
            Spirit = 0.6, Intellect = 0.55, Holy = 0.1, RangedDPS = 1 }) },
        -- Healing Power > MP5 > Spirit > Intellect > Stamina > Crit
        { key = "holy", name = "Holy", tab = 2, role = "healer", weights = healer({
            Spirit = 0.6, Intellect = 0.5, Stamina = 0.25, Holy = 0.1, RangedDPS = 1 }) },
        -- Spell Power > Crit > Hit > Intellect > MP5
        { key = "shadow", name = "Shadow", tab = 3, weights = caster("Shadow", {
            Holy = 0.2, Hit = 3, Crit = 3, Spirit = 0.45, Stamina = 0.3, RangedDPS = 2.5 }) },
    },
    SHAMAN = {
        -- Spell Power > Hit > Crit > Intellect > MP5 > Spirit > Stamina
        { key = "elemental", name = "Elemental", tab = 1, weights = caster("Nature", {
            Fire = 0.5, Frost = 0.2, Hit = 4, Spirit = 0.3, RangedDPS = 0, WeaponDPS = 0.5, Armor = 0.01 }) },
        -- Weapon DPS > Expertise and Hit > Crit > Strength > Intellect > Agility > MP5
        { key = "enhancement", name = "Enhancement", tab = 2, weights = melee({
            Agility = 0.4, Intellect = 0.25, MP5 = 0.3, SpellPower = 0.2, Nature = 0.2, Fire = 0.1,
            Frost = 0.1, Spirit = 0.1, Expertise = 2.5, RangedDPS = 0 }) },
        -- Healing Power, then Intellect, Spirit and MP5 (Mindfulness keeps Spirit regen while casting)
        { key = "restoration", name = "Restoration", tab = 3, role = "healer", weights = healer({
            Intellect = 0.65, Spirit = 0.55, RangedDPS = 0, Armor = 0.01 }) },
    },
    MAGE = {
        -- Hit > Spell Power > Spirit > Intellect > Crit > Stamina > MP5 (Frostbolt still does the levelling)
        { key = "arcane", name = "Arcane", tab = 1, weights = caster("Arcane", {
            Fire = 0.3, Frost = 0.6, Hit = 4, Spirit = 0.5, Intellect = 0.55 }) },
        -- Hit > Spell Power > Crit > Spirit > Intellect > Stamina > MP5
        { key = "fire", name = "Fire", tab = 2, weights = caster("Fire", {
            Frost = 0.2, Arcane = 0.2, Hit = 4, Crit = 3.5, Spirit = 0.45, Intellect = 0.45 }) },
        -- Spell Damage or Frost Damage > Hit > Intellect > Crit > Spirit
        { key = "frost", name = "Frost", tab = 3, weights = caster("Frost", {
            Fire = 0.2, Arcane = 0.2 }) },
    },
    WARLOCK = {
        -- Spell Power > Hit > Crit > Intellect / Stamina > Spirit; Life Tap scales with Spirit
        { key = "affliction", name = "Affliction", tab = 1, weights = caster("Shadow", {
            Fire = 0.15, Crit = 2, Intellect = 0.4, Stamina = 0.4, Spirit = 0.45, MP5 = 0.8, RangedDPS = 2.5 }) },
        -- Hit > Spell Power > Crit > Intellect / Stamina
        { key = "demonology", name = "Demonology", tab = 2, weights = caster("Shadow", {
            Fire = 0.2, Hit = 4, Crit = 2.5, Intellect = 0.4, Stamina = 0.4, Spirit = 0.45, MP5 = 0.8,
            RangedDPS = 2.5 }) },
        -- Spell Power > Hit > Crit > Intellect > Stamina > Spirit
        { key = "destruction", name = "Destruction", tab = 3, weights = caster("Shadow", {
            Fire = 0.5, Crit = 3, Intellect = 0.4, Stamina = 0.4, Spirit = 0.35, MP5 = 0.8, RangedDPS = 2.5 }) },
    },
    DRUID = {
        -- Spell Power > Intellect > Crit > Spirit; Moonfire and Starfire are Arcane
        { key = "balance", name = "Balance", tab = 1, weights = caster("Nature", {
            Arcane = 0.6, Hit = 3.5, RangedDPS = 0 }) },
        -- Weapon DPS > Hit > Crit > Strength > Stamina > Agility > Spirit
        { key = "feral", name = "Feral (cat)", tab = 2, weights = {
            Strength = 1, Agility = 0.7, Stamina = 0.35, AttackPower = 0.5, FeralAttackPower = 0.5,
            WeaponDPS = 4, Hit = 2.5, Crit = 2, Expertise = 2, Spirit = 0.15, Intellect = 0.1, Armor = 0.01,
            HP5 = 0.3 } },
        -- No published level 20 order: Armor, Stamina, avoidance, Hit, weapon DPS, offence.
        { key = "bear", name = "Feral (bear)", tab = 2, role = "tank", weights = {
            Stamina = 1, Agility = 0.9, Strength = 0.7, Armor = 0.06, Dodge = 5, Defense = 0.8,
            AttackPower = 0.35, FeralAttackPower = 0.35, WeaponDPS = 2, Hit = 2, Crit = 1.5, Expertise = 1.5,
            HP5 = 0.8 } },
        -- Healing Power > Spirit > Intellect > Crit > Stamina
        { key = "restoration", name = "Restoration", tab = 3, role = "healer", weights = healer({
            Spirit = 0.65, Intellect = 0.55, MP5 = 1.2, RangedDPS = 0, Armor = 0.008 }) },
    },
}
