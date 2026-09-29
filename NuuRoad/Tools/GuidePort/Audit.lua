-- Coverage report for a port. Run from the addon root:
--
--   lua Tools/GuidePort/Audit.lua <source.lua> [<source.lua> ...]
--
-- Prints every construct the sources use, what it becomes, and what is still
-- missing. A port is complete for those sources when nothing is left `todo`.
package.path = "Tools/GuidePort/?.lua;" .. package.path
local RestedXP = dofile("Tools/GuidePort/RestedXP.lua")
local Mapping = dofile("Tools/GuidePort/Mapping.lua")

local paths = { ... }
if #paths == 0 then
    io.stderr:write("usage: lua Tools/GuidePort/Audit.lua <source.lua> [...]\n")
    os.exit(2)
end

local counts = { command = {}, directive = {} }
local steps, guides = 0, 0
for _, path in ipairs(paths) do
    local registrations = RestedXP:ParseFile(path)
    for _, registration in ipairs(registrations) do
        guides = guides + 1
        steps = steps + #registration.steps
    end
    local commands, directives = RestedXP:Census(registrations)
    for name, count in pairs(commands) do counts.command[name] = (counts.command[name] or 0) + count end
    for name, count in pairs(directives) do counts.directive[name] = (counts.directive[name] or 0) + count end
end

local order = { mapped = 1, todo = 2, instruction = 3, excluded = 4, meta = 5, ignored = 6, missing = 7 }
local rows = {}
for kind, found in pairs(counts) do
    for name, count in pairs(found) do
        local mapped = Mapping:Lookup(kind, name)
        table.insert(rows, {
            kind = kind, name = name, count = count,
            status = mapped and mapped.status or "missing",
            becomes = mapped and mapped.becomes or "NO ENTRY IN Mapping.lua",
            note = mapped and mapped.note,
        })
    end
end
table.sort(rows, function(a, b)
    if a.status ~= b.status then return order[a.status] < order[b.status] end
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
end)

local byStatus, todoUses, missing = {}, 0, 0
for _, row in ipairs(rows) do
    byStatus[row.status] = (byStatus[row.status] or 0) + 1
    if row.status == "todo" then todoUses = todoUses + row.count end
    if row.status == "missing" then missing = missing + 1 end
end

print(("NuuRoad guide port coverage - %d guide(s), %d source steps"):format(guides, steps))
print(("mapping table version %d"):format(Mapping.version))
print()
local shown
for _, row in ipairs(rows) do
    if row.status ~= shown then
        shown = row.status
        print(("-- %s"):format(shown:upper()))
    end
    print(("  %-5s %-18s %4d  %s%s"):format(
        row.kind == "command" and "." or "#", row.name, row.count, row.becomes,
        row.note and ("  (" .. row.note .. ")") or ""))
end
print()
local parts = {}
for _, status in ipairs({ "mapped", "todo", "instruction", "excluded", "meta", "missing" }) do
    if byStatus[status] then table.insert(parts, ("%s %d"):format(status, byStatus[status])) end
end
print("constructs: " .. table.concat(parts, ", "))
print(("still to build: %d construct(s) covering %d source step commands"):format(byStatus.todo or 0, todoUses))
if missing > 0 then
    print(("%d construct(s) have no entry in Mapping.lua"):format(missing))
    os.exit(1)
end
