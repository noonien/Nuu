local _, ns = ...

-- An item's stats under one set of names (the keys Data/Weights.lua weighs).
-- The client's own stat table comes first; the tooltip fills in what it
-- leaves out, which on Forever is often the green "Equip:" lines, spell
-- power and school damage, a shield's block value and a weapon's damage
-- (ForeverGear found the same). Parse is pure; Get reads the client and
-- keeps what it read per link until Forget.
local ItemStats = { cache = {}, waiting = {} }

-- The client's stat keys. Forever has one Hit and one Crit for melee, ranged
-- and spells, so every flavour of either lands on the same name.
local KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "Strength",
    ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_STAMINA_SHORT = "Stamina",
    ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit",
    RESISTANCE0_NAME = "Armor",
    ITEM_MOD_ATTACK_POWER_SHORT = "AttackPower",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RangedAttackPower",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "FeralAttackPower",
    ITEM_MOD_SPELL_POWER_SHORT = "SpellPower",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SpellDamage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing",
    ITEM_MOD_SPELL_HEALING_DONE = "Healing",
    ITEM_MOD_HIT_RATING_SHORT = "Hit",
    ITEM_MOD_HIT_MELEE_RATING_SHORT = "Hit",
    ITEM_MOD_HIT_RANGED_RATING_SHORT = "Hit",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "Hit",
    ITEM_MOD_CRIT_RATING_SHORT = "Crit",
    ITEM_MOD_CRIT_MELEE_RATING_SHORT = "Crit",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT = "Crit",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "Crit",
    ITEM_MOD_HASTE_RATING_SHORT = "Haste",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "Expertise",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense",
    ITEM_MOD_DODGE_RATING_SHORT = "Dodge",
    ITEM_MOD_PARRY_RATING_SHORT = "Parry",
    ITEM_MOD_BLOCK_RATING_SHORT = "Block",
    ITEM_MOD_BLOCK_VALUE_SHORT = "BlockValue",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
    ITEM_MOD_HEALTH_REGEN_SHORT = "HP5",
    ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}
ItemStats.KEYS = KEYS

local SCHOOLS = { arcane = "Arcane", fire = "Fire", frost = "Frost", holy = "Holy", nature = "Nature", shadow = "Shadow" }
local PRIMARY = { strength = "Strength", agility = "Agility", stamina = "Stamina", intellect = "Intellect",
    spirit = "Spirit" }

local function numbers(line)
    local found = {}
    for value in line:gmatch("%d+[%.,]?%d*") do
        table.insert(found, tonumber((value:gsub(",", "."))))
    end
    return found
end

local function has(line, ...)
    for index = 1, select("#", ...) do
        if line:find((select(index, ...)), 1, true) then return true end
    end
    return false
end

-- Two lines of one stat add up: a shield's own block value and an "Equip:"
-- bonus to it are both worn.
local function add(out, stat, value)
    if value then out[stat] = (out[stat] or 0) + value end
end

