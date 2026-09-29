-- Each planner fixture played the way the game plays it
-- (Tools/SessionLog/plan_playthrough.lua): plan, Make the step the button
-- picks, craft the batch with every skill-up outcome followed at its
-- chance, plan again. No plan may ask for more than the bags hold, leave
-- the Make button with nothing it can make short of its target, or end
-- with the materials for a skill-up still in the bags; and following the
-- plan must end at least as high, on average, as the best fixed order of
-- the first plan's crafts (Tools/SessionLog/plan_orders.lua).
local ns = NewNamespace()
Load(ns, "Config.lua")
Load(ns, "Data/ProfessionTiers.lua")
Load(ns, "Domain/Prices.lua")
Load(ns, "Domain/ProfessionPlanner.lua")
LoadProfessionData(ns)
local Playthrough = dofile("Tools/SessionLog/plan_playthrough.lua")
local Orders = dofile("Tools/SessionLog/plan_orders.lua")

local count = 0
local pipe = io.popen("ls Tests/Fixtures/Planner/*.lua 2>/dev/null")
for path in pipe:lines() do
    local fixture = dofile(path)
    -- A fixture too big to follow every outcome (`playthrough = "sample"`)
    -- is played along a few rolled paths instead, each checked the same.
    if fixture.playthrough == "sample" then
        for seed = 1, 5 do
            local _, problems = Playthrough.Sample(ns, fixture, seed)
            assert(#problems == 0, path .. " (sample " .. seed .. "): " .. table.concat(problems, "; "))
        end
    end
    local orders = fixture.playthrough ~= "sample" and Orders.All(ns, fixture) or nil
    for _, single in ipairs(fixture.playthrough == "sample" and {} or { false, true }) do
        local mode = single and "one craft a press" or "a batch a press"
        local exact = Playthrough.Exact(ns, fixture, { single = single })
        assert(#exact.problems == 0, path .. " (" .. mode .. "): " .. table.concat(exact.problems, "; "))
        local total = 0
        for _, share in pairs(exact.odds) do total = total + share end
        assert(math.abs(total - 1) < 1e-9, path .. ": the odds add up to " .. total)
        -- Within a ten-thousandth of a skill: a last craft below the chance
        -- floor (a grinding stone at 2.5 percent, left unmade at 84 when the
        -- belt takes the last skill) is a known gap worth about 5e-6. An order
        -- mistake costs far more (the belt before one stone: 0.016).
        if orders then
            assert(exact.expected >= orders[1].expected - 1e-4, string.format(
                "%s (%s): following the plan ends at %.9f on average, the order %s at %.9f",
                path, mode, exact.expected, orders[1].text, orders[1].expected))
        end
    end
    count = count + 1
end
pipe:close()
assert(count > 0, "no planner fixtures in Tests/Fixtures/Planner")
return true
