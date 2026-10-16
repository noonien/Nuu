local _, ns = ...

-- Editing a guide's places (caves, tunnels, one-door buildings) in their
-- authored shape: `{ place, name, width, map, points = { ... },
-- connections = { { a, b }, { a, b, true } } }`. A connection names a point by
-- its position or by its `id`; deleting a point renumbers the positions after
-- it, the way the editor's draft keeps what points at a step, and a step standing on a point
-- by position ("cave.4") follows it. Pure, so the tests run it.
local PlaceEditing = { sampleYards = 15, turnDegrees = 30, turnYards = 5 }

local function round(value) return math.floor(value * 100 + 0.5) / 100 end

function PlaceEditing.Find(guide, placeID)
    for index, place in ipairs(guide.places or {}) do
        if place.place == placeID then return place, index end
    end
    return nil
end

-- A new place with the first free "place1", "place2"... ID.
function PlaceEditing.AddPlace(guide, map)
    guide.places = guide.places or {}
    local number = #guide.places + 1
    while PlaceEditing.Find(guide, "place" .. number) do number = number + 1 end
    local place = { place = "place" .. number, name = "New place", map = map, points = {}, connections = {} }
    table.insert(guide.places, place)
    return place
end

-- Every step reference into a place, as the location field that holds it.
local function eachReference(guide, visit)
    for _, node in ipairs(guide.nodes or {}) do
        local location = node.location
        if type(location) == "table" then
            for _, key in ipairs({ "point", "near" }) do
                if type(location[key]) == "string" then visit(location, key) end
            end
        end
    end
end

function PlaceEditing.DeletePlace(guide, placeID)
    local _, index = PlaceEditing.Find(guide, placeID)
    if not index then return false, "No such place." end
    local used = false
    eachReference(guide, function(location, key)
        if location[key]:match("^([^%.]+)%.") == placeID then used = true end
    end)
    if used then return false, "A step still stands on one of its points; move that step first." end
    table.remove(guide.places, index)
    if #guide.places == 0 then guide.places = nil end
    return true
end

-- Renaming a place renames what the steps call it.
function PlaceEditing.RenamePlace(guide, place, newID)
    if type(newID) ~= "string" or newID == "" or newID:find("[%.%s]") then return false, "A place ID is one word without a dot." end
    if newID == place.place then return true end
    if PlaceEditing.Find(guide, newID) then return false, "Another place already has that ID." end
    local old = place.place
    eachReference(guide, function(location, key)
        local placeID, rest = location[key]:match("^([^%.]+)%.(.+)$")
        if placeID == old then location[key] = newID .. "." .. rest end
    end)
    place.place = newID
    return true
end

local function pointIndex(place, ref)
    if type(ref) == "number" then return place.points[ref] and ref or nil end
    for index, point in ipairs(place.points) do
        if point.id == ref then return index end
    end
    return nil
end
PlaceEditing.PointIndex = pointIndex

-- A point at a map position (percentages), connected to `from` when given.
-- Returns its index.
function PlaceEditing.AddPoint(place, map, x, y, from)
    local point = { at = { round(x), round(y) } }
    if map and map ~= place.map then point.map = map end
    table.insert(place.points, point)
    local index = #place.points
    if from and place.points[from] then table.insert(place.connections, { from, index }) end
    return index
end

