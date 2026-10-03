local _, ns = ...

-- A small button on the quest log's detail page and on a quest offer: it
-- says whether the quest shown is part of any of the player's guides, its
-- tooltip names each guide and the steps that handle the quest, and a click
-- opens the guide browser searched for that quest. The same lines are
-- appended to every quest tooltip the client shows (quest links, quest log
-- rows), so the answer is there without opening anything. It never changes
-- progress or the active guide. The button is a kit Button.
local QuestFinder = {}

local WIDTH, HEIGHT = 96, 20

local function tipLine(tooltip, text, token, wrap)
    local c = ns:GetUI().tokens[token]
    tooltip:AddLine(text, c[1], c[2], c[3], wrap)
end

function QuestFinder:Tooltip(tooltip)
    local Names, QuestIndex, Progress = ns.modules.Names, ns.modules.QuestIndex, ns.modules.Progress
    local questID = self.questID
    tooltip:SetText(Names:DescribeQuest(questID), 1, 1, 1)
    local entries = QuestIndex:GuidesFor(questID)
    if #entries == 0 then
        tipLine(tooltip, "Not part of any of your guides.", "danger", true)
        return
    end
    local active = Progress and Progress.store and Progress:GetActiveGuide()
    for _, entry in ipairs(entries) do
        local isActive = active ~= nil and active.id == entry.guide.id
        tipLine(tooltip, (entry.guide.meta.title or "Untitled guide") .. (isActive and "  (active)" or ""), "accent")
        tipLine(tooltip, "  " .. QuestIndex:DescribeSteps(entry), "text", true)
    end
    tipLine(tooltip, "Click to see these guides in the guide list.", "muted")
end

local function buttonTip(tooltip) QuestFinder:Tooltip(tooltip) end

local function buttonClicked()
    local questID = QuestFinder.questID
    if not questID then return end
    local MainWindow = ns.modules.MainWindow
    if MainWindow and MainWindow.ShowGuidesForQuest then
        MainWindow:ShowGuidesForQuest(questID)
    else
        ns.modules.GuideBrowser:ShowQuest(questID)
    end
end

function QuestFinder:CreateButton()
    local ui = ns:GetUI()
    local button = ui:Button(UIParent, { "In guide", width = WIDTH, height = HEIGHT,
        tooltip = buttonTip, onClick = buttonClicked })
    -- Its strata is set by hand, above Blizzard's quest frames; it is never
    -- cleared, but marked as a changed frame all the same.
    button:Customize(ui.Custom.frame)
    button:SetFrameStrata("HIGH")
    button:Hide()
    self.button = button
end

-- Places the button on `frame` for `questID` (or a quest title when the
-- client gives no ID); hides it when there is no quest to speak of.
function QuestFinder:Show(frame, questID, title)
    local button = self.button
    if not button then return end
    if type(questID) ~= "number" or questID <= 0 then questID = ns.modules.QuestIndex:QuestIDByTitle(title) end
    if not frame or not questID then button:Hide(); return end
    self.questID = questID
    local count = #ns.modules.QuestIndex:GuidesFor(questID)
    button:SetText(count == 0 and "No guide" or (count == 1 and "In guide" or ("In " .. count .. " guides")))
    button:SetActive(count > 0)
    button:SetParent(frame)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    button:Show()
end

