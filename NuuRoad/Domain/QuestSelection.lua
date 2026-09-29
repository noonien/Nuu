local _, ns = ...

-- Keeps the quest log open on the quest the current step is about: points
-- the log at the step in front of the player, so when the guide moves to a
-- step whose quest is in the log, that quest becomes the
-- log's selection, so opening the log lands on the right page and the quest
-- log button beside it answers for the same quest.
--
-- It never accepts, abandons, shares, or watches anything, and it never
-- fights the player: the selection is set once, when the step's quest
-- changes, so clicking another quest in the log stays theirs until the guide
-- moves on. The setting under NPC conveniences turns all of it off.
--
-- Pure logic apart from the Client calls: the choice of quest is made by
-- `QuestForNode`, which asks a caller-supplied predicate what is in the log.
local QuestSelection = {}

-- Roles in preference order. The ones that mean the quest is already in hand
-- come first, so a step that turns one quest in and accepts the next selects
-- the one the player still has to do something about.
local rolePreference = { objective = 1, turnin = 2, collect = 3, track = 4, step = 5, accept = 6 }

-- The quest of a step worth showing in the log: the best-ranked of the quests
-- the step names that `isInLog` says the player is on, ties going to the one
-- the step names first. Nil when the step names no quest the player has.
function QuestSelection:QuestForNode(node, isInLog)
    local QuestIndex = ns.modules.QuestIndex
    if not QuestIndex or type(isInLog) ~= "function" then return nil end
    local best, bestRank
    for _, quest in ipairs(QuestIndex:NodeQuests(node)) do
        local rank = rolePreference[quest.role] or 9
        if (not bestRank or rank < bestRank) and isInLog(quest.id) then best, bestRank = quest.id, rank end
    end
    return best
end

function QuestSelection:Enabled()
    return ns.modules.Config:Get("automation.selectQuestInLog") == true
end

local function key(node)
    local Progress = ns.modules.Progress
    local guide = Progress and Progress.store and Progress:GetActiveGuide()
    return (guide and guide.id or "?") .. "#" .. tostring(node and node.index)
end

-- The row the log is parked on, where the client answers by position.
function QuestSelection:SelectedIndex()
    local Client = ns.modules.Client
    if not Client or type(Client.GetSelectedQuestLogIndex) ~= "function" then return nil end
    return Client:GetSelectedQuestLogIndex()
end

-- True when the log still stands on the row we picked but that row now holds
-- another quest. The classic log remembers a position, not a quest, so a quest
-- accepted or turned in above ours renumbers the rows below it and the log
-- quietly shows the neighbour. A player who clicked lands on a different row,
-- which reads as theirs and is left alone.
function QuestSelection:SelectionDrifted(questID)
    local index = self:SelectedIndex()
    if not index or not self.lastIndex or index ~= self.lastIndex then return false end
    return ns.modules.Client:GetSelectedQuestLogQuest() ~= questID
end

-- Called with the step the tracker is showing, on every repaint. Returns the
-- quest selected, or nil when nothing was done -- which is the usual answer,
-- since the selection only moves when the step's quest does, or when the log
-- renumbered out from under it.
function QuestSelection:Sync(node)
    if not self:Enabled() or not node then
        self.lastStep, self.lastQuest, self.lastIndex = nil, nil, nil
        return nil
    end
    local Client = ns.modules.Client
    local questID = self:QuestForNode(node, function(id) return Client:IsQuestInLog(id) end)
    local stepKey = key(node)
    local standing = stepKey == self.lastStep and questID == self.lastQuest
    self.lastStep, self.lastQuest = stepKey, questID
    if not questID then
        self.lastIndex = nil
        return nil
    end
    -- Nothing to do while the step stands with the quest it had: whatever the
    -- player clicked in the log in the meantime is left alone. A step whose
    -- quest is only accepted later does move the selection, once, when it
    -- reaches the log.
    if standing and not self:SelectionDrifted(questID) then return nil end
    if Client:GetSelectedQuestLogQuest() == questID then
        self.lastIndex = self:SelectedIndex()
        return questID
    end
    if not Client:SelectQuestInLog(questID) then
        self.lastIndex = nil
        ns:Log("quest log selection: client would not select " .. tostring(questID))
        return nil
    end
    self.lastIndex = self:SelectedIndex()
    ns:Log("quest log selection: " .. ns.modules.Names:DescribeQuest(questID))
    return questID
end

ns:RegisterModule("QuestSelection", QuestSelection)
