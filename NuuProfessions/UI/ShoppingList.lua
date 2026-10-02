local _, ns = ...

-- The shopping list: what a plan asks the player to buy or gather, in a
-- small panel of its own that stays up with the planner shut, so it can
-- be read at the vendor and the auction house.
--
-- Each section of a profession's plan that buys something is one list (with
-- the "one trip" sections, the default, that is the whole route). A
-- drop-down picks the list when there is more than one; "All sections" shows
-- every list of a profession, each under its heading.
--
-- The lists are what the planner last planned, kept per character
-- (`shoppingList.lists[profession]`, written by Keep after every plan): with
-- the planner shut nothing is planned again, so the list stays put while
-- the player shops. Only the bags and the skill are read live. An item is
-- ticked once the bags hold what it needs (the bags go to the earliest
-- section first, so two sections never count the same stack), and goes once
-- the skill passes the last step that uses it; a section with nothing left
-- leaves the drop-down. What the player makes on the way (an intermediate
-- such as a bolt of cloth) is not on the list: it is a step, not shopping.
-- The player may tick an item by hand with a click on its icon (what is in
-- the bank, or what they will do without); that tick is kept until the
-- item leaves the profession's lists.
--
-- Each row is the item's icon with the count needed, its name, where it
-- comes from with its price and what is carried, and what the rest costs.
-- Buying is on the vendor's own window (UI/VendorStrip.lua), not here. No
-- auction is searched or posted.
local List = {}

local WIDTH, MAX_HEIGHT = 340, 520

-- Where each item comes from, in the order the rows are listed, and the
-- group each is listed under.
local SOURCE_ORDER = { vendor = 1, ah = 2, estimate = 2, gather = 3, carried = 4 }
local GROUP_OF = { vendor = "vendor", ah = "ah", estimate = "ah", gather = "gather", carried = "carried" }
local GROUP_WORDS = { vendor = "Vendor", ah = "Auction house", gather = "Gather", carried = "In your bags",
    have = "Already have" }

-- Done: the bags hold what it needs, or the player ticked it by hand.
local function isDone(item) return item.have >= item.count or item.ticked and true or false end

-- The group an item is listed under: what is done goes to Already have, at
-- the end; the rest by where it is fetched.
local function groupOf(item)
    if isDone(item) then return "have" end
    return GROUP_OF[item.source] or "gather"
end
-- The price of these is spent at a shop; the rest is not money out.
local BOUGHT = { vendor = true, ah = true, estimate = true }

local ITEM_FIELDS = { "itemID", "count", "source", "each", "npc", "estimated", "lastSkill" }

local function Client() return ns.modules.Client end
local function Planner() return ns.modules.PlannerPanel end

local function after(seconds, callback)
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then timer.After(seconds, callback) else callback() end
end

-- This character's record: { lists = { [profession] = list }, pick, shown,
-- ticked = { [profession] = { [itemID] = true } } (the player's own ticks) }.
function List:Record(create)
    local Config = ns.modules.Config
    local store = Config and Config:CharacterStore()
    if not store then return nil end
    if create and type(store.shoppingList) ~= "table" then store.shoppingList = {} end
    return store.shoppingList
end

-- Keeping the plan's lists ---------------------------------------------------------------

local function copyItem(item)
    local out = {}
    for _, key in ipairs(ITEM_FIELDS) do out[key] = item[key] end
    out.source = out.source or "gather"
    return out
end

-- The lists of a plan just made: each section that buys something, its
-- title and skill levels, and its items as plain fields. Called by the
-- planner after every plan.
function List:Keep(profession, route, sections)
    if not profession or not route then return end
    local record = self:Record(true)
    if not record then return end
    local kept = {}
    for _, section in ipairs(sections or {}) do
        if section.shopping and #section.shopping > 0 then
            local title = section.title
            if section.kind == "shopping" then
                title = "Whole route " .. (section.fromSkill or route.startSkill or 1) .. "-" .. (section.toSkill or route.target or 0)
            end
            local items = {}
            for _, item in ipairs(section.shopping) do table.insert(items, copyItem(item)) end
            table.insert(kept, { title = title, kind = section.kind, fromSkill = section.fromSkill,
                toSkill = section.toSkill, items = items })
        end
    end
    record.lists = record.lists or {}
    local clock = rawget(_G, "time")
    record.lists[profession] = #kept > 0 and { at = type(clock) == "function" and clock() or 0, skill = route.startSkill,
        sections = kept } or nil
    -- A tick by hand goes with its item.
    local ticked = record.ticked and record.ticked[profession]
    if ticked then
        local listed = {}
        for _, section in ipairs(kept) do
            for _, item in ipairs(section.items) do listed[item.itemID] = true end
        end
        for itemID in pairs(ticked) do
            if not listed[itemID] then ticked[itemID] = nil end
        end
        if next(ticked) == nil then record.ticked[profession] = nil end
    end
    self:Refresh()
