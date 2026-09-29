_G = _G or _ENV
local ns = { modules = {}, db = { settings = { automation = { sellJunk = true } } }, printed = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
-- The coins come coloured (Kit.FormatMoney); the words are checked plain.
local function plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
function ns:Print(message) table.insert(self.printed, plain(message)) end
function ns:Log() end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Domain/JunkSelling.lua")
local JunkSelling = ns.modules.JunkSelling

local bags, sold, shift, native, nativeCalls
local Client = {}
function Client:IsShiftDown() return shift end
function Client:GetJunkSlots()
    local junk = {}
    for _, entry in ipairs(bags) do table.insert(junk, { bag = entry.bag, slot = entry.slot, itemID = entry.itemID, count = entry.count, price = entry.price }) end
    return junk
end
function Client:SellAllJunk()
    if not native then return false end
    nativeCalls = nativeCalls + 1
    return true
end
function Client:SellBagItem(bag, slot, itemID)
    for _, entry in ipairs(bags) do
        if entry.bag == bag and entry.slot == slot and entry.itemID == itemID then
            table.insert(sold, itemID)
            return true
        end
    end
    return false
end
ns.modules.Client = Client

local function reset(nativeSell)
    bags = {
        { bag = 0, slot = 1, itemID = 4865, count = 3, price = 15 },
        { bag = 1, slot = 4, itemID = 5134, count = 1, price = 10250 },
    }
    sold, shift, native, nativeCalls, ns.printed = {}, false, nativeSell, 0, {}
    JunkSelling.queue = nil
end

local function drain()
    for _ = 1, 20 do JunkSelling:OnUpdate(1) end
end

assert(plain(JunkSelling:FormatMoney(15)) == "15c")
assert(plain(JunkSelling:FormatMoney(10265)) == "1g 3s", "the two largest coins, rounded")
assert(plain(JunkSelling:FormatMoney(300)) == "3s", "no zero coin")
assert(plain(JunkSelling:FormatMoney(20013)) == "2g")
assert(JunkSelling:FormatMoney(15):find("|c", 1, true), "each coin in its colour")

-- The game's own Sell All Junk is used in one call when the client has it.
reset(true)
JunkSelling:OnMerchantShow()
assert(nativeCalls == 1 and #sold == 0 and JunkSelling.queue == nil)
assert(ns.printed[1] == "Sold 4 junk items for 1g 3s.", ns.printed[1])

-- Without it, one stack per tick, and the total at the end.
reset(false)
JunkSelling:OnMerchantShow()
assert(#sold == 0, "nothing is sold before the first tick")
drain()
assert(#sold == 2 and sold[1] == 4865 and sold[2] == 5134)
assert(#ns.printed == 1 and ns.printed[1] == "Sold 4 junk items for 1g 3s.", ns.printed[1])

-- A stack moved since the bags were read is skipped, not replaced.
reset(false)
JunkSelling:OnMerchantShow()
bags[1].itemID = 2589
drain()
assert(#sold == 1 and sold[1] == 5134)
assert(ns.printed[1] == "Sold 1 junk item for 1g 3s.", ns.printed[1])

-- Off, or Shift held as the vendor opens: nothing is sold.
reset(true)
ns.db.settings.automation.sellJunk = false
JunkSelling:OnMerchantShow(); drain()
assert(nativeCalls == 0 and #sold == 0 and #ns.printed == 0)
ns.db.settings.automation.sellJunk = true
reset(true)
shift = true
JunkSelling:OnMerchantShow(); drain()
assert(nativeCalls == 0 and #sold == 0 and #ns.printed == 0)

-- Shift part way through stops the rest; closing the vendor ends the run.
reset(false)
JunkSelling:OnMerchantShow()
JunkSelling:OnUpdate(1)
shift = true
drain()
assert(#sold == 1 and JunkSelling.queue == nil and ns.printed[1] == "Sold 3 junk items for 15c.")
reset(false)
JunkSelling:OnMerchantShow()
JunkSelling:Finish()
drain()
assert(#sold == 0 and #ns.printed == 0)

-- Bags with no junk start nothing.
reset(true)
bags = {}
JunkSelling:OnMerchantShow()
assert(nativeCalls == 0 and JunkSelling.queue == nil)
