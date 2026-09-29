# Client map tools

Guide places (the ways through cities and caves) worked out from the game's own map files instead of walked by
hand, and an offline viewer to check any place against the world map. Nothing here ships with the addon: the
tools read the client's data at build time, and only the resulting points go into a guide.

## Setup (once)

```
nix-shell Tools/ClientMap/shell.nix --run "bash Tools/ClientMap/setup.sh"
```

Builds CascLib (reads the client's CASC data store) and the navmesh tool, and downloads the community listfile (file
IDs to paths), all into `Tools/ClientMap/.cache/`, which git ignores. The Forever beta's files are in the store
shared by every installed WoW product (`World of Warcraft/Data`), as product `wow_classic_beta`.

## Finding caves: the zone browser

```
nix-shell Tools/ClientMap/shell.nix --run "python3 Tools/ClientMap/serve.py"
```

then open http://localhost:8765/zones.html. Pick a zone: its own minimap (the game's textured minimap tiles) with
every model the map files place in it. Caves, mines and dens (the `world/wmo/dungeon/md_*` models) are orange,
dungeon entrances purple, models new in this build teal; buildings and the rest can be switched on; the holes in
the ground (where caves and tunnels open) are red. The zone is read the first time it is opened (`zones.py`, a few
seconds, kept in `.cache/zones/`).

Click a cave, name it, and **Mark for place generation**: the mark goes to `marks.json` beside these tools (kept in
the repository), and `regions.py` makes a region of it (the cave's model, its box and 40 yd round it, the ground
within 40 yd of the cave floor as the way in, every branch kept). **Generate place** runs `build.py` for it (every
step below, about half a minute for a cave) and **Open place** shows it in the place viewer.

`python3 Tools/ClientMap/build.py <region>` does the same from the command line for any region.

## Exploring a zone in 3D

http://localhost:8765/scene.html?zone=1412 (or **Open in 3D** on a cave in the zone browser). A zone is baked once:
the page offers a **Bake** button, or `python3 Tools/ClientMap/scene/bake.py <map>` with the server running. Mulgore
(108 tiles, 1,584 models) takes a few minutes and about 500 MB in `.cache/scene/`:

- `scene/bake.py` writes each map tile's ground as a GLB (full detail and a low one, holes left out, under the tile's
  own baked ground texture), the tile's texture layers (each chunk's up to eight tiling textures, their blend maps
  as two RGBA pictures, the textures themselves once in `.cache/scene/textures/`) and its placements (every WMO and M2 on it, the props WMOs set out included, as ready
  4x4 matrices);
- `scene/models.js` bakes every model the tiles use to GLB with wow.export's own exporters (MIT, cloned into
  `.cache/wow.export` by `setup.sh`), textures inside, once per model.

