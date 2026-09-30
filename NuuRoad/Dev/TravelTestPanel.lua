local _, ns = ...

-- The in-game tests of the travel planner (TRAVEL.md), for developers:
-- `/nuuroad traveltest`. The window opens on a list of short tests, each
-- about one thing and each saying where to stand before it starts, so a
-- failure is rerun on its own. Loading a test loads its step guide when it
-- has one (Data/BuiltIn/TravelTestFixtures.lua): what a guide adds - the
-- tracker's route line, the numbered pins, a step done on arrival - is only
-- tested with one open, and what must work without one is tested without.
--
-- One step at a time the window says what to do, points the arrow (at a
-- waypoint, or at the guide's step), says what should happen, and checks what
-- it can against the planner live. The tester answers Pass, Fail or Skip,
-- with an optional note, or marks a spot without moving on. Every answer goes
-- to the recorder's `travel` channel with a snapshot of the route and the
-- player's position, so the run is its own report
-- (`Tools/SessionLog/sessions.py --channel travel`).
--
-- A test is `id`, `title`, `start` (where to stand first), optionally `guide`
-- (a packaged guide's ID), and `steps`. A step is `id`, `todo`, `expect`, and
-- one of:
--   target = { map, x, y, "title" }   a waypoint (map percentages), or
--            "bind" for the inn the hearthstone is set at;
--   guideStep = "label"                the test guide's step with that label;
--   neither                            the arrow is left as it is.
-- `arrive = true` finishes a waypoint step on arrival. `check` names what can
-- be judged from the planner, all of which must hold:
--   leg      pattern for the current leg's text ("" when the arrow points at
--            the target itself)
--   summary  pattern for the route
--   direct   true when the route must be one straight walk
--   choice   pattern for the route followed ("default", "walk", "teleport:1")
--   offers / withhold   pattern a route on offer must / must not match
--   glow     true when the flight map's destination button must glow
--   locked   the boat lock must be on (true) or off (false)
--   carried  true once the boat was seen carrying the player
--   innKnown true when the hearth's inn must be in the travel data
--   reason   pattern for why the route was last planned
--   below    an area's name the player must be known to be below, or false
--            when they must not be below anything
-- and what the arrow window itself shows (Navigation.display), since a right
-- plan drawn wrong is still wrong:
--   shows    the window's state: "traveling" (the arrow), "taxi" (the wing),
--            "teleport" (the icon), "arrived"
--   towards  what it measures to: "leg start", "landing" (of the flight or
--            boat the player is on), "target", "none"
--   clickable  true when a teleport's icon must be clickable now
--
-- The window is a kit window (NuuKit): the list, or one step of a test, is
-- built when the view changes (a test loaded, a step answered); what is live
-- (the checks, the route, where the arrow points) is changed in place on a
-- slow beat while the window is open.
local TravelTestPanel = { index = 1, interval = 0.5 }

local WIDTH, HEIGHT = 420, 620

TravelTestPanel.tests = {
    { id = "gates", title = "Orgrimmar gates", start = "Anywhere inside Orgrimmar.",
      steps = {
        { id = "leave-front", target = { 1411, 52, 44, "Test: Razor Hill" },
          todo = "Stand anywhere inside the city.",
          expect = "The arrow says 'Leave Orgrimmar by the front gate'.",
          check = { leg = "^Leave Orgrimmar by the front gate" } },
        { id = "west-gate-go", arrive = true, target = { 1454, 11, 66, "Test: the west gate (as the data has it)" },
          todo = "Walk to where the addon thinks the west gate is. If the arrow points into rock or nowhere near an exit, walk to the real western exit instead, stand in it, press 'Mark this spot', and then Fail.",
          expect = "The spot is in the western exit to the Barrens." },
        { id = "leave-west", target = { 1413, 45, 30, "Test: the Barrens" },
          todo = "Stand near the western exit, still inside the city.",
          expect = "The arrow says 'Leave Orgrimmar by the west gate' and points into the exit.",
          check = { leg = "^Leave Orgrimmar by the west gate" } },
        { id = "front-gate-go", arrive = true, target = { 1454, 49, 94, "Test: the front gate (as the data has it)" },
          todo = "Walk to the front gate.",
          expect = "The spot is in the gateway itself." },
        { id = "outside-walk", target = { 1411, 52, 44, "Test: Razor Hill" },
          todo = "Step just outside the front gate, onto Durotar.",
          expect = "A straight walk to Razor Hill: no 'Leave Orgrimmar'.",
          check = { direct = true } },
        { id = "enter-front", target = { 1454, 45.1, 63.9, "Test: Orgrimmar flight master" },
          todo = "Stay just outside the front gate.",
          expect = "The arrow says 'Enter Orgrimmar by the front gate'.",
          check = { leg = "^Enter Orgrimmar by the front gate" } },
      } },

    { id = "flight", title = "Flight master", guide = "nuuroad:fixture:travel-flight",
      start = "At the Orgrimmar flight master, before opening his map this session.",
      steps = {
        { id = "glow", guideStep = "crossroads",
          todo = "Talk to the flight master and open his map.",
          expect = "The Crossroads button glows on this first opening. Nothing is clicked for you.",
          check = { glow = true, summary = "^fly Crossroads" } },
        { id = "beads", guideStep = "crossroads",
          todo = "Close the flight map without flying. Open the world map on Durotar, then on the Barrens.",
          expect = "Small round beads at the Orgrimmar flight master and at the Crossroads landing, and the step's own numbered pin. (No lines are drawn.)",
          check = { summary = "^fly Crossroads" } },
        { id = "tracker-line", guideStep = "crossroads",
          todo = "In the NuuRoad window (the tracker, listing this guide's steps), under the current step 'Travel to the Crossroads', is a grey line starting 'Route:'. Click it.",
          expect = "The route switches to walking: the tracker's line says so and the arrow points straight at the Crossroads.",
          check = { choice = "^walk$" } },
        { id = "arrow-line", guideStep = "crossroads",
          todo = "Now right-click the arrow and pick 'fly Crossroads > walk'.",
          expect = "Back to the flight: 'fly Crossroads > walk' in both places.",
          check = { choice = "^default$", summary = "^fly Crossroads" } },
        { id = "in-flight", guideStep = "crossroads",
          todo = "Take the highlighted flight to the Crossroads. Answer while still flying, after half a minute.",
          expect = "The wing, and a distance to the Crossroads landing that shrinks as you fly (not to Orgrimmar's flight master, growing).",
          check = { shows = "taxi", towards = "landing" } },
        { id = "fly", guideStep = "crossroads",
          todo = "Answer after landing.",
          expect = "The wing while flying. The target is beside the flight master, so on landing the guide moves on to 'Flight test complete'." },
      } },

    { id = "zeppelin", title = "Undercity zeppelin", guide = "nuuroad:fixture:travel-zeppelin",
      start = "Just outside Orgrimmar's front gate. Takes a return trip to Tirisfal.",
      steps = {
        { id = "route", guideStep = "brill",
          todo = "Stand outside the front gate.",
          expect = "The route is 'walk > zeppelin > walk' and the arrow says 'Take the zeppelin to the Undercity', with no 'Leave Orgrimmar'.",
          check = { leg = "^Take the zeppelin to the Undercity" } },
        { id = "lock", guideStep = "brill",
          todo = "Follow the arrow up the tower to the Undercity zeppelin's platform. Note in the box how far the arrow's point was from where you board.",
          expect = "At the platform the route stops changing (the boat lock is on).",
          check = { locked = true } },
        { id = "walk-off", guideStep = "brill",
          todo = "Without boarding, walk 50 yards or more away from the platform (back down the tower).",
          expect = "The lock ends and the route is planned again.",
          check = { locked = false, reason = "^left the dock$" } },
        { id = "ride", guideStep = "brill",
          todo = "Go back up and board the Undercity zeppelin. Stand still on deck for 10 seconds, then walk about. Answer after the loading screen.",
          expect = "Nothing changes on board until the loading screen. The boat is seen carrying you, and the distance is to the far platform, not the one you left.",
          check = { carried = true, towards = "landing" } },
        { id = "landed", guideStep = "brill",
          todo = "Get off in Tirisfal.",
          expect = "The arrow leads straight to Brill.",
          check = { direct = true } },
        { id = "back", guideStep = "back",
          todo = "Take the zeppelin back to Orgrimmar. Answer once you are off it in Durotar.",
          expect = "Before boarding the arrow said 'Take the zeppelin to Orgrimmar'; after landing it says 'Enter Orgrimmar by the front gate'.",
          check = { leg = "^Enter Orgrimmar by the front gate" } },
      } },

    { id = "hearth", title = "Hearthstone, with a guide", guide = "nuuroad:fixture:travel-hearth",
      start = "At the Crossroads inn, with the hearthstone ready.",
      steps = {
        { id = "bind", guideStep = "bind",
          todo = "Set your hearthstone at the innkeeper.",
          expect = "The step completes, and the hearth is at an inn the travel data knows.",
          check = { innKnown = true } },
        { id = "fly-away", guideStep = "away",
          todo = "Fly to Orgrimmar from the Crossroads flight master. Answer after landing.",
          expect = "Orgrimmar glows on the flight map, and you land at the Orgrimmar flight master." },
        { id = "offer", guideStep = "home",
          todo = "Stand in Orgrimmar and look at the route in the tracker, then right-click the arrow.",
          expect = "The route is the flight. The tracker's line offers 'hearth > walk', and so does the arrow's right-click menu.",
          check = { choice = "^default$", offers = "^teleport" } },
        { id = "pick", guideStep = "home",
          todo = "Right-click the arrow and pick the hearth. Then walk 60 yards.",
          expect = "The arrow window says 'Hearth to The Crossroads' and shows the hearthstone in place of the arrow, with 'Click to use' and no distance. The pick stays after the walk.",
          check = { choice = "^teleport", shows = "teleport", clickable = true } },
        { id = "use", guideStep = "home",
          todo = "Click the hearthstone in the arrow window. Answer after landing.",
          expect = "The hearth casts from that click. You land at the Crossroads and the route is back to the default.",
          check = { choice = "^default$" } },
        { id = "cooldown", guideStep = "far",
          todo = "With the hearth on cooldown, look at the tracker's route line and right-click the arrow.",
          expect = "No hearth anywhere: nothing offers it.",
          check = { withhold = "^teleport" } },
      } },

    { id = "hearth-no-guide", title = "Hearthstone, no guide",
      start = "Far from the inn your hearth is set at (it must be the Crossroads, Camp Taurajo, Thunder Bluff, Bloodhoof or Orgrimmar), with the hearthstone ready.",
      steps = {
        { id = "tracker-closed", target = "bind",
          todo = "Close the NuuRoad window (the tracker).",
          expect = "The arrow stays up, and its right-click menu offers 'hearth > walk'.",
          check = { offers = "^teleport" } },
        { id = "pick", target = "bind",
          todo = "Right-click the arrow and pick the hearth.",
          expect = "The arrow window says 'Hearth to ...' and shows the hearthstone in place of the arrow, clickable, although no guide is open.",
          check = { choice = "^teleport", shows = "teleport", clickable = true } },
        { id = "use", target = "bind",
          todo = "Click the hearthstone in the arrow window. Answer after landing.",
          expect = "The hearth casts from that click. You land at the inn; the waypoint is reached and the arrow puts itself away." },
      } },

    { id = "druid", title = "Druid: Moonglade and back",
      start = "On a druid with Teleport: Moonglade ready, anywhere in Kalimdor far from Moonglade (Mulgore or Thunder Bluff is ideal).",
      steps = {
        { id = "teleport", target = { 1450, 44.29, 45.87, "Test: Bunthen Plainswind, Nighthaven" },
          todo = "Look at the arrow window.",
          expect = "No arrow and no distance: the Teleport: Moonglade spell icon stands in the arrow's place, with 'Click to use'. Its right-click menu offers walking instead.",
          check = { choice = "^default$", leg = "^Teleport: Moonglade", shows = "teleport", clickable = true } },
        { id = "combat", target = { 1450, 44.29, 45.87, "Test: Bunthen Plainswind, Nighthaven" },
          todo = "Optional: get into a fight with the icon showing, and look at it again once the fight is over. Skip if there is nothing to fight nearby.",
          expect = "After the fight the icon is still there and still clickable. No error about a blocked action.",
          check = { shows = "teleport", clickable = true } },
        { id = "cast", target = { 1450, 44.29, 45.87, "Test: Bunthen Plainswind, Nighthaven" },
          todo = "Click the spell icon in the arrow window. Answer once you are in Moonglade.",
          expect = "The cast goes through from the button. In Moonglade the route is a short walk to Bunthen Plainswind, and nothing is picked any more.",
          check = { choice = "^default$", direct = true } },
        { id = "druid-flight", target = { 1456, 45.81, 64.71, "Test: the Thunder Bluff inn" },
          todo = "Still in Moonglade, look at the arrow.",
          expect = "The arrow says 'Fly to Thunder Bluff' and points at Bunthen Plainswind.",
          check = { leg = "^Fly to Thunder Bluff" } },
        { id = "in-flight", target = { 1456, 45.81, 64.71, "Test: the Thunder Bluff inn" },
          todo = "Talk to Bunthen Plainswind and fly. Answer while still flying, after half a minute.",
          expect = "The wing, and a distance to the Thunder Bluff landing that shrinks as you fly (not to Nighthaven, growing).",
          check = { shows = "taxi", towards = "landing" } },
        { id = "landed", target = { 1456, 45.81, 64.71, "Test: the Thunder Bluff inn" },
          todo = "Answer after landing in Thunder Bluff.",
          expect = "After landing you count as on top of the mesa, and the arrow points straight to the inn.",
          check = { below = false, direct = true } },
      } },

    { id = "other-flight", title = "Flying somewhere else", guide = "nuuroad:fixture:travel-other-flight",
      start = "At the Crossroads flight master, with the Thunder Bluff flight path.",
      steps = {
        { id = "highlight", guideStep = "taurajo",
          todo = "Open the flight map.",
          expect = "Camp Taurajo glows.",
          check = { glow = true } },
        { id = "in-flight", guideStep = "taurajo",
          todo = "Fly to Thunder Bluff instead. Answer while still flying, after half a minute.",
          expect = "The arrow window shows the flight, not the route: 'Flying to Thunder Bluff', the wing, and a distance and time left that shrink as you fly.",
          check = { shows = "taxi", towards = "landing" } },
        { id = "elsewhere", guideStep = "taurajo",
          todo = "Answer after landing.",
          expect = "After landing the route is planned afresh from Thunder Bluff, and no leg is skipped." },
      } },

    { id = "lifts", title = "Thunder Bluff lifts", guide = "nuuroad:fixture:travel-lifts",
      start = "On top of Thunder Bluff, away from the west lift (only the west lift's bottom is recorded).",
      steps = {
        { id = "take-down", guideStep = "down",
          todo = "Stand on the mesa and look at the arrow.",
          expect = "The arrow says 'Take the west lift down' and points at the lift's top.",
          check = { leg = "^Take the west lift down" } },
        { id = "ride-down", guideStep = "down",
          todo = "Walk into the lift and ride it down. Answer once you step off at the bottom.",
          expect = "On the lift the arrow says 'Ride the west lift down'; at the bottom you are known to be below, and the arrow points straight to Bloodhoof.",
          check = { below = "Thunder Bluff", direct = true } },
        { id = "take-up", guideStep = "up",
          todo = "Walk 20 yards away from the lift, still at the foot of the mesa.",
          expect = "The arrow says 'Take the west lift up' and points at the lift's bottom, not at the cliff.",
          check = { below = "Thunder Bluff", leg = "^Take the west lift up" } },
        { id = "ride-up", guideStep = "up",
          todo = "Ride the lift up. Answer once you step off at the top.",
          expect = "At the top you are known to be on the mesa again, and the arrow points straight to the inn.",
          check = { below = false, direct = true } },
        { id = "walk-in", guideStep = "up",
          todo = "Take the lift down again, walk out onto Mulgore (off the Thunder Bluff map) and back towards the mesa's foot.",
          expect = "Walking back onto the Thunder Bluff map at ground level counts as below: the arrow says 'Take the west lift up'.",
          check = { below = "Thunder Bluff", leg = "^Take the west lift up" } },
      } },

    { id = "cave", title = "Bristleback cave", guide = "nuuroad:fixture:cave-place",
      start = "Mulgore, just south of the Bristleback cave's south mouth (59.7, 85). The cave's inside is a sketch: wrong turns inside are expected.",
      steps = {
        { id = "enter", guideStep = "den",
          todo = "Stand outside the cave.",
          expect = "The arrow leads in through a mouth, never up the hole.",
          check = { leg = "^Enter Bristleback cave" } },
        { id = "hill", guideStep = "den",
          todo = "Climb onto the hill above the cave.",
          expect = "The arrow still leads to a mouth, not straight down through the hill.",
          check = { leg = "^Enter Bristleback cave" } },
        { id = "out", guideStep = "camp",
          todo = "Go into the cave, then look at the arrow.",
          expect = "It leads out through a mouth or down the hole, whichever is shorter.",
          check = { leg = "^Leave" } },
      } },
}

------------------------------------------------------------------------------
-- Checks

local function route() return ns.modules.TravelRoute end

local function matchAny(list, pattern)
    for _, choice in ipairs(list or {}) do
        if tostring(choice.id):match(pattern) then return true end
    end
    return false
end

local function choiceIds(plan)
    local ids = {}
    for _, choice in ipairs(plan and plan.choices or {}) do table.insert(ids, choice.id) end
    return table.concat(ids, ", ")
end

-- Every check the step names, each true or false with what was seen.
-- Returns whether all hold (nil when the step has none), the lines ("ok  "
-- or "no  " and what was seen, plain text for the log) and whether each
-- line held.
function TravelTestPanel:Evaluate(check)
    if not check then return nil, {}, {} end
    local Route = route()
    local plan = Route and Route.plan
    local leg = Route and Route:Leg(Route.node)
    local lines, held, all = {}, {}, true
    local function add(ok, text)
        ok = ok and true or false
        all = all and ok
        table.insert(lines, (ok and "ok  " or "no  ") .. text)
        table.insert(held, ok)
    end
    local summary = plan and plan.summary or ("no route (" .. tostring(Route and Route.why) .. ")")
    if check.leg then
        local text = leg and leg.text or ""
        add(text:match(check.leg) ~= nil, "leg: " .. (text ~= "" and text or "(pointing at the target)"))
    end
    if check.summary then add(summary:match(check.summary) ~= nil, "route: " .. summary) end
    if check.direct ~= nil then
        add((plan and plan.direct or false) == check.direct, "route: " .. summary)
    end
    if check.choice then
        add(plan ~= nil and plan.choice:match(check.choice) ~= nil, "following: " .. tostring(plan and plan.choice))
    end
    if check.offers then add(matchAny(plan and plan.choices, check.offers), "on offer: " .. choiceIds(plan)) end
    if check.withhold then add(not matchAny(plan and plan.choices, check.withhold), "on offer: " .. choiceIds(plan)) end
    if check.glow then
        local highlight = Route and Route.lastHighlight
        add(highlight ~= nil and highlight.matched ~= nil, "glowing: " .. tostring(highlight and highlight.matched or "nothing"))
    end
    if check.locked ~= nil then
        add((Route and Route.frozen or false) == check.locked, "boat lock: " .. ((Route and Route.frozen) and "on" or "off"))
    end
    if check.carried then add(Route and Route.carried == true, "carried by the boat: " .. tostring(Route and Route.carried or false)) end
    if check.innKnown then
        local bind, known
        if Route then bind, known = Route:BindState() end
        add(known == true, "hearth: " .. tostring(bind or "not bound") .. (known and " (known inn)" or " (unknown inn)"))
    end
    if check.below ~= nil then
        local below = Route and Route.below or {}
        local names = {}
        for area in pairs(below) do table.insert(names, area) end
        local ok = check.below == false and #names == 0 or (check.below ~= false and below[check.below] == true)
        add(ok, "known to be below: " .. (#names > 0 and table.concat(names, ", ") or "nothing"))
    end
    local display = ns.modules.Navigation and ns.modules.Navigation.display or {}
    if check.shows then
        add(display.state == check.shows, "arrow window shows: " .. tostring(display.state)
            .. (display.status and (" (" .. tostring(display.status):gsub("\n", " ") .. ")") or ""))
    end
    if check.towards then
        add(display.towards == check.towards, "measures to: " .. tostring(display.towards)
            .. (display.yards and (", " .. display.yards .. " yd") or ""))
    end
    if check.clickable ~= nil then
        add((display.clickable or false) == check.clickable, "icon clickable: " .. tostring(display.clickable or false))
    end
    if check.reason then
        add(tostring(Route and Route.lastReason):match(check.reason) ~= nil, "last planned for: " .. tostring(Route and Route.lastReason))
    end
    return all, lines, held
end

-- What the planner is doing, for the log with each answer.
function TravelTestPanel:Snapshot()
    local Route = route()
    local plan = Route and Route.plan
    local leg = Route and Route:Leg(Route.node)
    local Navigation = ns.modules.Navigation
    return {
        route = plan and plan.summary or nil, why = Route and Route.why or nil,
        leg = leg and leg.text or nil, index = Route and Route.index or nil,
        following = plan and plan.choice or nil, offers = choiceIds(plan),
        locked = Route and Route.frozen or false, carried = Route and Route.carried or false,
        reason = Route and Route.lastReason or nil, speed = Route and Route.speed or nil,
        waypoint = Navigation and Navigation.waypoint and Navigation.waypoint.title or nil,
        below = Route and Route.below and next(Route.below) or nil,
        shows = Navigation and Navigation.display and Navigation.display.state or nil,
        towards = Navigation and Navigation.display and Navigation.display.towards or nil,
        status = Navigation and Navigation.display and Navigation.display.status or nil,
    }
end

------------------------------------------------------------------------------
-- Running a test

function TravelTestPanel:Step()
    return self.test and self.test.steps[self.index] or nil
end

function TravelTestPanel:Log(event, data)
    data = data or {}
    data.event = event
    ns:RecordHere("travel", data)
end

-- The inn the hearthstone is set at, as a waypoint target.
local function bindTarget()
    local Route = route()
    local bind = Route and Route:BindState()
    if not bind then return nil end
    local Travel = ns.modules.Travel
    for _, inn in ipairs(ns.travel and ns.travel.inns or {}) do
        if Travel.FlightKey(inn.name) == Travel.FlightKey(bind) then
            return { inn.map, inn.at[1], inn.at[2], "Test: " .. inn.name }
        end
    end
    return nil
end

-- The test's guide open on the step with this label. Opening it is
-- navigation only, the same as the tracker's jump box.
function TravelTestPanel:OpenGuideStep(label)
    local Progress, Repository = ns.modules.Progress, ns.modules.GuideRepository
    local guide = self.test.guide and Repository and Repository:Get(self.test.guide)
    if not guide then return false, "the test guide " .. tostring(self.test.guide) .. " is not loaded" end
    local active = Progress:GetActiveGuide()
    if not active or active.id ~= guide.id then Progress:Select(guide) end
    guide = Progress:GetActiveGuide() or guide
    for _, node in ipairs(guide.nodes) do
        if node.label == label then
            local current = Progress:GetCurrentNode(guide)
            if not current or current.index ~= node.index then Progress:GoTo(guide, node.index) end
            local MainWindow = ns.modules.MainWindow
            if MainWindow then
                if type(MainWindow.Landed) == "function" then MainWindow:Landed() end
                if type(MainWindow.Show) == "function" then MainWindow:Show() end
            end
            return true
        end
    end
    return false, "the test guide has no step labelled " .. label
end

-- Points the arrow for the step and says so in the log.
function TravelTestPanel:Start()
    local step = self:Step()
    if not step then return end
    local Navigation = ns.modules.Navigation
    self.ownWaypoint, self.problem = nil, nil
    local target = step.target == "bind" and bindTarget() or step.target
    if step.target == "bind" and not target then
        self.problem = "Your hearth is not set at an inn the travel data knows, so there is nowhere to point."
    end
    if type(target) == "table" and Navigation then
        -- The same place as the step before keeps its waypoint: a new one
        -- is a new destination, which resets the route picked for it.
        local current = Navigation.waypoint
        local location = current and current.location
        local same = location and location.mapID == target[1] and math.abs(location.x - target[2] / 100) < 1e-6
            and math.abs(location.y - target[3] / 100) < 1e-6
        if not same then Navigation:SetWaypoint(target[1], target[2] / 100, target[3] / 100, target[4]) end
        self.ownWaypoint = Navigation.waypoint
    elseif step.guideStep then
        if Navigation then Navigation:ClearWaypoint() end
        local ok, problem = self:OpenGuideStep(step.guideStep)
        if not ok then self.problem = "Cannot open the step: " .. problem end
    end
    self:Log("test", { test = self.test.id, step = step.id, result = "start", number = self.index })
    self:Render()
end

function TravelTestPanel:Answer(result)
    local step = self:Step()
    if not step then return end
    local ok, lines = self:Evaluate(step.check)
    local note = self.note and self.note:GetText() or ""
    local row = self:Snapshot()
    row.test, row.step, row.result, row.number = self.test.id, step.id, result, self.index
    row.note = note ~= "" and note or nil
    row.auto = ok == nil and "none" or (ok and "ok" or "no")
    row.checks = lines
    self:Log("test", row)
    if result == "flag" then
        if self.note then self.note:SetText("") end
        if self.win then self.win:Status("Spot marked for " .. self.test.id .. "/" .. step.id .. ".", { tone = "text" }) end
        return
    end
    self:Go(self.index + 1)
end

function TravelTestPanel:Go(index)
    if not self.test then return end
    if index < 1 then index = 1 end
    if index > #self.test.steps + 1 then index = #self.test.steps + 1 end
    self.index = index
    if self:Step() then self:Start() else
        self:Log("test", { test = self.test.id, result = "finished" })
        self:Render()
    end
end

-- Loads a test from the list: its guide, then its first step.
function TravelTestPanel:Load(test)
    self.test, self.index = test, 1
    self:Log("test", { test = test.id, result = "loaded", steps = #test.steps, guide = test.guide })
    self:Start()
end

-- Back to the list. A waypoint the test set is put away; a guide it opened
-- stays open.
function TravelTestPanel:ShowList()
    local Navigation = ns.modules.Navigation
    if self.ownWaypoint and Navigation and Navigation.waypoint == self.ownWaypoint then Navigation:ClearWaypoint() end
    self.test, self.ownWaypoint = nil, nil
    self:Render()
end

-- The slow beat: the live check, and an `arrive` step done on arrival (the
-- arrow drops a reached waypoint).
function TravelTestPanel:Tick()
    local step = self:Step()
    if not step then return end
    local Navigation = ns.modules.Navigation
    if step.arrive and self.ownWaypoint and Navigation and Navigation.waypoint ~= self.ownWaypoint then
        self.ownWaypoint = nil
        return self:Answer("arrived")
    end
    self:Refresh()
end

-- The player follows the next route on offer, as a click on the tracker's
-- route line.
function TravelTestPanel:SwitchRoute()
    local Route = route()
    if Route then Route:CycleChoice(Route.node) end
    self:Refresh()
end

------------------------------------------------------------------------------
-- The window

local function colorCode(key)
    local UI = ns.Kit.UI
    local t = ns.UI and ns.UI.tokens
    local color = t and t[key]
    return color and UI.ColorCode(color) or "|cffffffff"
end

-- The window's slow beat, on a frame of its own (the window is the kit's):
-- it runs only while the window is shown.
local function onUpdate(frame, elapsed)
    local panel = TravelTestPanel
    frame.elapsed = (frame.elapsed or 0) + elapsed
    if frame.elapsed < panel.interval then return end
    frame.elapsed = 0
    if panel.win and panel.win:IsShown() then panel:Tick() end
end

-- The window: its band's "All tests", a scrolling body for the list or the
-- step, and the answer below it, which stays in view however long the step's
-- text is.
function TravelTestPanel:Build()
    if self.win then return end
    local UI = ns:GetUI()
    local places = ns.db and ns.db.windows
    if not places then
        places = {}
        if ns.db then ns.db.windows = places end
    end
    local win = UI:Window({
        key = "traveltest", title = "Travel tests", width = WIDTH, height = HEIGHT, place = places,
        resizable = true, minWidth = 340, minHeight = 360, strata = "DIALOG", hidden = true,
        point = { "RIGHT", UIParent, "RIGHT", -40, 60 },
    })
    self.win = win
    self.listButton = win.header:Button{ "All tests", tooltip = "Back to the list of tests.",
        onClick = function() self:ShowList() end }
    local body = win:Column{ gap = 8, padding = 12 }
    self.area = body:ScrollArea{ grow = true }
    self.content = self.area:Column{ gap = 10 }
    self.footer = body:Column{ gap = 6 }
    self.ticker = CreateFrame("Frame", nil, UIParent)
    self.ticker:SetScript("OnUpdate", onUpdate)
end

-- Forgets the widgets of the view before, which clearing gives back.
function TravelTestPanel:ClearView()
    self.content:Clear()
    self.footer:Clear()
    self.note, self.targetText, self.checksText, self.liveText, self.switchButton, self.pointButton = nil, nil, nil, nil, nil, nil
end

-- The list: every test with where it starts.
function TravelTestPanel:RenderList()
    local win, content = self.win, self.content
    win:SetTitle("Travel tests")
    self.listButton:Hide()
    content:Text{ "Pick a test. Each is short and starts where it says; go there first. A test with a guide opens it.",
        color = "muted", wrap = true }
    for _, test in ipairs(self.tests) do
        local entry = content:Column{ gap = 3 }
        entry:Button{ test.title, onClick = function() self:Load(test) end }
        entry:Text{ string.format("%d steps%s. Start: %s", #test.steps, test.guide and ", with a guide" or ", no guide",
            test.start), style = "fine", wrap = true }
    end
end

-- One step of a test, or the test finished.
function TravelTestPanel:RenderStep()
    local win, content, footer = self.win, self.content, self.footer
    local step = self:Step()
    self.listButton:Show()
    local todo = content:Section{ "What to do" }
    if not step then
        win:SetTitle(self.test.title .. ": finished")
        todo:Text{ "Every step is answered. Pick another test from 'All tests', or log out: the answers are in the session log.",
            wrap = true }
    else
        win:SetTitle(string.format("%s, step %d of %d", self.test.title, self.index, #self.test.steps))
        todo:Text{ step.todo, wrap = true }
        self.targetText = todo:Text{ "", style = "fine", wrap = true }
        local expect = content:Section{ "What should happen" }
        expect:Text{ step.expect, wrap = true }
        local sees = content:Section{ "What the addon sees" }
        self.checksText = sees:Text{ "", wrap = true }
        self.liveText = sees:Text{ "", style = "fine", wrap = true }
        local actions = sees:Row{ gap = 6 }
        self.switchButton = actions:Button{ "Switch route",
            tooltip = "Follow the next route on offer, the same as clicking the tracker's route line.",
            onClick = function() self:SwitchRoute() end }
        if step.target ~= nil or step.guideStep ~= nil then
            self.pointButton = actions:Button{ "Point the arrow again",
                tooltip = "Set the arrow back on this step (its waypoint, or the guide's step).",
                onClick = function() self:Start() end }
        end

        footer:Text{ "Your answer", style = "heading" }
        self.note = footer:Input{ placeholder = "Optional note: type it before pressing a button" }
        local answers = footer:Row{ gap = 6 }
        answers:Button{ "Pass", tone = "accent", tooltip = "It did what 'What should happen' says. Goes to the next step.",
            onClick = function() self:Answer("pass") end }
        answers:Button{ "Fail", tooltip = "It did not. Write what went wrong in the note first. Goes to the next step.",
            onClick = function() self:Answer("fail") end }
        answers:Button{ "Skip", tooltip = "Not tested. Goes to the next step.", onClick = function() self:Answer("skip") end }
        answers:Spacer{}
        answers:Button{ "Mark this spot",
            tooltip = "Logs where you stand and the note, and stays on this step. For 'the real gate is here'.",
            onClick = function() self:Answer("flag") end }
    end
    local moves = footer:Row{ gap = 6 }
    moves:Button{ "< Previous step", tooltip = "Go back a step without answering.", onClick = function() self:Go(self.index - 1) end }
    moves:Spacer{}
    moves:Button{ "Next step >", tooltip = "Go on without answering.", onClick = function() self:Go(self.index + 1) end }
end

-- Builds the view again: the list, or the step. Only while shown; showing
-- the window builds it.
function TravelTestPanel:Render()
    local win = self.win
    if not win or not win:IsShown() then return end
    self:ClearView()
    win:Status(nil)
    if self.test then self:RenderStep() else self:RenderList() end
    self:Refresh()
    self.area:ScrollToTop()
end

-- Where the step points the arrow, from here.
function TravelTestPanel:TargetLine(step)
    if self.problem then return colorCode("danger") .. self.problem .. "|r" end
    local Navigation = ns.modules.Navigation
    if step.guideStep then
        return "The arrow follows the test guide's step '" .. step.guideStep .. "' (open in the tracker)."
    end
    if not step.target or not Navigation then return "" end
    local waypoint = Navigation.waypoint
    if not waypoint or waypoint ~= self.ownWaypoint then
        if step.arrive and not self.ownWaypoint then return "Arrived." end
        return "The arrow is not on this step's place: press 'Point the arrow again'."
    end
    local label = Navigation.Measure and Navigation:Measure(waypoint.location)
    return "Arrow target: " .. (waypoint.title or ""):gsub("^Test: ", "") .. (label and (", " .. label) or "")
        .. (step.arrive and ". This step finishes by itself when you get there." or "")
end

-- What changes as the player moves, changed in place.
function TravelTestPanel:Refresh()
    local step = self:Step()
    if not step or not self.checksText then return end
    self.targetText:SetText(self:TargetLine(step))
    local ok, lines, held = self:Evaluate(step.check)
    if ok == nil then
        self.checksText:SetText("Nothing to check automatically on this step: judge by eye.")
    else
        local good, bad = colorCode("done"), colorCode("danger")
        local shown = { ok and (good .. "Matches.|r") or (bad .. "Does not match yet.|r") }
        for index, line in ipairs(lines) do
            shown[#shown + 1] = (held[index] and good or bad) .. line:sub(1, 2) .. "|r" .. line:sub(3)
        end
        self.checksText:SetText(table.concat(shown, "\n"))
    end
    local snapshot = self:Snapshot()
    self.liveText:SetText("Route now: " .. tostring(snapshot.route or ("none (" .. tostring(snapshot.why) .. ")"))
        .. "\nArrow says: " .. (snapshot.leg or "the target itself"))
    local Route = route()
    local plan = Route and Route.plan
    self.switchButton:SetShown(plan ~= nil and #(plan.choices or {}) > 1)
end

function TravelTestPanel:Toggle()
    self:Build()
    if self.win:IsShown() then
        self.win:Hide()
        return
    end
    self.win:Show()
    self:Render()
end

ns:RegisterModule("TravelTestPanel", TravelTestPanel)
