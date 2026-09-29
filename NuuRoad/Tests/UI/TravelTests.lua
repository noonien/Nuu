-- The travel planner in the running game (UI/TravelRoute.lua) and the travel
-- test window (Dev/TravelTestPanel.lua), on the kit's stand-in for the client.
-- The client's map, position, faction, speed, taxi and clock calls are
-- stubbed here (and put back at the end, so a later suite sees the
-- stand-in as it was): a small world where Orgrimmar sits in the north of
-- Durotar and the Barrens lie west of it, on one continent. The player
-- stands at the Orgrimmar flight master with the travel-flight fixture's
-- step to reach the Crossroads: the route is planned, the choice cycled, a
-- setting change plans again, the flight map glows, a flight is timed, a
-- route to any place is asked for and stopped, and the test window is
-- driven through a test.
local ctx = dofile("Tests/UI/Harness.lua")
local ns, check, settle = ctx.ns, ctx.check, ctx.settle
local Route, Panel, Client = ns.modules.TravelRoute, ns.modules.TravelTestPanel, ns.modules.Client
check(Route and Panel and Client, "TravelRoute, TravelTestPanel and Client are loaded")

-- Stubs --------------------------------------------------------------------------------------

local STUBS = { "C_Map", "CreateVector2D", "UnitFactionGroup", "UnitClass", "GetUnitSpeed", "UnitOnTaxi", "GetTime",
    "GetBindLocation", "NumTaxiNodes", "TaxiNodeName", "TaxiNodeGetType", "TaxiButton1", "TaxiButton2" }
local saved = {}
for _, name in ipairs(STUBS) do saved[name] = rawget(_G, name) end
local savedTaxiState = Client.capabilities and Client.capabilities.taxiState

