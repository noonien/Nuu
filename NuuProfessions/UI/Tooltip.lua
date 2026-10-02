local _, ns = ...

-- Disenchanting in the game's item tooltips: what a weapon or armour piece
-- disenchants into on Forever, and what that fetches at the auction house
-- (Domain/Disenchant.lua). One disenchant gives one of the outcomes, so each
-- line is one outcome, "75%  2-3 Strange Dust", and what it is worth when it
-- comes up (the middle of its range at its price); the total on top is the
-- average over many disenchants, each outcome weighed by its drop rate, the
-- same number as TSM's disenchant value. Prices are Auctionator's
-- alone; a material it has no price for shows "?" and the total says it is
-- partial.
--
-- The account setting `disenchantTooltip` (Options, Tooltips) turns it off.
local Tooltip = {}

local LABEL = { 1, 1, 1 }
local ROW = { 0.85, 0.85, 0.85 }
local MUTED = { 0.6, 0.6, 0.6 }

local function Client() return ns.modules.Client end

local function enabled()
    local Config = ns.modules.Config
    return not Config or Config:Get("disenchantTooltip") ~= false
end

-- A material's name in its quality colour; its ID until the client has it.
local function materialName(itemID)
    local client = Client()
    local name = client and client:GetItemName(itemID)
    if not name then
        if client then client:RequestItemData(itemID) end
        return "item " .. itemID
    end
    local hex = client:GetItemQualityColor(itemID)
    return hex and ("|c" .. hex .. name .. "|r") or name
end

local function money(copper)
    return ns.Kit.FormatMoney(copper)
end

-- The lines for `link`, as { left, right, leftColor, rightColor }, or nil
-- when the item does not disenchant. Kept apart from the tooltip so the
-- tests can read them.
function Tooltip:Lines(link)
    local client, Disenchant = Client(), ns.modules.Disenchant
    if not client or not Disenchant then return nil end
    local result = Disenchant:Of(client:GetItemDisenchantInfo(link))
    if not result then return nil end
    if result.unknown then
        return { { "Disenchants into", "not known yet", LABEL, MUTED } }
    end
    local Prices = ns.modules.Prices
    local value = Disenchant:Value(result)
    local total
    if not value.total then
        total = (Prices and Prices:AuctionSourceAvailable()) and "no auction prices" or "needs Auctionator"
    else
        total = money(value.total) .. (value.unpriced > 0 and " +?" or "")
    end
    local lines = { { "Disenchant value (average)", total, LABEL, value.total and LABEL or MUTED } }
    for _, row in ipairs(value.rows) do
        local left = Disenchant.Range(row) .. " " .. materialName(row.itemID)
        if row.chance and row.chance < 1 then left = Disenchant.Percent(row.chance) .. "  " .. left end
        left = "  " .. left
        table.insert(lines, { left, row.outcome and money(row.outcome) or "?", ROW, row.outcome and ROW or MUTED })
    end
    return lines
end

function Tooltip:Fill(tooltip, link)
    if not enabled() then return end
    local ok, lines = pcall(self.Lines, self, link)
    if not ok then
        ns:Log("disenchant tooltip: " .. tostring(lines))
        return
    end
    if not lines then return end
    for _, line in ipairs(lines) do
        local l, r = line[3], line[4]
        tooltip:AddDoubleLine(line[1], line[2], l[1], l[2], l[3], r[1], r[2], r[3])
    end
    if tooltip.Show then tooltip:Show() end
end

function Tooltip:Initialize()
    local client = Client()
    if not client or not client.OnItemTooltip then return end
    self.hooks = client:OnItemTooltip(function(tooltip, link) self:Fill(tooltip, link) end)
    -- The materials' names, asked for now so the first tooltip has them.
    local seen = {}
    local data = ns.disenchantData or {}
    local function want(yields)
        for _, yield in ipairs(yields or {}) do
            if not seen[yield[1]] then
                seen[yield[1]] = true
                client:RequestItemData(yield[1])
            end
        end
    end
    for _, band in ipairs(data.bands or {}) do want(band.yields) end
    for _, yields in pairs(data.ownLoot or {}) do
        if yields then want(yields) end
    end
end

ns:RegisterModule("Tooltip", Tooltip)
