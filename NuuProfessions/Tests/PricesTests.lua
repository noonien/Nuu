local ns = NewNamespace()
Load(ns, "Domain/Prices.lua")
local Prices = ns.modules.Prices

-- Money, ASCII only.
assert(Prices:FormatMoney(12005) == "1g 20s", "the two largest coins")
assert(Prices:FormatMoney(12005, true) == "1g 20s 5c", "or every coin, for a field")
assert(Prices:FormatMoney(20013) == "2g", "a zero coin is left out, and the copper past it too")
assert(Prices:FormatMoney(20013, true) == "2g 13c")
assert(Prices:FormatMoney(12075) == "1g 21s", "rounded to the second coin")
assert(Prices:FormatMoney(150) == "1s 50c" and Prices:FormatMoney(99) == "99c")
assert(Prices:FormatMoney(0) == "0c")
assert(Prices:FormatMoney(100) == "1s")
assert(Prices:FormatMoney(10000) == "1g")
assert(Prices:FormatMoney(-150) == "-1s 50c")
assert(Prices:FormatMoney(99.6) == "1s", "rounded to the copper")
assert(Prices:ParseMoney("1g 20s 5c") == 12005)
assert(Prices:ParseMoney("1g20s") == 12000)
assert(Prices:ParseMoney(" 20S ") == 2000, "case and spaces do not matter")
assert(Prices:ParseMoney("5 c") == 5)
assert(Prices:ParseMoney("150") == 150, "a bare number is copper")
assert(Prices:ParseMoney("") == nil and Prices:ParseMoney("abc") == nil, "a typo is refused, not read as zero")
assert(Prices:ParseMoney("1g 1g") == nil, "one of each unit")
assert(Prices:ParseMoney("1g x") == nil)
assert(Prices:ParseMoney(Prices:FormatMoney(987654, true)) == 987654, "formatting and parsing round-trip")

-- Toy data: 100 is vendor-sold by the stack of 5, 101 only drops, 102 is
-- soulbound output, 2000 is made from two 100 per craft, two at a time.
local data = {
    recipes = {
        [50] = { makes = 2000, made = { 2, 2 }, skills = { 1, 10, 15, 20 }, reagents = { { 100, 2 } }, learn = "start" },
        [51] = { makes = 2001, made = { 1, 1 }, skills = { 1, 10, 15, 20 }, reagents = { { 101, 1 } }, learn = "item", teach = 5000, bind = "bop" },
    },
    items = {
        [100] = { buy = 50, buyCount = 5, vendor = true, sell = 3 },
        [101] = { sell = 7 },
        [102] = { sell = 20, bind = "bop" },
        [2000] = { sell = 1 },
        [5000] = { sell = 0 },
    },
}
local book = { prices = {}, trainers = {}, merchants = {} }

-- Facts: the data, then a merchant window, then the player's word.
assert(Prices:Fact(book, data, 100, "vendorBuy") == 10, "the stack price is per item")
assert(select(2, Prices:Fact(book, data, 100, "vendorBuy")) == "data")
assert(Prices:Fact(book, data, 101, "vendorBuy") == nil, "not vendor-sold")
book.merchants[77] = { [100] = { price = 40, count = 5, seen = 1000 } }
local value, source, seen, npc = Prices:Fact(book, data, 100, "vendorBuy")
assert(value == 8 and source == "merchant" and seen == 1000 and npc == 77, "a merchant window beats the data")
assert(Prices:SetFact(book, 100, "vendorBuy", 5))
value, source = Prices:Fact(book, data, 100, "vendorBuy")
assert(value == 5 and source == "player", "what the player types always wins")
assert(book.revision == 1, "every change bumps the revision")
Prices:SetFact(book, 100, "vendorBuy", nil)
assert(Prices:Fact(book, data, 100, "vendorBuy") == 8, "clearing it falls back")
assert(not Prices:SetFact(book, 100, "bogus", 5), "only the four facts")
assert(not Prices:SetFact(book, 100, "auctionBuy", -1), "no negative prices")

