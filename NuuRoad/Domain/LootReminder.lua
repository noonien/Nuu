local _, ns = ...

-- Reminds the player to loot a creature the active guide wants one item from:
-- a boss's gem, a named mob's head. Any step of the guide counts, not only
-- the current one, since a dungeon group kills its bosses in whatever order
-- it likes. Only a step that wants one item from named creatures
-- (`collect` and `kill`, no count above one) is watched; a step counting
-- eight shells off turtles has no single kill that must be looted.
--
-- A few seconds after the fight ends, if the item has not arrived and the
-- step is still to do, a line goes up in the middle of the screen and in
-- chat. An open loot window holds it off. It never loots anything itself.
local LootReminder = { pending = {}, handled = {}, combatLeftAt = -math.huge, wait = 0 }

local DELAY = 3 -- seconds out of combat before the reminder goes up
local EXPIRE = 120 -- seconds after the kill a reminder is dropped unsaid
local HANDLED_MEMORY = 30 -- seconds a kill's GUID is remembered, so one death is handled once
local CHECK_INTERVAL = 0.5

local function now() return GetTime and GetTime() or 0 end

function LootReminder:Enabled()
    return ns.modules.Config:Get("automation.lootReminder") == true
end

local function names(list, id)
    for _, candidate in ipairs(list or {}) do
        if candidate == id then return true end
    end
    return false
end

-- The first step of `guide` still to do that wants one item from `npcID`,
-- and that item, or nil.
function LootReminder:DropFor(guide, npcID)
    local Progress, GuideScan, Client = ns.modules.Progress, ns.modules.GuideScan, ns.modules.Client
    for _, node in ipairs(guide and guide.nodes or {}) do
        local auto = node.auto
        local itemID = auto and auto.collect and auto.collect[1]
        if itemID and auto.kill and (auto.count or 1) == 1 and names(auto.kill, npcID)
            and not Progress:IsRuledOut(node) and not Progress:IsBypassed(node)
            and not (GuideScan and (GuideScan:NodeCompleted(node) or GuideScan:NodeIsMoot(node)))
            and Client:GetItemCount(itemID) < 1 then
            return node, itemID
        end
    end
    return nil
end

-- A creature the player or their group killed.
function LootReminder:OnKill(guid, npcID)
    if not self:Enabled() or type(guid) ~= "string" or type(npcID) ~= "number" then return false end
    local time = now()
    for known, seen in pairs(self.handled) do
        if time - seen > HANDLED_MEMORY then self.handled[known] = nil end
    end
    if self.handled[guid] then return false end
    self.handled[guid] = time
    local Progress = ns.modules.Progress
    local guide = Progress and Progress:GetActiveGuide()
    local node, itemID = self:DropFor(guide, npcID)
    if not node then return false end
    self.pending[guid] = { npc = npcID, item = itemID, node = node, guide = guide.id, at = time }
    return true
end

function LootReminder:OnCombatEnded()
    self.combatLeftAt = now()
end

function LootReminder:Message(entry)
    local Names = ns.modules.Names
    return "Loot " .. Names:DescribeItem(entry.item) .. " from " .. Names:DescribeNPC(entry.npc) .. "."
end

-- Says what is due and drops what no longer needs saying. Returns how many
-- reminders went up.
function LootReminder:Check()
    if not next(self.pending) then return 0 end
    local Client, GuideScan, Progress = ns.modules.Client, ns.modules.GuideScan, ns.modules.Progress
    local time, shown = now(), 0
    local guide = Progress:GetActiveGuide()
    local fighting = Client:UnitInCombat("player")
    for guid, entry in pairs(self.pending) do
        if not self:Enabled() or not guide or guide.id ~= entry.guide or time - entry.at > EXPIRE
            or Client:GetItemCount(entry.item) > 0
            or (GuideScan and GuideScan:NodeCompleted(entry.node)) then
            self.pending[guid] = nil
        elseif not fighting and time - math.max(entry.at, self.combatLeftAt) >= DELAY and not Client:IsLootWindowShown() then
            self.pending[guid] = nil
            local message = self:Message(entry)
            Client:ShowAlert(message)
            ns:Print(message)
            shown = shown + 1
        end
    end
    return shown
end

function LootReminder:Initialize()
    local frame = CreateFrame("Frame")
    pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function() self:OnCombatEnded() end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        self.wait = self.wait - (elapsed or 0)
        if self.wait > 0 then return end
        self.wait = CHECK_INTERVAL
        self:Check()
    end)
    self.frame = frame
end

ns:RegisterModule("LootReminder", LootReminder)