-- Removes a point, its connections, and renumbers the positions after it.
-- Refuses when a step stands on it.
function PlaceEditing.DeletePoint(guide, place, index)
    local point = place.points[index]
    if not point then return false, "No such point." end
    local used = false
    eachReference(guide, function(location, key)
        local placeID, ref = location[key]:match("^([^%.]+)%.(.+)$")
        if placeID == place.place and (tonumber(ref) == index or (point.id and ref == point.id)) then used = true end
    end)
    if used then return false, "A step stands on this point; move that step first." end
    local kept = {}
    for _, connection in ipairs(place.connections) do
        local a, b = pointIndex(place, connection[1]), pointIndex(place, connection[2])
        if a ~= index and b ~= index then
            local function shift(ref)
                if type(ref) == "number" and ref > index then return ref - 1 end
                return ref
            end
            local copy = { shift(connection[1]), shift(connection[2]) }
            if connection[3] ~= nil then copy[3] = connection[3] end
            table.insert(kept, copy)
        end
    end
    place.connections = kept
    table.remove(place.points, index)
    eachReference(guide, function(location, key)
        local placeID, ref = location[key]:match("^([^%.]+)%.(.+)$")
        local number = tonumber(ref)
        if placeID == place.place and number and number > index then location[key] = placeID .. "." .. (number - 1) end
    end)
    return true
end

local function findConnection(place, a, b)
    for index, connection in ipairs(place.connections) do
        local ca, cb = pointIndex(place, connection[1]), pointIndex(place, connection[2])
        if (ca == a and cb == b) or (ca == b and cb == a) then return index, connection end
    end
    return nil
end

-- Joins two points both ways, or one way from `a` to `b`. Any connection
-- already between them is replaced, so the two are never joined twice.
function PlaceEditing.Connect(place, a, b, oneWay)
    if not place.points[a] or not place.points[b] or a == b then return false, "Pick two different points." end
    local index = findConnection(place, a, b)
    local connection = oneWay and { a, b, true } or { a, b }
    if index then place.connections[index] = connection else table.insert(place.connections, connection) end
    return true
end

function PlaceEditing.Disconnect(place, a, b)
    local index = findConnection(place, a, b)
    if not index then return false, "Those points are not joined." end
    table.remove(place.connections, index)
    return true
end

-- inside -> entrance -> exit -> inside.
function PlaceEditing.CycleKind(point)
    if point.kind == nil then point.kind = "entrance"
    elseif point.kind == "entrance" then point.kind = "exit"
    else point.kind = nil end
    return point.kind
end

-- The points each point is joined to, for the list ("> 3, 4" and "< 5" for
-- a one-way drop in).
function PlaceEditing.Neighbours(place, index)
    local out, into = {}, {}
    for _, connection in ipairs(place.connections) do
        local a, b = pointIndex(place, connection[1]), pointIndex(place, connection[2])
        if a == index and b then table.insert(out, b) end
        if b == index and a then
            if connection[3] == true then table.insert(into, a) else table.insert(out, a) end
        end
    end
    return out, into
end

-- The recorder behind the Places panel's Record button: given where the
-- player is now (world yards) and the recording so far, whether to drop a
-- point here. One every 15 yards, and one wherever the way turns by more than
-- 30 degrees, so a passage walked once becomes a line that follows it.
function PlaceEditing.ShouldSample(state, x, y)
    local last = state.last
    if not last then return true end
    local dx, dy = x - last.x, y - last.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance >= PlaceEditing.sampleYards then return true end
    if distance >= PlaceEditing.turnYards and state.heading then
        local heading = math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)
        local turn = math.abs((heading - state.heading + math.pi) % (2 * math.pi) - math.pi)
        if math.deg(turn) > PlaceEditing.turnDegrees then return true end
    end
    return false
end

function PlaceEditing.Sampled(state, x, y)
    local last = state.last
    if last then
        local dx, dy = x - last.x, y - last.y
        if dx ~= 0 or dy ~= 0 then state.heading = math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx) end
    end
    state.last = { x = x, y = y }
end