-- Sell value: vendor, or the auction net of its 5% cut.
local ctx = Prices:Context({ book = book, data = data })
assert(ctx:SellValue(101) == 7)
Prices:SetFact(book, 101, "auctionSell", 100, "player", 2000)
ctx = Prices:Context({ book = book, data = data })
value, source = ctx:SellValue(101)
assert(value == 95 and source == "ah", "the cut is taken here, not by the player")
ctx = Prices:Context({ book = book, data = data, options = { auction = "buy" } })
assert(ctx:SellValue(101) == 7, "no selling at the auction house when the player does not")
ctx = Prices:Context({ book = book, data = data, options = { keep = { [101] = true } } })
assert(ctx:SellValue(101) == 7, "kept output is worth the vendor price at most")
ctx = Prices:Context({ book = book, data = data, options = { keep = { [101] = true }, sellOutput = "chosen" } })
assert(ctx:SellValue(101) == 7, "and is counted as sold even when only chosen items are")
ctx = Prices:Context({ book = book, data = data, options = { nosell = { [101] = true } } })
assert(ctx:SellValue(101) == 0 and ctx:SellTotal(101, 3) == 0, "output never sold is worth nothing")
ctx = Prices:Context({ book = book, data = data, options = { nosell = { [101] = true }, sell = { [101] = true }, sellOutput = "chosen" } })
assert(ctx:SellValue(101) == 0, "whatever else is set")
assert(ctx:Describe(101).nosell, "and the row says so")
Prices:SetFact(book, 102, "auctionSell", 500)
ctx = Prices:Context({ book = book, data = data })
assert(ctx:SellValue(102) == 20, "soulbound output cannot be sold to players")

-- Market depth: past the cap, copies go to the vendor.
Prices:SetDepth(book, 101, 2)
ctx = Prices:Context({ book = book, data = data })
assert(ctx:SellTotal(101, 5) == 2 * 95 + 3 * 7)
assert(ctx:SellTotal(101, 2) == 190)
Prices:SetDepth(book, 101, nil)
ctx = Prices:Context({ book = book, data = data })
assert(ctx:SellTotal(101, 5) == 5 * 95)

-- Buy cost: the cheapest allowed source.
value, source = ctx:BuyCost(100)
assert(value == 8 and source == "vendor")
value, source = ctx:BuyCost(101)
assert(value == 7 * Prices.estimateFactor and source == "estimate", "no real price: an estimate from the sell price")
assert(select(4, ctx:BuyCost(101)) == true, "and it says so")
assert(Prices:Context({ book = book, data = data, options = { auction = "none" } }):BuyCost(101) == nil,
    "no source at all, with no auction house to buy at, is unobtainable")
Prices:SetFact(book, 101, "auctionBuy", 30)
ctx = Prices:Context({ book = book, data = data })
value, source = ctx:BuyCost(101)
assert(value == 30 and source == "ah")
ctx = Prices:Context({ book = book, data = data, options = { auction = "sell" } })
assert(ctx:BuyCost(101) == nil, "no buying at the auction house when the player does not")
ctx = Prices:Context({ book = book, data = data, options = { gather = { [101] = "zero" } } })
value, source = ctx:BuyCost(101)
assert(value == 0 and source == "gather", "gathered for free")
ctx = Prices:Context({ book = book, data = data, options = { gather = { [101] = "opportunity" } } })
value, source = ctx:BuyCost(101)
assert(value == 30 and source == "ah", "gathering at what it would sell for (95) loses to buying at 30")
Prices:SetFact(book, 101, "auctionBuy", nil)
ctx = Prices:Context({ book = book, data = data, options = { gather = { [101] = "opportunity" } } })
value, source = ctx:BuyCost(101)
assert(value == 95 and source == "gather")

-- Made from its parts: two 100 at 8 each make two.
value, source, npc = ctx:BuyCost(2000)
assert(value == 8 and source == "craft" and npc.spell == 50, "an intermediate costs its reagents per item made")
ctx = Prices:Context({ book = book, data = data, canCraft = function() return false end })
value, source = ctx:BuyCost(2000)
assert(source == "estimate", "not when the recipe is out of reach: then only an estimate")
ctx = Prices:Context({ book = book, data = data })
local reagents = ctx:ReagentCost(data.recipes[50])
assert(reagents == 16)
local missing
reagents, missing = Prices:Context({ book = book, data = data }):ReagentCost({ reagents = { { 999, 1 } } })
assert(reagents == nil and missing == 999, "a missing reagent is named")

-- Carried items are costed at their sell value.
assert(ctx:BagValue(100) == 3)

