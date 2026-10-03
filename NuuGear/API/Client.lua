local _, ns = ...

-- NuuGear's client adapter: every game call it makes goes through here,
-- feature-detected and guarded, so a client that lacks a call or changes it
-- degrades to "not known" rather than an error. The detection core is
-- NuuProfessions'; the item reads follow
-- what ForeverGear found works on the Forever client (C_Item stats filled
-- out from the item's tooltip, C_PlayerInfo.CanUseItem for what the
-- character may wear).
local Client = {}

local function global(name)
    return rawget(_G, name)
end

-- Values the client hides from addons (secret values): see Kit.IsSecret.
local function secret(value)
    return ns.Kit.IsSecret(value)
end

local function text(value)
    if type(value) ~= "string" or secret(value) or #value == 0 then return nil end
    return value
end

local function plainNumber(value)
    if type(value) ~= "number" or secret(value) then return nil end
    return value
end

-- A function out of a C_ namespace, else the old global of the same name.
local function api(namespace, name, legacy)
    local space = global(namespace)
    if type(space) == "table" and type(space[name]) == "function" then return space[name] end
    local fn = global(legacy or name)
    if type(fn) == "function" then return fn end
    return nil
end

function Client:Read(func, ...)
    return ns.Kit.Read(func, ...)
end

-- The player ------------------------------------------------------------------

function Client:GetUnitName(unit)
    return text(self:Read(global("UnitName"), unit))
end

function Client:GetUnitGUID(unit)
    return text(self:Read(global("UnitGUID"), unit))
end

-- "WARRIOR", "DRUID", ...: the class file name UnitClass gives second.
function Client:GetPlayerClass()
    local fn = global("UnitClass")
    if type(fn) ~= "function" then return nil end
    local ok, _, token = pcall(fn, "player")
    return ok and text(token) or nil
end

function Client:GetPlayerLevel()
    local level = plainNumber(self:Read(global("UnitLevel"), "player"))
    return level and level > 0 and level or nil
end

function Client:CanDualWield()
    local fn = global("CanDualWield")
    if type(fn) ~= "function" then return false end
    local ok, can = pcall(fn)
    return ok and can == true
end

-- Points spent in each talent tree, in the client's tree order. The Classic
-- clients answer GetTalentTabInfo two ways: (name, icon, points, file) and
-- (id, name, description, icon, points, ...); RXPGuides reads both the same
-- way, the third value when it is a number, else the fifth.
function Client:GetTalentPoints()
    local count, info = global("GetNumTalentTabs"), global("GetTalentTabInfo")
    if type(count) ~= "function" or type(info) ~= "function" then return nil end
    local tabs = plainNumber(self:Read(count, false)) or plainNumber(self:Read(count)) or 0
    local points = {}
    for tab = 1, tabs do
        local ok, _, _, third, _, fifth = pcall(info, tab)
        local spent = ok and (plainNumber(third) or plainNumber(fifth)) or 0
        points[tab] = spent
    end
    return points
end

-- Items -----------------------------------------------------------------------

-- What a link says without the item cached: { itemID, equipLoc, classID,
-- subclassID }, or nil.
function Client:GetItemInstant(link)
    local fn = api("C_Item", "GetItemInfoInstant")
    if not fn or not text(link) then return nil end
    local ok, itemID, _, _, equipLoc, _, classID, subclassID = pcall(fn, link)
    itemID = ok and plainNumber(itemID)
    if not itemID then return nil end
    return { itemID = itemID, equipLoc = text(equipLoc), classID = plainNumber(classID),
        subclassID = plainNumber(subclassID) }
end

-- Whether the client holds the item's data. When it does not, a load is asked
-- for and GET_ITEM_INFO_RECEIVED says when it is in.
function Client:IsItemLoaded(link)
    local fn = api("C_Item", "GetItemInfo")
    if not fn then return true end
    local ok, name = pcall(fn, link)
    if ok and text(name) then return true end
    local instant = self:GetItemInstant(link)
    local request = api("C_Item", "RequestLoadItemDataByID")
    if instant and request then pcall(request, instant.itemID) end
    return false
end