------------------------------------------------------------------------------
-- Walk recording: the author just walks the cave, every passage once, in and
-- out as they please, and the place builds itself.
--
--   * A point is dropped every 15 yards and at every turn, joined to the one
--     before (ShouldSample above).
--   * Coming back within 5 yards of a point already there reuses it and joins
--     to it, so walking back down a passage adds nothing, and walking round a
--     loop or into a side passage makes the junction on its own.
--   * Walking along a passage already recorded adds nothing until its far end.
--   * The client has no height, but it says when the player is indoors and
--     when they are falling. Stepping from outdoors in, or from indoors out,
--     marks the doorway an entrance; landing from a fall joins the ledge to the
--     landing one way only, and a fall that ends outdoors makes the landing an
--     exit. Nothing is recorded outdoors (unless the client never says indoors
--     at all, or `indoorsOnly` is off), and leaving by one mouth and walking
--     round to another never joins the two.
--   * Two levels over each other can still be joined by mistake when one is
--     walked within 5 yards of a point of the other. The author says which
--     level they are on (the recorder's LEVEL buttons, pressed at the top or
--     bottom of a ramp): points are only reused on the same level, while the
--     walk itself always joins up, so the ramp is the one way between levels.
--     Undo takes back the last point or join, and Simplify at the end drops
--     the points that only sit on a straight line between their neighbours.
--
-- `positions` holds each point's world position in yards (x, y), aligned
-- with `place.points`; the caller fills it for points recorded before, since
-- only the client can convert map percentages into yards.
PlaceEditing.snapYards, PlaceEditing.alongYards = 5, 4
PlaceEditing.simplifyYards, PlaceEditing.longestSegment = 2, 40

function PlaceEditing.StartWalk(place, positions, options)
    options = options or {}
    local state = { positions = positions or {}, added = {}, undo = {}, joined = 0, levels = {}, level = 1,
        indoorsOnly = options.indoorsOnly ~= false, last = options.from }
    for index = 1, #place.points do
        if state.positions[index] == nil then state.positions[index] = false end
        state.added[index], state.levels[index] = false, 1
    end
    if state.last and state.positions[state.last] then state.lastPos = state.positions[state.last] end
    return state
end

