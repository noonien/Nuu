local _, ns = ...

-- The travel planner in the running game: it asks Domain/Travel.lua for a
-- route to whatever the arrow is following, hands the arrow one leg at a
-- time, notices when a leg is done, and learns from play (flight times, what
-- each flight master can reach). The route is only ever a suggestion: nothing
-- here clicks a flight master, casts a teleport, or boards anything. At a
-- flight master the destination is highlighted; a teleport is a button in the
-- arrow window for the player to press.
--
-- When to plan again: when the step changes, on a zone change
-- or a loading screen, on landing, when a flight path is learned, and on a
-- slow beat once the player has moved 50 yards since the last plan. Inside a
-- guide place, also when the player steps onto another passage, and when a
-- teleport becomes ready or stops being (what the tracker offers). Never while
-- on a taxi (the route is planned from the landing), and not while waiting at
-- or riding a boat (the boat lock), until the zone changes or the player
-- walks away from the dock.
--
-- Everything it decides, and everything the client answered that a decision
-- rests on, goes to the recorder's `travel` channel (`sessions.py --channel
-- travel`), so a play session is its own test report: nothing has to be
-- copied out of the game.
local TravelRoute = { interval = 0.5, index = 1, maxHistory = 5, teleportCheck = 5, speedSamples = 20,
    dockYards = 40, carriedYards = 1, carriedBeats = 3, dockSampleSeconds = 5, speedLogStep = 0.5,
    liftYards = 10, jumpYards = 60 }

local function client() return ns.modules.Client end
local function travel() return ns.modules.Travel end
local function now() return GetTime and GetTime() or 0 end

local function round(value, places)
    if type(value) ~= "number" then return value end
    local factor = 10 ^ (places or 1)
    return math.floor(value * factor + 0.5) / factor
end

-- One row on the `travel` channel, with where the player stands.
local function log(event, data)
    data = data or {}
    data.event = event
    ns:RecordHere("travel", data)
end

-- A spot as a guide writes it: map and percentages.
local function spotOf(map, x, y)
    if not map or type(x) ~= "number" then return nil end
    return { map = map, at = { round(x * 100, 2), round(y * 100, 2) } }
end

-- The travel switches as they apply (navigation.travel, in Options).
function TravelRoute:Settings()
    return ns.modules.Config:Get("navigation.travel")
end

-- Where the player stands, as the planner wants it, plus world coordinates
-- for the moved-50-yards check.
function TravelRoute:PlayerPosition()
    local Client = client()
    local map = Client:GetCurrentMapID()
    if not map then return nil end
    local x, y = Client:GetPlayerMapPosition(map)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local continent, wx, wy = Client:GetWorldPosition(map, x, y)
    return { map = map, x = x, y = y }, continent, wx, wy
end

-- The guide's places, resolved once per guide.
function TravelRoute:Places(guide)
    if not guide or not guide.places then return {} end
    if self.placesGuide ~= guide then
        self.placesGuide = guide
        self.places = travel().ResolvePlaces(guide.places)
    end
    return self.places
end

-- The guide's places were edited and saved: resolve them again.
function TravelRoute:ForgetPlaces()
    log("places", { what = "reloaded after an editor save" })
    self.placesGuide, self.places, self.plan = nil, nil, nil
    self:Replan("places")
end

function TravelRoute:Target(node, from)
    local location = node and node.location
    if not location or type(location.x) ~= "number" or type(location.y) ~= "number" then return nil end
    local Client = client()
    local map = Client:ResolveMapID(location.mapID)
    if not map then return nil end
    local x, y = location.x, location.y
    if from and from.map == map then
        x, y = ns.modules.Navigation.NearestPoint(location, from.x, from.y)
    end
    -- Every spot of the step is a way to arrive: the planner picks the one
    -- quickest to reach, not the nearest in a straight line.
    local spots
    if location.spots and not location.point then
        spots = {}
        for _, spot in ipairs(location.spots) do
            if type(spot.x) == "number" and type(spot.y) == "number" then table.insert(spots, { x = spot.x, y = spot.y }) end
        end
        table.insert(spots, { x = location.x, y = location.y })
    end
    return { map = map, x = x, y = y, point = location.point, near = location.near, spots = spots }
end

-- Where the hearthstone is set, and whether `Data/Travel.lua` knows that
-- inn: without it no hearth is ever offered, so the log says so once per
-- bind location.
function TravelRoute:BindState()
    local bind = client():GetBindLocation()
    if not bind then return nil, false end
    local key = travel().FlightKey(bind)
    for _, inn in ipairs(ns.travel and ns.travel.inns or {}) do
        if travel().FlightKey(inn.name) == key then return bind, true end
    end
    if self.unknownBind ~= bind then
        self.unknownBind = bind
        ns:Log("travel: hearth bound to " .. bind .. ", which is not in Data/Travel.lua inns; no hearth is offered")
    end
    return bind, false
end

function TravelRoute:LogBind()
    local bind, known = self:BindState()
    if bind == self.loggedBind then return end
    self.loggedBind = bind
    log("bind", { bind = bind or "<none>", known = known })
end

-- The client's city-at-a-point answer, logged the first time each spot is
-- asked about: it is what decides whether a zone point is behind a wall.
function TravelRoute:MapAt(map, x, y)
    local answer = client():GetMapAtPosition(map, x, y)
    local key = map .. ":" .. round(x * 100, 1) .. ":" .. round(y * 100, 1)
    self.mapAtSeen = self.mapAtSeen or {}
    if not self.mapAtSeen[key] then
        self.mapAtSeen[key] = true
        log("mapat", { spot = spotOf(map, x, y), answer = answer or "<nil>" })
    end
    return answer
end

function TravelRoute:Context(node)
    local Client = client()
    local settings = self:Settings()
    self:LogBind()
    local facing
    if GetPlayerFacing then
        local ok, value = pcall(GetPlayerFacing)
        if ok and type(value) == "number" then facing = value end
    end
    return {
        world = function(map, x, y) return Client:GetWorldPosition(map, x, y) end,
        mapAt = function(map, x, y) return self:MapAt(map, x, y) end,
        places = self:Places(self.guide),
        faction = Client:GetPlayerFaction(),
        class = Client:GetPlayerClass(),
        knownFlight = function(name) return Client:HasFlightPath(name) end,
        reachable = Client:ReachableFlights(),
        flightTimes = ns.db.travel and ns.db.travel.flightTimes,
        bind = Client:GetBindLocation(),
        teleport = function(row) return Client:TeleportCooldown(row) end,
        speed = self.speed,
        indoors = Client:IsIndoors(),
        facing = facing,
        lastConnection = self.attachment,
        options = { suggest = settings.suggest ~= false, flights = settings.flights ~= false,
            teleports = settings.teleports ~= false, links = settings.links ~= false },
        choice = self.choiceNode ~= nil and self.choiceNode == node and self.choice or nil,
        below = self.below,
        previous = self.plan,
    }
end

-- Which teleports can be cast now, as a string: a hearth coming off
-- cooldown, or a stone looted, changes what the tracker offers.
function TravelRoute:TeleportKey()
    local Client, ready = client(), {}
    for index, row in ipairs(ns.travel and ns.travel.teleports or {}) do
        local remaining = Client:TeleportCooldown(row)
        if remaining and remaining <= travel().readySeconds then table.insert(ready, index) end
    end
    return table.concat(ready, ",")
end

-- True when that changed and the route was planned again.
function TravelRoute:CheckTeleports()
    local key = self:TeleportKey()
    if not self.node or key == self.teleportKey then return false end
    log("teleports", { ready = key, before = self.teleportKey })
    self:Replan("teleports")
    return true
end

-- The node the arrow follows changed (or the guide did).
function TravelRoute:Sync(node, guide)
    if node == self.node and guide == self.guide then return end
    local stepChanged = node ~= self.node
    self.node, self.guide = node, guide
    if stepChanged then
        self.plan, self.index, self.frozen = nil, 1, false
        if self.choiceNode ~= node then self.choiceNode, self.choice = nil, nil end
    end
    self:Replan("step")
end

function TravelRoute:Replan(reason)
    local node = self.node
    self.lastReason = reason
    if not node or not node.location or not travel() then return self:SetPlan(nil) end
    local Client = client()
    if Client:IsOnTaxi() then return end
    local from, continent, wx, wy = self:PlayerPosition()
    if not from then return self:SetPlan(nil, "unplaced") end
    local to = self:Target(node, from)
    if not to then return self:SetPlan(nil, "unplaced") end
    local context = self:Context(node)
    local ok, plan, why = pcall(travel().Plan, travel(), from, to, context)
    if not ok then
        ns:Log("travel: " .. tostring(plan))
        log("error", { message = tostring(plan), reason = reason })
        plan, why = nil, "error"
    end
    self:LogPlan(reason, to, context, plan, why)
    self.lastFrom = { continent = continent, wx = wx, wy = wy, map = from.map, x = from.x, y = from.y }
    self.teleportKey = self:TeleportKey()
    local key, attachment = travel():Locate(from, context.places, context)
    self.attachmentKey, self.attachment = key, attachment
    self:SetPlan(plan, why)
end

-- The route without its times: what a replan on the move is logged by.
local function shape(plan, why)
    if not plan then return "none:" .. tostring(why) end
    local ids = {}
    for _, choice in ipairs(plan.choices or {}) do table.insert(ids, choice.id .. "=" .. choice.outline) end
    local keys = {}
    for _, leg in ipairs(plan.legs) do table.insert(keys, tostring(leg.key)) end
    return plan.choice .. "|" .. table.concat(keys, ">") .. "|" .. table.concat(ids, ",")
end

-- A plan on the `travel` channel. Every plan asked for by an event is
-- written; one made because the player walked on only when its shape
-- changed, or the log would be a row every fifty yards.
function TravelRoute:LogPlan(reason, to, context, plan, why)
    local current = shape(plan, why)
    local changed = current ~= self.loggedShape
    self.loggedShape = current
    if reason == "moved" and not changed then return end
    local row = { reason = reason, target = spotOf(to.map, to.x, to.y), spots = to.spots and #to.spots or nil,
        picked = context.choice, speed = round(context.speed or travel().runSpeed, 1), indoors = context.indoors }
    if not plan then
        row.why = why
        return log("plan", row)
    end
    row.summary, row.choice, row.cost = plan.summary, plan.choice, round(plan.cost, 0)
    row.choices = {}
    for _, choice in ipairs(plan.choices) do
        table.insert(row.choices, { id = choice.id, outline = choice.outline, cost = round(choice.cost, 0) })
    end
    if changed then
        row.legs = {}
        for _, leg in ipairs(plan.legs) do
            local spot = leg.at or leg.dest
            table.insert(row.legs, { kind = leg.kind, text = leg.text or (leg.final and "to the step") or nil,
                key = leg.key, cost = round(leg.cost, 0),
                to = spot and spotOf(spot.mapID, spot.x, spot.y) or nil })
        end
    end
    log("plan", row)
end

-- What the tracker shows of a plan: the route and what else is on offer.
local function signature(plan)
    if not plan then return nil end
    local ids = {}
    for _, choice in ipairs(plan.choices or {}) do table.insert(ids, choice.id) end
    return plan.summary .. "|" .. plan.choice .. "|" .. table.concat(ids, ",")
end

function TravelRoute:SetPlan(plan, why)
    local before = signature(self.plan)
    self.plan, self.index, self.why = plan, 1, why
    if signature(plan) ~= before then self:Changed() end
end

-- The route moved on: the tracker's route line, the arrow, the teleport
-- button (it comes and goes with its leg) and the taxi highlight.
function TravelRoute:Changed()
    local MainWindow = ns.modules.MainWindow
    if MainWindow and MainWindow.RequestRefresh then MainWindow:RequestRefresh() end
    local Navigation = ns.modules.Navigation
    if Navigation then Navigation.forceAngleUpdate = true end
    self:HighlightTaxi()
    self:SyncTeleportButton()
end

-- The leg the arrow shows for this node, or nil when the arrow simply points
-- at the step (no route, or only the final walk is left).
function TravelRoute:Leg(node)
    if not self.plan or node == nil or self.node ~= node then return nil end
    local leg = self.plan.legs[self.index]
    if not leg or leg.final then return nil end
    return leg
end

-- The waypoints still ahead before the step itself, the current one first:
-- what the map pins, nearest first. A flight or a boat is two: where it is
-- taken and where it lands. A teleport has only its landing.
function TravelRoute:Waypoints(node)
    local list = {}
    if not self:Leg(node) then return list end
    for index = self.index, #self.plan.legs do
        local leg = self.plan.legs[index]
        if leg.final then break end
        if leg.kind ~= "teleport" then table.insert(list, leg) end
        if leg.kind ~= "walk" and leg.dest then
            table.insert(list, { kind = "landing", text = leg.text .. " (landing)", dest = leg.dest })
        end
    end
    return list
end

-- `how` says what ended the leg, for the log.
function TravelRoute:Advance(replan, how)
    local leg = self.plan and self.plan.legs[self.index]
    if leg then log("leg", { done = leg.kind, text = leg.text, index = self.index, how = how }) end
    self.index = self.index + 1
    self.frozen = false
    -- A teleport picked and taken is spent: the next plan is the default.
    if leg and leg.kind == "teleport" and self.choiceNode == self.node then self.choiceNode, self.choice = nil, nil end
    -- A teleport just cast has not moved the player yet: the legs after it
    -- are already planned from its landing, and the move itself replans.
    if leg and leg.kind == "teleport" and not replan then return self:Changed() end
    -- A flight, a boat or a teleport done is not a route to hold on to: the
    -- next plan starts fresh from wherever it put the player.
    if replan or (leg and leg.kind ~= "walk") then
        self.plan = nil
        self:Replan("leg done")
    end
    self:Changed()
end

-- Called from the arrow's update with the leg on screen: decides whether it
-- is done. Walking legs end on arrival; a flight once the player was on the
-- taxi and has landed; a boat once the continent changes or the far dock is
-- reached; a teleport once it is cast or the player stands where it lands.
function TravelRoute:Watch(leg)
    local Navigation, Client = ns.modules.Navigation, client()
    if leg.kind == "walk" then
        local _, _, _, arrived = Navigation:Measure(leg.at)
        if arrived then self:Advance(false, "arrived") end
    elseif leg.kind == "flight" then
        if Client:IsOnTaxi() then
            leg.boarded = true
        elseif leg.boarded then
            self:Advance(true, "landed")
        else
            local _, _, _, landed = Navigation:Measure(leg.dest)
            if landed then self:Advance(true, "at the landing without a taxi") end
        end
    elseif leg.kind == "link" then
        local _, continent = self:PlayerPosition()
        leg.startContinent = leg.startContinent or continent
        local _, _, _, atDock = Navigation:Measure(leg.at)
        if atDock and not self.frozen then
            self.frozen, self.carried, self.carriedCount, self.dockLast, self.dockSampleAt = true, false, 0, nil, nil
            log("dock", { state = "locked", link = leg.text })
        end
        local _, _, _, across = Navigation:Measure(leg.dest)
        -- A ride that is a taxi (a druid's flight) ends when the taxi does.
        if Client:IsOnTaxi() then return end
        if across then self:Advance(true, "at the far dock")
        elseif continent and leg.startContinent and continent ~= leg.startContinent then self:Advance(true, "continent changed") end
    elseif leg.kind == "teleport" then
        local _, _, _, there = Navigation:Measure(leg.dest)
        if there then self:Advance(true, "at the landing") end
    end
end

-- The boat lock: at the dock and on board nothing is planned, or
-- the player would be rerouted mid-crossing. The zone change or the far dock
-- ends it, and so does walking away without boarding: 40 yards from the dock
-- on the player's own feet. Riding shows as moving while the client says the
-- player's own speed is nought, for three beats running (a player who just
-- stopped walking moved between two beats too); once seen, only the crossing
-- ends the lock.
function TravelRoute:WatchDock()
    local leg = self:Leg(self.node)
    if not leg or leg.kind ~= "link" then
        self.frozen = false
        return
    end
    local from, continent, wx, wy = self:PlayerPosition()
    if not from then return end
    local own = client():GetMoveSpeed()
    local last = self.dockLast
    self.dockLast = { continent = continent, wx = wx, wy = wy }
    local moved
    if last and continent and continent == last.continent and wx and last.wx then
        local dx, dy = wx - last.wx, wy - last.wy
        moved = math.sqrt(dx * dx + dy * dy)
    end
    local _, distance, inYards = ns.modules.Navigation:Measure(leg.at)
    -- What the client says while waiting and riding, every few seconds:
    -- whether its own speed reads nought on board is what this rests on.
    if now() >= (self.dockSampleAt or 0) then
        self.dockSampleAt = now() + self.dockSampleSeconds
        log("dock", { state = "sample", ownSpeed = round(own, 2), movedYards = round(moved, 1),
            dockYards = inYards and round(distance, 0) or nil, carried = self.carried })
    end
    if moved and moved > self.carriedYards and own == 0 then
        self.carriedCount = (self.carriedCount or 0) + 1
    else
        self.carriedCount = 0
    end
    if self.carriedCount >= self.carriedBeats and not self.carried then
        self.carried = true
        log("dock", { state = "carried", movedYards = round(moved, 1) })
    end
    if self.carried or not own or own <= 0 then return end
    if inYards and distance and distance > self.dockYards then
        self.frozen = false
        log("dock", { state = "left", dockYards = round(distance, 0), ownSpeed = round(own, 2) })
        self:Replan("left the dock")
    end
end

-- Below or on top of a lifted area (Thunder Bluff's mesa), which the
-- client's map cannot say: its map covers the ground round the foot too.
-- It is read from where the player has been. Standing at a lift's bottom, or
-- walking onto the area's map from the zone around it, is below; standing at
-- a lift's top, landing from a flight, or arriving by a loading screen or a
-- teleport is on top. Leaving the area's map forgets it. With nothing known
-- the map decides, as for any other area.
function TravelRoute:LiftEnds()
    if self.liftEnds then return self.liftEnds end
    local Client, ends = client(), {}
    for _, area in ipairs(ns.travel and ns.travel.areas or {}) do
        for _, door in ipairs(area.doors or {}) do
            if type(door.bottom) == "table" and door.bottom.at and door.at then
                local function place(map, at)
                    local x, y = travel().Normalize(at[1], at[2])
                    local continent, wx, wy = Client:GetWorldPosition(map, x, y)
                    return continent and { continent = continent, wx = wx, wy = wy } or nil
                end
                table.insert(ends, { area = area.name, map = area.map,
                    top = place(door.map or area.map, door.at),
                    bottom = place(door.bottom.map or door.map or area.map, door.bottom.at) })
            end
        end
    end
    self.liftEnds = ends
    return ends
end

function TravelRoute:SetBelow(area, below, why)
    self.below = self.below or {}
    if (self.below[area] or false) == (below or false) then return false end
    self.below[area] = below or nil
    log("level", { area = area, below = below or false, why = why })
    return true
end

-- True when what is known changed, so the route is planned again.
function TravelRoute:TrackLevels(from, continent, wx, wy)
    local ends = self:LiftEnds()
    if #ends == 0 then return false end
    local changed = false
    local last = self.levelFrom
    self.levelFrom = { map = from.map, continent = continent, wx = wx, wy = wy }
    local jumped = last and last.continent == continent and wx and last.wx
        and math.sqrt((wx - last.wx) ^ 2 + (wy - last.wy) ^ 2) > self.jumpYards
    local function near(spot)
        if not spot or spot.continent ~= continent or not wx then return false end
        return math.sqrt((wx - spot.wx) ^ 2 + (wy - spot.wy) ^ 2) <= self.liftYards
    end
    local seen = {}
    for _, lift in ipairs(ends) do
        if not seen[lift.area] then
            seen[lift.area] = true
            if from.map ~= lift.map then
                changed = self:SetBelow(lift.area, false, "off the map") or changed
            elseif jumped then
                changed = self:SetBelow(lift.area, false, "teleported") or changed
            elseif last and last.map ~= lift.map then
                changed = self:SetBelow(lift.area, true, "walked in from map " .. tostring(last.map)) or changed
            end
        end
        if near(lift.bottom) then changed = self:SetBelow(lift.area, true, "at a lift's bottom") or changed end
        if near(lift.top) then changed = self:SetBelow(lift.area, false, "at a lift's top") or changed end
    end
    return changed
end

-- The player's travel speed: the run speed the client reports now (a
-- mount's while mounted, on foot otherwise, so a cave where nobody rides is
-- walked at walking pace), averaged over the last ten seconds so a moment's
-- sprint or a dismount to loot does not swing the route. Run speed, not the
-- speed moved at: standing still is not a speed of nothing.
function TravelRoute:SampleSpeed(speed)
    if type(speed) ~= "number" or speed <= 0 then return end
    self.speeds = self.speeds or {}
    table.insert(self.speeds, speed)
    while #self.speeds > self.speedSamples do table.remove(self.speeds, 1) end
    local total = 0
    for _, sample in ipairs(self.speeds) do total = total + sample end
    self.speed = total / #self.speeds
    if not self.loggedSpeed or math.abs(self.speed - self.loggedSpeed) >= self.speedLogStep then
        self.loggedSpeed = self.speed
        log("speed", { average = round(self.speed, 2), sample = round(speed, 2), ownSpeed = round(client():GetMoveSpeed(), 2) })
    end
end

-- The slow beat: learn the run speed, notice a taxi starting and ending, and
-- plan again when the player has moved on.
function TravelRoute:Tick()
    local Client = client()
    local onTaxi = Client:IsOnTaxi()
    if onTaxi and not self.wasOnTaxi then self:TaxiStarted() end
    if not onTaxi and self.wasOnTaxi then self:TaxiEnded() end
    self.wasOnTaxi = onTaxi
    if onTaxi then return end
    self:SampleSpeed(Client:GetRunSpeed())
    local here, hereContinent, hereX, hereY = self:PlayerPosition()
    local levelChanged = here and self:TrackLevels(here, hereContinent, hereX, hereY)
    if not self.node then return end
    if self.frozen then return self:WatchDock() end
    if levelChanged then return self:Replan("lift") end
    -- Across, but still aboard: the loading screen comes mid-crossing and
    -- the boat sails on to its dock. Nothing is planned until the player
    -- moves on their own feet.
    if self.aboard then
        local own = Client:GetMoveSpeed()
        if own == nil or own > 0 then
            self.aboard = false
            log("dock", { state = "ashore" })
            return self:Replan("ashore")
        end
        return
    end
    if now() >= (self.teleportCheckAt or 0) then
        self.teleportCheckAt = now() + self.teleportCheck
        if self:CheckTeleports() then return end
    end
    local from, continent, wx, wy = self:PlayerPosition()
    if not from then return end
    local last = self.lastFrom
    local moved
    if last and continent and last.continent == continent and wx and last.wx then
        local dx, dy = wx - last.wx, wy - last.wy
        moved = math.sqrt(dx * dx + dy * dy) > travel().replanYards
    else
        moved = not last or last.map ~= from.map
    end
    if moved then return self:Replan("moved") end
    local places = self:Places(self.guide)
    if #places > 0 then
        local key = travel():Locate(from, places, { world = function(map, x, y) return Client:GetWorldPosition(map, x, y) end,
            indoors = Client:IsIndoors(), lastConnection = self.attachment })
        if key ~= self.attachmentKey then self:Replan("passage") end
    end
end

-- The choice after the one followed now, round to the default again. None
-- while on a taxi: the flight is under way, nothing can be planned until it
-- lands, and a pick made in the air would only drop the route.
function TravelRoute:NextChoice()
    if client():IsOnTaxi() then return nil end
    local plan = self.plan
    local list = plan and plan.choices or {}
    if #list < 2 then return nil end
    for index, choice in ipairs(list) do
        if choice.id == plan.choice then return list[index % #list + 1] end
    end
    return list[1]
end

-- The routes on offer for this node, the one followed among them (its id is
-- `plan.choice`), for the arrow's menu: nil when the route does not follow
-- the node, on a taxi, or with nothing to pick between.
function TravelRoute:Choices(node)
    if not node or node ~= self.node or not self.plan or client():IsOnTaxi() then return nil end
    local list = self.plan.choices or {}
    if #list < 2 then return nil end
    return list, self.plan.choice
end

-- The player picks a route on offer by its id (a teleport, walking, or back
-- to the default), for this step only: the route is the player's call.
function TravelRoute:PickChoice(node, id)
    node = node or self.node
    local list, current = self:Choices(node)
    if not list or id == current then return end
    local picked
    for _, choice in ipairs(list) do if choice.id == id then picked = choice end end
    if not picked then return end
    log("choice", { from = current, to = picked.id, outline = picked.outline })
    self.choiceNode = node
    self.choice = picked.id ~= "default" and picked.id or nil
    self.plan = nil
    self:Replan("choice")
    self:Changed()
end

-- The next route on offer, round to the default again: a click on the
-- route line.
function TravelRoute:CycleChoice(node)
    node = node or self.node
    if node ~= self.node then return end
    local nextChoice = self:NextChoice()
    if nextChoice then self:PickChoice(node, nextChoice.id) end
end

-- The route for this node in two parts: the route followed ("fly
-- Crossroads > walk (~2m20s, walking ~8m)") and what a click would switch to
-- ("hearth > walk (~40s)"), or nil when the route is one straight walk and
-- there is nothing else to pick.
function TravelRoute:RouteParts(node)
    if not node or node ~= self.node or not self.plan then return nil end
    local plan = self.plan
    local nextChoice = self:NextChoice()
    if plan.direct and not nextChoice then return nil end
    local offer = nextChoice and (nextChoice.outline .. " (~" .. travel().FormatSeconds(nextChoice.cost) .. ")") or nil
    return plan.summary, offer
end

-- The tracker's muted route line under the current step, or nil.
function TravelRoute:RouteLine(node)
    local summary, offer = self:RouteParts(node)
    if not summary then return nil end
    return "Route: " .. summary .. (offer and (" - click: " .. offer) or "")
end

-- What a teleport leg asks the player to press: the hearthstone while it is
-- in the bags, else the spell. `{ icon, macro, itemID or spellID }`, or nil.
function TravelRoute:TeleportAction(leg)
    if not leg or leg.kind ~= "teleport" then return nil end
    local Client = client()
    if leg.item and Client:GetItemCount(leg.item) > 0 then
        return { itemID = leg.item, icon = Client:GetItemIcon(leg.item), macro = "/use item:" .. leg.item }
    end
    if leg.spell then
        local name = Client:GetSpellName(leg.spell)
        if name then return { spellID = leg.spell, icon = Client:GetSpellIcon(leg.spell), macro = "/cast " .. name } end
    end
    return nil
end

-- The click on a teleport leg: a secure macro button laid over the icon in
-- the arrow window. It is its own frame on UIParent, not a child of the
-- arrow window, since a frame holding a protected button becomes protected
-- itself and the arrow window shows, hides and resizes all the time. A
-- secure button can only be shown, hidden, moved or given a new macro out of
-- combat, so every change waits for combat to end (PLAYER_REGEN_ENABLED);
-- meanwhile the arrow says "Click after combat".
function TravelRoute:TeleportButton()
    if self.button then return self.button end
    local ok, button = pcall(CreateFrame, "Button", nil, UIParent, "SecureActionButtonTemplate")
    if not ok or not button then return nil end
    button:SetAttribute("type", "macro")
    if button.RegisterForClicks then button:RegisterForClicks("AnyDown") end
    -- The kit's tooltip (the addon's UI, made when first hovered: the saved
    -- variables are in by then). The button itself is no kit widget: a
    -- secure frame is never pooled.
    button:SetScript("OnEnter", function()
        local action = self.buttonAction
        if not action then return end
        ns:GetUI():Tooltip(button, function(tip)
            local shown
            if action.itemID and tip.SetItemByID then shown = pcall(tip.SetItemByID, tip, action.itemID) end
            if not shown and action.spellID and tip.SetSpellByID then shown = pcall(tip.SetSpellByID, tip, action.spellID) end
            if not shown then tip:SetText(self.buttonText or "Teleport", 1, 1, 1) end
        end, { anchor = "ANCHOR_RIGHT" })
    end)
    button:SetScript("OnLeave", function() if ns.UI then ns.UI:HideTooltip() end end)
    pcall(button.SetHighlightTexture, button, "Interface/Buttons/ButtonHilight-Square", "ADD")
    button:Hide()
    self.button = button
    return button
end

-- Whether the button over the icon is the current leg's, clickable now.
function TravelRoute:TeleportButtonReady()
    return self.buttonKey ~= nil and not self.buttonPending
end

-- Puts the button over the arrow window's icon for the current teleport
-- leg, or away. Out of combat only; in combat it waits.
function TravelRoute:SyncTeleportButton()
    local button = self:TeleportButton()
    if not button then return end
    local Navigation = ns.modules.Navigation
    local frame = Navigation and Navigation.frame
    local leg = self:Leg(self.node)
    local action = frame and frame:IsShown() and frame.teleportIcon and frame.teleportIcon:IsShown() and self:TeleportAction(leg)
    local key
    if action then
        local x, y = frame.teleportIcon:GetCenter()
        if x then key = action.macro .. "@" .. math.floor(x) .. "," .. math.floor(y) else action = nil end
    end
    if key == self.buttonKey and not self.buttonPending then return end
    if client():InCombatLockdown() then
        self.buttonPending = true
        return
    end
    self.buttonPending = false
    self.buttonKey = key
    if not action then
        button:Hide()
        self.buttonAction = nil
        return
    end
    local scale = frame.teleportIcon:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y = frame.teleportIcon:GetCenter()
    local width, height = frame.teleportIcon:GetSize()
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
    button:SetSize(width * scale, height * scale)
    button:SetFrameStrata(frame:GetFrameStrata())
    button:SetFrameLevel(frame:GetFrameLevel() + 10)
    button:SetAttribute("macrotext", action.macro)
    self.buttonAction, self.buttonText = action, leg.text
    button:Show()
    log("button", { macro = action.macro })
end

-- Seconds before the current teleport leg can be cast, or nil.
function TravelRoute:TeleportWait(leg)
    if not leg or leg.kind ~= "teleport" then return nil end
    return client():TeleportCooldown(leg.row)
end

------------------------------------------------------------------------------
-- Flight masters

-- The glow over one of Blizzard's taxi buttons (not a kit widget, so drawn
-- here), in the look's accent: coloured each time it is shown, so a look
-- changed since the last flight map is followed.
local function glow(button)
    local texture = button.nuuRoadGlow
    if not texture then
        texture = button:CreateTexture(nil, "OVERLAY")
        texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        pcall(texture.SetBlendMode, texture, "ADD")
        local width, height = button:GetSize()
        texture:SetSize((width or 16) * 2.4, (height or 16) * 2.4)
        texture:SetPoint("CENTER")
        button.nuuRoadGlow = texture
    end
    local accent = ns:GetUI().tokens.accent or { 0.3, 0.79, 0.94 }
    texture:SetVertexColor(accent[1], accent[2], accent[3], 1)
    return texture
end

-- Marks the button of the flight the current leg takes. Never clicks it:
-- where to fly is the player's call (some guide addons' autotaxi and flight
-- automation call TakeTaxiNode; NuuRoad does not).
function TravelRoute:HighlightTaxi()
    if not self.taxiOpen and not self.glowing then return end
    self.glowing = self.taxiOpen
    local Client = client()
    local leg = self:Leg(self.node)
    local wanted = self.taxiOpen and self:Settings().highlight ~= false and leg and leg.kind == "flight" and leg.toKey
    local buttons, matched = Client:GetTaxiButtons(), nil
    for _, entry in ipairs(buttons) do
        local match = wanted and travel().FlightKey(entry.name) == wanted
        if match then
            matched = entry.name
            glow(entry.button):Show()
        elseif entry.button.nuuRoadGlow then entry.button.nuuRoadGlow:Hide() end
    end
    if self.taxiOpen then self.lastHighlight = { wanted = wanted or nil, matched = matched } end
    if self.taxiOpen and not self.highlightLogged then
        self.highlightLogged = true
        log("highlight", { wanted = wanted or "<no flight leg>", matched = matched or "<none>", buttons = #buttons })
    end
end

function TravelRoute:OnTaxiMapOpened()
    self.taxiOpen, self.highlightLogged = true, false
    local Client = client()
    -- Learn the flights first and plan with them, so the destination glows on
    -- this opening rather than the next one.
    Client:RecordFlightPathsFromTaxiMap()
    local origin = Client:RecordReachableFlights()
    if origin then self.taxiOrigin, self.taxiOriginAt = origin, now() end
    local reachable = origin and Client:ReachableFlights()[travel().FlightKey(origin)]
    local known = {}
    for name in pairs(Client:FlightPathStore()) do table.insert(known, name) end
    table.sort(known)
    log("taximap", { origin = origin or "<unnamed>", reachable = reachable, known = known,
        packaged = origin and self:PackagedFlight(origin) or false })
    self:Replan("taxi map")
    self:HighlightTaxi()
end

function TravelRoute:OnTaxiMapClosed()
    self.taxiOpen = false
    self:HighlightTaxi()
    -- A flight path may have been learned just now.
    if not client():IsOnTaxi() then self:Replan("flight path") end
end

-- Whether `Data/Travel.lua` has this flight master: one it does not is known
-- to the player but invisible to the planner.
function TravelRoute:PackagedFlight(name)
    local key = travel().FlightKey(name)
    for _, row in ipairs(ns.travel and ns.travel.flights or {}) do
        if travel().FlightKey(row.name) == key then return true end
    end
    return false
end

-- The flight master a taxi was taken to, by the name the taxi map gives.
function TravelRoute:OnTakeTaxi(name)
    self.taxiDestination, self.taxiDestinationAt = name, now()
    log("taxi", { state = "taken", to = name })
end

function TravelRoute:TaxiStarted()
    local leg = self:Leg(self.node)
    if leg and leg.kind == "flight" then leg.boarded = true end
    -- Taking a flight is the player's route: a pick made before it (walking,
    -- a hearth) is spent, and the landing plans from the default.
    if self.choice and self.choiceNode == self.node then
        log("choice", { from = self.choice, to = "default", why = "taxi taken" })
        self.choiceNode, self.choice = nil, nil
    end
    local origin = self.taxiOrigin and now() - (self.taxiOriginAt or 0) < 60 and self.taxiOrigin or nil
    local destination = self.taxiDestination and now() - (self.taxiDestinationAt or 0) < 60 and self.taxiDestination or nil
    log("taxi", { state = "started", from = origin or "<unknown>", to = destination,
        leg = leg and leg.kind ~= "walk" and leg.text or nil })
    self.flight = { from = origin and travel().FlightKey(origin), at = now(), toName = destination,
        to = destination and travel().FlightKey(destination) }
    self.taxiOrigin, self.taxiDestination = nil, nil
end

-- The flight the player is on, for the arrow window: where it lands, what
-- to call it, and how long it takes if that has been timed. From the
-- destination clicked on the taxi map; else from the route's own leg (a
-- druid's flight is not taken from a taxi map); else nil.
function TravelRoute:CurrentFlight()
    local flight = self.flight
    if not client():IsOnTaxi() then return nil end
    if flight and flight.to then
        for _, row in ipairs(ns.travel and ns.travel.flights or {}) do
            if travel().FlightKey(row.name) == flight.to then
                local x, y = travel().Normalize(row.at[1], row.at[2])
                local times = flight.from and ns.db.travel and ns.db.travel.flightTimes
                    and ns.db.travel.flightTimes[flight.from .. ">" .. flight.to]
                local total
                if type(times) == "table" and #times > 0 then
                    local sorted = {}
                    for index, value in ipairs(times) do sorted[index] = value end
                    table.sort(sorted)
                    total = sorted[math.floor((#sorted + 1) / 2)]
                end
                return { name = (row.name:gsub(",.*$", "")), spot = { mapID = row.map, x = x, y = y, arrivalYards = 60 },
                    at = flight.at, total = total }
            end
        end
        return { name = (flight.toName:gsub(",.*$", "")), at = flight.at }
    end
    local leg = self:Leg(self.node)
    if leg and leg.kind ~= "walk" and leg.kind ~= "teleport" and leg.dest then
        return { name = (leg.text or "the landing"):gsub("^Fly to ", ""):gsub("^Take the %a+ to ", ""), spot = leg.dest,
            at = flight and flight.at }
    end
    return flight and { name = nil, at = flight.at } or nil
end

-- Seconds left on a flight: the timed length less the time flown when it
-- has been timed, else the straight distance left at taxi speed.
function TravelRoute:FlightRemaining(flight, yardsLeft)
    if flight.total and flight.at then return math.max(0, flight.total - (now() - flight.at)) end
    if yardsLeft then return yardsLeft * travel().flightDetour / travel().flightSpeed end
    return nil
end

-- Landing: the flight time is saved against the flight master the player
-- landed beside, and the route is planned again from here.
function TravelRoute:TaxiEnded()
    for area in pairs(self.below or {}) do self:SetBelow(area, false, "landed") end
    self.levelFrom = nil
    local flight = self.flight
    self.flight = nil
    local from, continent, wx, wy = self:PlayerPosition()
    if flight and flight.from and from and continent then
        local Client = client()
        local best, bestDistance
        for _, row in ipairs(ns.travel and ns.travel.flights or {}) do
            local x, y = travel().Normalize(row.at[1], row.at[2])
            local c, rx, ry = Client:GetWorldPosition(row.map, x, y)
            if c == continent then
                local dx, dy = rx - wx, ry - wy
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance < 100 and (not bestDistance or distance < bestDistance) then best, bestDistance = row, distance end
            end
        end
        local seconds = math.floor(now() - flight.at + 0.5)
        log("taxi", { state = "landed", from = flight.from, near = best and best.name or "<no packaged flight master within 100 yd>",
            nearYards = round(bestDistance, 0), seconds = seconds })
        if best then
            local key = flight.from .. ">" .. travel().FlightKey(best.name)
            if seconds > 5 then
                ns.db.travel = ns.db.travel or { flightTimes = {} }
                local times = ns.db.travel.flightTimes[key] or {}
                table.insert(times, seconds)
                while #times > self.maxHistory do table.remove(times, 1) end
                ns.db.travel.flightTimes[key] = times
            end
        end
    end
    local leg = self:Leg(self.node)
    -- The arrow's own watch may have seen the landing first and planned
    -- again; a flight leg not yet boarded belongs to that new plan.
    if leg and leg.kind == "flight" and leg.boarded then self:Advance(true, "taxi ended")
    elseif not (leg and leg.kind == "flight") then self:Replan("landed") end
end

function TravelRoute:OnSpellCast(unit, _, spellID)
    if unit ~= "player" then return end
    if type(spellID) ~= "number" or client():IsSecret(spellID) then return end
    local leg = self:Leg(self.node)
    for _, row in ipairs(ns.travel and ns.travel.teleports or {}) do
        if row.spell == spellID then
            log("cast", { spell = spellID, label = row.label, legSpell = leg and leg.spell or nil })
        end
    end
    if leg and leg.kind == "teleport" and spellID == leg.spell then self:Advance(false, "cast") end
end

function TravelRoute:OnZoneChanged(event)
    if event == "LOADING_SCREEN_DISABLED" then
        for area in pairs(self.below or {}) do self:SetBelow(area, false, "loading screen") end
        self.levelFrom = nil
    end
    local leg = self:Leg(self.node)
    log("zone", { cause = event, locked = self.frozen or nil })
    local wasLocked = self.frozen
    self.frozen = false
    if leg and leg.kind == "link" then
        local _, continent = self:PlayerPosition()
        if continent and leg.startContinent and continent ~= leg.startContinent then
            self.aboard = wasLocked and self.carried or nil
            return self:Advance(true, "continent changed")
        end
    end
    self:Replan("zone")
end

-- Once a session: what the client answers to every call the planner leans
-- on, so the API matrix can be filled in from the log alone.
function TravelRoute:Probe()
    if self.probed then return end
    self.probed = true
    local Client = client()
    local row = { apis = {} }
    for _, name in ipairs({ "GetUnitSpeed", "IsIndoors", "GetBindLocation", "UnitOnTaxi", "NumTaxiNodes", "TaxiNodeName",
        "TaxiNodeGetType", "GetPlayerFacing", "IsPlayerSpell", "GetItemCooldown" }) do
        row.apis[name] = type(rawget(_G, name)) == "function"
    end
    row.apis["C_Map.GetWorldPosFromMapPos"] = C_Map ~= nil and C_Map.GetWorldPosFromMapPos ~= nil
    row.apis["C_Map.GetMapInfoAtPosition"] = C_Map ~= nil and C_Map.GetMapInfoAtPosition ~= nil
    row.apis["C_Container.GetItemCooldown"] = C_Container ~= nil and C_Container.GetItemCooldown ~= nil
    local getter = rawget(_G, "GetUnitSpeed")
    if type(getter) == "function" then
        local ok, current, run, flight, swim = pcall(getter, "player")
        row.unitSpeed = ok and { current = current, run = run, flight = flight, swim = swim } or "<error>"
    end
    row.indoors = Client:IsIndoors()
    row.height = Client:GetPlayerHeight() or "<nil>"
    row.bind = Client:GetBindLocation() or "<nil>"
    row.faction, row.class = Client:GetPlayerFaction(), Client:GetPlayerClass()
    local from, continent, wx, wy = self:PlayerPosition()
    row.world = from and { continent = continent, x = round(wx, 1), y = round(wy, 1) } or "<no position>"
    -- Durotar inside Orgrimmar, and out on the plain; Mulgore under
    -- Thunder Bluff's mesa, and at Bloodhoof.
    row.mapAt = {}
    for _, probe in ipairs({ { 1411, 0.46, 0.14 }, { 1411, 0.30, 0.30 }, { 1412, 0.36, 0.30 }, { 1412, 0.47, 0.61 } }) do
        table.insert(row.mapAt, { spot = spotOf(probe[1], probe[2], probe[3]),
            answer = Client:GetMapAtPosition(probe[1], probe[2], probe[3]) or "<nil>" })
    end
    row.teleports = {}
    for _, teleport in ipairs(ns.travel and ns.travel.teleports or {}) do
        table.insert(row.teleports, { label = teleport.label, cooldown = Client:TeleportCooldown(teleport) or "<unusable>" })
    end
    log("probe", row)
end

-- For `/nuuroad where` and the bug report.
function TravelRoute:DiagnosticLines()
    local lines = {}
    local plan = self.plan
    table.insert(lines, "Travel route: " .. (plan and plan.summary or ("none (" .. tostring(self.why or "no plan") .. ")"))
        .. "; last planned for: " .. tostring(self.lastReason))
    if plan then
        for index, leg in ipairs(plan.legs) do
            table.insert(lines, string.format("  %s%d. %s %s (%ds)", index == self.index and ">" or " ", index, leg.kind,
                leg.text or (leg.final and "to the step" or ""), math.floor((leg.cost or 0) + 0.5)))
        end
    end
    if plan then
        for _, choice in ipairs(plan.choices) do
            table.insert(lines, string.format("  %s %s: %s (%ds)", choice.id == plan.choice and "*" or " ", choice.id,
                choice.outline, math.floor(choice.cost + 0.5)))
        end
    end
    local bind, known = self:BindState()
    table.insert(lines, "  hearth: " .. (bind and (bind .. (known and " (known inn)"
        or " (not in Data/Travel.lua inns: no hearth is offered)")) or "not bound, or the client will not say"))
    local below = {}
    for area in pairs(self.below or {}) do table.insert(below, area) end
    table.insert(lines, "  below: " .. (#below > 0 and table.concat(below, ", ") or "nothing"))
    table.insert(lines, string.format("  run speed %.1f yd/s; passage %s; frozen %s; picked %s",
        self.speed or 7, tostring(self.attachmentKey), tostring(self.frozen), tostring(self.choice or "default")))
    return lines
end

------------------------------------------------------------------------------
-- Settings, and routes asked for from outside

-- Config:Changed tells every module; a travel switch (navigation.travel.*,
-- or the whole group, or every setting at once) plans again, as OpenRoad's
-- Config:Changed did. The highlight switch is read by the taxi map's glow,
-- which is painted again at once while the map is open.
function TravelRoute:OnSettingChanged(path)
    if path ~= nil and path ~= "navigation" and path:sub(1, 17) ~= "navigation.travel" then return end
    self:Replan("options")
    self:HighlightTaxi()
end

-- A place as NuuRoad.API.Route hands it in: `{ mapID, x, y, label, npcID }`,
-- x and y as fractions of the map (0-1) or as percentages (above 1). Nil
-- and why when it cannot be placed.
function TravelRoute.TargetNode(target)
    if type(target) ~= "table" then return nil, "no target" end
    local mapID, x, y = tonumber(target.mapID), tonumber(target.x), tonumber(target.y)
    if not mapID or not x or not y then return nil, "a target needs mapID, x and y" end
    if x > 1 or y > 1 then x, y = x / 100, y / 100 end
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil, "x and y are outside the map" end
    local Navigation = ns.modules.Navigation
    local node = Navigation and Navigation.WaypointNode and Navigation.WaypointNode(mapID, x, y)
        or { kind = "travel", bead = "accent", location = { mapID = mapID, x = x, y = y, arrivalYards = 10 } }
    node.title = type(target.label) == "string" and target.label ~= "" and target.label
        or node.title or string.format("Waypoint %.1f, %.1f", x * 100, y * 100)
    node.npcID = tonumber(target.npcID)
    return node
end

-- The route to any place, for NuuRoad.API.Route and other addons: the arrow
-- is pointed at it (as `/nuuroad way` does, so it is put away on arrival)
-- and the planner routes there. Without the arrow the route is planned
-- alone. True, or false and why not. Like every route, only a suggestion.
function TravelRoute:RouteTo(target)
    local node, problem = TravelRoute.TargetNode(target)
    if not node then return false, problem end
    self.requested = node
    log("request", { target = spotOf(node.location.mapID, node.location.x, node.location.y), label = node.title,
        npc = node.npcID })
    local Navigation = ns.modules.Navigation
    if Navigation and Navigation.Retarget then
        Navigation.waypoint = node
        Navigation:Retarget()
    else
        self:Sync(node, nil)
    end
    return true
end

-- Stops the route RouteTo asked for, if it is still the one followed: the
-- arrow goes back to the guide's step. True when there was one to stop.
function TravelRoute:StopRoute()
    local node = self.requested
    self.requested = nil
    if not node then return false end
    local Navigation = ns.modules.Navigation
    local stopped = false
    if Navigation and Navigation.waypoint == node then
        Navigation:ClearWaypoint()
        stopped = true
    elseif self.node == node then
        self:Sync(nil, nil)
        stopped = true
    end
    if stopped then log("request", { stopped = node.title }) end
    return stopped
end

-- Whether the route followed now is one RouteTo asked for.
function TravelRoute:IsRouting()
    local node = self.requested
    if not node then return false end
    local Navigation = ns.modules.Navigation
    return self.node == node or (Navigation ~= nil and Navigation.waypoint == node)
end

function TravelRoute:Initialize()
    -- Made at load, out of combat: a secure button cannot be set up in it.
    self:TeleportButton()
    client():HookTakeTaxi(function(name) self:OnTakeTaxi(name) end)
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "LOADING_SCREEN_DISABLED", "PLAYER_ENTERING_WORLD",
        "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "HEARTHSTONE_BOUND", "BAG_UPDATE_DELAYED", "LEARNED_SPELL_IN_TAB",
        "PLAYER_REGEN_ENABLED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    client():RegisterUnitEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "TAXIMAP_OPENED" then self:OnTaxiMapOpened()
        elseif event == "TAXIMAP_CLOSED" then self:OnTaxiMapClosed()
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then self:OnSpellCast(...)
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Changes to the teleport button waited for combat to end.
            if self.buttonPending then self:SyncTeleportButton() end
        elseif event == "BAG_UPDATE_DELAYED" or event == "HEARTHSTONE_BOUND" or event == "LEARNED_SPELL_IN_TAB" then
            -- A hearthstone found, bound elsewhere, or a teleport learned.
            if event == "HEARTHSTONE_BOUND" then self:Replan("teleports") else self:CheckTeleports() end
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- The position the client reports here is the one from before
            -- the loading screen; LOADING_SCREEN_DISABLED follows with the
            -- real one.
            self:Probe()
            log("zone", { cause = event, locked = self.frozen or nil })
        else
            self:OnZoneChanged(event)
        end
    end)
    local elapsedTotal = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < self.interval then return end
        elapsedTotal = 0
        self:Tick()
    end)
    self.events = frame
end

ns:RegisterModule("TravelRoute", TravelRoute)
