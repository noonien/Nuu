_G = _G or _ENV
-- The guide port pipeline is developer tooling: it never loads in the client
-- and reads only text. These tests prove the reader never executes its input,
-- and hold the mapping table to the sources it claims to cover.
local RestedXP = dofile("Tools/GuidePort/RestedXP.lua")
local Mapping = dofile("Tools/GuidePort/Mapping.lua")

-- Reading a guide, including the parts a port has to keep: the header, the
-- gate on a step, directives, commands with their arguments and display text,
-- and a gate on a single command.
local sample = [==[
local faction = UnitFactionGroup("player")
RXPGuides.RegisterGuide([[
#classic
#name 1-6 Mulgore
#version 11
#group RestedXP Forever Guide (H)
#defaultfor Tauren
#next 6-12 Mulgore
<< Horde

step << !Tauren
    #completewith next
    .goto Mulgore,44.92,77.12
    +You have selected a guide meant for Tauren
step
    #label GrullTurnin
    .goto Mulgore,44.92,77.12
    >>Talk to Grull
    .accept 747 >>Accept The Hunt Begins
    .turnin 747,1 >>Turn in The Hunt Begins << Druid
    .target Grull Hawkwind
step
    #loop
    .goto Mulgore,47.36,83.05,0
    .complete 747,1 --Plainstrider Meat (7)
    .mob Plainstrider
]])
]==]

local registrations = RestedXP:Parse(sample, "sample.lua")
assert(#registrations == 1, "one registration")
local guide = registrations[1]
assert(guide.meta.name == "1-6 Mulgore")
assert(guide.meta.version == "11")
assert(guide.meta.next == "6-12 Mulgore")
assert(guide.meta.defaultFor == "Tauren")
assert(guide.meta.faction == "Horde")
assert(guide.meta.flags.classic == true, "a bare header flag is recorded")
assert(#guide.steps == 3, "three steps, got " .. #guide.steps)

local first = guide.steps[1]
assert(first.gate == "!Tauren", "a step gate is kept")
assert(first.directives[1].name == "completewith" and first.directives[1].value == "next")
assert(first.commands[1].name == "goto" and first.commands[1].args == "Mulgore,44.92,77.12")
assert(#first.display == 1 and first.display[1].text:find("meant for Tauren"))

local second = guide.steps[2]
assert(second.directives[1].name == "label" and second.directives[1].value == "GrullTurnin")
assert(second.commands[2].name == "accept" and second.commands[2].args == "747")
assert(second.commands[2].display == "Accept The Hunt Begins")
assert(second.commands[3].gate == "Druid", "a gate on one command is kept")
assert(second.commands[3].args == "747,1", "the argument keeps its objective index")
assert(second.commands[4].name == "target" and second.commands[4].args == "Grull Hawkwind")
assert(second.line < guide.steps[3].line, "steps keep their source line")

local third = guide.steps[3]
assert(third.directives[1].name == "loop")
assert(third.commands[2].args == "747,1 --Plainstrider Meat (7)", "trailing source comments are kept verbatim")

-- The census feeds the coverage gate.
local commands, directives = RestedXP:Census(registrations)
assert(commands["goto"] == 3 and commands.accept == 1 and commands.mob == 1)
assert(directives.completewith == 1 and directives.loop == 1 and directives.label == 1)

-- Reading never executes. A body that would delete the world is still text.
local hostile = [==[
RXPGuides.RegisterGuide([[
#name Hostile
step
    .goto Mulgore,1,1
]])
]==]
_G.portCanary = nil
local parsedHostile = RestedXP:Parse(hostile, "hostile.lua")
assert(#parsedHostile == 1 and _G.portCanary == nil, "parsing runs nothing")

-- Malformed input fails closed, with the line to look at.
local ok, err = pcall(RestedXP.Parse, RestedXP, [==[
RXPGuides.RegisterGuide([[
#name Bad
    .goto Mulgore,1,1
]])
]==], "bad.lua")
assert(not ok and tostring(err):find("outside a step"), "a command before any step is refused")

ok, err = pcall(RestedXP.Parse, RestedXP, [==[
RXPGuides.RegisterGuide([[
#name Bad
step
    this is not a directive, a command, or display text
]])
]==], "bad.lua")
assert(not ok and tostring(err):find("unrecognised line"), "an unreadable line is refused, not skipped")

-- `*` and `+` lines are more of the step's text, not commands. An #internal
-- registration is the author's scratch list of points: its stray commands are
-- not a guide and are passed over rather than refused.
local notes = RestedXP:Parse([==[
RXPGuides.RegisterGuide([[
#name Notes
step
    >>Talk to Elatrell
    *Keep Walk on Air for later << Shaman
    +Drag the bag into the reagent slot
]])
RXPGuides.RegisterGuide([[
#name Scratch
#internal
    .goto 2521,41.07,22.33 -- spirit healer
]])
]==], "notes.lua")
assert(#notes[1].steps[1].display == 3, "* and + lines join the step's text")
assert(notes[1].steps[1].display[2].gate == "Shaman", "a gate on a * line is kept")
assert(notes[2].meta.flags.internal == true and #notes[2].steps == 0, "an internal list is read as no steps")

-- Every construct the mapping table names carries a status the audit knows.
local statuses = { mapped = true, todo = true, instruction = true, excluded = true, meta = true, ignored = true }
for kind, entries in pairs({ command = Mapping.commands, directive = Mapping.directives }) do
    for name, mapped in pairs(entries) do
        assert(statuses[mapped.status], kind .. " " .. name .. " has status '" .. tostring(mapped.status) .. "'")
        assert(type(mapped.becomes) == "string" and #mapped.becomes > 0,
            kind .. " " .. name .. " must say what it becomes")
        if mapped.status == "todo" or mapped.status == "excluded" then
            assert(type(mapped.note) == "string" and #mapped.note > 0,
                kind .. " " .. name .. " is not ported yet and must say why")
        end
    end
end

-- The coverage gate proper. The source addon is developer-side and may not be
-- installed, so this runs where it is and says so where it is not.
local sources = {
    "/mnt/d/BNet/World of Warcraft/_classic_beta_/Interface/AddOns/RXPGuides/Guides/Forever/Horde-1-12_Mulgore.lua",
    "/mnt/d/BNet/World of Warcraft/_classic_beta_/Interface/AddOns/RXPGuides/Guides/Forever/RestedXP-Skyborne.lua",
}
local checked = 0
for _, path in ipairs(sources) do
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        checked = checked + 1
        local parsed = RestedXP:ParseFile(path)
        assert(#parsed > 0, "no registration found in " .. path)
        local sourceCommands, sourceDirectives = RestedXP:Census(parsed)
        local unmapped = {}
        for name in pairs(sourceCommands) do
            if not Mapping:Lookup("command", name) then table.insert(unmapped, "." .. name) end
        end
        for name in pairs(sourceDirectives) do
            if not Mapping:Lookup("directive", name) then table.insert(unmapped, "#" .. name) end
        end
        table.sort(unmapped)
        assert(#unmapped == 0,
            path:match("([^/]+)$") .. " uses constructs with no entry in Tools/GuidePort/Mapping.lua: "
            .. table.concat(unmapped, ", "))
    end
end
if checked == 0 then
    print("  (guide port coverage gate skipped: no source addon installed)")
end

return true