-- The client's own stat table for an item ({ ITEM_MOD_STRENGTH_SHORT = 5, ... })
-- with every secret or non-numeric value dropped, or nil.
function Client:GetItemStats(link)
    local fn = api("C_Item", "GetItemStats")
    if not fn or not text(link) then return nil end
    local ok, stats = pcall(fn, link)
    if not ok or type(stats) ~= "table" then return nil end
    local result = {}
    for key, value in pairs(stats) do
        if text(key) and plainNumber(value) then result[key] = value end
    end
    return result
end

-- A tooltip nobody sees, for clients without C_TooltipInfo.
local TOOLTIP_NAME = "NuuGearHiddenTooltip"
function Client:HiddenTooltip()
    if self.hiddenTooltip then return self.hiddenTooltip end
    local create = global("CreateFrame")
    if type(create) ~= "function" then return nil end
    local ok, created = pcall(create, "GameTooltip", TOOLTIP_NAME, nil, "GameTooltipTemplate")
    if not ok or not created then return nil end
    self.hiddenTooltip = created
    return created
end

-- The item's tooltip as lines of { left, right } text, or nil, and the
-- tooltip data's instance ID when it says more may come. Forever sends some
-- of an item's green "Equip:" lines after the base data (ForeverGear found
-- this); TOOLTIP_DATA_UPDATE then names that instance ID, and the item is
-- read again (Domain/ItemStats.lua).
function Client:GetTooltipLines(link)
    if not text(link) then return nil end
    local info = global("C_TooltipInfo")
    if type(info) == "table" and type(info.GetHyperlink) == "function" then
        local ok, data = pcall(info.GetHyperlink, link)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            local lines = {}
            for _, line in ipairs(data.lines) do
                if type(line) == "table" then
                    table.insert(lines, { left = text(line.leftText), right = text(line.rightText) })
                end
            end
            local instance = data.hasDynamicData == true and plainNumber(data.dataInstanceID) or nil
            return lines, instance
        end
    end
    local tooltip = self:HiddenTooltip()
    if not tooltip then return nil end
    local parent = global("UIParent")
    pcall(tooltip.SetOwner, tooltip, parent, "ANCHOR_NONE")
    pcall(tooltip.ClearLines, tooltip)
    if not pcall(tooltip.SetHyperlink, tooltip, link) then return nil end
    local count = plainNumber(self:Read(tooltip.NumLines, tooltip)) or 0
    local lines = {}
    for index = 1, count do
        local left, right = global(TOOLTIP_NAME .. "TextLeft" .. index), global(TOOLTIP_NAME .. "TextRight" .. index)
        table.insert(lines, {
            left = left and text(self:Read(left.GetText, left)),
            right = right and text(self:Read(right.GetText, right)),
        })
    end
    pcall(tooltip.Hide, tooltip)
    return lines
end

-- Whether this character may use the item: proficiency, class, level. nil
-- when the client cannot say.
function Client:CanUseItem(itemID)
    local info = global("C_PlayerInfo")
    if type(info) ~= "table" or type(info.CanUseItem) ~= "function" then return nil end
    local ok, can = pcall(info.CanUseItem, itemID)
    if not ok or secret(can) then return nil end
    return can == true
end

-- Where items are -------------------------------------------------------------

function Client:GetEquippedLink(slot)
    return text(self:Read(global("GetInventoryItemLink"), "player", slot))
end

function Client:GetBagSlotLink(bag, slot)
    local fn = api("C_Container", "GetContainerItemLink")
    return fn and text(self:Read(fn, bag, slot)) or nil
end

-- A quest reward's link: `kind` is "choice" or "reward". The quest log's
-- reward panel asks the log, the quest giver's the open quest.
function Client:GetQuestRewardLink(kind, index, fromLog, questID)
    if fromLog then
        local fn = global("GetQuestLogItemLink")
        if type(fn) ~= "function" then return nil end
        local link = questID and text(self:Read(fn, kind, index, questID))
        return link or text(self:Read(fn, kind, index))
    end
    return text(self:Read(global("GetQuestItemLink"), kind, index))
end

function Client:GetLootSlotLink(slot)
    return text(self:Read(global("GetLootSlotLink"), slot))
end

function Client:GetLootRollLink(rollID)
    return text(self:Read(global("GetLootRollItemLink"), rollID))
end

ns:RegisterModule("Client", Client)
