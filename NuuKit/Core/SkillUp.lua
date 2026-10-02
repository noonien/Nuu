local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- The skill-up model: how likely one craft is to raise a profession by a
-- point, and how many crafts a stretch of skill levels takes on average and with
-- what spread. Pure arithmetic over a recipe's four skill levels; the planner and
-- the tracker's notes are built on it.
--
-- A recipe's skill levels are { orange, yellow, green, grey } (O, Y, G, R). At skill s:
--
--   s < O        cannot be made
--   O <= s < Y   orange: chance 1
--   Y <= s < R   (R - s) / (R - Y), the accepted Classic formula; green is
--                about 50% and below
--   s >= R       grey: 0
--
-- One craft gives at most one point (to be checked on Forever). The crafts
-- needed for one point at skill s are geometric: expected 1/p, variance
-- (1-p)/p^2, and a run of consecutive points adds both up.
local SkillUp = {}

-- Chances below this are not planned on unless nothing else is left.
SkillUp.floor = 0.15

-- How many standard deviations the shopping list adds to the expected count:
-- typical is the expected count, safe finishes about 90% of runs, sure 99%.
SkillUp.confidence = { typical = 0, safe = 1.3, sure = 2.3 }
SkillUp.confidenceOrder = { "typical", "safe", "sure" }

function SkillUp:Z(confidence)
    if type(confidence) == "number" then return confidence end
    return self.confidence[confidence or "safe"] or self.confidence.safe
end

-- "orange", "yellow", "green", "grey", or "unknown" when the skill is below
-- the learn skill. Green starts at G; the chance does not care about G, only
-- the colour shown to the player does.
function SkillUp:Color(skills, skill)
    local orange, yellow, green, grey = skills[1], skills[2], skills[3], skills[4]
    if skill < orange then return "unknown" end
    if skill >= grey then return "grey" end
    if skill < yellow then return "orange" end
    if green and skill >= green then return "green" end
    return "yellow"
end

-- The chance that one craft at `skill` gives a point. A recipe whose yellow
-- is not below its grey (bad data) is treated as orange until grey.
function SkillUp:Chance(skills, skill)
    local orange, yellow, grey = skills[1], skills[2], skills[4]
    if skill < orange or skill >= grey then return 0 end
    if skill < yellow or grey <= yellow then return 1 end
    return (grey - skill) / (grey - yellow)
end

-- True when the chance is at or above the floor: a recipe the planner uses
-- freely. Below it, the recipe is a last resort.
function SkillUp:AboveFloor(skills, skill, floor)
    return self:Chance(skills, skill) >= (floor or self.floor)
end

-- Expected crafts and their variance to take one point at `skill`. nil when
-- the recipe cannot give a point there.
function SkillUp:Point(skills, skill)
    local p = self:Chance(skills, skill)
    if p <= 0 then return nil end
    return 1 / p, (1 - p) / (p * p)
end

-- Expected crafts and variance to go from skill `from` to skill `to` with one
-- recipe: the points taken at from, from+1, ..., to-1. nil when some skill in
-- between gives no point at all.
function SkillUp:Span(skills, from, to)
    local expected, variance = 0, 0
    for skill = from, to - 1 do
        local e, v = self:Point(skills, skill)
        if not e then return nil end
        expected, variance = expected + e, variance + v
    end
    return expected, variance
end

-- The number of crafts to plan for: the expected count plus z standard
-- deviations, rounded up to a whole craft. With no margin (z 0, typical) it
-- is the nearest whole craft: the count of crafts is skewed, so a fraction
-- above the expected count is more often not needed (7.39 expected crafts
-- are enough about 61% of the time in 7).
function SkillUp:Count(expected, variance, z)
    local count = expected + (z or 0) * math.sqrt(math.max(variance or 0, 0))
    if (z or 0) <= 0 then return math.max(math.floor(count + 0.5), 0) end
    return math.max(math.ceil(count - 1e-9), 0)
end

-- A low and a high count around the expected one at z standard deviations,
-- never below `atLeast` (a run of n points is never fewer than n crafts).
function SkillUp:Range(expected, variance, z, atLeast)
    local spread = (z or 0) * math.sqrt(math.max(variance or 0, 0))
    local low = math.max(math.floor(expected - spread + 1e-9), atLeast or 0)
    local high = math.max(math.ceil(expected + spread - 1e-9), low)
    return low, high
end

-- The expected points `count` crafts give when starting at `skill`, walking
-- the skill up by each craft's expected gain. Used for goals, which have a
-- count and no target skill. The points are fractional; the caller rounds.
function SkillUp:Gain(skills, skill, count)
    local reached = skill
    for _ = 1, count do
        reached = reached + self:Chance(skills, math.floor(reached + 1e-9))
    end
    return reached - skill
end

Kit.SkillUp = SkillUp