-- Patterns: gold vendor, auction house; trainers. A sale for a currency is
-- not a gold sale, even with a gold price beside it.
book.merchants[80] = { [5000] = { price = 0, count = 1, currency = { [3402] = 60 } } }
book.merchants[81] = { [5000] = { price = 500, count = 1, currency = { [3001] = 10 } } }
ctx = Prices:Context({ book = book, data = data })
assert(ctx:VendorPattern(5000) == nil, "a currency sale is not a gold sale")
book.merchants[82] = { [5001] = { price = 2500, count = 1 } }
local gold, goldNPC = ctx:VendorPattern(5001)
assert(gold == 2500 and goldNPC == 82)
assert(ctx:AuctionPattern(5000) == nil)
Prices:SetFact(book, 5000, "auctionBuy", 900)
ctx = Prices:Context({ book = book, data = data })
assert(ctx:AuctionPattern(5000) == 900)
book.trainers[90] = { [51] = { cost = 300, skill = 1, level = 5 } }
book.trainers[91] = { [51] = { cost = 200 } }
local cost, trainer = ctx:TrainerCost(51)
assert(cost == 200 and trainer == 91, "the cheapest trainer that showed it")
assert(ctx:TrainerCost(52) == nil, "unknown until a trainer window shows it")

-- Estimates: vendor sell price times the factor, a floor for an item that
-- sells for nothing, none for an item the data does not know, and a real
-- price always wins.
local est = {
    recipes = {
        [60] = { makes = 3000, made = { 1, 1 }, skills = { 1, 10, 15, 20 }, reagents = { { 301, 2 } }, learn = "start" },
        [61] = { makes = 3001, made = { 1, 1 }, skills = { 1, 10, 15, 20 }, reagents = { { 302, 1 } }, learn = "start" },
        [62] = { makes = 3002, made = { 1, 1 }, skills = { 1, 10, 15, 20 }, reagents = { { 303, 1 } }, learn = "start" },
    },
    items = {
        [300] = { sell = 0 }, [301] = { sell = 10 }, [302] = { buy = 20, vendor = true, sell = 5 },
        [303] = { unknown = true }, [3000] = { sell = 100 }, [3001] = { sell = 100 }, [3002] = { sell = 100 },
    },
}
local estimated
local estBook = { prices = {}, trainers = {}, merchants = {} }
ctx = Prices:Context({ book = estBook, data = est })
value, source, _, estimated = ctx:BuyCost(300)
assert(value == Prices.estimateFloor and source == "estimate" and estimated, "an item selling for nothing has the floor")
assert(ctx:BuyCost(303) == nil, "an unknown item gets no estimate")
assert(ctx:BuyCost(999) == nil, "nor does one the data does not have")
value, source, _, estimated = ctx:BuyCost(3000)
assert(value == 80 and source == "craft" and estimated, "made from estimated parts (80) beats its own estimate (400), and is an estimate too")
value, source, _, estimated = ctx:BuyCost(3001)
assert(value == 20 and source == "craft" and not estimated, "made from vendor parts is a real price")
value, source = ctx:BuyCost(3002)
assert(value == 400 and source == "estimate", "parts with no price at all: the product's own estimate")
local total, _, partsEstimated = ctx:ReagentCost(est.recipes[60])
assert(total == 80 and partsEstimated, "a recipe's reagent cost says when it rests on an estimate")
ctx = Prices:Context({ book = estBook, data = est, options = { estimateFactor = 2 } })
assert(ctx:BuyCost(301) == 20, "the factor is an option")
Prices:SetFact(estBook, 3000, "auctionBuy", 500)
ctx = Prices:Context({ book = estBook, data = est, options = { get = { [3000] = "buy" } } })
value, source, _, estimated = ctx:BuyCost(3000)
assert(value == 500 and source == "ah" and not estimated, "a real price beats a cheaper estimate")
ctx = Prices:Context({ book = estBook, data = est })
value, source, _, estimated = ctx:BuyCost(3000)
assert(value == 80 and source == "craft" and estimated, "but an item a usable recipe makes is made, by default")

