local _, ns = ...

-- The planner's client adapter: every game call NuuProfessions makes goes
-- through here, feature-detected and guarded, so a client that lacks a call
-- or changes it degrades to "not known" rather than an error: the detection
-- core, the stateless reads the planner uses, and the Professions section.
local Client = { capabilities = {} }

local function exists(name)
    return type(rawget(_G, name)) == "function" or type(rawget(_G, name)) == "table"
end

-- Values the client hides from addons (the "secret values" of 12.0): see
-- Kit.IsSecret. Every value read out of the client is checked first.
local function secret(value)
    return ns.Kit.IsSecret(value)
end

function Client:IsSecret(value)
    return secret(value)
end

-- A non-empty string read from the client, or nil. Checks for a secret first:
-- even taking the length of a secret string throws.
local function text(value)
    if type(value) ~= "string" or secret(value) or #value == 0 then return nil end
    return value
end

-- Calls a client function and hands back nil when the call fails or the value
-- it returns is secret, so callers can compare what they get (Kit.Read).
function Client:Read(func, ...)
    return ns.Kit.Read(func, ...)
end

local function plainNumber(value)
    if type(value) ~= "number" or secret(value) then return nil end
    return value
end

local function positionXY(position)
    if not position then return nil end
    if position.GetXY then return position:GetXY() end
    return position.x, position.y
end

function Client:Initialize()
    local info = rawget(_G, "GetBuildInfo")
    if type(info) == "function" then
        local ok, version, build, date, toc = pcall(info)
        if ok then self.build = { version = version, build = build, date = date, toc = toc } end
    end
    self.capabilities = {
        playerIdentity = exists("UnitName") and exists("UnitLevel"),
        mapCoordinates = exists("C_Map"),
        professions = exists("C_TradeSkillUI") or exists("GetProfessions"),
        skillLevels = exists("GetSkillLineInfo") or exists("GetProfessionInfo"),
        -- The profession planner's reads (the Professions section below).
        tradeSkillWindow = exists("GetTradeSkillInfo")
            or (type(rawget(_G, "C_TradeSkillUI")) == "table" and type(rawget(_G, "C_TradeSkillUI").GetAllRecipeIDs) == "function"),
        craftWindow = exists("GetCraftInfo"),
        trainerWindow = exists("GetTrainerServiceInfo"),
        merchantWindow = exists("GetMerchantItemInfo") or exists("C_MerchantFrame"),
        merchantCurrencyCosts = exists("GetMerchantItemCostItem"),
        currencies = exists("C_CurrencyInfo") or exists("GetCurrencyInfo"),
        -- Auctionator's public price API (another addon, OptionalDeps).
        auctionator = self:GetAuctionatorAPI() ~= nil,
    }
    self:WatchProfessionWindows()
    self:WatchDisenchants()
    -- The price book's auction source: Auctionator's prices, asked when a
    -- plan needs them (Domain/Prices.lua stays free of client calls).
    local Prices = ns.modules.Prices
    if Prices and Prices.SetAuctionSource then
        Prices:SetAuctionSource(function(itemID) return self:GetAuctionatorPrice(itemID) end,
            function() return self:GetAuctionatorAPI() ~= nil end)
    end
    self:WatchAuctionatorFullScans()
    -- Per-item scan times, kept by an earlier version.
    if ns.db and type(ns.db.professions) == "table" then ns.db.professions.auctionScans = nil end
end

-- Where the player is --------------------------------------------------------

function Client:GetCurrentMapID()
    local map = rawget(_G, "C_Map")
    if type(map) ~= "table" or not map.GetBestMapForUnit then return nil end
    return plainNumber(self:Read(map.GetBestMapForUnit, "player"))
end

function Client:GetPlayerMapPosition(mapID)
    local map = rawget(_G, "C_Map")
    if type(map) ~= "table" or not map.GetPlayerMapPosition or not mapID then return nil end
    local ok, position = pcall(map.GetPlayerMapPosition, mapID, "player")
    if not ok or secret(position) then return nil end
    return positionXY(position)
end