local function distance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function segmentDistance(p, a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    local length = dx * dx + dy * dy
    local t = length > 0 and ((p.x - a.x) * dx + (p.y - a.y) * dy) / length or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return distance(p, { x = a.x + t * dx, y = a.y + t * dy })
end

local function nearestPoint(state, pos, except)
    local best, bestDistance
    for index, known in ipairs(state.positions) do
        if known and index ~= except and (state.levels[index] or 1) == state.level then
            local d = distance(pos, known)
            if d <= PlaceEditing.snapYards and (not bestDistance or d < bestDistance) then best, bestDistance = index, d end
        end
    end
    return best
end

-- Whether the player is walking along a passage already recorded from the
-- point they last passed.
local function alongPassage(place, state, pos)
    if not state.last then return false end
    for _, connection in ipairs(place.connections) do
        local a, b = pointIndex(place, connection[1]), pointIndex(place, connection[2])
        local other = (a == state.last and b) or (b == state.last and connection[3] ~= true and a) or nil
        if other and state.positions[state.last] and state.positions[other]
            and segmentDistance(pos, state.positions[state.last], state.positions[other]) <= PlaceEditing.alongYards then
            return true
        end
    end
    return false
end

local function join(place, state, from, to, oneWay)
    if not from or from == to then return end
    local index = findConnection(place, from, to)
    if index then
        -- Already joined. A fall down an existing passage makes it one way
        -- only when it was recorded that way; walking it never downgrades it.
        return
    end
    table.insert(place.connections, oneWay and { from, to, true } or { from, to })
    table.insert(state.undo, { what = "join", a = from, b = to, last = state.last, step = state.step })
    state.joined = state.joined + 1
end

local function setKind(place, state, index, kind)
    local point = place.points[index]
    if not point or point.kind == kind or (point.kind == "entrance" and kind == "exit") then return end
    table.insert(state.undo, { what = "kind", index = index, before = point.kind, last = state.last, step = state.step })
    point.kind = kind
end

-- One reading of where the player is: `sample = { map, x, y }` in map
-- percentages, `wx, wy` in world yards, `indoors` and `falling` as the client
-- reports them (nil when it cannot say). Returns "point", "join", or nil.
function PlaceEditing.Walk(place, state, sample)
    if type(sample.wx) ~= "number" or type(sample.wy) ~= "number" then return nil end
    local pos = { x = sample.wx, y = sample.wy }
    state.step = (state.step or 0) + 1
    if sample.falling then state.fell = true; return nil end
    local indoors, wasIndoors = sample.indoors, state.wasIndoors
    if indoors ~= nil then state.wasIndoors = indoors end
    if indoors == true then state.seenIndoors = true end
    local fell = state.fell
    state.fell = false
    local stepped = state.indoorsOnly and indoors == false and wasIndoors == true
    local entering = state.indoorsOnly and indoors == true and wasIndoors == false
    if state.indoorsOnly and indoors == false and not stepped then
        -- Outside: nothing to record, and the next way in starts afresh.
        state.last, state.lastPos, state.heading = nil, nil, nil
        return nil
    end
    local result
    local near = nearestPoint(state, pos, state.last)
    if near then
        join(place, state, state.last, near, fell)
        state.last, state.lastPos, state.heading = near, state.positions[near], nil
        result = "join"
    elseif state.last and not (entering or stepped or fell or sample.force)
        and (alongPassage(place, state, pos) or not PlaceEditing.ShouldSample({ last = state.lastPos, heading = state.heading }, pos.x, pos.y)) then
        return nil
    elseif state.last and state.lastPos and distance(pos, state.lastPos) < (sample.force and 2 or 1) and not stepped then
        return nil
    else
        local index = PlaceEditing.AddPoint(place, sample.map, sample.x, sample.y)
        state.positions[index], state.added[index], state.levels[index] = pos, true, state.level
        table.insert(state.undo, { what = "point", index = index, last = state.last, step = state.step })
        -- Its join goes with it on undo, so it is not an entry of its own.
        if state.last then
            table.insert(place.connections, fell and { state.last, index, true } or { state.last, index })
        end
        local heading
        if state.lastPos then
            heading = math.atan2 and math.atan2(pos.y - state.lastPos.y, pos.x - state.lastPos.x)
                or math.atan(pos.y - state.lastPos.y, pos.x - state.lastPos.x)
        end
        state.last, state.lastPos, state.heading = index, pos, heading
        result = "point"
    end
    -- The doorways: in or out on foot is an entrance, out by a fall an exit.
    -- Without any word from the client, the first point is the way in.
    if stepped then
        setKind(place, state, state.last, fell and "exit" or "entrance")
        state.last, state.lastPos, state.heading = nil, nil, nil
    elseif entering then
        setKind(place, state, state.last, "entrance")
    elseif indoors == nil and not state.seenIndoors and #place.points == 1 and result == "point" then
        setKind(place, state, 1, "entrance")
    end
    return result
end

-- Takes back what the walk did last: a point with its join, a join onto a
-- point already there, and a doorway marked in the same moment, together.
-- Undo only ever removes the newest point, so no position shifts under it.
function PlaceEditing.UndoWalk(guide, place, state)
    local top = state.undo[#state.undo]
    if not top then return false end
    local entry
    while state.undo[#state.undo] and state.undo[#state.undo].step == top.step do
        entry = table.remove(state.undo)
        if entry.what == "point" then
            PlaceEditing.DeletePoint(guide, place, entry.index)
            table.remove(state.positions, entry.index)
            table.remove(state.added, entry.index)
            table.remove(state.levels, entry.index)
        elseif entry.what == "join" then
            PlaceEditing.Disconnect(place, entry.a, entry.b)
            state.joined = state.joined - 1
        elseif entry.what == "kind" then
            if place.points[entry.index] then place.points[entry.index].kind = entry.before end
        end
    end
    state.last = entry.last
    state.lastPos = entry.last and state.positions[entry.last] or nil
    state.heading = nil
    return true
end

-- Drops the points this walk made that only sit on a straight line between
-- their two neighbours: no kind, label or ID, joined both ways to exactly two
-- points that are not joined to each other, less than 2 yards off the line,
-- and never making a passage longer than 40 yards. Returns how many went.
function PlaceEditing.Simplify(guide, place, state)
    local removed = 0
    for index = #place.points, 1, -1 do
        local point = place.points[index]
        local here = state.positions[index]
        if state.added[index] and here and not point.kind and not point.label and not point.id then
            local ends, twoWay = {}, true
            for _, connection in ipairs(place.connections) do
                local a, b = pointIndex(place, connection[1]), pointIndex(place, connection[2])
                if a == index or b == index then
                    table.insert(ends, a == index and b or a)
                    if connection[3] == true then twoWay = false end
                end
            end
            local a, b = ends[1], ends[2]
            local pa, pb = a and state.positions[a], b and state.positions[b]
            if #ends == 2 and twoWay and a ~= b and pa and pb and not findConnection(place, a, b)
                and segmentDistance(here, pa, pb) <= PlaceEditing.simplifyYards
                and distance(pa, pb) <= PlaceEditing.longestSegment then
                if PlaceEditing.DeletePoint(guide, place, index) then
                    table.remove(state.positions, index)
                    table.remove(state.added, index)
                    table.remove(state.levels, index)
                    PlaceEditing.Connect(place, a > index and a - 1 or a, b > index and b - 1 or b, false)
                    removed = removed + 1
                end
            end
        end
    end
    state.undo = {}
    state.last, state.lastPos = nil, nil
    return removed
end

------------------------------------------------------------------------------
-- The raw trail. The place recorder does not write a place: it writes what
-- the client said, a sample at a time, and the place is worked out from that
-- - live while walking, and again afterwards with other settings if the
-- first result was not right (Tools/ProcessPlace.lua). A trail is
--
--   { name = "...", map = 1412, samples = { sample, ... }, marks = { mark, ... } }
--
-- where a sample is `{ t = seconds, map = 1412, at = { x, y } (map percent),
-- w = { x, y } (world yards), indoors = true, falling = true, swimming =
-- true, facing = radians, level = 2, zone = "Palemane Rock" }` (flags only
-- when set, `level` only above 1, `zone` only when it changed), and a mark is
-- `{ sample = n, label = "the chamber", id = "chamber", kind = "exit" }`: a
-- spot the author pressed MARK at, which always becomes a point.

-- "the Chamber of Bones" -> "chamber_of_bones": what a step calls a mark.
function PlaceEditing.MarkID(label)
    if type(label) ~= "string" then return nil end
    local id = label:lower():gsub("^%s*the%s+", ""):gsub("^%s*a%s+", ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if id == "" or tonumber(id) then return nil end
    return id
end

-- One trail sample as the walk recorder reads it.
function PlaceEditing.WalkSample(sample)
    local at, w = sample.at or {}, sample.w or {}
    return { map = sample.map, x = at[1], y = at[2], wx = w[1], wy = w[2],
        indoors = sample.indoors, falling = sample.falling == true }
end

-- Feeds one trail sample (and the marks made at it) to a walk.
function PlaceEditing.Replay(place, state, sample, marks)
    state.level = sample.level or 1
    local walkSample = PlaceEditing.WalkSample(sample)
    if marks and #marks > 0 then walkSample.force = true end
    local result = PlaceEditing.Walk(place, state, walkSample)
    local point = state.last and place.points[state.last]
    for _, mark in ipairs(marks or {}) do
        if point then
            if mark.label then point.label = mark.label end
            local id = mark.id or PlaceEditing.MarkID(mark.label)
            if id and not pointIndex(place, id) then point.id = id end
            if mark.kind then point.kind = mark.kind end
        end
    end
    return result
end

-- A whole trail into a place. `options.base` is a place to extend (it is
-- copied, not changed), `options.positions` its points' world yards, and
-- `options.from` the point the walk starts from; `options.indoorsOnly`,
-- `snapYards` and `sampleYards` tune the walk. The name is the author's, or
-- the subzone the trail spent most of its indoor time in.
function PlaceEditing.Process(trail, options)
    options = options or {}
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = copy(child) end
        return result
    end
    local place = options.base and copy(options.base)
        or { place = options.place or "recorded", map = trail.map, points = {}, connections = {} }
    local positions = copy(options.positions or {})
    local saved = { PlaceEditing.snapYards, PlaceEditing.sampleYards }
    PlaceEditing.snapYards = options.snapYards or PlaceEditing.snapYards
    PlaceEditing.sampleYards = options.sampleYards or PlaceEditing.sampleYards
    local state = PlaceEditing.StartWalk(place, positions, { indoorsOnly = options.indoorsOnly, from = options.from })
    local marksAt, zones, zone = {}, {}, nil
    for _, mark in ipairs(trail.marks or {}) do
        marksAt[mark.sample] = marksAt[mark.sample] or {}
        table.insert(marksAt[mark.sample], mark)
    end
    local ok, problem = pcall(function()
        for index, sample in ipairs(trail.samples or {}) do
            zone = sample.zone or zone
            if zone and sample.indoors then zones[zone] = (zones[zone] or 0) + 1 end
            PlaceEditing.Replay(place, state, sample, marksAt[index])
        end
    end)
    local removed = ok and PlaceEditing.Simplify(options.guide or { places = { place }, nodes = {} }, place, state) or 0
    PlaceEditing.snapYards, PlaceEditing.sampleYards = saved[1], saved[2]
    if not ok then error(problem) end
    if not place.name then
        local best
        for name, count in pairs(zones) do
            if not best or count > zones[best] or (count == zones[best] and name < best) then best = name end
        end
        place.name = trail.name or best or "Recorded place"
    end
    return place, { removed = removed, joined = state.joined, positions = state.positions }
end

-- A place as guide source, ready to paste into a guide's `places` list, in
-- the shape docs/guide-source.md shows: one point a line with its position
-- as a comment, so connections can be read against it.
local function quote(text) return string.format("%q", tostring(text)) end

function PlaceEditing.Serialize(place)
    local head = { "place = " .. quote(place.place) }
    if place.name then table.insert(head, "name = " .. quote(place.name)) end
    if place.width then table.insert(head, "width = " .. tostring(place.width)) end
    if place.map then table.insert(head, "map = " .. tostring(place.map)) end
    local lines = { "{ " .. table.concat(head, ", ") .. ",", "  points = {" }
    for index, point in ipairs(place.points) do
        local fields = { string.format("at = { %.2f, %.2f }", point.at[1], point.at[2]) }
        if point.map then table.insert(fields, "map = " .. tostring(point.map)) end
        if point.kind then table.insert(fields, "kind = " .. quote(point.kind)) end
        if point.label then table.insert(fields, "label = " .. quote(point.label)) end
        if point.id then table.insert(fields, "id = " .. quote(point.id)) end
        table.insert(lines, "      { " .. table.concat(fields, ", ") .. " }, -- " .. index)
    end
    table.insert(lines, "  },")
    local joins = {}
    for _, connection in ipairs(place.connections) do
        local parts = {}
        for position = 1, 2 do
            local ref = connection[position]
            parts[position] = type(ref) == "string" and quote(ref) or tostring(ref)
        end
        if connection[3] == true then parts[3] = "true" end
        table.insert(joins, "{ " .. table.concat(parts, ", ") .. " }")
    end
    -- Eight to a line keeps a big cave readable.
    table.insert(lines, "  connections = {")
    for first = 1, #joins, 8 do
        local last = math.min(#joins, first + 7)
        table.insert(lines, "      " .. table.concat(joins, ", ", first, last) .. ",")
    end
    table.insert(lines, "  },")
    table.insert(lines, "},")
    return table.concat(lines, "\n")
end

ns:RegisterModule("PlaceEditing", PlaceEditing)
