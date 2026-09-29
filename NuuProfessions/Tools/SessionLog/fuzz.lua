-- Tools/SessionLog/fuzz.lua
-- Plays random characters through the Profession Planner
-- (Tools/SessionLog/plan_fuzz.lua) and prints every broken invariant.
--
--   nix-shell -p lua5_1 --run "lua Tools/SessionLog/fuzz.lua --seeds 200"
-- Options:
--   --seeds N    how many seeds (default 50), from --from (default 1)
--   --seed S     play one seed and print it move by move
--   --moves N    moves a seed plays (default 24)
--   --max N      problems printed (default 40); the count is always given
--   --seed S --dump M [--fixture PATH]   the character at move M, its plan in full, and
--                as a planner fixture (Tests/Fixtures/Planner/) to pin it down
-- Run from the NuuProfessions folder.
dofile("Tests/Support/Namespace.lua")
local ns = NewNamespace()

local args = {}
do
    local index = 1
    while arg[index] do
        args[arg[index]:gsub("^%-%-", "")] = arg[index + 1]
        index = index + 2
    end
end

Load(ns, "Config.lua")
Load(ns, "Data/ProfessionTiers.lua")
Load(ns, "Domain/Prices.lua")
Load(ns, "Domain/ProfessionPlanner.lua")
LoadProfessionData(ns)
local Fuzz = dofile("Tools/SessionLog/plan_fuzz.lua")
local moves = tonumber(args.moves) or 24

-- The character as it stands at one move, as a fixture file, and its plan.
if args.seed and args.dump then
    local Snapshot = dofile("Tools/SessionLog/plan_snapshot.lua")
    local now, route = Fuzz.Play(ns, tonumber(args.seed), { moves = moves, dump = tonumber(args.dump) })
    if type(route) ~= "table" then print("the game ended before move " .. args.dump); os.exit(1) end
    now.expect = Snapshot.Describe(route.runs)
    if args.fixture then
        local out = assert(io.open(args.fixture, "w"))
        out:write("-- " .. args.fixture .. "\n-- From Tools/SessionLog/fuzz.lua --seed " .. args.seed .. " --dump " .. args.dump
            .. "; `expect` is what was planned (edit it to what should be).\nreturn " .. Snapshot.Serialize(now) .. "\n")
        out:close()
        print("wrote " .. args.fixture)
    end
    print(Snapshot.Serialize({ profession = now.profession, skill = now.skill, maxSkill = now.maxSkill, bags = now.bags,
        target = now.inputs.target, materials = now.inputs.options.materials, goals = now.inputs.goals,
        chosen = now.inputs.chosen }))
    print("plan: " .. now.expect .. " to " .. tostring(route.target) .. " (" .. tostring(route.ceiling and route.ceiling.text) .. ")")
    for _, run in ipairs(route.runs) do
        local parts = {}
        for key, value in pairs(run) do
            if type(value) ~= "table" and type(value) ~= "function" then table.insert(parts, key .. "=" .. tostring(value)) end
        end
        table.sort(parts)
        print("  run " .. table.concat(parts, " "))
    end
    for _, row in ipairs(route.shopping or {}) do
        print(string.format("  shop %s count %s have %s buy %s %s", row.itemID, row.count, row.have, row.buy, row.source))
    end
    for _, event in ipairs(route.events or {}) do
        print(string.format("  event %s at %s spell %s crafts %s count %s", event.kind, tostring(event.skill),
            tostring(event.spell), tostring(event.crafts), tostring(event.count)))
    end
    for _, warning in ipairs(route.warnings or {}) do print("  warn " .. warning.code .. ": " .. warning.text) end
    os.exit(0)
end

if args.seed then
    local problems, plans = Fuzz.Play(ns, tonumber(args.seed), { moves = moves, log = print })
    print(plans .. " plans")
    for _, problem in ipairs(problems) do print("PROBLEM " .. problem) end
    os.exit(#problems > 0 and 1 or 0)
end

local from, count = tonumber(args.from) or 1, tonumber(args.seeds) or 50
local shown, total, failing, plans = 0, 0, {}, 0
local started = os.clock()
for seed = from, from + count - 1 do
    local problems, made = Fuzz.Play(ns, seed, { moves = moves })
    plans = plans + made
    if #problems > 0 then table.insert(failing, seed) end
    for _, problem in ipairs(problems) do
        total = total + 1
        if shown < (tonumber(args.max) or 40) then
            print(problem)
            shown = shown + 1
        end
    end
end
print(string.format("%d seeds (%d-%d), %d plans, %.1fs: %d problem%s in %d seed%s%s", count, from, from + count - 1,
    plans, os.clock() - started, total, total == 1 and "" or "s", #failing, #failing == 1 and "" or "s",
    #failing > 0 and (": " .. table.concat(failing, " ", 1, math.min(#failing, 30))) or ""))
os.exit(total > 0 and 1 or 0)