The page (three.js, beside it in `.cache/viewer/vendor`) streams tiles round the camera: full ground to two tiles,
drawn as the game draws it (each chunk's textures blended by its blend maps, each projected from above and from the
sides by the slope, so cliffs get rock and not the top's pixels drawn out down them), the low ground with its baked
picture to four tiles, buildings and props on the nine tiles round it, each model loaded once and drawn instanced.
Built places are drawn as lines. Fly as in the other 3D view (drag to look, W/S along the view, A/D sideways, Q/E
turn, Space/R and X/F up and down, Shift faster, wheel for speed). A cave sits inside its hill as in the game:
switch **Ground** off to see it and its place.

## Making a place

Run from the addon root, each step inside `nix-shell Tools/ClientMap/shell.nix`:

```
python3 Tools/ClientMap/extract.py undercity      # the city's collision triangles -> .cache/undercity.obj
Tools/ClientMap/.cache/navmesh Tools/ClientMap/.cache/undercity.obj Tools/ClientMap/.cache/undercity.bin
python3 Tools/ClientMap/skeleton.py undercity > Tools/ClientMap/.cache/undercity.place.lua
python3 Tools/ClientMap/rooms.py undercity                     # rooms, halls, corridors, stairs, water
python3 Tools/ClientMap/view.py undercity [other.place.lua ...]   # -> .cache/viewer/index.html
```

1. **extract.py** reads the map tiles under the region's area and writes, in world coordinates: the ground
   (terrain, holes left out), every WMO in the area with its liquid surfaces (`.liquid.json`), and the props (M2)
   with a collision shell, both those the tiles place and those the WMOs set out. Each triangle is tagged terrain,
   model or prop. As a check it says how many place recorder samples on the map stand
   over one of its floors (all 931 for Undercity).
2. **navmesh** (C++, Recast) turns the triangles into the walkable area for a player (radius 0.5 yd, height 2,
   steps up to 1.6 yd, slopes up to 50 degrees): columns of half-yard cells, several floors per column where levels
   stack, each with its distance to the nearest edge and what it is made of (terrain, model, prop).
3. **skeleton.py** makes the place from the geometry alone. It fills small obstacles (pillars, stalls), thins every
   floor to its centre lines and traces them into a graph, joins the region's lifts, keeps what can be reached from
   the biggest floor (so roofs and closed rooms fall away), and leaves points at junctions and only where a straight
   line would otherwise leave the floor. `keep=core` (the default) drops branches that lead nowhere but keeps the
   ways to lifts and exits; `keep=all` keeps every branch. Recorded trails are not an input: at the end it only
   says how many trail samples lie within 5 yd of the place, as a check. Prints the place as guide source and
   writes `.cache/<region>.graph.json` for the viewer.
4. **rooms.py** splits the place's floors into regions and names each: water (floor more than 1.2 yd under a liquid
   surface: canals, pools), stairs or ramp, corridor (a tunnel or street: long for its width), hall (large or wide),
   crossing (a small space where corridors meet) and room, with the doorways between them (a passage narrowing to 2
   to 4 yd, under 60% of the room either side). It cuts the centre lines at doorways and stairs, joins the pieces
   that are one space (junctions whose widest circles overlap, the short passage inside a junction's circle, and the
   two passages that run on through a junction), and gives every floor cell to the nearest piece. Writes
   `.cache/<region>.rooms.json` (each region's kind, area, width, length, floor heights, doorways, neighbours) and
   `.rooms.npy` (the region of every walkable cell). Undercity: about 450 regions and 140 doorways.
5. **view.py** adds the region to one viewer for every region built so far: `.cache/viewer/index.html`, with a
   picker at the top; each region's data is `.cache/viewer/data/<region>.js`, loaded when picked. The address keeps
   the region, the tab and the rooms layer (`index.html#region=orgrimmar&3d&rooms`).
   Besides the world map art, the Map tab has two pictures of the map itself: the **Minimap** (the game's own
   textured minimap tiles, ground and buildings from above) and a **Floor plan** drawn from the geometry (the
   place's floors shaded by height, dark where something stands 0.3 to 2.2 yd above them, water in blue; ceilings
   are left out, so a city underground reads as a plan). The 3D tab's **Map geometry (textured)** draws the WMOs
   with their own textures (one atlas, 128 px a texture), the ground under its tiles' baked terrain texture, and
   the props as their grey collision shells; it is a separate file (`data/<region>.geo.js`) loaded when switched
   on. A slider cuts away everything above a height, to look into a city or a mine, and **Top view** looks straight
   down. In 3D the camera flies like a character with no gravity and no collisions: drag to look round, W/S forward and
   back where you look, A/D step sideways, Q/E turn, Space/R up, X/F down, Shift faster, the wheel sets the speed.
   On the map, W/A/S/D pan and Q/E zoom. The Map tab: the world map, the walkable area coloured by
   height (grey: walkable but not part of the place), the centre lines, the computed place with its lifts and ways
   out, and any place files given, each a layer to switch on and off; wheel zooms, drag
   pans, hovering a point gives its number, position, height and room round it. A Rooms layer colours the regions
   by kind with their doorways; hovering one says what it is. The 3D tab: the place's floors as
   a lit surface coloured by height over the world map, with the place and the lifts on them; drag
   turns, right-drag moves, wheel zooms, a slider stretches heights, and the floors can be coloured by room.

The viewer takes any place written as guide source, so it also checks places made with the in-game recorder
(`Tools/ProcessPlace.lua` output) or written by hand.

## Comparing ways of pathing a place

skeleton.py is one way to make a place; others live in `methods/`, one build script and one router each, and are
measured on the same trips:

```
python3 Tools/ClientMap/bench.py venturemine                   # the trips and their true shortest walks
python3 Tools/ClientMap/bench.py venturemine --score-current   # today's place as the baseline
python3 Tools/ClientMap/methods/<method>.py venturemine        # a method's data, drawing and score
python3 Tools/ClientMap/view.py venturemine
```

**bench.py** takes the floor the region's entrance stands on (`ENTRANCES`; the Venture Co. Mine is the benchmark)
and picks 46 trips: from the entrance to the ends of the branches, random ones, pairs close on the map but far
apart on foot, and targets with another floor above or below. The truth for each is the shortest walk over the
navmesh's cells, pulled straight. `check()` walks a method's route leg by leg through the floor's own links (so it
stays on its level) and says whether every leg can be walked straight, its length against the truth and how far
it keeps from the walls; `score()` does it for every trip and writes `.cache/<region>.score.<method>.json`.
Routes are given map % only, as the game gives them: heights are for building and drawing, never for routing.

