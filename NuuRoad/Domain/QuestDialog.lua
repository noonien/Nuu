local _, ns = ...

-- Handles quest dialogs the player opens, for the quests of the current quest
-- group only (the current member and the remaining authored members,
-- see Progress:QuestGroup): at a gossip or greeting window it picks one
-- of those quest lines, at a quest offer it accepts, and at a finished quest
-- it hands in. A turn-in that is not finished yet is not picked, and a
-- follow-up the NPC does not offer yet cannot be, so chains keep their order
-- through the game's own rules rather than the guide's. Every other
-- quest an NPC offers is left to the player: a quest is accepted or handed in
-- only when the client names it by ID and that ID is one of the guide's. A
-- title is never enough, since quests share titles; it is used only to pick a
-- line in a gossip or greeting list that carries no IDs, which just opens the
-- quest, and the window that opens is checked by ID before anything is done. A quest with a choice of
-- rewards is left open for the player to pick. Holding Shift while talking
-- to an NPC pauses all of it, for the whole conversation: once Shift is seen
-- down at any of its windows, nothing is picked, accepted, or handed in until
-- the dialog closes, so letting go of Shift to click a quest line yourself
-- does not hand the offer that opens to the addon.
--
-- It never opens a dialog, abandons a quest, or chooses between rewards.
local QuestDialog = { rewardNotices = {}, recent = {} }

local ACTION_MEMORY = 1.5 -- seconds before the same action on the same quest may repeat
local MANUAL_GRACE = 0.5 -- seconds after a manual dialog closes before automation resumes

local function now() return GetTime and GetTime() or 0 end

local function normalize(title)
    if type(title) ~= "string" then return nil end
    title = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if #title == 0 then return nil end
    return title
end

-- Whether the player has taken the open dialog over with Shift. The mark
-- lasts until the dialog has been closed for a moment: the gossip window
-- closes and the quest offer opens in the same frame, so a close alone must
-- not hand the rest of the conversation back.
function QuestDialog:IsManual()
    local time = now()
    if self.manual and self.manualClosedAt and time - self.manualClosedAt > MANUAL_GRACE then
        self.manual = false
    end
    self.manualClosedAt = nil
    if ns.modules.Client:IsShiftDown() then self.manual = true end
    return self.manual == true
end

function QuestDialog:OnClosed()
    if self.manual then self.manualClosedAt = now() end
end

function QuestDialog:Enabled(key)
    if ns.modules.Config:Get("automation." .. key) ~= true then return false end
    return not self:IsManual()
end

-- { [questID] = node } for the quests the current quest group accepts and
-- turns in. A later member already recorded done contributes nothing; the
-- current step always does, since the player may have walked back to it.
function QuestDialog:Expected()
    local Progress = ns.modules.Progress
    local accepts, turnins = {}, {}
    local guide = Progress and Progress.store and Progress:GetActiveGuide()
    if not guide then return accepts, turnins end
    local state = Progress:PeekState(guide)
    for index, node in ipairs(Progress:QuestGroup(guide)) do
        local auto = node.auto
        if auto and (index == 1 or not (state and Progress:IsDone(state.statuses[node.index]))) then
            for _, id in ipairs((auto.verb == "accept" and auto.quests) or auto.accept or {}) do accepts[id] = accepts[id] or node end
            for _, id in ipairs((auto.verb == "turnin" and auto.quests) or auto.turnin or {}) do turnins[id] = turnins[id] or node end
        end
    end
    return accepts, turnins
end

-- The expected quest an entry ({ questID, title }) stands for, by ID when the
-- client gives one, otherwise by title.
function QuestDialog:Match(entry, expected)
    if type(entry.questID) == "number" then
        return expected[entry.questID] and entry.questID or nil
    end
    local title = normalize(entry.title)
    if not title then return nil end
    local Names = ns.modules.Names
    for id in pairs(expected) do
        if normalize(Names:Quest(id)) == title then return id end
    end
    return nil
end

function QuestDialog:Once(action, questID)
    local key = action .. ":" .. tostring(questID)
    local time = now()
    for known, seen in pairs(self.recent) do
        if time - seen > ACTION_MEMORY then self.recent[known] = nil end
    end
    if self.recent[key] then return false end
    self.recent[key] = time
    return true
end

