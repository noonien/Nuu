-- What items disenchant into, its auction value, and the tooltip lines that
-- show it: Domain/Disenchant.lua on toy and shipped data, the client's item
-- reads and tooltip hook on stand-ins, and UI/Tooltip.lua's lines.
local saved = {}
for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "NuuGearHiddenTooltip", "GetItemInfo", "GetItemInfoInstant",
    "GetItemQualityColor", "C_Item", "Enum", "TooltipDataProcessor", "hooksecurefunc", "CreateFrame", "C_Container",
    "GetTime", "GetSpellInfo", "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo" }) do saved[name] = rawget(_G, name) end

local ns = NewNamespace()
Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
Load(ns, "Domain/Prices.lua")
Load(ns, "Data/Disenchant.lua")
Load(ns, "Domain/Disenchant.lua")
Load(ns, "UI/Tooltip.lua")
local Disenchant, Prices, Client, Tooltip = ns.modules.Disenchant, ns.modules.Prices, ns.modules.Client, ns.modules.Tooltip
local WEAPON, ARMOR = Disenchant.WEAPON, Disenchant.ARMOR
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

-- The shipped data ---------------------------------------------------------------

local data = ns.disenchantData
assert(data and #data.bands > 40, "the client's bands")
local function band(class, quality, level)
    return Disenchant:Of({ itemID = 1, classID = class, quality = quality, itemLevel = level })
end
local function first(result) return result.yields[1] end

-- Uncommon: armour gives mostly dust, weapons mostly essence.
local green = band(ARMOR, 2, 10)
assert(first(green)[1] == 10940 and first(green)[2] == 0.8, "low green armour: Strange Dust, 80%")
local greenWeapon = band(WEAPON, 2, 10)
assert(greenWeapon.yields[2][1] == 10938 and greenWeapon.yields[2][2] == 0.8, "low green weapon: Lesser Magic Essence, 80%")
-- Every known band's chances add up to one.
for _, row in ipairs(data.bands) do
    if row.yields then
        local sum = 0
        for _, yield in ipairs(row.yields) do sum = sum + yield[2] end
        assert(math.abs(sum - 1) < 1e-6, "band " .. row[1] .. "/" .. row[2] .. "/" .. row[3] .. " adds up to 100%")
    end
end
-- Forever's rare bands: 21-25 gives the Small Glimmering Shard (Classic's
-- 20-25), and the new ones below it are known to disenchant, not into what.
assert(first(band(ARMOR, 3, 21))[1] == 10978 and first(band(WEAPON, 3, 25))[1] == 10978)
assert(band(ARMOR, 3, 20).unknown and band(WEAPON, 3, 10).unknown, "Forever's new rare bands")
assert(band(ARMOR, 4, 58).yields[1][1] == 20725, "epic 56-60: Nexus Crystal")
-- What does not disenchant.
assert(band(ARMOR, 1, 20) == nil, "common items do not")
assert(band(ARMOR, 2, 3) == nil, "below the first band")
assert(band(15, 2, 20) == nil, "only weapons and armour")
assert(Disenchant:Of(nil) == nil and Disenchant:Of({ classID = ARMOR, quality = 2 }) == nil, "no level, no answer")
assert(Disenchant:Of({ itemID = 11287, classID = WEAPON, quality = 2, itemLevel = 15 }) == nil,
    "Lesser Magic Wand: the client says it cannot be disenchanted")
-- Items with a loot table of their own, whatever their class.
local pendant = Disenchant:Of({ itemID = 275724, classID = 15, quality = 2, itemLevel = 10 })
assert(pendant and pendant.yields[1][1] == 247884, "the Hexed Pendant gives Luminous Residue")
assert(Disenchant:Of({ itemID = 276538, classID = ARMOR, quality = 3, itemLevel = 30 }).unknown,
    "Spiritcaller gear: its own loot, not known yet")

-- Value -----------------------------------------------------------------------------

