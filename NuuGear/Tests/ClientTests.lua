-- API/Client.lua against stand-ins for the client's own calls.
local ns = NewNamespace()
Load(ns, "API/Client.lua")
local Client = ns.modules.Client

local saved = {}
local function stub(name, value)
    if saved[name] == nil then saved[name] = { value = rawget(_G, name) } end
    _G[name] = value
end

-- Talent points, in both shapes the Classic clients answer.
stub("GetNumTalentTabs", function() return 3 end)
stub("GetTalentTabInfo", function(tab) return "Tree" .. tab, "icon", ({ 4, 0, 11 })[tab], "file" end)
local points = Client:GetTalentPoints()
assert(points[1] == 4 and points[2] == 0 and points[3] == 11, "name, icon, points")
stub("GetTalentTabInfo", function(tab) return 100 + tab, "Tree", "description", "icon", ({ 0, 7, 1 })[tab] end)
points = Client:GetTalentPoints()
assert(points[1] == 0 and points[2] == 7 and points[3] == 1, "id, name, description, icon, points")

-- Item reads prefer C_Item, drop secret values, and say when an item is
-- still loading (asking the client to load it).
local secretValue = {}
stub("issecretvalue", function(value) return value == secretValue end)
local requested
stub("C_Item", {
    GetItemInfoInstant = function() return 2580, "Armor", "Mail", "INVTYPE_FEET", "icon", 4, 3 end,
    GetItemInfo = function(link) if link == "loaded" then return "Boots" end return nil end,
    RequestLoadItemDataByID = function(id) requested = id end,
    GetItemStats = function() return { ITEM_MOD_STAMINA_SHORT = 4, ITEM_MOD_AGILITY_SHORT = secretValue } end,
})
local instant = Client:GetItemInstant("loaded")
assert(instant.itemID == 2580 and instant.equipLoc == "INVTYPE_FEET" and instant.classID == 4)
assert(Client:IsItemLoaded("loaded") and not requested)
assert(not Client:IsItemLoaded("other") and requested == 2580, "a load is asked for")
local stats = Client:GetItemStats("loaded")
assert(stats.ITEM_MOD_STAMINA_SHORT == 4 and stats.ITEM_MOD_AGILITY_SHORT == nil, "a secret value is dropped")

-- Tooltip lines from C_TooltipInfo, with the instance ID when more may come.
stub("C_TooltipInfo", { GetHyperlink = function()
    return { dataInstanceID = 31, hasDynamicData = true,
        lines = { { leftText = "Boots" }, { leftText = "Feet", rightText = "Mail" }, { leftText = secretValue } } }
end })
local lines, instance = Client:GetTooltipLines("loaded")
assert(#lines == 3 and lines[1].left == "Boots" and lines[2].right == "Mail" and lines[3].left == nil)
assert(instance == 31)
_G.C_TooltipInfo.GetHyperlink = function() return { dataInstanceID = 32, lines = {} } end
lines, instance = Client:GetTooltipLines("loaded")
assert(#lines == 0 and instance == nil, "no instance when nothing more is coming")

-- CanUseItem: true, false, or nil when the client cannot say.
stub("C_PlayerInfo", { CanUseItem = function(id) return id == 1 end })
assert(Client:CanUseItem(1) == true and Client:CanUseItem(2) == false)
_G.C_PlayerInfo.CanUseItem = function() return secretValue end
assert(Client:CanUseItem(1) == nil)
_G.C_PlayerInfo = nil
assert(Client:CanUseItem(1) == nil)

-- Where items are.
stub("GetInventoryItemLink", function(unit, slot) return unit == "player" and slot == 6 and "belt" or nil end)
assert(Client:GetEquippedLink(6) == "belt" and Client:GetEquippedLink(7) == nil)
stub("C_Container", { GetContainerItemLink = function(bag, slot) return bag .. ":" .. slot end })
assert(Client:GetBagSlotLink(1, 4) == "1:4")
stub("GetQuestItemLink", function(kind, index) return kind .. index end)
stub("GetQuestLogItemLink", function(kind, index, questID) return questID and (kind .. index .. "@" .. questID) or "old" end)
assert(Client:GetQuestRewardLink("choice", 2, false) == "choice2")
assert(Client:GetQuestRewardLink("reward", 1, true, 99) == "reward1@99")
assert(Client:GetQuestRewardLink("reward", 1, true) == "old")

for name, entry in pairs(saved) do _G[name] = entry.value end
return true
