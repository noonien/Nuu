_G = _G or _ENV
local ns = { modules = {}, db = { settings = { automation = { lootReminder = true } } }, printed = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Print(message) table.insert(self.printed, message) end
function ns:Log() end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Data/GuideCheck.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Domain/LootReminder.lua")
local Steps, Progress, LootReminder = ns.modules.Steps, ns.modules.Progress, ns.modules.LootReminder

-- Two Fanglords the way the Wailing Caverns guide has them, a step counting
-- turtle shells, and a boss whose drop begins a quest.
local guide = Steps:Expand({
    kind = "guide", id = "test:loot", updated = 1789862400, title = "Loot", category = "test",
    data = { map = 1413, sections = {
    { title = "Steps", steps = {
        { type = "collect", item = 9739, kill = { 3671 }, quest = { 914, 2 } },
        { type = "collect", item = 9738, kill = { 3669 }, quest = { 914, 1 } },
        { type = "collect", item = 5098, count = 8, kill = { 3461 }, quest = { 880, 1 } },
        { type = "collect", item = 10441, starts = 6981, kill = { 3654 } },
        { type = "finish", note = "End" },
    } },
} },
})
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == guide.id and guide or nil end }
Progress:Select(guide)

local bags, done, fighting, looting, time, alerts = {}, {}, false, false, 100, {}
GetTime = function() return time end
local Client = {}
ns.modules.Client = Client
function Client:GetItemCount(itemID) return bags[itemID] or 0 end
function Client:UnitInCombat() return fighting end
function Client:IsLootWindowShown() return looting end
function Client:ShowAlert(message) table.insert(alerts, message); return true end
ns.modules.GuideScan = {
    NodeCompleted = function(_, node) return done[node.index] == true end,
    NodeIsMoot = function() return false end,
}
local function reset() LootReminder.pending, LootReminder.handled, alerts, ns.printed = {}, {}, {}, {} end
local function creature(id, serial) return "Creature-0-1-43-8-" .. id .. "-" .. string.format("%010d", serial) end

-- A boss killed out of the guide's order is still watched: Lord Cobrahn
-- is the second Fanglord, and the guide is on the first.
fighting = true
assert(LootReminder:OnKill(creature(3669, 1), 3669), "a kill the guide wants loot from is watched")
assert(not LootReminder:OnKill(creature(3669, 1), 3669), "one death is handled once")
assert(LootReminder:Check() == 0 and #alerts == 0, "nothing is said mid-fight")
fighting = false
LootReminder:OnCombatEnded()
time = time + 1
assert(LootReminder:Check() == 0, "nor the moment the fight ends")
time = time + 3
looting = true
assert(LootReminder:Check() == 0, "an open loot window holds it off")
looting = false
assert(LootReminder:Check() == 1 and #alerts == 1 and #ns.printed == 1, "then the reminder goes up, on screen and in chat")
assert(alerts[1]:find("^Loot ") and alerts[1]:find("from "), "it names the item and the creature: " .. alerts[1])
assert(LootReminder:Check() == 0 and #alerts == 1, "once")

-- Looted in time, nothing is said.
reset()
LootReminder:OnKill(creature(3671, 2), 3671)
bags[9739] = 1
time = time + 10
assert(LootReminder:Check() == 0 and #alerts == 0 and next(LootReminder.pending) == nil, "a looted drop is dropped")

-- Already carried, or the step done, the kill is not watched at all.
reset()
assert(not LootReminder:OnKill(creature(3671, 3), 3671), "an item already carried")
done[2] = true
assert(not LootReminder:OnKill(creature(3669, 4), 3669), "a step already done")

-- A count of shells has no single kill that must be looted; a creature the
-- guide wants nothing from is not watched either.
assert(not LootReminder:OnKill(creature(3461, 5), 3461), "a counted drop")
assert(not LootReminder:OnKill(creature(3244, 6), 3244), "a creature the guide names for nothing")

-- An item that begins a quest is watched like a quest objective.
reset()
assert(LootReminder:OnKill(creature(3654, 7), 3654), "a quest-starting drop")
time = time + 10
assert(LootReminder:Check() == 1, "and reminded")

-- Left too long, the reminder is dropped unsaid.
reset()
fighting = true
LootReminder:OnKill(creature(3654, 8), 3654)
time = time + 200
assert(LootReminder:Check() == 0 and next(LootReminder.pending) == nil, "an old kill is forgotten")
fighting = false

-- Turned off, nothing is watched.
reset()
ns.db.settings.automation.lootReminder = false
assert(not LootReminder:OnKill(creature(3654, 9), 3654), "off")
