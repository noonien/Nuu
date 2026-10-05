_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/PlaceEditing.lua")
local Steps, Schema = ns.modules.Steps, ns.modules.Schema

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local base = {
    kind = "guide", schema = 1, id = "test:places", updated = 1790121600,
    title = "Places", category = "test",
    data = {
        map = 1412,
        places = {
            { id = "cave", name = "The cave", width = 15, points = {
                { id = "mouth", at = { 4000, 2000 }, kind = "entrance", label = "the mouth" },
                { id = "fork", at = { 4100, 2100 }, label = "the fork" },
                { id = "den", at = { 4200, 2200 } },
                { id = "hole", at = { 4200, 2400 }, kind = "exit", label = "the hole" },
                { id = "low", at = { 4100, 2300, map = 1413 } },
            }, links = {
                { from = "mouth", to = "fork" }, { from = "fork", to = "den" }, { from = "den", to = "hole" },
                { from = "fork", to = "low" }, { from = "low", to = "den", oneway = true },
            } },
        },
        sections = {
            { title = "Cave", steps = {
                { type = "travel", to = "the den", stand = "cave.den" },
                { type = "travel", to = "the fork", stand = "cave.2" },
                { type = "kill", kill = { 2952 }, count = 3, at = { { 4210, 2220 } }, near = "cave.den" },
            } },
        },
    },
}

local function expand(guide)
    local ok, result = pcall(Steps.Expand, Steps, guide)
    if not ok then return nil, { tostring(result) } end
    local valid, errors = Schema:Validate(result)
    if not valid then return nil, errors end
    return result
end

local guide, errors = expand(copy(base))
assert(guide, table.concat(errors or {}, "; "))
assert(guide.places[1].map == 1412, "a place takes the guide's map")
assert(base.data.places[1].map == nil, "the authored place is not changed")
local den = guide.nodes[1].location
assert(den.mapID == 1412 and math.abs(den.x - 0.42) < 1e-9 and den.point == "cave.den", "a step can stand on a named point")
assert(guide.nodes[2].location.point == "cave.2", "or on a point by its position")
assert(guide.nodes[3].location.near == "cave.den", "a spot can say which point it is near")

local function fails(mutate, pattern)
    local broken = copy(base)
    mutate(broken)
    local result, problems = expand(broken)
    assert(not result, "should fail: " .. pattern)
    local text = table.concat(problems, "; ")
    assert(text:match(pattern), "expected '" .. pattern .. "' in: " .. text)
end

fails(function(g) g.data.sections[1].steps[1].stand = "cave.nowhere" end, "no place point 'cave.nowhere'")
fails(function(g) g.data.sections[1].steps[3].near = "cellar.den" end, "no place point 'cellar.den'")
fails(function(g) g.data.places[1].points[1].kind = nil end, "needs at least one entrance")
fails(function(g) table.insert(g.data.places[1].points, { id = "far", at = { 5000, 5000 } }) end, "cannot be reached from an entrance")
fails(function(g) g.data.places[1].links = { { from = "mouth", to = "fork" }, { from = "fork", to = "den", oneway = true },
    { from = "fork", to = "hole" }, { from = "fork", to = "low" } } end,
    "has no way to an entrance or exit")
fails(function(g) table.insert(g.data.places[1].links, { from = "fork", to = "attic" }) end, "names a point the place does not have")
fails(function(g) table.insert(g.data.places[1].links, { from = "fork", to = "fork" }) end, "joins a point to itself")
fails(function(g) table.insert(g.data.places[1].links, { from = "den", to = "low" }) end, "one way and both ways")
fails(function(g) g.data.places[1].points[2].id = "den" end, "repeats another point's ID")
fails(function(g) g.data.places[1].points[2].id = "a.b" end, "without a dot")
fails(function(g) table.insert(g.data.places, copy(g.data.places[1])) end, "repeats the ID of another place")
fails(function(g) g.data.places[1].width = 90 end, "5 to 60 yards")
fails(function(g) g.data.places[1].points[1].kind = "window" end, "must be entrance or exit")