-- How each item is had: made by default when a usable recipe makes it,
-- bought otherwise; "buy" never makes it, even when making is cheaper; the
-- gather modes as they always were. Making it is kept even when buying is
-- cheaper, and each part follows its own mode.
local modes = {
    recipes = {
        [70] = { makes = 4000, made = { 1, 1 }, skills = { 1, 10, 15, 20 }, reagents = { { 4001, 2 } }, learn = "start" },
        [71] = { makes = 4001, made = { 1, 1 }, skills = { 1, 10, 15, 20 }, reagents = { { 402, 3 } }, learn = "trainer" },
    },
    items = { [402] = { buy = 10, vendor = true }, [4000] = { buy = 20, vendor = true }, [4001] = { buy = 5, vendor = true } },
}
local modeBook = { prices = {}, trainers = {}, merchants = {} }
ctx = Prices:Context({ book = modeBook, data = modes })
assert(ctx:GetMode(4000) == "make" and ctx:GetMode(4001) == "make" and ctx:GetMode(402) == "buy")
value, source, npc = ctx:BuyCost(4000)
assert(value == 60 and source == "craft" and npc.spell == 70,
    "made from parts that are made too (2 x 3 x 10c), though a vendor sells it for 20c: " .. tostring(value))
local both = ctx:MakeOrBuy(4000)
assert(both.make == 60 and both.spell == 70 and both.buy == 20 and both.buyVia == "vendor", "making and buying, side by side")
ctx = Prices:Context({ book = modeBook, data = modes, options = { get = { [4001] = "buy" } } })
assert(ctx:BuyCost(4000) == 10, "a part to buy is bought (5c), the item itself still made")
ctx = Prices:Context({ book = modeBook, data = modes, options = { get = { [4000] = "buy" } } })
value, source = ctx:BuyCost(4000)
assert(value == 20 and source == "vendor", "an item to buy is never made")
assert(ctx:Describe(4000).mode == "buy" and ctx:Describe(4000).makeable, "and says it could be")
ctx = Prices:Context({ book = modeBook, data = modes, options = { gather = { [4001] = "zero" } } })
assert(ctx:GetMode(4001) == "gather-free" and ctx:BuyCost(4000) == 0, "a part gathered free")
ctx = Prices:Context({ book = modeBook, data = modes, canCraft = function(spell) return spell == 70 end })
assert(ctx:GetMode(4001) == "buy" and ctx:BuyCost(4000) == 10, "a recipe out of reach does not make its item")
ctx = Prices:Context({ book = estBook, data = est, options = { auction = "sell" } })
assert(ctx:BuyCost(301) == nil and ctx:BuyCost(3000) == nil, "no buying at the auction house, no estimates")
ctx = Prices:Context({ book = estBook, data = est })
local described = ctx:Describe(301)
assert(described.estimated and described.buySource == "estimate" and described.buy == 40 and not described.missing)
described = ctx:Describe(302)
assert(not described.estimated and described.buySource == "vendor")

-- Shipped recordings (Data/ProfessionRecorded.lua): read beside the book, the
-- book's row winning for the same NPC and key.
ns.professionRecorded = {
    trainers = { [7000] = { [70] = { cost = 900, skill = 40, level = 5, spellID = 70, seen = 1 },
                            [71] = { cost = 300, skill = 20, seen = 1 },
                            ["name:leatherworking (journeyman)"] = { name = "Leatherworking", cost = 500, skill = 50, level = 10, seen = 1 } } },
    merchants = { [7100] = { [301] = { price = 12, count = 1, seen = 1 } } },
}
local recBook = { prices = {}, trainers = {}, merchants = {} }
assert(Prices:TrainerCost(recBook, 70) == 900 and Prices:TrainerSkill(recBook, 70) == 40, "the shipped trainer is read")
assert(Prices:MerchantOffers(recBook, 301) == 12, "and the shipped merchant")
assert(select(2, Prices:Fact(recBook, est, 301, "vendorBuy")) == "merchant")
recBook.trainers[7000] = { [70] = { cost = 800, skill = 35, seen = 2 } }
local fee, feeNPC = Prices:TrainerCost(recBook, 70)
assert(fee == 800 and feeNPC == 7000 and Prices:TrainerSkill(recBook, 70) == 35, "this session's window wins for the same trainer")
assert(Prices:TrainerCost(recBook, 71) == 300, "the rows it did not show still come from the recording")
recBook.trainers[7001] = { [70] = { cost = 700, skill = 45, seen = 2 } }
assert(Prices:TrainerCost(recBook, 70) == 700 and Prices:TrainerSkill(recBook, 70) == 35, "another trainer: the cheapest fee, the lowest skill")
local tierRow = { name = "Journeyman", cap = 150, level = 10, minSkill = 50, spells = { Leatherworking = 99999 } }
assert(Prices:TierCost(recBook, "Leatherworking", tierRow) == 500, "a tier's fee from the service named after the profession")
assert(Prices:TierCost(recBook, "Tailoring", tierRow) == nil)
ns.professionRecorded = nil
assert(Prices:TrainerCost({}, 71) == nil)

