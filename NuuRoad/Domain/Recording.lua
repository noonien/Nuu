local _, ns = ...

-- The play recorder: what the player did, in the order they did it, written to
-- the `rec` channel of the session log (ns.recorder, the kit's recorder) as
-- material for writing a guide.
--
-- It is off until the player turns it on, and with it off every event handler
-- here returns on its first line: nothing is watched, nothing is read, and
-- nothing is written. What it records is a record of somebody's own play, so
-- it is theirs to start.
--
-- Nothing here decides anything. No row is acted on, no step is advanced, no
-- guide is written. A row is what the client said happened and where the
-- player was standing when it said so; turning a session into a guide is the
-- author's work afterwards, in the editor.
--
-- There are no breadcrumbs and nothing samples a position on a timer. Every
-- row carries its own place because every row is written with `RecordHere`,
-- so travel is read afterwards out of the gap between two rows. A route made
-- of positions nobody asked for is a route nobody can read, and it is most of
-- the bytes. Zone and subzone changes are not rows either: they come and go
-- with every road crossed, and the map on each row already says where it was.
--
-- What is worth a row is what a guide step would say: a quest accepted, an
-- objective that moved, a quest item looted, a creature killed, an NPC talked
-- to, a flight taken. Loot is filtered at the moment it is
-- seen - a quest item, or an item a quest in the log names - because a guide
-- never says "loot 14 Linen Cloth" and a session that recorded every grey
-- would bury the eight rows that matter.
--
-- The quest log's own objective lines are the primary signal. They count
-- kills, pickups, escorts and events alike, they are the same in every client,
-- and they are the one thing that never has to guess which creature the
-- player was fighting. The death of the player's own target is a hint on top
-- of that, for the creature ID the objective line does not carry.
--
-- Pure apart from the Client reads, so a session's rows can be built and
-- described outside the game.
local Recording = { listeners = {} }

local TALK_MEMORY = 2 -- seconds before the same dialog with the same NPC is a second row
local LOOT_MEMORY = 6 -- seconds a looted item is remembered so the chat line does not double it
local TAXI_MEMORY = 30 -- seconds a flight master's node stands as the takeoff point
local HEARTHSTONE_SPELL = 8690

local function now() return GetTime and GetTime() or 0 end

local function client() return ns.modules.Client end

function Recording:Enabled()
    return ns.modules.Config:Get("recording.enabled") == true
end

-- The session's rows, which is whatever the `rec` channel holds. There is no
-- second store: the UI reads what the tools will read.
function Recording:Rows()
    local rows = ns.recorder and ns.recorder:Records("rec")
    return rows or {}
end

function Recording:OnChange(callback)
    if type(callback) ~= "function" then return end
    table.insert(self.listeners, callback)
end

function Recording:Changed()
    for _, callback in ipairs(self.listeners) do pcall(callback) end
end

-- The one write path. Everything that produces a row comes through here, so
-- the panel watching the session hears every one of them.
function Recording:Write(row)
    if not self:Enabled() or type(row) ~= "table" then return nil end
    local record = ns:RecordHere("rec", row)
    self:Changed()
    return record
end

-- Starting and stopping. The row saying which is written while the setting
-- still allows it, so a session always carries the moment it began recording.
function Recording:SetEnabled(flag)
    flag = flag and true or false
    if flag then
        self:Forget()
        ns.modules.Config:Set("recording.enabled", true)
        self:Write({ event = "recording", on = true })
        self:Seed()
    else
        self:Write({ event = "recording", on = false })
        ns.modules.Config:Set("recording.enabled", false)
    end
    self:Changed()
    return flag
end

-- Everything the recorder remembers between rows. Cleared whenever it is
-- turned on, so a second run in one session never reads the first one's state.
function Recording:Forget()
    self.objectives, self.offer, self.reward, self.turnedIn = nil, nil, nil, nil
    self.recentLoot, self.recentTalk = nil, nil
    self.merchant, self.merchantPending, self.trainer, self.trainerPending = nil, nil, nil, nil
    self.taxiNode, self.taxiAt, self.flight = nil, nil, nil
    self.lastMap, self.jumpAt = nil, nil
end

-- What the world already looks like at the moment recording starts, taken
-- without writing a row for any of it: the quests in the log and their
-- objective counts. Without this the first
-- look at the log would write a tick for every objective of every quest.
function Recording:Seed()
    self.objectives = {}
    self.lastMap = client():GetCurrentMapID()
    self.questLogPending = true
    self:ScanObjectives()
end


-- Quests. The dialog text is stashed while the window is open and spent on the
-- row the client's own event writes, because QUEST_ACCEPTED arrives after the
-- window has closed and the words are gone by then.
function Recording:OnQuestDetail()
    if not self:Enabled() then return end
    local Client = client()
    local title, text, objectiveText = Client:GetQuestOfferText()
    self.offer = {
        quest = Client:GetOpenQuestID(),
        title = title, text = text, objectiveText = objectiveText,
        npc = Client:GetUnitCreatureID("npc"), npcName = Client:GetUnitName("npc"),
    }
    self:Talk("detail")
end

function Recording:OnQuestAccepted(questID)
    if not self:Enabled() then return end
    questID = tonumber(questID)
    local offer = self.offer or {}
    local row = { event = "accept", quest = questID or offer.quest }
    if not offer.quest or not questID or offer.quest == questID then
        row.npc, row.npcName = offer.npc, offer.npcName
        row.title, row.text, row.objectiveText = offer.title, offer.text, offer.objectiveText
    end
    row.npc = row.npc or client():GetUnitCreatureID("target")
    self.offer = nil
    self:Write(row)
end

function Recording:OnQuestProgress()
    if not self:Enabled() then return end
    local Client = client()
    self:Talk("progress")
    self.reward = {
        quest = Client:GetOpenQuestID(),
        progressText = Client:GetQuestProgressText(),
        npc = Client:GetUnitCreatureID("npc"), npcName = Client:GetUnitName("npc"),
    }
end

function Recording:OnQuestComplete()
    if not self:Enabled() then return end
    local Client = client()
    self:Talk("complete")
    local reward = self.reward or {}
    self.reward = {
        quest = Client:GetOpenQuestID() or reward.quest,
        progressText = reward.progressText,
        rewardText = Client:GetQuestRewardText(),
        npc = Client:GetUnitCreatureID("npc") or reward.npc,
        npcName = Client:GetUnitName("npc") or reward.npcName,
    }
end

-- Which reward the player picked, read off the UI's own call. It is data about
-- what they chose, never a choice the addon makes or repeats.
function Recording:OnRewardChosen(choice)
    if not self:Enabled() then return end
    choice = tonumber(choice)
    if not choice or choice < 1 then return end
    self.reward = self.reward or {}
    self.reward.choice = choice
    self.reward.item = (client():GetQuestRewardChoice(choice))
end

function Recording:OnQuestTurnedIn(questID)
    if not self:Enabled() then return end
    questID = tonumber(questID)
    local reward = self.reward or {}
    local row = { event = "turnin", quest = questID or reward.quest }
    if not reward.quest or not questID or reward.quest == questID then
        row.npc, row.npcName = reward.npc, reward.npcName
        row.rewardText, row.progressText = reward.rewardText, reward.progressText
        row.rewardChoice, row.rewardItem = reward.choice, reward.item
    end
    row.npc = row.npc or client():GetUnitCreatureID("target")
    self.reward = nil
    self.turnedIn = self.turnedIn or {}
    if row.quest then self.turnedIn[row.quest] = now() end
    self:Write(row)
end

-- A quest leaving the log is an abandon unless it left because it was just
-- handed in, which the client reports as the same removal a moment later.
function Recording:OnQuestRemoved(questID)
    if not self:Enabled() then return end
    questID = tonumber(questID)
    if not questID then return end
    local turnedIn = (self.turnedIn or {})[questID]
    if self.objectives then self.objectives[questID] = nil end
    if turnedIn and now() - turnedIn < 30 then return end
    self:Write({ event = "abandon", quest = questID })
end

-- The quest log's objective lines, compared with the last look. A line that
-- moved is progress made where the player is standing now, whatever made it
-- move. A quest seen for the first time only sets the baseline: accepting a
-- quest with five objectives must not read as five things done.
function Recording:ScanObjectives()
    if not self:Enabled() then return end
    local Client = client()
    self.objectives = self.objectives or {}
    local present = {}
    for _, entry in ipairs(Client:GetQuestLogEntries()) do
        local questID = entry.questID
        present[questID] = true
        local known = self.objectives[questID]
        local seeding = known == nil
        known = known or {}
        for part, objective in ipairs(Client:GetQuestObjectives(questID)) do
            local done = objective.finished == true
            local before = known[part]
            local moved = before == nil or before.have ~= objective.have or before.done ~= done
            if not seeding and moved then
                self:Write({ event = "objective", quest = questID, part = part, type = objective.type,
                    text = objective.text, have = objective.have, need = objective.need, done = done })
            end
            known[part] = { have = objective.have, need = objective.need, done = done }
        end
        self.objectives[questID] = known
    end
    for questID in pairs(self.objectives) do
        if not present[questID] then self.objectives[questID] = nil end
    end
    if self.questLogPending and next(present) then
        self.questLogPending = nil
        self:WriteQuestLog()
    end
end

-- The whole quest log, once, when recording starts. The ticks that follow
-- only say what moved; without this a reader could not tell which quests the
-- player was already carrying, or how far along each one stood. At login the
-- log arrives a moment after the addon does, so the row waits for the first
-- scan that finds anything in it.
function Recording:WriteQuestLog()
    local Client = client()
    local quests = {}
    for _, entry in ipairs(Client:GetQuestLogEntries()) do
        local quest = { quest = entry.questID, title = entry.title, objectives = {} }
        -- The words too, as an accept row carries them, since a quest picked
        -- up before recording began has no accept row to carry them.
        if Client.GetQuestLogText then
            quest.text, quest.objectiveText = Client:GetQuestLogText(entry.questID)
        end
        for part, objective in ipairs(Client:GetQuestObjectives(entry.questID)) do
            table.insert(quest.objectives, { part = part, type = objective.type, text = objective.text,
                have = objective.have, need = objective.need, done = objective.finished == true })
        end
        table.insert(quests, quest)
    end
    self:Write({ event = "questlog", count = #quests, quests = quests })
end


-- Loot. Only what a guide would ever ask for: what the game itself flags as a
-- quest item, and what a quest in the log names in one of its objective lines.
-- Everything else is the ordinary take of playing and is dropped where it is
-- seen rather than filtered afterwards, because a row kept is a row somebody
-- has to read.
function Recording:QuestForItemName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local Client = client()
    local needle = name:lower()
    for _, entry in ipairs(Client:GetQuestLogEntries()) do
        for _, objective in ipairs(Client:GetQuestObjectives(entry.questID)) do
            local text = type(objective.text) == "string" and objective.text:lower() or nil
            if text and text:find(needle, 1, true) then return entry.questID end
        end
    end
    return nil
end

function Recording:LootKey(itemID, name, count)
    return tostring(itemID or name or "?") .. "x" .. tostring(count or 1)
end

-- Whether this item and count has just been recorded from the loot window, so
-- the chat line that follows it does not write the same pickup twice.
function Recording:SeenLoot(key, remember)
    self.recentLoot = self.recentLoot or {}
    local time = now()
    for known, seen in pairs(self.recentLoot) do
        if time - seen > LOOT_MEMORY then self.recentLoot[known] = nil end
    end
    local seen = self.recentLoot[key] ~= nil
    if remember then self.recentLoot[key] = time end
    return seen
end

function Recording:OnLootOpened()
    if not self:Enabled() then return end
    for _, slot in ipairs(client():GetLootSlots()) do
        local quest = self:QuestForItemName(slot.name)
        if slot.questItem or quest then
            local key = self:LootKey(slot.itemID, slot.name, slot.count)
            self:SeenLoot(key, true)
            local row = { event = "loot", item = slot.itemID, name = slot.name, count = slot.count,
                questItem = slot.questItem or nil, quest = quest }
            if slot.from then
                row.from, row.fromKind = slot.from, slot.fromKind
                row.fromName = slot.fromKind == "Creature" and ns.modules.Names and ns.modules.Names:NPC(slot.from) or nil
            end
            self:Write(row)
        end
    end
end

-- The client's own loot and craft chat lines, which are all there is when the
-- loot window never opened (autoloot) or when the item was made rather than
-- taken. Same filter, and the same pickup is never written twice.
function Recording:OnChatLoot(message)
    if not self:Enabled() or type(message) ~= "string" then return end
    local itemID = tonumber(message:match("|Hitem:(%d+)"))
    local name = message:match("|h%[(.-)%]|h")
    if not itemID and not name then return end
    local count = tonumber(message:match("|h%s*x%s*(%d+)")) or tonumber(message:match("x(%d+)%.?$")) or 1
    local created = _G.LOOT_ITEM_CREATED_SELF
    local prefix = type(created) == "string" and created:match("^(.-)%%s") or "You create"
    local crafted = prefix ~= "" and message:sub(1, #prefix) == prefix
    local quest = self:QuestForItemName(name)
    if not quest then return end
    local key = self:LootKey(itemID, name, count)
    if not crafted and self:SeenLoot(key, true) then return end
    if crafted then self:SeenLoot(key, true) end
    self:Write({ event = crafted and "craft" or "loot", item = itemID, name = name, count = count,
        quest = quest, source = not crafted and "chat" or nil })
end


-- A kill, which the client will only tell us about through the death of the
-- player's own target. The objective line is what counts the kill; this row is
-- what says which creature it was.
function Recording:OnTargetDied(guid, npcID, name)
    if not self:Enabled() then return end
    npcID = tonumber(npcID)
    if not npcID then return end
    self:Write({ event = "kill", npc = npcID, name = name, seen = "target" })
end


-- One row per dialog opened, so a guide can be written with the NPC the
-- player actually talked to rather than the one standing nearest. Opening the
-- same window twice in a breath is one visit.
function Recording:Talk(kind)
    if not self:Enabled() then return end
    local Client = client()
    local npc = Client:GetUnitCreatureID("npc") or Client:GetUnitCreatureID("target")
    if not npc then return end
    self.recentTalk = self.recentTalk or {}
    local key = kind .. ":" .. tostring(npc)
    local time = now()
    for known, seen in pairs(self.recentTalk) do
        if time - seen > TALK_MEMORY then self.recentTalk[known] = nil end
    end
    if self.recentTalk[key] then return end
    self.recentTalk[key] = time
    self:Write({ event = "talk", kind = kind, npc = npc, name = Client:GetUnitName("npc") or Client:GetUnitName("target") })
end


-- Merchants and trainers say nothing about what changed hands, so the bags,
-- the purse and the skill ranks are read when the window opens and read again
-- once the client has settled after it closes. The difference is the visit.
function Recording:BagCounts()
    local Client, counts = client(), {}
    for _, item in ipairs(Client:GetBagItems()) do
        if counts[item.itemID] == nil then counts[item.itemID] = Client:GetItemCount(item.itemID) end
    end
    return counts
end

function Recording:OnMerchantShow()
    if not self:Enabled() then return end
    self:FlushMerchant()
    local Client = client()
    self:Talk("merchant")
    self.merchant = { npc = Client:GetUnitCreatureID("npc"), items = self:BagCounts(), money = Client:GetMoney() }
end

function Recording:OnMerchantClosed()
    if not self:Enabled() then return end
    self.merchantPending, self.merchant = self.merchant, nil
end

function Recording:FlushMerchant()
    local before = self.merchantPending
    self.merchantPending = nil
    if not before or not self:Enabled() then return end
    local Client = client()
    local after = self:BagCounts()
    local moved = false
    local ids = {}
    for itemID in pairs(before.items) do ids[itemID] = true end
    for itemID in pairs(after) do ids[itemID] = true end
    for itemID in pairs(ids) do
        local delta = (after[itemID] or 0) - (before.items[itemID] or 0)
        if delta > 0 then
            moved = true
            self:Write({ event = "buy", item = itemID, count = delta, npc = before.npc })
        elseif delta < 0 then
            moved = true
            self:Write({ event = "sell", item = itemID, count = -delta, npc = before.npc })
        end
    end
    -- Money gone with nothing carried away is a repair, which is the only
    -- thing a merchant takes payment for without handing anything over.
    local money = Client:GetMoney()
    if not moved and type(money) == "number" and type(before.money) == "number" and money < before.money then
        self:Write({ event = "repair", copper = before.money - money, npc = before.npc })
    end
end

function Recording:OnTrainerShow()
    if not self:Enabled() then return end
    self:FlushTrainer()
    local Client = client()
    self:Talk("trainer")
    self.trainer = { npc = Client:GetUnitCreatureID("npc"), ranks = Client:GetSkillRanks() }
end

function Recording:OnTrainerClosed()
    if not self:Enabled() then return end
    self.trainerPending, self.trainer = self.trainer, nil
end

function Recording:FlushTrainer()
    local before = self.trainerPending
    self.trainerPending = nil
    if not before or not self:Enabled() then return end
    local after = client():GetSkillRanks()
    for skill, rank in pairs(after) do
        local was = before.ranks[skill]
        if was == nil or rank > was then
            self:Write({ event = "train", skill = skill, rankBefore = was or 0, rankAfter = rank, npc = before.npc })
        end
    end
end


-- Flights. The taxi map names the node the player is standing on, which is the
-- only word the client gives for where a flight started; the landing is the
-- moment control comes back with the zone underneath.
function Recording:OnTaxiMap()
    if not self:Enabled() then return end
    self:Talk("taxi")
    local node = client():GetCurrentTaxiNodeName()
    if not node then return end
    self.taxiNode, self.taxiAt = node, now()
    self:Write({ event = "flightpath", node = node })
end

function Recording:OnControlLost()
    if not self:Enabled() then return end
    if not self.taxiNode or now() - (self.taxiAt or 0) > TAXI_MEMORY then return end
    local record = self:Write({ event = "flight", from = self.taxiNode })
    self.flight = { from = self.taxiNode, record = record }
    self.taxiNode, self.taxiAt = nil, nil
end

function Recording:OnControlGained()
    if not self:Enabled() then return end
    local flight = self.flight
    if not flight or client():IsOnTaxi() then return end
    self.flight = nil
    local node = client():GetSubzone() or client():GetZoneName()
    -- The takeoff row is where the flight is read from, so the destination is
    -- written back onto it rather than left for a reader to pair up.
    if node and type(flight.record) == "table" and type(flight.record.d) == "table" then flight.record.d.to = node end
    self:Write({ event = "flightend", node = node, from = flight.from })
end


-- Doorways. The client's map changes as the player walks through a city
-- gate or a mountain pass, so a change on foot marks one: the row's own
-- position is the doorway. `Tools/SessionLog/doors.py` gathers these into
-- candidate doors for Data/Travel.lua. A change after a taxi, a teleport, or
-- a loading screen is travel, not a doorway, and is not written.
local JUMP_MEMORY = 10 -- seconds after a loading screen or a teleport cast

function Recording:OnMapChanged()
    local Client = client()
    local map = Client:GetCurrentMapID()
    local last = self.lastMap
    if map then self.lastMap = map end
    if not map or not last or map == last then return end
    if Client:IsOnTaxi() or now() - (self.jumpAt or -JUMP_MEMORY) < JUMP_MEMORY then return end
    self:Write({ event = "door", from = last, to = map })
end

function Recording:OnJump()
    self.jumpAt = now()
    self.lastMap = client():GetCurrentMapID() or self.lastMap
end

-- Casts. `UNIT_SPELLCAST_SUCCEEDED` is a unit event, not the combat log, so it
-- is allowed here; the spell ID may still come back secret, which reads as no
-- cast at all. A cast is only worth a row when it is the hearthstone or when a
-- carried item is what cast it, which is what a guide step would say.
function Recording:OnSpellCast(...)
    if not self:Enabled() then return end
    local Client = client()
    if (...) ~= "player" then return end
    local spellID
    for index = 2, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "number" and not Client:IsSecret(value) then spellID = value end
    end
    if not spellID then return end
    if spellID == HEARTHSTONE_SPELL then
        self.jumpAt = now()
        self:Write({ event = "hearth", location = Client:GetBindLocation() })
        return
    end
    local itemID, name = Client:GetBagItemForSpell(spellID)
    if not itemID then return end
    self:Write({ event = "use", item = itemID, spell = spellID, name = name })
end

function Recording:OnHearthstoneBound()
    if not self:Enabled() then return end
    local Client = client()
    self:Write({ event = "hearthset", location = Client:GetBindLocation(), npc = Client:GetUnitCreatureID("npc") })
end

function Recording:OnEquipmentChanged(slot)
    if not self:Enabled() then return end
    slot = tonumber(slot)
    if not slot then return end
    local itemID = client():GetEquippedItemID(slot)
    if not itemID then return end
    self:Write({ event = "equip", item = itemID, slot = slot })
end

function Recording:OnLevelUp(level)
    if not self:Enabled() then return end
    level = tonumber(level)
    if not level then return end
    self:Write({ event = "level", level = level })
end

function Recording:OnDeath()
    if not self:Enabled() then return end
    self:Write({ event = "death" })
end

function Recording:OnAlive()
    if not self:Enabled() then return end
    self:Write({ event = "alive", ghost = client():IsPlayerGhost() == true })
end


-- One row, as a step viewer line would show it, plus every field it carries
-- for a tooltip. Pure: it reads the row and the name tables and nothing else,
-- so a session can be read outside the game and in a test.
local kindWords = {
    gossip = "gossip", merchant = "merchant", trainer = "trainer", taxi = "flight master",
    bank = "bank", greeting = "quests", detail = "quest offer", progress = "quest progress",
    complete = "quest reward",
}

local function named(lookup, id, fallback)
    local Names = ns.modules.Names
    if type(id) == "number" and Names and type(Names[lookup]) == "function" then
        local ok, name = pcall(Names[lookup], Names, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if type(fallback) == "string" and fallback ~= "" then return fallback end
    if type(id) == "number" then return tostring(id) end
    return nil
end

local function money(copper)
    copper = tonumber(copper) or 0
    local gold, silver = math.floor(copper / 10000), math.floor((copper % 10000) / 100)
    local parts = {}
    if gold > 0 then table.insert(parts, gold .. "g") end
    if gold > 0 or silver > 0 then table.insert(parts, silver .. "s") end
    table.insert(parts, (copper % 100) .. "c")
    return table.concat(parts, " ")
end

local function counted(name, count)
    return name .. " x" .. (tonumber(count) or 1)
end

local function value(field)
    if type(field) == "table" then
        local parts = {}
        for _, entry in ipairs(field) do table.insert(parts, tostring(entry)) end
        if #parts > 0 then return table.concat(parts, ", ") end
        return "{}"
    end
    return tostring(field)
end

function Recording:Describe(record)
    local data = type(record) == "table" and record.d or nil
    if type(data) ~= "table" then data = {} end
    local event = type(data.event) == "string" and data.event or "unknown"
    local quest = type(data.quest) == "number" and data.quest or nil
    local npc = type(data.npc) == "number" and data.npc or nil
    local item = type(data.item) == "number" and data.item or nil
    local questName = quest and named("Quest", quest, data.title) or data.title
    local itemName = (item or data.name) and named("Item", item, data.name) or nil
    local npcName = (npc or data.npcName) and named("NPC", npc, data.npcName or data.name) or nil

    local text
    if event == "accept" then
        text = "Accept: " .. tostring(questName or quest or "a quest")
    elseif event == "turnin" then
        text = "Turn in: " .. tostring(questName or quest or "a quest")
    elseif event == "abandon" then
        text = "Abandon: " .. tostring(questName or quest or "a quest")
    elseif event == "objective" then
        local label = type(data.text) == "string" and data.text or (questName or "objective")
        if type(data.have) == "number" and type(data.need) == "number" then
            label = label:gsub(":?%s*%d+%s*/%s*%d+%s*$", "")
            text = label .. " " .. data.have .. "/" .. data.need
        else
            text = label .. (data.done and " (done)" or "")
        end
    elseif event == "loot" then
        text = "Loot: " .. counted(itemName or "an item", data.count)
        if data.fromName or data.from then text = text .. " from " .. tostring(data.fromName or named("NPC", data.from)) end
    elseif event == "craft" then
        text = "Craft: " .. counted(itemName or "an item", data.count)
    elseif event == "kill" then
        text = "Killed: " .. tostring(npcName or named("NPC", npc, data.name) or "a creature")
    elseif event == "talk" then
        text = "Talk: " .. tostring(npcName or "an NPC")
        local word = kindWords[data.kind]
        if word then text = text .. " (" .. word .. ")" end
    elseif event == "buy" then
        text = "Buy: " .. counted(itemName or "an item", data.count)
    elseif event == "sell" then
        text = "Sell: " .. counted(itemName or "an item", data.count)
    elseif event == "repair" then
        text = "Repair: " .. money(data.copper)
    elseif event == "train" then
        if type(data.skill) == "string" then
            text = "Train: " .. data.skill .. " " .. tostring(data.rankBefore or 0) .. " > " .. tostring(data.rankAfter or 0)
        else
            text = "Train: " .. tostring(data.name or data.spell or "a spell")
        end
    elseif event == "flightpath" then
        text = "Flight path: " .. tostring(data.node or "a flight master")
    elseif event == "flight" then
        text = "Fly: " .. tostring(data.from or "?") .. " > " .. tostring(data.to or "?")
    elseif event == "flightend" then
        text = "Landed: " .. tostring(data.node or "?")
    elseif event == "hearthset" then
        text = "Hearth set: " .. tostring(data.location or "?")
    elseif event == "door" then
        text = "Doorway: map " .. tostring(data.from or "?") .. " > " .. tostring(data.to or "?")
    elseif event == "hearth" then
        text = "Hearth: " .. tostring(data.location or "?")
    elseif event == "use" then
        text = "Use: " .. tostring(itemName or data.name or data.spell or "an item")
    elseif event == "equip" then
        text = "Equip: " .. tostring(itemName or "an item")
    elseif event == "level" then
        text = "Level " .. tostring(data.level or "?")
    elseif event == "death" then
        text = "Died"
    elseif event == "alive" then
        text = data.ghost and "Released" or "Alive"
    elseif event == "recording" then
        text = data.on and "Recording on" or "Recording off"
    elseif event == "questlog" then
        local count = type(data.count) == "number" and data.count or (type(data.quests) == "table" and #data.quests or 0)
        text = "Quest log: " .. count .. (count == 1 and " quest" or " quests")
    else
        text = event
        if questName then text = text .. ": " .. questName
        elseif npcName then text = text .. ": " .. npcName
        elseif itemName then text = text .. ": " .. itemName end
    end

    local keys = {}
    for key in pairs(data) do
        if key ~= "event" then table.insert(keys, key) end
    end
    table.sort(keys)
    local detail = {}
    -- A quest log snapshot reads as one line per quest, the way the log
    -- itself reads, ahead of the rest rather than as a list of tables
    -- flattened to nothing.
    if type(data.quests) == "table" then
        for _, quest in ipairs(data.quests) do
            local line = tostring(named("Quest", quest.quest, quest.title) or quest.quest or "?")
            local parts = {}
            for _, objective in ipairs(quest.objectives or {}) do
                if type(objective.have) == "number" and type(objective.need) == "number" then
                    table.insert(parts, objective.have .. "/" .. objective.need)
                elseif objective.done then
                    table.insert(parts, "done")
                end
            end
            if #parts > 0 then line = line .. " (" .. table.concat(parts, ", ") .. ")" end
            table.insert(detail, line)
        end
    end
    for _, key in ipairs(keys) do
        if key ~= "quests" then table.insert(detail, key .. ": " .. value(data[key])) end
    end

    local time
    if type(record) == "table" and type(record.at) == "number" and type(date) == "function" then
        local ok, stamp = pcall(date, "%H:%M", record.at)
        if ok and type(stamp) == "string" then time = stamp end
    end

    return { kind = event, text = text, detail = detail, time = time, quest = quest, npc = npc, item = item }
end


function Recording:Initialize()
    local Client = client()
    if not Client or type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({
        "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
        "QUEST_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "LOOT_OPENED", "CHAT_MSG_LOOT",
        "GOSSIP_SHOW", "QUEST_GREETING", "MERCHANT_SHOW", "MERCHANT_CLOSED", "TRAINER_SHOW",
        "TRAINER_CLOSED", "BANKFRAME_OPENED", "TAXIMAP_OPENED", "PLAYER_CONTROL_LOST",
        "PLAYER_CONTROL_GAINED", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_LEVEL_UP", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_EQUIPMENT_CHANGED",
        "HEARTHSTONE_BOUND", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "SKILL_LINES_CHANGED",
        "LOADING_SCREEN_DISABLED", "PLAYER_ENTERING_WORLD",
    }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    -- A unit event, not the combat log: the client forbids the combat log to
    -- addons, and this one it allows.
    pcall(Client.RegisterUnitEvent, Client, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:SetScript("OnEvent", function(_, event, ...)
        if not self:Enabled() then return end
        if event == "QUEST_DETAIL" then self:OnQuestDetail()
        elseif event == "QUEST_PROGRESS" then self:OnQuestProgress()
        elseif event == "QUEST_COMPLETE" then self:OnQuestComplete()
        elseif event == "QUEST_ACCEPTED" then
            -- Classic passes (questLogIndex, questID); newer clients pass (questID).
            self:OnQuestAccepted(select(select("#", ...), ...))
        elseif event == "QUEST_TURNED_IN" then self:OnQuestTurnedIn((...))
        elseif event == "QUEST_REMOVED" then self:OnQuestRemoved((...))
        elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then self:ScanObjectives()
        elseif event == "LOOT_OPENED" then self:OnLootOpened()
        elseif event == "CHAT_MSG_LOOT" then self:OnChatLoot((...))
        elseif event == "GOSSIP_SHOW" then self:Talk("gossip")
        elseif event == "QUEST_GREETING" then self:Talk("greeting")
        elseif event == "BANKFRAME_OPENED" then self:Talk("bank")
        elseif event == "MERCHANT_SHOW" then self:OnMerchantShow()
        elseif event == "MERCHANT_CLOSED" then self:OnMerchantClosed()
        elseif event == "TRAINER_SHOW" then self:OnTrainerShow()
        elseif event == "TRAINER_CLOSED" then self:OnTrainerClosed()
        elseif event == "TAXIMAP_OPENED" then self:OnTaxiMap()
        elseif event == "PLAYER_CONTROL_LOST" then self:OnControlLost()
        elseif event == "PLAYER_CONTROL_GAINED" then self:OnControlGained()
        elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
            self:OnControlGained()
            self:OnMapChanged()
        elseif event == "LOADING_SCREEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" then self:OnJump()
        elseif event == "PLAYER_LEVEL_UP" then self:OnLevelUp((...))
        elseif event == "PLAYER_DEAD" then self:OnDeath()
        elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then self:OnAlive()
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then self:OnEquipmentChanged((...))
        elseif event == "HEARTHSTONE_BOUND" then self:OnHearthstoneBound()
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then self:OnSpellCast(...)
        elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" or event == "SKILL_LINES_CHANGED" then
            -- The bags and the skill window settle after a window closes, not
            -- while it is closing, so a visit is counted from here.
            self:FlushMerchant()
            self:FlushTrainer()
        end
    end)
    self.frame = frame
    -- Which reward was taken is only knowable from the UI's own call, so the
    -- hook is placed once and listens for the whole session.
    if Client.OnQuestRewardChosen then
        Client:OnQuestRewardChosen(function(choice) self:OnRewardChosen(choice) end)
    end
    if self:Enabled() then self:Seed() end
end

ns:RegisterModule("Recording", Recording)