-- A plain duplicate merges and is reported for the editor, not refused.
local duplicate = copy(base)
table.insert(duplicate.data.places[1].links, { from = "fork", to = "mouth" })
local merged = expand(duplicate)
assert(merged, "a repeated connection is not an error")
local _, _, duplicates = Schema:PlaceConnections(merged.places[1])
assert(#duplicates == 1 and duplicates[1] == 6, "and is listed as a duplicate")
-- Fields the schema does not know are kept.
local kept = expand(copy(base))
kept.places[1].points[1].note = "kept"
assert(Schema:Validate(kept) and kept.places[1].points[1].note == "kept")

-- The packaged cave fixture validates and every step resolves.
ns.packagedGuides = {}
Load(ns, "Dev/Fixtures/CavePlaceFixture.lua")
local fixture = expand(ns.packagedGuides[1])
assert(fixture and fixture.nodes[1].location.point == "bristleback.den")

-- Editing: what the Places panel does to a guide in its runtime shape.
local Editing = ns.modules.PlaceEditing
local working = expand(copy(base))
local place = working.places[1]
-- Deleting a point drops its connections, renumbers the ones after it, and
-- a step standing on a later point by position follows it.
working.nodes[2].location.point = "cave.5"
assert(not Editing.DeletePoint(working, place, 3), "a point a step stands on is kept")
assert(Editing.DeletePoint(working, place, 4))
assert(#place.points == 4 and working.nodes[2].location.point == "cave.4", "the step follows its point")
for _, connection in ipairs(place.connections) do
    assert(Editing.PointIndex(place, connection[1]) and Editing.PointIndex(place, connection[2]),
        "every connection left names a point still there")
end
-- Connect replaces, never duplicates; one-way goes from the first to the second.
assert(Editing.Connect(place, 1, 2, true))
local joined = 0
for _, connection in ipairs(place.connections) do
    local a, b = Editing.PointIndex(place, connection[1]), Editing.PointIndex(place, connection[2])
    if (a == 1 and b == 2) or (a == 2 and b == 1) then joined = joined + 1; assert(connection[3] == true and a == 1) end
end
assert(joined == 1, "two points are joined once")
assert(Editing.Disconnect(place, 2, 1) and not Editing.Disconnect(place, 2, 1))
assert(not Editing.Connect(place, 2, 2), "a point is not joined to itself")
-- Adding a point connects it to the selected one; one on another map says so.
local added = Editing.AddPoint(place, 1413, 41.234, 22.5, 2)
assert(place.points[added].at[1] == 41.23 and place.points[added].map == 1413)
local out = Editing.Neighbours(place, 2)
local found = false
for _, index in ipairs(out) do if index == added then found = true end end
assert(found, "the new point hangs off the selected one")
-- Renaming a place renames the steps' references; a clash is refused.
assert(Editing.RenamePlace(working, place, "den2"))
assert(working.nodes[1].location.point == "den2.den" and working.nodes[3].location.near == "den2.den")
assert(not Editing.RenamePlace(working, place, "a.b"))
local second = Editing.AddPlace(working, 1412)
assert(second.place == "place2" and not Editing.RenamePlace(working, second, "den2"))
assert(Editing.DeletePlace(working, "place2") and not Editing.DeletePlace(working, "den2"), "a place a step uses is kept")
assert(Editing.CycleKind(place.points[2]) == "entrance" and Editing.CycleKind(place.points[2]) == "exit"
    and Editing.CycleKind(place.points[2]) == nil)
-- Recording: a point every 15 yards, and one at a turn.
local state = {}
assert(Editing.ShouldSample(state, 0, 0)); Editing.Sampled(state, 0, 0)
assert(not Editing.ShouldSample(state, 10, 0))
assert(Editing.ShouldSample(state, 15, 0)); Editing.Sampled(state, 15, 0)
assert(not Editing.ShouldSample(state, 21, 1), "a straight line needs no point until 15 yards")
assert(Editing.ShouldSample(state, 16, 8), "a sharp turn does")

-- Walk recording: yards in, a place out. The map is 2000 yards square, so a
-- yard is 0.05 map percent.
local function walker(indoorsOnly)
    local cave = { place = "walk", name = "Walked cave", map = 1412, points = {}, connections = {} }
    return cave, Editing.StartWalk(cave, {}, { indoorsOnly = indoorsOnly })
end
local function step(cave, state, x, y, indoors, falling)
    return Editing.Walk(cave, state, { map = 1412, x = 50 + x * 0.05, y = 50 + y * 0.05, wx = x, wy = y,
        indoors = indoors, falling = falling })
end
local function joinedOnce(cave, a, b, oneWay)
    local count = 0
    for _, c in ipairs(cave.connections) do
        if (c[1] == a and c[2] == b) or (c[1] == b and c[2] == a) then
            count = count + 1
            if oneWay ~= nil then assert((c[3] == true) == oneWay and (not oneWay or c[1] == a), "direction of " .. a .. "-" .. b) end
        end
    end
    return count == 1
end
local cave, walk = walker(true)
assert(step(cave, walk, 0, -20, false) == nil and #cave.points == 0, "nothing is recorded outdoors")
assert(step(cave, walk, 0, 0, true) == "point" and cave.points[1].kind == "entrance", "walking in marks the entrance")
step(cave, walk, 0, 5, true); step(cave, walk, 0, 10, true)
assert(#cave.points == 1, "no point before 15 yards")
assert(step(cave, walk, 0, 15, true) == "point" and joinedOnce(cave, 1, 2))
step(cave, walk, 0, 30, true)
assert(#cave.points == 3 and joinedOnce(cave, 2, 3))
assert(step(cave, walk, 0.5, 22, true) == nil, "walking back down a passage adds nothing")
assert(step(cave, walk, 0, 16, true) == "join" and #cave.points == 3 and #cave.connections == 2, "and reuses the point")
step(cave, walk, 5, 15, true); step(cave, walk, 10, 15, true)
assert(step(cave, walk, 15, 15, true) == "point" and joinedOnce(cave, 2, 4), "a side passage branches off")
step(cave, walk, 15, 30, true)
assert(joinedOnce(cave, 4, 5))
assert(step(cave, walk, 3, 30, true) == "join" and joinedOnce(cave, 5, 3), "coming round closes the loop")
assert(step(cave, walk, 0, 38, true, true) == nil, "nothing mid-fall")
assert(step(cave, walk, 0, 45, true) == "point" and joinedOnce(cave, 3, 6, true), "a drop is one way")
assert(step(cave, walk, 0, 52, false) == "point" and cave.points[7].kind == "entrance", "walking out marks a way out")
step(cave, walk, 20, 0, false); step(cave, walk, 40, 0, false)
assert(#cave.points == 7, "nothing is recorded outside")
assert(step(cave, walk, 20, 10, true) == "point" and cave.points[8].kind == "entrance", "another mouth")
assert(not joinedOnce(cave, 7, 8), "two mouths are never joined through the outside")
assert(Editing.UndoWalk(guide, cave, walk) and #cave.points == 7, "undo takes the last point and its doorway together")
walk.last, walk.lastPos = 6, walk.positions[6]
walk.level = 2
assert(step(cave, walk, 0.5, 29.5, true) == "point", "another level does not reuse the point below it")
assert(joinedOnce(cave, 6, 8), "but the walk still joins up")
walk.level = 1
local problems = {}
Schema:ValidatePlaces({ places = { cave }, nodes = {} }, problems)
assert(#problems == 0, table.concat(problems, "; "))

-- Without any word from the client about indoors, the first point is the way in.
local open, openWalk = walker(true)
step(open, openWalk, 0, 0, nil)
assert(open.points[1].kind == "entrance")

-- Simplify drops points on a straight line, never making a passage over 40 yards.
local line, lineWalk = walker(false)
for y = 0, 45, 15 do step(line, lineWalk, 0, y, nil) end
assert(#line.points == 4)
assert(Editing.Simplify({ places = { line }, nodes = {} }, line, lineWalk) == 1 and #line.points == 3)
assert(joinedOnce(line, 1, 2) and joinedOnce(line, 2, 3) and #line.connections == 2, "the point that stays keeps every passage under 40 yards")

-- The raw trail: what the recorder writes, processed into a place afterwards.
assert(Editing.MarkID("the Chamber of Bones") == "chamber_of_bones" and Editing.MarkID("  ") == nil)
local function trailSample(t, x, y, flags)
    local sample = { t = t, map = 1412, at = { 50 + x * 0.05, 50 + y * 0.05 }, w = { x, y } }
    for key, value in pairs(flags or {}) do sample[key] = value end
    return sample
end
local trail = { map = 1412, samples = {
    trailSample(0, 0, -20, { indoors = false, zone = "Outside" }),
    trailSample(1, 0, 0, { indoors = true, zone = "Palemane Rock" }),
    trailSample(2, 0, 8, { indoors = true }),
    trailSample(3, 0, 15, { indoors = true }),
    trailSample(4, 0, 22, { indoors = true }),
    trailSample(5, 0, 30, { indoors = true }),
    trailSample(6, 0, 36, { indoors = true, falling = true }),
    trailSample(7, 0, 44, { indoors = true }),
    trailSample(8, 0, 30.5, { indoors = true, level = 2 }),
    trailSample(9, 0, 52, { indoors = false }),
}, marks = { { sample = 4, label = "the pool" } } }
local processed, stats = Editing.Process(trail, { indoorsOnly = true, place = "palemane" })
assert(processed.name == "Palemane Rock", "the place is named after the subzone it was walked in")
assert(processed.points[1].kind == "entrance" and processed.points[#processed.points].kind == "entrance")
local pool
for index, point in ipairs(processed.points) do if point.id == "pool" then pool = index end end
assert(pool and processed.points[pool].label == "the pool", "a mark always becomes a named point")
local dropped = false
for _, c in ipairs(processed.connections) do if c[3] == true then dropped = true end end
assert(dropped, "the fall made a one-way drop")
problems = {}
Schema:ValidatePlaces({ places = { processed }, nodes = {} }, problems)
assert(#problems == 0, table.concat(problems, "; "))
-- The same trail, other settings: nothing outdoors-only, points further apart.
local loose = Editing.Process(trail, { indoorsOnly = false, sampleYards = 30 })
assert(#loose.points ~= #processed.points, "a trail can be processed again with other settings")
assert(trail.samples[2].at[1] == 50, "processing does not change the trail")

-- The Lua the recorder hands over reads back as the same place.
local text = Editing.Serialize(cave)
local chunk = assert(loadstring("return " .. text:gsub(",%s*$", "")))
local back = chunk()
assert(#back.points == #cave.points and #back.connections == #cave.connections and back.points[1].kind == "entrance")
assert(not text:find("[\128-\255]"), "ASCII only")

print("NuuRoad places tests passed")