-- Gossip and greeting windows list the NPC's quests; a finished turn-in is
-- picked before a new quest so the log never fills up first.
function QuestDialog:HandleQuestList(quests, selectActive, selectAvailable)
    local Client = ns.modules.Client
    local accepts, turnins = self:Expected()
    if self:Enabled("turnInQuests") then
        for _, entry in ipairs(quests.active or {}) do
            local id = entry.isComplete and self:Match(entry, turnins)
            if id and self:Once("select-active", id) then
                ns:Log("selecting turn-in of " .. ns.modules.Names:DescribeQuest(id))
                return selectActive(Client, entry) and "turnin" or nil, id
            end
        end
    end
    if self:Enabled("acceptQuests") then
        for _, entry in ipairs(quests.available or {}) do
            local id = self:Match(entry, accepts)
            if id and not Client:IsQuestInLog(id) and not Client:IsQuestComplete(id) and self:Once("select-available", id) then
                ns:Log("selecting offer of " .. ns.modules.Names:DescribeQuest(id))
                return selectAvailable(Client, entry) and "accept" or nil, id
            end
        end
    end
    return nil
end

function QuestDialog:OnGossip()
    local Client = ns.modules.Client
    return self:HandleQuestList(Client:GetGossipQuests(), Client.SelectGossipActiveQuest, Client.SelectGossipAvailableQuest)
end

function QuestDialog:OnGreeting()
    local Client = ns.modules.Client
    return self:HandleQuestList(Client:GetGreetingQuests(), Client.SelectGreetingActiveQuest, Client.SelectGreetingAvailableQuest)
end

-- The quest in an open detail, progress, or reward dialog, when it is one of
-- `expected`. By ID only: without an ID the dialog is left to the player,
-- because a quest outside the guide can carry the same title as one in it.
function QuestDialog:OpenQuest(expected)
    local questID = ns.modules.Client:GetOpenQuestID()
    if questID and expected[questID] then return questID end
    if not questID then ns:Log("quest dialog has no ID; left to the player") end
    return nil
end

function QuestDialog:OnDetail()
    if not self:Enabled("acceptQuests") then return nil end
    local accepts = self:Expected()
    local questID = self:OpenQuest(accepts)
    if not questID or not self:Once("accept", questID) then return nil end
    if not ns.modules.Client:AcceptOpenQuest() then return nil end
    ns:Print("Accepted " .. ns.modules.Names:DescribeQuest(questID) .. ".")
    return "accept", questID
end

function QuestDialog:OnProgress()
    if not self:Enabled("turnInQuests") then return nil end
    local _, turnins = self:Expected()
    local questID = self:OpenQuest(turnins)
    if not questID or not ns.modules.Client:IsOpenQuestCompletable() or not self:Once("complete", questID) then return nil end
    if not ns.modules.Client:CompleteOpenQuest() then return nil end
    return "complete", questID
end

function QuestDialog:OnComplete()
    if not self:Enabled("turnInQuests") then return nil end
    local Client, Names = ns.modules.Client, ns.modules.Names
    local _, turnins = self:Expected()
    local questID = self:OpenQuest(turnins)
    if not questID then return nil end
    local choices = Client:GetOpenQuestChoiceCount()
    if choices > 1 then
        if not self.rewardNotices[questID] then
            self.rewardNotices[questID] = true
            ns:Print(Names:DescribeQuest(questID) .. " offers a choice of rewards. Pick one to finish it.")
        end
        return "choose", questID
    end
    if not self:Once("reward", questID) then return nil end
    if not Client:TakeOpenQuestReward(choices) then return nil end
    ns:Print("Turned in " .. Names:DescribeQuest(questID) .. ".")
    return "turnin", questID
end

function QuestDialog:Initialize()
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_CLOSED", "QUEST_FINISHED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "GOSSIP_SHOW" then
            self:OnGossip()
        elseif event == "QUEST_GREETING" then
            self:OnGreeting()
        elseif event == "QUEST_DETAIL" then
            self:OnDetail()
        elseif event == "QUEST_PROGRESS" then
            self:OnProgress()
        elseif event == "QUEST_COMPLETE" then
            self:OnComplete()
        elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
            self:OnClosed()
        end
    end)
    self.frame = frame
end

ns:RegisterModule("QuestDialog", QuestDialog)