-- The map the player is on and where on it (0 to 1), for the session log
-- (Core.lua's recorder): map, x, y, or nil.
function Client:GetPlayerPosition()
    local mapID = self:GetCurrentMapID()
    if not mapID then return nil end
    local x, y = self:GetPlayerMapPosition(mapID)
    if plainNumber(x) and plainNumber(y) then return mapID, x, y end
    return mapID
end

-- Items ------------------------------------------------------------------------

-- How many the character has, the bank included (GetItemCount's
-- includeBank). `bagsOnly`: what the bags hold, which is all a craft can use.
function Client:GetItemCount(itemID, bagsOnly)
    if type(itemID) ~= "number" then return 0 end
    local items = rawget(_G, "C_Item")
    local getter = (type(items) == "table" and items.GetItemCount) or rawget(_G, "GetItemCount")
    if type(getter) ~= "function" then return 0 end
    local ok, count = pcall(getter, itemID, not bagsOnly)
    return ok and plainNumber(tonumber(count)) or 0
end

-- The client's name for an item, or nil until it is in the client's cache
-- (RequestItemData asks for it; GET_ITEM_INFO_RECEIVED says it came). The
-- planner names items from here alone.
function Client:GetItemName(itemID)
    if type(itemID) ~= "number" then return nil end
    local items = rawget(_G, "C_Item")
    if type(items) == "table" and items.GetItemNameByID then
        local ok, name = pcall(items.GetItemNameByID, itemID)
        if ok and text(name) then return name end
    end
    local info = rawget(_G, "GetItemInfo")
    if type(info) == "function" then
        local ok, name = pcall(info, itemID)
        if ok and text(name) then return name end
    end
    return nil
end

-- Asks the server for an item the client has not cached yet. The answer
-- arrives as GET_ITEM_INFO_RECEIVED. Returns true when a request was sent.
function Client:RequestItemData(itemID)
    local items = rawget(_G, "C_Item")
    if type(itemID) ~= "number" or type(items) ~= "table" or not items.RequestLoadItemDataByID then return false end
    return pcall(items.RequestLoadItemDataByID, itemID) == true
end

-- The game's own link for an item: its quality colour, its name, and the
-- hyperlink the client answers for on hover and on click. Nil until the item
-- is in the client's cache, so callers keep the plain name as a fallback and
-- ask again on the next repaint. RequestItemData primes the cache.
function Client:GetItemLink(itemID)
    if type(itemID) ~= "number" then return nil end
    local items = rawget(_G, "C_Item")
    local getter = (type(items) == "table" and items.GetItemInfo) or rawget(_G, "GetItemInfo")
    if type(getter) ~= "function" then return nil end
    local ok, _, link = pcall(getter, itemID)
    if not ok or secret(link) or type(link) ~= "string" then return nil end
    -- A link is only useful whole: the escape, the item payload, and the
    -- bracketed name. Anything else is a name, which the caller has.
    if not link:find("|H", 1, true) then return nil end
    return link
end

-- A modified click on an item, as on one in the bags: the game's own
-- handler (HandleModifiedItemClick) puts its link in the chat box or its
-- name in the auction house's search with Shift, tries it on with Ctrl.
-- Answers whether the game took the click.
function Client:ItemClicked(itemID)
    local link = self:GetItemLink(itemID)
    local handle = rawget(_G, "HandleModifiedItemClick")
    if not link or type(handle) ~= "function" then return false end
    local ok, handled = pcall(handle, link)
    return ok and handled and true or false
end

-- Three ways to the same texture, because no one of them is everywhere: the
-- by-ID call is the modern one, GetItemInfoInstant answers from the client's
-- own files without the item being cached, and the full GetItemInfo returns
-- it tenth once the server has answered. A caller that still gets nil should
-- ask with RequestItemData and paint again when the data lands.
function Client:GetItemIcon(itemID)
    if type(itemID) ~= "number" then return nil end
    local items = rawget(_G, "C_Item")
    items = type(items) == "table" and items or {}
    local function usable(icon)
        return type(icon) == "number" or (type(icon) == "string" and icon ~= "")
    end
    local byID = items.GetItemIconByID or rawget(_G, "GetItemIcon")
    if type(byID) == "function" then
        local icon = self:Read(byID, itemID)
        if usable(icon) then return icon end
    end
    local instant = items.GetItemInfoInstant or rawget(_G, "GetItemInfoInstant")
    if type(instant) == "function" then
        local ok, _, _, _, _, icon = pcall(instant, itemID)
        if ok and not secret(icon) and usable(icon) then return icon end
    end
    local full = items.GetItemInfo or rawget(_G, "GetItemInfo")
    if type(full) == "function" then
        local ok, _, _, _, _, _, _, _, _, _, icon = pcall(full, itemID)
        if ok and not secret(icon) and usable(icon) then return icon end
    end
    return nil
end

-- "ffa335ee" and friends: the quality colour of an item as a colour escape
-- body, for painting a name the client has no link for yet.
function Client:GetItemQualityColor(itemID)
    if type(itemID) ~= "number" then return nil end
    local items = rawget(_G, "C_Item")
    items = type(items) == "table" and items or {}
    local quality
    if items.GetItemQualityByID then
        quality = self:Read(items.GetItemQualityByID, itemID)
    end
    if quality == nil then
        local getter = items.GetItemInfo or rawget(_G, "GetItemInfo")
        if type(getter) == "function" then
            local ok, _, _, itemQuality = pcall(getter, itemID)
            if ok and not secret(itemQuality) then quality = itemQuality end
        end
    end
    local colorOf = rawget(_G, "GetItemQualityColor")
    if type(quality) ~= "number" or type(colorOf) ~= "function" then return nil end
    local ok, _, _, _, hex = pcall(colorOf, quality)
    if not ok or type(hex) ~= "string" or secret(hex) then return nil end
    return hex
end

-- What disenchanting needs to know of an item, from its link or ID:
-- { itemID, classID, quality, itemLevel }, or nil until the client has the
-- item cached (a tooltip's item always is). The class comes from
-- GetItemInfoInstant when the full answer leaves it out.
function Client:GetItemDisenchantInfo(item)
    if type(item) ~= "number" and type(item) ~= "string" then return nil end
    local items = rawget(_G, "C_Item")
    items = type(items) == "table" and items or {}
    local full = items.GetItemInfo or rawget(_G, "GetItemInfo")
    if type(full) ~= "function" then return nil end
    local ok, _, link, quality, level, _, _, _, _, _, _, _, classID = pcall(full, item)
    quality, level, classID = plainNumber(ok and quality), plainNumber(ok and level), plainNumber(ok and classID)
    if not quality or not level then return nil end
    local itemID = type(item) == "number" and item or nil
    local instant = items.GetItemInfoInstant or rawget(_G, "GetItemInfoInstant")
    if type(instant) == "function" and (not itemID or not classID) then
        local okInstant, id, _, _, _, _, class = pcall(instant, item)
        if okInstant then
            itemID = itemID or plainNumber(id)
            classID = classID or plainNumber(class)
        end
    end
    if not itemID then
        local parsed = text(link) or (type(item) == "string" and text(item))
        itemID = parsed and tonumber(parsed:match("item:(%d+)"))
    end
    return { itemID = itemID, classID = classID, quality = quality, itemLevel = level }
end

-- The tooltips an item line is added to: the game's own, never a hidden one
-- another addon reads lines from (NuuGear's, this addon's NPC names).
local ITEM_TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

-- The item a tooltip shows, as its link, or nil.
local function tooltipItem(tooltip)
    if type(tooltip) ~= "table" or type(tooltip.GetItem) ~= "function" then return nil end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    return ok and text(link) or nil
end

-- Runs `callback(tooltip, link)` once each time one of the game's item
-- tooltips shows an item: the tooltip data pipeline where the client has it
-- (TooltipDataProcessor, Enum.TooltipDataType.Item), else each tooltip's
-- OnTooltipSetItem script, which can fire twice for one item, so a tooltip
-- answers once until it is cleared or hidden. Returns the names of the
-- hooks placed.
function Client:OnItemTooltip(callback)
    local hooked, wanted = {}, {}
    for _, name in ipairs(ITEM_TOOLTIPS) do
        local tooltip = rawget(_G, name)
        if type(tooltip) == "table" then wanted[tooltip] = name end
    end
    local done = setmetatable({}, { __mode = "k" })
    local function run(tooltip)
        if not wanted[tooltip] then return end
        local link = tooltipItem(tooltip)
        if not link or done[tooltip] == link then return end
        done[tooltip] = link
        callback(tooltip, link)
    end
    local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
    local itemType = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item
    local piped = type(processor) == "table" and type(processor.AddTooltipPostCall) == "function" and itemType
        and pcall(processor.AddTooltipPostCall, itemType, function(tooltip) run(tooltip) end)
    if piped then table.insert(hooked, "TooltipDataProcessor") end
    local function forget(tooltip) done[tooltip] = nil end
    for tooltip, name in pairs(wanted) do
        if type(tooltip.HookScript) == "function" then
            if not piped and pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", run) then
                table.insert(hooked, name .. ".OnTooltipSetItem")
            end
            pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", forget)
            pcall(tooltip.HookScript, tooltip, "OnHide", forget)
        end
    end
    self.capabilities.itemTooltips = #hooked > 0
    return hooked
end

-- Disenchanting -------------------------------------------------------------------
--
-- Each disenchant the player makes, with what it gave, goes on the session
-- log's `disenchant` channel (lasting: Core.lua), checked against the table
-- (Disenchant:Check), so play shows where Forever differs. The item is the
-- bag item last used (a click on it, or a macro's /use, while Disenchant
-- waits for a target), read before it is destroyed; the cast is the player's
-- Disenchant (UNIT_SPELLCAST_SENT, then _SUCCEEDED); what it gave is the next
-- loot window's contents, within a few seconds.

local DISENCHANT_SPELL = 13262
-- Seconds from using an item to sending the cast, and from the cast to the loot.
local TARGET_WINDOW, LOOT_WINDOW = 2, 5

local function now()
    local clock = rawget(_G, "GetTime")
    return type(clock) == "function" and clock() or 0
end

-- Whether `spellID` is Disenchant: its ID, or a spell of the same name.
function Client:IsDisenchant(spellID)
    spellID = plainNumber(spellID)
    if not spellID then return false end
    if spellID == DISENCHANT_SPELL then return true end
    local name = self:GetSpellName(DISENCHANT_SPELL)
    return name ~= nil and self:GetSpellName(spellID) == name
end

local function containerLink(bag, slot)
    local containers = rawget(_G, "C_Container")
    local getter = (type(containers) == "table" and containers.GetContainerItemLink) or rawget(_G, "GetContainerItemLink")
    if type(getter) ~= "function" then return nil end
    local ok, link = pcall(getter, bag, slot)
    return ok and text(link) or nil
end

-- A bag item was used: kept as the next Disenchant's likely target.
function Client:DisenchantItemUsed(bag, slot)
    local link = containerLink(bag, slot)
    if not link then return end
    self.disenchantUsed = { link = link, name = link:match("%[(.-)%]"), info = self:GetItemDisenchantInfo(link), at = now() }
end

-- The loot window's contents: { { itemID, count }, ... }.
function Client:ReadLoot()
    local count = self:Read(rawget(_G, "GetNumLootItems"))
    local loot = {}
    for slot = 1, plainNumber(count) or 0 do
        local link = self:Read(rawget(_G, "GetLootSlotLink"), slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local info = rawget(_G, "GetLootSlotInfo")
            local ok, _, _, quantity = pcall(info, slot)
            table.insert(loot, { id, ok and plainNumber(quantity) or 1 })
        end
    end
    return loot
end

-- Records one disenchant: the item, what it gave, and the table's surprises.
function Client:RecordDisenchant(target, loot)
    local Disenchant = ns.modules.Disenchant
    if not Disenchant then return end
    local row = Disenchant:Check(target.info or { itemID = tonumber(target.link:match("item:(%d+)")) }, loot)
    row.event, row.link = "disenchant", target.link
    if ns.RecordHere then ns:RecordHere("disenchant", row) end
    self.lastDisenchant = row
end

function Client:OnDisenchantEvent(event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        local unit, targetName, castGUID, spellID = ...
        if unit ~= "player" or not self:IsDisenchant(spellID) then return end
        local used = self.disenchantUsed
        self.disenchantUsed = nil
        local named = text(targetName)
        if used and (now() - used.at <= TARGET_WINDOW or (named and named == used.name)) then
            self.disenchantCast = { target = used, guid = text(castGUID) }
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
        local cast = self.disenchantCast
        if unit ~= "player" or not cast or not self:IsDisenchant(spellID) then return end
        if cast.guid and text(castGUID) and cast.guid ~= castGUID then return end
        self.disenchantCast, self.disenchantLoot = nil, { target = cast.target, at = now() }
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        local unit, castGUID = ...
        local cast = self.disenchantCast
        if unit == "player" and cast and (not cast.guid or cast.guid == text(castGUID)) then self.disenchantCast = nil end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        local pending = self.disenchantLoot
        if not pending then return end
        self.disenchantLoot = nil
        if now() - pending.at > LOOT_WINDOW then return end
        self:RecordDisenchant(pending.target, self:ReadLoot())
    end
end

local DISENCHANT_EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "LOOT_READY", "LOOT_OPENED" }

-- Starts watching for disenchants. Returns the names of the item-use hooks
-- placed; none means the target cannot be known and nothing is recorded.
function Client:WatchDisenchants()
    local hooked = {}
    local hook = rawget(_G, "hooksecurefunc")
    if self.disenchantFrame or type(hook) ~= "function" then return hooked end
    local function used(bag, slot) self:DisenchantItemUsed(bag, slot) end
    local containers = rawget(_G, "C_Container")
    if type(containers) == "table" and type(containers.UseContainerItem) == "function"
        and pcall(hook, containers, "UseContainerItem", used) then
        table.insert(hooked, "C_Container.UseContainerItem")
    end
    if type(rawget(_G, "UseContainerItem")) == "function" and pcall(hook, "UseContainerItem", used) then
        table.insert(hooked, "UseContainerItem")
    end
    self.capabilities.disenchantLog = #hooked > 0
    if #hooked == 0 or type(rawget(_G, "CreateFrame")) ~= "function" then return hooked end
    local ok, frame = pcall(CreateFrame, "Frame")
    if not ok or not frame or not frame.SetScript then return hooked end
    for _, event in ipairs(DISENCHANT_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
    pcall(frame.SetScript, frame, "OnEvent", function(_, event, ...) self:OnDisenchantEvent(event, ...) end)
    self.disenchantFrame = frame
    return hooked
end

-- Spells -----------------------------------------------------------------------

function Client:GetSpellName(spellID)
    if type(spellID) ~= "number" then return nil end
    local spells = rawget(_G, "C_Spell")
    if type(spells) == "table" and spells.GetSpellName then
        local name = self:Read(spells.GetSpellName, spellID)
        if text(name) then return name end
    end
    local name = self:Read(rawget(_G, "GetSpellInfo"), spellID)
    return text(name)
end

-- Skill levels ------------------------------------------------------------------------
--
-- The classic skill window lists every skill line, including the
-- professions; modern clients answer through GetProfessions/GetProfessionInfo
-- and keep the skill window for the rest. Both are read here so the planner
-- works on either. nil means the player does not have that skill, or the
-- client cannot say.
local function sameSkill(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

-- A skill's skill and the trained cap: skill, maxSkill, or nil.
function Client:GetSkillLevel(name)
    if type(name) ~= "string" then return nil end
    local lines, info = rawget(_G, "GetNumSkillLines"), rawget(_G, "GetSkillLineInfo")
    if type(lines) == "function" and type(info) == "function" then
        local count = plainNumber(self:Read(lines))
        for index = 1, count or 0 do
            local ok, skillName, isHeader, _, skill, _, _, maxSkill = pcall(info, index)
            if ok and not isHeader and not secret(skillName) and sameSkill(skillName, name) and not secret(skill) then
                return tonumber(skill) or 0, not secret(maxSkill) and tonumber(maxSkill) or nil
            end
        end
    end
    for skillName, entry in pairs(self:GetProfessionSkills() or {}) do
        if sameSkill(skillName, name) then return entry.skill, entry.maxSkill end
    end
    return nil
end

-- The professions the modern call hands over, as { [name] = { skill, maxSkill } },
-- or nil when the client has no such call. GetProfessions returns a fixed row
-- of slots with nil for each one empty (no second profession, no archaeology),
-- so the slots are walked by position: `ipairs` would stop at the first gap
-- and never reach cooking or fishing behind it. An empty table is an answer:
-- the character has no profession.
function Client:GetProfessionSkills()
    local list, info = rawget(_G, "GetProfessions"), rawget(_G, "GetProfessionInfo")
    if type(list) ~= "function" or type(info) ~= "function" then return nil end
    local results = { pcall(list) }
    if not results[1] then return nil end
    local skills = {}
    for index = 2, table.maxn(results) do
        local slot = results[index]
        if slot ~= nil and not secret(slot) then
            local ok, skillName, _, skill, maxSkill = pcall(info, slot)
            if ok and type(skillName) == "string" and not secret(skillName) and not secret(skill) then
                skills[skillName] = { skill = tonumber(skill) or 0, maxSkill = not secret(maxSkill) and tonumber(maxSkill) or nil }
            end
        end
    end
    return skills
end

-- Every skill the skill window lists, and every profession, as { [name] =
-- skill }. Read whole so a trainer visit can be told by what changed across
-- it rather than by asking about a skill the player might not have yet.
function Client:GetSkillLevels()
    local skills = {}
    local count = type(rawget(_G, "GetSkillLineInfo")) == "function" and plainNumber(self:Read(rawget(_G, "GetNumSkillLines")))
    for index = 1, count or 0 do
        local ok, name, isHeader, _, skill = pcall(rawget(_G, "GetSkillLineInfo"), index)
        if ok and not isHeader and type(name) == "string" and not secret(name) and not secret(skill) then
            skills[name] = tonumber(skill) or 0
        end
    end
    for name, entry in pairs(self:GetProfessionSkills() or {}) do
        if skills[name] == nil then skills[name] = entry.skill end
    end
    return skills
end

function Client:HasSkillLevel(name, atLeast)
    local skill = self:GetSkillLevel(name)
    if skill == nil then return false end
    return skill >= (tonumber(atLeast) or 1)
end

-- Units ------------------------------------------------------------------------

-- Creature ID out of a GUID ("Creature-0-1234-1413-5-3448-00001234").
-- Players, pets, and anything the client cannot see answer nil.
function Client:CreatureIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

function Client:GetUnitGUID(unit)
    return text(self:Read(rawget(_G, "UnitGUID"), unit))
end

function Client:GetUnitCreatureID(unit)
    return self:CreatureIDFromGUID(self:GetUnitGUID(unit))
end

function Client:GetUnitName(unit)
    return text(self:Read(rawget(_G, "UnitName"), unit))
end

-- The player's name as the game shows it, surname included where the client
-- answers one. UnitName("player") gave "Dill Douse" on build 69977 and "Dill"
-- on 70009; which call still carries the surname is not known yet, so this
-- is UnitName until one is found.
function Client:GetPlayerFullName()
    return self:GetUnitName("player")
end

function Client:GetPlayerLevel()
    local level = plainNumber(self:Read(rawget(_G, "UnitLevel"), "player"))
    return level and level > 0 and level or nil
end

-- A tooltip nobody sees, for reading what the client only prints there: the
-- spell a trainer service teaches, and a creature's name.
local TOOLTIP_NAME = "NuuProfessionsHiddenTooltip"
function Client:HiddenTooltip()
    if self.hiddenTooltip then return self.hiddenTooltip end
    local create = rawget(_G, "CreateFrame")
    if type(create) ~= "function" then return nil end
    local ok, created = pcall(create, "GameTooltip", TOOLTIP_NAME, nil, "GameTooltipTemplate")
    if not ok or not created then return nil end
    self.hiddenTooltip = created
    local parent = rawget(_G, "UIParent")
    if created.SetOwner and parent then pcall(created.SetOwner, created, parent, "ANCHOR_NONE") end
    return created
end

-- A trainer's or merchant's name by creature ID: the name the game gave it
-- when its window was recorded (`professions.names`), else what a creature
-- hyperlink on the hidden tooltip says. The client answers that only for
-- creatures it has cached this session, so a miss is remembered with a
-- timestamp and retried after a short delay. nil when neither knows.
local npcNames = {}
function Client:GetNPCName(npcID)
    npcID = tonumber(npcID)
    if not npcID then return nil end
    local store = type(ns.db) == "table" and type(ns.db.professions) == "table" and ns.db.professions.names
    local saved = type(store) == "table" and text(store[npcID])
    if saved then return saved end
    local cached = npcNames[npcID]
    if type(cached) == "string" then return cached end
    local clock = rawget(_G, "GetTime")
    local now = type(clock) == "function" and plainNumber(self:Read(clock)) or 0
    if type(cached) == "number" and now - cached < 1.5 then return nil end
    local tooltip = self:HiddenTooltip()
    if not tooltip or not tooltip.SetHyperlink then return nil end
    if tooltip.ClearLines then pcall(tooltip.ClearLines, tooltip) end
    local ok = pcall(tooltip.SetHyperlink, tooltip, ("unit:Creature-0-0-0-0-%d-0000000000"):format(npcID))
    local line = ok and rawget(_G, TOOLTIP_NAME .. "TextLeft1")
    -- Tooltip text can be secret in instances; discard it before string operations.
    local name = line and line.GetText and text(self:Read(line.GetText, line))
    if tooltip.Hide then pcall(tooltip.Hide, tooltip) end
    if name then
        name = name:match("^|c%x%x%x%x%x%x%x%x(.-)|r$") or name
        npcNames[npcID] = name
        return name
    end
    npcNames[npcID] = now
    return nil
end

-- Professions ----------------------------------------------------------------
--
-- What the profession planner (PROF_PLAN.md) learns from the windows the
-- player opens: the profession window (known recipes and each recipe's live
-- colour), a trainer (costs, skill and level gates) and a merchant (prices,
-- stock, and any currency cost a sale asks for). Every read here
-- is a read: nothing is crafted, bought, trained, selected, expanded or
-- filtered. What a window hides behind a collapsed header or a filter is
-- simply not seen, so an absent recipe or service is never evidence of
-- anything, and nothing saved is ever removed by a later read.
--
-- Three shapes of profession window are read, whichever this client has:
--   * the Classic trade skill tuples (`GetTradeSkillInfo` and friends), which
--     give no recipe spell ID: a recipe is known by its product item;
--   * the Classic Craft API (`GetCraftInfo`), which Enchanting uses there; its
--     "product" link is an `enchant:<spellID>` link, which is the spell;
--   * `C_TradeSkillUI` on a modern client, which answers by recipe spell ID.
-- The Classic calls are tried first: a Classic-shaped client can carry a
-- `C_TradeSkillUI` table with only a few functions in it.
--
-- Other modules hear about new data through `Client:OnProfessionChange`.
-- Everything worth reading later goes to the `prof` channel of the session
-- log (`ns:RecordHere`).

local unpackValues = unpack or table.unpack

local function pack(...) return { n = select("#", ...), ... } end

local function plainString(value)
    if type(value) ~= "string" or secret(value) or value == "" then return nil end
    return value
end

-- Every value a call returns, each secret one turned to nil, or nothing at
-- all when the call is missing or fails. The tuple readers need all of them.
local function readAll(func, ...)
    if type(func) ~= "function" then return nil end
    local results = pack(pcall(func, ...))
    if not results[1] then return nil end
    for index = 2, results.n do
        if secret(results[index]) then results[index] = nil end
    end
    return unpackValues(results, 2, results.n)
end

local function global(name) return rawget(_G, name) end

local function epoch()
    local clock = global("time") or (os and os.time)
    if type(clock) ~= "function" then return nil end
    local ok, value = pcall(clock)
    return ok and type(value) == "number" and value or nil
end

-- A hyperlink's kind, ID and shown name: "|Hitem:2304:...|h[Light Armor
-- Kit]|h" is ("item", 2304, "Light Armor Kit"), an Enchanting craft's is
-- ("enchant", <spellID>, ...), and a currency cost's is ("currency", 3402, ...).
function Client.ParseLink(link)
    link = plainString(link)
    if not link then return nil end
    local kind, id = link:match("|H(%a+):(%d+)")
    return kind, tonumber(id), link:match("|h%[(.-)%]|h")
end
local parseLink = Client.ParseLink

-- The window's words for a recipe's difficulty, and the colour the player
-- sees. `difficult` (red) only shows on a trainer; `relativeDifficulty` is
-- the modern client's number for the same four.
local DIFFICULTY_COLOR = { optimal = "orange", medium = "yellow", easy = "green", trivial = "grey", difficult = "red" }
local RELATIVE_DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
Client.difficultyColors = DIFFICULTY_COLOR

local function colorOf(word)
    if type(word) ~= "string" then return nil end
    word = word:lower()
    if word == "gray" then return "grey" end
    return DIFFICULTY_COLOR[word] or word
end

-- A recipe's identity in saved data: its spell where the client gave one,
-- else its product item, else (a craft with neither) its name.
function Client.RecipeKey(recipe)
    if type(recipe) ~= "table" then return nil end
    if recipe.spellID then return recipe.spellID end
    if recipe.itemID then return "item:" .. recipe.itemID end
    if recipe.name then return "name:" .. recipe.name:lower() end
    return nil
end

-- Listeners -------------------------------------------------------------------

Client.professionListeners = {}

-- `callback(kind, subject, data)` runs whenever a read changed something:
-- ("tradeskill", professionName, snapshot), ("trainer", npcID, services),
-- ("merchant", npcID, items), ("learned", professionName, recipe key),
-- ("auction", "shown"|"closed"|"scanned"), ("window", "tradeskill"|"craft"|"closed")
-- when the profession window opens or shuts (or first reads as before), or
-- ("crafted", itemID, count) when the loot line says the player made
-- something. Errors in a listener are swallowed.
function Client:OnProfessionChange(callback)
    if type(callback) ~= "function" then return end
    table.insert(self.professionListeners, callback)
end

function Client:ProfessionChanged(kind, subject, data)
    -- A trainer fee, a merchant price or an auction house visit (Auctionator
    -- reads prices while it is open) is a price fact: bumping the book's
    -- revision is what tells the planner its route is stale.
    if kind == "trainer" or kind == "merchant" or kind == "auction" then
        local store = self:ProfessionStore()
        if store then store.revision = (tonumber(store.revision) or 0) + 1 end
    end
    for _, callback in ipairs(self.professionListeners) do pcall(callback, kind, subject, data) end
end

local function logProf(event, data)
    data = data or {}
    data.event = event
    if ns.RecordHere then ns:RecordHere("prof", data) end
end

-- Saved stores ------------------------------------------------------------------

-- Account-wide: what trainers and merchants were seen to offer.
function Client:ProfessionStore()
    if type(ns.db) ~= "table" then return nil end
    ns.db.professions = ns.db.professions or {}
    local store = ns.db.professions
    store.trainers = store.trainers or {}
    store.merchants = store.merchants or {}
    return store
end

-- Per character: `knownRecipes[professionName][key] = true`, beside the
-- planner's inputs in the character's record (Config:CharacterStore).
function Client:KnownRecipeStore(professionName)
    local Config = ns.modules.Config
    local record = Config and Config:CharacterStore() or nil
    if type(record) ~= "table" then return nil end
    record.knownRecipes = record.knownRecipes or {}
    if professionName == nil then return record.knownRecipes end
    record.knownRecipes[professionName] = record.knownRecipes[professionName] or {}
    return record.knownRecipes[professionName]
end

-- The saved known set for one profession, `{ [key] = true }`; empty when
-- nothing was read yet. Keys are spell IDs or "item:<id>" (both, where the
-- client gave both).
function Client:GetKnownRecipes(professionName)
    local all = self:KnownRecipeStore()
    if not all or type(professionName) ~= "string" then return {} end
    for name, set in pairs(all) do
        if name:lower() == professionName:lower() then return set end
    end
    return {}
end

function Client:IsRecipeKnown(professionName, key)
    return self:GetKnownRecipes(professionName)[key] == true
end

-- The client's name of a profession from its recipe data key ("FirstAid" is
-- "First Aid").
local function professionOfDataKey(dataKey)
    local Planner = ns.modules.ProfessionPlanner
    for _, name in ipairs(Planner and Planner.professions or {}) do
        if (name:gsub("%s+", "")) == dataKey then return name end
    end
    return (tostring(dataKey):gsub("(%l)(%u)", "%1 %2"))
end

-- Every trainer row there is, this session's windows first, then the shipped
-- recording (Data/ProfessionRecorded.lua): { { npc, key, row } }.
local function trainerRows(self)
    local list = {}
    local store = self:ProfessionStore()
    local recorded = ns.professionRecorded
    local sources = { store and store.trainers or false, type(recorded) == "table" and recorded.trainers or false }
    for _, source in ipairs(sources) do
        if type(source) == "table" then
            for npc, rows in pairs(source) do
                if type(rows) == "table" then
                    for key, row in pairs(rows) do
                        if type(row) == "table" then table.insert(list, { npc = npc, key = key, row = row }) end
                    end
                end
            end
        end
    end
    return list
end

-- A recipe the player just learned (NEW_RECIPE_LEARNED gives its spell, the
-- system line "You have learned how to create a new item: %s." its name), put
-- in the character's known set at once, so a plan stops charging for it
-- before the profession window is next opened. The profession and the spell
-- come from the recipe data, the trainer rows (which carry both the name and
-- the skill), or a profession window read this session. The key is the
-- spell, else the product ("item:<id>"), else "name:<name>"
-- (Planner:ResolveKnown matches both). A
-- recipe none of them know is skipped. Returns the profession and the key.
function Client:MarkRecipeLearned(spellID, name)
    spellID = tonumber(spellID)
    local lowered = plainString(name) and name:lower() or nil
    local profession, key
    if spellID then
        for dataKey, data in pairs(ns.professionData or {}) do
            if type(data) == "table" and type(data.recipes) == "table" and data.recipes[spellID] then
                profession = professionOfDataKey(dataKey)
                break
            end
        end
    end
    if not profession and (spellID or lowered) then
        for _, found in ipairs(trainerRows(self)) do
            local row = found.row
            local rowSpell = tonumber(row.spellID) or (type(found.key) == "number" and found.key) or nil
            local match
            if spellID then
                match = rowSpell == spellID
            else
                match = type(row.name) == "string" and row.name:lower() == lowered
            end
            if match and plainString(row.profession) then
                profession, spellID = row.profession, spellID or rowSpell
                if not spellID and tonumber(row.itemID) then key = "item:" .. row.itemID end
                break
            end
        end
    end
    if not profession and lowered then
        for _, snapshot in pairs(self.tradeSkillSnapshots) do
            local recipe = self:GetSnapshotRecipe(snapshot.profession, "name:" .. lowered)
            if recipe then
                profession = snapshot.profession
                key = recipe.spellID or (recipe.itemID and ("item:" .. recipe.itemID)) or nil
                break
            end
        end
    end
    if not profession then return nil end
    key = key or spellID or (lowered and ("name:" .. lowered)) or nil
    if key == nil then return nil end
    local known = self:KnownRecipeStore(profession)
    if known and not known[key] then
        known[key] = true
        self:ProfessionChanged("learned", profession, key)
    end
    return profession, key
end

-- Profession window ---------------------------------------------------------------

-- The Classic tuple APIs, as one shape. `info` normalises the row to
-- (name, type, numAvailable, isExpanded, numSkillUps).
local CLASSIC_WINDOWS = {
    tradeskill = {
        line = "GetTradeSkillLine", count = "GetNumTradeSkills",
        info = function(index)
            local name, kind, available, expanded, _, skillUps = readAll(global("GetTradeSkillInfo"), index)
            return name, kind, available, expanded, skillUps
        end,
        itemLink = "GetTradeSkillItemLink", recipeLink = "GetTradeSkillRecipeLink",
        numMade = "GetTradeSkillNumMade", numReagents = "GetTradeSkillNumReagents",
        reagentInfo = "GetTradeSkillReagentInfo", reagentLink = "GetTradeSkillReagentItemLink",
        linked = "IsTradeSkillLinked",
    },
    craft = {
        line = "GetCraftDisplaySkillLine", count = "GetNumCrafts",
        info = function(index)
            local name, _, kind, available, expanded = readAll(global("GetCraftInfo"), index)
            return name, kind, available, expanded, nil
        end,
        itemLink = "GetCraftItemLink", recipeLink = "GetCraftRecipeLink",
        numMade = "GetCraftNumMade", numReagents = "GetCraftNumReagents",
        reagentInfo = "GetCraftReagentInfo", reagentLink = "GetCraftReagentItemLink",
    },
}

-- An item link names the product; an enchant or spell link names the recipe.
local function takeLink(recipe, link)
    local kind, id, name = parseLink(link)
    if not id then return end
    if kind == "item" then
        recipe.itemID = recipe.itemID or id
    elseif kind == "enchant" or kind == "spell" then
        recipe.spellID = recipe.spellID or id
    end
    recipe.name = recipe.name or name
end

local function readClassicWindow(which)
    local api = CLASSIC_WINDOWS[which]
    if not api or type(global(api.count)) ~= "function" then return nil end
    local profession, skill, maxSkill = readAll(global(api.line))
    profession = plainString(profession)
    -- "UNKNOWN" is what the trade skill line says while no window is open.
    if not profession or profession == "UNKNOWN" then return nil end
    local snapshot = { profession = profession, skill = plainNumber(skill), maxSkill = plainNumber(maxSkill),
        api = which, recipes = {}, order = {} }
    if api.linked and readAll(global(api.linked)) == true then snapshot.linked = true end
    local count = plainNumber(readAll(global(api.count))) or 0
    for index = 1, count do
        local name, kind, available, expanded, skillUps = api.info(index)
        if kind == "header" or kind == "subheader" then
            if expanded == false then snapshot.partial = true end
        elseif plainString(name) then
            local recipe = { name = name, difficulty = plainString(kind), available = plainNumber(available),
                skillUps = plainNumber(skillUps), known = true, reagents = {} }
            recipe.color = colorOf(recipe.difficulty)
            takeLink(recipe, readAll(global(api.recipeLink), index))
            takeLink(recipe, readAll(global(api.itemLink), index))
            local low, high = readAll(global(api.numMade), index)
            if plainNumber(low) then recipe.made = { low, plainNumber(high) or low } end
            local reagents = plainNumber(readAll(global(api.numReagents), index)) or 0
            for slot = 1, reagents do
                local reagentName, _, needed = readAll(global(api.reagentInfo), index, slot)
                local _, itemID = parseLink(readAll(global(api.reagentLink), index, slot))
                table.insert(recipe.reagents, { itemID = itemID, count = plainNumber(needed) or 1, name = plainString(reagentName) })
            end
            table.insert(snapshot.order, recipe)
        end
    end
    return snapshot
end

-- The modern client's profession name and skill: the base profession names
-- it, the child (the expansion's own line) may carry the skill.
local function modernLine(ui)
    local base = type(ui.GetBaseProfessionInfo) == "function" and Client:Read(ui.GetBaseProfessionInfo) or nil
    if type(base) == "table" and plainString(base.professionName) then
        local skill, maxSkill = plainNumber(base.skillLevel), plainNumber(base.maxSkillLevel)
        local child = type(ui.GetChildProfessionInfo) == "function" and Client:Read(ui.GetChildProfessionInfo) or nil
        if type(child) == "table" and (plainNumber(child.skillLevel) or 0) > (skill or 0) then
            skill, maxSkill = plainNumber(child.skillLevel), plainNumber(child.maxSkillLevel)
        end
        return base.professionName, skill, maxSkill
    end
    if type(ui.GetTradeSkillLine) == "function" then
        local _, name, skill, maxSkill = readAll(ui.GetTradeSkillLine)
        return plainString(name), plainNumber(skill), plainNumber(maxSkill)
    end
    return nil
end

local function modernReagents(ui, recipeID, recipe)
    local schematic = type(ui.GetRecipeSchematic) == "function" and Client:Read(ui.GetRecipeSchematic, recipeID, false) or nil
    if type(schematic) == "table" then
        local low, high = plainNumber(schematic.quantityMin), plainNumber(schematic.quantityMax)
        if low then recipe.made = { low, high or low } end
        recipe.itemID = recipe.itemID or plainNumber(schematic.outputItemID)
        for _, slot in ipairs(type(schematic.reagentSlotSchematics) == "table" and schematic.reagentSlotSchematics or {}) do
            local first = type(slot.reagents) == "table" and slot.reagents[1] or nil
            -- Optional and finishing reagents are the player's choice, not the recipe's cost.
            if slot.required ~= false and type(first) == "table" and plainNumber(first.itemID) then
                table.insert(recipe.reagents, { itemID = first.itemID, count = plainNumber(slot.quantityRequired) or 1 })
            end
        end
        return
    end
    local low, high = readAll(ui.GetRecipeNumItemsProduced, recipeID)
    if plainNumber(low) then recipe.made = { low, plainNumber(high) or low } end
    local count = plainNumber(readAll(ui.GetRecipeNumReagents, recipeID)) or 0
    for slot = 1, count do
        local name, _, needed = readAll(ui.GetRecipeReagentInfo, recipeID, slot)
        local _, itemID = parseLink(readAll(ui.GetRecipeReagentItemLink, recipeID, slot))
        table.insert(recipe.reagents, { itemID = itemID, count = plainNumber(needed) or 1, name = plainString(name) })
    end
end

local function readModernWindow()
    local ui = global("C_TradeSkillUI")
    if type(ui) ~= "table" or type(ui.GetAllRecipeIDs) ~= "function" then return nil end
    -- Reagents are missing until the client says the window is ready; the
    -- update that follows readiness reads it again.
    if type(ui.IsTradeSkillReady) == "function" and readAll(ui.IsTradeSkillReady) == false then return nil end
    local profession, skill, maxSkill = modernLine(ui)
    profession = plainString(profession)
    if not profession then return nil end
    local snapshot = { profession = profession, skill = skill, maxSkill = maxSkill, api = "modern", recipes = {}, order = {} }
    if readAll(ui.IsTradeSkillLinked) == true or readAll(ui.IsTradeSkillGuild) == true then snapshot.linked = true end
    local ids = Client:Read(ui.GetAllRecipeIDs)
    for _, recipeID in ipairs(type(ids) == "table" and ids or {}) do
        local info = plainNumber(recipeID) and Client:Read(ui.GetRecipeInfo, recipeID) or nil
        if type(info) == "table" and info.type ~= "header" and info.type ~= "subheader" and plainString(info.name) then
            local difficulty = plainString(info.difficulty) or RELATIVE_DIFFICULTY[plainNumber(info.relativeDifficulty) or -1]
            local recipe = { name = info.name, spellID = recipeID, difficulty = difficulty, color = colorOf(difficulty),
                available = plainNumber(info.numAvailable), skillUps = plainNumber(info.numSkillUps),
                known = info.learned ~= false, reagents = {} }
            takeLink(recipe, readAll(ui.GetRecipeItemLink, recipeID))
            modernReagents(ui, recipeID, recipe)
            table.insert(snapshot.order, recipe)
        end
    end
    return snapshot
end

-- Reads the open profession window into a snapshot, or nil when none is
-- open or readable:
--   { profession, skill, maxSkill, api = "tradeskill"|"craft"|"modern",
--     time, partial = true when a header was collapsed, linked = true for
--     another player's (or a guild's) window,
--     recipes = { [key] = recipe }, order = { recipe, ... } in window order,
--     index = { [spellID | "item:<id>" | "name:<name>"] = key } }
-- where a recipe is { key, name, spellID, itemID, difficulty, color,
-- made = { min, max }, reagents = { { itemID, count, name } }, available,
-- skillUps, known }. `which` picks the Classic window ("tradeskill" or
-- "craft"); the modern API is the fallback for either.
function Client:ReadTradeSkillWindow(which)
    local snapshot = readClassicWindow(which or "tradeskill")
    if not snapshot or #snapshot.order == 0 then snapshot = readModernWindow() or snapshot end
    if not snapshot then return nil end
    snapshot.time = epoch()
    snapshot.index = {}
    for _, recipe in ipairs(snapshot.order) do
        recipe.key = Client.RecipeKey(recipe)
        if recipe.key ~= nil then
            snapshot.recipes[recipe.key] = recipe
            snapshot.index[recipe.key] = recipe.key
            if recipe.spellID then snapshot.index[recipe.spellID] = recipe.key end
            if recipe.itemID then snapshot.index["item:" .. recipe.itemID] = recipe.key end
            if recipe.name then snapshot.index["name:" .. recipe.name:lower()] = recipe.key end
        end
    end
    return snapshot
end

Client.tradeSkillSnapshots = {}

local function snapshotSignature(snapshot)
    local parts = { tostring(snapshot.skill), tostring(snapshot.maxSkill) }
    for _, recipe in ipairs(snapshot.order) do
        table.insert(parts, tostring(recipe.key) .. "=" .. tostring(recipe.color) .. (recipe.known and "" or "?"))
    end
    return table.concat(parts, ",")
end

-- Keeps a snapshot for the session, saves the recipes it shows as known,
-- logs it, and tells the listeners - the last three only when something
-- changed, since the window updates after every craft. A linked window is
-- somebody else's profession and is left alone.
function Client:StoreTradeSkillSnapshot(snapshot)
    if type(snapshot) ~= "table" or not snapshot.profession then return false end
    if snapshot.linked then
        logProf("linked", { profession = snapshot.profession, api = snapshot.api })
        return false
    end
    local learned = 0
    local known = self:KnownRecipeStore(snapshot.profession)
    if known then
        for _, recipe in ipairs(snapshot.order) do
            if recipe.known and recipe.key ~= nil then
                for _, key in ipairs({ recipe.key, recipe.itemID and ("item:" .. recipe.itemID) or nil }) do
                    if not known[key] then known[key] = true; learned = learned + 1 end
                end
            end
        end
    end
    local name = snapshot.profession:lower()
    local previous = self.tradeSkillSnapshots[name]
    self.tradeSkillSnapshots[name] = snapshot
    snapshot.signature = snapshotSignature(snapshot)
    if previous and previous.signature == snapshot.signature and learned == 0 then return false end
    local colors = {}
    for _, recipe in ipairs(snapshot.order) do
        if recipe.color then colors[recipe.color] = (colors[recipe.color] or 0) + 1 end
    end
    logProf("window", { profession = snapshot.profession, skill = snapshot.skill, maxSkill = snapshot.maxSkill, api = snapshot.api,
        recipes = #snapshot.order, learned = learned, partial = snapshot.partial, colors = colors })
    ns:Log("prof: " .. snapshot.profession .. " " .. tostring(snapshot.skill) .. ", " .. #snapshot.order .. " recipes read")
    self:ProfessionChanged("tradeskill", snapshot.profession, snapshot)
    return true
end

function Client:ScanTradeSkill(which)
    local snapshot = self:ReadTradeSkillWindow(which)
    if snapshot then
        local news = self:StoreTradeSkillSnapshot(snapshot)
        -- The Make buttons drew when the window showed, before the client had
        -- its recipes ("Not learned"); a reopened window that reads as before
        -- is no news, so the first read after a show tells them to look again.
        if self.windowShown and not news then self:ProfessionChanged("window", which) end
        self.windowShown = nil
    end
    return snapshot
end

-- The latest snapshot of a profession's window this session (see
-- ReadTradeSkillWindow for its shape), or nil until the player opened it.
function Client:GetTradeSkillSnapshot(professionName)
    if type(professionName) ~= "string" then return nil end
    return self.tradeSkillSnapshots[professionName:lower()]
end

function Client:GetTradeSkillSnapshots()
    return self.tradeSkillSnapshots
end

-- A recipe of the snapshot by any of its identities: a spell ID, "item:<id>",
-- "name:<name>", or the snapshot's own key.
function Client:GetSnapshotRecipe(professionName, key)
    local snapshot = self:GetTradeSkillSnapshot(professionName)
    if not snapshot or key == nil then return nil end
    local found = snapshot.index and snapshot.index[key]
    return found ~= nil and snapshot.recipes[found] or nil
end

-- The planner's check of its table against the window: returns the live
-- colour and whether it agrees with `expectedColor` ("orange", or the
-- window's word "optimal"), or nil when the window has not shown the recipe.
-- A disagreement goes to the `prof` channel once per recipe, skill and
-- expectation a session; the live colour is the one to believe.
function Client:CompareRecipeColor(professionName, key, expectedColor)
    local recipe = self:GetSnapshotRecipe(professionName, key)
    if not recipe or not recipe.color then return nil end
    local expected = colorOf(expectedColor)
    if not expected then return recipe.color, nil end
    local agrees = recipe.color == expected
    if not agrees then
        local snapshot = self:GetTradeSkillSnapshot(professionName)
        local seen = tostring(professionName):lower() .. "|" .. tostring(recipe.key) .. "|" .. tostring(snapshot.skill) .. "|" .. tostring(expected)
        self.colorDisagreements = self.colorDisagreements or {}
        if not self.colorDisagreements[seen] then
            self.colorDisagreements[seen] = true
            logProf("color", { profession = snapshot.profession, skill = snapshot.skill, recipe = recipe.key, name = recipe.name,
                spell = recipe.spellID, item = recipe.itemID, expected = expected, live = recipe.color })
        end
    end
    return recipe.color, agrees
end

-- Making from the planner ---------------------------------------------------------
--
-- A Make button on a planner row or a craft step asks the open profession
-- window to make a recipe: `DoTradeSkill` with the window's row and a count
-- on the Classic window, `DoCraft` (one at a time; an enchant then waits for
-- its target) on the Craft window, and
-- `C_TradeSkillUI.CraftRecipe` on a modern client. On the modern client
-- (Forever's) the button opens the window on the recipe first
-- (`OpenProfession`), and every order selects its recipe in the window
-- (`FocusRecipe`), so the player sees what is being made. A press is one
-- batch. A batch made to a skill stops when the window shows that skill
-- (`StopTradeSkill`), so luck with skill-ups spends no extra materials.

local function sameProfession(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

-- nil asks for whichever profession's window is open.
local function wanted(line, professionName)
    return professionName == nil or sameProfession(line, professionName)
end

-- The open window's row for a recipe, by its spell or its product:
-- { api, index, available, profession, skill, spellID } or nil and why:
-- "closed" (no window, or another profession's; `other` names it),
-- "missing" (not in the window: not learned, or under a collapsed header
-- or a filter). `professionName` nil takes whichever window is open.
function Client:FindCraft(professionName, spellID, itemID)
    spellID, itemID = tonumber(spellID), tonumber(itemID)
    local which = self.professionWindow
    local api = which and CLASSIC_WINDOWS[which]
    if api and type(global(api.count)) == "function" then
        local line, skill = readAll(global(api.line))
        line = plainString(line)
        local count = plainNumber(readAll(global(api.count))) or 0
        -- A client with the Classic calls that lists nothing through them
        -- (Forever) answers through C_TradeSkillUI below.
        if line and line ~= "UNKNOWN" and count > 0 then
            if not wanted(line, professionName) then return nil, "closed", line end
            for index = 1, count do
                local name, kind, available = api.info(index)
                if plainString(name) and kind ~= "header" and kind ~= "subheader" then
                    local recipe = {}
                    takeLink(recipe, readAll(global(api.recipeLink), index))
                    takeLink(recipe, readAll(global(api.itemLink), index))
                    -- By the spell where the window gives one: two recipes can make one item.
                    local match
                    if spellID and recipe.spellID then match = recipe.spellID == spellID
                    else match = itemID ~= nil and recipe.itemID == itemID end
                    if match then
                        return { api = which, index = index, available = plainNumber(available) or 0,
                            profession = line, skill = plainNumber(skill), spellID = recipe.spellID }
                    end
                end
            end
            return nil, "missing"
        end
    end
    local ui = global("C_TradeSkillUI")
    if which and type(ui) == "table" and type(ui.CraftRecipe) == "function" then
        local line, skill = modernLine(ui)
        if not line then return nil, "closed" end
        if not wanted(line, professionName) then return nil, "closed", line end
        if not spellID and itemID then
            local recipe = self:GetSnapshotRecipe(line, "item:" .. itemID)
            spellID = recipe and recipe.spellID
        end
        local info = spellID and self:Read(ui.GetRecipeInfo, spellID)
        if type(info) ~= "table" or info.learned == false then return nil, "missing" end
        -- numAvailable may be missing on Forever: nil is "not said", not none.
        return { api = "modern", spellID = spellID, available = plainNumber(info.numAvailable),
            profession = line, skill = skill }
    end
    return nil, "closed"
end

-- Makes `count` of a recipe in the open window (as many as the materials
-- carried allow), stopping early at `untilSkill` when given. `carried` is
-- how many crafts the bags make by the recipe data (Crafting:CanMake), for
-- a window that does not say or says too few. Returns the count asked of
-- the client, or nil and FindCraft's reason, or "materials" when nothing
-- can be made from what is carried.
function Client:Craft(professionName, spellID, itemID, count, untilSkill, carried)
    local found, why, other = self:FindCraft(professionName, spellID, itemID)
    if found then
        local said = found.available
        local Crafting = ns.Kit.Crafting
        found.available = Crafting and Crafting:Available(said, carried) or said
        found.said = said
    end
    if found and found.available == 0 then found, why = nil, "materials" end
    if not found then
        logProf("craft", { profession = professionName, spell = spellID, item = itemID, why = why, other = other,
            window = self.professionWindow, craftRecipe = type(global("C_TradeSkillUI")) == "table"
                and type(global("C_TradeSkillUI").CraftRecipe) == "function" })
        return nil, why, other
    end
    self:FocusRecipe(spellID, itemID)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if found.available then count = math.min(count, found.available) end
    if found.api == "craft" then count = 1 end
    local ok
    if found.api == "tradeskill" then
        ok = pcall(global("DoTradeSkill"), found.index, count)
    elseif found.api == "craft" then
        ok = pcall(global("DoCraft"), found.index)
    else
        ok = pcall(global("C_TradeSkillUI").CraftRecipe, found.spellID, count)
    end
    self.craftUntil = (ok and tonumber(untilSkill)) and { profession = found.profession, skill = tonumber(untilSkill) } or nil
    logProf("craft", { profession = found.profession, api = found.api, spell = found.spellID or spellID, item = itemID,
        count = count, available = found.available, said = found.said, carried = carried, skill = found.skill,
        untilSkill = untilSkill, ok = ok })
    if not ok then return nil, "failed" end
    return count
end

-- The profession's skill line, which C_TradeSkillUI.OpenTradeSkill takes,
-- from its recipe data (Blacksmithing 164, Mining 186).
function Client:ProfessionSkillLine(professionName)
    for _, all in ipairs({ ns.professionData, ns.professionDataFull }) do
        for dataKey, data in pairs(type(all) == "table" and all or {}) do
            if type(data) == "table" and sameProfession(professionOfDataKey(dataKey), professionName) then
                return tonumber(data.skillLine)
            end
        end
    end
    return nil
end

-- True where the addon can open a profession's window itself: the modern
-- C_TradeSkillUI.OpenTradeSkill. The Classic window opens only by casting
-- the profession, which an addon may not.
function Client:CanOpenProfession(professionName)
    local ui = global("C_TradeSkillUI")
    return type(ui) == "table" and type(ui.OpenTradeSkill) == "function"
        and self:ProfessionSkillLine(professionName) ~= nil
end

-- Opens a profession's window and, once it shows, selects the recipe in it.
-- Returns whether the client took the call.
function Client:OpenProfession(professionName, spellID, itemID)
    local line = self:ProfessionSkillLine(professionName)
    local ui = global("C_TradeSkillUI")
    if not line or type(ui) ~= "table" or type(ui.OpenTradeSkill) ~= "function" then return false end
    self.pendingFocus = { spell = tonumber(spellID), item = tonumber(itemID) }
    local ok, result = pcall(ui.OpenTradeSkill, line)
    logProf("open", { profession = professionName, skillLine = line, spell = spellID, item = itemID, ok = ok,
        result = ok and tostring(result) or nil })
    -- Already open on that profession: no show event will come.
    if ok and self.professionWindow then self:ScheduleFocus() end
    return ok
end

-- Selects a recipe in the open profession window, so the player sees what
-- a click makes: the modern window's CraftingPage:SelectRecipe, else the
-- Classic list's TradeSkillFrame_SetSelection, scrolled to it. Returns the
-- way that worked, or nil.
function Client:FocusRecipe(spellID, itemID)
    spellID, itemID = tonumber(spellID), tonumber(itemID)
    local how
    local ui = global("C_TradeSkillUI")
    local frame = global("ProfessionsFrame")
    local page = type(frame) == "table" and frame.CraftingPage
    if spellID and type(ui) == "table" and type(page) == "table" and type(page.SelectRecipe) == "function" then
        local info = self:Read(ui.GetRecipeInfo, spellID)
        if type(info) == "table" and pcall(page.SelectRecipe, page, info) then how = "SelectRecipe" end
    end
    if not how and self.professionWindow == "tradeskill" and type(global("TradeSkillFrame_SetSelection")) == "function" then
        local found = self:FindCraft(nil, spellID, itemID)
        if found and found.index and pcall(global("TradeSkillFrame_SetSelection"), found.index) then
            how = "TradeSkillFrame_SetSelection"
            local scroll = global("TradeSkillListScrollFrame")
            local offset = math.max(0, found.index - 3)
            if scroll and type(global("FauxScrollFrame_SetOffset")) == "function" then
                pcall(global("FauxScrollFrame_SetOffset"), scroll, offset)
                local bar = global("TradeSkillListScrollFrameScrollBar")
                if bar and bar.SetValue then pcall(bar.SetValue, bar, offset * (tonumber(global("TRADE_SKILL_HEIGHT")) or 16)) end
            end
            if type(global("TradeSkillFrame_Update")) == "function" then pcall(global("TradeSkillFrame_Update")) end
        end
    end
    logProf("focus", { spell = spellID, item = itemID, how = how, window = self.professionWindow,
        professionsFrame = type(page) == "table" })
    return how
end

-- A window opened for a recipe selects it once its list is there: a moment
-- after the show, and again a little later for a list still loading.
function Client:ScheduleFocus()
    local focus = self.pendingFocus
    if not focus then return end
    local run = function()
        if self.pendingFocus ~= focus then return end
        if self:FocusRecipe(focus.spell, focus.item) then self.pendingFocus = nil end
    end
    local timer = global("C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        pcall(timer.After, 0.2, run)
        pcall(timer.After, 0.8, function() run(); self.pendingFocus = nil end)
    else
        run()
        self.pendingFocus = nil
    end
end

-- Called on every profession window update: a batch made to a skill stops
-- once the window shows it.
function Client:CheckCraftStop()
    local stop = self.craftUntil
    if not stop then return end
    local skill
    local api = self.professionWindow and CLASSIC_WINDOWS[self.professionWindow]
    if api and type(global(api.line)) == "function" then
        local line, lineSkill = readAll(global(api.line))
        if sameProfession(plainString(line), stop.profession) then skill = plainNumber(lineSkill) end
    end
    skill = skill or self:GetSkillLevel(stop.profession)
    if skill and skill >= stop.skill then
        self.craftUntil = nil
        local ok = pcall(global("StopTradeSkill"))
        logProf("craftStop", { profession = stop.profession, skill = skill, untilSkill = stop.skill, ok = ok })
    end
end

-- Trainer window ------------------------------------------------------------------

-- The spell a trainer service teaches, where the client will say: the modern
-- tooltip data, else a hidden tooltip's own GetSpell.
function Client:GetTrainerServiceSpell(index)
    local tooltipInfo = global("C_TooltipInfo")
    if type(tooltipInfo) == "table" and type(tooltipInfo.GetTrainerService) == "function" then
        local data = self:Read(tooltipInfo.GetTrainerService, index)
        if type(data) == "table" and plainNumber(data.id) then return data.id end
    end
    local tooltip = self:HiddenTooltip()
    if tooltip and tooltip.SetTrainerService and tooltip.GetSpell then
        pcall(tooltip.ClearLines, tooltip)
        if pcall(tooltip.SetTrainerService, tooltip, index) then
            local _, spellID = readAll(tooltip.GetSpell, tooltip)
            if plainNumber(spellID) then return spellID end
        end
    end
    return nil
end

-- A trainer service's name, tier subtext ("Journeyman") and state
-- ("available", "unavailable", "used" or "header"). Forever answers name,
-- state, icon, _, tier (seen 2026-10-02: the state read as the tier, the
-- icon as the state); Classic's older order is name, tier, state.
local TRAINER_STATES = { available = true, unavailable = true, used = true, header = true }
local function trainerServiceInfo(index)
    local name, second, third, _, fifth = readAll(global("GetTrainerServiceInfo"), index)
    if TRAINER_STATES[second] then return plainString(name), plainString(fifth), second end
    return plainString(name), plainString(second), plainString(third)
end

-- Every service the open trainer lists, headers left out, as
-- { index, key, name, tier, state, cost = copper, profession, skill, level, spellID, itemID }.
-- `tier` is the subtext ("Journeyman"), `state` "available", "unavailable"
-- or "used". Only what the window's filters show is listed.
function Client:ReadTrainerServices()
    local services = {}
    local count = plainNumber(readAll(global("GetNumTrainerServices")))
    for index = 1, count or 0 do
        local name, tier, state = trainerServiceInfo(index)
        if name and state ~= "header" then
            local service = { index = index, name = name, tier = tier, state = state }
            service.cost = plainNumber((readAll(global("GetTrainerServiceCost"), index)))
            local profession, skill = readAll(global("GetTrainerServiceSkillReq"), index)
            service.profession, service.skill = plainString(profession), plainNumber(skill)
            service.level = plainNumber((readAll(global("GetTrainerServiceLevelReq"), index)))
            takeLink(service, readAll(global("GetTrainerServiceItemLink"), index))
            service.name = name
            service.spellID = service.spellID or self:GetTrainerServiceSpell(index)
            service.key = service.spellID or (service.itemID and ("item:" .. service.itemID))
                or ("name:" .. name:lower() .. (service.tier and (" (" .. service.tier:lower() .. ")") or ""))
            table.insert(services, service)
        end
    end
    return services
end

-- Whether the open trainer teaches a profession: false for a class trainer,
-- true where the client cannot say.
function Client:IsTradeskillTrainer()
    return readAll(global("IsTradeskillTrainer")) ~= false
end

-- What the open profession trainer offers, as ReadTrainerServices; empty
-- with no trainer open or a class trainer's.
function Client:TrainerOffers()
    if not self.trainerOpen or not self:IsTradeskillTrainer() then return {} end
    return self:ReadTrainerServices()
end

-- Trains the open trainer's service `index`, only while it is still the
-- service named `name` and is available. Answers whether the call was made.
function Client:BuyTrainerService(index, name)
    if not self.trainerOpen then return false end
    local shown, _, state = trainerServiceInfo(index)
    if shown ~= name or state ~= "available" then return false end
    local buy = global("BuyTrainerService")
    if type(buy) ~= "function" then return false end
    return (pcall(buy, index))
end

local function sameEntry(old, new, fields)
    if type(old) ~= "table" then return false end
    for _, field in ipairs(fields) do
        if old[field] ~= new[field] then return false end
    end
    return true
end

local TRAINER_FIELDS = { "name", "tier", "cost", "profession", "skill", "level", "spellID", "itemID" }

-- The name the game gives the NPC whose window is open, kept account-wide as
-- `professions.names[npcID]` for Client:GetNPCName.
local function recordName(self, store, npc)
    local name = self:GetUnitName("npc")
    if not name or not npc then return end
    store.names = store.names or {}
    store.names[npc] = name
end

-- Saves the open trainer's services account-wide as
-- `professions.trainers[npcID][key] = { name, tier, cost, skill, skill, level,
-- spellID, itemID, seen }`. A class trainer (IsTradeskillTrainer answering
-- false) is left out; a client without the call is read anyway.
function Client:RecordTrainer()
    local npc = self:GetUnitCreatureID("npc")
    local tradeskill = readAll(global("IsTradeskillTrainer"))
    if tradeskill == false then return nil end
    local services = self:ReadTrainerServices()
    local store = self:ProfessionStore()
    if not npc or not store or #services == 0 then
        logProf("trainer", { npc = npc, services = #services, saved = false })
        return services
    end
    recordName(self, store, npc)
    store.trainers[npc] = store.trainers[npc] or {}
    local saved, now, changed = store.trainers[npc], epoch(), {}
    for _, service in ipairs(services) do
        local old = saved[service.key]
        if not sameEntry(old, service, TRAINER_FIELDS) then
            table.insert(changed, { key = service.key, name = service.name, tier = service.tier, cost = service.cost,
                profession = service.profession, skill = service.skill, level = service.level })
        end
        saved[service.key] = { name = service.name, tier = service.tier, cost = service.cost, profession = service.profession,
            skill = service.skill, level = service.level, spellID = service.spellID, itemID = service.itemID, seen = now }
    end
    logProf("trainer", { npc = npc, services = #services, changed = #changed > 0 and changed or nil })
    if #changed > 0 then self:ProfessionChanged("trainer", npc, saved) end
    return services
end

-- Merchant window -------------------------------------------------------------------

-- Every item the open merchant sells, as { index, itemID, name, price =
-- copper for `count` items, count, stock (nil when unlimited), currency =
-- { [currencyID] = amount }, items = { [itemID] = amount } }. A currency
-- the client names without a link is kept as "name:<name>".
function Client:ReadMerchantItems()
    local items = {}
    local count = plainNumber(readAll(global("GetMerchantNumItems")))
    local modern = global("C_MerchantFrame")
    for index = 1, count or 0 do
        local entry = { index = index }
        if type(modern) == "table" and type(modern.GetItemInfo) == "function" then
            local info = self:Read(modern.GetItemInfo, index)
            if type(info) == "table" then
                entry.name, entry.price = plainString(info.name), plainNumber(info.price)
                entry.count, entry.stock = plainNumber(info.stackCount), plainNumber(info.numAvailable)
            end
        end
        if entry.price == nil then
            local name, _, price, quantity, available = readAll(global("GetMerchantItemInfo"), index)
            entry.name, entry.price = plainString(name), plainNumber(price)
            entry.count, entry.stock = plainNumber(quantity), plainNumber(available)
        end
        if entry.stock and entry.stock < 0 then entry.stock = nil end
        local kind, itemID, linkName = parseLink(readAll(global("GetMerchantItemLink"), index))
        if kind == "item" then entry.itemID = itemID end
        entry.name = entry.name or linkName
        local costs = plainNumber(readAll(global("GetMerchantItemCostInfo"), index)) or 0
        for slot = 1, costs do
            local _, amount, link, currencyName = readAll(global("GetMerchantItemCostItem"), index, slot)
            local costKind, costID = parseLink(link)
            amount = plainNumber(amount)
            if amount then
                if costKind == "currency" then
                    entry.currency = entry.currency or {}
                    entry.currency[costID] = amount
                elseif costKind == "item" then
                    entry.items = entry.items or {}
                    entry.items[costID] = amount
                elseif plainString(currencyName) then
                    entry.currency = entry.currency or {}
                    entry.currency["name:" .. currencyName] = amount
                end
            end
        end
        table.insert(items, entry)
    end
    return items
end

-- What the open merchant sells for money alone, by item: each
-- ReadMerchantItems entry with `maxStack`, the most one purchase call may
-- take. Empty with no merchant open.
function Client:MerchantOffers()
    local offers = {}
    if not self.merchantOpen then return offers end
    for _, entry in ipairs(self:ReadMerchantItems()) do
        if entry.itemID and entry.price and not entry.currency and not entry.items and not offers[entry.itemID] then
            entry.maxStack = plainNumber(readAll(global("GetMerchantItemMaxStack"), entry.index))
            offers[entry.itemID] = entry
        end
    end
    return offers
end

-- The item in the open merchant's slot `index`, or nil.
function Client:MerchantItemID(index)
    local kind, id = parseLink(readAll(global("GetMerchantItemLink"), index))
    return kind == "item" and id or nil
end

-- Buys from the open merchant's slot `index`, only while it still holds
-- `itemID`: `quantity` items in one call, or one purchase (the merchant's
-- own batch) with no quantity. Answers whether the call was made.
function Client:BuyMerchantItem(index, itemID, quantity)
    if not self.merchantOpen then return false end
    local kind, id = parseLink(readAll(global("GetMerchantItemLink"), index))
    if kind ~= "item" or id ~= itemID then return false end
    local buy = global("BuyMerchantItem")
    if type(buy) ~= "function" then return false end
    if quantity then return (pcall(buy, index, quantity)) end
    return (pcall(buy, index))
end

-- The character's money, in copper.
function Client:GetMoney()
    return plainNumber(readAll(global("GetMoney"))) or 0
end

local function sameCosts(a, b)
    if a == nil or b == nil then return a == b end
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- Saves the open merchant's stock account-wide as
-- `professions.merchants[npcID][itemID] = { price, count, stock, currency,
-- items, seen }`. Items the client has no link for yet are skipped; the
-- MERCHANT_UPDATE that follows their arrival reads them.
function Client:RecordMerchant()
    local npc = self:GetUnitCreatureID("npc")
    local items = self:ReadMerchantItems()
    local store = self:ProfessionStore()
    if not npc or not store then
        logProf("merchant", { npc = npc, items = #items, saved = false })
        return items
    end
    recordName(self, store, npc)
    store.merchants[npc] = store.merchants[npc] or {}
    local saved, now, changed, extended, unread = store.merchants[npc], epoch(), 0, {}, 0
    for _, entry in ipairs(items) do
        if entry.itemID then
            local old = saved[entry.itemID]
            if not (sameEntry(old, entry, { "price", "count", "stock" }) and sameCosts(old.currency, entry.currency)
                and sameCosts(old.items, entry.items)) then
                changed = changed + 1
                if entry.currency or entry.items then
                    table.insert(extended, { item = entry.itemID, name = entry.name, price = entry.price,
                        currency = entry.currency, items = entry.items })
                end
            end
            saved[entry.itemID] = { price = entry.price, count = entry.count, stock = entry.stock,
                currency = entry.currency, items = entry.items, seen = now }
        else
            unread = unread + 1
        end
    end
    if changed > 0 or unread > 0 then
        logProf("merchant", { npc = npc, items = #items, changed = changed, unread = unread > 0 and unread or nil,
            extended = #extended > 0 and extended or nil })
    end
    if changed > 0 then self:ProfessionChanged("merchant", npc, saved) end
    return items
end

-- Auctionator ---------------------------------------------------------------------
--
-- Auction prices come from Auctionator when it is installed, through its
-- public API (`Auctionator.API.v1`), never its saved data. The one exception
-- is its internal event bus, for when a full scan ends, which its API does
-- not say (WatchAuctionatorFullScans). Otherwise an auction house visit bumps
-- the book's revision (the events below), so the planner replans after one.

local AUCTIONATOR_CALLER = "NuuProfessions"

-- Auctionator's v1 API table when it has the price call, else nil.
function Client:GetAuctionatorAPI()
    local auctionator = global("Auctionator")
    local api = type(auctionator) == "table" and type(auctionator.API) == "table" and auctionator.API.v1
    if type(api) ~= "table" or type(api.GetAuctionPriceByItemID) ~= "function" then return nil end
    return api
end

-- When the player last ran a full scan with Auctionator, per realm, as
-- Auctionator's prices are: `book.auctionScan[realm] = time()`. Its API has
-- no such thing; its internal event bus says when a full scan is done, after
-- every price of it is written, and takes any listener with a ReceiveEvent
-- method. Which scan its Full scan button runs depends on the client's
-- auction house: on Forever, the modern one's browse scan
-- (IncrementalScan.Events.ScanComplete, fired only for a full scan, never a
-- search); on the old auction house, a get-all query
-- (FullScan.Events.ScanComplete). Both are listened for, those there are. That
-- is looked for: without either, no scan time, and an auction house visit
-- still replans. A scan done tells the planner as an auction house visit
-- does ("auction", "scanned").
local SCAN_SOURCES = { "IncrementalScan", "FullScan" }

function Client:WatchAuctionatorFullScans()
    local auctionator = global("Auctionator")
    local bus = type(auctionator) == "table" and auctionator.EventBus
    local events = {}
    for _, name in ipairs(SCAN_SOURCES) do
        local source = type(auctionator) == "table" and auctionator[name]
        local event = type(source) == "table" and type(source.Events) == "table" and source.Events.ScanComplete
        if type(event) == "string" then events[#events + 1] = event end
    end
    if self.fullScansWatched or type(bus) ~= "table" or type(bus.Register) ~= "function" or #events == 0 then return false end
    local listener = { ReceiveEvent = function()
        local book, clock = ns.db and ns.db.professions, global("time")
        if type(book) == "table" and type(clock) == "function" then
            book.auctionScan = book.auctionScan or {}
            book.auctionScan[self:Read(global("GetRealmName")) or "?"] = clock()
        end
        self:ProfessionChanged("auction", "scanned")
    end }
    if not pcall(bus.Register, bus, listener, events) then return false end
    self.fullScansWatched = true
    return true
end

-- When the last full Auctionator scan on this realm ended (time()), or nil.
function Client:LastAuctionScan()
    local book = ns.db and ns.db.professions
    local scans = type(book) == "table" and book.auctionScan
    local at = type(scans) == "table" and scans[self:Read(global("GetRealmName")) or "?"]
    return type(at) == "number" and at or nil
end

-- Auctionator's price for one item (copper, the lowest buyout per item it
-- saw) and its age in days (nil past 21 days or when it will not say). nil
-- when Auctionator or its API is missing, or it has no price.
function Client:GetAuctionatorPrice(itemID)
    itemID = tonumber(itemID)
    local api = itemID and self:GetAuctionatorAPI()
    if not api then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, AUCTIONATOR_CALLER, itemID)
    price = ok and plainNumber(price) or nil
    if not price or price <= 0 then return nil end
    local age
    if type(api.GetAuctionAgeByItemID) == "function" then
        local okAge, days = pcall(api.GetAuctionAgeByItemID, AUCTIONATOR_CALLER, itemID)
        age = okAge and plainNumber(days) or nil
    end
    return price, age
end

-- Events --------------------------------------------------------------------------

-- The windows update in bursts (every craft, every item that arrives from the
-- server), so a read waits for the burst to settle.
local SETTLE = 0.5

function Client:ScheduleProfessionRead(kind)
    self.professionPending = self.professionPending or {}
    if self.professionPending[kind] then return end
    local run = function()
        self.professionPending[kind] = nil
        if kind == "trainer" then self:RecordTrainer()
        elseif kind == "merchant" then self:RecordMerchant()
        elseif self.professionWindow then self:ScanTradeSkill(self.professionWindow) end
    end
    local timer = global("C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        self.professionPending[kind] = true
        if not pcall(timer.After, SETTLE, run) then run() end
    else
        run()
    end
end

local PROFESSION_EVENTS = {
    TRADE_SKILL_SHOW = "tradeskill", TRADE_SKILL_UPDATE = "tradeskill", TRADE_SKILL_LIST_UPDATE = "tradeskill",
    TRADE_SKILL_DATA_SOURCE_CHANGED = "tradeskill", CRAFT_SHOW = "craft", CRAFT_UPDATE = "craft",
    TRADE_SKILL_CLOSE = "close", CRAFT_CLOSE = "close",
    TRAINER_SHOW = "trainer", TRAINER_UPDATE = "trainer", MERCHANT_SHOW = "merchant", MERCHANT_UPDATE = "merchant",
    MERCHANT_CLOSED = "merchantClosed", TRAINER_CLOSED = "trainerClosed",
    NEW_RECIPE_LEARNED = "learned", CHAT_MSG_SYSTEM = "system", CHAT_MSG_LOOT = "loot",
    AUCTION_HOUSE_SHOW = "auction", AUCTION_HOUSE_CLOSED = "auction",
}

-- The recipe named by the client's "You have learned how to create a new
-- item: %s." line (its global string, so any locale), or nil.
function Client.MatchLearnMessage(format, message)
    format, message = plainString(format), plainString(message)
    if not format or not message then return nil end
    local pattern = format:gsub("[%%%.%(%)%[%]%-%+%*%?%^%$]", "%%%0")
    pattern = pattern:gsub("%%%%s", "(.+)")
    return message:match("^" .. pattern .. "$")
end

-- "You create: [Rough Sharpening Stone]x5." is the only word the client gives
-- that a craft happened: the item made and how many, or nil. The client's
-- own wording up to the item link decides (LOOT_ITEM_CREATED_SELF), so the
-- locale does and a "You receive loot:" line is never taken for a craft.
function Client.MatchCraftMessage(format, message)
    message = plainString(message)
    if not message then return nil end
    local prefix = plainString(format) and format:match("^(.-)%%s") or "You create"
    if prefix == "" or message:sub(1, #prefix) ~= prefix then return nil end
    local itemID = tonumber(message:match("|Hitem:(%d+)"))
    if not itemID then return nil end
    return itemID, tonumber(message:match("|h|r[xX](%d+)")) or 1
end

function Client:OnProfessionEvent(event, ...)
    local kind = PROFESSION_EVENTS[event]
    if kind == "tradeskill" or kind == "craft" then
        -- An update with no window open (a skill-up elsewhere) has nothing to read.
        local shown = event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW"
        if shown then self.professionWindow, self.windowShown = kind, true end
        if self.professionWindow then
            self:CheckCraftStop()
            self:ScheduleProfessionRead("window")
        end
        -- The Make buttons follow the window open and shut; a window opened
        -- for a recipe selects it.
        if shown then
            self:ProfessionChanged("window", kind)
            self:ScheduleFocus()
        end
    elseif kind == "close" then
        self.professionWindow, self.craftUntil = nil, nil
        self:ProfessionChanged("window", "closed")
    elseif kind == "trainer" or kind == "merchant" then
        if event == "TRAINER_SHOW" or event == "MERCHANT_SHOW" then self[kind .. "Open"] = true end
        if self[kind .. "Open"] then self:ScheduleProfessionRead(kind) end
    elseif kind == "merchantClosed" then
        self.merchantOpen = nil
    elseif kind == "trainerClosed" then
        self.trainerOpen = nil
    elseif kind == "learned" then
        local spell = plainNumber((...))
        local profession, key = self:MarkRecipeLearned(spell, nil)
        logProf("learned", { spell = spell, profession = profession, key = key })
        if self.professionWindow then self:ScheduleProfessionRead("window") end
    elseif kind == "system" then
        local learned = Client.MatchLearnMessage(global("ERR_LEARN_RECIPE_S"), (...))
        if learned then
            local profession, key = self:MarkRecipeLearned(nil, learned)
            logProf("learned", { name = learned, profession = profession, key = key })
        end
    elseif kind == "loot" then
        local itemID, count = Client.MatchCraftMessage(global("LOOT_ITEM_CREATED_SELF"), (...))
        if itemID then self:ProfessionChanged("crafted", itemID, count) end
    elseif kind == "auction" then
        logProf("auction", { window = event == "AUCTION_HOUSE_CLOSED" and "closed" or "shown",
            auctionator = self:GetAuctionatorAPI() ~= nil })
        self:ProfessionChanged("auction", event == "AUCTION_HOUSE_CLOSED" and "closed" or "shown")
    end
end

function Client:WatchProfessionWindows()
    if self.professionFrame or type(global("CreateFrame")) ~= "function" then return end
    local ok, frame = pcall(CreateFrame, "Frame")
    if not ok or not frame or not frame.SetScript then return end
    for event in pairs(PROFESSION_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
    pcall(frame.SetScript, frame, "OnEvent", function(_, event, ...) self:OnProfessionEvent(event, ...) end)
    self.professionFrame = frame
end

function Client:GetDiagnostics()
    return self.build, self.capabilities
end

-- False for everything until Initialize has looked (PLAYER_LOGIN).
function Client:Has(capability)
    return self.capabilities ~= nil and self.capabilities[capability] == true
end

function Client:GetDiagnosticLines()
    local build = self.build or {}
    local lines = {
        "Build " .. tostring(build.version) .. " (" .. tostring(build.build) .. ")",
        "Date " .. tostring(build.date) .. " - TOC " .. tostring(build.toc),
        "Detected symbols are not verified Forever support. Run the smoke checklist before enabling an integration.",
        "Saved data sessions: " .. tostring(ns.db and ns.db.sessionCount or "?") .. " (stays at 1 when the client never restores SavedVariables)",
    }
    local names = {}
    for name in pairs(self.capabilities) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        table.insert(lines, name .. ": " .. (self.capabilities[name] and "detected - unverified" or "not detected - manual fallback"))
    end
    return lines
end

ns:RegisterModule("Client", Client)
