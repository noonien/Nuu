local _, ns = ...

-- What an item disenchants into on Forever, and what that is worth at the
-- auction house: the lines of the item tooltip (UI/Tooltip.lua). Pure: the
-- item's class, quality and level come from the caller, the yields from
-- Data/Disenchant.lua (Tools/ProfData/disenchant.py), the prices from
-- Auctionator alone (Prices:AuctionPrice, the source API/Client.lua sets).
--
-- An uncommon to epic weapon or armour piece disenchants by its band (class,
-- quality, item level), unless the client marks it as one that cannot; an
-- item with a loot table of its own (the Hexed Pendant) has its own yields.
-- Forever's bands are its client's; their yields are Classic's rates, held by
-- the server, so a band Forever added (rare, item level 5-20) is known to
-- disenchant but not into what.
local Disenchant = {}

Disenchant.WEAPON, Disenchant.ARMOR = 2, 4

function Disenchant:Data()
    return self.data or ns.disenchantData or {}
end

-- Another data set, for the tests; nil goes back to the shipped one.
function Disenchant:SetData(data)
    self.data = data
end

-- `item` = { itemID, classID, quality, itemLevel }. nil when it does not
-- disenchant; else { yields = { { itemID, chance, min, max }, ... } } with
-- `band` the band it falls in, or { unknown = true } when it disenchants
-- into something not known yet.
function Disenchant:Of(item)
    if type(item) ~= "table" then return nil end
    local data = self:Data()
    local id = tonumber(item.itemID)
    if id and data.noDisenchant and data.noDisenchant[id] then return nil end
    local own = id and data.ownLoot and data.ownLoot[id]
    if own then return { yields = own } end
    if own == false then return { unknown = true } end
    local class, quality, level = item.classID, item.quality, tonumber(item.itemLevel)
    if (class ~= self.WEAPON and class ~= self.ARMOR) or not level then return nil end
    for _, band in ipairs(data.bands or {}) do
        if band[1] == class and band[2] == quality and level >= band[3] and level <= band[4] then
            if band.yields then return { yields = band.yields, band = band } end
            return { unknown = true, band = band }
        end
    end
    return nil
end

-- How many of a yield one disenchant gives on average.
function Disenchant.Expected(yield)
    return (yield[2] or 0) * ((yield[3] or 0) + (yield[4] or 0)) / 2
end

-- What one material is worth at the auction house: Auctionator's price, and
-- only Auctionator's (prices typed in the planner are left out). nil when it
-- has none. The cut is not taken off: this is the market's price, as the
-- auction house shows it.
function Disenchant:MaterialPrice(itemID)
    local Prices = ns.modules.Prices
    if not Prices then return nil end
    return (Prices:AuctionPrice(itemID))
end

-- The value of `result` (from Disenchant:Of): { total, rows, unpriced },
-- each row { itemID, chance, min, max, expected, price, outcome, value }
-- (price, outcome and value nil when unpriced). One disenchant gives one of
-- the rows: `outcome` is what that row is worth when it comes up (its price
-- times the middle of its range), `value` its share of the average (its
-- price times its expected
-- count, the drop rate times the middle of its range (80% of 1-2 is 1.2), as
-- TSM's amountOfMats; `total` sums the priced rows, nil when none is priced;
-- `unpriced` counts the rows without a price.
function Disenchant:Value(result)
    if not result or not result.yields then return nil end
    local rows, total, unpriced = {}, nil, 0
    for _, yield in ipairs(result.yields) do
        local expected = Disenchant.Expected(yield)
        local price = self:MaterialPrice(yield[1])
        local row = { itemID = yield[1], chance = yield[2], min = yield[3], max = yield[4], expected = expected, price = price }
        if price then
            row.outcome = price * ((yield[3] or 0) + (yield[4] or 0)) / 2
            row.value = price * expected
            total = (total or 0) + row.value
        else
            unpriced = unpriced + 1
        end
        table.insert(rows, row)
    end
    return { total = total, rows = rows, unpriced = unpriced }
end

-- One disenchant against the table: the row the `disenchant` log channel
-- keeps (API/Client.lua records it), so play can show where the table is
-- wrong. `item` as for Disenchant:Of (from before the item was destroyed),
-- `loot` = { { itemID, count }, ... } what the loot window held. The row:
--   item, quality, itemLevel, class   the item
--   band       "class/quality/min-max" when it falls in one
--   expected   "yields" (the table knows), "unknown" (it knows the item
--              disenchants, not into what), "none" (it says it does not)
--   loot       the loot as given
--   surprises  what the table did not expect, each { why, itemID, count }:
--              "material" (not among the yields), "count" (outside the
--              yield's range), "several" (more than one material: one
--              disenchant gives one), "nothing" (empty loot), "disenchanted"
--              (the table says it cannot be); nil when there are none
function Disenchant:Check(item, loot)
    item, loot = item or {}, loot or {}
    local result = self:Of(item)
    local row = { item = item.itemID, quality = item.quality, itemLevel = item.itemLevel, class = item.classID,
        loot = loot, expected = not result and "none" or (result.unknown and "unknown" or "yields") }
    local band = result and result.band
    if band then row.band = band[1] .. "/" .. band[2] .. "/" .. band[3] .. "-" .. band[4] end
    local surprises = {}
    if not result then table.insert(surprises, { why = "disenchanted" }) end
    if #loot == 0 then table.insert(surprises, { why = "nothing" }) end
    if #loot > 1 then table.insert(surprises, { why = "several" }) end
    if result and result.yields then
        for _, got in ipairs(loot) do
            local yield
            for _, candidate in ipairs(result.yields) do
                if candidate[1] == got[1] then yield = candidate end
            end
            if not yield then
                table.insert(surprises, { why = "material", itemID = got[1], count = got[2] })
            elseif got[2] and (got[2] < yield[3] or got[2] > yield[4]) then
                table.insert(surprises, { why = "count", itemID = got[1], count = got[2] })
            end
        end
    end
    if #surprises > 0 then row.surprises = surprises end
    return row
end

-- "1-2", or "3" when always the same count.
function Disenchant.Range(row)
    if row.min == row.max then return tostring(row.min) end
    return row.min .. "-" .. row.max
end

-- "80%", "0.5%".
function Disenchant.Percent(chance)
    local percent = (chance or 0) * 100
    if percent >= 1 then return string.format("%d%%", math.floor(percent + 0.5)) end
    return (string.format("%.1f", percent):gsub("%.0$", "")) .. "%"
end

ns:RegisterModule("Disenchant", Disenchant)