-- World X grows north and Y grows west, in yards (the client's axes).
local maps = {
    [1411] = { left = 4000, top = 0, size = 5000 },    -- Durotar
    [1454] = { left = 5500, top = 0, size = 1500 },    -- Orgrimmar, in Durotar's north
    [1413] = { left = 0, top = 0, size = 4000 },       -- the Barrens, west of Durotar
}
local player = { map = 1454, x = 0.4529, y = 0.6389 }
local clock, onTaxi = 1000, false

local function vector(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
_G.CreateVector2D = vector
_G.C_Map = {
    GetBestMapForUnit = function() return player.map end,
    GetPlayerMapPosition = function(map)
        if map ~= player.map then return nil end
        return vector(player.x, player.y)
    end,
    GetWorldPosFromMapPos = function(map, position)
        local m = maps[map]
        if not m then return nil end
        return 1, vector(-(m.top + position.y * m.size), -(m.left + position.x * m.size))
    end,
    GetMapWorldSize = function(map)
        local m = maps[map]
        if m then return m.size, m.size end
    end,
}
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
_G.GetUnitSpeed = function() return 0, 7, 7, 4.7 end
_G.UnitOnTaxi = function() return onTaxi end
_G.GetTime = function() return clock end
_G.GetBindLocation = function() return "Orgrimmar" end
if Client.capabilities then Client.capabilities.taxiState = true end
Client:RecordFlightPath("Orgrimmar, Durotar")
Client:RecordFlightPath("Crossroads, The Barrens")

-- Planning a guide step ------------------------------------------------------------------------

local Repository, Progress = ns.modules.GuideRepository, ns.modules.Progress
local guide = Repository:Get("nuuroad:fixture:travel-flight")
check(guide, "the travel-flight fixture is packaged")
Progress:Select(guide)
guide = Progress:GetActiveGuide() or guide
local node = Progress:GetCurrentNode(guide)
check(node and node.label == "crossroads", "the fixture opens on its Crossroads step")
Route:Sync(node, guide)
settle()

local plan = Route.plan
check(plan, "a route is planned to the Crossroads: " .. tostring(Route.why))
check(plan.summary:match("^fly Crossroads"), "the route is the flight: " .. plan.summary)
check(plan.choice == "default", "the default is followed")
local leg = Route:Leg(node)
check(leg and leg.kind == "flight" and leg.toKey == "crossroads", "the arrow's leg is the flight to the Crossroads")
local summary, offer = Route:RouteParts(node)
check(summary == plan.summary and offer and offer:match("^walk"), "walking is on offer: " .. tostring(offer))
check(Route:RouteLine(node):match("^Route: fly Crossroads.* %- click: walk"), "the tracker's route line")
check(Route:Leg({}) == nil, "no leg for a node the route does not follow")
check(#Route:Waypoints(node) >= 1, "the flight's waypoints are listed for the map")

-- The player cycles the choice: walking, then back to the flight.
Route:CycleChoice(node)
check(Route.plan and Route.plan.choice == "walk", "a click follows walking instead: " .. tostring(Route.plan and Route.plan.choice))
check(Route.lastReason == "choice", "planned again for the choice")
Route:CycleChoice(node)
check(Route.plan and Route.plan.choice == "default" and Route.plan.summary:match("^fly Crossroads"), "and back to the flight")

-- A travel switch plans again: no flights, so the route walks.
local Config = ns.modules.Config
Config:Set("navigation.travel.flights", false)
check(Route.lastReason == "options", "a travel setting plans again")
check(Route.plan and not Route.plan.summary:match("fly"), "without flights the route walks: " .. tostring(Route.plan and Route.plan.summary))
Route.lastReason = nil
Config:Set("tracker.scale", 1)
check(Route.lastReason == nil, "another setting leaves the route alone")
Config:Reset("navigation.travel.flights")
check(Route.plan and Route.plan.summary:match("^fly Crossroads"), "the flight is back once the switch is reset")

-- The flight map: the Crossroads button glows; nothing is clicked.
local taxiNodes = { { "Orgrimmar, Durotar", "CURRENT" }, { "Crossroads, The Barrens", "REACHABLE" } }
_G.NumTaxiNodes = function() return #taxiNodes end
_G.TaxiNodeName = function(index) return taxiNodes[index] and taxiNodes[index][1] end
_G.TaxiNodeGetType = function(index) return taxiNodes[index] and taxiNodes[index][2] end
_G.TaxiButton1 = CreateFrame("Button", nil, UIParent)
_G.TaxiButton2 = CreateFrame("Button", nil, UIParent)
Route:OnTaxiMapOpened()
check(Route.lastHighlight and Route.lastHighlight.matched == "Crossroads, The Barrens", "the Crossroads button glows")
check(TaxiButton2.nuuRoadGlow and TaxiButton2.nuuRoadGlow:IsShown(), "with a glow over it")
check(not TaxiButton1.nuuRoadGlow, "and nothing over the flight master's own node")
Config:Set("navigation.travel.highlight", false)
check(not TaxiButton2.nuuRoadGlow:IsShown(), "the highlight switch puts the glow away at once")
Config:Reset("navigation.travel.highlight")
check(TaxiButton2.nuuRoadGlow:IsShown(), "and back")
Route:OnTaxiMapClosed()
check(not TaxiButton2.nuuRoadGlow:IsShown(), "closing the map puts the glow away")

-- A flight is timed: taken, flown for two minutes, landed by the Crossroads
-- flight master.
Route:OnTakeTaxi("Crossroads, The Barrens")
onTaxi = true
Route:Tick()
check(Route.flight and Route.flight.to == "crossroads", "the flight under way is known")
check(Route:CurrentFlight() and Route:CurrentFlight().name == "Crossroads", "the arrow window's flight")
clock = clock + 120
onTaxi = false
player.map, player.x, player.y = 1413, 0.515, 0.3034
Route:Tick()
local times = ns.db.travel and ns.db.travel.flightTimes and ns.db.travel.flightTimes["orgrimmar>crossroads"]
check(times and times[#times] == 120, "the flight time is learned into ns.db.travel")
check(Route.lastReason == "leg done", "landing plans again from the landing: " .. tostring(Route.lastReason))
check(#Route:DiagnosticLines() >= 4, "the diagnostic lines")

-- A route to any place (NuuRoad.API.Route), then stopped.
player.map, player.x, player.y = 1454, 0.4529, 0.6389
local ok, why = Route:RouteTo({ mapID = 1413, x = 52, y = 31, label = "Test: the Crossroads inn", npcID = 3934 })
check(ok, "a route to any place: " .. tostring(why))
check(Route:IsRouting() and Route.node and Route.node.npcID == 3934, "the route follows the asked-for place")
check(Route.node.title == "Test: the Crossroads inn", "under its label")
check(Route.plan and Route.plan.summary:match("^fly Crossroads"), "and is planned there: " .. tostring(Route.plan and Route.plan.summary))
check(Route:StopRoute() and not Route:IsRouting(), "stopped")
check(not Route:StopRoute(), "stopping twice stops nothing")
check(not Route:RouteTo({ mapID = 1413 }), "a place without x and y is refused")
Route:Sync(node, guide)

-- The teleport button: no teleport leg, so nothing over the arrow window.
Route:SyncTeleportButton()
check(not (Route.button and Route.button:IsShown()), "no teleport button without a teleport leg")
check(Route:TeleportAction(nil) == nil and Route:TeleportWait(nil) == nil, "no teleport action or wait")
ctx.noErrors("the route")

-- The travel test window ------------------------------------------------------------------------

local function textShown(pattern)
    for _, o in ipairs(ctx.frames.objects) do
        if o.kind == "FontString" and o.text and o.text:find(pattern) and o:IsVisible() then return o end
    end
    return nil
end

local function button(caption)
    for _, o in ipairs(ctx.frames.objects) do
        if o.kind == "Button" and o.label and o.label.text == caption and o:IsVisible() then return o end
    end
    return nil
end

Panel:Toggle()
settle()
check(Panel.win and Panel.win:IsShown(), "/nuuroad traveltest opens the window")
check(textShown("^Pick a test"), "on the list of tests")
check(button("Flight master") and textShown("^6 steps, with a guide"), "every test with where it starts")
check(not Panel.listButton:IsShown(), "no 'All tests' on the list")

-- Load the flight test by its button.
button("Flight master"):Click()
settle()
check(Panel.test and Panel.test.id == "flight" and Panel.index == 1, "the flight test is loaded")
check(textShown("^Flight master, step 1 of 6"), "titled with the step")
check(textShown("^Talk to the flight master"), "what to do")
check(textShown("follows the test guide's step 'crossroads'"), "where the arrow points")
check(textShown("glowing: "), "the live checks")
check(textShown("^Route now: fly Crossroads"), "the route now")
check(Panel.listButton:IsShown(), "'All tests' in the band")

-- Pass, then switch the route on step 2, mark a spot, go on.
button("Pass"):Click()
settle()
check(Panel.index == 2 and textShown("^Close the flight map"), "Pass goes to the next step")
check(button("Switch route"), "the route can be switched while there is a choice")
button("Switch route"):Click()
check(Route.plan and Route.plan.choice == "walk", "Switch route follows walking")
check(textShown("^Route now: walk"), "and the window shows it in place")
Panel:SwitchRoute()
check(Route.plan.choice == "default", "and back")
Panel.note:SetText("gate is two yards west")
button("Mark this spot"):Click()
check(Panel.index == 2 and Panel.note:GetText() == "", "Mark this spot stays on the step and empties the note")
button("Next step >"):Click()
button("< Previous step"):Click()
check(Panel.index == 2, "Previous and Next move without answering")
Panel:Tick()
Panel:Go(#Panel.test.steps + 1)
settle()
check(textShown("^Every step is answered"), "the test finishes")
check(not button("Pass") and button("< Previous step"), "no answer buttons once finished")

-- A waypoint test points the arrow at its place, and the list puts it away.
Panel:ShowList()
settle()
check(textShown("^Pick a test"), "back on the list")
local gates
for _, test in ipairs(Panel.tests) do if test.id == "gates" then gates = test end end
Panel:Load(gates)
settle()
local Navigation = ns.modules.Navigation
check(Navigation and Navigation.SetWaypoint, "the arrow takes a waypoint")
do
    check(Navigation.waypoint and Navigation.waypoint.title == "Test: Razor Hill", "the waypoint test points the arrow")
    Panel:ShowList()
    check(Navigation.waypoint == nil, "and the list puts its waypoint away")
end
ns.UI:SetLook({ theme = "slate" })
settle()
Panel:Toggle()
check(not Panel.win:IsShown(), "toggled closed")
Panel:Toggle()
settle()
Panel:Toggle()

-- Put the stand-in back as it was.
for _, name in ipairs(STUBS) do rawset(_G, name, saved[name]) end
if Client.capabilities then Client.capabilities.taxiState = savedTaxiState end
Route:Sync(nil, nil)
ctx.noErrors("the travel test window")
print("NuuRoad travel window tests passed")