**In the viewer** each method's layers sit with the others, and the Route test picks a trip (or a start and a
target clicked on the map) and draws every method's route in its colour, with the true walk dashed white and
each route's length, bends and time. A method is `.cache/<region>.method.<id>.json` (layers and data) and
`methods/<id>.js` (its router); `view.py`'s `method_overlays` describes both.

## Maps

`maps.py` describes every world map as the client does (`.cache/maps.json`): its name, continent, where its 0-100 %
square sits in world yards (UiMapAssignment), and the tiles of its art (UiMapXMapArt, UiMapArtTile; the Forever
beta uses its own `_c60` art). `db2.py` reads those tables (WDC3 to WDC5), with columns from the WoWDBDefs
definitions, downloaded once into `.cache/dbd/`. Undercity's frame from the tables matches the one fitted from 931
recorder samples to 0.01 yd.

## Adding a region

Add it to `regions.py`: the UiMap ID, and what makes up its ground: `crop` (the part of the map, as map %), `terrain`
(on, off, or `"approach"`: only the ground within `approach` yards of a model's floor, the way into a cave),
`models` (only these WMO file IDs), `props`, and its `lifts`, `exits` and default `keep`. Lifts are not in the map
files; find them in the 3D view (a floor that stops short over a landing far below) or from a recorded ride.

Regions so far: `undercity` (one WMO, no terrain), `bristleback` (the Mulgore cave of
`nuuroad:fixture:cave-place`: its WMO and the hillside at its mouth), `orgrimmar` and `thunderbluff` (the whole
map: terrain, WMOs and props; not bounded to the city yet).

## Notes on the client's files

- Newer WMO groups keep each triangle's flags and material in MPY2 (two bytes each) instead of MOPY, and may use
  32-bit indices (MOVX). A triangle collides when it is flagged for collision, or drawn and not detail, as the
  server's own extractor (TrinityCore's vmap4_extractor) reads it.
- The Forever beta does not keep every texture on disk (it fetches some when first drawn). A texture it lacks is
  read from the other products in the same store (Classic Era, Anniversary, retail), where the same file ID is the
  same picture. Models and maps are only ever read from the beta.

## Limits

- Lifts and moving platforms are not in the map files (the server spawns them); each is one line in `regions.py`.
- Props are their collision shells: in 3D they show as rough grey shapes, not as the models the game draws.
- Heights are known here but not in the game, so a place still only says map positions.