assert(near(Disenchant.Expected({ 10940, 0.8, 1, 2 }), 1.2), "80% of one or two")
assert(Disenchant.Range({ min = 1, max = 2 }) == "1-2" and Disenchant.Range({ min = 1, max = 1 }) == "1")
assert(Disenchant.Percent(0.8) == "80%" and Disenchant.Percent(0.05) == "5%" and Disenchant.Percent(0.005) == "0.5%")

-- Prices are Auctionator's alone.
local auction = {}
Prices:SetAuctionSource(function(itemID) return auction[itemID], 0 end)
local value = Disenchant:Value(green)
assert(value.total == nil and value.unpriced == 2 and #value.rows == 2, "nothing priced")
auction[10940] = 100
value = Disenchant:Value(green)
assert(near(value.total, 120) and value.unpriced == 1, "1.2 Strange Dust at 1s, the essence unpriced")
assert(near(value.rows[1].value, 120) and value.rows[2].value == nil)
assert(near(value.rows[1].outcome, 150) and value.rows[2].outcome == nil, "the dust outcome: 1.5 dust at 1s")
-- The drop rate weighs each share: 20% of 1-2 essence is 0.3 of one.
auction[10938] = 500
value = Disenchant:Value(green)
assert(near(value.rows[2].expected, 0.3) and near(value.total, 120 + 0.3 * 500) and value.unpriced == 0)
local book = { prices = {}, trainers = {}, merchants = {} }
Prices:SetFact(book, 10978, "auctionSell", 1500)
ns.db = { settings = {}, professions = book }
auction[10978] = 2000
assert(Disenchant:Value(band(ARMOR, 3, 22)).total == 2000, "a price typed in the planner is not used")
auction = {}

-- Toy data replaces the shipped set and goes back.
Disenchant:SetData({ bands = { { ARMOR, 2, 1, 99, yields = { { 7, 1, 2, 2 } } } } })
assert(band(ARMOR, 2, 50).yields[1][1] == 7)
Disenchant:SetData(nil)
assert(band(ARMOR, 2, 50).yields[1][1] == 11176)

-- The client's item reads -------------------------------------------------------------

local function link(id, name) return "|cff1eff00|Hitem:" .. id .. "::::::::20:::::|h[" .. name .. "]|h|r" end
local items = {
    [2000] = { "Green Gloves", 2, 12, ARMOR },
    [2001] = { "Rare Sword", 3, 23, WEAPON },
    [2002] = { "Plain Shirt", 1, 10, ARMOR },
    [10940] = { "Strange Dust", 1, 10, 7 },
    [10938] = { "Lesser Magic Essence", 2, 10, 7 },
}
local function idOf(item)
    if type(item) == "number" then return item end
    return tonumber(tostring(item):match("item:(%d+)"))
end
_G.GetItemInfo = function(item)
    local id = idOf(item)
    local row = items[id]
    if not row then return nil end
    return row[1], link(id, row[1]), row[2], row[3], 1, "Armor", "Cloth", 1, "INVTYPE_HAND", 0, 10, row[4], 1
end
_G.GetItemQualityColor = function(quality)
    return 1, 1, 1, quality == 2 and "ff1eff00" or "ffffffff"
end
local info = Client:GetItemDisenchantInfo(link(2000, "Green Gloves"))
assert(info.itemID == 2000 and info.classID == ARMOR and info.quality == 2 and info.itemLevel == 12)
info = Client:GetItemDisenchantInfo(2001)
assert(info.itemID == 2001 and info.classID == WEAPON and info.quality == 3)
assert(Client:GetItemDisenchantInfo(9999) == nil, "not cached: no answer")
assert(Client:GetItemDisenchantInfo({}) == nil)
-- A client whose GetItemInfo leaves the class out: GetItemInfoInstant has it.
local full = _G.GetItemInfo
_G.GetItemInfo = function(item)
    local a, b, c, d = full(item)
    return a, b, c, d
end
_G.GetItemInfoInstant = function(item) return idOf(item), "Armor", "Cloth", "INVTYPE_HAND", 0, ARMOR, 1 end
info = Client:GetItemDisenchantInfo(link(2000, "Green Gloves"))
assert(info.classID == ARMOR and info.itemID == 2000, "the class from GetItemInfoInstant")
_G.GetItemInfo, _G.GetItemInfoInstant = full, nil

-- The tooltip lines ------------------------------------------------------------------

local lines = Tooltip:Lines(link(2000, "Green Gloves"))
assert(lines[1][1] == "Disenchant value (average)" and lines[1][2] == "no auction prices", "nothing priced")
local function plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
assert(#lines == 3 and plain(lines[2][1]) == "  80%  1-2 Strange Dust" and lines[2][2] == "?",
    "each outcome: its drop rate and range")
assert(lines[3][1]:find("|cff1eff00Lesser Magic Essence|r", 1, true), "a material in its quality colour")
auction[10940] = 10000
lines = Tooltip:Lines(link(2000, "Green Gloves"))
assert(ns.Kit.ParseMoney(lines[1][2]:gsub(" %+%?$", "")) == 12000 and lines[1][2]:find("+?", 1, true),
    "the total, partial while a material is unpriced")
assert(ns.Kit.ParseMoney(lines[2][2]) == 15000, "what the dust outcome is worth: 1.5 dust at 1g")
auction[10938] = 10000
lines = Tooltip:Lines(link(2000, "Green Gloves"))
assert(ns.Kit.ParseMoney(lines[1][2]) == 15000 and not lines[1][2]:find("?", 1, true), "everything priced")
assert(Tooltip:Lines(link(2002, "Plain Shirt")) == nil, "a common item has no lines")
lines = Tooltip:Lines(link(2001, "Rare Sword"))
assert(#lines == 2 and not lines[2][1]:find("%%") and lines[2][1]:find("  1 ", 1, true), "a sure yield shows no chance")
items[2003] = { "Low Rare Ring", 3, 12, ARMOR }
lines = Tooltip:Lines(link(2003, "Low Rare Ring"))
assert(#lines == 1 and lines[1][1] == "Disenchants into" and lines[1][2] == "not known yet")
-- A material the client has not cached yet is named by its ID and asked for.
items[10938] = nil
local asked = {}
_G.C_Item = { RequestLoadItemDataByID = function(id) asked[id] = true end }
lines = Tooltip:Lines(link(2000, "Green Gloves"))
assert(lines[3][1]:find("item 10938", 1, true) and asked[10938])
_G.C_Item = nil
items[10938] = { "Lesser Magic Essence", 2, 10, 7 }
-- Without Auctionator there is no value, and the tooltip says what it needs.
Prices:SetAuctionSource(nil)
lines = Tooltip:Lines(link(2000, "Green Gloves"))
assert(lines[1][2] == "needs Auctionator" and lines[2][2] == "?")
Prices:SetAuctionSource(function(itemID) return auction[itemID], 0 end)

-- The tooltip hook ---------------------------------------------------------------------

local function newTooltip(name)
    local tip = { name = name, lines = {}, scripts = {}, shown = false }
    function tip:HookScript(script, fn)
        self.scripts[script] = self.scripts[script] or {}
        table.insert(self.scripts[script], fn)
    end
    function tip:Fire(script)
        for _, fn in ipairs(self.scripts[script] or {}) do fn(self) end
    end
    function tip:GetItem() return self.itemName, self.itemLink end
    function tip:AddDoubleLine(left, right) table.insert(self.lines, { left, right }) end
    function tip:Show() self.shown = true end
    function tip:SetItem(id)
        self.lines = {}
        self:Fire("OnTooltipCleared")
        self.itemName, self.itemLink = items[id][1], link(id, items[id][1])
        self:Fire("OnTooltipSetItem")
    end
    _G[name] = tip
    return tip
end
local tip, ref = newTooltip("GameTooltip"), newTooltip("ItemRefTooltip")
local hidden = newTooltip("NuuGearHiddenTooltip")
Client.capabilities = {}
Tooltip:Initialize()
assert(#Tooltip.hooks >= 2 and Client:Has("itemTooltips"), "OnTooltipSetItem on the game's tooltips")
tip:SetItem(2000)
assert(#tip.lines == 3 and tip.lines[1][1] == "Disenchant value (average)" and tip.shown, "the lines, and the tooltip resized")
tip:Fire("OnTooltipSetItem")
assert(#tip.lines == 3, "the same item twice: its lines once")
tip:SetItem(2000)
assert(#tip.lines == 3, "shown again after a clear: its lines again")
ref:SetItem(2001)
assert(#ref.lines == 2, "the item link tooltip too")
hidden:SetItem(2000)
assert(#hidden.lines == 0, "never another addon's hidden tooltip")
tip:SetItem(2002)
assert(#tip.lines == 0, "nothing for a common item")
-- The switch.
ns.modules.Config:Set("disenchantTooltip", false)
tip:SetItem(2000)
assert(#tip.lines == 0, "off: no lines")
ns.modules.Config:Reset("disenchantTooltip")
tip:SetItem(2001)
assert(#tip.lines == 2, "back on")

-- The tooltip data pipeline, where the client has it: one hook for every item
-- tooltip, and OnTooltipSetItem is left alone.
local calls = {}
_G.Enum = { TooltipDataType = { Item = 0 } }
_G.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) calls[kind] = fn end }
local modern = newTooltip("GameTooltip")
newTooltip("ItemRefTooltip")
local hooks = Client:OnItemTooltip(function(tooltip, itemLink) tooltip:AddDoubleLine("seen", itemLink) end)
assert(hooks[1] == "TooltipDataProcessor" and #hooks == 1 and calls[0], "the pipeline alone")
assert(not modern.scripts.OnTooltipSetItem, "no script hook beside it")
modern.itemName, modern.itemLink = "Green Gloves", link(2000, "Green Gloves")
calls[0](modern, { id = 2000 })
assert(#modern.lines == 1 and modern.lines[1][1] == "seen")
calls[0](hidden, { id = 2000 })
assert(#hidden.lines == 0, "the pipeline's other tooltips are left alone")
_G.Enum, _G.TooltipDataProcessor = nil, nil

-- Checking a disenchant against the table ------------------------------------------------

local gloves = { itemID = 2000, classID = ARMOR, quality = 2, itemLevel = 18 }
local row = Disenchant:Check(gloves, { { 10940, 3 } })
assert(row.band == "4/2/16-20" and row.expected == "yields" and row.item == 2000 and row.itemLevel == 18
    and row.surprises == nil, "3 Strange Dust from a level 18 green: as the table says")
row = Disenchant:Check(gloves, { { 10940, 5 } })
assert(row.surprises[1].why == "count" and row.surprises[1].count == 5, "more dust than the range")
row = Disenchant:Check(gloves, { { 247884, 1 } })
assert(row.surprises[1].why == "material" and row.surprises[1].itemID == 247884, "a material the band does not list")
row = Disenchant:Check(gloves, { { 10940, 2 }, { 10939, 1 } })
assert(row.surprises[1].why == "several", "two materials from one disenchant")
row = Disenchant:Check(gloves, {})
assert(row.surprises[1].why == "nothing")
row = Disenchant:Check({ itemID = 2003, classID = ARMOR, quality = 3, itemLevel = 12 }, { { 10978, 1 } })
assert(row.expected == "unknown" and row.band == "4/3/5-15" and row.surprises == nil,
    "a new rare band: recorded, nothing to contradict")
row = Disenchant:Check({ itemID = 11287, classID = WEAPON, quality = 2, itemLevel = 15 }, { { 10940, 1 } })
assert(row.expected == "none" and row.surprises[1].why == "disenchanted", "the table said it could not be")

-- Watching disenchants in the client ------------------------------------------------------

local clock, hooks, frame = 100, {}, nil
_G.GetTime = function() return clock end
_G.hooksecurefunc = function(a, b, c)
    if type(a) == "table" then hooks[b] = c else hooks[a] = b end
end
_G.CreateFrame = function()
    frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(_, fn) self.handler = fn end
    return frame
end
_G.C_Container = { UseContainerItem = function() end,
    GetContainerItemLink = function(bag, slot) return bag == 0 and slot == 1 and link(2000, "Green Gloves") or nil end }
_G.GetSpellInfo = function(id) return id == 13262 and "Disenchant" or "Other" end
local lootNow = {}
_G.GetNumLootItems = function() return #lootNow end
_G.GetLootSlotLink = function(slot) return link(lootNow[slot][1], "Loot") end
_G.GetLootSlotInfo = function(slot) return 0, "Loot", lootNow[slot][2] end
local function fire(event, ...) frame.handler(frame, event, ...) end
local function disenchantRows()
    local rows = {}
    for _, record in ipairs(ns.records) do
        if record.channel == "disenchant" then table.insert(rows, record.data) end
    end
    return rows
end

local placed = Client:WatchDisenchants()
assert(placed[1] == "C_Container.UseContainerItem" and Client:Has("disenchantLog") and frame.events.LOOT_OPENED)
-- The player clicks the gloves while Disenchant waits, the cast goes through,
-- the loot window opens with three Strange Dust.
hooks.UseContainerItem(0, 1)
fire("UNIT_SPELLCAST_SENT", "player", "Green Gloves", "cast-1", 13262)
clock = clock + 3
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
lootNow = { { 10940, 3 } }
fire("LOOT_READY")
fire("LOOT_OPENED")
local rows = disenchantRows()
assert(#rows == 1, "one disenchant, one row (LOOT_READY and LOOT_OPENED both fire)")
assert(rows[1].event == "disenchant" and rows[1].item == 2000 and rows[1].band == "4/2/5-15" and rows[1].quality == 2
    and rows[1].loot[1][1] == 10940 and rows[1].loot[1][2] == 3 and rows[1].link:find("Green Gloves", 1, true))
-- Looting a mob afterwards records nothing.
fire("LOOT_OPENED")
assert(#disenchantRows() == 1, "other loot is not a disenchant")
-- An interrupted cast records nothing, and neither does another spell.
hooks.UseContainerItem(0, 1)
fire("UNIT_SPELLCAST_SENT", "player", "Green Gloves", "cast-2", 13262)
fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-2", 13262)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 13262)
fire("LOOT_OPENED")
hooks.UseContainerItem(0, 1)
fire("UNIT_SPELLCAST_SENT", "player", "Green Gloves", "cast-3", 7)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 7)
fire("LOOT_OPENED")
assert(#disenchantRows() == 1, "no cast, no row")
-- A bag item used long before the cast is not its target.
hooks.UseContainerItem(0, 1)
clock = clock + 30
fire("UNIT_SPELLCAST_SENT", "player", "Something Else", "cast-4", 13262)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 13262)
fire("LOOT_OPENED")
assert(#disenchantRows() == 1, "an old item use is not the target")
-- A loot window long after the cast is not its loot.
hooks.UseContainerItem(0, 1)
fire("UNIT_SPELLCAST_SENT", "player", "Green Gloves", "cast-5", 13262)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 13262)
clock = clock + 60
fire("LOOT_OPENED")
assert(#disenchantRows() == 1, "late loot is not the disenchant's")
-- A surprise is on the row.
lootNow = { { 247884, 1 } }
hooks.UseContainerItem(0, 1)
fire("UNIT_SPELLCAST_SENT", "player", "Green Gloves", "cast-6", 13262)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6", 13262)
fire("LOOT_OPENED")
rows = disenchantRows()
assert(#rows == 2 and rows[2].surprises[1].why == "material" and rows[2].surprises[1].itemID == 247884)

Prices:SetAuctionSource(nil)
for name in pairs({ GameTooltip = 1, ItemRefTooltip = 1, NuuGearHiddenTooltip = 1, GetItemInfo = 1, GetItemInfoInstant = 1,
    GetItemQualityColor = 1, C_Item = 1, Enum = 1, TooltipDataProcessor = 1, hooksecurefunc = 1, CreateFrame = 1,
    C_Container = 1, GetTime = 1, GetSpellInfo = 1, GetNumLootItems = 1, GetLootSlotLink = 1,
    GetLootSlotInfo = 1 }) do _G[name] = saved[name] end
return true
