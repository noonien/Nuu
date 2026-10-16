-- The versioned mapping table: what every RestedXP construct becomes in a
-- NuuRoad guide source. This file is the definition of "fully ported".
--
-- Each entry carries a status:
--   mapped     the converter can emit it today
--   todo       it belongs in a full port and the schema cannot hold it yet
--   instruction the source performs an action for the player; NuuRoad ports
--              the words and leaves the doing to them (the player-directed
--              constraint in CLAUDE.md), so this is a deliberate difference,
--              not a gap
--   meta       guide-level bookkeeping, not a step
--   excluded   deliberately left out, with the reason recorded
--   ignored    carries nothing a port needs
--
-- The coverage gate in Tests/GuidePortTests.lua fails on any construct found
-- in the approved sources that has no entry here. A port is complete for a
-- source when nothing it uses is still `todo`.
local Mapping = { version = 5 }

local function entry(status, becomes, note)
    return { status = status, becomes = becomes, note = note }
end

Mapping.commands = {
    -- Route and quests: the part already ported.
    ["goto"] = entry("mapped", "at", "one point, or a list whose first is the arrow target"),
    accept = entry("mapped", "accept"),
    turnin = entry("mapped", "turnin"),
    complete = entry("mapped", "a kill, collect, interact or talk step with quest = { id, n }"),
    collect = entry("mapped", "collect, with starts/quest where the item begins or serves a quest"),
    mob = entry("mapped", "kill"),
    target = entry("mapped", "npc"),
    item = entry("mapped", "item"),
    xp = entry("mapped", "level, with xp into it"),
    fp = entry("mapped", "flight"),
    home = entry("mapped", "hearth"),
    hs = entry("mapped", "travel, with the hearthstone named in the note"),
    skill = entry("mapped", "skill"),
    train = entry("mapped", "train for a profession; a class rank is a note naming the trainer"),
    trainer = entry("mapped", "note naming the trainer"),
    isQuestComplete = entry("mapped", "optional = true on a turn-in: passed unless the quest is ready"),
    isQuestAvailable = entry("todo", "a condition on a quest not taken", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    isOnQuest = entry("todo", "a condition on a quest in the log", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    isQuestTurnedIn = entry("todo", "a condition on a finished quest", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    isQuestNotComplete = entry("todo", "a condition on a quest not ready", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    isNotOnQuest = entry("todo", "a condition on a quest not in the log", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    money = entry("todo", "a condition on gold", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    itemcount = entry("todo", "a condition on an item count",
        "only an accept from an item reads the bags (passed when the item is not there); otherwise the step is written for everyone"),
    aura = entry("todo", "a condition on an aura", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    cooldown = entry("todo", "a condition on a cooldown", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),

    -- Still to build.
    itemStat = entry("todo", "a condition on worn gear", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    vendor = entry("mapped", "a vendor step: { type = \"vendor\", sell = true, npc = { N } }"),
    bindlocation = entry("todo", "a condition on where the hearthstone is bound", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    zoneskip = entry("todo", "a condition on the zone the player is in", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    subzoneskip = entry("todo", "a condition on the subzone the player is in", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    zone = entry("mapped", '{ type = "travel", to = "...", zone = 1413 }', nil),
    subzone = entry("mapped", '{ type = "travel", to = "...", area = 222 }'),
    line = entry("todo", "a drawn route on the world map",
        "its points already carry as map pins; the polyline between them needs a map canvas overlay, and it is decoration on 7 steps"),
    timer = entry("mapped", "wait = N seconds"),

    -- Ported as instructions: the source acts for the player, NuuRoad tells
    -- them what to do. See the Hard constraints in CLAUDE.md.
    use = entry("instruction", "note, or the step's item reference"),
    cast = entry("instruction", "note naming the spell"),
    equip = entry("instruction", "equip step, which observes the slots but does not fill them"),
    abandon = entry("instruction", "note"),
    destroy = entry("instruction", "note"),
    engrave = entry("instruction", "note naming the rune"),
    fly = entry("instruction", "travel, with the flight master named"),
    deathskip = entry("instruction", "note offering the shortcut, never instructing a death"),
    skipgossip = entry("instruction", "nothing; the player picks their own dialog lines"),
    skipgossipid = entry("instruction", "nothing; the player picks their own dialog lines"),
    gossipoption = entry("instruction", "note naming the dialog line or object to click"),
    usespell = entry("instruction", "note naming the spell"),
    emote = entry("instruction", "note naming the emote"),
    dungeon = entry("instruction", "note that the quests are for an instance run"),

    link = entry("excluded", "nothing",
        "an external URL; NuuRoad is offline first and points at no web service"),
    macro = entry("excluded", "nothing",
        "a macro the source builds for the player; guides carry no macros (CLAUDE.md), the step's note says what to do"),
    unitscan = entry("excluded", "nothing",
        "a rare to look out for; a rare whose drop starts a quest is a collect step with kill and starts, and a dangerous one goes in the note"),
    disablecheckbox = entry("ignored", "nothing", "a source UI setting on its step's checkbox"),
    addquestitem = entry("ignored", "nothing",
        "tells the source's item button which quest an item belongs to; a step names its own item"),
}

Mapping.directives = {
    label = entry("mapped", "label"),
    optional = entry("mapped", "a note, or a condition where the source gated it"),
    season = entry("mapped", "cond = { season = N }"),
    hardcore = entry("mapped", "cond = { hardcore = true }"),
    softcore = entry("mapped", "cond = { none = { { hardcore = true } } }"),
    sofcore = entry("mapped", "cond = { none = { { hardcore = true } } }", "a typo in the source for softcore"),
    requires = entry("mapped", "step order", "the required step already runs earlier"),

    completewith = entry("mapped", 'with = "<label>"',
        nil),
    loop = entry("mapped", "loop = true on the step's at list",
        "the arrow already takes the nearest point of any list"),
    sticky = entry("mapped", "sticky = true"),
    include = entry("mapped", "the included registration's steps, written in place"),
    hidewindow = entry("ignored", "nothing", "hides the source's step frame while the step runs"),
    arrowtext = entry("ignored", "nothing", "the source's arrow caption; NuuRoad's arrow shows the step title"),
    xprate = entry("todo", "a condition on the realm's experience rate", "a guide source has no condition for it: the step is written for everyone, and the note says when it applies"),
    ah = entry("mapped", "show = { ah = true }",
        "reads the answer the player gives in Options; unknown until they do"),
    ssf = entry("mapped", "show = { selffound = true }",
        "reads the answer the player gives in Options; unknown until they do"),

    name = entry("meta", "title"),
    group = entry("meta", "tags"),
    subgroup = entry("meta", "tags"),
    groupid = entry("meta", "tags"),
    version = entry("meta", "updated"),
    next = entry("meta", "the closing step's text"),
    defaultfor = entry("meta", "tags"),
    classic = entry("meta", "content flavour"),
    tbc = entry("meta", "content flavour"),
    era = entry("meta", "content flavour"),
    ["era/som"] = entry("meta", "content flavour"),
    ["era/som--h"] = entry("meta", "content flavour"),
}

function Mapping:Lookup(kind, name)
    local table_ = kind == "command" and self.commands or self.directives
    return table_[name]
end

return Mapping
