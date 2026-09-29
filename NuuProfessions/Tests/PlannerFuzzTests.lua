-- Random Profession Planner play (Tools/SessionLog/plan_fuzz.lua): a fixed
-- set of seeds, each a character made from the real recipe data and played
-- as a player would - Make and craft with a plan after every craft, with
-- other crafts, loot, lost materials, option and target changes, other
-- ways, refused recipes and goals in between, in both Only what I have and
-- buying - and every plan checked against the invariants listed there. A
-- failure names its seed; `lua Tools/SessionLog/fuzz.lua --seed N` plays it
-- move by move, `--dump M` shows the character and its plan at a move.
-- Run many more seeds with `lua Tools/SessionLog/fuzz.lua --seeds 1000`.
local ns = NewNamespace()
Load(ns, "Config.lua")
Load(ns, "Data/ProfessionTiers.lua")
Load(ns, "Domain/Prices.lua")
Load(ns, "Domain/ProfessionPlanner.lua")
LoadProfessionData(ns)
local Fuzz = dofile("Tools/SessionLog/plan_fuzz.lua")

local seeds, moves = 40, 16
local all = {}
for seed = 1, seeds do
    local problems = Fuzz.Play(ns, seed, { moves = moves })
    for _, problem in ipairs(problems) do table.insert(all, problem) end
end
assert(#all == 0, #all .. " planner invariant(s) broken:\n  " .. table.concat(all, "\n  "))
return true
