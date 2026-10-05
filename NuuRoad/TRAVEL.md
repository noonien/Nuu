# Travel system plan

## Goal

When the current step is far away, tell the player the fastest sensible way to get there: walk, take a flight
path they know, hearth or teleport, or take a boat or zeppelin, and go in and out of caves and walled cities through
their entrances instead of through the rock. City gates and mountain passes are packaged with the addon. Caves
are not: a guide that sends the player into one describes the way through it itself. Show it one leg at a time in the arrow and the tracker, the way
Zygor's "Fly to Ratchet" legs do. The player can still ignore the route and walk.

Scope and limits:

- **No libraries.** One pure-Lua planner module, one data file, and small changes to Navigation and the tracker.
  There is no LibRover-style graph of the whole world.
- **Simple.** The world model is a few dozen points joined by straight lines. Paths do not follow terrain, and
  nothing is baked into a navmesh.
- **Almost as good as Zygor.** Most of Zygor's benefit comes from four things: using the flight paths you know,
  using your hearthstone and class teleports, crossing to another continent, and knowing where the ways in and out
  of a place are. This plan covers those four and leaves out the rest.
- **Player-directed.** NuuRoad suggests a route and never takes one for the player. It does not click taxi nodes,
  cast a teleport, or board anything. At a flight master it can highlight the destination, and the hearthstone or
  teleport takes the arrow's place in the arrow window, as a button for the player to press.

## What exists today

- `Navigation:Measure` points at the nearest of a step's points, on the same map or on the same continent through
  world coordinates. For a target on another continent it shows "No route from here".
- `Client:IsOnTaxi` switches the arrow to the flight state.
- Learned flight paths are saved per character by name (`Client:RecordFlightPath`, from `TAXIMAP_OPENED` and
  `ERR_NEWTAXIPATH`). `Client:GetBindLocation` reads the hearth.
- `C_TaxiMap.GetAllTaxiNodes` has returned nothing on Forever so far (`docs/api-compatibility.md`). The client
  cannot provide the taxi network, so NuuRoad has to ship it as data.

## Design

### 1. Travel data: `Data/Travel.lua`

This is a declarative table that uses the same conventions as guides: IDs, map percentages, and ASCII only. It
contains four lists.

```lua
ns.travel = {
    flights = {
        -- name is the client's TaxiNodeName, which is how learned paths are keyed
        { name = "Crossroads, The Barrens", npc = 3615, map = 1413, at = { 51.50, 30.34 }, faction = "Horde" },
        { name = "Ratchet, The Barrens", npc = 16227, map = 1413, at = { 63.09, 37.16 }, faction = "Neutral" },
        ...
    },
    links = {
        -- fixed one-way or two-way connections: boats, zeppelins, trams, portals
        { kind = "zeppelin", from = { map = 1454, at = { 50.8, 12.9 } }, to = { map = 1434, at = { 31.5, 29.2 } },
          wait = 90, ride = 60, both = true, faction = "Horde", label = "Zeppelin to Grom'gol" },
        { kind = "boat", from = { ... }, to = { ... }, wait = 120, ride = 90, both = true, label = "Boat to Booty Bay" },
    },
    teleports = {
        -- from anywhere to a fixed place; `to = "bind"` means wherever the hearthstone is set
        { item = 6948, to = "bind", cast = 10, label = "Hearth" },
        { spell = 556, to = "bind", cast = 10, class = "SHAMAN", label = "Astral Recall" },
        { spell = 18960, to = { map = 1450, at = { 56.2, 30.6 } }, cast = 10, class = "DRUID", label = "Teleport: Moonglade" },
        { spell = 3567, to = { map = 1454, at = { 47.5, 62.0 } }, cast = 10, class = "MAGE", reagent = 17031,
          label = "Teleport: Orgrimmar" },
    },
    inns = {
        -- GetBindLocation's answer -> where the player lands
        { name = "The Crossroads", map = 1413, at = { 51.99, 29.90 } },
    },
    areas = {
        -- cities and walled zones you can only walk into or out of through their doors
        { name = "Orgrimmar", map = 1454, doors = {
            { at = { 49.0, 94.0 }, label = "the front gate" },
            { at = { 11.0, 66.0 }, label = "the west gate" },
        } },
        { name = "Thunder Bluff", map = 1456, doors = {
            { at = { 30.0, 62.0 }, wait = 15, label = "the west lift" },
            { at = { 60.0, 23.0 }, wait = 15, label = "the north lift" },
        } },
    },
}
```

