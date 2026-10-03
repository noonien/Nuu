local _, ns = ...

-- The planner's Materials tab (PROF_PLAN.md, "UI"): every material the route
-- buys, what the plan pays for it and where that price comes from, and what
-- the player decides about it.
--
--   the toolbar  which materials to show (this route, the section holding
--                your skill, the guessed or missing prices, what is cheaper
--                to buy, every material in range, or the ones not used) and
--                a search
--   the banners  how many prices are guesses or missing, with a button that
--                shows only those; and what the route makes at a loss (it
--                costs less to buy than its parts, or its gathered parts
--                would sell for more), with a button that fixes it or, for
--                several, shows only those
--   the table    grouped by where each comes from (made on the way, a
--                vendor, the auction house or gathered), each group folding:
--                what is carried of what is needed, the price used and its
--                source, the player's own auction prices, how they get it,
--                what the rest costs, and how the plan may use it. Under
--                them, what the route makes and how each counts when sold
--   the foot     what is left to buy, what the route's materials cost, and
--                what its output sells for
--
-- Not used lists the materials turned off, with a field to turn off any
-- other. Nothing here buys or sells: the prices typed are facts in the price
-- book, the rest are planner inputs, and every change plans again.
--
-- Built on a kit Table. There is no tracker section (the route is not
-- exported to a guide), so This section is the
-- one holding your skill, and the list opens on the whole route.
local Tab = { key = "materials", caption = "Materials", filter = "route", groups = {},
    -- What the status strip says while nothing else is to be said.
    hint = "Plan with it: Never use it leaves a material out, and every recipe that needs it;"
        .. " Prefer it favours recipes that use it. Right-click a material for the same." }

local function Planner() return ns.modules.ProfessionPlanner end
local function Prices() return ns.modules.Prices end
local function Tiers() return ns.modules.ProfessionTiers end

-- The Show filter, in the order the menu lists it.
local FILTERS = { "route", "section", "guessed", "loss", "range", "avoided" }
local FILTER_CAPTION = {
    route = "This route", section = "This section", guessed = "Guessed or missing", loss = "Cheaper to buy",
    range = "Every material in range", avoided = "Not used",
}
-- Other names a caller may pass to OnShow.
local FILTER_ALIAS = { notused = "avoided", never = "avoided", missing = "guessed" }

-- The groups. What puts a material in one is what the material is, never
-- what Get it says for it, so choosing there never moves a row: one a
-- recipe you may use can make, else one a vendor sells, else the rest
-- (the auction house, or gathered).
local GROUPS = {
    { "craft", "Can be made" }, { "vendor", "Sold by a vendor" }, { "ah", "Auction house or gathered" },
}

-- Plan with it: what the route may do with a material.
local PLAN_WITH = {
    { value = "auto", caption = "Planner decides", desc = "Use it where it is cheapest" },
    { value = "prefer", caption = "Prefer it", desc = "Favour recipes that use it" },
    { value = "never", caption = "Never use it", desc = "Leave out every recipe that needs it" },
}

