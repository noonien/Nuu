local _, ns = ...

-- A grid of item slots for the current step, five to a row, on the kit's
-- strip (UI:StripPanel): the icon is the whole control, the item's own
-- tooltip explains it, and a click uses the item. Nothing here is a plan --
-- an item only takes a slot once it is really in the player's bags and
-- either the game says it has a use or the guide says it begins a quest, so
-- the grid is the step's "press this" and nothing more.
--
-- The slots are secure and the first ten are bindable (Key Bindings >
-- AddOns > NuuRoad, NuuRoadItemButton1 to 10), because the whole point of
-- the grid is reaching a quest item without digging through the bags.
-- NuuRoad never presses one itself. They are the kit's secure slots, never
-- pooled: each is made once, the first time a step needs that many, and
-- kept for the session, so its global name and its binding stay with it.
local ItemPanel = { slots = {}, rows = {}, pending = false }

local COLUMNS, BOUND_SLOTS = 5, 10
local QUESTION = "Interface/Icons/INV_Misc_QuestionMark"

-- Only the first ten slots are named and bindable; anything past that still
-- shows, it just has no key of its own.
ItemPanel.buttonNames = {}
for index = 1, BOUND_SLOTS do
    ItemPanel.buttonNames[index] = "NuuRoadItemButton" .. index
    _G["BINDING_NAME_CLICK " .. ItemPanel.buttonNames[index] .. ":LeftButton"] = "Use step item " .. index
end


local function Config() return ns.modules.Config end
local function Client() return ns.modules.Client end
local function UI() return ns:GetUI() end

function ItemPanel:Enabled()
    return Config():Get("itemPanel.shown") == true and Config():Get("tracker.shown") == true
end

-- The items the current step is about, in the order the step names them, kept
-- to the ones the player is carrying and the game will let them use. Counts
-- come from the bags, so the number on the icon is what is really there.
function ItemPanel:Candidates()
    local Progress, Client = ns.modules.Progress, Client()
    local seen, items = {}, {}
    if not self:Enabled() then return items end
    -- The travel route's hearth or teleport is not here: it takes the
    -- arrow's place in the arrow window (UI/TravelRoute.lua).
    local guide = Progress and Progress.store and Progress:GetActiveGuide()
    if not guide then return items end
    local node = Progress:GetCurrentNode(guide)
    if not node then return items end
    -- `starts` means the guide has said this item begins a quest. The client
    -- gives such an item no use spell -- "Begins a quest" is not one -- so
    -- asking the client alone would drop exactly the item the step is about.
    -- Everything else has to earn its slot by really having a use, or a
    -- step's quest items would fill the panel with loot nobody can press.
    local function consider(id, authored, startsQuest)
        if type(id) ~= "number" or seen[id] then return end
        seen[id] = true
        local count = Client:GetItemCount(id)
        if count <= 0 then return end
        if not authored and not Client:IsItemUsable(id) then return end
        table.insert(items, { itemID = id, count = count, startsQuest = startsQuest or nil })
    end
    -- The step, then the rest of its authored group, then anything carried
    -- alongside it: everything the tracker is showing right now.
    local nodes = Progress:QuestGroup(guide, node)
    for _, carried in ipairs(Progress:Carried(guide, node)) do table.insert(nodes, carried) end
    -- The step's own `use` first and unconditionally: the author has said
    -- this is the thing to press, and it is often not the item the step
    -- counts (smash the picks, collect the tools).
    for _, candidate in ipairs(nodes) do
        for _, id in ipairs(candidate.use or {}) do consider(id, true) end
    end
    for _, candidate in ipairs(nodes) do
        local auto = candidate.auto
        for index, id in ipairs(auto and auto.collect or {}) do
            local starts = index == 1 and auto.starts ~= nil
            consider(id, starts, starts)
        end
        for _, id in ipairs(candidate.refs and candidate.refs.items or {}) do consider(id) end
        if auto and auto.item then consider(auto.item) end
    end
    return items
end

-- The item's own tooltip, from the kit (the slot's item); what NuuRoad adds
-- to it goes in a tooltip of its own over the item's.
local function fillSlotTooltip(tip, slot)
    local data = slot.data
    local t = slot.ui.tokens
    if data.spellID then
        local shown = tip.SetSpellByID and pcall(tip.SetSpellByID, tip, data.spellID)
        if not shown then tip:SetText(data.spellName or "Teleport", t.text[1], t.text[2], t.text[3]) end
    else
        tip:SetText(ns.modules.Names:DescribeItem(data.itemID), t.text[1], t.text[2], t.text[3])
    end
    if data.startsQuest then tip:AddLine("Using it starts its quest.", t.quest[1], t.quest[2], t.quest[3]) end
    local key = data.buttonName and Client():GetBindingKeyForButton(data.buttonName)
    if key then tip:AddLine("Bound to " .. key, t.accent[1], t.accent[2], t.accent[3]) end
end

