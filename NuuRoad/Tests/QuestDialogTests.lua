_G = _G or _ENV
local ns = { modules = {}, db = { settings = { automation = { acceptQuests = true, turnInQuests = true } } }, printed = {}, logs = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Print(message) table.insert(self.printed, message) end
function ns:Log(message) table.insert(self.logs, message) end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Data/GuideCheck.lua")
Load(ns, "Data/Names.lua")
AddBuiltInNames(ns)
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Domain/QuestDialog.lua")
local Steps, Progress, QuestDialog = ns.modules.Steps, ns.modules.Progress, ns.modules.QuestDialog

local guide = Steps:Expand({
    kind = "guide", id = "test:dialog", updated = 1789862400, title = "Dialog", category = "test",
    -- Objective steps between the quest steps keep each one its own group.
    data = { map = 1413, sections = {
        { title = "Steps", steps = {
            { type = "accept", quests = { 869 }, npc = { 3464 } },
            { type = "kill", quest = 869 },
            { type = "talk", turnin = { 869 }, accept = { 871 }, npc = { 3464 } },
            { type = "kill", quest = 871 },
            { type = "accept", quests = { 870 }, npc = { 3448 } },
            { type = "kill", quest = 870 },
            { type = "talk", turnin = { 870 }, accept = { 877 }, npc = { 3448 } },
            { type = "kill", quest = 877 },
            { type = "accept", quests = { 1502 }, npc = { 5810 }, cond = { class = "WARRIOR" } },
            { type = "turnin", quests = { 877 }, npc = { 3448 } },
        } },
    } },
})
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == guide.id and guide or nil end }

