_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
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

-- The registry is what a condition is checked against.
assert(Client:HasPredicate("class") and Client:HasPredicate("season") and Client:HasPredicate("lua"))
assert(not Client:HasPredicate("nonsense"))
assert(Client:HasPredicate("all") and Client:HasPredicate("any") and Client:HasPredicate("not"),
    "the combinators are always available")
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

-- Registered kinds read the client, and say unknown when it cannot answer.
assert(Client:EvaluateCondition({ type = "season", id = 2 }) == nil, "no season API is unknown")
C_Seasons = { GetActiveSeason = function() return 2 end }
assert(Client:EvaluateCondition({ type = "season", id = 2 }) == true)
assert(Client:EvaluateCondition({ type = "season", id = 1 }) == false)
assert(Client:EvaluateCondition({ type = "season" }) == true, "a bare season asks whether any is active")
assert(Client:EvaluateCondition({ type = "gold", atLeast = 5000 }) == nil)
GetMoney = function() return 7000 end
assert(Client:EvaluateCondition({ type = "gold", atLeast = 5000 }) == true)
assert(Client:EvaluateCondition({ type = "gold", atLeast = 9000 }) == false)
GetItemCount = function(id) return id == 2495 and 2 or 0 end
assert(Client:EvaluateCondition({ type = "item", id = 2495 }) == true)
assert(Client:EvaluateCondition({ type = "item", id = 2495, count = 3 }) == false)
UnitLevel = function() return 12 end
assert(Client:EvaluateCondition({ type = "level", atLeast = 10 }) == true)
assert(Client:EvaluateCondition({ type = "level", atLeast = 10, atMost = 11 }) == false)

-- Every kind Schema names must exist in the registry: that drift is what the
-- registry is for.
local expanded = Steps:Expand({
    schema = 2, id = "nuuroad:test:kinds", updated = 1, map = 1412, meta = { title = "Predicate fixture", category = "test" },
    steps = { { section = "S", steps = {
        { note = "warrior", only = "Warrior" },
        { note = "season", only = "season 2" },
        { note = "skill", only = "skill Mining 75" },
        { note = "item", only = "item 2495 x3" },
        { note = "equipped", only = "equipped 2495" },
        { note = "spell", only = "spell 8017" },
        { note = "zone", only = "zone 1412" },
        { note = "level", only = "level 10" },
        { note = "gold", only = "gold 5000" },
        { note = "profession", only = "profession Skinning" },
        { note = "reputation", only = "reputation 576 Honored" },
        { note = "quest state", only = "quest 858 finished" },
        { note = "hardcore", only = "hardcore" },
        { note = "neither", only = "not Warrior | not Druid" },
    } } },
})
local ok, problems = Schema:Validate(expanded)
assert(ok, table.concat(problems or {}, "; "))
assert(expanded.nodes[2].condition.type == "season" and expanded.nodes[2].condition.id == 2)
assert(expanded.nodes[3].condition.name == "Mining" and expanded.nodes[3].condition.atLeast == 75,
    "a skill name keeps its capitalization")