(All coordinates above are placeholders to show the shape. The real rows come from recordings.)

The data does not include a list of which flight connects to which. Classic taxis route through intermediate nodes
on their own, so the planner assumes that **any two known nodes on the same continent are connected**, with a cost
equal to the straight-line distance at flight speed times a detour factor (about 1.2, the factor Zygor uses for
taxis it has not yet timed). Where that assumption is wrong, a measured time replaces it (section 5). This choice
avoids hand-maintaining a route table.

The assumption fails in one case: a flight chain that needs a stop the player has not learned. The client says
which flights are really available. At the flight master, `TaxiNodeGetType(i) == "REACHABLE"` lists every
destination the player can fly to from that node. That list is saved per character as `reachable[origin] = { names }`,
and once it exists it overrides the assumption for that origin. Zygor and RestedXP read known and reachable flights
from the taxi map in the same way.

**Teleports.** The hearthstone is the first teleport, not a separate mechanism. Every row is an edge from wherever
the player stands to a fixed place (or to the inn named by `GetBindLocation`), available only when the player has
the item or knows the spell, matches `class`, and carries the `reagent` (Rune of Teleportation for Mage
teleports). Adding a new teleport is one data row with no code.

**Areas and doors (choke points).** An area is a big place with walls: a city, Thunder Bluff's mesa, or a zone
whose border can only be crossed at a few passes (Zygor's border data covers exactly those). These are hardcoded
in `Data/Travel.lua`, and there are few of them. An area is either a whole map (`map = 1454`, since cities are
their own maps) or a circle on a map (`map`, `at`, `radius`) for a walled place that shares its zone's map. A
point authored on the zone around a whole-map area (a Durotar point inside Orgrimmar) is inside it when
`C_Map.GetMapInfoAtPosition` says the city's map lies there, the world map's own hover data; without that API only
points on the city's map count. Each
area lists its doors: points where walking in and out is possible. A door can carry a `wait` (a lift) and a
`kind`, which works the same way as in guide places (section 6): `"entrance"` (the default) for in and out, and
`"exit"` for out only, such as a drop off a ledge. Only walking is affected by areas. Flights, boats and teleports cross walls freely, which is how Zygor
treats its borders ("ground only, ignored by flight").

**Lifts.** Thunder Bluff's map also covers the ground round the mesa's foot, so "on the city's map" cannot mean
"on the mesa", and the client's height (`UnitPosition`) is always 0. A lift is therefore a door with a `bottom`:
the door is its top, the bottom is a waypoint outside the area even on the area's own map, and `wait + ride` is the
only way between them. The legs read `Take the west lift up`, `Ride the west lift up` (and `down` the other way).
Where the player stands is read from where they have been (`UI/TravelRoute.lua`): standing at a lift's bottom, or
walking onto the area's map from the zone around it, is below; standing at a lift's top, landing from a flight, or
arriving by a loading screen or a teleport is on top; leaving the area's map forgets it. The planner is told
`below[area name]`, which puts the player outside the area whatever their map says. With nothing known, the map
decides.

An area only exists where someone added it. Everywhere else, straight lines are assumed to work, so the list
stays short: the cities and the few zone borders that are mountains (Mulgore, Stonetalon, Thousand Needles).
Caves are not in this file. They belong to the guides that use them (section 6).

Where the data comes from: coordinates and NPC IDs we record ourselves, not copied from Zygor or RestedXP. The
walkable layout of a city or cave may also be worked out at build time from the client's own map files
(`Tools/ClientMap`): only the resulting points ship, never the game's geometry. The
recorder already runs on `TAXIMAP_OPENED`. It will also store the player's position and the flight master's own
node name (`Client:GetCurrentTaxiNodeName`), which places the flight master exactly. The packaged guides already
author many flight masters (`HordeBarrens`, `HordeMulgore612`). Start with Horde Kalimdor plus the Horde transports,
which is what the guides cover, and add the rest as they are recorded.

### 2. The planner: `Domain/Travel.lua` (pure, testable)

`Travel:Plan(from, to, context)` returns a list of legs, or nil when walking is best.

The graph is rebuilt on every call because it is small (under about 100 nodes):

- **Nodes:** the player, the target, every *known* flight node for the player's faction, every link endpoint,
  every area exit on the continents involved, and each usable teleport's destination.
- **Several spots:** a step with `spots` can be arrived at any of them. Each spot is a node joined to the goal at
  no cost, so the search picks the one quickest to reach (a far spot beside a flight master can beat the one
  nearest in a straight line).
- **Walk edges:** between any two nodes on the same continent: straight-line yards times 1.2 (roads are not
  straight; Zygor uses the same factor), divided by run speed (7 yd/s, or the observed speed when mounted; see
  below). **The wall rule:** a walk edge is only allowed if, for every area, both ends are on the same side of it
  (both inside or both outside), or one end is a door of that area. Each node's "inside which areas" set is
  computed once per plan, so the rule is a set comparison per edge. Dijkstra then picks the best exit on its
  own: nothing else in the planner knows about walls. Areas nest: a guide place in a cave inside a walled zone
  passes the cave mouth and then the zone's pass. A door's `wait` is added to any edge that uses it, and an
  `"exit"` door only allows edges going from inside to outside.
- **Flight edges:** between known flight nodes on the same continent, using the measured time or the estimate
  above.
- **Link edges:** `wait + ride`. A boat's average wait is part of its cost, so a short boat ride does not beat a
  slightly longer walk. Zygor charges a flat 240 s for every boat and zeppelin, so a single `cost` per link is
  enough to start with.
- **Teleport edges:** from the player to each usable teleport's destination, costing the cast time. Only a
  teleport that can be cast now has an edge: one on cooldown (`GetItemCooldown` for items, `GetSpellCooldown`
  for spells) is not offered, never waited for. Zygor counts the wait instead; NuuRoad leaves it out, because a
  hearth the guide has planned for later is not the planner's to spend. A `"bind"`
  teleport resolves through the `inns` list, keyed by `GetBindLocation`'s subzone name the way Zygor keys its inn
  data. A bind location that is not in the list has no edge; the debug log says so once per bind location, and
  `/nuuroad where` shows it.
- **Mode change penalty:** every leg after the first adds 15 s. Without it, the planner will propose
  walk > fly > walk > boat routes that save 20 seconds and cost the player attention. Zygor applies the same kind
  of penalty for each mode change.

Search: plain Dijkstra with a linear scan for the minimum. Zygor also uses Dijkstra without a heuristic, and it
needs a heap only because its graph is thousands of nodes. At this size a linear scan runs in well under a
millisecond.

**Flights collapse into one leg.** Consecutive flight edges are merged into a single "Fly to <final>" leg, because
the client flies the whole chain from one click. Zygor's route display merges them the same way.

**Hysteresis**, which stops the route from flipping between options (the main thing that makes a planner feel
bad):

- Suggest a non-walking route only if it saves at least 60 s and at least 25% over walking.
- Once a route is shown, keep it until a new route is better by the same margin, or until the current route
  becomes impossible (hearth used, taxi taken elsewhere, continent changed).

**Waypoints and choices.** A plan is always one or more waypoints: each leg ends on one, and the last is the step
itself, so a straight walk is a plan of one waypoint. The planner returns the route it shows plus the others the
player can pick, default first:

1. **The default:** walking, or flights and transports when they clearly beat walking. Never a teleport, so the
   hearth the guide has planned for later is not spent by a suggestion.
2. **Each ready teleport** whose route clearly beats the default (the same 60 s and 25% rule), fastest first. One
   the player picked stays on offer while it can be cast, so the pick does not lapse as they walk.
3. **Walking**, when the default is not already that.

Hysteresis applies inside the route being followed, never across a pick: choosing the hearth takes effect at once.

**Movement speed:** the run speed `GetUnitSpeed("player")` reports now, averaged over the last ten seconds. It is
the mount's speed while mounted and the speed on foot otherwise, so a mounted player gets fewer flight suggestions
for short hops, and a cave, where nobody rides, is walked at walking pace. The average keeps a moment's Sprint or
a dismount to loot from swinging the route, and hysteresis holds it through the rest. Run speed rather than the
speed moved at, since standing still is not a speed of nothing. Without that API, use 7 yd/s.

### 3. Legs and how each one completes

| Leg | Arrow points at | Tracker line | Completes when |
| --- | --- | --- | --- |
| `walk` | the leg's end point | (none; the step's own line) | arrival at the leg's end, as `Navigation:Measure` measures it |
| `flight` | the flight master, until the taxi starts | `Fly to Ratchet` | the player was on a taxi and has landed (`UnitOnTaxi` true, then false) |
| `walk` via a door | the door | `Leave Orgrimmar by the west gate`, `Enter Bristleback cave by the cave mouth` | arrival at the door; the next walk leg then points at the target |
| `walk` inside a guide place | the next point of the route ahead of the player | `Go to the gallery`, `Leave by the hole to the river` | reaching the last point of the route inside the place, judged by which connection the player stands on, not by touching each point |
| `teleport` | none; the item or spell button is shown | `Hearth to The Crossroads`, `Teleport: Moonglade` (only when the player picked it) | `UNIT_SPELLCAST_SUCCEEDED` for the row's spell (8690 for the hearthstone; the recorder already listens for it; RestedXP completes `.hs` the same way), or arrival at the destination |
| `link` | the dock or portal | `Take the zeppelin to Grom'gol` | the player's continent changes, or they arrive at the far end |

