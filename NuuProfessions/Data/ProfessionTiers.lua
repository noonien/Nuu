local _, ns = ...

-- Trainer tiers: how far each one lets a profession go, the character level it
-- asks for, and what training it costs. The client database holds none of
-- this, so it is authored, at the scope of the beta's level cap (Apprentice,
-- Journeyman and Expert). Artisan is in the full list only, which the planner's
-- testing switch turns on (SetFullScope) to plan past the beta's cap; it joins
-- the beta list when the cap passes 35.
--
-- UNVERIFIED ON FOREVER. These are Classic's caps and gates. They are checked at
-- a trainer before they are trusted; `verified` flips per tier when they are.
--
--   cap      the highest skill the tier allows
--   level    the character level it needs
--   minSkill  the skill at which the trainer offers it (Classic: 50, 125)
--   cost     the fee in copper; nil is unknown, counted as 0 and flagged
--            "cost unknown" in the plan. A fee a trainer window showed
--            (NuuProfessionsDB.professions.trainers) is used instead when the
--            tier's spell for the profession is recorded there.
--   spells   the tier's training spell per profession: Classic IDs, used
--            only to find a recorded fee, and unverified on Forever
local apprentice = { name = "Apprentice", cap = 75, level = 1, minSkill = 0, cost = nil, verified = false,
    spells = { Alchemy = 2259, Blacksmithing = 2018, Enchanting = 7411, Engineering = 4036,
               Leatherworking = 2108, Tailoring = 3908, ["First Aid"] = 3273, Cooking = 2550 } }
local journeyman = { name = "Journeyman", cap = 150, level = 10, minSkill = 50, cost = nil, verified = false,
    spells = { Alchemy = 3101, Blacksmithing = 3100, Enchanting = 7412, Engineering = 4037,
               Leatherworking = 3104, Tailoring = 3909, ["First Aid"] = 3274, Cooking = 3102 } }
local expert = { name = "Expert", cap = 225, level = 20, minSkill = 125, cost = nil, verified = false,
    spells = { Alchemy = 3464, Blacksmithing = 3538, Enchanting = 7413, Engineering = 4038,
               Leatherworking = 3811, Tailoring = 3910, ["First Aid"] = 7924, Cooking = 3413 } }
-- Past the beta's cap: Classic's gate and spells, not seen on Forever at all.
local artisan = { name = "Artisan", cap = 300, level = 35, minSkill = 200, cost = nil, verified = false,
    spells = { Alchemy = 11611, Blacksmithing = 9785, Enchanting = 13920, Engineering = 12656,
               Leatherworking = 10662, Tailoring = 12180, ["First Aid"] = 10846, Cooking = 18260 } }

local ProfessionTiers = {
    verified = false,
    fullScope = false,
    -- The beta's tiers, and every tier to Classic's 300. `tiers` is one of the
    -- two; everything reads it.
    betaTiers = { apprentice, journeyman, expert },
    fullTiers = { apprentice, journeyman, expert, artisan },
}
ProfessionTiers.tiers = ProfessionTiers.betaTiers

-- The testing switch: with `on`, the tiers run to Artisan (300) whatever the
-- beta's cap; off puts back the beta's.
function ProfessionTiers:SetFullScope(on)
    self.fullScope = on and true or false
    self.tiers = self.fullScope and self.fullTiers or self.betaTiers
end

-- The tier whose cap covers `skill`: the one a player at that skill has, or
-- needs, trained. Skill 0 is no profession at all, which is Apprentice to learn.
function ProfessionTiers:ForSkill(skill)
    for index, tier in ipairs(self.tiers) do
        if skill < tier.cap then return tier, index end
    end
    return self.tiers[#self.tiers], #self.tiers
end

-- The highest cap a character of `level` can train to.
function ProfessionTiers:CapForLevel(level)
    local cap, name
    for _, tier in ipairs(self.tiers) do
        if not level or level >= tier.level then cap, name = tier.cap, tier.name end
    end
    return cap or 0, name
end

-- The highest cap at this scope.
function ProfessionTiers:MaxCap()
    return self.tiers[#self.tiers].cap
end

ns:RegisterModule("ProfessionTiers", ProfessionTiers)
