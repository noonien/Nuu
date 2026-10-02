local _, ns = ...

-- Buys shopping-list items from the open vendor when the player presses Buy
-- or Buy all on the strip under the vendor's window (UI/VendorStrip.lua):
-- what is still missing, rounded up to the vendor's batches and
-- held to its stock, for money only (an item costing a currency or other
-- items is left to the player). As NuuRoad's junk selling does, it makes one
-- call every fifth of a second so the client has each purchase settled
-- before the next, checks that the vendor's slot still holds the item before
-- each, stops when the vendor closes, and says in chat what it bought.
--
-- It buys only on the player's press, only from a vendor the player opened,
-- and never more than the list says is missing.
local Buying = {}

local BUY_INTERVAL = 0.2 -- seconds between two purchase calls

local function Client() return ns.modules.Client end

local function after(seconds, callback)
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then timer.After(seconds, callback) else callback() end
end

-- What buying `missing` items from `offer` (Client:MerchantOffers) takes:
-- `purchases` (the vendor's batches of `offer.count`), the `items` they
-- give, the `cost` in copper, and `calls`: for a vendor selling one at a
-- time, a quantity per call up to its `maxStack`; for one selling batches,
-- one batch a call (false: no quantity). nil when nothing can be bought.
function Buying:Plan(offer, missing)
    if not offer or not offer.price or (missing or 0) <= 0 then return nil end
    local per = math.max(1, offer.count or 1)
    local purchases = math.ceil(missing / per)
    if offer.stock then purchases = math.min(purchases, offer.stock) end
    if purchases <= 0 then return nil end
    local calls = {}
    if per == 1 then
        local chunk, left = math.max(1, offer.maxStack or 1), purchases
        while left > 0 do
            local quantity = math.min(chunk, left)
            table.insert(calls, quantity)
            left = left - quantity
        end
    else
        for _ = 1, purchases do table.insert(calls, false) end
    end
    return { purchases = purchases, items = purchases * per, per = per, cost = purchases * offer.price, calls = calls }
end

function Buying:Busy() return self.run ~= nil end

-- Starts buying `entries`, each { itemID, name, offer, missing }, one
-- after the other. `done()` is called once it ends. Answers true, or false
-- and why not.
function Buying:StartAll(entries, done)
    if self.run then return false, "Still buying." end
    local steps, cost, order = {}, 0, {}
    for _, entry in ipairs(entries or {}) do
        local plan = self:Plan(entry.offer, entry.missing)
        if plan then
            local name = entry.name or ("item " .. tostring(entry.itemID))
            for _, quantity in ipairs(plan.calls) do
                table.insert(steps, { index = entry.offer.index, itemID = entry.itemID, name = name, per = plan.per,
                    price = entry.offer.price, quantity = quantity })
            end
            cost = cost + plan.cost
            table.insert(order, { itemID = entry.itemID, name = name, items = plan.items })
        end
    end
    if #steps == 0 then return false, "Nothing to buy." end
    if Client():GetMoney() < cost then return false, "Not enough money." end
    self.run = { steps = steps, order = order, bought = {}, copper = 0, done = done }
    ns:Record("prof", { event = "buy", items = order, cost = cost, calls = #steps })
    self:Next()
    return true
end

-- One item: StartAll with one entry.
function Buying:Start(itemID, name, offer, missing, done)
    return self:StartAll({ { itemID = itemID, name = name, offer = offer, missing = missing } }, done)
end

-- One call, then the next after the interval, until none is left, a call
-- fails (the vendor closed, its slot changed) or the money runs out.
function Buying:Next()
    local run = self.run
    if not run then return end
    local step = table.remove(run.steps, 1)
    if not step then return self:Finish() end
    local items = step.quantity or step.per
    local copper = math.ceil(items / step.per) * step.price
    if Client():GetMoney() < copper then return self:Finish("ran out of money") end
    if not Client():BuyMerchantItem(step.index, step.itemID, step.quantity or nil) then
        return self:Finish("the vendor closed or its stock changed")
    end
    run.bought[step.itemID] = (run.bought[step.itemID] or 0) + items
    run.copper = run.copper + copper
    if #run.steps == 0 then return self:Finish() end
    after(BUY_INTERVAL, function() if self.run == run then self:Next() end end)
end

-- "Bought 53 Coarse Thread and 4 Red Dye for 7s 30c."
function Buying:Finish(stopped)
    local run = self.run
    if not run then return end
    self.run = nil
    local parts = {}
    for _, item in ipairs(run.order) do
        local count = run.bought[item.itemID]
        if count then table.insert(parts, count .. " " .. item.name) end
    end
    if #parts > 0 then
        local words = #parts == 1 and parts[1]
            or (table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts])
        ns:Print(("Bought %s for %s%s."):format(words, ns.Kit.FormatMoney(run.copper),
            stopped and (" (stopped: " .. stopped .. ")") or ""))
    elseif stopped then
        ns:Print("Bought nothing: " .. stopped .. ".")
    end
    if run.done then pcall(run.done) end
end

function Buying:Initialize()
    if type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    pcall(frame.RegisterEvent, frame, "MERCHANT_CLOSED")
    frame:SetScript("OnEvent", function() if self.run then self:Finish("the vendor closed") end end)
    self.frame = frame
end

ns:RegisterModule("MerchantBuying", Buying)
