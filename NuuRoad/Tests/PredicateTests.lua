_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/IDNames.lua")
Load(ns, "Data/Steps.lua")
local Client, Schema, Steps = ns.modules.Client, ns.modules.Schema, ns.modules.Steps

-- The suites share one Lua state, so a stub left behind by an earlier one
-- would answer before these do. Start from nothing and leave nothing behind.
local stubbed = {
    "C_Item", "C_Seasons", "C_GameRules", "C_QuestLog", "C_Map", "GetMoney", "GetItemCount",
    "UnitLevel", "UnitClass", "UnitRace", "UnitFactionGroup", "IsQuestFlaggedCompleted",
    "IsInInstance", "IsPlayerSpell", "IsSpellKnown", "SendChatMessage", "GetSkillLineInfo",
    "GetNumSkillLines",
}
local function clearStubs()
    for _, name in ipairs(stubbed) do _G[name] = nil end
end
clearStubs()

-- The registry is what a condition is checked against: who the character
-- is, the realm, what the player has chosen (`cond` and `show`), and the two
-- terms a step works out from its own fields.
local registered = { "auctionHouse", "class", "faction", "hardcore", "item", "profession", "quest", "race", "season", "selfFound" }
assert(table.concat(Client:PredicateKinds(), ",") == table.concat(registered, ","),
    "the registry holds exactly the remaining kinds, got " .. table.concat(Client:PredicateKinds(), ","))
for _, kind in ipairs({ "level", "experience", "skill", "equippedItem", "gold", "reputation", "spell", "zone",
    "instance", "hearth", "subzone", "slot", "aura", "cooldown", "xprate", "lua" }) do
    assert(not Client:HasPredicate(kind), "a removed predicate is gone: " .. kind)
    assert(Client:EvaluateCondition({ type = kind }) == nil, "a removed predicate is unknown: " .. kind)
end
assert(not Client:HasPredicate("nonsense"))
assert(Client:HasPredicate("all") and Client:HasPredicate("any") and Client:HasPredicate("not") and Client:HasPredicate("now"),
    "the combinators are always available")

-- Anti-drift: Schema's list (what it accepts without the client loaded) and
-- the client's registry are the same set, both ways.
for kind in pairs(Schema.predicateKinds) do
    assert(Client:HasPredicate(kind), "Schema names a predicate nothing implements: " .. kind)
end
for _, kind in ipairs(Client:PredicateKinds()) do
    assert(Schema.predicateKinds[kind], "the client implements a predicate Schema does not name: " .. kind)
end

Client:RegisterPredicate("fixture", function(predicate) return predicate.answer end)
assert(Client:EvaluateCondition({ type = "fixture", answer = true }) == true)
assert(Client:EvaluateCondition({ type = "fixture", answer = false }) == false)
assert(Client:EvaluateCondition({ type = "fixture", answer = nil }) == nil, "nil is unknown, not false")
Client:RegisterPredicate("boom", function() error("predicate blew up") end)
assert(Client:EvaluateCondition({ type = "boom" }) == nil, "a predicate that raises is unknown")
assert(Client:EvaluateCondition({ type = "neverRegistered" }) == nil, "an unregistered kind is unknown")

-- Three-valued combinators.
local yes, no, dunno = { type = "fixture", answer = true }, { type = "fixture", answer = false }, { type = "boom" }
assert(Client:EvaluateCondition({ type = "all", children = { yes, yes } }) == true)
assert(Client:EvaluateCondition({ type = "all", children = { yes, no } }) == false)
assert(Client:EvaluateCondition({ type = "all", children = { yes, dunno } }) == nil)
assert(Client:EvaluateCondition({ type = "all", children = { no, dunno } }) == false, "one false settles all")
assert(Client:EvaluateCondition({ type = "any", children = { no, no } }) == false)
assert(Client:EvaluateCondition({ type = "any", children = { no, dunno } }) == nil)
assert(Client:EvaluateCondition({ type = "any", children = { yes, dunno } }) == true, "one true settles any")
assert(Client:EvaluateCondition({ type = "not", child = dunno }) == nil, "unknown stays unknown under not")
assert(Client:EvaluateCondition({ type = "not", child = no }) == true)
assert(Client:MatchesCondition(dunno), "a condition the client cannot judge never hides a step")
assert(not Client:MatchesCondition(no))
Client.predicates.fixture, Client.predicates.boom = nil, nil

