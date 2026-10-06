-- Guide format v1 (docs/examples/guide-v1.lua) on the wire, as Data/GuideWire.lua
-- shapes it. Never loaded in game: NuuKit/Tools/Codec/Gen.lua reads it and
-- writes Data/GuideCodec.lua (NuuKit/Tools/Codec/Types.lua says what each
-- helper is and how it is written). After a change here, from NuuRoad/:
--
--   lua ../NuuKit/Tools/Codec/Gen.lua Schema/Guide.lua Data/GuideCodec.lua
--
-- The reader and the writer of a string always have the same schema, so
-- anything may be reordered or renumbered: keys and variants are written by
-- position. The most used keys come first, where an object's bitmap is
-- shortest. Tests/GuideWireTests.lua checks the step kinds and the fields
-- any step may carry against GuideDraft's, and that the generated file is
-- this schema's.
local T = ...

-- One value, or a list of them: { "one", v } or { "list", { v, ... } }.
local function OneOrList(t) return T.Union { { "one", t }, { "list", T.List(t) } } end

local IDs = T.List(T.UInt)
local Class = T.Enum { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- UnitRace's tokens, lower case, and WoW: Forever's Skyborne (Data/Steps.lua).
local Race = T.Enum { "orc", "tauren", "troll", "scourge", "human", "dwarf", "gnome", "nightelf", "skyborne" }
local Faction = T.Enum { "Horde", "Alliance" }

-- { x, y } or { x, y, map = }, in hundredths of a map percent.
local Point = T.Tuple { T.UInt, T.UInt, T.ZeroNil(T.UInt) }
-- quest = 924 (the whole quest) or { 871, 1 } (its first objective).
local Quest = T.Union { { "quest", T.UInt }, { "objective", T.Tuple { T.UInt, T.UInt } } }

-- CONDITIONS. Keys, and any/none/all of conditions, two deep: the deepest
-- holds keys only. A deeper one is named in data.conds and used with `is`.
local CondTerm = T.Object {
    { "class", OneOrList(Class) },
    { "faction", OneOrList(Faction) },
    { "race", OneOrList(Race) },
    { "skill", OneOrList(T.UInt) },
    { "is", T.String },
    { "ah", T.True },
    { "selffound", T.True },
    { "season", T.Union { "any", { "number", T.UInt } } },
    { "hardcore", T.True },
}
local function CondLevel(inner)
    local level = T.Extend(CondTerm, { { "any", T.List(inner) }, { "none", T.List(inner) }, { "all", T.List(inner) } })
    return level
end
local Cond = CondLevel(CondLevel(CondTerm))

-- STEPS. A step is its kind (its type and that type's own fields) and the
-- fields any step may carry.
local StepCommon = T.Object {
    { "npc", IDs },
    { "note", T.String },
    { "at", T.List(Point) },
    { "cond", Cond },
    { "quest", Quest },
    { "radius", T.UInt },
    { "item", OneOrList(T.UInt) },
    { "object", T.String },
    { "from", T.String },
    { "label", T.String },
    { "show", Cond },
    { "use", IDs },
    { "sticky", T.True },
    { "with", T.String },
    { "wait", T.UInt },
    { "mark", IDs },
    { "needs", T.List(T.Object {
        { "item", T.UInt }, { "count", T.UInt }, { "source", T.Enum { "gather", "vendor", "ah", "drop", "craft" } },
    }) },
    { "stand", T.String },
    { "upto", T.Object { { "skill", T.UInt }, { "rank", T.UInt } } },
    { "loop", T.True },
    { "near", T.String },
}

-- GuideDraft.typeFields, in its order, without `item` (a StepCommon field).
local StepKind = T.Union {
    "note",
    { "finish", T.Object { { "next", OneOrList(T.String) } } },
    { "travel", T.Object { { "to", T.String }, { "zone", T.UInt }, { "area", T.UInt }, { "instance", T.UInt } } },
    { "accept", T.Object { { "quests", IDs }, { "level", T.UInt }, { "kill", IDs } } },
    { "turnin", T.Object { { "quests", IDs }, { "optional", T.True } } },
    { "talk", T.Object { { "turnin", IDs }, { "accept", IDs }, { "say", IDs }, { "level", T.UInt }, { "optional", T.True } } },
    "escort",
    { "collect", T.Object { { "count", T.UInt }, { "kill", IDs }, { "starts", T.UInt } } },
    { "kill", T.Object { { "kill", IDs }, { "count", T.UInt } } },
    "interact",
    { "gather", T.Object { { "count", T.UInt }, { "skill", T.UInt } } },
    { "craft", T.Object { { "count", T.UInt }, { "skill", T.UInt } } },
    { "skillup", T.Object { { "skill", T.UInt }, { "rank", T.UInt } } },
    { "buy", T.Object { { "count", T.UInt } } },
    { "vendor", T.Object { { "sell", T.True }, { "repair", T.True } } },
    "equip",
    { "train", T.Object { { "skill", T.UInt }, { "rank", T.UInt } } },
    { "learn", T.Object { { "spells", IDs } } },
    { "cast", T.Object { { "spell", T.UInt }, { "count", T.UInt } } },
    { "skill", T.Object { { "skill", T.UInt }, { "rank", T.UInt } } },
    { "reputation", T.Object { { "faction", T.UInt }, { "standing", T.UInt } } },
    { "hearth", T.Object { { "area", T.UInt } } },
    { "flight", T.Object { { "node", T.UInt } } },
    { "level", T.Object { { "level", T.UInt }, { "xp", T.UInt }, { "by", T.String } } },
    { "choice", T.Object { { "text", T.String }, { "options", T.List(T.Object { { "text", T.String }, { "go", T.String } }) } } },
}

local Step = T.Tuple { StepKind, StepCommon }
-- v1's `group` is `steps` here: a group is not a step.
local Group = T.Object { { "steps", T.List(Step) }, { "label", T.String }, { "cond", Cond }, { "show", Cond } }
local Entry = T.Union { { "step", Step }, { "group", Group } }

local Section = T.Object {
    { "title", T.String },
    { "steps", T.List(Entry) },
    { "map", T.UInt },
    { "label", T.String },
    { "cond", Cond },
    { "show", Cond },
}

local Place = T.Object {
    { "id", T.String },
    { "name", T.String },
    { "width", T.UInt },
    { "map", T.UInt },
    { "points", T.List(T.Object {
        { "id", T.String }, { "at", Point }, { "kind", T.Enum { "entrance", "exit" } }, { "label", T.String },
    }) },
    { "links", T.List(T.Object { { "from", T.String }, { "to", T.String }, { "oneway", T.True } }) },
}

-- A name, or one the guide visits: where it stands is a point, several
-- points, or "place.point".
local Npc = T.Union {
    { "name", T.String },
    { "npc", T.Object {
        { "name", T.String },
        { "at", T.Union { { "point", Point }, { "points", T.List(Point) }, { "place", T.String } } },
        { "note", T.String },
        { "instance", T.UInt },
    } },
}

-- kind = "guide" and schema = 1 are what the schema's id says; GuideWire
-- leaves them out and puts them back.
local Guide = T.Object {
    { "id", T.String },
    { "updated", T.UInt },
    { "title", T.String },
    { "category", T.String },
    { "author", T.String },
    { "tags", T.List(T.String) },
    { "levels", T.Object { { "from", T.UInt }, { "to", T.UInt } } },
    { "cond", Cond },
    { "source", T.String },
    { "materials", T.String },
    { "data", T.Object {
        { "map", T.UInt },
        { "sections", T.List(Section) },
        { "npcs", T.Map(T.UInt, T.Map(T.UInt, Npc)) },
        { "conds", T.Map(T.String, Cond) },
        { "places", T.List(Place) },
    } },
}

return T.Schema {
    id = 1,
    root = Guide,
    module = "GuideCodec",
    names = {
        Guide = Guide, Point = Point, Quest = Quest, CondTerm = CondTerm, Cond = Cond, StepCommon = StepCommon,
        StepKind = StepKind, Step = Step, Group = Group, Entry = Entry, Section = Section, Place = Place, Npc = Npc,
        IDs = IDs, Class = Class, Race = Race, Faction = Faction,
    },
}