When the route has only one walk leg, the travel system hides itself and the arrow behaves exactly as it does
now.

**Off route:** replan immediately when the step changes, on `ZONE_CHANGED_NEW_AREA`, on `LOADING_SCREEN_DISABLED`,
on landing, and when a flight path is learned. Also check on a slow timer and replan only if the player has moved
more than 50 yd since the last plan. That is Zygor's rule, and it keeps a player standing still from flickering
between routes. Two cases pause replanning:

- **On a taxi:** plan from the landing node, not from the player's position in the air (Zygor forces the start
  there the same way).
- **On a boat or zeppelin:** freeze the plan from arrival at the dock until the continent or zone changes. Zygor has
  a "boat lock" for this, because the player is moving without walking and would otherwise be rerouted mid-ride.
  A player who walks 40 yd away from the dock on their own feet (`GetUnitSpeed` above 0) has changed their mind,
  and the lock ends. Riding shows as moving while `GetUnitSpeed` says 0 (Zygor's "involuntary movement"); once
  that is seen, only the crossing ends the lock.
- **A teleport just cast:** the legs after it were planned from its landing, so the arrow moves on to them at
  once, and the move itself replans.

Zygor also replans from wherever an off-route player is. NuuRoad never tells the player they went the wrong way.

### 4. Presentation

- **Arrow window:** the destination label becomes the leg ("Fly to Ratchet"), with the final target under it in
  muted text. On a taxi the window shows the flight, whatever the route's next leg is: the bobbing wing,
  "Flying to Crossroads", and the distance and time left to the landing, until it lands and the route takes over
  again. The landing is the flight master clicked on the taxi map (a secure post-hook on `TakeTaxiNode`, the way
  RestedXP times its flights), else the route's own leg (a druid's flight is not taken from a taxi map). The time
  left is the learned flight time less the time flown, else the straight distance left at taxi speed. No route is
  written out under the arrow; the arrow shows it one leg at a time. A right-click anywhere on the window opens its
  menu: every route on offer with its time and the one followed checked, and Clear waypoint while one is set. It is
  the one place to pick while the arrow follows a typed-in waypoint with no guide open.