-- Registered kinds read the client, and say unknown when it cannot answer.
assert(Client:EvaluateCondition({ type = "season", id = 2 }) == nil, "no season API is unknown")
C_Seasons = { GetActiveSeason = function() return 2 end }
assert(Client:EvaluateCondition({ type = "season", id = 2 }) == true)
assert(Client:EvaluateCondition({ type = "season", id = 1 }) == false)
assert(Client:EvaluateCondition({ type = "season" }) == true, "a bare season asks whether any is active")
assert(Client:EvaluateCondition({ type = "hardcore" }) == nil, "no hardcore API is unknown")
C_GameRules = { IsHardcoreActive = function() return false end }
assert(Client:EvaluateCondition({ type = "hardcore" }) == false)
GetItemCount = function(id) return id == 2495 and 2 or 0 end
assert(Client:EvaluateCondition({ type = "item", id = 2495 }) == true)
assert(Client:EvaluateCondition({ type = "item", id = 2495, count = 3 }) == false)

-- A guide's `cond` and `show`, every key: each becomes a registered kind and
-- the guide validates.
local function guide(steps, conds)
    return { kind = "guide", schema = 1, id = "nuuroad:test:kinds", updated = 1,
        title = "Predicate fixture", category = "test",
        data = { map = 1412, conds = conds, sections = { { title = "S", steps = steps } } } }
end
local expanded = Steps:Expand(guide({
    { type = "note", note = "warrior", cond = { class = "WARRIOR" } },
    { type = "note", note = "season", cond = { season = 2 } },
    { type = "note", note = "skill", show = { skill = 186 } },
    { type = "note", note = "profession", show = { skill = { 393, 186 } } },
    { type = "note", note = "ah", show = { ah = true } },
    { type = "note", note = "selffound", show = { selffound = true } },
    { type = "note", note = "hardcore", cond = { hardcore = true } },
    { type = "note", note = "neither", cond = { none = { { class = "WARRIOR" }, { class = "DRUID" } } } },
    { type = "note", note = "faction", cond = { faction = "Horde" } },
    { type = "note", note = "race", cond = { race = { "orc", "troll" } } },
    { type = "note", note = "named", cond = { is = "orcs" } },
}, { orcs = { race = "orc" } }))
local ok, problems = Schema:Validate(expanded)
assert(ok, table.concat(problems or {}, "; "))
local nodes = expanded.nodes
assert(nodes[1].condition.type == "class" and nodes[1].condition.values[1] == "WARRIOR")
assert(nodes[2].condition.type == "season" and nodes[2].condition.id == 2)
assert(nodes[3].condition.type == "now" and nodes[3].condition.child.type == "profession"
    and nodes[3].condition.child.name == "Mining", "a skill is named by its SkillLine name, read as it stands")
