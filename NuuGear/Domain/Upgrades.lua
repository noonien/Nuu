local _, ns = ...

-- Whether an item beats what the character wears, scored with the active
-- spec's weights. The slot rules are ForeverGear's: a ring or trinket is
-- weighed against the weaker of the two worn, a two-hander against both
-- hands together, a one-hander in either hand when the character can dual
-- wield, and nothing goes in the off hand while a two-hander is worn. An
-- off-hand weapon's damage counts half, as the game deals it.
local Upgrades = { cache = {} }

local function Client() return ns.modules.Client end

-- Equip location -> the slots it can go in (the character's inventory slot
-- numbers). Shirts, tabards, bags, quivers and ammo are never upgrades.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}
Upgrades.SLOTS = SLOTS

local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local OFF_HAND, MAIN_HAND = 17, 16

-- Differences smaller than this are rounding, not an upgrade.
local EPSILON = 0.001

-- An item's score under `weights`. `equipLoc` says whether its damage per
-- second is a ranged or a melee weapon's; `offHand`, that it would be swung
-- in the off hand.
function Upgrades.Score(stats, weights, equipLoc, offHand)
    local score = 0
    for stat, value in pairs(stats) do
        local weight
        if stat == "DPS" then
            if RANGED[equipLoc] then weight = weights.RangedDPS
            else weight = (weights.WeaponDPS or 0) * (offHand and 0.5 or 1) end
        else
            weight = weights[stat]
        end
        score = score + value * (weight or 0)
    end
    return score
end

-- What is worn in a slot: { link, equipLoc, stats }, an empty table for an
-- empty slot, or nil while its stats are not loaded.
local function worn(slot)
    local link = Client():GetEquippedLink(slot)
    if not link then return {} end
    local stats = ns.modules.ItemStats:Get(link)
    if not stats then return nil end
    local instant = Client():GetItemInstant(link)
    return { link = link, equipLoc = instant and instant.equipLoc, stats = stats }
end

local function wornScore(item, weights, slot)
    if not item.stats then return 0 end
    return Upgrades.Score(item.stats, weights, item.equipLoc, slot == OFF_HAND)
end

-- The ways the item could be worn: each { slot, replaces = { slots }, offHand }.
-- nil when one of the slots it would replace is not loaded yet.
local function placements(equipLoc, wornIn)
    local mainHand = wornIn(MAIN_HAND)
    if mainHand == nil then return nil end
    local twoHander = mainHand.equipLoc == "INVTYPE_2HWEAPON"
    if equipLoc == "INVTYPE_2HWEAPON" then
        return { { slot = MAIN_HAND, replaces = { MAIN_HAND, OFF_HAND } } }
    elseif equipLoc == "INVTYPE_WEAPON" then
        local options = { { slot = MAIN_HAND, replaces = { MAIN_HAND } } }
        if Client():CanDualWield() and not twoHander then
            table.insert(options, { slot = OFF_HAND, replaces = { OFF_HAND }, offHand = true })
        end
        return options
    elseif equipLoc == "INVTYPE_WEAPONOFFHAND" then
        if twoHander or not Client():CanDualWield() then return {} end
        return { { slot = OFF_HAND, replaces = { OFF_HAND }, offHand = true } }
    elseif SLOTS[equipLoc][1] == OFF_HAND then
        if twoHander then return {} end
        return { { slot = OFF_HAND, replaces = { OFF_HAND } } }
    end
    local options = {}
    for _, slot in ipairs(SLOTS[equipLoc]) do
        table.insert(options, { slot = slot, replaces = { slot } })
    end
    return options
end

-- How the item compares, as { state, score, delta, slot, spec }:
--   "upgrade"    it scores higher than what it would replace (`delta` > 0)
--   "downgrade"  lower; "same" no different
--   "unusable"   the character cannot wear it (class, proficiency, level)
--   "blocked"    no slot takes it as worn now (an off hand under a two-hander)
--   "unknown"    the item or what it would replace is not loaded yet
--   "none"       not gear, or no weights for this class
-- Kept per link until Forget; "unknown" is not kept.
function Upgrades:Evaluate(link)
    if not link then return { state = "none" } end
    local cached = self.cache[link]
    if cached then return cached end
    local result = self:Compare(link)
    if result.state ~= "unknown" then self.cache[link] = result end
    return result
end

function Upgrades:Compare(link)
    local instant = Client():GetItemInstant(link)
    local equipLoc = instant and instant.equipLoc
    if not equipLoc or not SLOTS[equipLoc] then return { state = "none" } end
    local spec = ns.modules.Specs:Active()
    if not spec then return { state = "none" } end
    if Client():CanUseItem(instant.itemID) == false then return { state = "unusable", spec = spec } end
    local stats = ns.modules.ItemStats:Get(link)
    if not stats then return { state = "unknown" } end

    local seen = {}
    local function wornIn(slot)
        if seen[slot] == nil then seen[slot] = worn(slot) or false end
        return seen[slot] or nil
    end
    local options = placements(equipLoc, wornIn)
    if not options then return { state = "unknown" } end
    if #options == 0 then return { state = "blocked", spec = spec } end

    local best
    for _, option in ipairs(options) do
        local score = Upgrades.Score(stats, spec.weights, equipLoc, option.offHand)
        local replaced = 0
        for _, slot in ipairs(option.replaces) do
            local item = wornIn(slot)
            if not item then return { state = "unknown" } end
            if item.link == link then replaced = math.huge end
            replaced = replaced + wornScore(item, spec.weights, slot)
        end
        local delta = score - replaced
        if not best or delta > best.delta then
            best = { score = score, delta = delta, slot = option.slot, replaced = replaced }
        end
    end
    if best.delta > EPSILON then best.state = "upgrade"
    elseif best.delta < -EPSILON then best.state = "downgrade"
    else best.state = "same" end
    best.spec = spec
    return best
end

function Upgrades:IsUpgrade(link)
    return self:Evaluate(link).state == "upgrade"
end

-- Drops every verdict and every item read: the gear worn, the spec or the
-- client's item data changed.
function Upgrades:Forget()
    self.cache = {}
    ns.modules.ItemStats:Forget()
end

-- The tooltip data `instance` came in full (TOOLTIP_DATA_UPDATE): drops what
-- was read from it. Whether it was one of ours. An item worn may be the one,
-- so every verdict goes then, not only its own.
function Upgrades:TooltipUpdated(instance)
    local link = ns.modules.ItemStats:Updated(instance)
    if not link then return false end
    self.cache = {}
    return true
end

ns:RegisterModule("Upgrades", Upgrades)