- **Tracker:** under the current step, one muted route line such as `Route: walk > fly Crossroads > walk (~2m10s,
  walking ~6m)`, drawn the way `with = "next"` lines already are. When there is something else to pick, the line
  names the next choice (`- click: hearth > walk ~1m10s`), and clicking it moves to that route for this step,
  round through the choices and back to the default. The pick is the player's decision. A straight walk with
  nothing else on offer shows no line. On a taxi nothing is on offer (the flight is under way and nothing is
  planned until it lands), and taking a taxi spends a pick made before it, so the landing plans from the default.
- **Flight master:** when the taxi map opens and the current leg is a flight, highlight the destination node's
  button (`TaxiButtonN` on the classic taxi frame). NuuRoad does not click it. Zygor (`autotaxi`) and RestedXP
  (`enableFPAutomation`) both call `TakeTaxiNode` automatically. For NuuRoad that is a route decision, so it
  stays with the player.
- **Teleport:** during a teleport leg the arrow window shows the hearthstone or the spell in the arrow's place,
  with no distance, and clicking it uses it: a secure macro button (`/use item:6948`, or `/cast` of the name
  `GetSpellInfo` returns) laid over the icon. It is its own frame on UIParent, since a frame that holds a
  protected button becomes protected itself and the arrow window shows, hides and resizes freely. It is only
  placed, shown, hidden or given a new macro out of combat; a change in combat waits for `PLAYER_REGEN_ENABLED`,
  and the window says "Click after combat" meanwhile. The player presses it; NuuRoad never does.
