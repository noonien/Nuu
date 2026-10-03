-- Tools/SessionLog/replay_plan.lua
-- Plans a traced Profession Planner plan again outside the game, from the
-- saved variables: the plan row's inputs and live reads, its `replay` block
-- (known recipes, the other professions' recipes, bag counts, as the planner
-- window traces them on its `planner` channel) and the price book. Prints the route
-- the game planned beside the one planned here, and exits 1 when they
-- differ: a difference means the trace is missing something the plan read,
-- or the planner changed since.
--
-- Run from the NuuProfessions folder:
--   nix-shell -p lua5_1 --run "lua Tools/SessionLog/replay_plan.lua"
-- Options:
--   --trace N         the Nth latest trace session (default 1)
--   --row N           the Nth latest plan row in it (default 1, the last plan)
--   --profession P    only plans of this profession
--   --bags 2835=8,2770=7   set bag counts (for rows traced before `replay`)
--   --saved PATH      this SavedVariables file instead of the account's
--   --fixture PATH    also write the plan as a test fixture (Tests/Fixtures/Planner/)
--   --note TEXT       the fixture's note: what it pins down
--   --quiet           only the comparison
dofile("Tests/Support/Namespace.lua")
local ns = NewNamespace()

local args = {}
do
    local index = 1
    while arg[index] do
        local key = arg[index]
        if key == "--quiet" then
            args.quiet = true
            index = index + 1
        else
            args[key:gsub("^%-%-", "")] = arg[index + 1]
            index = index + 2
        end
    end
end

local function fail(text)
    io.stderr:write(text .. "\n")
    os.exit(2)
end

-- The saved file: the one asked for, else the first account's.
local saved = args.saved
if not saved then
    local pipe = io.popen('ls ../../../WTF/Account/*/SavedVariables/NuuProfessions.lua 2>/dev/null')
    saved = pipe and pipe:read("*l")
    if pipe then pipe:close() end
end
if not saved then fail("no NuuProfessions.lua under ../../../WTF/Account: pass --saved") end
local chunk, problem = loadfile(saved)
if not chunk then fail("cannot read " .. saved .. ": " .. tostring(problem)) end
chunk()
local db = rawget(_G, "NuuProfessionsDB")
if type(db) ~= "table" then fail(saved .. " has no NuuProfessionsDB") end
ns.db = db

Load(ns, "Config.lua")
Load(ns, "Data/ProfessionTiers.lua")
Load(ns, "Domain/Prices.lua")
Load(ns, "Domain/ProfessionPlanner.lua")
LoadProfessionData(ns)
local Planner = ns.modules.ProfessionPlanner
local Snapshot = dofile("Tools/SessionLog/plan_snapshot.lua")

-- The plan row: the Nth latest session, the Nth latest plan in it.
local sessions = db.trace and db.trace.sessions or {}
local session = sessions[#sessions - (tonumber(args.trace) or 1) + 1]
if not session then fail("no trace session " .. tostring(args.trace or 1) .. " (" .. #sessions .. " kept)") end
local function professionOf(d)
    if d.profession then return d.profession end
    local signature = d.route and d.route.signature or ""
    return signature:match("profession=([^,}]+)")
end
local rows = {}
for _, record in ipairs(session.channels and session.channels.planner or {}) do
    local d = record.d
    if type(d) == "table" and d.event == "plan" and d.data and d.route
        and (not args.profession or professionOf(d) == args.profession) then
        table.insert(rows, d)
    end
end
local d = rows[#rows - (tonumber(args.row) or 1) + 1]
if not d then fail("no plan row " .. tostring(args.row or 1) .. " in that session (" .. #rows .. " found)") end
local profession = professionOf(d)
local signature = d.route.signature or ""

-- The snapshot: the replay block's known recipes, other professions'
-- recipes and bag counts, else read back out of the route's signature.
local replay = d.replay or {}
local live = d.live or {}
local snapshot = { profession = profession, skill = live.skill, maxSkill = live.maxSkill, level = live.level,
    fullScope = d.fullScope or nil, inputs = d.inputs, book = db.professions, known = {}, bags = {} }
if replay.known then
    for _, spell in pairs(replay.known) do table.insert(snapshot.known, spell) end
else
    local list = signature:match("known=(%b{})")
    for spell in (list or ""):gmatch("(%d+)=true") do table.insert(snapshot.known, tonumber(spell)) end
end
table.sort(snapshot.known)
snapshot.helpers = replay.helpers
if not snapshot.helpers then
    snapshot.helpers = {}
    local block = signature:match("helpers=(%b{})")
    for name, list in (block or ""):gmatch("([%a ]+)=(%b{})") do
        snapshot.helpers[name] = {}
        for spell in list:gmatch("=(%d+)") do table.insert(snapshot.helpers[name], tonumber(spell)) end
    end
end
local counts = {}
for _, row in pairs(replay.bags or {}) do counts[row[1]] = row[2] end
for item, count in (args.bags or ""):gmatch("(%d+)=(%d+)") do counts[tonumber(item)] = tonumber(count) end
for item, count in pairs(counts) do table.insert(snapshot.bags, { item, count }) end
table.sort(snapshot.bags, function(a, b) return a[1] < b[1] end)
if not d.replay and not args.bags then
    io.stderr:write("this row was traced before bag counts were: every bag reads 0 (use --bags)\n")
end

local input, why = Snapshot.Input(ns, snapshot)
if not input then fail(why) end
local route = Planner:Plan(input)

local traced, planned = Snapshot.Describe(d.route.runs), Snapshot.Describe(route.runs)
if not args.quiet then
    print(string.format("%s, skill %s, target %s (%s), saved %s", profession, tostring(live.skill),
        tostring(d.route.target), tostring(d.route.ceiling and d.route.ceiling.text or "-"), saved))
    local shown = {}
    for _, row in ipairs(snapshot.bags) do table.insert(shown, row[1] .. "=" .. row[2]) end
    print("bags: " .. (#shown > 0 and table.concat(shown, " ") or "none"))
end
print("game:   " .. traced)
print("replay: " .. planned .. string.format("  (target %s, %s)", route.target, route.ceiling and route.ceiling.text or "-"))
-- A fixture for Tests/PlannerFixtureTests.lua: the snapshot, the saved book
-- with it, and the route the game planned as what it should plan.
if args.fixture then
    snapshot.expect = traced
    snapshot.note = args.note
    local out = assert(io.open(args.fixture, "w"))
    out:write("-- " .. args.fixture .. "\n-- Written by Tools/SessionLog/replay_plan.lua from a traced plan; `expect` is what the\n"
        .. "-- game planned, or what it should have (edit it, and say why in `note`).\nreturn "
        .. Snapshot.Serialize(snapshot) .. "\n")
    out:close()
    print("wrote " .. args.fixture)
end
if traced ~= planned then
    print("DIFFERENT")
    os.exit(1)
end
print("same")