-- Appends the guide lines to a tooltip that shows a quest: one line naming
-- the guides that handle it, or one saying no guide does, in NuuRoad's own
-- colour so it reads as the addon's. The steps stay on the button's tooltip.
function QuestFinder:AddTooltipLines(tooltip, questID, title)
    if type(tooltip) ~= "table" or not tooltip.AddLine then return false end
    if type(questID) ~= "number" or questID <= 0 then questID = ns.modules.QuestIndex:QuestIDByTitle(title) end
    if not questID then return false end
    -- A tooltip set through several paths at once (link and quest data) gets the lines once.
    if tooltip.nuuRoadQuestID == questID then return true end
    tooltip.nuuRoadQuestID = questID
    -- A blank line sets the addon's lines apart from the quest's own text,
    -- unless the tooltip already ends on one (or its lines cannot be read).
    local lines = tooltip.NumLines and tooltip:NumLines() or 0
    local name = tooltip.GetName and tooltip:GetName()
    local last = lines > 0 and name and _G[name .. "TextLeft" .. lines]
    local lastText = last and last.GetText and last:GetText()
    if lines == 0 or not last or (type(lastText) == "string" and lastText:match("%S")) then tooltip:AddLine(" ") end
    local entries = ns.modules.QuestIndex:GuidesFor(questID)
    -- Only the addon's name takes its colour, the way the chat prefix does; the answer stays white.
    local prefix = "|cff4cc9f0NuuRoad:|r "
    if #entries == 0 then
        tooltip:AddLine(prefix .. "not in any of your guides", 0.7, 0.7, 0.7, true)
    elseif #entries == 1 then
        tooltip:AddLine(prefix .. (entries[1].guide.meta.title or "Untitled guide"), 1, 1, 1, true)
    else
        -- Several guides: one per line under the header, the active one marked.
        local Progress = ns.modules.Progress
        local active = Progress and Progress.store and Progress:GetActiveGuide()
        tooltip:AddLine(prefix .. "in " .. #entries .. " guides", 1, 1, 1)
        for _, entry in ipairs(entries) do
            local isActive = active ~= nil and active.id == entry.guide.id
            tooltip:AddLine("  " .. (entry.guide.meta.title or "Untitled guide") .. (isActive and " (active)" or ""), 1, 1, 1, true)
        end
    end
    if tooltip.Show then tooltip:Show() end
    return true
end

-- A quest log row under the mouse. The client shows a tooltip there only for
-- party progress, so when none is up one is opened for the guide lines.
function QuestFinder:OnQuestLogRow(button, questID, title)
    if not GameTooltip then return end
    local Client = ns.modules.Client
    if not Client:TooltipOwnedBy(GameTooltip, button) then
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or ns.modules.Names:DescribeQuest(questID), 1, 1, 1)
    end
    self:AddTooltipLines(GameTooltip, questID, title)
end

function QuestFinder:Hide()
    if self.button then self.button:Hide() end
end

function QuestFinder:RefreshQuestLog()
    local Client = ns.modules.Client
    local frame = Client:GetQuestLogDetailFrame()
    if not frame or not (frame.IsVisible and frame:IsVisible()) then self:Hide(); return end
    local questID, title = Client:GetSelectedQuestLogQuest()
    self:Show(frame, questID, title)
end

function QuestFinder:RefreshOffer()
    local Client = ns.modules.Client
    local frame = Client:GetQuestOfferFrame()
    if not frame then self:Hide(); return end
    self:Show(frame, Client:GetOpenQuestID(), Client:GetQuestDialogTitle())
end

function QuestFinder:Initialize()
    if not ns.modules.QuestIndex or type(CreateFrame) ~= "function" then return end
    self:CreateButton()
    local Client = ns.modules.Client
    self.hooks = Client:OnQuestLogSelection(function() self:RefreshQuestLog() end)
    for _, name in ipairs(Client:OnQuestTooltip(function(tooltip, questID, title) self:AddTooltipLines(tooltip, questID, title) end)) do table.insert(self.hooks, name) end
    for _, name in ipairs(Client:OnQuestLogRowEnter(function(button, questID, title) self:OnQuestLogRow(button, questID, title) end)) do table.insert(self.hooks, name) end
    if GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function(tooltip) tooltip.nuuRoadQuestID = nil end)
    end
    ns:Log("quest finder: hooked " .. (#self.hooks > 0 and table.concat(self.hooks, ", ") or "nothing"))
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_DETAIL", "QUEST_FINISHED", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "QUEST_DETAIL" then
            self:RefreshOffer()
        elseif event == "QUEST_FINISHED" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
            -- The offer closed or moved on; the log button comes back on its own hook.
            if self.button and self.button:GetParent() == Client:GetQuestOfferFrame() then self:Hide() end
        elseif event == "QUEST_LOG_UPDATE" then
            if self.button and self.button:IsShown() and self.button:GetParent() ~= Client:GetQuestOfferFrame() then self:RefreshQuestLog() end
        end
    end)
    local log = Client:GetQuestLogDetailFrame()
    if log and log.HookScript then
        pcall(log.HookScript, log, "OnShow", function() self:RefreshQuestLog() end)
        pcall(log.HookScript, log, "OnHide", function() self:Hide() end)
    end
    self.frame = frame
end

ns:RegisterModule("QuestFinder", QuestFinder)