- **Map pins:** every waypoint still ahead gets an accent bead on the world map, the arrow's one in full and the
  later ones fading; the minimap shows the arrow's one. The step's own numbered pins do not change.

### 5. Learning from play

These measurements are saved account-wide in `NuuRoadDB.travel`, so the plan gets more accurate with use:

- **Flight times:** when a taxi ends, save `from node -> landing node = seconds`. The planner uses the median of
  the measured times over the estimate.
- **Flight master positions:** the recorder rows collected in section 1 feed `Data/Travel.lua` at build time. The
  addon never rewrites packaged data at runtime.
- **Doors:** every time the client's map ID changes while the player is on foot (not on a taxi, not after a
  teleport or loading screen), the recorder saves the position. Walking into Orgrimmar through a gate or into a
  zone through a pass marks the doorway. A build-time tool clusters those points into candidate doors for
  review.

Neither measurement is required. With nothing saved, the estimates still produce a reasonable route.

### 6. Guides

Existing guides work unchanged. The planner runs for any step that has a location, so authored `travel` steps
such as "Travel to Thunder Bluff, fly from Nighthaven" gain a route without editing. Authored notes stay as they
are, and where a note disagrees with the plan, the author's note is the one the player reads.

#### Guide places (caves and other local pathing)

A guide can describe the way through a place the packaged data does not know, such as a cave, a tunnel, a ramp up
a hill, or a building with one door. It does this with a guide-level `places` list beside `steps`. A place is a
small graph: a list of points and the connections between them. Only the place has an ID. A point is named only
when a step needs to refer to it.

A cave with a four-way junction, two loops, two entrances, a one-way drop and a hole out:

```
                  north mouth (1) [entrance]
                    |
  gallery (6) --- junction (3) --- tunnel (4) --- east mouth (2) [entrance]
     |              |                  |
     |              |               ledge (5)
     |              |                  :  one-way drop
   lower (7) ---- chamber (8) <........:
                    |
                  hole (9) [exit]
```

```lua
places = {
    { place = "windfury", name = "Windfury cave", width = 15,
      points = {
          { at = { 40.1, 20.3 }, kind = "entrance", label = "the north mouth" },   -- 1
          { at = { 44.8, 22.0 }, kind = "entrance" },                              -- 2
          { at = { 40.3, 22.1 }, label = "the crossroads" },                       -- 3
          { at = { 42.6, 22.1 } },                                                 -- 4
          { at = { 42.7, 23.6 }, label = "the ledge" },                            -- 5
          { at = { 38.6, 22.2 }, label = "the gallery" },                          -- 6
          { at = { 38.5, 24.4 } },                                                 -- 7
          { at = { 40.4, 24.5 }, id = "chamber" },                                 -- 8
          { at = { 40.6, 26.0 }, kind = "exit", label = "the hole to the river" }, -- 9
      },
      connections = { { 1, 3 }, { 2, 4 }, { 3, 4 }, { 3, 6 }, { 3, 8 }, { 4, 5 }, { 5, 8, true },
                      { 6, 7 }, { 7, 8 }, { 8, 9 } },
    },
}
```