-- Auctionator, through the injected auction source: after the player's word
-- and a merchant window, before the shipped data and any estimate, for both
-- auction facts; the cut is taken off its sell price like any other.
local seenPrices = { [301] = { 200, 3 }, [302] = { 70 }, [3000] = { 1000, 1 } }
Prices:SetAuctionSource(function(itemID)
    local row = seenPrices[itemID]
    if row then return row[1], row[2] end
    if itemID == 666 then error("boom") end
end)
local aBook = { prices = {}, trainers = {}, merchants = {} }
ctx = Prices:Context({ book = aBook, data = est })
value, source, _, estimated = ctx:BuyCost(301)
assert(value == 200 and source == "ah" and not estimated, "Auctionator's price is a real price, never an estimate")
local fact, factSource, _, _, days = Prices:Fact(aBook, est, 301, "auctionBuy")
assert(fact == 200 and factSource == "auctionator" and days == 3)
value, source = ctx:SellValue(3000)
assert(value == 950 and source == "ah", "its listing price, less the 5% cut")
assert(Prices:AuctionPrice(666) == nil, "a failing source is no answer")
assert(ctx:BuyCost(302) == 20 and select(2, ctx:BuyCost(302)) == "vendor", "a cheaper vendor still wins on price")
local rowA = ctx:Describe(301)
assert(rowA.buySource == "auctionator" and rowA.buyDays == 3 and rowA.days == 3 and rowA.auctionator)
assert(rowA.facts.auctionBuy.source == "auctionator" and rowA.facts.auctionBuy.age == 3 * 86400)
rowA = ctx:Describe(3000)
assert(rowA.sellSource == "auctionator" and rowA.sellDays == 1)
Prices:SetFact(aBook, 301, "auctionBuy", 150)
ctx = Prices:Context({ book = aBook, data = est })
value, source = ctx:BuyCost(301)
assert(value == 150 and select(2, Prices:Fact(aBook, est, 301, "auctionBuy")) == "player", "the player's word beats Auctionator")
Prices:SetFact(aBook, 301, "auctionBuy", nil)
ctx = Prices:Context({ book = aBook, data = est, options = { useAuctionator = false } })
value, source, _, estimated = ctx:BuyCost(301)
assert(value == 40 and estimated, "turned off, Auctionator is not asked: back to the estimate")
assert(not ctx:UsesAuctionator())
ctx = Prices:Context({ book = aBook, data = est, options = { auction = "sell" } })
assert(ctx:BuyCost(301) == nil and ctx:SellValue(3000) == 950, "the auction option still rules: selling only")
ctx = Prices:Context({ book = aBook, data = est, options = { auction = "buy" } })
assert(ctx:BuyCost(301) == 200 and ctx:SellValue(3000) == 100, "buying only")
ctx = Prices:Context({ book = aBook, data = est })
assert(ctx:UsesAuctionator() and Prices:AuctionSourceAvailable())
Prices:SetAuctionSource(function() return nil end, function() return false end)
assert(not Prices:AuctionSourceAvailable(), "the source says when Auctionator is not installed")
Prices:SetAuctionSource(nil)
ctx = Prices:Context({ book = aBook, data = est })
value, source, _, estimated = ctx:BuyCost(301)
assert(value == 40 and estimated and not ctx:UsesAuctionator(), "without Auctionator: estimates as before")

-- One row of the Prices tab.
ctx = Prices:Context({ book = book, data = data })
local row = ctx:Describe(100, 1500)
assert(row.buy == 8 and row.buySource == "vendor" and row.sell == 3 and not row.missing)
assert(row.facts.vendorBuy.source == "merchant" and row.facts.vendorBuy.age == 500)
row = Prices:Context({ book = book, data = data }):Describe(999)
assert(row.missing, "an item with no price is flagged")

return true