-- A fake client: quest log state, open dialogs, and a record of every action.
local time, shift, log, finished, class = 100, false, {}, {}, "SHAMAN"
GetTime = function() return time end
local actions = {}
local open = {}
local Client = {}
ns.modules.Client = Client
function Client:IsShiftDown() return shift end
function Client:IsQuestInLog(id) return log[id] == true end
function Client:IsQuestComplete(id) return finished[id] == true end
function Client:MatchesCondition(predicate) return predicate.type ~= "class" or predicate.values[1] == class end
function Client:GetGossipQuests() return open.gossip or { available = {}, active = {} } end
function Client:SelectGossipAvailableQuest(entry) table.insert(actions, "gossip-available:" .. tostring(entry.questID or entry.index)); return true end
function Client:SelectGossipActiveQuest(entry) table.insert(actions, "gossip-active:" .. tostring(entry.questID or entry.index)); return true end
function Client:GetGreetingQuests() return open.greeting or { available = {}, active = {} } end
function Client:SelectGreetingAvailableQuest(entry) table.insert(actions, "greeting-available:" .. entry.index); return true end
function Client:SelectGreetingActiveQuest(entry) table.insert(actions, "greeting-active:" .. entry.index); return true end
function Client:GetOpenQuestID() return open.questID end
function Client:GetQuestDialogTitle() return open.title end
function Client:AcceptOpenQuest() table.insert(actions, "accept"); return true end
function Client:IsOpenQuestCompletable() return open.completable == true end
function Client:CompleteOpenQuest() table.insert(actions, "complete"); return true end
function Client:GetOpenQuestChoiceCount() return open.choices or 0 end
function Client:TakeOpenQuestReward(choice) table.insert(actions, "reward:" .. choice); return true end
function Client:GetQuestTitle(id) return nil end
local function last() return actions[#actions] end
local function clear() actions = {} end

-- Expected quests: only the current step's accepts and turn-ins.
Progress:Select(guide)
Progress:Complete(guide); Progress:Complete(guide) -- past "accept 869" and its objective; now at "turnin 869 / accept 871"
local accepts, turnins = QuestDialog:Expected()
assert(accepts[869] == nil and turnins[869], "the current step turns 869 in but does not accept it")
assert(accepts[871] and next(accepts, next(accepts)) == nil, "only the current step's offer is expected")
assert(accepts[870] == nil and accepts[877] == nil and turnins[870] == nil and turnins[877] == nil, "later steps are not")
assert(next(turnins, next(turnins)) == nil)

-- Gossip: a finished turn-in is picked before a new quest; IDs win over titles.
open.gossip = { available = { { index = 1, questID = 871, title = "Disrupt the Attacks" } }, active = { { index = 1, questID = 869, title = "Raptor Thieves", isComplete = true } } }
local action, questID = QuestDialog:OnGossip()
assert(action == "turnin" and questID == 869 and last() == "gossip-active:869", tostring(last()))
clear()
action, questID = QuestDialog:OnGossip()
assert(action == "accept" and questID == 871 and last() == "gossip-available:871", "the same turn-in pick is not repeated at once; the offer is next")
clear()
assert(QuestDialog:OnGossip() == nil and #actions == 0, "nor is the offer pick")
time = 110
open.gossip.active[1].isComplete = false
action, questID = QuestDialog:OnGossip()
assert(action == "accept" and questID == 871 and last() == "gossip-available:871", "an unfinished quest is skipped and the offer taken")
clear(); time = 120
log[871] = true
assert(QuestDialog:OnGossip() == nil and #actions == 0, "a quest already in the log is not accepted again")
log[871] = nil
Progress:Complete(guide); Progress:Complete(guide) -- now at "accept 870"
open.gossip = { available = { { index = 1, title = "Supplies for the Crossroads" }, { index = 2, title = "the forgotten pools" } }, active = {} }
action, questID = QuestDialog:OnGossip()
assert(action == "accept" and questID == 870 and last() == "gossip-available:2", "without IDs the title decides, ignoring case")
clear(); time = 130
open.gossip = { available = { { index = 1, questID = 4921, title = "Lost in Battle" } }, active = {} }
assert(QuestDialog:OnGossip() == nil and #actions == 0, "a quest the guide does not mention is left to the player")
shift = true
open.gossip = { available = { { index = 1, questID = 870, title = "The Forgotten Pools" } }, active = {} }
assert(QuestDialog:OnGossip() == nil and #actions == 0, "Shift pauses everything")
shift = false
open.questID = 870
QuestDialog:OnClosed() -- the gossip window closes as the offer opens, in the same frame
assert(QuestDialog:OnDetail() == nil and #actions == 0, "the offer opened by hand after Shift is left to the player")
QuestDialog:OnClosed(); time = time + 0.1
assert(QuestDialog:OnDetail() == nil and #actions == 0, "so is one reopened at once")
QuestDialog:OnClosed(); time = time + 1
assert(QuestDialog:OnDetail() == "accept" and last() == "accept", "a dialog opened later without Shift is handled again")
clear(); open.questID = nil
ns.db.settings.automation.acceptQuests = false
assert(QuestDialog:OnGossip() == nil and #actions == 0, "the accept setting turns offers off")
ns.db.settings.automation.acceptQuests = true

-- Greeting windows work the same way, by index.
time = 140
open.greeting = { available = { { index = 1, title = "The Forgotten Pools" } }, active = { { index = 1, title = "Raptor Thieves", isComplete = true } } }
action = QuestDialog:OnGreeting()
assert(action == "accept" and last() == "greeting-available:1", "a finished quest of an earlier step is not handed in")
clear(); time = 150
Progress:Back(guide); Progress:Back(guide) -- back at "turnin 869 / accept 871"
action = QuestDialog:OnGreeting()
assert(action == "turnin" and last() == "greeting-active:1")
clear(); time = 160
Progress:Forward(guide); Progress:Forward(guide) -- forward to "accept 870"

-- Quest detail, progress, and reward dialogs.
open = { questID = 870 }
action, questID = QuestDialog:OnDetail()
assert(action == "accept" and questID == 870 and last() == "accept" and ns.printed[#ns.printed] == "Accepted The Forgotten Pools.")
clear(); time = 170
open = { questID = 4921 }
assert(QuestDialog:OnDetail() == nil and #actions == 0, "an unrelated offer is not accepted")
open = { title = "The Zhevra" }
assert(QuestDialog:OnDetail() == nil, "a title the guide does not know is ignored")
open = { title = "The Forgotten Pools" }
assert(QuestDialog:OnDetail() == nil and #actions == 0, "without an ID even a title the guide knows is left to the player")
open = { questID = 870 }
assert(QuestDialog:OnDetail() == "accept" and last() == "accept", "the same quest named by ID is accepted")
clear(); time = 180
Progress:Forward(guide); Progress:Forward(guide) -- "turnin 870 / accept 877"
open = { questID = 869, completable = true }
assert(QuestDialog:OnProgress() == nil and #actions == 0, "a finished quest from another step is left alone")
open = { title = "The Forgotten Pools", completable = true }
assert(QuestDialog:OnProgress() == nil and #actions == 0, "without an ID a finished quest is not handed in by title")
open = { questID = 870, completable = false }
assert(QuestDialog:OnProgress() == nil and #actions == 0, "an unfinished quest is not handed in")
open.completable = true
assert(QuestDialog:OnProgress() == "complete" and last() == "complete")
clear(); time = 190
open = { questID = 870, choices = 0 }
action = QuestDialog:OnComplete()
assert(action == "turnin" and last() == "reward:0" and ns.printed[#ns.printed] == "Turned in The Forgotten Pools.")
clear(); time = 200
open = { questID = 870, choices = 1 }
assert(QuestDialog:OnComplete() == "turnin" and last() == "reward:1", "a single reward is taken")
clear(); time = 210
Progress:Forward(guide); Progress:Forward(guide) -- "turnin 877" (the Warrior-only step is skipped for a Shaman)
open = { questID = 877, choices = 3 }
assert(QuestDialog:OnComplete() == "choose" and #actions == 0, "a choice of rewards is left to the player")
assert(ns.printed[#ns.printed]:find("choice of rewards"), ns.printed[#ns.printed])

local notices = #ns.printed
assert(QuestDialog:OnComplete() == "choose" and #ns.printed == notices, "the reward notice is given once")
open = { questID = 4921, choices = 0 }
assert(QuestDialog:OnComplete() == nil and #actions == 0, "an unrelated turn-in is left alone")
ns.db.settings.automation.turnInQuests = false
open = { questID = 877, choices = 0, completable = true }
assert(QuestDialog:OnComplete() == nil and QuestDialog:OnProgress() == nil, "the turn-in setting turns hand-ins off")

-- A run of quest steps is one group: every member's quests are expected at
-- once, so a hub can be worked in any order, while a member already recorded
-- done drops out.
local hub = Steps:Expand({
    kind = "guide", id = "test:hub", updated = 1789862400, title = "Hub", category = "test",
    data = { map = 1413, sections = {
        { title = "Steps", steps = {
            { group = {
                { type = "accept", quests = { 870 }, npc = { 3448 } },
                { type = "accept", quests = { 869 }, npc = { 3464 } },
                { type = "talk", turnin = { 842 }, accept = { 844 }, npc = { 3338 } },
                { type = "accept", quests = { 1502 }, npc = { 5810 }, cond = { class = "WARRIOR" } },
                { type = "accept", quests = { 871 }, npc = { 3429 } },
            } },
            { type = "kill", quest = 870 },
            { type = "turnin", quests = { 870 }, npc = { 3448 } },
        } },
    } },
})
ns.modules.GuideRepository = { Get = function(_, id) return id == hub.id and hub or nil end }
ns.db.settings.automation.turnInQuests = true
Progress.store, Progress.session = {}, {}
Progress:Select(hub)
log, finished = {}, {}
accepts, turnins = QuestDialog:Expected()
assert(accepts[870] and accepts[869] and accepts[844] and accepts[871], "every accept of the group is expected")
assert(accepts[1502] == nil, "a member gated out for this character is not")
assert(turnins[842] and turnins[870] == nil, "the turn-in past the objective step is outside the group")
assert(accepts[869].index == 2, "each quest maps to its own step")
time = 300; clear()
open.gossip = { available = { { index = 1, questID = 871, title = "Disrupt the Attacks" } }, active = {} }
action, questID = QuestDialog:OnGossip()
assert(action == "accept" and questID == 871 and last() == "gossip-available:871", "a later member's offer is taken at once")
clear(); time = 310
open = { questID = 869 }
assert(QuestDialog:OnDetail() == "accept" and last() == "accept", "and accepted when the offer opens")
clear(); time = 320
open.gossip = { available = {}, active = { { index = 1, questID = 842, title = "Plainstrider Menace", isComplete = false } } }
assert(QuestDialog:OnGossip() == nil and #actions == 0, "an unfinished turn-in of the group is left alone")
Progress:Record(hub, 5, "observed")
accepts = QuestDialog:Expected()
assert(accepts[871] == nil and accepts[870], "a member recorded done ahead of its turn is no longer expected")

-- Without an active guide nothing is expected.
Progress.store.activeGuideID = nil
accepts, turnins = QuestDialog:Expected()
assert(next(accepts) == nil and next(turnins) == nil)

return true
