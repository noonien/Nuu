-- Build-time port check, not shipped behaviour: compares a ported guide's
-- step order against the RestedXP source it was ported from.
--
--   lua Tools/CompareGuideOrder.lua Data/Guides/<Guide>.lua <source>.lua ["<#name>"]
--
-- One RestedXP file holds several registrations of the same route - one per
-- experience rate, and season variants besides - so the third argument names
-- the `#name` of the registration the port was made from ("6-12 Mulgore").
-- Without it the whole file is read, and matching will wander into a
-- duplicate of the route and call everything after it out of order.
--
-- For every quest reference in our guide (an objective part, a turn-in, an
-- accept) it finds where that reference appears in the source, and walks our
-- steps in order looking for a position that only ever moves forward.
--
-- The source states the same reference several times: a class variant, a
-- season variant, an experience-rate variant, and an opportunistic turn-in
-- that the route later does properly. So a step is matched to the earliest
-- source line at or after the step before it, not to the first line in the
-- file; only a step with no such line left is really out of order. Matching
-- greedily this way is what keeps the report down to the steps worth reading.
--
-- It also compares the map: a source step whose `.goto` names one zone and a
-- ported step whose coordinates resolve on another is the port having
-- dropped a `map = ...`, which sends the arrow to the right numbers in the
-- wrong zone.
--
-- Only ports made from a RestedXP source can be checked this way. A
-- Zygor-derived port has a different source format and will report nonsense.
--
-- A report is still a candidate, not a verdict. A step the source carried
-- alongside another with #completewith legitimately sits elsewhere in our
-- order, and the report says when the source line it wanted is inside such a
-- step. Read the source around the reported line before moving anything, and
-- record in the port's header comment any divergence kept on purpose.
_G = _G or _ENV
-- The addon's files take (addon name, ns), as the client runs them.
dofile("Tests/Support/Namespace.lua")
local ns = NewNamespace()
Load(ns, "Data/GuideCheck.lua"); Load(ns, "Data/Names.lua"); Load(ns, "Data/Steps.lua")
Load(ns, "Data/IDNames.lua")
ns.packagedGuides, ns.builtInGuides = {}, {}
Load(ns, arg[1])
for _, guide in ipairs(ns.packagedGuides) do ns.builtInGuides[guide.id] = guide end

-- The line range of the registration named by arg[3], or the whole file.
local wanted = arg[3]
local firstLine, lastLine, line = 1, math.huge, 0
if wanted then
    local starts, names = {}, {}
    for text in io.lines(arg[2]) do
        line = line + 1
        if text:match("RegisterGuide") then table.insert(starts, line) end
        local name = text:match("^#name%s+(.-)%s*$")
        if name then names[#starts] = name end
    end
    local total = line
    local chosen
    for index, name in pairs(names) do
        if name == wanted then chosen = index end
    end
    if not chosen then
        io.stderr:write("no registration named '" .. wanted .. "' in " .. arg[2] .. "\n")
        os.exit(1)
    end
    firstLine = starts[chosen]
    lastLine = (starts[chosen + 1] or (total + 1)) - 1
end

-- Zones the ported guides reach, by the names the source writes.
local mapIDs = {
    ["Mulgore"] = 1412, ["Thunder Bluff"] = 1456, ["The Barrens"] = 1413, ["Durotar"] = 1411,
    ["Orgrimmar"] = 1454, ["Stonetalon Mountains"] = 1442, ["Ashenvale"] = 1440,
}

-- key -> every source line stating it, in file order, and the map each
-- source line's own step block travels to.
local source, sourceMap, pendingMap = {}, {}, nil
local function record(key)
    source[key] = source[key] or {}
    table.insert(source[key], line)
    sourceMap[line] = pendingMap
end
line = 0
for text in io.lines(arg[2]) do
    line = line + 1
    if line >= firstLine and line <= lastLine then
        if text:match("^step") then pendingMap = nil end
        local zone = text:match("^%s*%.goto%s+([^,]+),")
        if zone and not pendingMap then
            pendingMap = tonumber(zone:match("^(%d+)/")) or mapIDs[zone]
        end
        local quest, part = text:match("^%s*%.complete%s+(%d+),(%d+)")
        if quest then record("c" .. quest .. "." .. part) end
        for _, verb in ipairs({ "turnin", "accept" }) do
            local ids = text:match("^%s*%." .. verb .. "%s+([%d,]+)")
            for id in (ids or ""):gmatch("%d+") do record(verb:sub(1, 1) .. id) end
        end
    end
end
-- Whether the step block holding a line is one the source carries alongside
-- another step. The directive can follow the references in its block, so the
-- flag is applied to the whole block in a second pass.
local blockCarried, blockStart, flags = false, 0, {}
line = 0
for text in io.lines(arg[2]) do
    line = line + 1
    if text:match("^step") then
        for at = blockStart, line - 1 do flags[at] = blockCarried end
        blockStart, blockCarried = line, false
    end
    if text:match("^%s*#completewith") then blockCarried = true end
end
for at = blockStart, line do flags[at] = blockCarried end

local function keysFor(node)
    local auto, keys = node.auto, {}
    if not auto then return keys end
    if auto.part and auto.quests then table.insert(keys, "c" .. auto.quests[1] .. "." .. auto.part) end
    for _, q in ipairs(auto.turnin or (auto.verb == "turnin" and auto.quests) or {}) do table.insert(keys, "t" .. q) end
    for _, q in ipairs(auto.accept or (auto.verb == "accept" and auto.quests) or {}) do table.insert(keys, "a" .. q) end
    return keys
end

for id, guide in pairs(ns.builtInGuides) do
    local expanded = ns.modules.Steps:Expand(guide)
    print("== " .. id)
    local previous, previousStep, matched, reported = firstLine - 1, 0, 0, 0
    for index, node in ipairs(expanded.nodes) do
        local keys = keysFor(node)
        if #keys > 0 then
            -- The earliest source line at or after where we already are, and,
            -- failing that, the latest line before it: what the step would
            -- have matched if the order allowed.
            local forward, backward
            for _, key in ipairs(keys) do
                for _, at in ipairs(source[key] or {}) do
                    if at >= previous then
                        if not forward or at < forward then forward = at end
                    elseif not backward or at > backward then
                        backward = at
                    end
                end
            end
            if forward or backward then matched = matched + 1 end
            if forward then
                previous, previousStep = forward, index
                local want, have = sourceMap[forward], node.location and node.location.mapID
                if want and have and want ~= have then
                    reported = reported + 1
                    print(string.format("  step %3d is on map %d, but source line %d is on map %d  |  %s",
                        index, have, forward, want, ns.modules.Steps:Title(node, true)))
                end
            elseif backward then
                reported = reported + 1
                print(string.format("  step %3d wants source line %d, behind step %d at line %d%s  |  %s",
                    index, backward, previousStep, previous,
                    flags[backward] and " (a #completewith step in the source)" or "",
                    ns.modules.Steps:Title(node, true)))
            end
        end
    end
    print(string.format("  %d steps matched, %d reported", matched, reported))
end
