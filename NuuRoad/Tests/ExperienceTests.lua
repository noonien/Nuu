_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

-- A stand-in client: only Read and IsSecret are used.
local player = { level = 10, xp = 0, xpMax = 7600, rested = nil }
ns.modules.Client = {
    Read = function(_, func, ...) if type(func) ~= "function" then return nil end return func(...) end,
    IsSecret = function() return false end,
}
UnitLevel = function() return player.level end
UnitXP = function() return player.xp end
UnitXPMax = function() return player.xpMax end
GetXPExhaustion = function() return player.rested end

Load(ns, "Domain/Experience.lua")
local Experience = ns.modules.Experience

local function eq(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

-- Chat lines, the English fallbacks: a plain kill, a rested kill (the bonus
-- is taken off), and quest experience, which is not a kill.
eq(Experience:ParseMessage("Kolkar Bloodcharger dies, you gain 120 experience."), 120, "plain kill")
eq(Experience:ParseMessage("Kolkar Bloodcharger dies, you gain 240 experience. (+120 exp Rested bonus)"), 120, "rested kill")
eq(Experience:ParseMessage("You gain 850 experience."), nil, "quest experience")
eq(Experience:ParseMessage(""), nil, "empty")

-- The client's own format strings, positional arguments included.
COMBATLOG_XPGAIN_FIRSTPERSON = "%1$s dies, you gain %2$d experience."
eq(Experience:ParseMessage("Plainstrider dies, you gain 99 experience."), 99, "positional format")
COMBATLOG_XPGAIN_FIRSTPERSON = nil

-- No kill seen yet: a mob of the player's level, 10 * 5 + 45 = 95.
local left = Experience:Left(11)
eq(left.xp, 7600, "xp to the next level")
eq(left.kills, math.ceil(7600 / 95), "kills from the formula")
eq(Experience:Describe(left), "7600 XP, ~80 kills", "describe")

-- Kills seen: their average. The five kept are the newest.
for _, xp in ipairs({ 1, 1, 100, 100, 100, 100, 100 }) do Experience:OnMessage("Mob dies, you gain " .. xp .. " experience.") end
eq(#Experience.kills, 5, "five kept")
eq(Experience:Left(11).kills, 76, "kills from the average")

-- Two levels on: this level's remainder plus the next one from the curve,
-- scaled by what the client says this level takes (here exactly the curve).
player.xp = 7000
eq(Experience:Left(12).xp, 600 + 8800, "two levels")
-- With experience into the target level.
eq(Experience:Left(11, 500).xp, 1100, "level plus experience")
player.level = 11; player.xp = 200; player.xpMax = 8800
eq(Experience:Left(11, 500).xp, 300, "experience in the target level")
eq(Experience:Left(11), nil, "already there")
eq(Experience:Left(10), nil, "past it")

-- Rested: half the pool is bonus, never more than half of what is needed.
player.level, player.xp, player.xpMax, player.rested = 10, 0, 7600, 2000
eq(Experience:Left(11).kills, math.ceil((7600 - 1000) / 100), "rested")
player.rested = 100000
eq(Experience:Left(11).kills, math.ceil(3800 / 100), "rested capped")

-- Unreadable client: nothing to say.
UnitXP = function() return nil end
eq(Experience:Left(11), nil, "no experience reading")
UnitXP = function() return player.xp end

-- `by`: the turn-ins between a level step and the step it names count as
-- experience on the way.
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
local Steps = ns.modules.Steps
local guide = Steps:Expand({
    schema = 2, id = "test:xp", updated = 1789862400, map = 1413, meta = { title = "XP", category = "test" },
    steps = { { section = "Grind", steps = {
        { level = 11, by = "ratchet" },
        { turnin = 871, accept = 872, npc = 3429, at = { 51, 30 } },
        { turnin = 844, npc = 3338, at = { 52, 31 } },
        { turnin = 819, npc = 3292, only = "Shaman", at = { 62, 38 } },
        { turnin = 872, npc = 3429, at = { 51, 30 } },
        { turnin = 900, npc = 3429, at = { 51, 30 } },
        { travel = "Ratchet", label = "ratchet", at = { 63, 37 } },
        { turnin = 887, npc = 3391, at = { 62, 36 } },
    } } },
})
eq(guide.nodes[1].completion.observed.by, 7, "by resolves to the labelled step")
eq(Steps:Title(guide.nodes[1]), "Reach level 11 by step 7", "title")
eq(ns.modules.Schema:Validate(guide), true, "validates")
local function expands(steps)
    return (pcall(Steps.Expand, Steps, { schema = 2, id = "t", updated = 1, meta = { title = "t", category = "t" },
        steps = { { section = "s", steps = steps } } }))
end
eq(expands({ { note = "x", label = "a" }, { level = 3, by = "a" } }), false, "by names a later step")
eq(expands({ { level = 3, by = "a" }, { note = "x" } }), false, "by names a label that exists")
eq(expands({ { level = 3, xp = 100, by = "a" }, { note = "x", label = "a" } }), false, "no xp with by")

-- 871 and 844 are in the log, 872 is taken on the way, 819 is for a Shaman
-- (this is not one), 900 was never taken, and 887 is past the step.
local inLog, finished, logXP = { [871] = true, [844] = true }, {}, { [871] = 400, [844] = 300 }
local Client = ns.modules.Client
Client.IsQuestInLog = function(_, id) return inLog[id] == true end
Client.IsQuestComplete = function(_, id) return finished[id] == true end
Client.GetQuestLogRewardXP = function(_, id) return logXP[id] end
ns.modules.Progress = {
    GetActiveGuide = function() return guide end,
    IsAvailable = function(_, node) return node.condition == nil end,
}
ns.db = { questXP = {} }
local observed = guide.nodes[1].completion.observed
player.level, player.xp, player.xpMax, player.rested = 10, 6000, 7600, nil
Experience.kills = {}

local pending = Experience:Pending(guide, 1, 7)
eq(pending.quests, 3, "three turn-ins count")
eq(pending.xp, 700, "known experience")
eq(pending.unknown, 1, "872 is not known yet")
-- The unknown one is left out, and the line says so.
eq(Experience:Progress(observed, 1), "900 XP, ~10 kills, 1 turn-in not counted", "unknown said")

-- 872 learned from its offer: all three are credited.
Experience:LearnQuestXP(872, 500)
eq(Experience:Target(observed, 1).credit, 1200, "all three credited")
eq(Experience:Progress(observed, 1), "400 XP, ~5 kills", "owed less the turn-ins")
eq(Experience:Reached(observed, 1), false, "not yet")
player.xp = 6400
eq(Experience:Reached(observed, 1), true, "the turn-ins bring the level")

-- A quest already handed in no longer counts.
finished[871] = true
eq(Experience:Pending(guide, 1, 7).xp, 800, "handed in")

-- Learned at a turn-in: the event's second value.
eq(Experience:LearnQuestXP(900, 0), false, "zero is not learned")
eq(Experience:LearnQuestXP(900, 650), true, "learned")
eq(Experience:QuestXP(900), 650, "read back")