assert(nodes[4].condition.child.type == "any" and #nodes[4].condition.child.children == 2)
assert(nodes[5].condition.type == "now" and nodes[5].condition.child.type == "auctionHouse")
assert(nodes[6].condition.type == "now" and nodes[6].condition.child.type == "selfFound")
assert(nodes[7].condition.type == "hardcore")
assert(nodes[8].condition.type == "not" and nodes[8].condition.child.type == "any")
assert(nodes[11].condition.type == "race" and nodes[11].condition.values[1] == "orc", "`is` names data.conds")
local function leaves(predicate, visit)
    if predicate.type == "all" or predicate.type == "any" then
        for _, child in ipairs(predicate.children) do leaves(child, visit) end
    elseif predicate.type == "not" or predicate.type == "now" then
        leaves(predicate.child, visit)
    else
        visit(predicate)
    end
end
for _, node in ipairs(nodes) do
    leaves(node.condition, function(leaf) assert(Client:HasPredicate(leaf.type), "unregistered kind: " .. leaf.type) end)
end

-- Conditions read back as the editor's text.
assert(Steps:DescribeCondition(nodes[1].condition) == "Warrior")
assert(Steps:DescribeCondition(nodes[2].condition) == "season 2")
assert(Steps:DescribeCondition(nodes[3].condition) == "skill Mining", "the `now` in front of a show key is not said")
assert(Steps:DescribeCondition(nodes[4].condition) == "skill Skinning or skill Mining")
assert(Steps:DescribeCondition(nodes[5].condition) == "ah")
assert(Steps:DescribeCondition(nodes[6].condition) == "selffound")
assert(Steps:DescribeCondition(nodes[7].condition) == "hardcore")
assert(Steps:DescribeCondition(nodes[9].condition) == "Horde")
assert(Steps:DescribeCondition(nodes[10].condition) == "Orc or Troll")

-- The editor's text, every key it takes.
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
assert(same(Steps:ParseCondition("Horde"), { type = "faction", values = { "Horde" } }))
assert(same(Steps:ParseCondition("Warrior or Shaman"), { type = "any", children = {
    { type = "class", values = { "WARRIOR" } }, { type = "class", values = { "SHAMAN" } } } }))
assert(same(Steps:ParseCondition("not Tauren"), { type = "not", child = { type = "race", values = { "tauren" } } }))
assert(same(Steps:ParseCondition("undead"), { type = "race", values = { "scourge" } }))
assert(same(Steps:ParseCondition("season 2"), { type = "season", id = 2 }))
assert(same(Steps:ParseCondition("season"), { type = "season" }))
assert(same(Steps:ParseCondition("hardcore"), { type = "hardcore" }))
assert(same(Steps:ParseCondition("skill Mining"), { type = "now", child = { type = "profession", name = "Mining" } }))
assert(same(Steps:ParseCondition("skill 186"), Steps:ParseCondition("skill mining")), "a skill by ID or by name")
assert(same(Steps:ParseCondition("ah"), { type = "now", child = { type = "auctionHouse" } }))
assert(same(Steps:ParseCondition("selffound"), { type = "now", child = { type = "selfFound" } }))
local joined = Steps:ParseCondition("Horde | not Tauren | Warrior or Shaman")
assert(joined.type == "all" and #joined.children == 3, "a bar joins groups that must all hold")
assert(Steps:ParseCondition("") == nil and Steps:ParseCondition("  ") == nil and Steps:ParseCondition(nil) == nil)
for _, text in ipairs({ "banana", "level 10", "quest 858", "item 2495", "gold 5000", "skill Nonsense", "now item 4470" }) do
    assert(not pcall(Steps.ParseCondition, Steps, text), "not a condition the editor takes: " .. text)
end
assert(Steps:Condition(nil) == nil)
assert(same(Steps:Condition({ faction = "Horde", ah = true }), { type = "now", child = { type = "all", children = {
    { type = "auctionHouse" }, { type = "faction", values = { "Horde" } } } } }),
    "a cond that asks what show asks is read as it stands")

local badTerm, message = pcall(Steps.Expand, Steps, guide({ { type = "note", note = "x", cond = { banana = true } } }))
assert(not badTerm and message:find("data.sections[1].steps[1].cond.banana: is not a condition", 1, true),
    "an unknown condition key is refused at load: " .. tostring(message))
badTerm, message = pcall(Steps.Expand, Steps, guide({ { type = "note", note = "x", cond = { is = "missing" } } }))
assert(not badTerm and message:find("no condition named 'missing'", 1, true), tostring(message))
badTerm, message = pcall(Steps.Expand, Steps, guide({ { type = "note", note = "x", cond = { is = "loop" } } }, { loop = { is = "loop" } }))
assert(not badTerm and message:find("names itself", 1, true), tostring(message))
-- `only` strings are gone: a step's unknown fields are not read, so one
-- gates nothing.
assert(Steps:Expand(guide({ { type = "note", note = "x", only = "Warrior" } })).nodes[1].condition == nil,
    "`only` strings are gone")

-- A condition on its own, with no client: who the character is, the realm,
-- and the player's choices. Used to hold the text round trip to the meaning,
-- not only to the words.
local function holds(predicate, who)
    local kind = predicate.type
    if kind == "all" or kind == "any" then
        for _, child in ipairs(predicate.children) do
            local result = holds(child, who)
            if kind == "all" and not result then return false end
            if kind == "any" and result then return true end
        end
        return kind == "all"
    end
    if kind == "not" then return not holds(predicate.child, who) end
    if kind == "now" then return holds(predicate.child, who) end
    local function among(value)
        for _, entry in ipairs(predicate.values) do if entry:lower() == value:lower() then return true end end
        return false
    end
    if kind == "class" then return among(who.class) end
    if kind == "race" then return among(who.race) end
    if kind == "faction" then return among(who.faction) end
    if kind == "season" then return predicate.id == nil and who.season > 0 or who.season == predicate.id end
    if kind == "hardcore" then return who.hardcore end
    if kind == "profession" then return who.skills[predicate.name] == true end
    if kind == "auctionHouse" then return who.ah end
    if kind == "selfFound" then return who.selffound end
    error("no meaning for " .. tostring(kind))
end
local characters = {}
for _, class in ipairs({ "WARRIOR", "SHAMAN", "MAGE", "DRUID" }) do
    for _, race in ipairs({ "orc", "troll", "tauren", "human" }) do
        for _, flags in ipairs({ { false, false, false, 0 }, { true, true, false, 2 }, { false, true, true, 1 }, { true, false, true, 2 } }) do
            table.insert(characters, { class = class, race = race, faction = race == "human" and "Alliance" or "Horde",
                hardcore = flags[1], ah = flags[2], selffound = flags[3], season = flags[4],
                skills = { Mining = flags[2], Skinning = flags[3] } })
        end
    end
end

-- The shipped condition fixture is the parity case: the editor's "Shown
-- when" tab reads each step's written condition as text and writes it back,
-- and what it writes back must be the condition the step had.
ns.packagedGuides = {}
Load(ns, "Dev/Fixtures/ConditionFixture.lua")
local fixture = Steps:Expand(ns.packagedGuides[1])
ns.packagedGuides = nil
ok, problems = Schema:Validate(fixture)
assert(ok, "condition fixture: " .. table.concat(problems or {}, "; "))
-- Every step is checked before the suite fails, so one run names them all;
-- the failures are raised at the end of the suite.
local gated, roundTrip = 0, {}
for _, node in ipairs(fixture.nodes) do
    if node.condition then
        gated = gated + 1
        local written, derived = Steps:SplitCondition(node.condition)
        assert(written and #derived == 0, "the fixture's conditions are all written: " .. node.body)
        local text = Steps:DescribeCondition(written)
        assert(text, "every written condition reads as text: " .. node.body)
        local reparsed = Steps:ParseCondition(text)
        local problem
        if Steps:DescribeCondition(reparsed) ~= text then
            problem = "reads back as '" .. tostring(Steps:DescribeCondition(reparsed)) .. "'"
        elseif (reparsed.type == "now") ~= (written.type == "now") then
            problem = "is no longer read as it stands"
        else
            for _, who in ipairs(characters) do
                if holds(reparsed, who) ~= holds(written, who) then
                    problem = "means something else for a " .. who.race .. " " .. who.class
                    break
                end
            end
        end
        if problem then table.insert(roundTrip, "'" .. text .. "' (" .. node.body .. ") " .. problem) end
    end
end
assert(gated == 14, "the fixture covers every key, got " .. gated)

-- Splitting a step's condition keeps the terms it worked out for itself: an
-- optional turn-in's ready quests, an item accept's item. The editor writes
-- only the written half and joins the derived terms back on.
local derivedGuide = Steps:Expand(guide({
    { type = "turnin", quests = { 870, 871 }, optional = true, cond = { class = "WARRIOR" } },
    { type = "accept", quests = { 819 }, item = 4926 },
    { type = "talk", turnin = { 872 }, accept = { 873 }, npc = { 3429 }, optional = true, show = { ah = true } },
    { type = "turnin", quests = { 874 }, optional = true },
}))
ok, problems = Schema:Validate(derivedGuide)
assert(ok, table.concat(problems or {}, "; "))
local turnin = derivedGuide.nodes[1].condition
local written, derived = Steps:SplitCondition(turnin)
assert(same(written, { type = "class", values = { "WARRIOR" } }))
assert(#derived == 1 and derived[1].derived and derived[1].type == "now" and derived[1].child.type == "any"
    and derived[1].child.children[1].type == "quest" and derived[1].child.children[1].state == "readyToTurnIn")
assert(Steps:DescribeCondition(derived[1]) == "now quest 870 readyToTurnIn or now quest 871 readyToTurnIn",
    "a derived term is said as what it waits on, `now` on each quest")
assert(Steps:DescribeCondition(derivedGuide.nodes[4].condition) == "now quest 874 readyToTurnIn")
assert(same(Steps:JoinCondition(written, derived), turnin), "split and joined, the condition is the same")
-- An edit replaces the written half and keeps the derived one.
local edited = Steps:JoinCondition(Steps:ParseCondition("Shaman"), derived)
assert(edited.type == "all" and edited.children[1].values[1] == "SHAMAN" and edited.children[2] == derived[1])
-- Cleared, only the derived terms are left.
assert(Steps:JoinCondition(nil, derived) == derived[1])

local accept = derivedGuide.nodes[2].condition
written, derived = Steps:SplitCondition(accept)
assert(written == nil and #derived == 1 and derived[1].child.type == "item" and derived[1].child.id == 4926,
    "an item accept waits on the item")
assert(Steps:DescribeCondition(accept) == "now item 4926")
assert(same(Steps:JoinCondition(written, derived), accept))
edited = Steps:JoinCondition(Steps:ParseCondition("Horde"), derived)
assert(edited.type == "all" and #edited.children == 2 and edited.children[2].derived)

written, derived = Steps:SplitCondition(derivedGuide.nodes[3].condition)
assert(written.type == "now" and written.child.type == "auctionHouse" and #derived == 1 and derived[1].derived)
assert(same(Steps:JoinCondition(written, derived), derivedGuide.nodes[3].condition))
written, derived = Steps:SplitCondition(derivedGuide.nodes[4].condition)
assert(written == nil and #derived == 1, "a lone derived term is all derived")
assert(Steps:SplitCondition(nil) == nil)
assert(Steps:JoinCondition(nil, {}) == nil)

-- Only who the character is rules a step out; a quest, an item or a
-- profession may yet come.
UnitRace = function() return "Orc", "Orc" end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitFactionGroup = function() return "Horde" end
assert(Client:RulesOut(Steps:ParseCondition("Alliance")), "the wrong faction rules a step out")
assert(Client:RulesOut(Steps:ParseCondition("Tauren or Troll")), "the wrong race rules a step out")
assert(Client:RulesOut(Steps:ParseCondition("not Warrior")))
assert(not Client:RulesOut(Steps:ParseCondition("Orc")))
assert(Client:RulesOut(Steps:ParseCondition("season 1")), "the wrong season rules a step out")
assert(Client:RulesOut(Steps:ParseCondition("hardcore")), "so does a hardcore step on a normal realm")
assert(not Client:RulesOut(Steps:ParseCondition("skill Mining")), "a profession not learnt yet is not ruled out")
assert(not Client:RulesOut(Steps:ParseCondition("ah")), "nor is a realm answer")
local quest858 = { type = "quest", id = 858 }
local ready900 = { type = "quest", id = 900, state = "readyToTurnIn" }
assert(not Client:RulesOut({ type = "any", children = { { type = "race", values = { "tauren" } }, ready900 } }),
    "a term that may still come keeps it")
assert(Client:RulesOut({ type = "all", children = { { type = "race", values = { "tauren" } }, { type = "not", child = quest858 } } }),
    "a fixed term that fails settles all")
assert(not Client:RulesOut(nil))

-- What could still open: a quest or an item the player can gain is waited
-- on; a `not` term already settled and a wrong race are not.
C_QuestLog = { IsOnQuest = function(id) return id == 858 end, IsQuestFlaggedCompleted = function() return false end }
assert(Client:CouldOpen(ready900), "a quest not taken yet may come")
assert(Client:CouldOpen({ type = "item", id = 4470 }))
assert(not Client:CouldOpen({ type = "not", child = quest858 }), "a quest already taken does not go away")
assert(Client:CouldOpen({ type = "not", child = { type = "quest", id = 900 } }))
assert(not Client:CouldOpen(Steps:ParseCondition("Tauren or Troll")), "the wrong race never opens")
assert(Client:CouldOpen({ type = "any", children = { { type = "race", values = { "tauren" } }, ready900 } }))
assert(not Client:CouldOpen({ type = "all", children = { { type = "quest", id = 900 }, { type = "not", child = quest858 } } }),
    "one settled `not` closes it")
assert(Client:CouldOpen(nil))

-- A bar joins groups that must all hold.
assert(Client:RulesOut(Steps:ParseCondition("Hunter | Horde")), "the class of a barred group still rules it out")
assert(Client:MatchesCondition(Steps:ParseCondition("Horde | Warrior or Mage")))
assert(not Client:MatchesCondition(Steps:ParseCondition("Horde | not Orc")))
GetItemCount = function(id) return id == 2495 and 1 or 0 end
assert(not Client:MatchesCondition({ type = "all", children = { { type = "item", id = 2495 }, { type = "item", id = 4470 } } }),
    "both items are wanted")

-- `now`: read as it stands, never waited on.
local nowItem = { type = "now", child = { type = "item", id = 4470 } }
assert(Steps:DescribeCondition(nowItem) == "now item 4470")
assert(Client:CouldOpen({ type = "item", id = 4470 }), "an item may still come")
assert(not Client:CouldOpen(nowItem), "a `now` item not carried closes the step")
assert(Client:CouldOpen({ type = "now", child = { type = "item", id = 2495 } }))
assert(Client:MatchesCondition({ type = "now", child = { type = "item", id = 2495 } }), "read plainly, `now` is its term")
assert(Client:CouldOpen({ type = "any", children = { nowItem, ready900 } }), "another term that may come keeps it open")
assert(Client:CouldOpen({ type = "not", child = nowItem }))
assert(not Client:CouldOpen({ type = "not", child = { type = "now", child = { type = "item", id = 2495 } } }))
assert(not Client:RulesOut(nowItem), "`now` never rules a step out: it can change")
C_QuestLog = nil

clearStubs()

assert(#roundTrip == 0, "the editor must write back every condition the fixture wrote:\n  " .. table.concat(roundTrip, "\n  "))

return true
