-- Plans recorded in the game (Tests/Fixtures/Planner/*.lua, written by
-- Tools/SessionLog/replay_plan.lua --fixture), planned again with the real
-- recipe data: each must come out as its `expect` says. The toy professions
-- of ProfessionPlannerTests.lua check the planner's rules; these check that
-- the rules give the right route on what a character really has.
local ns = NewNamespace()
Load(ns, "Config.lua")
Load(ns, "Data/ProfessionTiers.lua")
Load(ns, "Domain/Prices.lua")
Load(ns, "Domain/ProfessionPlanner.lua")
LoadProfessionData(ns)
local Planner = ns.modules.ProfessionPlanner
local Snapshot = dofile("Tools/SessionLog/plan_snapshot.lua")

local count = 0
local pipe = io.popen("ls Tests/Fixtures/Planner/*.lua 2>/dev/null")
for path in pipe:lines() do
    local fixture = dofile(path)
    local input = assert(Snapshot.Input(ns, fixture), path .. ": no input")
    local route = Planner:Plan(input)
    local planned = Snapshot.Describe(route.runs)
    assert(planned == fixture.expect, path .. (fixture.note and (" (" .. fixture.note .. ")") or "")
        .. "\n  expected " .. tostring(fixture.expect) .. "\n  planned  " .. planned)
    count = count + 1
end
pipe:close()
assert(count > 0, "no planner fixtures in Tests/Fixtures/Planner")
return true
