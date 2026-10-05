local ns = NewNamespace()
local records = ns.records
Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
local Client = ns.modules.Client

-- The character's record, as Config:CharacterStore hands it out.
local character = {}
ns.modules.Config.characterStore = character
ns.db = {}

local function profRows(event)
    local rows = {}
    for _, record in ipairs(records) do
        if record.channel == "prof" and record.data.event == event then table.insert(rows, record.data) end
    end
    return rows
end

local heard = {}
Client:OnProfessionChange(function(kind, subject, data) table.insert(heard, { kind = kind, subject = subject, data = data }) end)

local function itemLink(id, name) return "|cffffffff|Hitem:" .. id .. "::::::::20:::::|h[" .. name .. "]|h|r" end

-- Links -------------------------------------------------------------------------

local kind, id, name = Client.ParseLink(itemLink(2304, "Light Armor Kit"))
assert(kind == "item" and id == 2304 and name == "Light Armor Kit")
kind, id = Client.ParseLink("|cffffd000|Henchant:7418|h[Enchant Bracer - Minor Health]|h|r")
assert(kind == "enchant" and id == 7418)
kind, id = Client.ParseLink("|cffffffff|Hcurrency:3402:0|h[Test Coin]|h|r")
assert(kind == "currency" and id == 3402)
assert(Client.ParseLink(nil) == nil and Client.ParseLink("plain text") == nil)

assert(Client.MatchLearnMessage("You have learned how to create a new item: %s.",
    "You have learned how to create a new item: Light Armor Kit.") == "Light Armor Kit")
assert(Client.MatchLearnMessage("You have learned how to create a new item: %s.", "You feel better.") == nil)

-- Classic trade skill window --------------------------------------------------------

local rows = {
    { "Armor Kits", "header", 0, true },
    { "Light Armor Kit", "optimal", 3, nil, nil, 1, item = 2304, made = { 1, 1 }, reagents = { { 2318, "Light Leather", 1 } } },
    { "Cured Light Hide", "easy", 0, nil, nil, 1, item = 4231, made = { 1, 1 }, reagents = { { 783, "Light Hide", 1 }, { 4289, "Salt", 1 } } },
    { "Boots", "header", 0, false },
}
local tradeLine = "Leatherworking"
GetTradeSkillLine = function() return tradeLine, 45, 75 end
GetNumTradeSkills = function() return #rows end
GetTradeSkillInfo = function(i) local r = rows[i]; return r[1], r[2], r[3], r[4], r[5], r[6] end
GetTradeSkillItemLink = function(i) return rows[i].item and itemLink(rows[i].item, rows[i][1]) end
GetTradeSkillNumMade = function(i) return rows[i].made[1], rows[i].made[2] end
GetTradeSkillNumReagents = function(i) return #rows[i].reagents end
GetTradeSkillReagentInfo = function(i, r) local g = rows[i].reagents[r]; return g[2], "icon", g[3], 0 end
GetTradeSkillReagentItemLink = function(i, r) local g = rows[i].reagents[r]; return itemLink(g[1], g[2]) end