-- Get it: make or buy (the planner's choice), make it, buy it, or gather it
-- (valued at its sale price, or free): Planner:GetMode. Make or buy and Make
-- it are offered only for an item a recipe the route may use makes, and make
-- or buy is then the default.
local MAKE_OR_BUY = { value = "auto", caption = "Make or buy",
    desc = "Made, or bought where buying it costs less than its parts" }
local MAKE_IT = { value = "make", caption = "Make it",
    desc = "Made from its parts on the way, even when buying is cheaper; its crafts may give skill" }
local BUY_IT = { value = "buy", caption = "Buy", desc = "From a vendor, or the auction house when you buy there; never made" }
local GATHER_VALUED = { value = "gather-valued", caption = "Gather, valued",
    desc = "You gather it; costed at what it would sell for, since you could sell it instead" }
local GATHER_FREE = { value = "gather-free", caption = "Gather, free", desc = "You gather it and it costs the plan nothing" }
local GET_MADE = { MAKE_OR_BUY, MAKE_IT, BUY_IT, GATHER_VALUED, GATHER_FREE }
local GET_PLAIN = { BUY_IT, GATHER_VALUED, GATHER_FREE }
local GET_CAPTION = { auto = "made or bought, whichever costs less", make = "made from its parts", buy = "bought", ["gather-valued"] = "gathered, valued at its sale price",
    ["gather-free"] = "gathered, free" }

local SALE_CAPTION = { sell = "Sold, best price", vendor = "Sold to vendors only", keep = "Kept, never sold" }

-- The column heads' tooltips, for what the short name leaves out.
local HEAD_TIPS = {
    need = "What you carry of what the route needs, at the plan's confidence.",
    used = "What one costs the plan now, and where that price comes from: you, a vendor, a merchant window you"
        .. " opened, Auctionator, or a guess (marked ~).",
    buy = "What one costs at your auction house. What you type wins over everything else. An empty field shows in"
        .. " grey the auction price in use: Auctionator's, or ~ a guess.",
    sell = "What one lists for at your auction house. The 5% auction cut is taken off for you.",
    get = "Make it: made from its parts on the way (the default wherever a recipe you may use makes it). Buy: bought"
        .. " from a vendor or the auction house, never made. Gather, valued: you gather it yourself, costed at what it"
        .. " would sell for, since you could sell it instead. Gather, free: you gather it and it costs nothing.",
    cost = "What the rest costs: what you still need past what you carry, at the price used.",
    plan = "Planner decides: use it where it is cheapest. Prefer it: favour the recipes that use it. Never use it:"
        .. " leave out every recipe that needs it. Right-click a row for the same.",
}

-- Helpers -------------------------------------------------------------------------------

local function round(value) return math.floor((value or 0) + 0.5) end

local function now()
    local clock = rawget(_G, "time") or (os and os.time)
    return clock and clock() or 0
end

local function plural(count, one, many) return count .. " " .. (count == 1 and one or many) end

-- "today", "1 day", "3 days": how old an Auctionator price is.
local function days(count)
    if not count then return nil end
    count = math.floor(count)
    if count <= 0 then return "today" end
    return count .. (count == 1 and " day" or " days")
end

local function muted(text)
    if not text or text == "" then return "" end
    return Tab.panel:Tint(text, "muted")
end

-- The row's cells --------------------------------------------------------------------

-- The widgets in a row's cells hand the player's changes on for the item
-- the row shows now (`field.data`, set each draw).
local function buyCommitted(copper, field)
    local item = field.data
    if item then Tab:SetPrice(item.itemID, "auctionBuy", copper) end
end
local function sellCommitted(copper, field)
    local item = field.data
    if item then Tab:SetPrice(item.itemID, "auctionSell", copper) end
end
local function priceInvalid(message, field)
    local item = field.data
    if not item then return end
    Tab.panel:SetStatus("Could not read that as money for " .. Tab.panel:ItemName(item.itemID) .. ". " .. message, true)
end
local function getPicked(value, select)
    local item = select.data
    if not item then return end
    if item.kind == "sale" then Tab:SetSaleMode(item.itemID, value) else Tab:SetGetMode(item.itemID, value) end
end
local function planPicked(value, select)
    local item = select.data
    if item then Tab:SetMaterialMode(item.itemID, value) end
end

local function makeMoney(onChange)
    return function(ui, cell)
        return ui:MoneyInput(cell, { boxWidth = 72, preview = false, compact = true, onChange = onChange,
            onInvalid = priceInvalid })
    end
end

-- A field showing another item puts down what was being typed in it
-- without committing: the text was meant for the item that left. A field
-- the player left with unreadable money keeps it, edged, while it shows
-- the same item.
local function showMoney(field, item, value, placeholder)
    if field.data ~= item then
        if field:HasFocus() then
            field.data = nil
            field:ClearFocus()
        end
        field:SetInvalid(nil)
        field.data = item
    elseif field:HasFocus() or field:IsInvalid() then
        return
    end
    field:SetValue(value)
    field:SetPlaceholder(placeholder)
end

local function drawBuy(field, item)
    if item.kind ~= "material" then field:Hide(); field.data = nil; return end
    field:Show()
    showMoney(field, item, item.buyValue, item.buyPlaceholder)
    field:SetAlpha(item.avoided and 0.5 or 1)
end

local function drawSell(field, item)
    field:Show()
    showMoney(field, item, item.sellValue, item.sellPlaceholder)
    field:SetAlpha(item.avoided and 0.5 or 1)
end

local function drawGet(select, item)
    select.data = item
    select:SetOptions(item.getOptions)
    select:SetValue(item.getValue)
    select:SetAlpha(item.avoided and 0.5 or 1)
end

local function drawPlan(select, item)
    if item.kind ~= "material" then select:Hide(); select.data = nil; return end
    select:Show()
    select.data = item
    select:SetValue(item.planValue)
end

local function colorOf(key) return function(item) return item[key] end end

local COLUMNS = {
    { key = "nameText", caption = "Item", grow = true, color = colorOf("nameColor") },
    { key = "needText", caption = "Need", width = 50, align = "right", number = true, color = colorOf("needColor"),
        tooltip = HEAD_TIPS.need },
    { key = "usedText", caption = "Price used", width = 130, color = colorOf("usedColor"), tooltip = HEAD_TIPS.used },
    { key = "buy", caption = "AH buy", width = 76, tooltip = HEAD_TIPS.buy, make = makeMoney(buyCommitted), draw = drawBuy },
    { key = "sell", caption = "AH sell", width = 76, tooltip = HEAD_TIPS.sell, make = makeMoney(sellCommitted),
        draw = drawSell },
    -- Wide enough for its longest choice, "Gather, valued", beside the chevron.
    { key = "get", caption = "Get it", width = 150, tooltip = HEAD_TIPS.get,
        make = function(ui, cell) return ui:Select(cell, { boxWidth = 146, options = GET_PLAIN, onChange = getPicked }) end,
        draw = drawGet },
    { key = "costText", caption = "Cost", width = 64, align = "right", color = colorOf("costColor"), tooltip = HEAD_TIPS.cost },
    { key = "plan", caption = "Plan with it", width = 170, tooltip = HEAD_TIPS.plan,
        make = function(ui, cell)
            return ui:Select(cell, { boxWidth = 126, default = "auto", options = PLAN_WITH, onChange = planPicked })
        end,
        draw = drawPlan },
}

-- Build ---------------------------------------------------------------------------------

local function filterPicked(value) Tab:SetFilter(value) end

-- The search draws the table again once typing pauses.
local function searchTyped()
    Tab.searchSerial = (Tab.searchSerial or 0) + 1
    local serial = Tab.searchSerial
    Tab.panel.After(0.15, function()
        if serial == Tab.searchSerial then Tab:Render(Tab.panel) end
    end)
end

local function neverTyped()
    Tab.suggestSerial = (Tab.suggestSerial or 0) + 1
    local serial = Tab.suggestSerial
    Tab.panel.After(0.15, function()
        if serial == Tab.suggestSerial then Tab:Suggest() end
    end)
end
local function neverCommitted() Tab:AddTyped() end

function Tab:Build(panel, page)
    self.panel, self.page = panel, page

    -- The toolbar: Show, the search, and how to type money.
    local bar = page:Row{ gap = 8 }
    bar:Text{ "Show", style = "label" }
    self.show = bar:Select{ boxWidth = 190, options = {}, onChange = filterPicked }
    self.search = bar:Search{ width = 200, placeholder = "Search materials", onType = searchTyped, valign = "center" }
    bar:Spacer{}
    bar:Text{ "Type a price as " .. ns.Kit.FormatMoney(12005, true) .. "; empty goes back to the one in grey.",
        style = "label" }

    -- As tall as its notices: a column on a page would otherwise grow.
    self.banners = page:Column{ gap = 6, grow = false }

    self.table = page:Table{
        grow = true, rowHeight = 32, columns = COLUMNS,
        onRightClick = function(item) Tab:RightClicked(item) end,
        tooltip = function(item) return Tab:RowTip(item) end,
    }

    -- Not used: a field to turn off any material.
    local never = page:Row{ gap = 8 }
    never:Text{ "Never use", style = "label" }
    self.neverField = never:Input{ width = 240, placeholder = "Type a material's name", onType = neverTyped,
        onChange = neverCommitted, valign = "center" }
    never:Button{ "Add", onClick = neverCommitted, tooltip = "Never use the material named in the field" }
    never:Text{ "any material, in this route or not", style = "label" }
    never:Hide()
    self.neverRow = never

    -- The foot: three figures and what the counts mean.
    local foot = page:Row{ gap = 6 }
    self.foot = {}
    for index, caption in ipairs({ "To buy now", "Materials, whole route", "Output sells for" }) do
        if index > 1 then foot:Spacer{ size = 14 } end
        foot:Text{ caption, style = "label" }
        self.foot[index] = foot:Text{ "", style = "number" }
    end
    foot:Spacer{}
    self.footNote = foot:Text{ "", style = "label" }
end

-- Collecting ----------------------------------------------------------------------------

-- The section holding the player's skill, and the materials it asks for:
-- its own shopping when the route is split, else (one trip) what its
-- recipes use.
function Tab:CurrentSection(panel)
    local skill = panel.live and panel.live.skill or 0
    for _, section in ipairs(panel.sections or {}) do
        if section.kind ~= "shopping" and section.kind ~= "goals" and section.toSkill and skill < section.toSkill then
            return section
        end
    end
    for _, section in ipairs(panel.sections or {}) do
        if section.kind ~= "shopping" and section.kind ~= "goals" then return section end
    end
end

local function sectionMaterials(section)
    if not section then return {} end
    if section.shopping and #section.shopping > 0 then return section.shopping end
    local counts, order = {}, {}
    for _, batch in ipairs(section.batches or {}) do
        for _, need in ipairs(batch.needs or {}) do
            local item = need[1]
            if not counts[item] then
                counts[item] = { itemID = item, count = 0, source = need[3] }
                table.insert(order, counts[item])
            end
            counts[item].count = counts[item].count + (need[2] or 0)
        end
    end
    return order
end

-- Everything the render needs: the prices described once, and the item
-- lists of every filter (for the counts in the Show menu).
function Tab:Collect(panel)
    local route, data, inputs = panel.route, panel.data, panel.inputs or {}
    local ctx = panel:PriceContext()
    local described, stamp = {}, now()
    local guessedByRoute = {}
    for _, itemID in ipairs(route and route.estimated or {}) do guessedByRoute[itemID] = true end
    local function describe(itemID)
        local info = described[itemID]
        if info then return info end
        info = ctx and ctx:Describe(itemID, stamp) or { itemID = itemID, facts = {}, missing = true }
        info.guess = (info.estimated or info.buySource == "estimate" or guessedByRoute[itemID]) and true or nil
        -- Making against buying, for an item a usable recipe makes.
        info.compare = ctx and info.makeable and ctx:MakeOrBuy(itemID) or nil
        described[itemID] = info
        return info
    end

    -- The route's materials: its shopping, then what it could not get.
    local shopping, routeList, listed = {}, {}, {}
    for _, entry in ipairs(route and route.shopping or {}) do
        shopping[entry.itemID] = entry
        listed[entry.itemID] = { itemID = entry.itemID, shop = entry, count = entry.count }
        table.insert(routeList, listed[entry.itemID])
    end
    -- What it makes on the way from its parts, beside what it carries of them.
    for _, make in ipairs(route and route.makes or {}) do
        local entry = listed[make.itemID]
        if entry then
            entry.make, entry.count = make, (entry.count or 0) + make.count
        else
            table.insert(routeList, { itemID = make.itemID, make = make, count = make.count })
        end
    end
    for _, missing in ipairs(route and route.unobtainable or {}) do
        if not shopping[missing.itemID] then table.insert(routeList, { itemID = missing.itemID }) end
    end

    local section = route and self:CurrentSection(panel)
    local sectionList = {}
    for _, entry in ipairs(sectionMaterials(section)) do
        table.insert(sectionList, { itemID = entry.itemID, shop = entry, count = entry.count })
    end

    local avoided = inputs.avoided or {}
    local guessedList = {}
    for _, entry in ipairs(routeList) do
        local info = describe(entry.itemID)
        if (info.guess or info.missing) and not avoided[entry.itemID] then table.insert(guessedList, entry) end
    end

    local lossList = {}
    for _, entry in ipairs(routeList) do
        if panel:MakeLoss(entry.itemID) then table.insert(lossList, entry) end
    end

    local rangeList = {}
    if route then
        local live = panel.live or {}
        local tiers = Tiers()
        -- The level the route was planned at: the testing switch plans past the real one.
        local level = (panel.input and panel.input.level) or live.level
        local upTo = inputs.target or (tiers and tiers.CapForLevel and tiers:CapForLevel(level)) or nil
        for _, itemID in ipairs(Planner():PriceItems(route, data, true, upTo)) do
            local shop = shopping[itemID]
            table.insert(rangeList, { itemID = itemID, shop = shop, count = shop and shop.count })
        end
    end

    local avoidedList = {}
    for itemID, off in pairs(avoided) do
        if off then table.insert(avoidedList, { itemID = itemID }) end
    end

    return {
        describe = describe, section = section,
        lists = { route = routeList, section = sectionList, guessed = guessedList, loss = lossList, range = rangeList,
            avoided = avoidedList },
    }
end

-- Render --------------------------------------------------------------------------------

function Tab:OnShow(panel, opts)
    local show = opts and opts.show
    show = show and (FILTER_ALIAS[show] or show)
    if show and FILTER_CAPTION[show] then
        self.filter = show
        self.toTop = true
    end
end

-- Another profession: its own materials, from the top.
function Tab:OnProfession()
    self.toTop = true
    if self.search then self.search:SetText("") end
    if self.neverField then self.neverField:SetText("") end
end

function Tab:SetFilter(filter)
    if not FILTER_CAPTION[filter] then return end
    self.filter = filter
    self.toTop = true
    self:Render(self.panel)
end

function Tab:Render(panel)
    if not self.table then return end
    self.panel = panel
    local collected = self:Collect(panel)
    self.collected = collected
    local filter = FILTER_CAPTION[self.filter] and self.filter or "route"
    self.filter = filter

    -- The Show menu, with how many each would list; This section says
    -- which it is.
    local list = {}
    local section = collected.section
    for _, key in ipairs(FILTERS) do
        if key == "avoided" then table.insert(list, { separator = true }) end
        table.insert(list, { value = key, caption = FILTER_CAPTION[key] .. " (" .. #collected.lists[key] .. ")",
            desc = key == "section" and section and section.title or nil })
    end
    self.show:SetOptions(list)
    self.show:SetValue(filter)

    self:RenderBanners(panel, collected)
    self:RenderTable(panel, collected)
    self:RenderFoot(panel)
end

-- "3 prices are guesses and 1 has none", and what is made at a loss: each a
-- notice with the button that deals with it.
function Tab:RenderBanners(panel, collected)
    local notices = {}
    local guesses, none = 0, 0
    for _, entry in ipairs(collected.lists.guessed) do
        if collected.describe(entry.itemID).missing then none = none + 1 else guesses = guesses + 1 end
    end
    if (guesses + none) > 0 and self.filter ~= "avoided" then
        -- A material with no source is said by why (Planner:MissingWords),
        -- never as having "no price".
        local carried = panel.route and panel.route.missingWhy == "carried"
        local said
        if guesses > 0 then
            said = guesses == 1 and "1 price is a guess" or (guesses .. " prices are guesses")
            if none > 0 then said = said .. ", and no vendor sells " .. plural(none, "material", "materials") end
            said = said .. ": the route's cost rests on them. Type what they cost on your realm."
        elseif carried then
            said = "You have none of " .. plural(none, "material", "materials") .. ", and no vendor sells "
                .. (none == 1 and "it" or "them") .. ": the recipes needing " .. (none == 1 and "it" or "them") .. " are left out."
        else
            said = "No vendor sells " .. plural(none, "material", "materials") .. ": the recipes needing "
                .. (none == 1 and "it" or "them") .. " are left out. Type what " .. (none == 1 and "it costs" or "they cost")
                .. " on your realm, or gather " .. (none == 1 and "it" or "them") .. "."
        end
        table.insert(notices, { said, self.filter ~= "guessed" and "Show only those" or nil,
            function() self:SetFilter("guessed") end })
    end

    local acting = {}
    for _, loss in ipairs(panel:MakeLosses()) do
        if panel:LossToAct(loss) then table.insert(acting, loss) end
    end
    if #acting > 0 and self.filter ~= "avoided" then
        if #acting == 1 then
            local loss = acting[1]
            local head, advice = panel:LossWords(loss)
            local part = loss.kind == "free" and loss.free and loss.free[1] and panel:ItemName(loss.free[1])
            table.insert(notices, { head .. " " .. advice, part and ("Value " .. part) or "Buy it instead",
                function() panel:ActOnLoss(loss) end })
        else
            local names = {}
            for index = 1, math.min(#acting, 2) do table.insert(names, panel:ItemName(acting[index].itemID)) end
            table.insert(notices, { #acting .. " materials are made at a loss (" .. table.concat(names, ", ")
                .. (#acting > 2 and ", ..." or "") .. "): buying them, or selling their parts, costs less."
                .. " Hover one for how much.", self.filter ~= "loss" and "Show only those" or nil,
                function() self:SetFilter("loss") end })
        end
    end

    -- Built again only when what they say changes.
    local key = {}
    for index, notice in ipairs(notices) do key[index] = notice[1] .. "|" .. tostring(notice[2]) end
    key = table.concat(key, "\n")
    self.bannerActions = notices
    if key == self.bannersKey then return end
    self.bannersKey = key
    self.banners:Clear()
    for index, notice in ipairs(notices) do
        self.banners:Notice{ notice[1], tone = "warning", action = notice[2] and {
            caption = notice[2], onClick = function() local current = self.bannerActions[index]; current[3]() end,
        } or nil }
    end
end

-- What a material is, for its group.
local function groupOf(entry, info)
    if entry.make or info.makeable then return "craft" end
    if info.facts and info.facts.vendorBuy then return "vendor" end
    return "ah"
end

-- Where the price the plan uses came from, in the player's words.
local function priceSource(info, entry)
    local source = info.buySource
    if source == "auctionator" then
        local seen = days(info.buyDays or (info.facts.auctionBuy and info.facts.auctionBuy.days))
        return "Auctionator" .. (seen and (", " .. seen) or "")
    end
    if source == "gather" then
        return info.gather == "zero" and "you gather it" or "what it sells for"
    end
    if source == "craft" then return info.estimated and "made, from guesses" or "made" end
    if source == "carried" then return "your bags" end
    if source == "vendor" then
        local fact = info.facts.vendorBuy
        if fact and fact.source == "player" then return "you" end
        if fact and fact.source == "merchant" then return "merchant" end
        return "vendor"
    end
    if source == "ah" then
        local fact = info.facts.auctionBuy
        if fact and fact.source == "player" then return "you" end
        return "auction house"
    end
    return source or (entry and entry.shop and entry.shop.source) or "?"
end

-- The grey text of an empty auction field: the auction price in use that is
-- not the player's own, or ~ the guess.
local function placeholder(fact, guess)
    if fact and fact.source ~= "player" then return ns.Kit.FormatMoney(fact.value) end
    if guess then return "~" .. ns.Kit.FormatMoney(guess) end
    return "-"
end

local function playerValue(fact)
    if fact and fact.source == "player" then return fact.value end
    return nil
end

-- A material's row: what each cell says, worked out once a render.
function Tab:MaterialItem(panel, collected, entry)
    local itemID = entry.itemID
    local info = collected.describe(itemID)
    local inputs = panel.inputs or {}
    local mode = Planner():MaterialMode(inputs, itemID)
    local avoided = mode == "never"
    local item = { kind = "material", itemID = itemID, entry = entry, info = info, avoided = avoided, planValue = mode }
    item.nameText = panel:ItemName(itemID) .. (info.bound and muted(" BoP") or "")
    item.nameColor = (info.missing and not avoided) and "danger" or (avoided and "muted" or "text")

    -- Need: carried of needed.
    local count = entry.count
    local bags = panel.live and panel.live.bags
    local have = (count and bags) and (bags(itemID) or 0) or 0
    item.count, item.have = count, have
    if count and count > 0 then
        item.needText = math.min(have, count) .. "/" .. count
        item.needColor = have >= count and "done" or "text"
    else
        item.needText, item.needColor = "-", "muted"
    end

    -- Price used, and its source.
    local each = (entry.shop and entry.shop.each) or info.buy
    local guess = info.guess or (entry.shop and entry.shop.estimated)
    if avoided then
        local left = Planner():MaterialRecipeCount(panel.data, itemID)
        item.usedText, item.usedColor = plural(left, "recipe", "recipes") .. " left out", "muted"
    elseif info.missing then
        item.usedText = (panel.route and panel.route.missingWhy == "carried") and "you have none" or "no vendor sells it"
        item.usedColor = "danger"
    elseif info.buySource == "craft" then
        -- Made: what its parts cost, for one; made at a loss, what buying
        -- one costs beside it.
        item.usedText = muted("made, ") .. (guess and ("~" .. panel:PlainMoney(round(each))) or panel:Money(round(each)))
        local loss = panel:MakeLoss(itemID)
        if loss then item.usedText = item.usedText .. " " .. panel:Tint("buy " .. panel:PlainMoney(loss.buy), "estimate") end
        item.usedColor = guess and "estimate" or "text"
    elseif guess then
        item.usedText, item.usedColor = "~" .. panel:PlainMoney(round(each)) .. ", a guess", "estimate"
    else
        item.usedText, item.usedColor = panel:Money(round(each)) .. " " .. muted(priceSource(info, entry)), "text"
    end

    -- The player's auction prices, the price in use in grey under them.
    item.buyValue = playerValue(info.facts.auctionBuy)
    item.sellValue = playerValue(info.facts.auctionSell)
    item.buyPlaceholder = placeholder(info.facts.auctionBuy, info.buySource == "estimate" and info.buy or nil)
    item.sellPlaceholder = placeholder(info.facts.auctionSell)

    -- Get it.
    local craftable = info.makeable and true or false
    item.getOptions = craftable and GET_MADE or GET_PLAIN
    item.getValue = Planner():GetMode(inputs, itemID, craftable)
    item.craftable = craftable

    -- Cost: what is still needed past what is carried.
    local short = count and math.max(count - have, 0) or nil
    if avoided or not each or not short or short == 0 then
        item.costText, item.costColor = "-", "muted"
    elseif guess then
        item.costText, item.costColor = panel:PlainMoney(round(short * each)) .. " ~", "estimate"
    else
        item.costText, item.costColor = panel:Money(round(short * each)), "text"
    end
    -- What is made is not bought: its parts are, in their own rows.
    item.short, item.each, item.guess = short, each, guess
    item.counts = not avoided and entry.make == nil
    return item
end

-- A row of What you make: each output the route has left over, and how it
-- counts when sold.
function Tab:SaleItem(panel, everySale, sale)
    local itemID = sale.itemID
    local item = { kind = "sale", itemID = itemID, sale = sale }
    item.nameText, item.nameColor = panel:ItemName(itemID), "text"
    item.needText, item.needColor = "makes " .. round(sale.count), "muted"
    local info = everySale and everySale:Describe(itemID, now()) or { facts = {} }
    local worth = info.sell or 0
    if worth > 0 then
        local where = "vendor"
        if info.sellSource == "auctionator" then
            where = "Auctionator"
        elseif info.sellSource == "ah" then
            where = (info.facts.auctionSell and info.facts.auctionSell.source == "player") and "you" or "auction house"
        end
        item.usedText = "sells " .. panel:Money(worth) .. " " .. muted(where)
    else
        item.usedText = muted("no sale price")
    end
    item.usedColor = "text"
    item.sellValue = playerValue(info.facts.auctionSell)
    item.sellPlaceholder = placeholder(info.facts.auctionSell)
    item.getOptions = self.saleList
    item.getValue = Planner():SaleMode(panel.inputs, itemID)
    local total = sale.total or 0
    if total > 0 then
        item.costText, item.costColor = "+" .. panel:Money(total), "gain"
    else
        item.costText, item.costColor = "-", "muted"
    end
    return item
end

-- A group of the table, kept from one render to the next so a fold holds.
function Tab:Group(key, caption, note, rows)
    local group = self.groups[key] or { open = true }
    self.groups[key] = group
    group.caption = caption .. (note and note ~= "" and ("  " .. muted(note)) or "")
    group.rows = rows
    return group
end

function Tab:RenderTable(panel, collected)
    local filter = self.filter
    local query = (self.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local function matches(itemID)
        return query == "" or panel:ItemName(itemID):lower():find(query, 1, true) ~= nil
    end
    self.neverRow:SetShown(filter == "avoided")
    self.shown = {}
    local toTop = self.toTop
    self.toTop = nil

    if not panel.route and filter ~= "avoided" then
        self.table:SetState("empty", panel.problem or "Plan a route to see what it needs.")
        self.table:SetItems({}, not toTop)
        return
    end

    local entries = {}
    for _, entry in ipairs(collected.lists[filter] or {}) do
        if matches(entry.itemID) then table.insert(entries, entry) end
    end
    table.sort(entries, function(a, b)
        local left, right = panel:ItemName(a.itemID), panel:ItemName(b.itemID)
        if left ~= right then return left < right end
        return a.itemID < b.itemID
    end)

    local items = {}
    if filter == "avoided" then
        local rows = {}
        for _, entry in ipairs(entries) do table.insert(rows, self:MaterialItem(panel, collected, entry)) end
        if #rows > 0 then
            table.insert(items, self:Group("avoided", "Not used",
                "the route is planned without these and every recipe that needs them", rows))
        end
    else
        local groups = {}
        for _, entry in ipairs(entries) do
            local key = groupOf(entry, collected.describe(entry.itemID))
            groups[key] = groups[key] or {}
            table.insert(groups[key], self:MaterialItem(panel, collected, entry))
        end
        for _, spec in ipairs(GROUPS) do
            local rows = groups[spec[1]]
            if rows then
                local guesses = 0
                for _, item in ipairs(rows) do
                    if item.info.guess or item.info.missing then guesses = guesses + 1 end
                end
                local note = guesses > 0 and (guesses == 1 and "1 price here is a guess"
                    or (guesses .. " prices here are guesses")) or ""
                if spec[1] == "craft" then note = "made from their parts unless Get it says otherwise" end
                table.insert(items, self:Group(spec[1], spec[2], note, rows))
            end
        end
        if filter == "route" then
            local sales = self:SaleRows(panel, query)
            if #sales > 0 then
                table.insert(items, self:Group("make", "What you make", "how each is counted when you sell it", sales))
            end
        end
    end
    for _, group in ipairs(items) do
        for _, item in ipairs(group.rows) do
            if item.kind == "material" then table.insert(self.shown, item) end
        end
    end

    if #items == 0 then
        local said
        if query ~= "" then
            said = "No material here matches \"" .. query .. "\"."
        elseif filter == "guessed" then
            said = "Every price the route uses is known: nothing is guessed or missing."
        elseif filter == "loss" then
            said = "Nothing is made at a loss: everything the route makes costs less than buying it."
        elseif filter == "section" then
            said = "Nothing to buy for this section: it makes do with what earlier ones made and what you carry."
        elseif filter == "avoided" then
            said = "You use every material. Never use one below to plan without it, and every recipe that needs it."
        else
            said = "The route needs no materials."
        end
        self.table:SetState("empty", said)
    else
        self.table:SetState(nil)
    end
    self.table:SetItems(items, not toTop)
end

-- What the route makes, as rows of What you make.
function Tab:SaleRows(panel, query)
    local route = panel.route
    local sales = {}
    for _, sale in ipairs(route and route.selling or {}) do
        if round(sale.count) > 0 and (query == "" or panel:ItemName(sale.itemID):lower():find(query, 1, true)) then
            table.insert(sales, sale)
        end
    end
    table.sort(sales, function(a, b)
        local left, right = panel:ItemName(a.itemID), panel:ItemName(b.itemID)
        if left ~= right then return left < right end
        return a.itemID < b.itemID
    end)
    local options = panel.inputs and panel.inputs.options or {}
    self.saleList = {
        { value = "default", caption = "As in Options",
            desc = options.sellOutput == "all" and "Options counts everything you make as sold"
                or "Options counts only what you choose as sold" },
        { value = "sell", caption = SALE_CAPTION.sell, desc = "Counted as sold, at the better of the vendor and the auction house" },
        { value = "vendor", caption = SALE_CAPTION.vendor, desc = "Counted as sold, at the vendor price only" },
        { value = "keep", caption = SALE_CAPTION.keep, desc = "Never counted as sold" },
    }
    local everySale = #sales > 0 and panel:PriceContext(true) or nil
    local rows = {}
    for _, sale in ipairs(sales) do table.insert(rows, self:SaleItem(panel, everySale, sale)) end
    return rows
end

-- The foot: what the listed materials still cost, the route's materials,
-- what its output sells for.
function Tab:RenderFoot(panel)
    local route = panel.route
    local toBuy, guessed, any = 0, false, false
    for _, item in ipairs(self.shown or {}) do
        if item.counts and item.short and item.each then
            any = true
            toBuy = toBuy + item.short * item.each
            if item.guess and item.short > 0 then guessed = true end
        end
    end
    local function money(text, copper, estimated)
        if not copper then
            text:SetText("-"); text:SetColor("muted")
        elseif estimated then
            text:SetText(panel:PlainMoney(round(copper)) .. " ~"); text:SetColor("estimate")
        else
            text:SetText(panel:Money(round(copper))); text:SetColor(nil)
        end
    end
    money(self.foot[1], any and toBuy or nil, guessed)
    local summary = route and route.summary
    money(self.foot[2], summary and summary.materials, summary and (summary.estimated or 0) > 0)
    if summary and (summary.recovered or 0) > 0 then
        self.foot[3]:SetText("+" .. panel:Money(summary.recovered))
        self.foot[3]:SetColor("gain")
    else
        self.foot[3]:SetText("-")
        self.foot[3]:SetColor("muted")
    end
    self.footNote:SetText(route and ("counts at " .. tostring(route.confidence or "typical")
        .. " confidence, less what you carry") or "")
end

-- Tooltips -------------------------------------------------------------------------------

function Tab:RowTip(item)
    local panel = self.panel
    local name = panel:ItemName(item.itemID)
    local opts = panel:TipOpts({ item = item.itemID })
    if item.kind == "sale" then
        local sale = item.sale
        local total = sale.total or 0
        return function(tooltip)
            tooltip:SetText(name, 1, 1, 1)
            tooltip:AddLine("The route leaves about " .. round(sale.count) .. " to sell or keep.", 0.8, 0.8, 0.8, true)
            if total > 0 then
                tooltip:AddLine("Counted as sold: about " .. panel:Money(sale.each or 0) .. " each.", 0.8, 0.8, 0.8, true)
            else
                tooltip:AddLine("Not counted as sold: it earns the plan nothing.", 0.6, 0.6, 0.6, true)
            end
        end, opts
    end
    local info, entry, avoided = item.info, item.entry, item.avoided
    return function(tooltip)
        tooltip:SetText(name, 1, 1, 1)
        if avoided then
            tooltip:AddLine("Not used: every recipe that needs it is left out.", 0.8, 0.8, 0.8, true)
        elseif info.missing then
            local why = panel.route and panel.route.missingWhy
            local text = "No vendor sells it, and no auction price is known: the plan cannot use it. Type its auction"
                .. " price, or gather it."
            if why == "carried" then
                text = "You have none, and no vendor sells it: the plan cannot use it."
            elseif why == "vendor" then
                text = "No vendor sells it, and you don't buy at the auction house: the plan cannot use it. Type a"
                    .. " price, or gather it."
            end
            panel:TipLine(tooltip, text, "danger")
        elseif item.guess then
            panel:TipLine(tooltip, "~ marks a guess: nobody has told the planner what this costs on your realm.", "estimate")
        end
        if item.count then
            tooltip:AddLine(item.count .. " needed at " .. tostring(panel.route and panel.route.confidence or "typical")
                .. " confidence, " .. item.have .. " carried.", 0.8, 0.8, 0.8)
        end
        local shop = entry.shop
        if shop and shop.lastSkill and panel.profession then
            tooltip:AddLine("Not needed past " .. panel.profession .. " " .. shop.lastSkill .. ".", 0.6, 0.6, 0.6, true)
        end
        local make = entry.make
        if make then
            tooltip:AddLine("Made on the way: " .. round(make.count) .. " in " .. round(make.crafts)
                .. (round(make.crafts) == 1 and " craft" or " crafts")
                .. ((make.gain or 0) > 0 and (", about +" .. make.gain .. " skill") or "") .. ".", 0.8, 0.8, 0.8, true)
        end
        -- Made at a loss: say so first, and what to do.
        local loss = panel:MakeLoss(item.itemID)
        if loss and not avoided then
            local head, advice = panel:LossWords(loss)
            local color = panel:LossToAct(loss) and "estimate" or { 0.8, 0.8, 0.8 }
            panel:TipLine(tooltip, head, color)
            panel:TipLine(tooltip, advice, color)
        end
        -- Making against buying, one each, so the player can choose.
        local both = item.craftable and not avoided and info.compare
        if both then
            local cheaper = both.make and both.buy and (both.make < both.buy and "make" or "buy") or nil
            if both.make then
                tooltip:AddDoubleLine("Make it (its parts)", (both.makeEstimated and "~" or "") .. panel:Money(round(both.make))
                    .. (cheaper == "make" and " cheaper" or ""), 0.8, 0.8, 0.8, 1, 1, 1)
            else
                tooltip:AddLine("Make it: a part cannot be had.", 0.6, 0.6, 0.6, true)
            end
            if both.buy then
                tooltip:AddDoubleLine("Buy it (" .. (both.buyVia == "ah" and "auction house" or "vendor") .. ")",
                    panel:Money(round(both.buy)) .. (cheaper == "buy" and " cheaper" or ""), 0.8, 0.8, 0.8, 1, 1, 1)
            else
                tooltip:AddLine("Buy it: no vendor or auction price known.", 0.6, 0.6, 0.6, true)
            end
            tooltip:AddLine("Get it chooses between them.", 0.6, 0.6, 0.6, true)
        end
        tooltip:AddLine("Right-click: how the plan may use it.", 0.6, 0.6, 0.6, true)
    end, opts
end

-- Changes -------------------------------------------------------------------------------

-- A typed auction price: empty (nil) forgets the player's own, money sets
-- it; the field itself refuses what is not money (priceInvalid). Prices live
-- in the price book, not the planner inputs, so the undo puts the old fact
-- back itself.
function Tab:SetPrice(itemID, fact, copper)
    local panel = self.panel
    if not itemID or not panel then return end
    local book = Prices():Book()
    if not book then return end
    local stored = book.prices and book.prices[itemID] and book.prices[itemID][fact]
    local old = stored and { value = stored.value, source = stored.source, seen = stored.seen } or nil
    local name = panel:ItemName(itemID)
    local label = fact == "auctionBuy" and "AH buy" or "AH sell"
    local said
    if copper == nil then
        if not (old and old.source == "player") then
            panel:Trace("price", { itemID = itemID, fact = fact, result = "nothing", old = old })
            return
        end
        Prices():SetFact(book, itemID, fact, nil)
        panel:Trace("price", { itemID = itemID, fact = fact, result = "cleared", old = old })
        said = name .. ": your " .. label .. " price is cleared; the one in grey is used again."
    else
        Prices():SetFact(book, itemID, fact, copper, "player", now())
        panel:Trace("price", { itemID = itemID, fact = fact, result = "set", value = copper, old = old })
        said = name .. ": " .. label .. " " .. panel:Money(copper) .. "."
    end
    panel:Changed("prices")
    panel:SetStatus(said, false, function()
        local current = Prices():Book()
        if not current then return end
        panel:Trace("undo", { reason = "price", itemID = itemID, fact = fact, restored = old })
        if old then
            Prices():SetFact(current, itemID, fact, old.value, old.source, old.seen)
        else
            Prices():SetFact(current, itemID, fact, nil)
        end
        panel:Changed("undo")
    end)
end

-- Get it: make, buy, or gather (valued or free).
function Tab:SetGetMode(itemID, mode)
    local panel = self.panel
    if not GET_CAPTION[mode] then return end
    local name = panel:ItemName(itemID)
    panel:Change("get", function(inputs) Planner():SetGetMode(inputs, itemID, mode) end, function(before, after)
        return name .. ": " .. GET_CAPTION[mode] .. "." .. panel:NetChange(before, after)
    end)
end

function Tab:SetMaterialMode(itemID, mode)
    local panel = self.panel
    local name = panel:ItemName(itemID)
    panel:Change("material", function(inputs) Planner():SetMaterialMode(inputs, itemID, mode) end,
        function(before, after)
            local change = panel:NetChange(before, after)
            if mode == "never" then
                local left = Planner():MaterialRecipeCount(panel.data, itemID)
                return "Not using " .. name .. ": " .. plural(left, "recipe", "recipes") .. " left out." .. change
            elseif mode == "prefer" then
                return "Preferring " .. name .. ": recipes that use it are favoured." .. change
            end
            return "The planner decides on " .. name .. " again." .. change
        end)
end

function Tab:SetSaleMode(itemID, mode)
    local panel = self.panel
    local name = panel:ItemName(itemID)
    local caption = SALE_CAPTION[mode] and SALE_CAPTION[mode]:lower() or "counted as in Options"
    panel:Change("sale", function(inputs) Planner():SetSaleMode(inputs, itemID, mode) end,
        function(before, after)
            return name .. ": " .. caption .. "." .. panel:NetChange(before, after)
        end)
end

-- Right-click on a material: the Plan with it menu at the cursor.
function Tab:RightClicked(item)
    if item.kind ~= "material" then return end
    local panel = self.panel
    panel:HideTip()
    local itemID = item.itemID
    panel:UI():OpenMenu(PLAN_WITH, { at = "cursor", current = Planner():MaterialMode(panel.inputs or {}, itemID),
        onChoose = function(value) self:SetMaterialMode(itemID, value) end })
end

-- Never use: the materials the field's text matches, in the menu under it.
function Tab:Candidates(query)
    local panel = self.panel
    local live = panel.live or {}
    local nameOf = live.nameOf or function(kind, id)
        if kind == "item" then return panel:ItemName(id) end
    end
    return Planner():MaterialCandidates(panel.data, query, nameOf, 12, panel.inputs) or {}
end

local function neverChosen(itemID) if itemID then Tab:NeverUse(itemID) end end

function Tab:Suggest()
    local field = self.neverField
    local query = (field:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local ui = self.panel:UI()
    if query == "" or not self.panel.data then ui:CloseMenu(); return end
    local list = {}
    for _, candidate in ipairs(self:Candidates(query)) do
        table.insert(list, { value = candidate.itemID, caption = candidate.name,
            desc = plural(candidate.recipes, "recipe", "recipes"),
            disabled = candidate.never or nil, reason = candidate.never and "Already not used." or nil })
    end
    if #list == 0 then
        table.insert(list, { caption = "No " .. tostring(self.panel.profession or "profession")
            .. " material matches", disabled = true, reason = "Only this profession's materials can be turned off here." })
    end
    -- A fresh list replaces the one showing.
    ui:CloseMenu()
    ui:OpenMenu(list, { anchor = field.box, onChoose = neverChosen })
end

-- Add, or Enter in the field: the material whose name was typed in full, or
-- the only one that matches; otherwise the list to pick from.
function Tab:AddTyped()
    local field = self.neverField
    local query = (field:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return end
    local open, exact = {}, nil
    for _, candidate in ipairs(self:Candidates(query)) do
        if not candidate.never then
            table.insert(open, candidate)
            if candidate.name:lower() == query:lower() then exact = candidate end
        end
    end
    local chosen = exact or (#open == 1 and open[1]) or nil
    if chosen then
        self:NeverUse(chosen.itemID)
    else
        self:Suggest()
    end
end

function Tab:NeverUse(itemID)
    self.panel:UI():CloseMenu()
    local field = self.neverField
    field:SetText("")
    field:ClearFocus()
    self:SetMaterialMode(itemID, "never")
end

ns:RegisterModule("PlannerTabMaterials", Tab)
