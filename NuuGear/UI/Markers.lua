local _, ns = ...

-- The upgrade arrow on item icons: the bags (the game's own and
-- EllesmereUIBags'), quest rewards (the quest giver's and the quest log's),
-- the loot window and group loot rolls. Each place is looked for by name and
-- hooked only when the client has it, as ForeverGear does; the arrow is our
-- own texture (Art/UpgradeArrow.tga, Tools/Art.py) because the Forever font
-- draws arrow characters as missing glyphs.
local Markers = {}

local ARROW = "Interface\\AddOns\\NuuGear\\Art\\UpgradeArrow.tga"
local SIZE = 16

local function Client() return ns.modules.Client end
local function Upgrades() return ns.modules.Upgrades end
local function enabled(place) return ns.modules.Config:Get("markers." .. place) end

-- Our textures, by the button they sit on. Kept here, not on the buttons:
-- EllesmereUIBags asks that no state be put on its secure buttons.
local arrows = setmetatable({}, { __mode = "k" })

-- Shows or hides the arrow on `button`, made the first time it shows.
-- `parent` is the frame the texture belongs to when not the button itself.
local function mark(button, show, parent)
    if not button then return end
    local arrow = arrows[button]
    if not arrow then
        if not show then return end
        local owner = parent or button
        if type(owner.CreateTexture) ~= "function" then return end
        arrow = owner:CreateTexture(nil, "OVERLAY", nil, 7)
        arrow:SetTexture(ARROW)
        arrow:SetSize(SIZE, SIZE)
        arrow:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
        arrows[button] = arrow
    end
    arrow:SetShown(show and true or false)
end

local function markLink(button, link, parent)
    local show = false
    if link then
        local ok, upgrade = pcall(Upgrades().IsUpgrade, Upgrades(), link)
        show = ok and upgrade
    end
    mark(button, show, parent)
end

local function shown(frame)
    return frame and type(frame.IsShown) == "function" and frame:IsShown()
end

local function hook(name, fn)
    if type(rawget(_G, name)) == "function" then pcall(rawget(_G, "hooksecurefunc"), name, fn) end
end

local function hookMethod(object, method, fn)
    if object and type(object[method]) == "function" then pcall(rawget(_G, "hooksecurefunc"), object, method, fn) end
end

-- Bags --------------------------------------------------------------------------

local function bagSlot(button)
    local bag
    if type(button.GetBagID) == "function" then bag = button:GetBagID() end
    if bag == nil and type(button.GetParent) == "function" then
        local parent = button:GetParent()
        if parent and type(parent.GetID) == "function" then bag = parent:GetID() end
    end
    return bag, type(button.GetID) == "function" and button:GetID() or nil
end

local function markBagButton(button)
    local bag, slot = bagSlot(button)
    if not (bag and slot) or not enabled("bags") then return mark(button, false) end
    markLink(button, Client():GetBagSlotLink(bag, slot))
end

local function bagButtons(frame, visit)
    if type(frame.EnumerateValidItems) == "function" then
        for _, button in frame:EnumerateValidItems() do visit(button) end
        return
    end
    local name = type(frame.GetName) == "function" and frame:GetName()
    for index = 1, frame.size or 36 do
        local button = (name and rawget(_G, name .. "Item" .. index)) or frame["Item" .. index]
        if button then visit(button) end
    end
end

local function bagFrames()
    local frames = {}
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if combined then table.insert(frames, combined) end
    for index = 1, rawget(_G, "NUM_CONTAINER_FRAMES") or 13 do
        local frame = rawget(_G, "ContainerFrame" .. index)
        if frame then table.insert(frames, frame) end
    end
    return frames
end

-- `repaint`: verdicts may have changed with nothing in the bags moving, so
-- EllesmereUIBags is asked to draw again too (it redraws on bag changes by
-- itself).
function Markers:RefreshBags(repaint)
    for _, frame in ipairs(bagFrames()) do
        if shown(frame) then bagButtons(frame, markBagButton) end
    end
    local bags = rawget(_G, "EUI_Bags")
    if repaint and self.ellesmere and bags and shown(bags) and type(bags.RefreshInventory) == "function" then
        pcall(bags.RefreshInventory, bags)
    end
end

function Markers:HookBags()
    hook("ContainerFrame_Update", function(frame) if frame then bagButtons(frame, markBagButton) end end)
    for _, frame in ipairs(bagFrames()) do
        hookMethod(frame, "UpdateItems", function(updated) bagButtons(updated, markBagButton) end)
        if type(frame.HookScript) == "function" then
            frame:HookScript("OnShow", function() Markers:Schedule() end)
        end
    end
    -- EllesmereUIBags paints its own buttons and calls every registered
    -- painter for each slot it draws (EUI_Bags.RegisterItemOverlayIcon).
    local bags = rawget(_G, "EUI_Bags")
    if bags and type(bags.RegisterItemOverlayIcon) == "function" then
        bags.RegisterItemOverlayIcon("NuuGear", function(button, data)
            local link = enabled("bags") and data and data.itemLink or nil
            markLink(button, link, button._textOverlay)
        end)
        self.ellesmere = true
    end
end

-- Quest rewards -----------------------------------------------------------------

-- The reward buttons of every quest panel the client may have: the
-- QuestInfo template's (quest giver, and the quest log where it uses it) and
-- the older per-frame names.
local QUEST_BUTTONS = { "QuestInfoRewardsFrameQuestInfoItem", "QuestInfoItem", "QuestLogItem", "QuestRewardItem",
    "QuestDetailItem" }

local function questButtons(visit)
    local frame = rawget(_G, "QuestInfoRewardsFrame")
    if frame and type(frame.RewardButtons) == "table" then
        for _, button in ipairs(frame.RewardButtons) do visit(button, false) end
    end
    for _, prefix in ipairs(QUEST_BUTTONS) do
        for index = 1, 10 do
            local button = rawget(_G, prefix .. index)
            if button then visit(button, prefix == "QuestLogItem") end
        end
    end
end

local function markQuestButton(button, fromLog)
    local kind = button.type
    if not shown(button) or not enabled("quests") or (kind ~= "choice" and kind ~= "reward")
        or (button.objectType and button.objectType ~= "item") then
        return mark(button, false)
    end
    local info = rawget(_G, "QuestInfoFrame")
    fromLog = fromLog or (info and info.questLog and true or false)
    local questID = button.questID
    local link = Client():GetQuestRewardLink(kind, button:GetID(), fromLog, questID)
    markLink(button, link)
end

function Markers:RefreshQuests()
    questButtons(markQuestButton)
end

function Markers:HookQuests()
    local refresh = function() Markers:RefreshQuests() end
    for _, name in ipairs({ "QuestInfo_Display", "QuestInfo_ShowRewards", "QuestLog_UpdateQuestDetails",
        "QuestFrameItems_Update" }) do
        hook(name, refresh)
    end
end

-- The loot window -----------------------------------------------------------------

function Markers:RefreshLoot()
    local frame = rawget(_G, "LootFrame")
    if not shown(frame) then return end
    local on = enabled("loot")
    -- The scrolling loot window of newer clients: one element frame per slot.
    local box = frame.ScrollBox
    if type(box) == "table" and type(box.ForEachFrame) == "function" then
        box:ForEachFrame(function(element)
            local slot = type(element.GetSlotIndex) == "function" and element:GetSlotIndex() or nil
            local button = type(element.Item) == "table" and element.Item or element
            markLink(button, on and slot and Client():GetLootSlotLink(slot) or nil)
        end)
        return
    end
    for index = 1, rawget(_G, "LOOTFRAME_NUMBUTTONS") or 4 do
        local button = rawget(_G, "LootButton" .. index)
        if button then
            local slot = shown(button) and on and button.slot
            markLink(button, slot and Client():GetLootSlotLink(slot) or nil)
        end
    end
end

-- Group loot rolls ----------------------------------------------------------------

local function rollFrames()
    local frames = {}
    for index = 1, math.max(rawget(_G, "NUM_GROUP_LOOT_FRAMES") or 4, 4) do
        local frame = rawget(_G, "GroupLootFrame" .. index)
        if frame then table.insert(frames, frame) end
    end
    local container = rawget(_G, "GroupLootContainer")
    if container and type(container.rollFrames) == "table" then
        for _, frame in pairs(container.rollFrames) do table.insert(frames, frame) end
    end
    return frames
end

function Markers:RefreshRolls()
    local on = enabled("rolls")
    for _, frame in ipairs(rollFrames()) do
        local name = type(frame.GetName) == "function" and frame:GetName()
        local icon = type(frame.IconFrame) == "table" and frame.IconFrame
            or (name and rawget(_G, name .. "IconFrame")) or frame
        local rollID = frame.rollID
        local link = on and shown(frame) and rollID and Client():GetLootRollLink(rollID) or nil
        markLink(icon, link, frame)
    end
end

function Markers:HookRolls()
    hook("GroupLootFrame_OpenNewFrame", function() Markers:Schedule() end)
    for _, frame in ipairs(rollFrames()) do
        if type(frame.HookScript) == "function" then
            frame:HookScript("OnShow", function() Markers:Schedule() end)
        end
    end
end

-- Refreshing ----------------------------------------------------------------------

function Markers:RefreshAll(repaint)
    for _, refresh in ipairs({ self.RefreshBags, self.RefreshQuests, self.RefreshLoot, self.RefreshRolls }) do
        local ok, err = pcall(refresh, self, repaint)
        if not ok then ns:Log("markers: " .. tostring(err)) end
    end
end

-- Refreshes once, shortly: events come in bursts (a bag update fires one per
-- bag) and the client fills windows in after the event that opens them.
-- `change`: "forget" drops every verdict first; "verdicts" says some may
-- read differently now (an item came in).
function Markers:Schedule(change)
    if change == "forget" then self.forget = true end
    if change then self.repaint = true end
    if self.pending then return end
    local timer = rawget(_G, "C_Timer")
    if type(timer) ~= "table" or type(timer.After) ~= "function" then
        return self:Flush()
    end
    self.pending = true
    timer.After(0.1, function() Markers:Flush() end)
end

function Markers:Flush()
    self.pending = false
    if self.forget then Upgrades():Forget() end
    local repaint = self.repaint
    self.forget, self.repaint = false, false
    self:RefreshAll(repaint)
end

-- Events that change what is worn, what may be worn or how it scores drop
-- every verdict. Item data coming in may change one ("unknown" is never
-- kept, so a redraw asks again); the rest only redraw.
local FORGET = { PLAYER_EQUIPMENT_CHANGED = true, PLAYER_LEVEL_UP = true, CHARACTER_POINTS_CHANGED = true,
    SKILL_LINES_CHANGED = true }
local VERDICTS = { GET_ITEM_INFO_RECEIVED = true, ITEM_DATA_LOAD_RESULT = true }
local REDRAW = { "BAG_UPDATE_DELAYED", "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_LOG_UPDATE", "QUEST_ITEM_UPDATE",
    "LOOT_OPENED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED", "START_LOOT_ROLL" }

function Markers:OnEvent(event, arg)
    if event == "TOOLTIP_DATA_UPDATE" then
        if Upgrades():TooltipUpdated(arg) then self:Schedule("verdicts") end
    elseif FORGET[event] then
        self:Schedule("forget")
    elseif VERDICTS[event] then
        self:Schedule("verdicts")
    else
        self:Schedule()
    end
end

-- The spec or a setting changed: every verdict and every arrow again.
function Markers:Changed()
    self:Schedule("forget")
end

function Markers:Initialize()
    if type(rawget(_G, "hooksecurefunc")) ~= "function" or type(rawget(_G, "CreateFrame")) ~= "function" then
        return
    end
    self:HookBags()
    self:HookQuests()
    self:HookRolls()
    hook("LootFrame_Update", function() Markers:RefreshLoot() end)
    local frame = CreateFrame("Frame")
    local events = { "TOOLTIP_DATA_UPDATE" }
    for event in pairs(FORGET) do table.insert(events, event) end
    for event in pairs(VERDICTS) do table.insert(events, event) end
    for _, event in ipairs(REDRAW) do table.insert(events, event) end
    for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end
    frame:SetScript("OnEvent", function(_, event, arg) Markers:OnEvent(event, arg) end)
    self.frame = frame
end

ns:RegisterModule("Markers", Markers)
