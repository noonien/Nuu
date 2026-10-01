-- Run from the NuuRoad folder with a standalone Lua 5.1 interpreter:
--   nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"
-- The kit comes from ../NuuKit (Tests/Support/Namespace.lua), so the suites
-- always run on the current kit. The kit's own suites (the recorder, bug
-- reports, the skill-up model, crafting and the UI) are NuuKit's runner's.
dofile("Tests/Support/Namespace.lua")

local suites = {
    { "load order", "Tests/LoadTests.lua" },
    { "settings", "Tests/SettingsTests.lua" },
    { "schema", "Tests/SchemaTests.lua" },
    { "groups", "Tests/GroupTests.lua" },
    { "guide editing", "Tests/GuideEditingTests.lua" },
    { "progress", "Tests/ProgressTests.lua" },
    { "navigation", "Tests/NavigationTests.lua" },
    { "travel", "Tests/TravelTests.lua" },
    { "places", "Tests/PlacesTests.lua" },
    { "client", "Tests/ClientTests.lua" },
    { "predicates", "Tests/PredicateTests.lua" },
    { "steps", "Tests/StepsTests.lua" },
    { "npc tracking", "Tests/NPCTrackingTests.lua" },
    { "target marking", "Tests/TargetMarkingTests.lua" },
    { "quest dialog", "Tests/QuestDialogTests.lua" },
    { "quest selection", "Tests/QuestSelectionTests.lua" },
    { "junk selling", "Tests/JunkSellingTests.lua" },
    { "loot reminder", "Tests/LootReminderTests.lua" },
    { "quest POI log", "Tests/POILogTests.lua" },
    { "recording", "Tests/RecordingTests.lua" },
    { "bug report", "Tests/BugReportTests.lua" },
    { "guide corrections", "Tests/GuideCorrectionsTests.lua" },
    { "built-in guide", "Tests/BuiltInGuideTests.lua" },
    { "guide audit", "Tests/GuideAuditTests.lua" },
    { "guide scan", "Tests/GuideScanTests.lua" },
    { "observed progress", "Tests/ObservedProgressTests.lua" },
    { "experience", "Tests/ExperienceTests.lua" },
    { "step state", "Tests/StepStateTests.lua" },
    { "quest index", "Tests/QuestIndexTests.lua" },
    { "guide catalog", "Tests/GuideCatalogTests.lua" },
    { "materials", "Tests/MaterialsTests.lua" },
    { "skyborne flow", "Tests/SkyborneFlowTests.lua" },
    { "port constructs", "Tests/PortConstructTests.lua" },
    { "guide port", "Tests/GuidePortTests.lua" },
    -- Last: they stand in for the client's frame API in _G
    -- (Tests/UI/Harness.lua).
    { "tracker", "Tests/UI/TrackerTests.lua" },
    { "guide browser", "Tests/UI/BrowserTests.lua" },
    { "editor", "Tests/UI/EditorTests.lua" },
    { "panels", "Tests/UI/PanelsTests.lua" },
    { "options and forms", "Tests/UI/FormsTests.lua" },
    { "travel windows", "Tests/UI/TravelTests.lua" },
}
local only = arg and arg[1]
local ran = 0
for _, suite in ipairs(suites) do
    if not only or suite[1] == only or suite[2] == only then
        local ok, err = pcall(dofile, suite[2])
        if not ok then
            io.stderr:write("NuuRoad " .. suite[1] .. " tests failed: " .. tostring(err) .. "\n")
            os.exit(1)
        end
        ran = ran + 1
    end
end
print("NuuRoad " .. ran .. " test suites passed")
