-- Run from the NuuKit folder with a standalone Lua 5.1 interpreter:
--   nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"
_G = _G or _ENV

-- Loads the kit the way the client does: every file `NuuKit.toc` lists, in
-- its order, into one addon table, except the development-only NuuKit.lua.
-- Returns that table; its `Kit` is what the suites test.
function LoadKit(addonName)
    local ns = {}
    for line in io.lines("NuuKit.toc") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file and file ~= "NuuKit.lua" then
            local chunk = assert(loadfile(file))
            chunk(addonName or "NuuKit", ns)
        end
    end
    return ns
end

local suites = {
    { "logging", "Tests/Core/LoggingTests.lua" },
    { "recorder", "Tests/Core/RecorderTests.lua" },
    { "bug report", "Tests/Core/BugReportTests.lua" },
    { "ui theme", "Tests/UI/ThemeTests.lua" },
    { "ui base", "Tests/UI/BaseTests.lua" },
    { "ui display", "Tests/UI/DisplayTests.lua" },
    -- Last: it stands in for the client's frame API in _G.
    { "ui smoke", "Tests/UI/Smoke/Run.lua" },
}
for _, suite in ipairs(suites) do
    local ok, err = pcall(dofile, suite[2])
    if not ok then
        io.stderr:write("NuuKit " .. suite[1] .. " tests failed: " .. tostring(err) .. "\n")
        os.exit(1)
    end
end
print("NuuKit " .. #suites .. " test suites passed")
