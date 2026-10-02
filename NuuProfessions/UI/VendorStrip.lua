local _, ns = ...

-- Buying from the shopping list at a vendor: a strip of ours under the
-- game's vendor window, while it sells something the list in view still
-- needs. It says which list ("From your Tailoring list"), has Buy all with
-- what everything costs at this vendor, and a row per item with its count,
-- cost and Buy (Domain/MerchantBuying.lua). Those items also wear a mark on
-- the vendor's own page: an accent edge and the count needed.
--
-- The strip and the marks are our frames, parented to the vendor window's;
-- nothing of the game's is changed. The marks are painted after the game
-- draws a page (MerchantFrame_UpdateMerchantInfo, hooked), so a page turn
-- moves them with it.
local Strip = { badges = {} }

local BUY_WIDTH = 44

local function Client() return ns.modules.Client end
local function List() return ns.modules.ShoppingList end
local function Buying() return ns.modules.MerchantBuying end
local function Planner() return ns.modules.PlannerPanel end

local function after(seconds, callback)
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then timer.After(seconds, callback) else callback() end
end

local function money(copper) return ns.Kit.FormatMoney(math.floor(copper + 0.5)) end

-- What the open vendor sells of the list in view, still missing and not
-- ticked by hand: { itemID, name, offer, missing, plan }, in the list's
-- order (an item in two sections of All sections counts once, both
-- needs together). Also answers the profession.
function Strip:Wanted()
    local api = Client()
    if not (api and api.merchantOpen and List()) then return nil, {} end
    local entry, _, sections = List():InView()
    if not entry then return nil, {} end
    local offers = api:MerchantOffers()
    local wanted, byItem = {}, {}
    for _, section in ipairs(sections) do
        for _, item in ipairs(section.items) do
            local offer = offers[item.itemID]
            local missing = math.max(0, item.count - item.have)
            if offer and missing > 0 and not item.ticked then
                local found = byItem[item.itemID]
                if found then
                    found.missing = found.missing + missing
                else
                    found = { itemID = item.itemID, offer = offer, missing = missing,
                        name = Planner() and Planner():ItemName(item.itemID) or ("item " .. item.itemID) }
                    byItem[item.itemID] = found
                    table.insert(wanted, found)
                end
            end
        end
    end
    local buying = Buying()
    for index = #wanted, 1, -1 do
        wanted[index].plan = buying:Plan(wanted[index].offer, wanted[index].missing)
        if not wanted[index].plan then table.remove(wanted, index) end
    end
    return entry.profession, wanted
end

-- The strip -----------------------------------------------------------------------------

local function buyClicked(button)
    local line = button.data
    if line and line.want then Strip:Buy({ line.want }) end
end

local function buyAllClicked()
    if Strip.wanted then Strip:Buy(Strip.wanted) end
end

function Strip:Buy(entries)
    local ok, why = Buying():StartAll(entries, function() List():Refresh(); Strip:Refresh() end)
    if not ok and why then ns:Print(why) end
    self:Refresh()
end

function Strip:Create(merchant)
    if self.frame then return end
    local ui = ns:GetUI()
    local win = ui:Panel({ parent = merchant, width = math.floor(merchant:GetWidth() or 336), height = 60, hidden = true,
        point = { "TOPLEFT", merchant, "BOTTOMLEFT", 0, -2 } })
    self.body = win:Column{ padding = 8, gap = 4 }
    self.frame = win
    ui:OnLook(function() self.shape = nil; self:Refresh() end)
end

function Strip:Build(profession, wanted)
    local body = self.body
    body:Clear()
    self.rows = {}
    local head = body:Row{ gap = 8 }
    head:Text{ "From your " .. profession .. " list", style = "fine", grow = true, valign = "center" }
    self.buyAll = head:Button{ "Buy all", tone = "accent", height = 22, onClick = buyAllClicked,
        tooltip = "Buys everything on the list this vendor sells, one item after the other" }
    for _, want in ipairs(wanted) do
        local row = body:Row{ gap = 8 }
        local line = { want = want }
        line.name = row:Text{ "", grow = true, valign = "center" }
        line.cost = row:Text{ "", style = "number", valign = "center" }
        line.buy = row:Button{ "Buy", width = BUY_WIDTH, height = 20, onClick = buyClicked, data = line,
            tooltip = function(tip) tip:SetText(line.tip or "", 1, 1, 1, 1, true) end }
        table.insert(self.rows, line)
    end
end

-- As tall as what it holds.
function Strip:Fit()
    local win = self.frame
    ns.Kit.UI.LayoutNow()
    local inset = win.kitInset or 1
    local height = self.body:NaturalHeight((win:GetWidth() or 0) - 2 * inset) + 2 * inset
    win:SetHeight(math.ceil(height))
end