- **A place** has a `place` ID, unique within the guide, and a display `name` for the tracker ("Follow the way into
  Windfury cave"). `width` is how far from a connection, in yards, still counts as being in the place (default 20).
- **No table mixes list entries and keys.** `points` and `connections` are plain lists; each point is a keyed
  table; `at` is a plain pair and each connection a plain list of two or three values. A plain list keeps its order in Lua and in
  SavedVariables, which writes it back as `[1]`, `[2]`, ... explicitly, so referring to a point by its position
  is safe.
- **Points** are `{ at = { x, y } }` in map percentages, each with optional `label`, `kind`, `id` and `map`
  (`map` sits beside `at`, not inside it). A point's position in the list is only how connections refer to it.
- **Connections** are `{ a, b }` or `{ a, b, true }`, where each end is a point's position in the list or its
  `id`. `{ a, b }` can be walked both ways. A third value `true` makes it one-way, walkable only from `a` to
  `b`, such as the drop from the ledge (5) into the chamber (8): `{ 5, 8, true }`. Connections are the only way
  to move between points; two points without a connection are walls apart. A junction is a point with three or
  more connections, and a loop is just connections that close a ring. Neither needs any special syntax.
- **Kinds:**
  - `kind = "entrance"`: the player can walk in or out here.
  - `kind = "exit"`: the player can only leave here, such as a hole or a drop to the river. Put the point where
    the player lands.
  - no kind: an inside waypoint.
- **Labels are optional.** When the next point has one, the arrow says "Go to the gallery". When it does not,
  the arrow shows the place's name and the distance to the point ("Windfury cave, 18 yd").
- **IDs are optional** and unique within their place (one word, no dot, not a number). A step refers to a
  point as `at = "windfury.chamber"` (place ID, a dot, point ID) instead of repeating its coordinates. Steps use
  IDs rather than list positions so that editing the place never changes what a step points at. This names a
  waypoint, not a step position, so authors still never write step positions. A step with ordinary coordinates
  works too; it counts as inside when it is within `width` yards of one of the place's connections. A step
  whose coordinates are close to a point can say so with `near = "windfury.chamber"` beside `at`: it is then
  joined to that point's connections instead of whichever connection happens to be nearest, which settles
  overlapping levels and spots between passages.
- Hand editing: add a new point at the end of the list, so no existing connection changes meaning. The editor
  renumbers connections itself when a point is deleted.
- The player is **inside** when they are within `width` of a connection that is not only an entrance's doorstep
  and, when the client reports it, `IsIndoors()` is true. The indoors check stops the place from claiming a player
  walking on the hill above the cave.
- **Steps never name a place.** A place applies to the whole guide. Any step whose target is inside it gets led
  in through the best entrance, and any step whose target is outside, while the player is still inside, gets led
  out through the best entrance or exit. So a player who finishes a cave quest is led back out without the guide
  saying so, and down the hole if that is quicker.

**In the planner** a place is one more area, and its kinds are the same two kinds the packaged areas use
(section 1). Its points become nodes and its connections become the only walk edges inside it. Entrances join the outside both ways and exits join it outward only. The wall rule, the costs and the
Dijkstra search are the same ones used for cities, so no new search code is needed, and loops and junctions are
ordinary graph edges that Dijkstra handles by picking the shorter way around.

**The arrow inside a place** does not wait for the player to touch each point:

- It finds the connection the player is standing on and joins the graph at both of its ends, with the
  distance to each end as the cost. On a loop the player carries on the way they are facing instead of being
  sent back to a point behind them.
- It points at the next point of the planned route ahead of them. If the player takes the other branch at a
  junction, the place's graph (a dozen nodes) is replanned on the spot, and the route follows the branch they
  took if it still gets there.
- **Stable on loops.** When both ways around a ring are nearly equal, the route only switches if the other way is
  shorter by at least 15 yd and 15%, the cave-sized version of the rule for flights. Otherwise the arrow would
  swap sides as the player walks.
- **Overlapping levels.** A ledge above a hall can put two connections on top of each other on the map. When
  connections are about equally close, the arrow prefers the connection the player was last on, or one sharing a
  point with it,
  over one elsewhere in the cave.

Guide places apply even when "Suggest travel routes" is off. They are part of the guide, like its coordinates;
the option only controls flights, teleports and transports.

Authored `travel` steps that already say "through the cave" stay valid. A place replaces them only when an author
chooses to rewrite the guide.

**Editor (viewer/editor parity, same change):**

- A Places panel in the guide editor lists the guide's places, each with its points and connections, a name,
  a width field, rename and delete.
- "Add point here" adds a point at the player's position, connected to the selected point. Walking is done in
  the place recorder, a separate small window (Menu, or "Record..." here to extend the selected place from the
  selected point). It records a raw trail and nothing else: a sample every 3 yd and at every change of the
  indoors, falling or swimming flag or the map (position, world yards, flags, facing, subzone), plus spots the
  author names with MARK. No point is made while walking. When the walk stops, the place is worked out from the
  trail: a point every 15 yd and at turns, points reused when a passage is walked again (so loops and junctions
  join themselves), doorways from the indoors flag, one-way drops from falls. Every sample goes to the session log as it is taken,
  and `Tools/ProcessPlace.lua` reprocesses it with other settings outside the game. The client has no height, so
  for now passages on two levels over each other are joined where they cross; telling them apart from the order
  they were walked in is left to processing, and not done yet.
- Selecting two points offers connect, disconnect, and one-way (from the first selected to the second).
- Each point has an entrance / exit / inside toggle, an optional label, and an optional ID.
- A step's location field offers the guide's named points as well as coordinates, and a `near` point.
- Deleting a point removes its connections and renumbers the others, the way the editor's draft (`Domain/GuideDraft.lua`) keeps what points at a step.
- The place is drawn on the world map while the panel is open, with its points, connections (one-way ones with
  arrowheads), IDs, labels and kinds, so the author can see and fix a bad point.
- Validation, reported at load like a bad `goto` label:
  - Place IDs unique within the guide, point IDs unique within their place, all ASCII, and no dot in either.
  - Every connection end is a point in the list or an ID in the place, and no point connects to itself.
    A third value other than `true` is an error. A duplicate connection is merged with a warning, and the same
    two points joined both one-way and two-way is an error.
  - Every step `at` or `near` string names an existing `place.point`.
  - At least one entrance per place.
  - Every point can be reached from an entrance, and every point can reach an entrance or exit.
  - Every point on one continent, and width from 5 to 60 yd.
  - Unknown fields on a place or point are kept as they are.
- Fixture guide `nuuroad:fixture:cave-place`: a short guide into a Mulgore cave, to a step placed by a named
  point past a junction, and back out. It checks being led in, being led out, leaving by an exit when it is
  shorter, never being sent in through an exit, never walking a one-way connection backwards, re-routing after
  taking the wrong branch, holding a route on a loop, and the indoors check.

One optional field, added later only if it proves necessary: `route = "walk"` on a step to suppress suggestions,
for example inside a cave where a flight suggestion would be nonsense. If it is added, the editor gets a checkbox,
schema validation, and a fixture step in the same change (viewer/editor parity).

The guide verb `flight` keeps its current meaning ("learn this flight path"). Travel legs are runtime objects and
never appear in guide data.

### 7. Options

Add to the navigation options:

- Suggest travel routes (on)
- Use flight paths (on)
- Use hearthstone and teleports (on)
- Use boats and zeppelins (on)
- Highlight destination at the flight master (on)

## What we skip on purpose

- **Terrain beyond the areas list:** a hill or a river between two open points is walked straight through. Areas
  and guide places fix the spots where that goes badly wrong. Paths are not drawn around obstacles, and there is no navmesh.
- **Packaged caves:** the addon ships no cave data. A cave is pathed only when a guide describes it as a place.
- **Paths inside cities:** a city is one area with gates, and the walk from a gate to the target is straight.
  A guide that needs more (the Undercity's lifts, a building's back door) can add a guide place.
- **Mage portals for a group, summons, and "die and resurrect" shortcuts:** these depend on other players or
  are a trick a guide explains in a note.
- **Transport schedules:** we use an average wait instead of tracking where the boat actually is.
- **Automatically taking taxis or clicking flight nodes:** this is a route decision, and it stays with the player.

## Implementation order

Each stage can ship on its own and has tests.

1. **Planner core:** `Domain/Travel.lua` with Dijkstra over walk and flight edges, the hysteresis rule, and a
   `Tests/TravelTests.lua` suite. Tests cover: walking wins when close; a known flight wins when far; an unknown
   flight is ignored; the wrong faction is ignored; hysteresis holds a route through small cost changes; the mode
   change penalty rejects a route that adds a leg to save 20 s; chained flights collapse into one leg; a saved
   `reachable` list overrides the any-known-node assumption.
2. **Data:** `Data/Travel.lua` with the Horde Kalimdor flight masters already present in the guides. Add it to
   `NuuRoad.toc`, and add schema-style validation (IDs, coordinates, known maps) to the existing test run.
3. **Navigation integration:** Navigation asks the planner for the first leg and points at it; the arrow label and
   the tracker route line are added; the "walk instead" toggle. Leg completion for walk and flight.
4. **Teleports:** the hearthstone first (item cooldown, the inn list, the item-panel button), then the class
   spells as data rows (spell cooldown, reagent count, the `/cast` button).
5. **Areas:** the wall rule in the planner with its tests (the nearest door is chosen, an `"exit"` door is never
   used inwards, nested areas pass both doors, flights ignore walls), then the Horde cities and Thunder Bluff's
   lifts.
6. **Guide places:** the `places` schema and validation (in `Data/Schema.lua`, imported by `Data/Steps.lua`
   alongside the steps), step `at = "place.point"`, import into the planner as areas, the arrow following the connection the
   player stands on, the indoors check, and the editor panel with recording and branching. Also the cave fixture,
   and a place for the Bristleback cave in `HordeMulgore16`. Tests: led in through an entrance; never led in
   through an exit; led out by an exit when it is shorter; a one-way connection is never walked backwards; a junction
   reroutes when the player takes the other branch; a loop holds its route when both ways are nearly equal; entering mid-cave starts from there; a player above the cave
   who is not indoors is outside; an unknown point name, an unreachable point, or a place with no entrance fails validation.
7. **Links:** the Horde zeppelins, the neutral boats, and cross-continent planning. This replaces "No route from
   here".
8. **Learning:** saving measured flight times, and recorder rows for flight master positions and city doors.
9. **Flight master highlight** on the taxi map.
10. **Optional, driven by play:** mountain zone borders as areas, and `route = "walk"`.

## Testing in the client

`/nuuroad traveltest` opens a list of short tests (`Dev/TravelTestPanel.lua`): Orgrimmar's gates, the flight
master, the Undercity zeppelin, the hearthstone with and without a guide, flying somewhere else, Thunder Bluff's
lifts, and the Bristleback cave. Each says where to stand first, so a failed one is rerun on its own. A test with
a step guide (`Dev/Fixtures/TravelTestFixtures.lua`, and the cave fixture) opens it and follows its steps by label,
since the tracker's route line, the numbered pins and a step done on arrival only exist with a guide open; the
rest point the arrow at a waypoint, since travel without a guide must work too. Each step says where to go and
what to do, points the arrow there, says what should happen, and checks what it can against the planner live. Pass, Fail, Skip and Flag each write a row with a snapshot of the route to the recorder's
`travel` channel, beside the planner's own rows (plans, legs, the boat lock, taxi, the API probe at login), so a
session is its own report: `python3 Tools/SessionLog/sessions.py --channel travel`.

## APIs to verify in client

Record each result in `docs/api-compatibility.md`. Every item has a fallback, so none of them blocks the feature.

| Need | API | Fallback |
| --- | --- | --- |
| Continent and world yards | `C_Map.GetWorldPosFromMapPos` (behind `Client:GetWorldPosition`) | map-local only; cross-continent routes use link endpoints |
| Taxi state | `UnitOnTaxi` | flight legs complete on arrival at the landing node |
| Taxi buttons for highlighting | `NumTaxiNodes`, `TaxiNodeName`, `TaxiNodeGetType`, `TaxiButtonN` frames | no highlight |
| Reachable flights at a flight master | `TaxiNodeGetType(i) == "REACHABLE"` on `TAXIMAP_OPENED` | assume any two known nodes on a continent connect |
| Teleport cast | `UNIT_SPELLCAST_SUCCEEDED` with the row's spell (8690 for the hearthstone) | arrival at the destination |
| Spell known and cooldown | `IsPlayerSpell` / `IsSpellKnown`, `GetSpellCooldown` (already read by `Client`) | no teleport edge for that spell |
| Reagent | `GetItemCount(17031)` | assume the player has one |
| Casting from a button | the arrow window's secure macro button with `/cast <GetSpellInfo name>` or `/use item:<id>` | the leg's text alone |
| Hearth cooldown | `GetItemCooldown(6948)` / `C_Container.GetItemCooldown` | assume ready when the stone is in the bags |
| Bind location | `GetBindLocation` | no hearth edges |
| Run speed | `GetUnitSpeed` | 7 yd/s |
| City a zone point lies in | `C_Map.GetMapInfoAtPosition` | only points on the city's own map are inside it |
| Indoors, for guide places | `IsIndoors` | nearness to a place's links alone decides inside |
| Zone change | `ZONE_CHANGED_NEW_AREA`, `LOADING_SCREEN_DISABLED` | the moved-50-yd replan timer |

## Documentation

When stages land, update `docs/authoring.md` (the route line, the walk toggle, and the Places panel),
`docs/guide-schema.md` (`places`, step `at = "place.point"`, and `route` if it is added), and `docs/api-compatibility.md` (the table above).
