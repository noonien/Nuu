local _, ns = ...

-- The price store behind the profession planner: what an item costs the
-- player and what it earns them, on their realm.
--
-- Each item has up to four facts, kept account-wide in the price book
-- (`NuuProfessionsDB.professions`):
--
--   vendorBuy    what a vendor charges for one   (recipe data, merchant windows)
--   vendorSell   what a vendor pays for one      (recipe data, the item's sell price)
--   auctionBuy   what one costs at the auction house     (the player's word, or Auctionator)
--   auctionSell  what one lists for at the auction house (the player's word, or
--                Auctionator; the 5% cut is taken off here, never by the player)
--
-- A value the player typed always beats one the addon read. Then a merchant
-- window, then Auctionator's price (both auction facts), then the shipped
-- data, then an estimate. Nothing here reads the auction house itself, and
-- nothing buys, posts or trains: the book only holds what the player said and
-- what the client showed them. Auctionator's prices are asked through an
-- injected source (`Prices:SetAuctionSource`, wired by API/Client.lua), so
-- this module stays pure.
--
-- The book's shape:
--
--   book.prices[itemID]    = { vendorBuy = fact, vendorSell = fact, auctionBuy = fact,
--                              auctionSell = fact, depth = n }
--                            fact = { value = copper, source = "player"|"item"|..., seen = time }
--   book.merchants[npcID][itemID] = { price = copper, count = n, currency = { [currencyID] = n }, seen = time }
--   book.trainers[npcID][spellID] = { cost = copper, skill = n, level = n, seen = time }
--   book.revision          bumped on every change, so a plan can tell it is stale
--
-- Merchant and trainer rows are written by API/Client.lua when the player
-- opens those windows; this module only reads them. The beta client never
-- restores SavedVariables, so the book only holds this session. What trainers
-- and merchants showed in earlier sessions ships as addon data
-- (Data/ProfessionRecorded.lua, `ns.professionRecorded`, same row shapes);
-- every read here merges the two, the book's row winning over the shipped
-- one for the same NPC and key.
--
-- A material with no price at all, when the player buys at the auction
-- house, gets an estimated auction price: its vendor sell price times
-- `estimateFactor` (a floor for items that sell for nothing). An estimate is
-- flagged wherever it is used, and any real price beats it.
--
-- The effective prices depend on the player's sourcing options, so they are
-- asked of a context (`Prices:Context`) built once per plan.
local Prices = {}

Prices.facts = { "vendorBuy", "vendorSell", "auctionBuy", "auctionSell" }
local isFact = { vendorBuy = true, vendorSell = true, auctionBuy = true, auctionSell = true }
Prices.auctionCut = 0.05
-- Where one source beats another at the same price: a vendor is one stop, the
-- player's own gathering is theirs to do anyway, then the auction house, and
-- crafting the item from its parts last.
local sourceSkill = { vendor = 1, gather = 2, ah = 3, craft = 4, carried = 5, estimate = 6 }
-- An unpriced material's estimated auction price: its vendor sell price
-- times this, and at least the floor (copper) for an item that sells for
-- nothing. The planner's `estimateFactor` option overrides the factor.
Prices.estimateFactor = 4
Prices.estimateFloor = 5

-- Money ---------------------------------------------------------------------

-- Money as the player reads it: the two largest coins, rounded to the
-- second, with a zero coin left out. 12005 -> "1g 20s", 20013 -> "2g",
-- 150 -> "1s 50c", 0 -> "0c"; a negative amount keeps its sign. `exact`
-- keeps every coin (12005 -> "1g 20s 5c"), for a field the player edits,
-- which must read back as what they typed. ASCII only: the Forever client
-- does not draw the coin glyphs reliably. The kit's plain form
-- (Kit.FormatMoney with `plain` false), whose rules are these; the kit's
-- coloured coins are the UI's to ask for.
function Prices:FormatMoney(copper, exact)
    return ns.Kit.FormatMoney(copper, exact, false)
end

-- "1g 20s 5c", "1g20s", "20s", "5c" or a bare number of copper -> copper. nil
-- for anything else, so a typo is refused rather than read as zero. The kit's
-- (Kit.ParseMoney), which also reads the coloured coins it draws.
function Prices:ParseMoney(text)
    return ns.Kit.ParseMoney(text)
end

-- The auction source --------------------------------------------------------

-- `fn(itemID) -> copper, ageDays` answers an item's auction price (per item)
-- and how many days ago it was seen, or nil. `available()`, when given, says
-- whether the source is there at all (Auctionator installed with its API),
-- which the planner uses to suggest visiting the auction house. nil removes
-- the source.
function Prices:SetAuctionSource(fn, available)
    self.auctionSource = type(fn) == "function" and fn or nil
    self.auctionAvailable = type(available) == "function" and available or nil
end

function Prices:AuctionSourceAvailable()
    if not self.auctionSource then return false end
    if not self.auctionAvailable then return true end
    local ok, present = pcall(self.auctionAvailable)
    return ok and present == true
end

-- The source's price for one item and its age in days, or nil. A failing or
-- odd answer is no answer.
function Prices:AuctionPrice(itemID)
    local source = self.auctionSource
    if not source then return nil end
    local ok, price, age = pcall(source, itemID)
    if not ok or type(price) ~= "number" or price <= 0 then return nil end
    return price, type(age) == "number" and age or nil
end

-- The book ------------------------------------------------------------------

function Prices:Book()
    return ns.db and ns.db.professions
end

local function entry(book, itemID, create)
    book.prices = book.prices or {}
    local row = book.prices[itemID]
    if not row and create then
        row = {}
        book.prices[itemID] = row
    end
    return row
end

local function touch(book)
    book.revision = (book.revision or 0) + 1
end

-- Records one fact. `value` nil clears it; `source` defaults to "player", which
-- is what the Prices tab writes and what always wins.
function Prices:SetFact(book, itemID, fact, value, source, now)
    if not isFact[fact] or type(itemID) ~= "number" then return false end
    local row = entry(book, itemID, value ~= nil)
    if value == nil then
        if row then row[fact] = nil end
    else
        value = tonumber(value)
        if not value or value < 0 then return false end
        row[fact] = { value = math.floor(value + 0.5), source = source or "player", seen = now }
    end
    touch(book)
    return true
end

-- How many the market takes at the auction price; beyond it, extra copies
-- fall back to the vendor. nil lifts the cap.
function Prices:SetDepth(book, itemID, count)
    count = tonumber(count)
    local row = entry(book, itemID, count ~= nil)
    if row then row.depth = count and math.max(math.floor(count), 0) or nil end
    touch(book)
end

function Prices:Revision(book)
    return book and book.revision or 0
end

-- Recorded windows --------------------------------------------------------

-- The shipped recording (Data/ProfessionRecorded.lua), or nil.
function Prices:Recorded()
    local recorded = ns.professionRecorded
    return type(recorded) == "table" and recorded or nil
end

-- Every row of one kind ("trainers" or "merchants") for one key (a spell or
-- trainer key, an item) as { [npcID] = row }: the shipped recording, then
-- this session's book over it. `match(key, row)`, when given, is asked of
-- every row instead of looking the key up (a trainer row found by its
-- spellID field).
local function rowsFor(book, kind, key, match)
    local found = {}
    local recorded = Prices:Recorded()
    local sources = { recorded and recorded[kind] or false, book and book[kind] or false }
    for _, source in ipairs(sources) do
        if type(source) == "table" then
            for npcID, rows in pairs(source) do
                if type(rows) == "table" then
                    if match then
                        for rowKey, row in pairs(rows) do
                            if type(row) == "table" and match(rowKey, row) then found[npcID] = row end
                        end
                    else
                        local row = rows[key]
                        if type(row) == "table" then found[npcID] = row end
                    end
                end
            end
        end
    end
    return found
end
Prices.RowsFor = rowsFor

-- The cheapest merchant row for an item: gold price per item, the NPC and
-- when it was seen. A row that also asks for a currency is not a gold sale
-- and is left out: the planner does not price currencies.
function Prices:MerchantOffers(book, itemID)
    local gold, goldNPC, seen
    for npcID, row in pairs(rowsFor(book, "merchants", itemID)) do
        local currency = type(row) == "table" and type(row.currency) == "table" and next(row.currency) ~= nil
        if type(row) == "table" and not currency and tonumber(row.price) and row.price > 0 then
            local each = row.price / math.max(tonumber(row.count) or 1, 1)
            if not gold or each < gold or (each == gold and npcID < goldNPC) then
                gold, goldNPC, seen = each, npcID, row.seen
            end
        end
    end
    return gold, goldNPC, seen
end

-- The recorded trainer fee for a spell, the cheapest trainer and the level it
-- asks for. nil when no trainer window has shown it, this session or in the
-- shipped recording.
function Prices:TrainerCost(book, spellID)
    local cost, npc, level
    for npcID, row in pairs(rowsFor(book, "trainers", spellID)) do
        if tonumber(row.cost) then
            if not cost or row.cost < cost or (row.cost == cost and npcID < npc) then cost, npc, level = row.cost, npcID, row.level end
        end
    end
    return cost, npc, level
end

-- The recorded fee for a trainer tier (Journeyman, Expert) of a profession:
-- the tier's spell when a window showed it, else the service named after the
-- profession whose key names the tier ("name:leatherworking (journeyman)")
-- or whose skill and level gates are the tier's.
function Prices:TierCost(book, profession, tier)
    local spell = tier.spells and tier.spells[profession]
    local cost, npc = nil, nil
    if spell then cost, npc = self:TrainerCost(book, spell) end
    if cost then return cost, npc end
    local name = tostring(profession):lower()
    local suffix = " (" .. tostring(tier.name):lower() .. ")"
    local rows = rowsFor(book, "trainers", nil, function(key, row)
        if type(row.name) ~= "string" or row.name:lower() ~= name or not tonumber(row.cost) then return false end
        if type(key) == "string" and key:sub(-#suffix) == suffix then return true end
        if row.tier == tier.name then return true end
        return tier.minSkill ~= nil and row.skill == tier.minSkill and row.level == tier.level
    end)
    for npcID, row in pairs(rows) do
        if not cost or row.cost < cost or (row.cost == cost and npcID < npc) then cost, npc = row.cost, npcID end
    end
    return cost, npc
end

-- The skill level a trainer asked for before teaching this recipe, the lowest
-- any recorded trainer asked. Forever's client data has no learn skill for a
-- trainer recipe (the extraction falls back to its yellow skill), so a trainer
-- window is the only word on it. A service the window showed as unavailable
-- (the player's skill was too low) still gives its skill.
function Prices:TrainerSkill(book, spellID)
    local skill
    local rows = rowsFor(book, "trainers", nil, function(key, row)
        return (key == spellID or row.spellID == spellID) and tonumber(row.skill) ~= nil
    end)
    for _, row in pairs(rows) do
        if not skill or row.skill < skill then skill = row.skill end
    end
    return skill
end

-- One fact as the planner sees it: the value, where it came from, when, (for
-- a vendor price) which NPC, and (for Auctionator's) its age in days. The
-- player's own value wins; then what a merchant window showed; then
-- Auctionator's price for either auction fact, unless `noAuctionator`; then
-- what the client told us of the item; then the shipped recipe data.
function Prices:Fact(book, data, itemID, fact, noAuctionator)
    local row = book and book.prices and book.prices[itemID]
    local stored = row and row[fact]
    if stored and stored.source == "player" then return stored.value, "player", stored.seen end
    if fact == "vendorBuy" then
        local gold, npc, seen = self:MerchantOffers(book, itemID)
        if gold then return gold, "merchant", seen, npc end
    end
    if (fact == "auctionBuy" or fact == "auctionSell") and not noAuctionator then
        local price, age = self:AuctionPrice(itemID)
        if price then return price, "auctionator", nil, nil, age end
    end
    if stored then return stored.value, stored.source, stored.seen end
    local item = data and data.items and data.items[itemID]
    if item then
        if fact == "vendorBuy" and item.vendor and tonumber(item.buy) and item.buy > 0 then
            return item.buy / math.max(tonumber(item.buyCount) or 1, 1), "data"
        end
        if fact == "vendorSell" and tonumber(item.sell) and item.sell > 0 then return item.sell, "data" end
    end
    return nil
end

-- The context ---------------------------------------------------------------

local Context = {}
Context.__index = Context

-- args:
--   book     the price book (default ns.db.professions)
--   data     one profession's recipe data (Data/Professions/*.lua)
--   options  { auction = "both"|"buy"|"sell"|"none", gather = { [itemID] = "opportunity"|"zero" },
--              get = { [itemID] = "buy" } (never made; see Context:GetMode),
--              keep = { [itemID] = true } (sold at the vendor price only),
--              nosell = { [itemID] = true } (never counted as sold, in either sellOutput),
--              estimateFactor = n (default Prices.estimateFactor),
--              sellOutput = "all" (the default: whatever is made is worth its best sale) or
--              "chosen" (worth nothing unless in sell or keep: plan on cost),
--              useAuctionator = false to leave Auctionator's prices out,
--              carried = function(itemID) -> count in the bags: plan with only
--              what is carried and what vendors sell (see Context:BuyCost) }
--   canCraft function(spellID) -> true when the player may make that recipe to
--            supply an intermediate; default: trainer and starting recipes
function Prices:Context(args)
    args = args or {}
    local options = args.options or {}
    local auction = options.auction or "both"
    local carried = type(options.carried) == "function" and options.carried or nil
    -- With only what is carried, nothing is bought at the auction house.
    if carried then auction = (auction == "both" or auction == "sell") and "sell" or "none" end
    local ctx = setmetatable({
        book = args.book or self:Book() or {},
        data = args.data or {},
        options = options,
        buyAH = auction == "both" or auction == "buy",
        sellAH = auction == "both" or auction == "sell",
        canCraft = args.canCraft,
        carried = carried,
        estimateFactor = tonumber(options.estimateFactor) or Prices.estimateFactor,
        noAuctionator = options.useAuctionator == false,
        buyCache = {},
        sellCache = {},
        visiting = {},
    }, Context)
    return ctx
end

function Context:Item(itemID)
    return self.data.items and self.data.items[itemID]
end

-- Prices:Fact with this context's book, data and Auctionator choice.
function Context:Fact(itemID, fact)
    return Prices:Fact(self.book, self.data, itemID, fact, self.noAuctionator)
end

-- True when Auctionator is there and this context uses it.
function Context:UsesAuctionator()
    return not self.noAuctionator and Prices:AuctionSourceAvailable()
end

-- What one copy is worth when sold: the better of the vendor and the
-- auction house net of its cut. Soulbound output, and output the player sells
-- at the vendor only (`keep`), is worth the vendor price or nothing. Output
-- the player never sells (`nosell`) is worth nothing, whatever sellOutput says.
function Context:SellValue(itemID)
    local cached = self.sellCache[itemID]
    if cached then return cached[1], cached[2] end
    local options = self.options
    local vendorOnly = options.keep and options.keep[itemID]
    -- Planning on cost: only what the player chose to sell is worth anything.
    local unsold = options.nosell and options.nosell[itemID]
    if not unsold and options.sellOutput == "chosen" then
        unsold = not ((options.sell and options.sell[itemID]) or vendorOnly)
    end
    if unsold then
        self.sellCache[itemID] = { 0, nil }
        return 0, nil
    end
    local vendor = Prices:Fact(self.book, self.data, itemID, "vendorSell") or 0
    local value, source = vendor, vendor > 0 and "vendor" or nil
    local item = self:Item(itemID)
    local bound = item and item.bind == "bop"
    if not bound and not vendorOnly and self.sellAH then
        local listed = self:Fact(itemID, "auctionSell")
        if listed then
            local net = math.floor(listed * (1 - Prices.auctionCut))
            if net > value then value, source = net, "ah" end
        end
    end
    self.sellCache[itemID] = { value, source }
    return value, source
end

function Context:VendorSell(itemID)
    return Prices:Fact(self.book, self.data, itemID, "vendorSell") or 0
end

-- How many sell at the auction price before the rest go to a vendor.
function Context:Depth(itemID)
    local row = self.book.prices and self.book.prices[itemID]
    return row and row.depth
end

-- What `count` copies bring in all, the market depth applied: past the cap,
-- copies are worth the vendor price.
function Context:SellTotal(itemID, count)
    if not count or count <= 0 then return 0 end
    local value, source = self:SellValue(itemID)
    local depth = self:Depth(itemID)
    if source == "ah" and depth and count > depth then
        return depth * value + (count - depth) * self:VendorSell(itemID)
    end
    return count * value
end

-- Carried items are costed at what they would sell for: using them avoids a
-- purchase but gives up the sale.
function Context:BagValue(itemID)
    return (self:SellValue(itemID))
end

local function makers(ctx, itemID)
    if not ctx.makerIndex then
        ctx.makerIndex = {}
        for spellID, recipe in pairs(ctx.data.recipes or {}) do
            if recipe.makes then
                local list = ctx.makerIndex[recipe.makes] or {}
                table.insert(list, spellID)
                ctx.makerIndex[recipe.makes] = list
            end
        end
        for _, list in pairs(ctx.makerIndex) do table.sort(list) end
    end
    return ctx.makerIndex[itemID] or {}
end

local function averageMade(recipe)
    local made = recipe.made
    if type(made) ~= "table" then return 1 end
    local low, high = tonumber(made[1]) or 1, tonumber(made[2] or made[1]) or 1
    return math.max((low + high) / 2, 0.01)
end
Prices.AverageMade = averageMade

-- The cost of a recipe's reagents for one craft, nil and the first reagent
-- that cannot be had, and true as the third value when any reagent's price is
-- an estimate.
function Context:ReagentCost(recipe)
    local total, estimated = 0, false
    for _, reagent in ipairs(recipe.reagents or {}) do
        local each, _, _, guessed = self:BuyCost(reagent[1])
        if not each then return nil, reagent[1] end
        total = total + each * (reagent[2] or 1)
        if guessed then estimated = true end
    end
    return total, nil, estimated
end

-- The estimated auction price of an item nobody priced: its vendor sell price
-- times the factor, at least the floor. nil for an item the data does not
-- know (no row, or `unknown`), and when the player does not buy at the
-- auction house.
function Context:Estimate(itemID)
    if not self.buyAH then return nil end
    local item = self:Item(itemID)
    if type(item) ~= "table" or item.unknown then return nil end
    local sell = Prices:Fact(self.book, self.data, itemID, "vendorSell") or 0
    return math.max(math.floor(sell * self.estimateFactor + 0.5), Prices.estimateFloor)
end

-- The recipes that make an item which the player may use to make it (the
-- context's canCraft; by default trainer and starting recipes), by spell.
function Context:Makers(itemID)
    local list = {}
    for _, spellID in ipairs(makers(self, itemID)) do
        local recipe = self.data.recipes[spellID]
        local allowed
        if self.canCraft then allowed = self.canCraft(spellID) else allowed = recipe.learn == "start" or recipe.learn == "trainer" end
        if allowed then table.insert(list, spellID) end
    end
    return list
end

-- How the player gets an item, one of:
--   make           made from its parts, even when buying would be cheaper
--                  (each part as its own mode says); the default for an item
--                  a usable recipe makes
--   buy            bought (a vendor, or the auction house when the player
--                  buys there), never made; the default for any other item
--   gather-valued  gathered, costed at what it would sell for (options.gather
--                  "opportunity")
--   gather-free    gathered, and free (options.gather "zero")
-- A gathered item competes with the other sources, as it always has; the
-- player's buy is options.get (make needs no mark: it is the default).
function Context:GetMode(itemID)
    local gather = self.options.gather and self.options.gather[itemID]
    if gather == "zero" then return "gather-free" end
    if gather then return "gather-valued" end
    local chosen = self.options.get and self.options.get[itemID]
    if chosen == "buy" then return "buy" end
    if #self:Makers(itemID) > 0 then return "make" end
    return "buy"
end

-- The cheapest way to have one the item's mode allows: a vendor, the auction
-- house, making it from its parts, or gathering it (at what it would sell
-- for, or free, as the player chose). Returns the cost per item, the source
-- ("vendor", "ah", "craft", "gather", "carried", "estimate"), a detail table ({ npc = }
-- for a vendor, { spell = } for a craft), and true when the cost is an
-- estimate. nil when there is no allowed source: the item is unobtainable and
-- recipes needing it are skipped.
--
-- An item to make is only made, from the cheapest of its recipes; when none
-- can be made (a part has no source) it is bought after all rather than
-- holding the route up. An item to buy is never made.
--
-- Estimates only fill a gap: any real price wins over every estimate, and
-- only when there is none do the estimate and making it from estimated parts
-- compete.
--
-- With only what is carried (the context's `carried`), an item is made or
-- bought from a vendor as above, never gathered; one that cannot be had
-- that way comes from the bags ("carried", at its bag value) while there
-- are any, and has no source otherwise. How many the bags hold is the
-- planner's to count (Planner:Plan).
function Context:BuyCost(itemID)
    local cached = self.buyCache[itemID]
    if cached then return cached[1], cached[2], cached[3], cached[4] end
    if self.visiting[itemID] then return nil end
    self.visiting[itemID] = true
    local best, source, detail
    local guess, guessSource, guessDetail
    local function offer(cost, kind, extra, estimated)
        if cost == nil then return end
        if estimated then
            if not guess or cost < guess - 1e-9 or (math.abs(cost - guess) <= 1e-9 and sourceSkill[kind] < sourceSkill[guessSource]) then
                guess, guessSource, guessDetail = cost, kind, extra
            end
        elseif not best or cost < best - 1e-9 or (math.abs(cost - best) <= 1e-9 and sourceSkill[kind] < sourceSkill[source]) then
            best, source, detail = cost, kind, extra
        end
    end
    local mode = self:GetMode(itemID)
    if mode ~= "buy" then
        for _, spellID in ipairs(self:Makers(itemID)) do
            local recipe = self.data.recipes[spellID]
            local parts, _, estimated = self:ReagentCost(recipe)
            if parts then offer(parts / averageMade(recipe), "craft", { spell = spellID }, estimated) end
        end
    end
    -- Made: nothing else is asked.
    local made = mode == "make" and (best or guess) ~= nil
    if not made then
        local vendor, _, _, npc = Prices:Fact(self.book, self.data, itemID, "vendorBuy")
        offer(vendor, "vendor", { npc = npc })
        if self.buyAH then offer((self:Fact(itemID, "auctionBuy")), "ah", {}) end
        if self.carried then
            if not best and (self.carried(itemID) or 0) > 0 then offer(self:BagValue(itemID), "carried", {}) end
        elseif mode == "gather-free" then
            offer(0, "gather", {})
        elseif mode == "gather-valued" then
            -- The sale given up: the market's, whatever the player counts
            -- their own output as.
            offer(self:MarketValue(itemID), "gather", {})
        end
    end
    local estimated
    if not best then
        if not made then offer(self:Estimate(itemID), "estimate", {}, true) end
        best, source, detail = guess, guessSource, guessDetail
        estimated = guess ~= nil or nil
    end
    self.visiting[itemID] = nil
    self.buyCache[itemID] = { best, source, detail, estimated }
    return best, source, detail, estimated
end

-- What one copy would fetch on the market, whatever the player sells their
-- output as: the better of the vendor and (when they sell there) the auction
-- house net of its cut. What a gathered part is worth unmade.
function Context:MarketValue(itemID)
    local value = Prices:Fact(self.book, self.data, itemID, "vendorSell") or 0
    local item = self:Item(itemID)
    if self.sellAH and not (item and item.bind == "bop") then
        local listed = self:Fact(itemID, "auctionSell")
        if listed then value = math.max(value, math.floor(listed * (1 - Prices.auctionCut))) end
    end
    return value
end

-- What making an item and buying it would each cost, whatever its mode says,
-- for the player to compare: the cheapest usable recipe's parts per item (and
-- that recipe, and whether the parts rest on a guess), and the cheaper of a
-- vendor and the auction house (and which, "vendor" or "ah"). Either is nil
-- when there is no such way.
--
-- `worth` is what that recipe's parts are worth per item with the ones the
-- player gathers free (`free`, their item IDs) valued at what they would
-- sell for: free to the plan, but a sale given up all the same.
function Context:MakeOrBuy(itemID)
    local make, spell, guessed, recipeOf
    for _, spellID in ipairs(self:Makers(itemID)) do
        local recipe = self.data.recipes[spellID]
        local parts, _, estimated = self:ReagentCost(recipe)
        if parts then
            local each = parts / averageMade(recipe)
            if not make or each < make then make, spell, guessed, recipeOf = each, spellID, estimated or nil, recipe end
        end
    end
    local worth, free = make, nil
    if recipeOf then
        local total = 0
        for _, reagent in ipairs(recipeOf.reagents or {}) do
            local each
            if self:GetMode(reagent[1]) == "gather-free" then
                each = self:MarketValue(reagent[1])
                free = free or {}
                table.insert(free, reagent[1])
            else
                each = self:BuyCost(reagent[1]) or 0
            end
            total = total + each * (reagent[2] or 1)
        end
        worth = total / averageMade(recipeOf)
    end
    local buy, via = Prices:Fact(self.book, self.data, itemID, "vendorBuy"), "vendor"
    if not buy then via = nil end
    local listed = self.buyAH and self:Fact(itemID, "auctionBuy") or nil
    if listed and (not buy or listed < buy) then buy, via = listed, "ah" end
    return { make = make, spell = spell, makeEstimated = guessed, worth = worth, free = free, buy = buy, buyVia = via }
end

-- A pattern's price in gold at a vendor (merchant window, or vendor-sold in
-- the data), and the NPC when known.
function Context:VendorPattern(itemID)
    local gold, npc = Prices:MerchantOffers(self.book, itemID)
    if gold then return gold, npc end
    local item = self:Item(itemID)
    if item and item.vendor and tonumber(item.buy) and item.buy > 0 then return item.buy, nil end
    local row = self.book.prices and self.book.prices[itemID]
    if row and row.vendorBuy and row.vendorBuy.source == "player" then return row.vendorBuy.value, nil end
    return nil
end

-- What a pattern costs at the auction house, from the player's price. nil
-- when they have not given one, or do not use the auction house to buy.
function Context:AuctionPattern(itemID)
    if not self.buyAH then return nil end
    return (self:Fact(itemID, "auctionBuy"))
end

function Context:TrainerCost(spellID)
    return Prices:TrainerCost(self.book, spellID)
end

-- One row of the Prices tab: every fact with its source and age, the
-- effective buy and sell values with where they come from, whether the buy
-- price is an estimate (`estimated`, buySource "estimate", or "craft" from
-- estimated parts), whether an auction fact is Auctionator's (`auctionator`;
-- a buy or sell value taken from it has buySource or sellSource
-- "auctionator" and its age in `buyDays`/`sellDays`, `days` either; the
-- fact's own `source` and `days` say the same), and whether the item has no
-- price at all.
function Context:Describe(itemID, now)
    local facts = {}
    for _, fact in ipairs(Prices.facts) do
        local value, source, seen, npc, days = self:Fact(itemID, fact)
        if value then
            -- Ages in seconds; Auctionator's is whole days.
            local age = (seen and now) and math.max(now - seen, 0) or nil
            if days then age = days * 86400 end
            facts[fact] = { value = value, source = source, seen = seen, npc = npc, age = age, days = days }
        end
    end
    local buy, buySource, _, estimated = self:BuyCost(itemID)
    local sell, sellSource = self:SellValue(itemID)
    local item = self:Item(itemID)
    -- An auction price that is Auctionator's says so, with its age in days.
    local buyDays, sellDays
    if buySource == "ah" and facts.auctionBuy and facts.auctionBuy.source == "auctionator" then
        buySource, buyDays = "auctionator", facts.auctionBuy.days
    end
    if sellSource == "ah" and facts.auctionSell and facts.auctionSell.source == "auctionator" then
        sellSource, sellDays = "auctionator", facts.auctionSell.days
    end
    return {
        itemID = itemID, facts = facts,
        buy = buy, buySource = buySource, estimated = estimated, sell = sell, sellSource = sellSource,
        buyDays = buyDays, sellDays = sellDays, days = buyDays or sellDays,
        auctionator = ((facts.auctionBuy and facts.auctionBuy.source == "auctionator")
            or (facts.auctionSell and facts.auctionSell.source == "auctionator")) or nil,
        depth = self:Depth(itemID),
        keep = self.options.keep and self.options.keep[itemID] or nil,
        nosell = self.options.nosell and self.options.nosell[itemID] or nil,
        gather = self.options.gather and self.options.gather[itemID] or nil,
        mode = self:GetMode(itemID), makeable = #self:Makers(itemID) > 0 or nil,
        bound = item and item.bind == "bop" or nil,
        missing = buy == nil,
    }
end

ns:RegisterModule("Prices", Prices)
