local _, ns = ...

-- Sells the grey items in the bags when the player opens a vendor. Where
-- the client has the game's own Sell All Junk
-- it is used, in one call; otherwise poor-quality items the vendor pays for
-- are sold one stack at a time so the client has each sale settled before
-- the next. A chat line totals what came in. Holding Shift as the vendor
-- opens leaves the whole visit to the player, and pressing it part way
-- through stops the rest. Everything sold is on the vendor's Buyback tab.
--
-- It never sells anything better than grey, never opens a vendor, and never
-- buys or repairs.
local JunkSelling = {}

local SELL_INTERVAL = 0.2 -- seconds between two sales

function JunkSelling:Enabled()
    return ns.modules.Config:Get("automation.sellJunk") == true
end

-- Copper as every Nuu addon writes it (Kit.FormatMoney): the two largest
-- coins, a zero coin left out, so "1g 3s" and "3s", each coin's letter in
-- its coin's colour.
function JunkSelling:FormatMoney(copper)
    return ns.Kit.FormatMoney(math.floor(tonumber(copper) or 0))
end

function JunkSelling:OnMerchantShow()
    self.queue = nil
    local Client = ns.modules.Client
    if not self:Enabled() or Client:IsShiftDown() then return end
    local queue = Client:GetJunkSlots()
    if #queue == 0 then return end
    self.queue, self.sold, self.copper, self.wait = queue, 0, 0, 0
    -- The game's own call sells exactly these, so the bags as read are the
    -- account of what went.
    if Client:SellAllJunk() then
        for _, entry in ipairs(queue) do
            self.sold = self.sold + entry.count
            self.copper = self.copper + entry.price
        end
        self:Finish()
    end
end

-- Sells the next stack in the queue. Returns true while any are left.
function JunkSelling:SellNext()
    local queue = self.queue
    if not queue then return false end
    local Client = ns.modules.Client
    if Client:IsShiftDown() then return self:Finish() end
    local entry = table.remove(queue, 1)
    if entry and Client:SellBagItem(entry.bag, entry.slot, entry.itemID) then
        self.sold = self.sold + entry.count
        self.copper = self.copper + entry.price
    end
    if #queue == 0 then return self:Finish() end
    return true
end

function JunkSelling:OnUpdate(elapsed)
    if not self.queue then return end
    self.wait = self.wait - (elapsed or 0)
    if self.wait > 0 then return end
    self.wait = SELL_INTERVAL
    self:SellNext()
end

-- Ends the run, at the last stack or when the vendor closes, and says what
-- was sold.
function JunkSelling:Finish()
    if not self.queue then return false end
    self.queue = nil
    if self.sold > 0 then
        ns:Print(("Sold %d junk item%s for %s."):format(self.sold, self.sold == 1 and "" or "s", self:FormatMoney(self.copper)))
    end
    return false
end

function JunkSelling:Initialize()
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then self:OnMerchantShow() else self:Finish() end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
    self.frame = frame
end

ns:RegisterModule("JunkSelling", JunkSelling)
