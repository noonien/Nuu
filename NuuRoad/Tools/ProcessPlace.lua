-- Works a guide place out of a place recorder trail, outside the game, and
-- prints it as guide source for a guide's `places = { ... }` list.
--
--   lua Tools/ProcessPlace.lua Tools/SessionLog/places/<file>.lua [snap=5] [spacing=15] [outdoors] [place=cave]
--
-- The trail files come from `python3 Tools/SessionLog/places.py`. The
-- settings are the walk recorder's (Domain/PlaceEditing.lua): `snap` is how
-- near a point must be to be reused, in yards; `spacing` how far apart new
-- points are on a straight passage; `outdoors` keeps what was recorded
-- outdoors too; `place` is the ID to give it. Run from the addon root.
local path = arg[1]
if not path then
    io.stderr:write("usage: lua Tools/ProcessPlace.lua <trail.lua> [snap=5] [spacing=15] [outdoors] [place=id]\n")
    os.exit(1)
end
-- The addon's files take (addon name, ns), as the client runs them.
dofile("Tests/Support/Namespace.lua")
local ns = NewNamespace()
Load(ns, "Domain/PlaceEditing.lua")
local Editing = ns.modules.PlaceEditing

local options = { indoorsOnly = true }
for index = 2, #arg do
    local key, value = arg[index]:match("^(%w+)=(.+)$")
    if arg[index] == "outdoors" then options.indoorsOnly = false
    elseif key == "snap" then options.snapYards = tonumber(value)
    elseif key == "spacing" then options.sampleYards = tonumber(value)
    elseif key == "place" then options.place = value
    else io.stderr:write("unknown setting: " .. arg[index] .. "\n"); os.exit(1) end
end
local trail = dofile(path)
options.place = options.place or trail.place or "recorded"
local place, stats = Editing.Process(trail, options)
io.stderr:write(string.format("%d samples, %d marks -> %d points, %d connections (%d straight-line points tidied)\n",
    #(trail.samples or {}), #(trail.marks or {}), #place.points, #place.connections, stats.removed))
print(Editing.Serialize(place))