end

-- Reading them against the bags and the skill ---------------------------------------------

local function skillIn(profession, kept)
    local api = Client()
    local skill = api and api:GetSkillLevel(profession)
    return skill or kept.skill or 0
end

-- A profession's sections as they stand now: the items still needed (the
-- skill has not passed their last step), each with `have` from the bags
-- shared out in section order, and only the sections with something left.
function List:Live(profession, kept)
    local skill = skillIn(profession, kept)
    local api = Client()
    local record = self:Record(false)
    local ticked = record and record.ticked and record.ticked[profession] or {}
    local bags, out = {}, {}
    for index, section in ipairs(kept.sections or {}) do
        local items = {}
        for _, item in ipairs(section.items or {}) do
            if item.source ~= "craft" and not (item.lastSkill and skill >= item.lastSkill) then
                local id = item.itemID
                if bags[id] == nil then bags[id] = api and api:GetItemCount(id, true) or 0 end
                local have = math.min(bags[id], item.count or 0)
                bags[id] = bags[id] - have
                local row = copyItem(item)
                row.have, row.profession, row.ticked = have, profession, ticked[id] or nil
                table.insert(items, row)
            end
        end
        if #items > 0 then
            table.insert(out, { index = index, title = section.title, items = items })
        end
    end
    return out
end

-- Every list the drop-down can offer, professions by name: { profession,
-- sections = live sections }.
function List:Professions()
    local record = self:Record(false)
    local out = {}
    for profession, kept in pairs(record and record.lists or {}) do
        local sections = self:Live(profession, kept)
        if #sections > 0 then table.insert(out, { profession = profession, sections = sections, at = kept.at or 0 }) end
    end
    table.sort(out, function(a, b) return a.profession < b.profession end)
    return out
end

local function keyOf(profession, which) return profession .. ":" .. tostring(which) end

-- The list in view: the one picked while it still has something left, else
-- the first section left of the profession planned last. Answers the
-- profession's entry and the section index, or "all".
function List:Current(professions)
    local record = self:Record(false)
    local pick = record and record.pick
    if pick then
        for _, entry in ipairs(professions) do
            if pick == keyOf(entry.profession, "all") and #entry.sections > 1 then return entry, "all" end
            for _, section in ipairs(entry.sections) do
                if pick == keyOf(entry.profession, section.index) then return entry, section.index end
            end
        end
    end
    local latest
    for _, entry in ipairs(professions) do
        if not latest or entry.at > latest.at then latest = entry end
    end
    if latest then return latest, latest.sections[1].index end
end

-- The drop-down's choices, "<Profession>: <section>": each profession's
-- All sections where it has more than one, then its sections; a line
-- between professions.
function List:Options(professions)
    local options = {}
    for index, entry in ipairs(professions) do
        if index > 1 then table.insert(options, { separator = true }) end
        local prefix = entry.profession .. ": "
        if #entry.sections > 1 then
            table.insert(options, { value = keyOf(entry.profession, "all"), caption = prefix .. "All sections",
                desc = "Every section of the plan, each under its heading" })
        end
        for _, section in ipairs(entry.sections) do
            table.insert(options, { value = keyOf(entry.profession, section.index), caption = prefix .. section.title })
        end
    end
    return options
end

local function countLists(professions)
    local count = 0
    for _, entry in ipairs(professions) do count = count + #entry.sections end
    return count
end

-- What is in view: the profession's entry, the pick ("all" or a section
-- index), and the sections shown. nil when there is no list.
function List:InView()
    local professions = self:Professions()
    local entry, which = self:Current(professions)
    if not entry then return nil end
    local sections = {}
    for _, section in ipairs(entry.sections) do
        if which == "all" or section.index == which then table.insert(sections, section) end
    end
    return entry, which, sections, professions
end

-- What the rest of an item costs at the plan's price, and whether that is
-- a guess; nil without a price or with nothing left.
function List:CostOf(item)
    local short = math.max(0, item.count - item.have)
    if short == 0 or not item.each then return nil end
    return short * item.each, (item.estimated or item.source == "estimate") and true or false
end

-- The panel -------------------------------------------------------------------------------

local PICK_WIDTH = WIDTH - 2 * 12 - 12

local function money(copper) return ns.Kit.FormatMoney(math.floor(copper + 0.5)) end

local function picked(value)
    local record = List:Record(true)
    if record then record.pick = value end
    List:Refresh()
end

-- The close mark: the player puts the list away (a hide from code, such as
-- the whole interface hidden, does not).
local function closed()
    local record = List:Record(true)
    if record then record.shown = nil end
end