local snapshot = Client:ScanTradeSkill("tradeskill")
assert(snapshot and snapshot.profession == "Leatherworking" and snapshot.skill == 45 and snapshot.maxSkill == 75)
assert(snapshot.api == "tradeskill" and snapshot.partial == true, "a collapsed header marks the snapshot partial")
assert(#snapshot.order == 2, "headers are not recipes")
local kit = snapshot.recipes["item:2304"]
assert(kit and kit.color == "orange" and kit.difficulty == "optimal" and kit.itemID == 2304 and kit.spellID == nil)
assert(kit.made[1] == 1 and kit.made[2] == 1 and kit.available == 3 and kit.skillUps == 1)
assert(kit.reagents[1].itemID == 2318 and kit.reagents[1].count == 1 and kit.reagents[1].name == "Light Leather")
assert(#snapshot.recipes["item:4231"].reagents == 2 and snapshot.recipes["item:4231"].color == "green")
assert(Client:GetTradeSkillSnapshot("leatherworking") == snapshot, "snapshots are found whatever the case")
assert(character.knownRecipes.Leatherworking["item:2304"] == true)
assert(Client:IsRecipeKnown("Leatherworking", "item:4231"))
assert(not Client:IsRecipeKnown("Leatherworking", "item:9999"))
assert(#heard == 1 and heard[1].kind == "tradeskill" and heard[1].subject == "Leatherworking")
assert(#profRows("window") == 1 and profRows("window")[1].learned == 2)

-- The window updates after every craft; an unchanged read says nothing.
Client:ScanTradeSkill("tradeskill")
assert(#heard == 1 and #profRows("window") == 1, "an unchanged window is not news")
-- Reopened, it reads the same, but the MAKE buttons drawn at the show look again.
Client.windowShown = true
Client:ScanTradeSkill("tradeskill")
assert(#heard == 2 and heard[2].kind == "window" and heard[2].subject == "tradeskill", "a reopened window redraws the buttons")
table.remove(heard)
Client:ScanTradeSkill("tradeskill")
assert(#heard == 1, "only the first read after a show")
rows[2][2] = "medium"
Client:ScanTradeSkill("tradeskill")
assert(#heard == 2 and Client:GetSnapshotRecipe("Leatherworking", "item:2304").color == "yellow", "a colour change is news")

-- The planner's colour check: live colour wins, a disagreement is logged once.
local live, agrees = Client:CompareRecipeColor("Leatherworking", "item:2304", "yellow")
assert(live == "yellow" and agrees == true)
live, agrees = Client:CompareRecipeColor("Leatherworking", "item:2304", "optimal")
assert(live == "yellow" and agrees == false)
Client:CompareRecipeColor("Leatherworking", "item:2304", "orange")
assert(#profRows("color") == 1, "the same disagreement is logged once")
assert(profRows("color")[1].expected == "orange" and profRows("color")[1].live == "yellow")
assert(Client:CompareRecipeColor("Leatherworking", "item:9999", "orange") == nil, "an unseen recipe cannot be compared")
assert(Client:CompareRecipeColor("Tailoring", "item:2304", "orange") == nil)
local lookup = Client:GetSnapshotRecipe("Leatherworking", "name:light armor kit")
assert(lookup and lookup.itemID == 2304, "recipes are found by name too")

-- A window with nothing open answers nothing.
tradeLine = "UNKNOWN"
assert(Client:ReadTradeSkillWindow("tradeskill") == nil)
tradeLine = "Leatherworking"

-- Another player's linked window is never taken for the player's own.
IsTradeSkillLinked = function() return true end
rows[3][2] = "trivial"
local heardBefore = #heard
Client:ScanTradeSkill("tradeskill")
assert(#heard == heardBefore and Client:GetSnapshotRecipe("Leatherworking", "item:4231").color == "green")
assert(#profRows("linked") == 1)
IsTradeSkillLinked = nil

-- A secret name hides the recipe rather than raising later.
issecretvalue = function(value) return value == "Cured Light Hide" end
local hidden = Client:ReadTradeSkillWindow("tradeskill")
assert(#hidden.order == 1 and hidden.order[1].name == "Light Armor Kit")
issecretvalue = nil

-- Classic Craft API (Enchanting) --------------------------------------------------

local crafts = {
    { "Enchanting", nil, "header", 0, true },
    { "Enchant Bracer - Minor Health", nil, "optimal", 2, nil, link = "|cffffd000|Henchant:7418|h[Enchant Bracer - Minor Health]|h|r",
        reagents = { { 10940, "Strange Dust", 1 } } },
    { "Runed Copper Rod", nil, "trivial", 0, nil, link = itemLink(6218, "Runed Copper Rod"),
        reagents = { { 6217, "Copper Rod", 1 }, { 10940, "Strange Dust", 1 }, { 10938, "Lesser Magic Essence", 1 } } },
}
GetCraftDisplaySkillLine = function() return "Enchanting", 20, 75 end
GetNumCrafts = function() return #crafts end
GetCraftInfo = function(i) local c = crafts[i]; return c[1], c[2], c[3], c[4], c[5] end
GetCraftItemLink = function(i) return crafts[i].link end
GetCraftNumReagents = function(i) return #crafts[i].reagents end
GetCraftReagentInfo = function(i, r) local g = crafts[i].reagents[r]; return g[2], "icon", g[3], 0 end
GetCraftReagentItemLink = function(i, r) local g = crafts[i].reagents[r]; return itemLink(g[1], g[2]) end

local enchanting = Client:ScanTradeSkill("craft")
assert(enchanting.api == "craft" and enchanting.profession == "Enchanting" and enchanting.skill == 20)
local bracer = enchanting.recipes[7418]
assert(bracer and bracer.spellID == 7418 and bracer.itemID == nil and bracer.color == "orange", "an enchant is keyed by its spell")
assert(bracer.made == nil, "no GetCraftNumMade: nothing invented")
assert(enchanting.recipes["item:6218"].color == "grey" and #enchanting.recipes["item:6218"].reagents == 3)
assert(character.knownRecipes.Enchanting[7418] == true and character.knownRecipes.Enchanting["item:6218"] == true)
assert(Client:GetTradeSkillSnapshot("Leatherworking").api == "tradeskill", "each profession keeps its own snapshot")

-- Modern C_TradeSkillUI -------------------------------------------------------------

GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillLine = nil, nil, nil
local modernRecipes = {
    [3753] = { name = "Handstitched Leather Belt", learned = true, relativeDifficulty = 0, numSkillUps = 1 },
    [9065] = { name = "Light Leather Bracers", learned = true, difficulty = "easy" },
    [3762] = { name = "Hillman's Leather Vest", learned = false, relativeDifficulty = 1 },
}
C_TradeSkillUI = {
    IsTradeSkillReady = function() return true end,
    GetBaseProfessionInfo = function() return { professionName = "Leatherworking", skillLevel = 0, maxSkillLevel = 0 } end,
    GetChildProfessionInfo = function() return { professionName = "Leatherworking", skillLevel = 60, maxSkillLevel = 75 } end,
    GetAllRecipeIDs = function() return { 3753, 9065, 3762 } end,
    GetRecipeInfo = function(recipeID) return modernRecipes[recipeID] end,
    GetRecipeItemLink = function(recipeID)
        if recipeID == 3753 then return itemLink(4237, "Handstitched Leather Belt") end
        return nil
    end,
    GetRecipeSchematic = function(recipeID)
        if recipeID ~= 3753 then return nil end
        return { quantityMin = 1, quantityMax = 1, outputItemID = 4237, reagentSlotSchematics = {
            { reagents = { { itemID = 2318 } }, quantityRequired = 6, required = true },
            { reagents = { { itemID = 2320 } }, quantityRequired = 2 },
            { reagents = { { itemID = 99999 } }, quantityRequired = 1, required = false },
        } }
    end,
    GetRecipeNumItemsProduced = function() return 1, 1 end,
    GetRecipeNumReagents = function(recipeID) return recipeID == 9065 and 1 or 0 end,
    GetRecipeReagentInfo = function() return "Light Leather", "icon", 6, 0 end,
    GetRecipeReagentItemLink = function() return itemLink(2318, "Light Leather") end,
}
local modern = Client:ScanTradeSkill("tradeskill")
assert(modern.api == "modern" and modern.profession == "Leatherworking" and modern.skill == 60 and modern.maxSkill == 75,
    "the child profession carries the skill")
local belt = modern.recipes[3753]
assert(belt.spellID == 3753 and belt.itemID == 4237 and belt.color == "orange")
assert(#belt.reagents == 2 and belt.reagents[1].count == 6 and belt.reagents[2].itemID == 2320, "optional reagents are left out")
assert(modern.recipes[9065].color == "green" and modern.recipes[9065].reagents[1].itemID == 2318, "the older reagent calls")
assert(modern.recipes[3762].known == false and modern.recipes[3762].color == "yellow")
assert(character.knownRecipes.Leatherworking[3753] == true and character.knownRecipes.Leatherworking["item:4237"] == true)
assert(character.knownRecipes.Leatherworking[3762] == nil, "a recipe the window lists unlearned is not saved as known")
assert(Client:GetSnapshotRecipe("Leatherworking", "item:4237") == belt, "a spell-keyed recipe is found by its product")
C_TradeSkillUI.IsTradeSkillReady = function() return false end
assert(Client:ReadTradeSkillWindow("tradeskill") == nil, "a window that is not ready is not read")
C_TradeSkillUI = nil

-- Events: reads follow the window, not every update --------------------------------

GetTradeSkillLine = function() return "Leatherworking", 46, 75 end
GetNumTradeSkills = function() return #rows end
GetTradeSkillInfo = function(i) local r = rows[i]; return r[1], r[2], r[3], r[4], r[5], r[6] end
Client:OnProfessionEvent("TRADE_SKILL_CLOSE")
local before = Client:GetTradeSkillSnapshot("Leatherworking")
Client:OnProfessionEvent("TRADE_SKILL_UPDATE")
assert(Client:GetTradeSkillSnapshot("Leatherworking") == before, "an update with no window open reads nothing")
Client:OnProfessionEvent("TRADE_SKILL_SHOW")
assert(Client:GetTradeSkillSnapshot("Leatherworking").skill == 46, "opening the window reads it (no C_Timer: at once)")

-- A settling timer holds a burst of updates to one read.
local timers = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
Client:OnProfessionEvent("TRADE_SKILL_UPDATE")
Client:OnProfessionEvent("TRADE_SKILL_UPDATE")
assert(#timers == 1)
timers[1]()
C_Timer = nil

-- Making from the planner ---------------------------------------------------------

local made = {}
DoTradeSkill = function(index, count) table.insert(made, { index, count }) end
local stopped = 0
StopTradeSkill = function() stopped = stopped + 1 end
local windowSaid
Client:OnProfessionChange(function(kind, subject) if kind == "window" then windowSaid = subject end end)

local found = Client:FindCraft("leatherworking", nil, 2304)
assert(found and found.api == "tradeskill" and found.index == 2 and found.available == 3, "found by product, any case")
local why, other = select(2, Client:FindCraft("Tailoring", nil, 2304))
assert(why == "closed" and other == "Leatherworking", "another profession's window is not this one's")
assert(select(2, Client:FindCraft("Leatherworking", nil, 99999)) == "missing")
assert(Client:Craft("Leatherworking", nil, 2304, 10) == 3, "as many as the materials allow")
assert(made[1][1] == 2 and made[1][2] == 3)
assert(select(2, Client:Craft("Leatherworking", nil, 4231, 2)) == "materials", "nothing to make it from")
assert(#made == 1)

-- A batch made to a skill stops when the window shows it.
Client:Craft("Leatherworking", nil, 2304, 2, 47)
assert(Client.craftUntil and Client.craftUntil.skill == 47)
Client:OnProfessionEvent("TRADE_SKILL_UPDATE")
assert(stopped == 0, "still short of the skill")
GetTradeSkillLine = function() return "Leatherworking", 47, 75 end
Client:OnProfessionEvent("TRADE_SKILL_UPDATE")
assert(stopped == 1 and Client.craftUntil == nil, "stopped at the skill")
GetTradeSkillLine = function() return "Leatherworking", 46, 75 end
Client:OnProfessionEvent("TRADE_SKILL_CLOSE")
assert(windowSaid == "closed")
assert(select(2, Client:FindCraft("Leatherworking", nil, 2304)) == "closed")
Client:OnProfessionEvent("TRADE_SKILL_SHOW")
assert(windowSaid == "tradeskill")
DoTradeSkill, StopTradeSkill = nil, nil

-- Trainer ---------------------------------------------------------------------------

local services = {
    { "Leatherworking", "Journeyman", "available", cost = 500, requires = { "Leatherworking", 50 }, level = 10 },
    { "Recipes", nil, "header" },
    { "Light Armor Kit", nil, "used", cost = 10, requires = { "Leatherworking", 1 }, level = 0, link = itemLink(2304, "Light Armor Kit") },
    { "Embossed Leather Gloves", nil, "unavailable", cost = 100, requires = { "Leatherworking", 55 }, level = 0, spell = 3756 },
}
UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-1-1-3365-000001" or nil end
UnitName = function(unit) return unit == "npc" and "Dwane Wertle" or nil end
IsTradeskillTrainer = function() return true end
GetNumTrainerServices = function() return #services end
GetTrainerServiceInfo = function(i) local s = services[i]; return s[1], s[2], s[3], true end
GetTrainerServiceCost = function(i) return services[i].cost, 0 end
GetTrainerServiceSkillReq = function(i) local s = services[i].requires; if s then return s[1], s[2], true end end
GetTrainerServiceLevelReq = function(i) return services[i].level end
GetTrainerServiceItemLink = function(i) return services[i].link end
C_TooltipInfo = { GetTrainerService = function(i) return services[i].spell and { id = services[i].spell } or nil end }

heardBefore = #heard
Client:OnProfessionEvent("TRAINER_SHOW")
local trainer = ns.db.professions.trainers[3365]
assert(trainer, "the trainer is saved under its creature ID")
local tier = trainer["name:leatherworking (journeyman)"]
assert(tier and tier.cost == 500 and tier.profession == "Leatherworking" and tier.skill == 50 and tier.level == 10 and tier.tier == "Journeyman")
assert(type(tier.seen) == "number")
assert(trainer["item:2304"].cost == 10 and trainer["item:2304"].itemID == 2304)
assert(trainer[3756].cost == 100 and trainer[3756].skill == 55 and trainer[3756].spellID == 3756)
local count = 0
for _ in pairs(trainer) do count = count + 1 end
assert(count == 3, "the header is not a service")
assert(#heard == heardBefore + 1 and heard[#heard].kind == "trainer" and heard[#heard].subject == 3365)
local trainerRow = profRows("trainer")[1]
assert(trainerRow.npc == 3365 and trainerRow.services == 3 and #trainerRow.changed == 3)
Client:RecordTrainer()
assert(#heard == heardBefore + 1 and profRows("trainer")[2].changed == nil, "a second visit with nothing new changes nothing")
C_TooltipInfo = nil
-- The trainer's name is kept for the planner's rows (new in NuuProfessions).
assert(ns.db.professions.names[3365] == "Dwane Wertle" and Client:GetNPCName(3365) == "Dwane Wertle")
assert(Client:GetNPCName(1) == nil and Client:GetNPCName(nil) == nil, "an NPC never seen, outside the client")
UnitName = nil

-- A class trainer is not a profession trainer.
UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-1-1-3169-000001" or nil end
IsTradeskillTrainer = function() return false end
Client:RecordTrainer()
assert(ns.db.professions.trainers[3169] == nil)
Client:OnProfessionEvent("TRAINER_CLOSED")

-- Merchant --------------------------------------------------------------------------

local stock = {
    { "Salt", 50, 1, -1, link = itemLink(4289, "Salt") },
    { "Pattern: Dark Leather Boots", 0, 1, -1, link = itemLink(2406, "Pattern: Dark Leather Boots"),
        costs = { { 30, "|cffffffff|Hcurrency:3402:0|h[Test Coin]|h|r" } } },
    { "Pattern: Swapped", 0, 1, 2, link = itemLink(5083, "Pattern: Swapped"),
        costs = { { 2, itemLink(2318, "Light Leather") }, { 5, nil, "Honor Points" } } },
    { "Not Cached", 100, 1, -1 },
}
UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-1-1-44000-000001" or nil end
GetMerchantNumItems = function() return #stock end
GetMerchantItemInfo = function(i) local s = stock[i]; return s[1], "icon", s[2], s[3], s[4], true, true, s.costs ~= nil end
GetMerchantItemLink = function(i) return stock[i].link end
GetMerchantItemCostInfo = function(i) return stock[i].costs and #stock[i].costs or 0 end
GetMerchantItemCostItem = function(i, c) local cost = stock[i].costs[c]; return "icon", cost[1], cost[2], cost[3] end

heardBefore = #heard
Client:OnProfessionEvent("MERCHANT_SHOW")
local merchant = ns.db.professions.merchants[44000]
assert(merchant[4289].price == 50 and merchant[4289].count == 1 and merchant[4289].stock == nil and merchant[4289].currency == nil)
assert(merchant[2406].currency[3402] == 30 and merchant[2406].price == 0, "a currency cost is recorded as the window shows it")
assert(merchant[5083].items[2318] == 2 and merchant[5083].currency["name:Honor Points"] == 5 and merchant[5083].stock == 2)
assert(type(merchant[4289].seen) == "number")
local merchantRow = profRows("merchant")[1]
assert(merchantRow.changed == 3 and merchantRow.unread == 1 and #merchantRow.extended == 2)
assert(#heard == heardBefore + 1 and heard[#heard].kind == "merchant")

-- The modern merchant table, with the old tuple gone.
GetMerchantItemInfo = nil
C_MerchantFrame = { GetItemInfo = function(i)
    local s = stock[i]
    return { name = s[1], price = s[2] + 1, stackCount = s[3], numAvailable = s[4], hasExtendedCost = s.costs ~= nil }
end }
Client:RecordMerchant()
assert(merchant[4289].price == 51, "the modern merchant table is read")
C_MerchantFrame = nil
Client:OnProfessionEvent("MERCHANT_CLOSED")
Client:OnProfessionEvent("MERCHANT_UPDATE")
assert(merchant[4289].price == 51, "a merchant update with no window open reads nothing")

-- Learned recipes join the known set at once -----------------------------------

ns.professionData = {
    Leatherworking = { recipes = { [2165] = { makes = 2313 }, [2881] = { makes = 2318 } } },
    FirstAid = { recipes = { [3275] = { makes = 1251 } } },
}
heardBefore = #heard
Client:OnProfessionEvent("NEW_RECIPE_LEARNED", 2881)
assert(character.knownRecipes.Leatherworking[2881] == true, "a learned spell is known in its profession")
assert(heard[#heard].kind == "learned" and heard[#heard].subject == "Leatherworking" and heard[#heard].data == 2881)
Client:OnProfessionEvent("NEW_RECIPE_LEARNED", 3275)
assert(character.knownRecipes["First Aid"][3275] == true, "filed under the client's profession name")
local learnedRow = profRows("learned")[#profRows("learned")]
assert(learnedRow.spell == 3275 and learnedRow.profession == "First Aid" and learnedRow.key == 3275)
Client:OnProfessionEvent("NEW_RECIPE_LEARNED", 777777)
assert(profRows("learned")[#profRows("learned")].profession == nil, "a spell nothing knows is skipped")
-- By name, from the system line: the trainer rows carry the name, the spell and the skill.
ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
Client:OnProfessionEvent("CHAT_MSG_SYSTEM", "You have learned how to create a new item: Embossed Leather Gloves.")
assert(character.knownRecipes.Leatherworking[3756] == true, "a name the trainer showed is its spell")
ns.professionRecorded = { trainers = { [11084] = { [2166] = { name = "Toughened Leather Armor", profession = "Leatherworking",
    spellID = 2166, skill = 95, cost = 405 } } } }
Client:OnProfessionEvent("CHAT_MSG_SYSTEM", "You have learned how to create a new item: Toughened Leather Armor.")
assert(character.knownRecipes.Leatherworking[2166] == true, "the shipped trainer recording counts too")
ns.professionRecorded = nil
Client:OnProfessionEvent("CHAT_MSG_SYSTEM", "You have learned how to create a new item: Light Armor Kit.")
assert(profRows("learned")[#profRows("learned")].key == "item:2304", "a name a profession window showed")
local before = 0
for _ in pairs(character.knownRecipes.Leatherworking) do before = before + 1 end
Client:OnProfessionEvent("CHAT_MSG_SYSTEM", "You have learned how to create a new item: Mystery Boots.")
local after = 0
for _ in pairs(character.knownRecipes.Leatherworking) do after = after + 1 end
assert(after == before and profRows("learned")[#profRows("learned")].profession == nil, "a name nobody knows is skipped")
Client:OnProfessionEvent("CHAT_MSG_SYSTEM", "You feel better.")
ERR_LEARN_RECIPE_S = nil
ns.professionData = nil

-- Auctionator ---------------------------------------------------------------------

assert(Client:GetAuctionatorAPI() == nil and Client:GetAuctionatorPrice(2318) == nil, "no Auctionator: no price")
local asked = {}
Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(caller, itemID)
        table.insert(asked, caller)
        if itemID == 2318 then return 45 end
        if itemID == 666 then error("boom") end
        return nil
    end,
    GetAuctionAgeByItemID = function(_, itemID) if itemID == 2318 then return 2 end end,
} } }
local price, age = Client:GetAuctionatorPrice(2318)
assert(price == 45 and age == 2 and asked[1] == "NuuProfessions", "its public API, named as NuuProfessions")
assert(Client:GetAuctionatorPrice(2319) == nil, "no price seen")
assert(Client:GetAuctionatorPrice(666) == nil, "an error is no answer")
Auctionator.API.v1.GetAuctionAgeByItemID = nil
price, age = Client:GetAuctionatorPrice(2318)
assert(price == 45 and age == nil, "no age call: a price without an age")
Auctionator = { API = {} }
assert(Client:GetAuctionatorAPI() == nil, "an Auctionator without the v1 price call is not used")
Auctionator = nil

-- Full scans: Auctionator's event bus says when one ends; its time is kept
-- per realm, and the planner is told as for an auction house visit.
assert(Client:WatchAuctionatorFullScans() == false and Client:LastAuctionScan() == nil, "no Auctionator: no scan")
local listeners = {}
Auctionator = {
    FullScan = { Events = { ScanComplete = "get_all_scan_complete" } },
    IncrementalScan = { Events = { ScanComplete = "full_incremental_scan_complete" } },
    EventBus = { Register = function(_, listener, events)
        for _, event in ipairs(events) do listeners[event] = listener end
    end },
}
GetRealmName = function() return "Classic Beta PvP" end
time = function() return 5000 end
assert(Client:WatchAuctionatorFullScans() == true and Client:WatchAuctionatorFullScans() == false, "listening once")
local before, told = ns.db.professions.revision or 0, #heard
listeners.get_all_scan_complete:ReceiveEvent("get_all_scan_complete")
assert(Client:LastAuctionScan() == 5000 and ns.db.professions.auctionScan["Classic Beta PvP"] == 5000, "kept per realm")
assert(heard[#heard].kind == "auction" and heard[#heard].subject == "scanned" and #heard == told + 1
    and ns.db.professions.revision == before + 1, "the planner told, as for a visit")
time = function() return 6000 end
listeners.full_incremental_scan_complete:ReceiveEvent("full_incremental_scan_complete")
assert(Client:LastAuctionScan() == 6000 and #heard == told + 2,
    "the modern auction house's full scan (a browse scan) too, as on Forever")
GetRealmName = function() return "Other" end
assert(Client:LastAuctionScan() == nil, "another realm's scan is not this one's")
Auctionator, time, GetRealmName = nil, nil, nil
ns.db.professions.auctionScan = nil
local revision = ns.db.professions.revision or 0
heardBefore = #heard
Client:OnProfessionEvent("AUCTION_HOUSE_CLOSED")
assert(ns.db.professions.revision == revision + 1, "closing the auction house makes the plan stale")
assert(#heard == heardBefore + 1 and heard[#heard].kind == "auction" and heard[#heard].subject == "closed")
assert(profRows("auction")[1].window == "closed")

-- What the loot line says was made.
LOOT_ITEM_CREATED_SELF = "You create: %s."
heardBefore = #heard
Client:OnProfessionEvent("CHAT_MSG_LOOT", "You create: " .. itemLink(2304, "Light Armor Kit") .. "x5.")
assert(#heard == heardBefore + 1 and heard[#heard].kind == "crafted" and heard[#heard].subject == 2304 and heard[#heard].data == 5)
Client:OnProfessionEvent("CHAT_MSG_LOOT", "You create: " .. itemLink(2318, "Light Leather") .. ".")
assert(heard[#heard].subject == 2318 and heard[#heard].data == 1, "one when the line gives no count")
Client:OnProfessionEvent("CHAT_MSG_LOOT", "You receive loot: " .. itemLink(2318, "Light Leather") .. ".")
assert(#heard == heardBefore + 2, "loot is not a craft")
LOOT_ITEM_CREATED_SELF = nil
assert(Client.MatchCraftMessage(nil, "You create: " .. itemLink(7, "X") .. "x2.") == 7, "the English words without the global")

-- Nothing crashes without a saved database or a character record.
ns.db, ns.modules.Config.characterStore, ns.characterDB = nil, nil, nil
assert(Client:ScanTradeSkill("tradeskill"))
assert(next(Client:GetKnownRecipes("Leatherworking")) == nil)
Client:RecordMerchant()
Client:RecordTrainer()

-- The modern window (Forever's): opened on a recipe, which is then selected ------

GetNumTradeSkills = function() return 0 end
GetTradeSkillLine = function() return "Blacksmithing", 35, 75 end
ns.professionData = { Blacksmithing = { skillLine = 164, recipes = {} } }
local opened, selected, crafted = {}, {}, {}
C_TradeSkillUI = {
    OpenTradeSkill = function(line) table.insert(opened, line); return true end,
    CraftRecipe = function(spell, count) table.insert(crafted, { spell, count }) end,
    GetBaseProfessionInfo = function() return { professionName = "Blacksmithing", skillLevel = 35, maxSkillLevel = 75 } end,
    GetRecipeInfo = function(spell) return { recipeID = spell, learned = true, numAvailable = 5 } end,
}
ProfessionsFrame = { CraftingPage = { SelectRecipe = function(_, info) table.insert(selected, info.recipeID) end } }
Client:OnProfessionEvent("TRADE_SKILL_CLOSE")
assert(Client:ProfessionSkillLine("blacksmithing") == 164)
assert(Client:CanOpenProfession("Blacksmithing") and not Client:CanOpenProfession("Tailoring"))
assert(select(2, Client:FindCraft("Blacksmithing", 2660)) == "closed")
assert(Client:OpenProfession("Blacksmithing", 2660, 2862))
assert(opened[1] == 164 and #selected == 0, "nothing to select until the window shows")
Client:OnProfessionEvent("TRADE_SKILL_SHOW")
assert(selected[1] == 2660 and Client.pendingFocus == nil, "the window selects the recipe it was opened for")
local found = Client:FindCraft("Blacksmithing", 2660)
assert(found and found.api == "modern" and found.available == 5, "a Classic list with no rows falls through to the modern one")
assert(Client:FindCraft(nil, 2660), "nil takes whichever window is open")
assert(Client:Craft("Blacksmithing", 2660, 2862, 3) == 3 and crafted[1][1] == 2660 and crafted[1][2] == 3)
-- A window that says none while the bags make some: the bags win.
C_TradeSkillUI.GetRecipeInfo = function(spell) return { recipeID = spell, learned = true, numAvailable = 0 } end
assert(select(2, Client:Craft("Blacksmithing", 2660, 2862, 3)) == "materials")
assert(Client:Craft("Blacksmithing", 2660, 2862, 3, nil, 2) == 2 and crafted[2][2] == 2)
assert(selected[2] == 2660, "an order selects its recipe")
GetNumTradeSkills, GetTradeSkillLine, C_TradeSkillUI, ProfessionsFrame = nil, nil, nil, nil
Client:OnProfessionEvent("TRADE_SKILL_CLOSE")

return true
