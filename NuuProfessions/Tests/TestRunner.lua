-- Run from the NuuProfessions folder with a standalone Lua 5.1 interpreter:
--   nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"
-- The kit comes from ../NuuKit (Tests/Support/Namespace.lua), so the suites
-- always run on the current kit. The kit's own suites (the skill-up model,
-- crafting and the rest) are NuuKit's runner's.
dofile("Tests/Support/Namespace.lua")

local suites = {
    { "load order", "Tests/LoadTests.lua" },
    { "profession client", "Tests/ProfessionClientTests.lua" },
    { "prices", "Tests/PricesTests.lua" },
    { "profession planner", "Tests/ProfessionPlannerTests.lua" },
    { "planner fixtures", "Tests/PlannerFixtureTests.lua" },
    { "planner playthroughs", "Tests/PlannerPlaythroughTests.lua" },
    { "planner fuzz", "Tests/PlannerFuzzTests.lua" },
    { "colour audit", "Tests/ColorAuditTests.lua" },
    -- Last: they stand in for the client's frame API in _G.
    { "planner window", "Tests/UISmokeTests.lua" },
    { "replanning", "Tests/ReplanTests.lua" },
}
for _, suite in ipairs(suites) do
    local ok, err = pcall(dofile, suite[2])
    if not ok then
        io.stderr:write("NuuProfessions " .. suite[1] .. " tests failed: " .. tostring(err) .. "\n")
        os.exit(1)
    end
end
print("NuuProfessions " .. #suites .. " test suites passed")
