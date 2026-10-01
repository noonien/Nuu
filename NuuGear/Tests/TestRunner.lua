-- Run from the NuuGear folder with a standalone Lua 5.1 interpreter:
--   nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"
-- The kit comes from ../NuuKit (Tests/Support/Namespace.lua).
dofile("Tests/Support/Namespace.lua")

local suites = {
    { "load order", "Tests/LoadTests.lua" },
    { "client", "Tests/ClientTests.lua" },
    { "item stats", "Tests/ItemStatsTests.lua" },
    { "specs", "Tests/SpecsTests.lua" },
    { "upgrades", "Tests/UpgradesTests.lua" },
    -- Last: it stands in for the client's frame API in _G.
    { "markers", "Tests/MarkersTests.lua" },
}
for _, suite in ipairs(suites) do
    local ok, err = pcall(dofile, suite[2])
    if not ok then
        io.stderr:write("NuuGear " .. suite[1] .. " tests failed: " .. tostring(err) .. "\n")
        os.exit(1)
    end
end
print("NuuGear " .. #suites .. " test suites passed")