local function createSlot(index)
    local ui = UI()
    local rowIndex = math.floor((index - 1) / COLUMNS) + 1
    local row = ItemPanel.rows[rowIndex]
    if not row then
        row = ItemPanel.grid:Row{ gap = 4 }
        ItemPanel.rows[rowIndex] = row
    end
    local name = ItemPanel.buttonNames[index] -- nil past the bindable ten
    local slot = row:Slot({ name = name, secure = { type = "macro", macrotext = "/stopmacro" },
        data = { index = index, buttonName = name } })
    -- Key down only, as the game's own action buttons with key-down casting.
    slot:Customize(ui.Custom.frame)
    if slot:IsSecure() and slot.RegisterForClicks then slot:RegisterForClicks("AnyDown") end
    slot.data.tooltip = function(tip) fillSlotTooltip(tip, slot) end
    return slot
end

function ItemPanel:Create()
    local strip = UI():StripPanel({ key = "itemPanel", place = ns.db.windows, title = "Items", rail = "warning",
        point = { "CENTER", UIParent, "CENTER", 300, 100 } })
    self.frame = strip
    self.grid = strip:Column{ gap = 4 }
    strip:Hide()
end

function ItemPanel:Refresh()
    if not self.frame then return end
    local Client = Client()
    -- The macro behind a secure button cannot be rewritten in combat, so the
    -- strip freezes as it was and catches up when combat ends.
    if Client:InCombatLockdown() then self.pending = true; return end
    self.pending = false
    local items = self:Candidates()
    local shown = #items
    for index = 1, shown do
        local entry = items[index]
        local slot = self.slots[index]
        if not slot then slot = createSlot(index); self.slots[index] = slot end
        local data = slot.data
        data.itemID, data.startsQuest = entry.itemID, entry.startsQuest
        data.spellID, data.spellName = entry.spellID, entry.spellName
        -- The item's quality ring, cooldown and tooltip come with it.
        slot:SetItem(entry.itemID)
        local icon = entry.spellID and Client:GetSpellIcon(entry.spellID) or (entry.itemID and Client:GetItemIcon(entry.itemID))
        if icon then
            slot:SetIcon(icon)
        else
            -- The client has nothing cached for this item yet. Show the
            -- question mark, ask the server, and paint again when
            -- GET_ITEM_INFO_RECEIVED says the answer arrived; without the
            -- ask, a slot for an item nobody has inspected stays a question
            -- mark for as long as the step lasts.
            slot:SetIcon(QUESTION)
            if not entry.spellID then Client:RequestItemData(entry.itemID) end
        end
        slot:SetCount(entry.count)
        -- An item that begins a quest is the one the step is really about,
        -- so it wears the quest mark.
        slot:SetQuest(entry.startsQuest)
        local key = data.buttonName and Client:GetBindingKeyForButton(data.buttonName)
        slot:SetKey(key)
        -- The item's own tooltip alone, unless there is more to say.
        slot:SetTooltip((entry.startsQuest or key or entry.spellID) and data.tooltip or nil)
        -- A spell is cast by the name the client gives it, an item used by
        -- its ID; either way the player's click is what does it.
        if slot:IsSecure() then
            slot:SetSecure({ macrotext = entry.spellID and ("/cast " .. entry.spellName) or ("/use item:" .. entry.itemID) })
        end
        slot:Show()
    end
    for index = shown + 1, #self.slots do
        local slot = self.slots[index]
        slot:Hide()
        slot.data.itemID, slot.data.spellID = nil, nil
    end
    for rowIndex, row in ipairs(self.rows) do row:SetShown((rowIndex - 1) * COLUMNS < shown) end
    if shown == 0 then self.frame:Hide(); return end
    self.frame:SetSummary(shown > 1 and (shown .. " items") or "")
    self.frame:SetScale(Config():Get("tracker.scale") or 1)
    self.frame:Show()
end

-- Whether a shown slot is still waiting on the client for this item.
function ItemPanel:Waiting(itemID)
    if type(itemID) ~= "number" then return false end
    for _, slot in ipairs(self.slots) do
        if slot:IsShown() and slot.data.itemID == itemID then return true end
    end
    return false
end

function ItemPanel:OnCombatEnded()
    if self.pending then self:Refresh() end
end

-- What these settings refresh, and the tracker's own: the strip follows the tracker's visibility and scale.
function ItemPanel:OnSettingChanged(path)
    if path:sub(1, 10) == "itemPanel." or path == "tracker.shown" or path == "tracker.scale" then
        self:Refresh()
    end
end

-- Cooldowns change with no step change; the slots with an item follow.
local function updateCooldowns()
    for _, slot in ipairs(ItemPanel.slots) do
        if slot:IsShown() and slot.data.itemID then slot:UpdateCooldown() end
    end
end

function ItemPanel:Initialize()
    self:Create()
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
        "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_COOLDOWN" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, itemID)
        if event == "PLAYER_REGEN_ENABLED" then
            self:OnCombatEnded()
        elseif event == "BAG_UPDATE_COOLDOWN" then
            updateCooldowns()
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            -- The client answers for every item anything on screen asks
            -- about, so repaint only when the answer is about a slot of ours.
            if self:Waiting(itemID) then self:Refresh() end
        else
            self:Refresh()
        end
    end)
    self.events = frame
    self:Refresh()
end

ns:RegisterModule("ItemPanel", ItemPanel)