-- Spell power, healing and school damage lines. "Increases damage and
-- healing done by magical spells and effects by up to 12" is both;
-- "Increases healing done by spells and effects by up to 48 and damage done
-- by up to 16" gives each its own number, in the order the words come.
local function spellLine(line, out)
    local values = numbers(line)
    if #values == 0 or has(line, "resist") then return false end
    local healing, damage = line:find("healing", 1, true), line:find("damage", 1, true)
    if healing and damage and #values >= 2 then
        local first, second = values[1], values[2]
        if healing > damage then first, second = second, first end
        add(out, "Healing", first)
        add(out, "SpellDamage", second)
        return true
    end
    if healing and damage then add(out, "SpellPower", values[#values]); return true end
    if healing then add(out, "Healing", values[#values]); return true end
    if damage and has(line, "spells", "spell damage") then
        for word, school in pairs(SCHOOLS) do
            if line:find(word .. " spells", 1, true) or line:find(word .. " damage", 1, true) then
                add(out, school, values[#values])
                return true
            end
        end
        add(out, "SpellDamage", values[#values])
        return true
    end
    return false
end

-- One tooltip line, lower case, into `out`. Returns whether it named a stat.
-- What only lasts a while or only sometimes counts is left out: "Use:"
-- effects, "Chance on hit:" procs, set bonuses ("(2) Set: ...") and the
-- quoted flavour text.
local function parseLine(line, out)
    if line:find("^use:") or line:find("^chance on hit") or line:find("^%(%d+%) set") or line:find('^"') then
        return false
    end
    local value = line:match("%((%d+[%.,]?%d*) damage per second%)")
    if value then add(out, "DPS", tonumber((value:gsub(",", ".")))); return true end
    value = line:match("^(%d+) armor$")
    if value then add(out, "Armor", tonumber(value)); return true end
    value = line:match("^(%d+) block$")
    if value then add(out, "BlockValue", tonumber(value)); return true end
    local amount, word = line:match("^%+(%d+) (%a+)$")
    if amount and PRIMARY[word] then add(out, PRIMARY[word], tonumber(amount)); return true end

    local values = numbers(line)
    if #values == 0 then return false end
    local last = values[#values]
    if has(line, "attack power") then
        if has(line, "cat", "bear") then add(out, "FeralAttackPower", last)
        elseif has(line, "ranged attack power") then add(out, "RangedAttackPower", last)
        else add(out, "AttackPower", last) end
        return true
    end
    if has(line, "critical strike", "critical hit") then add(out, "Crit", last); return true end
    if has(line, "chance to hit") then add(out, "Hit", last); return true end
    if has(line, "dodged or parried", "expertise") then add(out, "Expertise", last); return true end
    if has(line, "mana per 5", "mana every 5") then add(out, "MP5", values[1]); return true end
    if has(line, "health per 5", "health every 5") then add(out, "HP5", values[1]); return true end
    if has(line, "block value") then add(out, "BlockValue", last); return true end
    if has(line, "chance to block") then add(out, "Block", last); return true end
    if has(line, "chance to dodge") then add(out, "Dodge", last); return true end
    if has(line, "chance to parry") then add(out, "Parry", last); return true end
    if has(line, "defense") then add(out, "Defense", last); return true end
    if has(line, "haste") then add(out, "Haste", last); return true end
    return spellLine(line, out)
end

-- Stats from the client's table (`apiStats`, its keys) and the tooltip's
-- lines ({ left, right } each); either may be nil. The client's numbers
-- stand; the tooltip only adds stats the client left out. nil when neither
-- said anything.
function ItemStats.Parse(apiStats, lines)
    if not apiStats and not lines then return nil end
    local stats = {}
    for key, value in pairs(apiStats or {}) do
        local name = KEYS[key]
        if name and value ~= 0 then stats[name] = (stats[name] or 0) + value end
    end
    local found = {}
    for _, line in ipairs(lines or {}) do
        if line.left then parseLine(line.left:lower(), found) end
    end
    for name, value in pairs(found) do
        if not stats[name] and value ~= 0 then stats[name] = value end
    end
    return stats
end

-- The stats of the item a link names, or nil while the client has not loaded
-- it (GET_ITEM_INFO_RECEIVED says when to ask again).
function ItemStats:Get(link)
    if not link then return nil end
    local cached = self.cache[link]
    if cached then return cached end
    local Client = ns.modules.Client
    if not Client:IsItemLoaded(link) then return nil end
    local lines, instance = Client:GetTooltipLines(link)
    local stats = ItemStats.Parse(Client:GetItemStats(link), lines)
    if stats then self.cache[link] = stats end
    if instance then self.waiting[instance] = link end
    return stats
end

-- The link whose tooltip data `instance` is, forgotten so the next Get reads
-- it again; nil when it is none of ours (TOOLTIP_DATA_UPDATE fires for every
-- tooltip the game shows).
function ItemStats:Updated(instance)
    local link = instance and self.waiting[instance]
    if not link then return nil end
    self.waiting[instance] = nil
    self.cache[link] = nil
    return link
end

-- Drops everything read, for when the client's answers may have changed.
function ItemStats:Forget()
    self.cache = {}
    self.waiting = {}
end

ns:RegisterModule("ItemStats", ItemStats)
