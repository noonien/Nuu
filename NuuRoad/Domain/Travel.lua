local _, ns = ...

-- The travel planner: the fastest sensible way from the player to a step's
-- place, as a list of legs (walk, fly, take a boat, hearth), each ending on
-- a waypoint; a straight walk is one leg to the step itself. Pure: everything the client knows arrives
-- in `context`, so the whole planner runs in the tests.
--
-- The world model is a few dozen points joined by straight lines
-- (`Data/Travel.lua` plus the guide's own `places`): the player, the target,
-- the flight masters the player knows, transport docks, teleport landings,
-- the doors of walled areas, and the points of guide places. The graph is
-- rebuilt on every call because it is that small, and searched with a plain
-- Dijkstra: a heap only earns its keep once a graph reaches thousands of
-- nodes, which ours never will.
--
-- Rules that make a planner feel calm rather than clever:
--   * roads are not straight: walked yards count 1.2 times, and so do flights
--     nobody has timed yet;
--   * every change of mode costs 15 s, so a route never trades the player's
--     attention for 20 seconds;
--   * a route that is not plain walking has to save a minute and a quarter of
--     the walk, and once one is shown it stays until another beats it by the
--     same margin;
--   * a teleport that costs something to use (the hearthstone's hour, which
--     guides plan around) is never part of the route shown by default: each
--     one that is ready and clearly faster is offered as an alternative for
--     the player to pick. One marked `free` (Teleport: Moonglade, a mage's
--     teleports) is an ordinary way to travel and may be the default route.
--     One on cooldown is not offered at all.
--
-- Walls: an area (a city, Thunder Bluff's mesa) or a guide place (a cave) can
-- only be walked into or out of through its doors. A straight walk is allowed
-- only when both ends are on the same side of every area, or one end is a
-- door of it; an `exit` door is only ever used outwards. Inside a guide
-- place, its connections are the only walks there are. Nothing else in the
-- planner knows about walls: Dijkstra picks the best door on its own.
--
-- Lifts: a door with a `bottom` is a lift. Its top is the door; its bottom
-- is a waypoint outside the area, even when the client puts it on the city's
-- map (the ground round Thunder Bluff's mesa is on Thunder Bluff's map), and
-- the ride between them is the only way from one to the other. Where the
-- player stands can be said outright: `context.below[area name]` puts them
-- outside a lifted area whatever map they are on.
local Travel = {
    runSpeed = 7, detour = 1.2,
    flightSpeed = 30, flightDetour = 1.2,
    legPenalty = 15, linkCost = 240, teleportCast = 10, readySeconds = 1,
    suggestSeconds = 60, suggestShare = 0.25,
    placeYards = 15, placeShare = 0.15,
    replanYards = 50, defaultWidth = 20, sameConnectionYards = 3,
}

-- Coordinates above 1 are percentages, the way guides are written.
local function normalize(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if x > 1 or y > 1 then return x / 100, y / 100 end
    return x, y
end
Travel.Normalize = normalize

-- "Crossroads, The Barrens" and "The Crossroads" are the same flight master.
function Travel.FlightKey(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower():gsub(",.*$", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^the%s+", "")
    return key
end

local function innKey(name) return Travel.FlightKey(name) end

-- The part of a flight master's name the tracker says: "Ratchet".
local function shortName(name)
    if type(name) ~= "string" then return "?" end
    return (name:gsub(",.*$", ""))
end

-- "2m10s", "45s", "1h05m".
function Travel.FormatSeconds(seconds)
    seconds = math.floor((tonumber(seconds) or 0) + 0.5)
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then
        local minutes, rest = math.floor(seconds / 60), seconds % 60
        return rest > 0 and string.format("%dm%02ds", minutes, rest) or (minutes .. "m")
    end
    return string.format("%dh%02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function yards(a, b)
    if not a.continent or a.continent ~= b.continent then return nil end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return math.sqrt(dx * dx + dy * dy)
end

-- Distance from p to the segment a-b, and where along it (0 at a, 1 at b).
local function segment(p, a, b)
    local dx, dy = b.wx - a.wx, b.wy - a.wy
    local length = dx * dx + dy * dy
    local t = length > 0 and ((p.wx - a.wx) * dx + (p.wy - a.wy) * dy) / length or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local x, y = a.wx + t * dx - p.wx, a.wy + t * dy - p.wy
    return math.sqrt(x * x + y * y), t
end

local function allowedFaction(row, faction)
    if not row.faction or row.faction == "Neutral" or not faction then return true end
    return row.faction == faction
end

local function allowedClass(row, class)
    if not row.class or not class then return true end
    return row.class == class
end

-- A guide's places in one shape: points normalized and placed on a map,
-- connections as point indexes. `ref` for a connection end or a step's
-- `place.point` is a position in the list or a point's `id`. Unresolvable
-- ends are dropped here; the schema reports them.
function Travel.ResolvePlaces(places, defaultMap)
    local resolved = {}
    for _, place in ipairs(type(places) == "table" and places or {}) do
        if type(place) == "table" and type(place.place) == "string" then
            local entry = { id = place.place, name = place.name or place.place,
                width = tonumber(place.width) or Travel.defaultWidth, points = {}, connections = {}, byId = {} }
            for index, point in ipairs(type(place.points) == "table" and place.points or {}) do
                local at = type(point) == "table" and point.at
                local x, y = normalize(type(at) == "table" and at[1], type(at) == "table" and at[2])
                local map = type(point) == "table" and (point.map or place.map or defaultMap)
                if x and map then
                    entry.points[index] = { index = index, map = map, x = x, y = y, kind = point.kind,
                        label = point.label, id = point.id }
                    if type(point.id) == "string" then entry.byId[point.id] = index end
                end
            end
            local function ref(value)
                if type(value) == "number" then return entry.points[value] and value or nil end
                if type(value) == "string" then return entry.byId[value] end
                return nil
            end
            for _, connection in ipairs(type(place.connections) == "table" and place.connections or {}) do
                if type(connection) == "table" then
                    local a, b = ref(connection[1]), ref(connection[2])
                    if a and b and a ~= b then
                        table.insert(entry.connections, { a = a, b = b, oneWay = connection[3] == true })
                    end
                end
            end
            entry.ref = ref
            table.insert(resolved, entry)
        end
    end
    return resolved
end

-- "windfury.chamber" -> the place and the point's index.
function Travel.FindPoint(places, reference)
    if type(reference) ~= "string" then return nil end
    local placeID, pointRef = reference:match("^([^%.]+)%.(.+)$")
    if not placeID then return nil end
    for _, place in ipairs(places) do
        if place.id == placeID then
            local index = place.ref(tonumber(pointRef) or pointRef)
            if index then return place, index end
        end
    end
    return nil
end

------------------------------------------------------------------------------
-- The graph

local function addNode(graph, context, node)
    node.id = #graph.nodes + 1
    node.areaIn, node.doorOf = {}, {}
    if context.world and node.map and node.x then
        local continent, wx, wy = context.world(node.map, node.x, node.y)
        if continent and type(wx) == "number" and type(wy) == "number" then
            node.continent, node.wx, node.wy = continent, wx, wy
        end
    end
    graph.nodes[node.id] = node
    graph.edges[node.id] = {}
    if node.key then graph.byKey[node.key] = node end
    return node
end

local function addEdge(graph, from, to, cost, mode, extra)
    local edge = extra or {}
    edge.from, edge.to, edge.cost, edge.mode = from, to, cost, mode
    table.insert(graph.edges[from.id], edge)
    return edge
end

local function areaCentre(graph, context, area, index)
    graph.centres = graph.centres or {}
    if graph.centres[index] == nil then
        local x, y = normalize(area.at and area.at[1], area.at and area.at[2])
        graph.centres[index] = false
        if x and context.world then
            local continent, wx, wy = context.world(area.map, x, y)
            if continent then graph.centres[index] = { continent = continent, wx = wx, wy = wy } end
        end
    end
    return graph.centres[index] or nil
end

local function insideArea(graph, context, node, area, index)
    if area.at and area.radius then
        local centre = areaCentre(graph, context, area, index)
        if not centre or not node.continent then return node.map == area.map end
        local distance = yards(node, centre)
        return distance ~= nil and distance <= area.radius
    end
    if node.map == area.map then return true end
    -- A point authored on the zone around a city is in it when the client
    -- says the city's map is what lies there. Never the player: the client
    -- already placed them on the map they stand on, and its city area on the
    -- zone reaches a little past the walls (just outside Orgrimmar's gate
    -- answers Orgrimmar).
    if context.mapAt and node.map and node.x and node.kind ~= "start" then
        if node.mapAt == nil then node.mapAt = context.mapAt(node.map, node.x, node.y) or false end
        return node.mapAt == area.map
    end
    return false
end

-- Which connection of which place a node stands on, or nil. A point just
-- past an entrance (the nearest spot on the connection is the doorway itself)
-- is outside. `only` keeps the search to connections touching one point: the
-- step said which part of the place it means.
local function locate(node, place, nodes, context, only)
    if not node.continent then return nil end
    local best, bestD, bestT
    local candidates = {}
    for index, connection in ipairs(place.connections) do
        local a, b = nodes[connection.a], nodes[connection.b]
        if a and b and a.continent == node.continent and b.continent == node.continent
            and (not only or connection.a == only or connection.b == only) then
            local distance, t = segment(node, a, b)
            local doorstep = (t <= 0 and a.pointKind) or (t >= 1 and b.pointKind)
            if (only or distance <= place.width) and not doorstep then
                table.insert(candidates, { index = index, connection = connection, d = distance, t = t })
                if not bestD or distance < bestD then best, bestD, bestT = index, distance, t end
            end
        end
    end
    if not best then return nil end
    -- Two levels over each other: when connections are about equally close,
    -- the one the player was last on, or one sharing a point with it, wins.
    local last = context.lastConnection
    if last and last.place == place.id and place.connections[last.index] then
        local previous = place.connections[last.index]
        local preferred
        for _, candidate in ipairs(candidates) do
            if candidate.d <= bestD + Travel.sameConnectionYards then
                local c = candidate.connection
                if candidate.index == last.index then preferred = candidate; break end
                if not preferred and (c.a == previous.a or c.a == previous.b or c.b == previous.a or c.b == previous.b) then
                    preferred = candidate
                end
            end
        end
        if preferred then return preferred.index, preferred.t, preferred.d end
    end
    return best, bestT, bestD
end

local function median(values)
    if type(values) ~= "table" or #values == 0 then return nil end
    local sorted = {}
    for index, value in ipairs(values) do sorted[index] = value end
    table.sort(sorted)
    local middle = math.floor((#sorted + 1) / 2)
    if #sorted % 2 == 1 then return sorted[middle] end
    return (sorted[middle] + sorted[middle + 1]) / 2
end

local function reachableSet(context, originKey)
    local list = context.reachable and context.reachable[originKey]
    if type(list) ~= "table" then return nil end
    local set = {}
    for _, name in ipairs(list) do set[Travel.FlightKey(name) or name] = true end
    return set
end

-- The walls. `u` walks straight to `v`: see the header for the rules.
local function walkAllowed(u, v, areas)
    if u.inside or v.inside then return false end
    if u.place and v.place and u.place == v.place then return false end
    if v.pointKind == "exit" then return false end
    for index in ipairs(areas) do
        local du, dv = u.doorOf[index], v.doorOf[index]
        -- A lift's top reaches outside only by the lift itself.
        if du and du.bottom and not dv and not v.areaIn[index] then return false end
        if dv and dv.bottom and not du and not u.areaIn[index] then return false end
        if du and dv then
            -- gate to gate: fine either way
        elseif du then
            if du.kind == "exit" and v.areaIn[index] then return false end
        elseif dv then
            if dv.kind == "exit" and not u.areaIn[index] then return false end
        elseif (u.areaIn[index] or false) ~= (v.areaIn[index] or false) then
            return false
        end
    end
    return true
end

function Travel:Graph(from, to, context)
    context = context or {}
    local data = context.data or ns.travel or {}
    local speed = context.speed or self.runSpeed
    local graph = { nodes = {}, edges = {}, byKey = {}, speed = speed }
    local start = addNode(graph, context, { key = "start", kind = "start", map = from.map, x = from.x, y = from.y })
    local goal = addNode(graph, context, { key = "goal", kind = "goal", map = to.map, x = to.x, y = to.y })
    graph.start, graph.goal = start, goal
    -- A step with several spots: each is a way to arrive, joined to the goal
    -- at no cost, so the search picks the one quickest to reach.
    for index, spot in ipairs(type(to.spots) == "table" and to.spots or {}) do
        local x, y = normalize(spot.x, spot.y)
        if x then
            local node = addNode(graph, context, { key = "spot:" .. index, kind = "spot", map = spot.map or to.map, x = x, y = y })
            addEdge(graph, node, goal, 0, "walk")
        end
    end
    if not start.continent or not goal.continent then
        -- Nothing can be measured; only the same map can still be walked.
        if from.map ~= to.map then return nil end
    end
    local options = context.options or {}

    if options.flights ~= false and context.knownFlight then
        for _, row in ipairs(data.flights or {}) do
            local x, y = normalize(row.at and row.at[1], row.at and row.at[2])
            if x and allowedFaction(row, context.faction) and context.knownFlight(row.name) then
                local key = Travel.FlightKey(row.name)
                if not graph.byKey["flight:" .. key] then
                    addNode(graph, context, { key = "flight:" .. key, kind = "flight", flightKey = key, row = row, map = row.map, x = x, y = y })
                end
            end
        end
    end
    if options.links ~= false then
        for index, row in ipairs(data.links or {}) do
            if allowedFaction(row, context.faction) and allowedClass(row, context.class) then
                local ends = {}
                for _, side in ipairs({ "from", "to" }) do
                    local spot = row[side]
                    local x, y = normalize(spot and spot.at and spot.at[1], spot and spot.at and spot.at[2])
                    if x then
                        ends[side] = addNode(graph, context, { key = "dock:" .. index .. ":" .. side, kind = "dock",
                            row = row, side = side, map = spot.map, x = x, y = y })
                    end
                end
                if ends.from and ends.to then
                    local cost = row.cost or ((row.wait or 0) + (row.ride or 0))
                    if cost <= 0 then cost = self.linkCost end
                    local mode = "link:" .. index
                    addEdge(graph, ends.from, ends.to, cost, mode, { row = row, side = "to" })
                    if row.both then addEdge(graph, ends.to, ends.from, cost, mode, { row = row, side = "from" }) end
                end
            end
        end
    end
    if options.teleports ~= false and context.teleport then
        for index, row in ipairs(data.teleports or {}) do
            -- Only a teleport that can be cast now: one on cooldown is not
            -- offered, never waited for.
            local remaining = allowedClass(row, context.class) and context.teleport(row) or nil
            if remaining and remaining <= self.readySeconds then
                local map, x, y, place
                if row.to == "bind" then
                    local bind = innKey(context.bind)
                    for _, inn in ipairs(data.inns or {}) do
                        if bind and innKey(inn.name) == bind then
                            map, place = inn.map, inn.name
                            x, y = normalize(inn.at[1], inn.at[2])
                        end
                    end
                elseif type(row.to) == "table" then
                    map = row.to.map
                    x, y = normalize(row.to.at and row.to.at[1], row.to.at and row.to.at[2])
                end
                if map and x then
                    local arrival = addNode(graph, context, { key = "arrive:" .. index, kind = "arrival", row = row,
                        map = map, x = x, y = y, placeName = place })
                    addEdge(graph, start, arrival, row.cast or self.teleportCast, "teleport:" .. index, { row = row, index = index })
                end
            end
        end
    end
    local areas = data.areas or {}
    for areaIndex, area in ipairs(areas) do
        for doorIndex, door in ipairs(area.doors or {}) do
            local x, y = normalize(door.at and door.at[1], door.at and door.at[2])
            if x then
                local node = addNode(graph, context, { key = "door:" .. areaIndex .. ":" .. doorIndex, kind = "door",
                    area = area, door = door, map = door.map or area.map, x = x, y = y })
                node.doorOf[areaIndex] = door
                local bottom = type(door.bottom) == "table" and door.bottom
                local bx, by = normalize(bottom and bottom.at and bottom.at[1], bottom and bottom.at and bottom.at[2])
                if bx then
                    local foot = addNode(graph, context, { key = "lift:" .. areaIndex .. ":" .. doorIndex, kind = "lift",
                        area = area, door = door, top = node, map = bottom.map or door.map or area.map, x = bx, y = by })
                    foot.outsideOf = { [areaIndex] = true }
                    node.foot = foot
                    local ride = (door.wait or 0) + (door.ride or 0)
                    addEdge(graph, foot, node, ride, "walk", { lift = true })
                    addEdge(graph, node, foot, ride, "walk", { lift = true })
                end
            end
        end
    end
    local below = type(context.below) == "table" and context.below or {}
    for areaIndex, area in ipairs(areas) do
        if area.name and below[area.name] then
            start.outsideOf = start.outsideOf or {}
            start.outsideOf[areaIndex] = true
        end
    end

    -- Guide places: their points are nodes, their connections the only walks
    -- inside them.
    local places = context.places or {}
    local placeNodes = {}
    for _, place in ipairs(places) do
        local nodes = {}
        for index, point in pairs(place.points) do
            nodes[index] = addNode(graph, context, { key = "point:" .. place.id .. ":" .. index, kind = "point",
                place = place, point = point, pointKind = point.kind, map = point.map, x = point.x, y = point.y })
            if not point.kind then nodes[index].inside = place end
        end
        placeNodes[place] = nodes
        for _, connection in ipairs(place.connections) do
            local a, b = nodes[connection.a], nodes[connection.b]
            local distance = a and b and yards(a, b)
            if distance then
                addEdge(graph, a, b, distance / speed, "walk")
                if not connection.oneWay then addEdge(graph, b, a, distance / speed, "walk") end
            end
        end
    end

    for areaIndex, area in ipairs(areas) do
        for _, node in ipairs(graph.nodes) do
            if node.outsideOf and node.outsideOf[areaIndex] then
                node.areaIn[areaIndex] = false
            elseif not node.doorOf[areaIndex] then
                node.areaIn[areaIndex] = insideArea(graph, context, node, area, areaIndex)
            end
        end
    end

    -- Where the player and the target stand in a place.
    local function join(node, isStart)
        local exact, near
        if not isStart then exact, near = to.point, to.near end
        local place, only
        if exact or near then
            place, only = Travel.FindPoint(places, exact or near)
        end
        if exact and place then
            local pointNode = placeNodes[place][only]
            if pointNode and not pointNode.pointKind then
                node.inside = place
                addEdge(graph, pointNode, node, 0, "walk")
                return
            end
            place = nil
        end
        if isStart and context.indoors == false then return end
        for _, candidate in ipairs(places) do
            if not place or candidate == place then
                local index, t, distance = locate(node, candidate, placeNodes[candidate], context, place and only or nil)
                if index then
                    local connection = candidate.connections[index]
                    local a, b = placeNodes[candidate][connection.a], placeNodes[candidate][connection.b]
                    node.inside, node.connection, node.along = candidate, connection, t
                    local toA, toB = yards(node, a) or 0, yards(node, b) or 0
                    if isStart then
                        graph.attachment = { place = candidate.id, index = index, distance = distance }
                        -- On a loop the player carries on the way they face:
                        -- the end behind them costs a turn.
                        local function behind(target)
                            if type(context.facing) ~= "number" then return 0 end
                            local north, west = target.wx - node.wx, target.wy - node.wy
                            local dot = north * math.cos(context.facing) + west * math.sin(context.facing)
                            return dot < 0 and (2 * Travel.placeYards / speed) or 0
                        end
                        if not connection.oneWay then addEdge(graph, node, a, toA / speed + behind(a), "walk") end
                        addEdge(graph, node, b, toB / speed + behind(b), "walk")
                    else
                        addEdge(graph, a, node, toA / speed, "walk")
                        if not connection.oneWay then addEdge(graph, b, node, toB / speed, "walk") end
                    end
                    return
                end
            end
        end
    end
    join(start, true)
    join(goal, false)
    if start.connection and start.inside == goal.inside and start.connection == goal.connection then
        local ahead = not start.connection.oneWay or (goal.along or 0) >= (start.along or 0)
        local distance = yards(start, goal)
        if ahead and distance then addEdge(graph, start, goal, distance / speed, "walk") end
    end

    -- Straight walks between everything the walls allow.
    for _, u in ipairs(graph.nodes) do
        if u ~= goal then
            for _, v in ipairs(graph.nodes) do
                if v ~= u and v ~= start and v.kind ~= "arrival" and walkAllowed(u, v, areas) then
                    local distance = yards(u, v)
                    if distance == nil and u.map == v.map and not u.continent and not v.continent then
                        distance = 0 -- unplaceable, same map: the arrow alone
                    end
                    if distance then
                        local wait = 0
                        for _, door in pairs(u.doorOf) do
                            if not door.bottom then wait = wait + (door.wait or 0) end
                        end
                        addEdge(graph, u, v, distance * self.detour / speed + wait, "walk")
                    end
                end
            end
        end
    end

    -- Flights between known masters on one continent.
    for _, u in ipairs(graph.nodes) do
        if u.kind == "flight" then
            local reachable = reachableSet(context, u.flightKey)
            for _, v in ipairs(graph.nodes) do
                if v.kind == "flight" and v ~= u and (not reachable or reachable[v.flightKey]) then
                    local distance = yards(u, v)
                    if distance then
                        local measured = median(context.flightTimes and context.flightTimes[u.flightKey .. ">" .. v.flightKey])
                        addEdge(graph, u, v, measured or distance * self.flightDetour / self.flightSpeed, "flight")
                    end
                end
            end
        end
    end
    return graph
end

------------------------------------------------------------------------------
-- The search

local function stateKey(node, mode) return node.id .. "|" .. (mode or "") end

local function search(graph, allow)
    local start, goal = graph.start, graph.goal
    local dist, previous, done = {}, {}, {}
    local open = { { key = stateKey(start, nil), node = start } }
    dist[open[1].key] = 0
    while #open > 0 do
        local bestIndex = 1
        for index = 2, #open do
            if dist[open[index].key] < dist[open[bestIndex].key] then bestIndex = index end
        end
        local current = table.remove(open, bestIndex)
        if not done[current.key] then
            done[current.key] = true
            if current.node == goal then
                local path, key = {}, current.key
                while previous[key] do
                    table.insert(path, 1, previous[key].edge)
                    key = previous[key].from
                end
                return { edges = path, cost = dist[current.key] }
            end
            for _, edge in ipairs(graph.edges[current.node.id]) do
                if allow(edge) then
                    local penalty = (current.mode and current.mode ~= edge.mode) and Travel.legPenalty or 0
                    local key = stateKey(edge.to, edge.mode)
                    -- A hair per edge, so walking through a point on the
                    -- straight line never ties with walking past it.
                    local cost = dist[current.key] + edge.cost + penalty + 1e-6
                    if not done[key] and (dist[key] == nil or cost < dist[key]) then
                        dist[key] = cost
                        previous[key] = { from = current.key, edge = edge }
                        table.insert(open, { key = key, node = edge.to, mode = edge.mode })
                    end
                end
            end
        end
    end
    return nil
end
Travel.Search = search

local function onlyWalking(edge) return edge.mode == "walk" end

local function isWalkOnly(result)
    for _, edge in ipairs(result.edges) do if edge.mode ~= "walk" then return false end end
    return true
end

-- The route shown last time, priced from where the player stands now: the
-- same nodes by the same modes, or nil when that is no longer possible (the
-- hearth was used, the continent changed, a door is now behind a wall). A
-- walk that the player has partly done starts at the furthest of its
-- leading points they can walk to directly, which is how a player half way
-- along a cave passage keeps going the way they face.
local function evaluate(graph, path, allow)
    local function edgeTo(node, key, mode)
        for _, edge in ipairs(graph.edges[node.id]) do
            if edge.to.key == key and edge.mode == mode and allow(edge) then return edge end
        end
        return nil
    end
    -- The furthest of the route's leading walk points `from` walks to directly.
    local function furthest(from)
        local found = nil
        for index, step in ipairs(path) do
            if step.mode ~= "walk" and index > 1 then break end
            if edgeTo(from, step.key, step.mode) then found = index end
            if step.mode ~= "walk" then break end
        end
        return found
    end
    local edges, cost, node, mode = {}, 0, graph.start, nil
    local first = furthest(graph.start)
    if not first then
        -- The player stepped onto the next connection at a junction: one walk
        -- to the end of the connection they are on rejoins the route.
        for _, edge in ipairs(graph.edges[graph.start.id]) do
            if edge.mode == "walk" and allow(edge) and edge.to.kind == "point" then
                local rejoin = furthest(edge.to)
                if rejoin then
                    edges[1], cost, node, mode, first = edge, edge.cost, edge.to, "walk", rejoin
                    break
                end
            end
        end
    end
    if not first then return nil end
    for index = first, #path do
        local edge = edgeTo(node, path[index].key, path[index].mode)
        if not edge then return nil end
        cost = cost + edge.cost + ((mode and mode ~= edge.mode) and Travel.legPenalty or 0)
        table.insert(edges, edge)
        node, mode = edge.to, edge.mode
    end
    if node ~= graph.goal then return nil end
    return { edges = edges, cost = cost }
end

local function pathOf(result)
    local path = {}
    for index, edge in ipairs(result.edges) do path[index] = { key = edge.to.key, mode = edge.mode } end
    return path
end

local function samePath(a, b)
    if #a.edges ~= #b.edges then return false end
    for index, edge in ipairs(a.edges) do
        if edge.to.key ~= b.edges[index].to.key or edge.mode ~= b.edges[index].mode then return false end
    end
    return true
end

------------------------------------------------------------------------------
-- Legs

local function spot(node, arrivalYards)
    return { mapID = node.map, x = node.x, y = node.y, arrivalYards = arrivalYards }
end

local function doorText(edge)
    local u, v = edge.from, edge.to
    if edge.lift then
        return "Ride " .. (v.door.label or "the lift") .. (v.kind == "lift" and " down" or " up")
    end
    if v.kind == "lift" then return "Take " .. (v.door.label or "the lift") .. " up" end
    if v.kind == "door" then
        local index
        for areaIndex in pairs(v.doorOf) do index = areaIndex end
        local leaving = index and u.areaIn[index]
        local name = v.area.name or "the area"
        local label = v.door.label
        if v.door.bottom and leaving then return "Take " .. (label or "the lift") .. " down" end
        if leaving then return "Leave " .. name .. (label and (" by " .. label) or "") end
        return "Enter " .. name .. (label and (" by " .. label) or "")
    end
    if v.kind == "point" then
        local place, point = v.place, v.point
        if v.pointKind then
            local leaving = u.inside == place or u.place == place
            if leaving then return point.label and ("Leave by " .. point.label) or ("Leave " .. place.name) end
            return "Enter " .. place.name .. (point.label and (" by " .. point.label) or "")
        end
        if point.label then return "Go to " .. point.label end
        return place.name
    end
    if v.kind == "dock" then return "Go to the " .. (v.row.kind or "dock") end
    if v.kind == "flight" then return "Go to the flight master" end
    return "Walk"
end

local function linkText(row, side)
    local destination = row[side] and row[side].name or "the far side"
    if row.kind == "flight" then return "Fly to " .. destination end
    return "Take the " .. (row.kind or "boat") .. " to " .. destination
end

local function teleportText(row, arrival)
    if row.to == "bind" and arrival.placeName then return row.label .. " to " .. arrival.placeName end
    return row.label or "Teleport"
end

function Travel:Legs(graph, result)
    local legs, edges, index = {}, result.edges, 1
    local before = 0 -- walking folded into the next leg (to a flight master or a dock)
    while index <= #edges do
        local edge = edges[index]
        local mode = edge.mode
        if mode == "walk" then
            local nextEdge = edges[index + 1]
            if nextEdge and nextEdge.mode ~= "walk" and nextEdge.from == edge.to then
                before = before + edge.cost
            elseif nextEdge and edge.from == graph.start and (yards(edge.from, edge.to) or math.huge)
                < (edge.to.kind == "point" and 5 or 10) then
                -- Already standing on the point, as near as the arrow counts
                -- arriving there: nothing to walk to. Otherwise a plan made
                -- just after arriving at a gate hands the gate back.
            elseif edge.to == graph.goal and edge.cost == 0 and legs[#legs] and legs[#legs].kind == "walk"
                and legs[#legs].key == edge.from.key then
                -- The target is a place's point, and the leg before already
                -- ends on it.
                local last = legs[#legs]
                last.final, last.text = true, nil
            elseif edge.to == graph.goal then
                table.insert(legs, { kind = "walk", final = true, cost = edge.cost,
                    at = spot(edge.to), dest = spot(edge.to), key = edge.to.key })
            else
                local node = edge.to
                table.insert(legs, { kind = "walk", text = doorText(edge), cost = edge.cost,
                    at = spot(node, node.kind == "point" and 5 or 10), dest = spot(node), key = node.key,
                    place = node.place and node.place.name, point = node.point and node.point.label })
            end
            index = index + 1
        elseif mode == "flight" then
            local last = index
            while edges[last + 1] and edges[last + 1].mode == "flight" do last = last + 1 end
            local origin, landing = edge.from, edges[last].to
            local cost = 0
            for step = index, last do cost = cost + edges[step].cost end
            table.insert(legs, { kind = "flight", text = "Fly to " .. shortName(landing.row.name), cost = cost,
                walkBefore = before, from = origin.row, to = landing.row, fromKey = origin.flightKey, toKey = landing.flightKey,
                at = spot(origin, 6), dest = spot(landing, 60), key = landing.key })
            before = 0
            index = last + 1
        elseif mode:match("^link:") then
            table.insert(legs, { kind = "link", text = linkText(edge.row, edge.side), cost = edge.cost,
                walkBefore = before, row = edge.row, linkKind = edge.row.kind,
                at = spot(edge.from, 15), dest = spot(edge.to, 60), key = edge.to.key })
            before = 0
            index = index + 1
        else -- teleport
            local row = edge.row
            table.insert(legs, { kind = "teleport", text = teleportText(row, edge.to), cost = edge.cost,
                row = row, spell = row.spell, item = row.item,
                dest = spot(edge.to, 60), key = edge.to.key })
            index = index + 1
        end
    end
    return legs
end

-- "walk > fly Crossroads > walk": the legs, without the times.
function Travel.Outline(legs)
    local parts = {}
    local function add(word)
        if parts[#parts] ~= word then table.insert(parts, word) end
    end
    for _, leg in ipairs(legs) do
        if leg.kind == "walk" then
            add("walk")
        else
            if (leg.walkBefore or 0) >= 10 then add("walk") end
            if leg.kind == "flight" then add("fly " .. shortName(leg.to and leg.to.name))
            elseif leg.kind == "link" then add(leg.linkKind == "flight" and "fly" or (leg.linkKind or "boat"))
            else add((leg.row and leg.row.label or "teleport"):lower()) end
        end
    end
    return table.concat(parts, " > ")
end

-- "walk > fly Crossroads > walk (~2m10s, walking ~6m)"
function Travel.Summary(plan)
    local text = Travel.Outline(plan.legs) .. " (~" .. Travel.FormatSeconds(plan.cost)
    if plan.walkCost and not plan.walkOnly then text = text .. ", walking ~" .. Travel.FormatSeconds(plan.walkCost) end
    return text .. ")"
end

-- Everything but a teleport that costs something to use.
local function noSpentTeleport(edge)
    return not edge.mode:match("^teleport:") or (edge.row ~= nil and edge.row.free == true)
end

-- Everything but the other teleports.
local function withTeleport(mode)
    return function(edge) return edge.mode == mode or not edge.mode:match("^teleport:") end
end

local function usesMode(result, mode)
    for _, edge in ipairs(result.edges) do if edge.mode == mode then return true end end
    return false
end

-- `a` saves enough over `b` to be worth the player's attention.
local function clearlyBetter(a, b, seconds, share)
    return b.cost - a.cost >= seconds and a.cost <= b.cost * (1 - share)
end

-- The routes the player can pick between, the default first: the route
-- shown unless the player picks another (walking, or flights, transports and
-- free teleports when they clearly beat walking); then each teleport that
-- is ready and clearly beats the default (or was picked), fastest first;
-- then plain walking
-- when the default is not already that.
local function choices(self, graph, context)
    local options = context.options or {}
    local seconds = context.suggestSeconds or self.suggestSeconds
    local share = context.suggestShare or self.suggestShare
    local walk = search(graph, onlyWalking)
    local list = {}
    local default, allow = walk, onlyWalking
    local suggest = options.suggest ~= false
    if suggest then
        allow = noSpentTeleport
        local full = search(graph, noSpentTeleport)
        if full and not isWalkOnly(full) and (not walk or clearlyBetter(full, walk, seconds, share)) then default = full end
    end
    if default then table.insert(list, { id = "default", result = default, allow = allow }) end
    if not suggest then return list, walk end
    local teleports = {}
    for _, edge in ipairs(graph.edges[graph.start.id]) do
        if edge.mode:match("^teleport:") and not usesMode(default or { edges = {} }, edge.mode) then
            local only = withTeleport(edge.mode)
            local result = search(graph, only)
            -- One the player picked stays on offer while it can be cast,
            -- so the pick does not lapse as they walk.
            local worth = not default or edge.mode == context.choice or clearlyBetter(result, default, seconds, share)
            if result and usesMode(result, edge.mode) and worth then
                table.insert(teleports, { id = edge.mode, result = result, allow = only })
            end
        end
    end
    table.sort(teleports, function(a, b) return a.result.cost < b.result.cost end)
    for _, choice in ipairs(teleports) do table.insert(list, choice) end
    if walk and default and default ~= walk and not isWalkOnly(default) then
        table.insert(list, { id = "walk", result = walk, allow = onlyWalking })
    end
    return list, walk
end

-- The route from `from` to `to` (both `{ map, x, y }`, normalized; `to` may
-- also carry `point` or `near`, a guide place's "place.point", or `spots`,
-- more `{ x, y }` on its map any of which will do), as waypoints:
-- a plan `{ legs, cost, walkCost, path, walkOnly, direct, choice, choices,
-- summary, attachment }`. Each leg ends on a waypoint and the last one on the
-- target, so a plan that is one straight walk (`direct`) is one waypoint.
-- `choices` lists what the player can pick instead, `{ id, outline, cost }`,
-- the default first; `choice` is the id this plan follows. Nil and a reason
-- when nothing can be said ("unplaced", "unreachable").
--
-- context: world(map, x, y) -> continent, worldX, worldY in yards; data
-- (defaults to ns.travel); places (Travel.ResolvePlaces); faction; class;
-- mapAt(map, x, y) -> the map the client says lies there (a city inside its
-- zone), or nil; knownFlight(name); reachable[originKey] = { names };
-- flightTimes["a>b"] = { seconds }; bind; teleport(row) -> seconds of cooldown left, or nil when
-- unusable; speed; indoors; lastConnection; options { suggest, flights,
-- teleports, links }; choice (an id from a plan's `choices`, the player's
-- pick; unknown or nil means the default); previous (the last plan, for
-- hysteresis).
function Travel:Plan(from, to, context)
    context = context or {}
    if type(from) ~= "table" or type(to) ~= "table" then return nil, "unplaced" end
    local graph = self:Graph(from, to, context)
    if not graph then return nil, "unplaced" end
    local list, walk = choices(self, graph, context)
    if #list == 0 then return nil, "unreachable" end
    local chosen = list[1]
    for _, choice in ipairs(list) do
        if choice.id == context.choice then chosen = choice end
    end
    local best = chosen.result
    -- Hysteresis, within the route the player is following: the one shown
    -- last time holds until another clearly beats it.
    local previous = context.previous
    if previous and previous.path and previous.choice == chosen.id then
        local kept = evaluate(graph, previous.path, chosen.allow)
        if kept and not samePath(kept, best) then
            local bothWalk = isWalkOnly(kept) and isWalkOnly(best)
            local margin = bothWalk and (self.placeYards / graph.speed) or (context.suggestSeconds or self.suggestSeconds)
            local share = bothWalk and self.placeShare or (context.suggestShare or self.suggestShare)
            if not clearlyBetter(best, kept, margin, share) then best = kept end
        end
    end
    local legs = self:Legs(graph, best)
    if #legs == 0 then return nil, "unplaced" end
    local plan = { legs = legs, cost = best.cost, walkCost = walk and walk.cost, path = pathOf(best),
        walkOnly = isWalkOnly(best), direct = #legs == 1 and legs[1].final == true,
        choice = chosen.id, choices = {}, attachment = graph.attachment }
    for _, choice in ipairs(list) do
        local result = choice == chosen and best or choice.result
        table.insert(plan.choices, { id = choice.id, cost = result.cost, outline = Travel.Outline(self:Legs(graph, result)) })
    end
    plan.summary = Travel.Summary(plan)
    return plan
end

-- The classic world's zone and city maps (uiMapID 1411 Durotar to 1458
-- Undercity, 1459 and 1460 the battlegrounds' neighbours excluded). A row on
-- any other map is a typo, not a place.
local function knownMap(map) return type(map) == "number" and map >= 1411 and map <= 1458 end

-- Problems with `Data/Travel.lua`, as "flights[3].at: ..." strings; empty
-- when the data is sound. Run by the tests, the way guides are validated.
function Travel.ValidateData(data)
    local problems = {}
    local function problem(path, message) table.insert(problems, path .. ": " .. message) end
    local function ascii(path, value)
        if type(value) == "string" and value:find("[\128-\255]") then problem(path, "must be ASCII") end
    end
    local function position(path, map, at)
        if not knownMap(map) then problem(path .. ".map", "is not a known map") end
        local x, y = normalize(type(at) == "table" and at[1], type(at) == "table" and at[2])
        if not x or x < 0 or x > 1 or y < 0 or y > 1 then problem(path .. ".at", "must be { x, y } map percentages") end
    end
    local factions = { Horde = true, Alliance = true, Neutral = true }
    local seen = {}
    for index, row in ipairs(data.flights or {}) do
        local path = "flights[" .. index .. "]"
        if type(row.name) ~= "string" then problem(path .. ".name", "must be the taxi node's name")
        else
            ascii(path .. ".name", row.name)
            local key = Travel.FlightKey(row.name)
            if seen[key] then problem(path .. ".name", "repeats " .. seen[key]) end
            seen[key] = path
        end
        if row.npc ~= nil and (type(row.npc) ~= "number" or row.npc % 1 ~= 0) then problem(path .. ".npc", "must be an NPC ID") end
        if row.faction ~= nil and not factions[row.faction] then problem(path .. ".faction", "must be Horde, Alliance or Neutral") end
        position(path, row.map, row.at)
    end
    for index, row in ipairs(data.links or {}) do
        local path = "links[" .. index .. "]"
        for _, side in ipairs({ "from", "to" }) do
            local spot = row[side]
            if type(spot) ~= "table" then problem(path .. "." .. side, "is required")
            else
                position(path .. "." .. side, spot.map, spot.at)
                if type(spot.name) ~= "string" then problem(path .. "." .. side .. ".name", "is what the tracker says") end
                ascii(path .. "." .. side .. ".name", spot.name)
            end
        end
        if row.faction ~= nil and not factions[row.faction] then problem(path .. ".faction", "must be Horde, Alliance or Neutral") end
    end
    for index, row in ipairs(data.teleports or {}) do
        local path = "teleports[" .. index .. "]"
        if type(row.item) ~= "number" and type(row.spell) ~= "number" then problem(path, "needs an item or a spell ID") end
        if row.to ~= "bind" then
            if type(row.to) ~= "table" then problem(path .. ".to", "must be \"bind\" or a place")
            else position(path .. ".to", row.to.map, row.to.at) end
        end
        if type(row.label) ~= "string" then problem(path .. ".label", "is required") end
        if row.free ~= nil and row.free ~= true then problem(path .. ".free", "is true or left out") end
        ascii(path .. ".label", row.label)
    end
    for index, inn in ipairs(data.inns or {}) do
        local path = "inns[" .. index .. "]"
        if type(inn.name) ~= "string" then problem(path .. ".name", "must be the bind location's name") end
        ascii(path .. ".name", inn.name)
        position(path, inn.map, inn.at)
    end
    for index, area in ipairs(data.areas or {}) do
        local path = "areas[" .. index .. "]"
        if type(area.name) ~= "string" then problem(path .. ".name", "is required") end
        if not knownMap(area.map) then problem(path .. ".map", "is not a known map") end
        if (area.at == nil) ~= (area.radius == nil) then problem(path, "a circle needs both at and radius") end
        if area.at ~= nil then position(path, area.map, area.at) end
        if type(area.doors) ~= "table" or #area.doors == 0 then problem(path .. ".doors", "an area needs a door") end
        for doorIndex, door in ipairs(type(area.doors) == "table" and area.doors or {}) do
            local doorPath = path .. ".doors[" .. doorIndex .. "]"
            position(doorPath, door.map or area.map, door.at)
            if door.kind ~= nil and door.kind ~= "entrance" and door.kind ~= "exit" then problem(doorPath .. ".kind", "must be entrance or exit") end
            if door.bottom ~= nil then
                if type(door.bottom) ~= "table" then problem(doorPath .. ".bottom", "must be { at = { x, y } }")
                else position(doorPath .. ".bottom", door.bottom.map or door.map or area.map, door.bottom.at) end
            end
            ascii(doorPath .. ".label", door.label)
        end
    end
    return problems
end

-- Which connection of the guide's places the player stands on, as
-- "place:index", without planning anything: the arrow replans when this
-- changes, which is how it follows a player who took the other branch.
function Travel:Locate(from, places, context)
    if type(from) ~= "table" or not places or #places == 0 then return nil end
    context = context or {}
    if context.indoors == false then return nil end
    local graph = { nodes = {}, edges = {}, byKey = {} }
    local player = addNode(graph, context, { map = from.map, x = from.x, y = from.y })
    for _, place in ipairs(places) do
        local nodes = {}
        for index, point in pairs(place.points) do
            nodes[index] = addNode(graph, context, { map = point.map, x = point.x, y = point.y, pointKind = point.kind })
        end
        local index = locate(player, place, nodes, context)
        if index then return place.id .. ":" .. index, { place = place.id, index = index } end
    end
    return nil
end

ns:RegisterModule("Travel", Travel)