-- A click on an item's icon ticks it by hand, or takes the tick off.
function List:ToggleTick(item)
    local record = self:Record(true)
    if not (item and record) then return end
    record.ticked = record.ticked or {}
    local ticked = record.ticked[item.profession] or {}
    ticked[item.itemID] = (not item.ticked) or nil
    record.ticked[item.profession] = next(ticked) and ticked or nil
    self:Refresh()
end

local function slotClicked(slot)
    local line = slot.data
    if line then List:ToggleTick(line.item) end
end

function List:Create()
    if self.frame then return end
    local ui = ns:GetUI()
    local places = ns.db and ns.db.windows
    local win = ui:Panel({ key = "shopping", place = places, title = "Shopping list", width = WIDTH, height = 80,
        collapsible = true, close = true, onClose = closed, hidden = true,
        point = { "RIGHT", rawget(_G, "UIParent"), "RIGHT", -80, 60 } })
    self.area = win:ScrollArea{ padding = 12, gap = 6 }
    self.frame = win
    ui:OnLook(function() self.shape = nil; self:Refresh() end)
end

-- What is in view, as one string: the same shape is painted again in
-- place, another is built again.
local function shapeOf(blocks, options, value, label)
    local parts = { tostring(value), label }
    for _, option in ipairs(options or {}) do parts[#parts + 1] = tostring(option.value) .. "=" .. tostring(option.caption) end
    for _, block in ipairs(blocks) do
        parts[#parts + 1] = "|" .. tostring(block.heading)
        for _, item in ipairs(block.items) do parts[#parts + 1] = groupOf(item) .. item.itemID end
    end
    return table.concat(parts, ",")
end

-- A section's items in the order they are fetched: vendors, the auction
-- house, gathering, the bags; what is already had last.
local function ordered(items)
    local list = {}
    for index, item in ipairs(items) do list[index] = item end
    table.sort(list, function(a, b)
        local doneA, doneB = isDone(a), isDone(b)
        if doneA ~= doneB then return doneB end
        local left, right = SOURCE_ORDER[a.source] or 9, SOURCE_ORDER[b.source] or 9
        if left ~= right then return left < right end
        if (a.npc or 0) ~= (b.npc or 0) then return (a.npc or 0) < (b.npc or 0) end
        return a.itemID < b.itemID
    end)
    return list
end

function List:Build(blocks, options, value, label)
    local area = self.area
    area:Clear()
    self.rows, self.groups = {}, {}
    if options then
        area:Select{ boxWidth = PICK_WIDTH, options = options, value = value, onChange = picked,
            tooltip = "The list to show: a section of a plan, or all of one plan's sections" }
    else
        area:Text{ label, style = "label" }
    end
    for index, block in ipairs(blocks) do
        if block.heading then
            if index > 1 then area:Spacer{ size = 4 } end
            area:Text{ block.heading, style = "label" }
        end
        local group
        for _, item in ipairs(block.items) do
            local key = groupOf(item)
            if key ~= group then
                group = key
                local heading = area:Row{ gap = 8 }
                heading:Text{ GROUP_WORDS[key], style = "fine", grow = true }
                table.insert(self.groups, { key = key, block = index, cost = heading:Text{ "", style = "fine" } })
            end
            local row = area:Row{ gap = 10 }
            local line = { item = item, row = row, block = index }
            line.slot = row:Slot{ item = item.itemID, size = 34, onClick = slotClicked, data = line,
                tooltip = function(tip) tip:SetText(line.tip or "", 1, 1, 1, 1, true) end }
            local words = row:Column{ gap = 1, grow = true, valign = "center" }
            line.name = words:Text{ "" }
            line.detail = words:Text{ "", style = "fine" }
            line.cost = row:Text{ "", style = "number", valign = "center" }
            table.insert(self.rows, line)
        end
    end
    self.foot = area:Row{ gap = 8 }
    self.left = self.foot:Text{ "", style = "fine", grow = true }
    self.spend = self.foot:Text{ "", style = "fine" }
end

-- As tall as the list, up to MAX_HEIGHT, past which it scrolls.
function List:Fit()
    local win = self.frame
    ns.Kit.UI.LayoutNow()
    if win:IsCollapsed() then return end
    local inset = win.kitInset or 1
    local band = win.band:IsShown() and win.band:GetHeight() or 0
    local inner = WIDTH - 2 * inset - (ns.Kit.UI.SCROLLBAR or 0)
    local _, tall = self.area.kitInner:Measure(inner)
    win:SetHeight(math.ceil(math.min(MAX_HEIGHT, (tall or 0) + band + 2 * inset)))
end

-- An item's second line: where it comes from, its price, what is carried.
local function detailOf(item, done)
    if done then
        if item.have >= item.count then return "Carried, " .. item.have .. " of " .. item.count end
        return "Ticked by hand, " .. item.have .. " of " .. item.count .. " carried"
    end
    local have = item.have > 0 and ("you have " .. item.have .. " of " .. item.count) or "you have 0"
    local each = item.each and money(item.each) or nil
    if item.source == "vendor" then
        local name = item.npc and Planner() and Planner():NPCName(item.npc) or "A vendor"
        return name .. (each and (", " .. each .. " each") or "") .. ", " .. have
    elseif item.source == "ah" or item.source == "estimate" then
        return "Auction house" .. (each and (", about " .. each) or "") .. ", " .. have
    elseif item.source == "carried" then
        return "From your bags, " .. have
    end
    return "Gather, " .. have
end

function List:Refresh()
    if self.onRefresh then pcall(self.onRefresh) end
    if not self.frame then return end
    local record = self:Record(false)
    if not (record and record.shown) then self.frame:Hide(); return end
    local entry, which, sections, professions = self:InView()
    if not entry then self.frame:Hide(); return end

    local blocks = {}
    for _, section in ipairs(sections) do
        table.insert(blocks, { title = section.title, heading = which == "all" and section.title or nil,
            items = ordered(section.items) })
    end
    local options = countLists(professions) > 1 and self:Options(professions) or nil
    local value = keyOf(entry.profession, which)
    local label = entry.profession .. ": " .. (blocks[1] and blocks[1].title or "")
    local shape = shapeOf(blocks, options, value, label)
    local rebuilt = shape ~= self.shape
    if rebuilt then
        self:Build(blocks, options, value, label)
        self.shape = shape
    end

    -- The rows in the shape's order, each painted with its item as read now.
    local fresh = {}
    for _, block in ipairs(blocks) do
        for _, item in ipairs(block.items) do fresh[#fresh + 1] = item end
    end
    local missing, spend, guessed = 0, 0, false
    -- Each group's heading: what is left to buy in it.
    local groupCost = {}
    for index, line in ipairs(self.rows) do
        local item = fresh[index]
        line.item = item
        local done = isDone(item)
        local cost, guess = self:CostOf(item)
        if not done then
            missing = missing + 1
            if cost and BOUGHT[item.source] then
                spend = spend + cost
                guessed = guessed or guess
                local key = line.block .. ":" .. groupOf(item)
                local sum = groupCost[key] or { copper = 0 }
                sum.copper, sum.guess = sum.copper + cost, sum.guess or guess
                groupCost[key] = sum
            end
        end
        line.slot:SetCount(tostring(item.count))
        line.slot:SetEdge(done and "done" or nil)
        line.slot:FadePicture(done and 0.5 or 1)
        line.tip = done and "Click to take the tick off" or "Click to tick it by hand"
        line.name:SetText(Planner() and Planner():ItemName(item.itemID) or ("item " .. item.itemID))
        line.name:SetColor(done and "muted" or "text")
        line.detail:SetText(detailOf(item, done))
        line.detail:SetColor(done and "done" or "muted")
        line.cost:SetText((not done and cost) and ((guess and "~" or "") .. money(cost)) or "")
    end
    for _, group in ipairs(self.groups) do
        local sum = groupCost[group.block .. ":" .. group.key]
        group.cost:SetText(sum and ((sum.guess and "~" or "") .. money(sum.copper)) or "")
    end
    self.left:SetText(missing == 0 and "All carried" or (missing .. " still needed"))
    self.spend:SetText(spend > 0 and ("to buy " .. (guessed and "~" or "") .. money(spend)) or "")
    self.frame:Show()
    if rebuilt then self:Fit() end
end

-- Shown or put away, kept per character.
function List:SetShown(shown)
    local record = self:Record(true)
    if not record then return end
    record.shown = shown and true or nil
    self:Create()
    self:Refresh()
    if shown and not self.frame:IsShown() then
        ns:Print("No shopping list yet: plan a profession in the planner first.")
    end
end

function List:Toggle()
    local record = self:Record(false)
    self:SetShown(not (record and record.shown))
end

function List:IsShown()
    return self.frame ~= nil and self.frame:IsShown() or false
end

-- Events -----------------------------------------------------------------------------------

-- The bags and the skill change the ticks and what is left; a burst of
-- them repaints once.
function List:Changed()
    if self.pending then return end
    self.pending = true
    after(0.5, function()
        self.pending = false
        self:Refresh()
    end)
end

function List:Initialize()
    local record = self:Record(false)
    if record and record.shown then
        self:Create()
        self:Refresh()
    end
    if type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    local delayed = pcall(frame.RegisterEvent, frame, "BAG_UPDATE_DELAYED")
    if not delayed then pcall(frame.RegisterEvent, frame, "BAG_UPDATE") end
    frame:SetScript("OnEvent", function() self:Changed() end)
    self.eventFrame = frame
end

ns:RegisterModule("ShoppingList", List)
