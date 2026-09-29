-- The versioned mapping table: what every RestedXP construct becomes in the
-- NuuRoad v2 format. This file is the definition of "fully ported".
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
local Mapping = { version = 3 }

local function entry(status, becomes, note)
    return { status = status, becomes = becomes, note = note }
end

Mapping.commands = {
    -- Route and quests: the part already ported.
    ["goto"] = entry("mapped", "at", "one point, or a list whose first is the arrow target"),
    accept = entry("mapped", "accept"),
    turnin = entry("mapped", "turnin"),
    complete = entry("mapped", "objective + part"),
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
    isQuestComplete = entry("mapped", 'only = "quest N readyToTurnIn"'),
    isQuestAvailable = entry("mapped", 'only = "not quest N"'),
    isOnQuest = entry("mapped", 'only = "quest N accepted"'),
    isQuestTurnedIn = entry("mapped", 'only = "quest N finished"'),
    isQuestNotComplete = entry("mapped", 'only = "not quest N readyToTurnIn"'),
    isNotOnQuest = entry("mapped", 'only = "not quest N accepted"'),
    money = entry("mapped", 'only = "gold N"'),
    itemcount = entry("mapped", 'only = "item N xC"'),
    aura = entry("mapped", 'only = "aura N"', "needs the aura predicate registered"),
    cooldown = entry("mapped", 'only = "cooldown ..."', "needs the cooldown predicate registered"),

    -- Still to build.
    itemStat = entry("mapped", 'only = "slot 16 dps < 4.2"',
        "quality reads directly; damage per second is read off the tooltip and is unknown where that fails"),
    vendor = entry("mapped", "a vendor step: { vendor = \"sell\", npc = N }"),
    bindlocation = entry("mapped", 'only = "hearth <name>"'),
    zoneskip = entry("mapped", 'only = "not zone <mapID>"'),
    subzoneskip = entry("mapped", 'only = "not subzone <name>"'),
    zone = entry("mapped", '{ travel = "...", zone = "The Barrens" }', nil),
    subzone = entry("mapped", '{ travel = "...", subzone = "Bloodhoof Village" }'),
    line = entry("todo", "a drawn route on the world map",
        "its points already carry as map pins; the polyline between them needs a map canvas overlay, and it is decoration on 7 steps"),
    unitscan = entry("mapped", "watch = N", nil),
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
    disablecheckbox = entry("ignored", "nothing", "a source UI setting on its step's checkbox"),
}

Mapping.directives = {
    label = entry("mapped", "label"),
    optional = entry("mapped", "a note, or a condition where the source gated it"),
    season = entry("mapped", 'only = "season N"'),
    hardcore = entry("mapped", 'only = "hardcore"'),
    softcore = entry("mapped", 'only = "not hardcore"'),
    sofcore = entry("mapped", 'only = "not hardcore"', "a typo in the source for softcore"),
    requires = entry("mapped", "step order", "the required step already runs earlier"),

    completewith = entry("mapped", 'with = "next" or with = "<label>"',
        nil),
    loop = entry("mapped", "loop = true on the step's at list",
        "the arrow already takes the nearest point of any list"),
    sticky = entry("mapped", "sticky = true"),
    include = entry("mapped", "the included registration's steps, written in place"),
    hidewindow = entry("ignored", "nothing", "hides the source's step frame while the step runs"),
    arrowtext = entry("ignored", "nothing", "the source's arrow caption; NuuRoad's arrow shows the step title"),
    xprate = entry("mapped", 'only = "xprate < 1.5"',
        "reads the rate the player states in Options; unknown until they do"),
    ah = entry("mapped", 'only = "auctionhouse"',
        "reads the answer the player gives in Options; unknown until they do"),
    ssf = entry("mapped", 'only = "selffound"',
        "reads the answer the player gives in Options; unknown until they do"),

    name = entry("meta", "meta.title"),
    group = entry("meta", "meta.tags"),
    subgroup = entry("meta", "meta.tags"),
    groupid = entry("meta", "meta.tags"),
    version = entry("meta", "updated"),
    next = entry("meta", "the closing step's text"),
    defaultfor = entry("meta", "meta.tags"),
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