function Strip:Refresh()
    local merchant = rawget(_G, "MerchantFrame")
    local profession, wanted = self:Wanted()
    self.wanted = wanted
    self:PaintBadges(wanted)
    if type(merchant) ~= "table" or not profession or #wanted == 0 then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Create(merchant)
    local parts = { profession }
    for _, want in ipairs(wanted) do parts[#parts + 1] = want.itemID end
    local shape = table.concat(parts, ",")
    local rebuilt = shape ~= self.shape
    if rebuilt then
        self:Build(profession, wanted)
        self.shape = shape
    end
    local buying, have, total = Buying(), Client():GetMoney(), 0
    for index, line in ipairs(self.rows) do
        local want = wanted[index]
        local plan = want.plan
        line.want = want
        total = total + plan.cost
        line.name:SetText(plan.items .. " " .. want.name)
        line.cost:SetText(money(plan.cost))
        local tip = "Buys " .. plan.items .. " " .. want.name .. " for " .. money(plan.cost)
        if plan.items > want.missing then tip = tip .. " (sold " .. plan.per .. " at a time)" end
        if plan.items < want.missing then tip = tip .. ", all this vendor has" end
        line.tip = tip .. "."
        local reason = (buying:Busy() and "Buying, one purchase at a time")
            or (have < plan.cost and ("You have " .. money(have))) or nil
        line.buy:SetEnabled(reason == nil, reason)
    end
    self.buyAll:SetText("Buy all " .. money(total))
    local reason = (buying:Busy() and "Buying, one purchase at a time")
        or (have < total and ("You have " .. money(have))) or nil
    self.buyAll:SetEnabled(reason == nil, reason)
    self.frame:Show()
    if rebuilt then self:Fit() end
end

-- The marks on the vendor's page ----------------------------------------------------------

-- One mark per item button of the page, made the first time: an accent
-- edge round the icon and the count needed in its corner.
function Strip:Badge(slot, button)
    local badge = self.badges[slot]
    if badge then return badge end
    badge = CreateFrame("Frame", nil, button)
    badge:SetAllPoints(button)
    badge:SetFrameLevel((button:GetFrameLevel() or 0) + 5)
    badge.edges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", "height" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
        { "TOPLEFT", "BOTTOMLEFT", "width" }, { "TOPRIGHT", "BOTTOMRIGHT", "width" } }) do
        local edge = badge:CreateTexture(nil, "OVERLAY")
        edge:SetPoint(side[1], badge, side[1], 0, 0)
        edge:SetPoint(side[2], badge, side[2], 0, 0)
        if side[3] == "height" then edge:SetHeight(2) else edge:SetWidth(2) end
        table.insert(badge.edges, edge)
    end
    badge.tag = badge:CreateTexture(nil, "OVERLAY")
    badge.tag:SetPoint("TOPLEFT", badge, "TOPLEFT", 0, 0)
    badge.count = badge:CreateFontString(nil, "OVERLAY")
    badge.count:SetPoint("TOPLEFT", badge, "TOPLEFT", 2, -1)
    self.badges[slot] = badge
    return badge
end

function Strip:PaintBadges(wanted)
    local need = {}
    for _, want in ipairs(wanted or {}) do need[want.itemID] = want.missing end
    local merchant = rawget(_G, "MerchantFrame")
    local perPage = tonumber(rawget(_G, "MERCHANT_ITEMS_PER_PAGE")) or 10
    local page = type(merchant) == "table" and tonumber(merchant.page) or 1
    -- The Buyback tab shows the same buttons for what was sold.
    local buying = type(merchant) ~= "table" or merchant.selectedTab == nil or merchant.selectedTab == 1
    local api, ui = Client(), ns:GetUI()
    local t = ui.tokens
    for slot = 1, perPage do
        local button = rawget(_G, "MerchantItem" .. slot .. "ItemButton")
        if type(button) == "table" and button.GetObjectType then
            local id = buying and api.merchantOpen and api:MerchantItemID((page - 1) * perPage + slot) or nil
            local count = id and need[id]
            if count or self.badges[slot] then
                local badge = self:Badge(slot, button)
                if count then
                    for _, edge in ipairs(badge.edges) do ns.Kit.UI.TexColor(edge, t.accent) end
                    ns.Kit.UI.TexColor(badge.tag, t.accent)
                    ns.Kit.UI.ApplyStyle(badge.count, "fine", t)
                    ns.Kit.UI.TextColor(badge.count, t.window or { 0.04, 0.05, 0.06 })
                    badge.count:SetText(tostring(count))
                    badge.tag:SetSize(math.ceil((badge.count:GetStringWidth() or 8) + 4), 13)
                    badge:Show()
                else
                    badge:Hide()
                end
            end
        end
    end
end

-- Events -----------------------------------------------------------------------------------

-- A vendor opening, its stock, the bags, the money and the list itself
-- change the strip; a burst of them repaints once.
function Strip:Changed()
    if self.pending then return end
    self.pending = true
    after(0.2, function()
        self.pending = false
        self:Refresh()
    end)
end

function Strip:Initialize()
    if List() then List().onRefresh = function() Strip:Changed() end end
    if type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "PLAYER_MONEY" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    local delayed = pcall(frame.RegisterEvent, frame, "BAG_UPDATE_DELAYED")
    if not delayed then pcall(frame.RegisterEvent, frame, "BAG_UPDATE") end
    frame:SetScript("OnEvent", function() self:Changed() end)
    self.eventFrame = frame
    -- A page turn redraws the vendor's buttons: the marks follow at once.
    local hook = rawget(_G, "hooksecurefunc")
    if type(hook) == "function" and type(rawget(_G, "MerchantFrame_UpdateMerchantInfo")) == "function" then
        pcall(hook, "MerchantFrame_UpdateMerchantInfo", function() Strip:PaintBadges(Strip.wanted) end)
    end
end

ns:RegisterModule("VendorStrip", Strip)
