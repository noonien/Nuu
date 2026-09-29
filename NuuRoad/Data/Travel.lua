local _, ns = ...

-- The world model the travel planner (Domain/Travel.lua) routes over:
-- flight masters, fixed transports, teleports, inns, and the walled places
-- that can only be walked into through their doors. Declarative, IDs and map
-- percentages only, ASCII only, the same conventions as a guide.
--
-- Rows marked "guide" take their coordinates from a packaged guide that
-- already stands the player there. Rows marked "unrecorded" are best
-- knowledge and wait for a recording (the recorder writes a `flightpath` row
-- with the player's position at every flight master, and a `door` row at
-- every map change on foot); replace them from those, never from another
-- addon's data.
--
-- There is no list of which flight connects to which: the planner treats any
-- two known nodes on a continent as connected, and what the flight master
-- itself says is reachable (saved per character) overrides that.
ns.travel = {
    -- `name` is the client's TaxiNodeName, which is how learned paths are keyed.
    flights = {
        { name = "Crossroads, The Barrens", npc = 3615, map = 1413, at = { 51.50, 30.34 }, faction = "Horde" }, -- guide
        { name = "Ratchet, The Barrens", npc = 16227, map = 1413, at = { 63.09, 37.16 }, faction = "Neutral" }, -- guide
        { name = "Camp Taurajo, The Barrens", npc = 10378, map = 1413, at = { 44.45, 59.15 }, faction = "Horde" }, -- guide
        { name = "Sun Rock Retreat, Stonetalon Mountains", npc = 4312, map = 1442, at = { 45.13, 59.84 }, faction = "Horde" }, -- guide
        { name = "Orgrimmar, Durotar", npc = 3310, map = 1454, at = { 45.29, 63.89 }, faction = "Horde" }, -- recorded
        { name = "Thunder Bluff, Mulgore", npc = 2995, map = 1456, at = { 46.65, 49.90 }, faction = "Horde" }, -- recorded
    },
    -- Fixed connections. `both` rides either way. `wait` is the average time
    -- standing at the dock and `ride` the crossing, both in seconds. Each end
    -- carries the name the tracker says ("Take the zeppelin to Grom'gol").
    links = {
        { kind = "zeppelin", faction = "Horde", wait = 120, ride = 60, both = true, -- unrecorded
          from = { map = 1411, at = { 50.6, 12.6 }, name = "Orgrimmar" },
          to = { map = 1434, at = { 31.5, 29.2 }, name = "Grom'gol" } },
        -- 2026-09-23: about two minutes from leaving the platform to the far
        -- one, the loading screen half way; the wait was four minutes once.
        { kind = "zeppelin", faction = "Horde", wait = 120, ride = 120, both = true, -- recorded platforms
          from = { map = 1411, at = { 50.83, 13.72 }, name = "Orgrimmar" },
          to = { map = 1420, at = { 60.60, 58.50 }, name = "the Undercity" } },
        { kind = "boat", wait = 120, ride = 90, both = true, -- unrecorded
          from = { map = 1413, at = { 63.7, 38.6 }, name = "Ratchet" },
          to = { map = 1434, at = { 25.8, 73.1 }, name = "Booty Bay" } },
        -- Bunthen Plainswind flies druids from Nighthaven to Thunder Bluff.
        -- 2026-09-23: the flight took 544 s, by way of Felwood, Ashenvale and
        -- Stonetalon.
        { kind = "flight", class = "DRUID", wait = 5, ride = 545, -- guide
          from = { map = 1450, at = { 44.29, 45.87 }, name = "Nighthaven" },
          to = { map = 1456, at = { 46.65, 49.90 }, name = "Thunder Bluff" } },
    },
    -- From anywhere to a fixed place. `to = "bind"` is wherever the
    -- hearthstone is set, looked up in `inns` by the bind location's name.
    -- `free = true` costs nothing worth saving (no long cooldown a guide
    -- plans around), so it may be the route by default; the others are only
    -- ever offered for the player to pick.
    teleports = {
        { item = 6948, spell = 8690, to = "bind", cast = 10, label = "Hearth" },
        { spell = 556, to = "bind", cast = 10, class = "SHAMAN", label = "Astral Recall" },
        { spell = 18960, to = { map = 1450, at = { 56.21, 30.64 } }, cast = 10, class = "DRUID", label = "Teleport: Moonglade", free = true }, -- guide
        { spell = 3567, to = { map = 1454, at = { 47.5, 62.0 } }, cast = 10, class = "MAGE", reagent = 17031, label = "Teleport: Orgrimmar", free = true }, -- unrecorded
        { spell = 3566, to = { map = 1456, at = { 22.0, 16.0 } }, cast = 10, class = "MAGE", reagent = 17031, label = "Teleport: Thunder Bluff", free = true }, -- unrecorded
        { spell = 3563, to = { map = 1458, at = { 84.0, 16.0 } }, cast = 10, class = "MAGE", reagent = 17031, label = "Teleport: Undercity", free = true }, -- unrecorded
    },
    -- GetBindLocation's answer -> where the hearthstone lands. The innkeeper's
    -- spot from the guide's hearth step is close enough.
    inns = {
        { name = "The Crossroads", map = 1413, at = { 51.99, 29.90 } }, -- guide
        { name = "Camp Taurajo", map = 1413, at = { 45.58, 59.04 } }, -- guide
        { name = "Thunder Bluff", map = 1456, at = { 45.81, 64.71 } }, -- guide
        { name = "Bloodhoof Village", map = 1412, at = { 46.63, 61.09 } }, -- guide
        { name = "Orgrimmar", map = 1454, at = { 54.1, 68.4 } }, -- unrecorded
    },
    -- Walled places walked into or out of only at their doors. A whole map
    -- (`map` alone) or a circle on one (`map`, `at`, `radius` in yards). A door
    -- is `kind = "entrance"` (the default, both ways) or `"exit"` (out only),
    -- and may carry a `wait` in seconds. A lift is a door with a `bottom =
    -- { at = { x, y } }` (and `map` when it differs): the door is its top,
    -- the bottom is outside even on the area's own map, and `wait` plus `ride`
    -- is the trip between. Flights, boats and teleports cross walls freely.
    areas = {
        { name = "Orgrimmar", map = 1454, doors = { -- recorded
            { at = { 49.17, 93.38 }, label = "the front gate" },
            { at = { 17.37, 61.29 }, label = "the west gate" },
        } },
        -- The ground round the mesa's foot is on Thunder Bluff's map too, so
        -- only a lift with a recorded bottom can say where the mesa ends.
        { name = "Thunder Bluff", map = 1456, doors = {
            -- recorded 2026-09-23: the top where the arrow's walk arrived, the
            -- bottom where the player stepped off
            { at = { 30.36, 61.69 }, bottom = { at = { 31.77, 65.95 } }, wait = 15, ride = 10, label = "the west lift" },
            { at = { 60.0, 23.0 }, wait = 15, label = "the north lift" }, -- unrecorded, and no bottom yet
        } },
    },
}
