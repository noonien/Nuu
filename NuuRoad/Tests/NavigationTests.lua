_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Domain/Navigation.lua")
local Navigation = ns.modules.Navigation

local function near(a, b) return math.abs(Navigation.ShortestAngle(a, b)) < 1e-6 end
local pi = math.pi

-- Facing north, target due east: the up-pointing arrow must turn clockwise
-- (negative rotation in WoW's counter-clockwise convention).
assert(near(Navigation.RelativeAngle(1, 0, 0), -pi / 2), "east target while facing north points right")
-- Facing north, target due west: counter-clockwise.
assert(near(Navigation.RelativeAngle(-1, 0, 0), pi / 2), "west target while facing north points left")
-- Facing east (3pi/2 counter-clockwise from north), target due east: straight ahead.
assert(near(Navigation.RelativeAngle(1, 0, 3 * pi / 2), 0), "target ahead gives no rotation")
-- Facing west (pi/2), target due east: directly behind.
assert(near(Navigation.RelativeAngle(1, 0, pi / 2), pi), "target behind gives a half turn")
-- Facing north, target due north: no rotation.
assert(near(Navigation.RelativeAngle(0, 1, 0), 0), "target north while facing north")

assert(near(Navigation.ShortestAngle(0, 2 * pi - 0.1), -0.1), "shortest angle wraps")

local east, north, inYards = Navigation.WorldDelta(0.1, 0.2, 1000, 500)
assert(east == 100 and north == 100 and inYards, "world delta scales by map size")
east, north, inYards = Navigation.WorldDelta(0.1, 0.2, nil, nil)
assert(east == 0.1 and math.abs(north - 0.132) < 1e-9 and not inYards, "fallback applies the aspect correction")


-- World axes: X grows north, Y grows west.
east, north = Navigation.CrossMapDelta(100, 200, 150, 120)
assert(east == 80 and north == 50, "target north-east in world coordinates")
east, north = Navigation.CrossMapDelta(0, 0, -10, 30)
assert(east == -30 and north == -10, "target south-west in world coordinates")

-- Arrival is seven yards once the map size is known: a 5% radius on a
-- zone-sized map would otherwise claim arrival hundreds of yards out.
assert(Navigation.ArrivalRadius(0.05, 6690, 4460) == 7, "a wide radius clamps to seven yards")
assert(math.abs(Navigation.ArrivalRadius(0.01, 400, 260) - 4) < 1e-9, "a tighter radius on a small map is kept")
assert(Navigation.ArrivalRadius(0.02, nil, nil) == 0.02, "without a map size the normalized radius is kept")
assert(Navigation.ArrivalRadius(nil, 1000, 700) == nil, "no radius stays no radius")

-- The sprite sheet covers 0..180 degrees in 150 frames; the rest of the turn
-- is those frames mirrored.
local frame, mirrored = Navigation.SpriteFrame(0)
assert(frame == 0 and not mirrored, "dead ahead is the first frame")
frame, mirrored = Navigation.SpriteFrame(pi)
assert(frame == 149 and not mirrored, "a half turn is the last frame")
frame, mirrored = Navigation.SpriteFrame(pi / 2)
assert(frame == 75 and not mirrored, "a quarter turn lands mid sheet")
local left, right = Navigation.SpriteFrame(-pi / 2)
assert(left == 75 and right, "the opposite quarter turn mirrors the same frame")
frame, mirrored = Navigation.SpriteFrame(2 * pi)
assert(frame == 0 and not mirrored, "a full turn wraps to the first frame")
frame, mirrored = Navigation.SpriteFrame(4 * pi + pi / 2)
assert(frame == 75 and not mirrored, "angles beyond a full turn wrap")
for step = 0, 720 do
    local index = Navigation.SpriteFrame(math.rad(step))
    assert(index >= 0 and index <= 149, "every angle maps into the sheet")
end

-- Mirrored frames come back with the horizontal coordinates swapped, over the
-- same cell as the unmirrored frame.
local aLeft, aRight, aTop, aBottom = Navigation.SpriteCoords(pi / 2)
local bLeft, bRight, bTop, bBottom = Navigation.SpriteCoords(-pi / 2)
assert(aLeft == bRight and aRight == bLeft, "the mirrored frame flips left and right")
assert(aTop == bTop and aBottom == bBottom, "the mirrored frame keeps its row")
assert(aRight - aLeft == 102 / 1024, "a cell is one sprite wide")
assert(aBottom - aTop == 68 / 1024, "a cell is one sprite tall")
local _, _, lastTop, lastBottom = Navigation.SpriteCoords(pi)
assert(lastBottom <= 1 and lastTop < lastBottom, "the last frame stays inside the sheet")

-- Heading colour: red behind, green ahead, with a flat snap dead ahead.
local function dominant(r, g, b)
    if r > g and r > b then return "red" end
    if g > r and g > b then return "green" end
    return "other"
end
assert(dominant(Navigation.ArrowColor(pi)) == "red", "a target behind is red")
assert(dominant(Navigation.ArrowColor(pi / 8)) == "green", "a target ahead is green")
local snapR, snapG, snapB = Navigation.ArrowColor(math.rad(1))
assert(snapG == 1.00 and snapR == 0.45 and snapB == 0.40, "dead ahead snaps to the bright colour")
local nearR = Navigation.ArrowColor(math.rad(10))
assert(nearR ~= snapR, "outside the snap the gradient applies")
-- Mirrored headings are the same distance off, so they colour the same.
local pr, pg, pb = Navigation.ArrowColor(pi / 3)
local nr, ng, nb = Navigation.ArrowColor(-pi / 3)
assert(pr == nr and pg == ng and pb == nb, "left and right of the heading colour alike")
local across = { Navigation.ArrowColor(pi / 2) }
assert(across[1] > 0.8 and across[2] > 0.5 and across[3] < 0.4, "a target across is amber")


-- Which face the window shows. A taxi outranks everything: the player is not
-- steering, so an arrow would be noise even with the destination in reach.
local function state(context) return Navigation.ArrowState(context) end
assert(state({ hasLocation = false }) == "none", "a step with no location shows no window")
assert(state({ hasLocation = true, hasBearing = true }) == "traveling", "a bearing shows the arrow")
assert(state({ hasLocation = true, hasBearing = true, arrived = true }) == "arrived", "inside the radius shows the pin")
assert(state({ hasLocation = true, hasBearing = false }) == "unreachable", "no bearing shows the barred ring")
assert(state({ hasLocation = true, hasBearing = true, onTaxi = true }) == "taxi", "a flight outranks travelling")
assert(state({ hasLocation = true, hasBearing = true, arrived = true, onTaxi = true }) == "taxi",
    "a flight outranks arrival, since arriving mid-flight is not arriving")
assert(state({ hasLocation = true, hasBearing = false, onTaxi = true }) == "taxi", "a flight outranks an unknown bearing")
assert(state({ hasLocation = false, onTaxi = true }) == "none", "no location still shows no window")

-- Special icons sit in one row of 64-pixel cells.
local sLeft, sRight, sTop, sBottom = Navigation.SpecialCoords("arrived")
assert(sLeft == 0 and sRight == 64 / 256, "the pin is the first cell")
assert(sTop == 0 and sBottom == 1, "an icon cell is the full height of its sheet")
local tLeft, tRight = Navigation.SpecialCoords("taxi")
assert(tLeft == 64 / 256 and tRight == 128 / 256, "the wing is the second cell")
local uLeft, uRight = Navigation.SpecialCoords("unreachable")
assert(uLeft == 128 / 256 and uRight == 192 / 256 and uRight <= 1, "the barred ring is the third cell")
assert(Navigation.SpecialCoords("traveling") == nil, "travelling has no icon; it has the arrow")
assert(Navigation.SpecialCoords("none") == nil, "no state, no icon")

-- The corpse arrow. A ghost's corpse outranks the tracked step; the step is
-- kept when the client cannot place the corpse, and comes back on resurrection.
local corpse = Navigation.CorpseNode(1413, 0.4, 0.6)
assert(corpse.location.mapID == 1413 and corpse.location.x == 0.4 and corpse.location.y == 0.6, "the corpse node carries the position")
assert(corpse.title == "Your corpse" and corpse.location.arrivalYards == 40, "the corpse node reads as the corpse and arrives at reclaim range")
assert(Navigation.CorpseNode(1413, nil, nil) == nil, "no position, no corpse node")

local corpses, ghost = {}, false
ns.modules.Client = {
    GetCurrentMapID = function() return 1413 end,
    IsPlayerGhost = function() return ghost end,
    GetCorpseMapPosition = function(_, mapID) local c = corpses[mapID]; if c then return c[1], c[2] end end,
}
local step = { id = "s1", location = { mapID = 1413, x = 0.1, y = 0.1 } }
local nav = setmetatable({ activeNode = step }, { __index = Navigation })
assert(nav:Target() == step, "alive, the arrow points at the step")
ghost = true
nav.ghost = true
assert(nav:Target() == step, "a ghost whose corpse cannot be placed keeps the step")
corpses[1413] = { 0.4, 0.6 }
local found = nav:Target()
assert(found and found.title == "Your corpse" and found.location.x == 0.4, "a ghost is pointed at the corpse on the current map")
assert(nav:Target() == found, "the corpse is looked up once and kept")
nav.corpse, corpses[1413] = nil, nil
corpses[1440] = { 0.2, 0.3 }
nav.deathMap = 1440
found = nav:Target()
assert(found and found.location.mapID == 1440, "a corpse not on this map is looked for on the map of death")
nav.Update, nav.UpdateWorldMapPOI, nav.UpdateMinimapPOI = function() end, function() end, function() end
ghost = false
nav:RefreshLifeState()
assert(nav.ghost == false and nav.corpse == nil and nav:Target() == step, "resurrection drops the corpse and returns to the step")
nav.activeNode = nil
ghost = true
nav:RefreshLifeState()
assert(nav:Target() and nav:Target().title == "Your corpse", "the corpse arrow needs no guide step")

-- A typed-in waypoint: X and Y as percentages, an optional map ID in front.
local wpMap, wpX, wpY = Navigation.ParseWaypoint("45.2 60.1")
assert(wpMap == nil and math.abs(wpX - 0.452) < 1e-9 and math.abs(wpY - 0.601) < 1e-9, "two numbers are X and Y")
wpMap, wpX, wpY = Navigation.ParseWaypoint("1440, 45, 60")
assert(wpMap == 1440 and wpX == 0.45 and wpY == 0.6, "a third number in front is the map")
assert(select(2, Navigation.ParseWaypoint("45")) == nil and select(4, Navigation.ParseWaypoint("45")), "one number is not a place")
assert(select(2, Navigation.ParseWaypoint("145 60")) == nil, "percentages stop at 100")
local waypoint = Navigation.WaypointNode(1413, 0.452, 0.601)
assert(waypoint.title == "Waypoint 45.2, 60.1" and waypoint.location.arrivalYards == 10 and not waypoint.index, "the waypoint reads as its coordinates and has no step number")

-- It outranks the step, but not the corpse, and clearing it returns to the step.
nav.activeNode, ghost = step, false
nav:RefreshLifeState()
assert(nav:SetWaypointFromText("30 40") == true, "a waypoint is set on the current map")
assert(nav:Target() == nav.waypoint and nav.waypoint.location.mapID == 1413, "the arrow points at the waypoint")
local ok, problem = nav:SetWaypointFromText("nowhere")
assert(ok == false and problem and nav.waypoint.location.x == 0.3, "a bad entry says why and keeps the old waypoint")
ghost = true
nav:RefreshLifeState()
assert(nav:Target().title == "Your corpse", "the corpse still comes first")
ghost = false
nav:RefreshLifeState()
nav:ClearWaypoint()
assert(nav.waypoint == nil and nav:Target() == step, "clearing the waypoint returns to the step")

-- Measure: the one answer the arrow window and the guide list both read.
local here = { map = 1413, x = 0.5, y = 0.5 }
_G.C_Map = { GetMapWorldSize = function() return 1000, 1000 end }
ns.modules.Client = {
    ResolveMapID = function(_, mapID) return mapID end,
    GetCurrentMapID = function() return here.map end,
    GetPlayerMapPosition = function(_, mapID) if mapID == here.map then return here.x, here.y end end,
    GetMapWorldSize = function() return 1000, 1000 end,
    GetMapName = function(_, mapID) return "Map " .. tostring(mapID) end,
    GetWorldPosition = function(_, mapID, x, y)
        -- One flat continent, so another map is still measurable.
        return 0, x * 1000 + (mapID == 1440 and 5000 or 0), y * 1000
    end,
}
local measure = setmetatable({}, { __index = Navigation })
assert(measure:Measure(nil) == nil, "nothing to measure")
assert(measure:Measure({ mapID = 1413, x = 0.5 }) == nil, "an incomplete location measures to nothing")
local label, distance, inYards, arrived = measure:Measure({ mapID = 1413, x = 0.6, y = 0.5 })
assert(inYards and math.abs(distance - 100) < 1e-6, tostring(distance))
assert(label == "100 yd E", label)
assert(arrived == false or arrived == nil, "no radius means arrival is never claimed")
label, _, _, arrived = measure:Measure({ mapID = 1413, x = 0.5, y = 0.5, arrivalRadiusNormalized = 0.02 })
assert(arrived == true and label == "Arrived (0 yd)", tostring(label))
-- A place on another map still measures, through world coordinates, and says
-- which map it is on rather than claiming arrival there.
local elsewhere
label, distance, _, arrived, _, _, elsewhere = measure:Measure({ mapID = 1440, x = 0.5, y = 0.5 })
assert(elsewhere == "Map 1440" and arrived == false and distance and distance > 1000, tostring(distance))
-- Standing on a spot authored on the neighbouring map is arriving there: the
-- client picks the city while the step names the zone around it.
label, distance, _, arrived = measure:Measure({ mapID = 1440, x = -4.5, y = 0.503, arrivalRadiusNormalized = 0.02 })
assert(arrived == true and math.abs(distance - 3) < 1e-6, "arrived across maps: " .. tostring(label))
-- Across maps the nearest of a step's points is measured too.
label, distance, _, arrived = measure:Measure({ mapID = 1440, x = 0.5, y = 0.5, spots = { { x = -4.49, y = 0.5 } }, arrivalYards = 12 })
assert(arrived == true and math.abs(distance - 10) < 1e-6, "the nearest point across maps: " .. tostring(distance))
-- A step with several points measures to whichever is nearest.
label, distance = measure:Measure({ mapID = 1413, x = 0.9, y = 0.5, spots = { { x = 0.55, y = 0.5 } } })
assert(math.abs(distance - 50) < 1e-6, "the nearest point is the one measured")
-- The tracker's column drops the bearing and the map name and keeps only the
-- number, since a goal line has no room for the arrow window's full reading.
assert(Navigation.ShortDistance(nil) == nil, "nothing measured, nothing shown")
assert(Navigation.ShortDistance(100, true, false) == "100 yd", Navigation.ShortDistance(100, true, false))
assert(Navigation.ShortDistance(3, true, true) == "here", "inside the arrival radius the number stops mattering")
assert(Navigation.ShortDistance(1450, true, false) == "1.4k yd", Navigation.ShortDistance(1450, true, false))
assert(Navigation.ShortDistance(0.123, false, false) == "12%", Navigation.ShortDistance(0.123, false, false))
assert(measure:ShortAway({ mapID = 1413, x = 0.6, y = 0.5 }) == "100 yd", "the short form goes through Measure")

-- No position at all: the label is nil, which the arrow reads as "no route".
ns.modules.Client.GetPlayerMapPosition = function() return nil end
assert(measure:Measure({ mapID = 1413, x = 0.6, y = 0.5 }) == nil, "without a position there is no measurement")

-- Map pins: the current step, its group, then the next steps with a place.
local function placed(index, extra)
    local node = { index = index, location = { mapID = 1413, x = index / 100, y = 0.5 } }
    for key, value in pairs(extra or {}) do node[key] = value end
    return node
end
local pinGuide = { nodes = {
    placed(1), placed(2), { index = 3 }, placed(4), placed(5), placed(6, { choices = { { label = "a" } } }), placed(7),
} }
local doneSteps, groupOf = { [4] = true }, {}
ns.modules.Progress = {
    PeekState = function() return {} end,
    QuestGroup = function(_, _, node) return groupOf[node.index] or { node } end,
    NextIndex = function(_, _, node) return node.index + 1 end,
}
ns.modules.GuideScan = {
    IsStepDone = function(_, _, node) return doneSteps[node.index] == true end,
    NodeIsMoot = function() return false end,
}
local function indexes(steps)
    local out = {}
    for _, step in ipairs(steps) do out[#out + 1] = step.node.index .. (step.current and "*" or "") end
    return table.concat(out, ",")
end
local pinNav = setmetatable({}, { __index = Navigation })
assert(indexes(pinNav:PinSteps(pinGuide, pinGuide.nodes[1], 2)) == "1*,2,5",
    "a step without a place and a step already done are passed over: " .. indexes(pinNav:PinSteps(pinGuide, pinGuide.nodes[1], 2)))
assert(indexes(pinNav:PinSteps(pinGuide, pinGuide.nodes[1], 0)) == "1*", "zero ahead keeps the current step only")
assert(indexes(pinNav:PinSteps(pinGuide, pinGuide.nodes[5], 5)) == "5*,6", "the walk stops at a choice")
groupOf[1] = { pinGuide.nodes[1], pinGuide.nodes[2] }
assert(indexes(pinNav:PinSteps(pinGuide, pinGuide.nodes[1], 1)) == "1*,2*,5", "group members are current, not counted ahead")
assert(indexes(pinNav:PinSteps(nil, pinGuide.nodes[1], 3)) == "1*", "without a guide only the current step is pinned")
assert(#pinNav:PinSteps(pinGuide, nil, 3) == 0, "no step, no pins")

local a, b, c = { index = 12 }, { index = 13 }, { index = 20 }
local clusters = Navigation.ClusterPins({
    { x = 0, y = 0, node = a, current = true, rank = 0 },
    { x = 30, y = 0, node = a, current = true, rank = 0 },
    { x = 5, y = 5, node = b, rank = 1 },
    { x = 100, y = 100, node = c, rank = 2 },
    { x = 101, y = 100, node = c, rank = 2 },
}, 16)
assert(#clusters == 3, "near points share a pin, far ones do not")
assert(Navigation.PinLabel(clusters[1]) == "12+" and clusters[1].current, "a shared pin reads the first step and a plus")
assert(clusters[1].currentNodes[a] and not clusters[1].currentNodes[b], "the tooltip knows which step is current")
assert(Navigation.PinLabel(clusters[2]) == "12", "a step's other point carries the same number")
assert(Navigation.PinLabel(clusters[3]) == "20", "two points of one step are not a crowd")
local corpseNode = { title = "Your corpse" }
clusters = Navigation.ClusterPins({
    { x = 0, y = 0, node = corpseNode, current = true, solo = true },
    { x = 1, y = 1, node = a, current = true },
}, 16)
assert(#clusters == 2 and Navigation.PinLabel(clusters[1]) == "", "the corpse keeps its own unnumbered pin")
assert(Navigation.PinAlpha(0, true) == 1 and Navigation.PinAlpha(3) < Navigation.PinAlpha(1), "later pins fade")
assert(Navigation.PinAlpha(50) == 0.5, "fading stops at half")

-- The minimap: points in range are drawn; with none in range the nearest one
-- (the arrow's target) sits on the rim, and the others are not drawn at all.
local edgeLocation = { mapID = 1413, x = 0.9, y = 0.5, spots = { { x = 0.2, y = 0.5 }, { x = 0.5, y = 0.1 } } }
local inRange = { [0.5] = true }
local function fakeOffset(x, y, clamp)
    if inRange[x] then return x, y, false end
    if clamp then return -x, -y, true end
end
local drawn = Navigation.MinimapPoints(edgeLocation, 0.5, 0.5, fakeOffset)
assert(#drawn == 1 and drawn[1].x == 0.5 and not drawn[1].onEdge, "a point in range is drawn and nothing goes to the rim")
inRange = {}
drawn = Navigation.MinimapPoints(edgeLocation, 0.25, 0.5, fakeOffset)
assert(#drawn == 1 and drawn[1].onEdge and drawn[1].x == -0.2, "with nothing in range only the nearest point sits on the rim")
assert(Navigation.ClusterPins({ { x = 1, y = 1, node = a, onEdge = true } }, 14)[1].onEdge, "a rim pin stays marked for its tooltip")

return true