assert(expanded.nodes[4].condition.count == 3)
assert(expanded.nodes[11].condition.standing == 6, "Honored is standing six")
assert(expanded.nodes[12].condition.state == "finished")
assert(expanded.nodes[14].condition.type == "all" and #expanded.nodes[14].condition.children == 2)
for _, node in ipairs(expanded.nodes) do
    if node.condition and node.condition.type ~= "all" then
        assert(Client:HasPredicate(node.condition.type), "unregistered kind: " .. node.condition.type)
    end
end

-- `only` renders back to text so the editor can show and re-parse it.
assert(Steps:DescribeCondition(expanded.nodes[3].condition) == "skill Mining 75")
assert(Steps:DescribeCondition(expanded.nodes[4].condition) == "item 2495 x3")
assert(Steps:DescribeCondition(expanded.nodes[11].condition) == "reputation 576 Honored")
assert(Steps:DescribeCondition(expanded.nodes[14].condition) == "not Warrior | not Druid")

local badTerm = pcall(Steps.Expand, Steps, {
    schema = 2, id = "nuuroad:test:bad", updated = 1, map = 1412, meta = { title = "Predicate fixture", category = "test" },
    steps = { { section = "S", steps = { { note = "x", only = "banana" } } } },
})
assert(not badTerm, "an unknown condition term is refused at load")

-- The Lua fallback ---------------------------------------------------------
local withWhen = Steps:Expand({
    schema = 2, id = "nuuroad:test:lua", updated = 1, map = 1412, meta = { title = "Predicate fixture", category = "test" },
    steps = { { section = "S", steps = {
        { note = "expression", when = "level() >= 10" },
        { note = "both", only = "Warrior", when = "money() > 100" },
    } } },
})
ok, problems = Schema:Validate(withWhen)
assert(ok, table.concat(problems or {}, "; "))
assert(withWhen.nodes[1].condition.type == "lua" and withWhen.nodes[1].condition.body == "level() >= 10")
assert(withWhen.nodes[2].condition.type == "all", "only and when are AND-ed")
assert(Steps:LuaCondition(withWhen.nodes[2].condition) == "money() > 100")
assert(Steps:DescribeCondition(withWhen.nodes[2].condition) == "Warrior",
    "the keyword half renders; the expression is shown on its own")

assert(Client:EvaluateCondition({ type = "lua", body = "level() >= 10" }) == true)
assert(Client:EvaluateCondition({ type = "lua", body = "level() >= 20" }) == false)
assert(Client:EvaluateCondition({ type = "lua", body = "itemCount(2495) >= 2 and money() > 100" }) == true)
assert(Client:EvaluateCondition({ type = "lua", body = "season() == 2" }) == true)
assert(Client:EvaluateCondition({ type = "lua", body = "api('UnitLevel', 'player') == 12" }) == true,
    "an allowlisted read is reachable through api()")
assert(Client:EvaluateCondition({ type = "lua", body = "api('C_Seasons.GetActiveSeason') == 2" }) == true,
    "so is a namespaced one")

-- It is data, not code: guides still carry no executable values.
ok, problems = Schema:Validate(withWhen)
assert(ok, table.concat(problems or {}, "; "))
assert(type(withWhen.nodes[1].condition.body) == "string")

-- The sandbox.
SendChatMessage = function() error("a guide must never reach this") end
assert(Client:EvaluateCondition({ type = "lua", body = "api('SendChatMessage', 'hi') or true" }) == true,
    "api() refuses a name that is not on the read allowlist and answers nil")
assert(Client:EvaluateCondition({ type = "lua", body = "UnitLevel == nil" }) == true,
    "raw globals are not in the sandbox")
assert(Client:EvaluateCondition({ type = "lua", body = "SendChatMessage == nil" }) == true)
assert(Client:EvaluateCondition({ type = "lua", body = "nosuchhelper() == 1" }) == nil,
    "calling something the sandbox does not define is unknown, not false")

local function refused(body)
    local compiled, problem = Client:InspectLuaPredicate(body)
    return compiled == nil and problem ~= nil
end
assert(refused("while true do end"), "a loop is not an expression")
assert(refused("x = 1"), "an assignment is not an expression")
assert(refused("function() return 1 end()"), "a function definition is refused")
assert(refused("_G.UnitLevel"), "_G is named and refused")
assert(refused("getfenv(1)"))
assert(refused("loadstring('x')"))
assert(refused("pcall(level)"))
assert(refused("CreateFrame('Frame')"))
assert(refused(string.rep("level() and ", 60) .. "true"), "an over-long body is refused")
assert(refused(""), "an empty body is refused")
assert(select(2, Client:InspectLuaPredicate("level() >")) ~= nil, "a syntax error is reported, not raised")

-- A refused body is unknown at runtime and an error at load.
assert(Client:EvaluateCondition({ type = "lua", body = "while true do end" }) == nil)
local luaProblems = select(2, Schema:Validate(Steps:Expand({
    schema = 2, id = "nuuroad:test:badlua", updated = 1, map = 1412, meta = { title = "Predicate fixture", category = "test" },
    steps = { { section = "S", steps = { { note = "x", when = "_G.UnitLevel" } } } },
})))
assert(luaProblems and #luaProblems > 0, "Schema refuses a body the client will not compile")

-- Anti-drift: every kind Schema will accept without the client loaded must be
-- one the client actually implements.
for kind in pairs(Schema.predicateKinds) do
    assert(Client:HasPredicate(kind), "Schema names a predicate nothing implements: " .. kind)
end

-- The shipped condition fixture is the parity case: every keyword it uses must
-- parse, validate, and render back as the text it was written with.
ns.builtInGuides = {}
Load(ns, "Dev/Fixtures/ConditionFixture.lua")
local fixture = Steps:Expand(ns.builtInGuides["nuuroad:fixture:conditions"])
ok, problems = Schema:Validate(fixture)
assert(ok, "condition fixture: " .. table.concat(problems or {}, "; "))
local gated, expressions = 0, 0
for _, node in ipairs(fixture.nodes) do
    if node.condition then
        gated = gated + 1
        local body = Steps:LuaCondition(node.condition)
        if body then
            expressions = expressions + 1
            assert(Client:InspectLuaPredicate(body), "fixture expression will not compile: " .. body)
        end
        local text = Steps:DescribeCondition(node.condition)
        if text then
            local reparsed = Steps:ParseCondition(text, body)
            assert(Steps:DescribeCondition(reparsed) == text,
                "a condition must render back as the text that made it: " .. text)
        end
    end
end
assert(gated >= 20, "the fixture covers every keyword, got " .. gated)
assert(expressions == 3, "the fixture covers the expression fallback, got " .. expressions)

-- Only who the character is rules a step out; a quest or a level may yet come.
UnitRace = function() return "Orc", "Orc" end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitFactionGroup = function() return "Horde" end
UnitLevel = function() return 5 end
assert(Client:RulesOut(Steps:ParseCondition("Alliance")), "the wrong faction rules a step out")
assert(Client:RulesOut(Steps:ParseCondition("Tauren or Troll")), "the wrong race rules a step out")
assert(Client:RulesOut(Steps:ParseCondition("not Warrior")))
assert(not Client:RulesOut(Steps:ParseCondition("Orc")))
assert(not Client:RulesOut(Steps:ParseCondition("level 10")), "a level not reached yet is not ruled out")
assert(not Client:MatchesCondition(Steps:ParseCondition("level 10")))
assert(not Client:RulesOut(Steps:ParseCondition("Tauren or level 10")), "a term that may still come keeps it")
assert(Client:RulesOut(Steps:ParseCondition("Tauren | not quest 858")), "a fixed term that fails settles all")
assert(not Client:RulesOut(Steps:ParseCondition("Horde", "level() > 10")), "an expression is never fixed")
assert(not Client:RulesOut(nil))

-- What could still open: a quest, a level, or an item the player can gain is
-- waited on; a `not` term already settled and a wrong race are not.
C_QuestLog = { IsOnQuest = function(id) return id == 858 end, IsQuestFlaggedCompleted = function() return false end }
assert(Client:CouldOpen(Steps:ParseCondition("level 10")), "a level not reached yet may come")
assert(Client:CouldOpen(Steps:ParseCondition("quest 900 readyToTurnIn")), "a quest not taken yet may come")
assert(Client:CouldOpen(Steps:ParseCondition("item 2495")))
assert(not Client:CouldOpen(Steps:ParseCondition("not quest 858")), "a quest already taken does not go away")
assert(Client:CouldOpen(Steps:ParseCondition("not quest 900")))
assert(not Client:CouldOpen(Steps:ParseCondition("Tauren or Troll")), "the wrong race never opens")
assert(Client:CouldOpen(Steps:ParseCondition("Tauren or level 10")))
assert(not Client:CouldOpen(Steps:ParseCondition("quest 900 | not quest 858")), "one settled `not` closes it")
assert(Client:CouldOpen(nil))

-- A bar joins groups that must all hold: a Warrior at level 5 is not a
-- Hunter at level 4, whatever the level says.
assert(Client:RulesOut(Steps:ParseCondition("Hunter | level 4 | gold 200")), "the class of a barred group still rules it out")
assert(not Client:MatchesCondition(Steps:ParseCondition("Hunter | level 4")))
assert(Client:MatchesCondition(Steps:ParseCondition("Warrior | level 4")))
assert(not Client:MatchesCondition(Steps:ParseCondition("Warrior | level 10")))
assert(Client:MatchesCondition(Steps:ParseCondition("Horde | Warrior or Mage")))
assert(not Client:MatchesCondition(Steps:ParseCondition("item 2495 | item 4470")), "both items are wanted")

-- `now`: read as it stands, never waited on.
GetItemCount = function(id) return id == 2495 and 1 or 0 end
local nowItem = Steps:ParseCondition("now item 4470")
assert(nowItem.type == "now" and nowItem.child.type == "item" and nowItem.child.id == 4470)
assert(Steps:DescribeCondition(nowItem) == "now item 4470")
assert(Client:CouldOpen(Steps:ParseCondition("item 4470")), "an item may still come")
assert(not Client:CouldOpen(nowItem), "a `now` item not carried closes the step")
assert(Client:CouldOpen(Steps:ParseCondition("now item 2495")))
assert(Client:MatchesCondition(Steps:ParseCondition("now item 2495")), "read plainly, `now` is its term")
assert(not Client:CouldOpen(Steps:ParseCondition("Warrior | now level 10")), "a level not reached is not waited for")
assert(Client:CouldOpen(Steps:ParseCondition("Warrior | now level 4")))
assert(Client:CouldOpen(Steps:ParseCondition("now item 4470 or level 10")), "another term that may come keeps it open")
assert(Client:CouldOpen(Steps:ParseCondition("not now item 4470")))
assert(not Client:CouldOpen(Steps:ParseCondition("not now item 2495")))
assert(not Client:RulesOut(nowItem), "`now` never rules a step out: it can change")
assert(Steps:DescribeCondition(Steps:ParseCondition("Mage | now level 4 | now gold 100")) == "Mage | now level 4 | now gold 100")
assert(Client:HasPredicate("now"))
local nowGuide = Steps:Expand({
    schema = 2, id = "nuuroad:test:now", updated = 1, map = 1412, meta = { title = "Now", category = "test" },
    steps = { { section = "S", steps = { { note = "book", only = "now item 4470" } } } },
})
ok, problems = Schema:Validate(nowGuide)
assert(ok, table.concat(problems or {}, "; "))
C_QuestLog = nil

clearStubs()

return true
