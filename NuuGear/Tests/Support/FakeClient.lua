-- A stand-in for API/Client.lua: the character and their items as plain
-- tables the suites fill in.
--
--   client.items[link] = { itemID, equipLoc, api = { ITEM_MOD_... = n }, lines = { "text", ... },
--                          usable = false, loading = true }
--   client.worn[slot] = link
--   client.class, client.talents, client.dualWield
local client = { items = {}, worn = {}, class = "WARRIOR", talents = { 0, 0, 0 }, dualWield = false }

function client:GetPlayerClass() return self.class end
function client:GetTalentPoints() return self.talents end
function client:CanDualWield() return self.dualWield end
function client:GetUnitName() return "Tester" end
function client:GetUnitGUID() return "Player-1-0001" end

function client:GetItemInstant(link)
    local item = self.items[link]
    return item and { itemID = item.itemID or 1, equipLoc = item.equipLoc } or nil
end

function client:IsItemLoaded(link)
    local item = self.items[link]
    return item ~= nil and not item.loading
end

function client:GetItemStats(link)
    local item = self.items[link]
    return item and item.api or nil
end

function client:GetTooltipLines(link)
    local item = self.items[link]
    if not item or not item.lines then return nil end
    local lines = {}
    for _, line in ipairs(item.lines) do table.insert(lines, { left = line }) end
    return lines, item.instance
end

function client:CanUseItem(itemID)
    for _, item in pairs(self.items) do
        if (item.itemID or 1) == itemID and item.usable ~= nil then return item.usable end
    end
    return true
end

function client:GetEquippedLink(slot) return self.worn[slot] end

-- Adds an item and hands back its link.
local nextID = 100
function client:Item(name, equipLoc, api, extra)
    nextID = nextID + 1
    local item = extra or {}
    item.itemID, item.equipLoc, item.api = nextID, equipLoc, api
    local link = "|cff1eff00|Hitem:" .. nextID .. "|h[" .. name .. "]|h|r"
    self.items[link] = item
    return link
end

return client
