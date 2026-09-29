local _, ns = ...

-- Porting aid. The built-in guides were written against another expansion's
-- database, so IDs, coordinates, objective lines, and names may not match this
-- client. This module compares what the game reports against what the guide
-- says and reports every disagreement in chat, naming the value the client
-- actually uses whenever it can see one:
--
--   * a live name for a guide ID that is not the authored name (wrong ID);
--   * a target, mouseover, quest giver, quest in the log, or item in the bags
--     whose name the guide knows under a different ID (the right ID);
--   * a quest dialog whose title is not one the current step expects, or a
--     step's quest handled by an NPC other than the one the step names;
--   * a quest handled, an objective advanced, or an item picked up far from
--     the coordinates the step gives, or on another map;
--   * an objective step whose quest line is about something else, has a
--     different count, or does not exist (an object-click step only when the
--     object names another line of the same quest), or a kill step for a
--     line the client calls an item to loot;
--   * a hearthstone bound or a flight master met under another name;
--   * `/nuuroad audit`, which checks every quest, item, cached NPC, and
--     objective of the active guide at once, requesting uncached data.
--
-- Passive checks run only while the debug log is on. Each finding is printed
-- once per session and kept in SavedVariables; `/nuuroad log` shows them all
-- as plain text for copying.
local GuideAudit = { reported = {}, pending = { quests = {}, items = {} }, elapsed = 0, pollInterval = 5 }

local labels = { quests = "quest", npcs = "NPC", items = "item", factions = "faction", spells = "spell" }
local prefix = "|cffffb347[audit]|r "

local function normalizeName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if #name == 0 then return nil end
    return name
end

local function sameName(a, b)
    local left = normalizeName(a)
    return left ~= nil and left == normalizeName(b)
end

local function joinIDs(ids)
    local parts = {}
    for _, id in ipairs(ids) do table.insert(parts, tostring(id)) end
    return table.concat(parts, "/")
end

function GuideAudit:Enabled()
    return ns.modules.Config:Get("debug") == true
end

function GuideAudit:Authored(kind, id)
    local Names = ns.modules.Names
    local authored = Names and Names.authored
    return authored and authored[kind] and authored[kind][id] or nil
end

-- Every guide ID recorded under a name, so a live name can be traced back to
-- the ID the guide uses for it.
function GuideAudit:AuthoredIDsFor(kind, name)
    local key = normalizeName(name)
    if not key then return {} end
    self.index = self.index or {}
    if not self.index[kind] then
        local index = {}
        local Names = ns.modules.Names
        for id, authoredName in pairs(Names and Names.authored and Names.authored[kind] or {}) do
            local authoredKey = normalizeName(authoredName)
            if authoredKey then
                index[authoredKey] = index[authoredKey] or {}
                table.insert(index[authoredKey], id)
            end
        end
        for _, ids in pairs(index) do table.sort(ids) end
        self.index[kind] = index
    end
    return self.index[kind][key] or {}
end

-- "Orc Warrior 14": the details that decide which steps a character sees.
local function characterDescriptor()
    local race = UnitRace and (UnitRace("player")) or nil
    local class = UnitClass and (UnitClass("player")) or nil
    local level = UnitLevel and UnitLevel("player") or nil
    local parts = {}
    for _, part in ipairs({ race, class, level and tostring(level) }) do if part then table.insert(parts, part) end end
    return table.concat(parts, " ")
end

-- Findings persist in SavedVariables (NuuRoadDB.audit.findings), one entry
-- per distinct message, with the guide, step, character, and time it was seen,
-- so `/nuuroad log` can hand them over as plain text.
function GuideAudit:Findings()
    if not ns.db then return {} end
    ns.db.audit = ns.db.audit or {}
    ns.db.audit.findings = ns.db.audit.findings or {}
    return ns.db.audit.findings
end

function GuideAudit:Record(message)
    local findings = self:Findings()
    for _, finding in ipairs(findings) do
        if finding.text == message then return false end
    end
    local node, guide = self:CurrentNode()
    table.insert(findings, {
        text = message,
        at = date and date("%Y-%m-%d %H:%M") or "",
        guideID = guide and guide.id or nil,
        guideTitle = guide and guide.meta and guide.meta.title or nil,
        guideUpdated = guide and guide.updated or nil,
        step = node and node.index or nil,
        character = ns.modules.Config and ns.modules.Config.characterKey or nil,
        who = characterDescriptor(),
    })
    return true
end

-- `force` prints even when the debug log is off; the on-demand audit uses it.
function GuideAudit:Report(message, force)
    if not force and not self:Enabled() then return false end
    if self.reported[message] then return false end
    self.reported[message] = true
    self:Record(message)
    ns:Print(prefix .. message)
    return true
end

function GuideAudit:HeaderLine()
    local build = ns.modules.Client and ns.modules.Client.build or {}
    return string.format("NuuRoad %s | client %s (%s, %s, toc %s) | exported %s",
        tostring(ns.version or "?"), tostring(build.version or "?"), tostring(build.build or "?"), tostring(build.date or "?"), tostring(build.toc or "?"),
        date and date("%Y-%m-%d %H:%M") or "?")
end

-- Plain text grouped by guide, then by character, ready to paste anywhere:
--
--   NuuRoad 0.1.0-dev | client 1.15.8 (60000, Sep 1 2026, toc 11508) | exported 2026-09-19 14:02
--   Guide: Horde 13-21: The Barrens & Stonetalon (nuuroad:leveling:horde-barrens-13-21, updated 1789862400)
--     Grom-Whitemane (Orc Warrior 14)
--       09-19 14:02 @accept:870  quest 870 is 'The Zhevra' on this client, ...
function GuideAudit:ExportText()
    local findings = self:Findings()
    local lines = { self:HeaderLine() }
    if #findings == 0 then
        table.insert(lines, "No findings recorded yet. Turn on the debug log or run /nuuroad audit.")
        return table.concat(lines, "\n")
    end
    local guides, guideOrder = {}, {}
    for _, finding in ipairs(findings) do
        local guideKey = (finding.guideID or "-") .. "@" .. tostring(finding.guideUpdated or "-")
        local group = guides[guideKey]
        if not group then
            group = { finding = finding, characters = {}, characterOrder = {} }
            guides[guideKey] = group
            table.insert(guideOrder, guideKey)
        end
        local characterKey = finding.character or "unknown"
        local entries = group.characters[characterKey]
        if not entries then
            entries = { who = finding.who, list = {} }
            group.characters[characterKey] = entries
            table.insert(group.characterOrder, characterKey)
        end
        if finding.who and finding.who ~= "" then entries.who = finding.who end
        table.insert(entries.list, finding)
    end
    for _, guideKey in ipairs(guideOrder) do
        local group = guides[guideKey]
        local first = group.finding
        if first.guideID then
            table.insert(lines, string.format("Guide: %s (%s, updated %s)", first.guideTitle or first.guideID, first.guideID, tostring(first.guideUpdated or "?")))
        else
            table.insert(lines, "No active guide")
        end
        for _, characterKey in ipairs(group.characterOrder) do
            local entries = group.characters[characterKey]
            table.insert(lines, string.format("  %s%s", characterKey, entries.who and entries.who ~= "" and (" (" .. entries.who .. ")") or ""))
            for _, finding in ipairs(entries.list) do
                local when = (finding.at or ""):match("^%d%d%d%d%-(.+)$") or finding.at or ""
                table.insert(lines, string.format("    %s%s  %s", when, finding.step and (" @" .. finding.step) or "", finding.text))
            end
        end
    end
    return table.concat(lines, "\n")
end

function GuideAudit:ClearFindings()
    if ns.db and ns.db.audit then ns.db.audit.findings = {} end
    self.reported = {}
end

-- Copyable text window shared by `/nuuroad log`, `/nuuroad db` and the other
-- reports: a kit window with the text in a text area, so it can be selected
-- and copied (Ctrl+A, Ctrl+C). The area is read-only: anything typed into it
-- is undone by putting the text back. Made the first time a report is shown,
-- never at load (the saved variables, and so the window's place, are not in
-- yet), and kept for the session.
local TEXT_WIDTH, TEXT_HEIGHT = 560, 320

function GuideAudit:ShowText(title, text)
    self.logText = tostring(text or "")
    local window = self.logWindow
    if not window then
        local UI = ns:GetUI()
        window = UI:Window({
            key = "auditText",
            place = ns.db and ns.db.windows,
            title = title,
            subtitle = "Ctrl+A, Ctrl+C to copy",
            width = TEXT_WIDTH + 24,
        })
        local body = window:Column{ gap = 8, padding = 12 }
        self.logArea = body:TextArea{
            boxHeight = TEXT_HEIGHT,
            value = self.logText,
            onType = function(_, area) area:SetText(self.logText) end,
        }
        local buttons = body:Row{ align = "right", gap = 8 }
        self.logClear = buttons:Button{ "Clear findings",
            tooltip = "Empties the saved list of guide findings.",
            onClick = function() self:ClearFindings(); self:ShowLog() end }
        buttons:Button{ "Close", onClick = function() window:Hide() end }
        self.logWindow = window
    end
    window:SetTitle(title)
    self.logClear:SetShown(title == "Guide findings")
    self.logArea:SetText(self.logText)
    window:Show()
    self.logArea:SetFocus()
    -- The kit's text area selects nothing on focus (it is for writing); a
    -- report is for copying, so its text starts selected.
    local box = self.logArea.box
    if box and box.HighlightText then box:HighlightText() end
end

function GuideAudit:ShowLog()
    self:ShowText("Guide findings", self:ExportText())
end

function GuideAudit:ShowSavedData()
    local lines = ns.modules.Config:GetSavedDataLines()
    for _, line in ipairs(ns.modules.Client:GetDiagnosticLines()) do table.insert(lines, line) end
    self:ShowText("Saved data", table.concat(lines, "\n"))
end

-- The client's name for a guide ID disagrees with the authored name.
function GuideAudit:Compare(kind, id, live, force)
    local authored = self:Authored(kind, id)
    if not authored or type(live) ~= "string" or sameName(authored, live) then return false end
    local message = string.format("%s %d is '%s' on this client, but the guide expects '%s'", labels[kind], id, live, authored)
    local others = {}
    for _, otherID in ipairs(self:AuthoredIDsFor(kind, live)) do
        if otherID ~= id then table.insert(others, otherID) end
    end
    if #others > 0 then
        message = message .. string.format(" (the guide uses '%s' for %s %s)", live, labels[kind], joinIDs(others))
    end
    return self:Report(message .. ".", force)
end

-- Something seen on the client with both an ID and a name. Reports a wrong
-- name for a guide ID, or a guide name that the client files under another ID.
function GuideAudit:NoticeLive(kind, liveID, liveName, source, force)
    if type(liveID) ~= "number" or type(liveName) ~= "string" then return false end
    if self:Compare(kind, liveID, liveName, force) then return true end
    if self:Authored(kind, liveID) then return false end
    local expected = {}
    for _, id in ipairs(self:AuthoredIDsFor(kind, liveName)) do
        if id ~= liveID then table.insert(expected, id) end
    end
    if #expected == 0 then return false end
    return self:Report(string.format("guide expects %s %s for '%s', but %s '%s' is %s %d.",
        labels[kind], joinIDs(expected), self:Authored(kind, expected[1]), source, liveName, labels[kind], liveID), force)
end

function GuideAudit:CheckUnit(unit, source)
    local Client = ns.modules.Client
    local id = Client:GetUnitCreatureID(unit)
    if not id then return false end
    return self:NoticeLive("npcs", id, Client:GetUnitName(unit), source)
end

function GuideAudit:ScanQuestLog()
    for _, entry in ipairs(ns.modules.Client:GetQuestLogEntries()) do
        self:NoticeLive("quests", entry.questID, entry.title, "the quest in your log")
    end
end

function GuideAudit:ScanBags()
    for _, item in ipairs(ns.modules.Client:GetBagItems()) do
        self:NoticeLive("items", item.itemID, item.name, "the item in your bags")
    end
end

-- IDs a node references, grouped by kind, each listed once.
function GuideAudit:NodeIDs(node)
    local ids, seen = { quests = {}, npcs = {}, items = {} }, { quests = {}, npcs = {}, items = {} }
    local function add(kind, values)
        if type(values) == "number" then values = { values } end
        for _, id in ipairs(type(values) == "table" and values or {}) do
            if type(id) == "number" and not seen[kind][id] then
                seen[kind][id] = true
                table.insert(ids[kind], id)
            end
        end
    end
    local function addObserved(observed)
        if type(observed) ~= "table" then return end
        add("quests", observed.ids)
        add("quests", observed.questID)
        add("items", observed.itemID)
        for _, child in ipairs(observed.children or {}) do addObserved(child) end
    end
    if type(node) ~= "table" then return ids end
    if node.completion and node.completion.type == "observed" then addObserved(node.completion.observed) end
    if node.refs then
        add("quests", node.refs.quests)
        add("npcs", node.refs.npcs)
        add("items", node.refs.items)
    end
    if node.auto then
        add("quests", node.auto.quests)
        add("quests", node.auto.turnin)
        add("quests", node.auto.accept)
        add("quests", node.auto.track)
        add("quests", node.auto.untrack)
        add("npcs", node.auto.kill)
        add("items", node.auto.collect)
    end
    return ids
end

function GuideAudit:CurrentNode()
    local Progress = ns.modules.Progress
    if not Progress or not Progress.store then return nil end
    local guide = Progress:GetActiveGuide()
    if not guide then return nil end
    return Progress:GetCurrentNode(guide), guide
end

-- Names the client already has for the IDs of one step.
function GuideAudit:AuditNode(node, force)
    local Client = ns.modules.Client
    local ids = self:NodeIDs(node)
    for _, id in ipairs(ids.quests) do self:Compare("quests", id, Client:GetQuestTitle(id), force) end
    for _, id in ipairs(ids.items) do self:Compare("items", id, Client:GetItemName(id), force) end
    for _, id in ipairs(ids.npcs) do self:Compare("npcs", id, Client:GetNPCName(id), force) end
end

function GuideAudit:AuditCurrentNode()
    if not self:Enabled() then return end
    local node = self:CurrentNode()
    if not node then return end
    self:AuditNode(node)
    self:CheckObjective(node)
    self:CheckProgressPosition(node)
end

local function contains(list, value)
    for _, entry in ipairs(list or {}) do
        if entry == value then return true end
    end
    return false
end

-- A quest the step expects is being handled by an NPC the step does not name.
-- Steps carry the giver in refs.npcs; objective steps completed at an object
-- have none and are skipped.
function GuideAudit:CheckQuestGiver(node, questID, npcID, npcName)
    local givers = node and node.refs and node.refs.npcs
    if type(givers) ~= "table" or #givers == 0 or type(npcID) ~= "number" or contains(givers, npcID) then return false end
    local expected = {}
    for _, id in ipairs(givers) do table.insert(expected, string.format("%d '%s'", id, self:Authored("npcs", id) or "?")) end
    local title = ns.modules.Client:GetQuestTitle(questID) or self:Authored("quests", questID) or "?"
    return self:Report(string.format("quest %d '%s' is handled by NPC %d '%s', but step '%s' says NPC %s.",
        questID, title, npcID, npcName or "?", ns.modules.Steps:Title(node, true), table.concat(expected, " or ")))
end

-- A quest dialog is open: check the quest giver's ID, whether it is the giver
-- the step names, and whether the title is one the current step is about.
function GuideAudit:CheckQuestDialog()
    if not self:Enabled() then return end
    local Client = ns.modules.Client
    local title = Client:GetQuestDialogTitle()
    self.lastDialog = { title = title, npcID = Client:GetUnitCreatureID("npc"), npcName = Client:GetUnitName("npc") }
    self:CheckUnit("npc", "the quest giver")
    local node = self:CurrentNode()
    if not node or not title then return end
    local ids = self:NodeIDs(node).quests
    if #ids == 0 then return end
    local expected = {}
    for _, id in ipairs(ids) do
        local name = Client:GetQuestTitle(id) or self:Authored("quests", id)
        if sameName(name, title) then
            self:CheckQuestGiver(node, id, self.lastDialog.npcID, self.lastDialog.npcName)
            return
        end
        table.insert(expected, string.format("%d '%s'", id, name or "?"))
    end
    self:Report(string.format("the quest dialog shows '%s', but step '%s' expects quest %s.", title, ns.modules.Steps:Title(node, true), table.concat(expected, ", ")))
end

-- QUEST_ACCEPTED and QUEST_TURNED_IN carry the real ID; the title and the
-- giver come from the log, or from the dialog that was just open.
function GuideAudit:CheckQuestEvent(questID)
    if not self:Enabled() or type(questID) ~= "number" then return end
    local dialog = self.lastDialog or {}
    local title = ns.modules.Client:GetQuestTitle(questID) or dialog.title
    self:NoticeLive("quests", questID, title, "the quest you just handled")
    local node = self:CurrentNode()
    if node and contains(self:NodeIDs(node).quests, questID) then
        self:CheckQuestGiver(node, questID, dialog.npcID, dialog.npcName)
        self:CheckPosition(node, string.format("quest %d '%s' handled", questID, title or "?"))
    end
end

-- Where things happen versus where the step points. The threshold is generous:
-- a few percent of the map, scaled by the step's own arrival radius.
local function fmtPercent(x, y)
    return string.format("%.1f, %.1f", x * 100, y * 100)
end

function GuideAudit:CheckPosition(node, what, slack)
    local location = node and node.location
    if type(location) ~= "table" or type(location.x) ~= "number" then return false end
    local Client = ns.modules.Client
    local mapID = Client:GetCurrentMapID()
    if not mapID then return false end
    local title = ns.modules.Steps:Title(node, true)
    local expectedMap = Client:ResolveMapID(location.mapID)
    if expectedMap and expectedMap ~= mapID then
        return self:Report(string.format("%s on map %d, but step '%s' is on map %d.", what, mapID, title, expectedMap))
    end
    local x, y = Client:GetPlayerMapPosition(mapID)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    local best, bestX, bestY = math.huge, location.x, location.y
    local points = { { x = location.x, y = location.y } }
    for _, spot in ipairs(location.spots or {}) do table.insert(points, spot) end
    for _, point in ipairs(points) do
        local dx, dy = x - point.x, y - point.y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance < best then best, bestX, bestY = distance, point.x, point.y end
    end
    local threshold = math.max((location.arrivalRadiusNormalized or 0.02) * (slack or 2), 0.05)
    if best <= threshold then return false end
    return self:Report(string.format("%s at %s, but step '%s' points to %s (%.0f%% of the map away).", what, fmtPercent(x, y), title, fmtPercent(bestX, bestY), best * 100))
end

local function objectiveTotal(text)
    if type(text) ~= "string" then return nil end
    local total = text:match("%d+%s*/%s*(%d+)")
    return total and tonumber(total) or nil
end

local function textMentions(text, name)
    local key, haystack = normalizeName(name), normalizeName(text)
    return key ~= nil and haystack ~= nil and haystack:find(key, 1, true) ~= nil
end

-- A step about one objective line of a quest: does that line exist, is it
-- about the mob, item, or object the step names, and does the count agree?
function GuideAudit:CheckObjective(node, force)
    local observed = node and node.completion and node.completion.observed
    if type(observed) ~= "table" or observed.type ~= "objective" then return false end
    local Client = ns.modules.Client
    local lines = Client:GetQuestObjectives(observed.questID)
    if #lines == 0 then return false end
    local title = ns.modules.Steps:Title(node, true)
    local questName = Client:GetQuestTitle(observed.questID) or self:Authored("quests", observed.questID) or "?"
    local line = lines[observed.index]
    if not line then
        return self:Report(string.format("step '%s' is about objective %d of quest %d '%s', which has only %d objectives.", title, observed.index, observed.questID, questName, #lines), force)
    end
    if type(line.text) ~= "string" or #line.text == 0 then return false end
    local names = {}
    local auto = node.auto or {}
    -- The client says the line is an item to loot, and the step only names
    -- what to kill: it reads "Kill Highlands Bandit" for "Pilfered
    -- Windstone: 0/10", and the tracker cannot tell the loot from the kills.
    if line.type == "item" and auto.kill and not auto.collect then
        return self:Report(string.format("objective %d of quest %d '%s' is an item to loot ('%s'), but step '%s' names no collect item.", observed.index, observed.questID, questName, line.text, title), force)
    end
    for _, id in ipairs(auto.kill or {}) do table.insert(names, ns.modules.Names:NPC(id) or self:Authored("npcs", id)) end
    for _, id in ipairs(auto.collect or {}) do table.insert(names, ns.modules.Names:Item(id) or self:Authored("items", id)) end
    -- A world object's name is its own, not the quest's: 'Click The Altar of
    -- Fire' serves 'Destroy the Demon Seed'. Silence alone proves nothing, so
    -- an object only accuses the step when it names a different line.
    local objectOnly = #names == 0 and auto.object ~= nil
    if auto.object then table.insert(names, auto.object) end
    local mentioned = #names == 0
    for _, name in ipairs(names) do
        if textMentions(line.text, name) then mentioned = true end
    end
    if not mentioned then
        local elsewhere
        for index, other in ipairs(lines) do
            for _, name in ipairs(names) do
                if index ~= observed.index and textMentions(other.text, name) then elsewhere = index end
            end
        end
        if not (objectOnly and not elsewhere) then
            return self:Report(string.format("objective %d of quest %d '%s' reads '%s', but step '%s' is about '%s'%s.", observed.index, observed.questID, questName, line.text, title,
                table.concat(names, "', '"), elsewhere and string.format(" (that is objective %d)", elsewhere) or ""), force)
        end
    end
    local total = objectiveTotal(line.text)
    if auto.count and total and total ~= auto.count then
        return self:Report(string.format("objective %d of quest %d '%s' needs %d ('%s'), but step '%s' says %d.", observed.index, observed.questID, questName, total, line.text, title, auto.count), force)
    end
    return false
end

-- Progress on the current step (an objective line changing, a collect count
-- rising) is credited to where the player stands, then compared to the step.
function GuideAudit:CheckProgressPosition(node)
    local observed = node and node.completion and node.completion.observed
    if type(observed) ~= "table" then return end
    local Client = ns.modules.Client
    local key, value, what
    if observed.type == "objective" then
        local _, text = Client:GetQuestObjective(observed.questID, observed.index)
        key, value, what = node, text, text and ("progress '" .. text .. "'") or nil
    elseif observed.type == "item" then
        local count = Client:GetItemCount(observed.itemID)
        key, value, what = node, count, string.format("picked up '%s'", ns.modules.Names:DescribeItem(observed.itemID))
    else
        return
    end
    local seen = self.progressSeen or setmetatable({}, { __mode = "k" })
    self.progressSeen = seen
    local previous = seen[key]
    seen[key] = value
    if value == nil or previous == nil or previous == value then return end
    if observed.type == "item" and type(value) == "number" and value < previous then return end
    self:CheckPosition(node, what, 3)
end

function GuideAudit:CheckHearth()
    if not self:Enabled() then return end
    local node = self:CurrentNode()
    local observed = node and node.completion and node.completion.observed
    if not observed or observed.type ~= "hearth" then return end
    local Client = ns.modules.Client
    local bound = Client:GetBindLocation()
    if not bound or Client:IsHearthSetAt(observed.name) then return end
    self:Report(string.format("hearthstone bound at '%s', but step '%s' says '%s'.", bound, ns.modules.Steps:Title(node, true), observed.name))
end

function GuideAudit:CheckFlightMaster()
    if not self:Enabled() then return end
    local node = self:CurrentNode()
    local observed = node and node.completion and node.completion.observed
    if not observed or observed.type ~= "flightpath" then return end
    local current = ns.modules.Client:GetCurrentTaxiNodeName()
    if not current then return end
    local short = current:gsub(",.*$", "")
    if sameName(short, observed.name) or sameName(current, observed.name) or sameName(short:gsub("^the%s+", ""), observed.name:gsub("^[Tt]he%s+", "")) then return end
    self:Report(string.format("the flight master here is '%s', but step '%s' says '%s'.", current, ns.modules.Steps:Title(node, true), observed.name))
    self:CheckUnit("npc", "the flight master")
end

local function collectGuideIDs(guide)
    local ids, seen = { quests = {}, npcs = {}, items = {} }, { quests = {}, npcs = {}, items = {} }
    for _, node in ipairs(guide.nodes or {}) do
        local referencedIDs = GuideAudit:NodeIDs(node)
        for kind, list in pairs(referencedIDs) do
            for _, id in ipairs(list) do
                if not seen[kind][id] then
                    seen[kind][id] = true
                    table.insert(ids[kind], id)
                end
            end
        end
    end
    for _, list in pairs(ids) do table.sort(list) end
    return ids
end

-- On demand: every ID of a guide. Uncached quests and items are requested from
-- the server and reported as the answers arrive; NPC names come only from the
-- creature cache, so unseen NPCs cannot be judged.
function GuideAudit:AuditGuide(guide)
    guide = guide or select(2, self:CurrentNode())
    if not guide then
        ns:Print(prefix .. "No active guide to audit.")
        return
    end
    local Client = ns.modules.Client
    local ids = collectGuideIDs(guide)
    local mismatched, requested, unknown = 0, 0, 0
    self.reported = {}
    for _, id in ipairs(ids.quests) do
        local live = Client:GetQuestTitle(id)
        if live then
            if self:Compare("quests", id, live, true) then mismatched = mismatched + 1 end
        elseif Client:RequestQuestData(id) then
            self.pending.quests[id] = true
            requested = requested + 1
        else
            unknown = unknown + 1
        end
    end
    for _, id in ipairs(ids.items) do
        local live = Client:GetItemName(id)
        if live then
            if self:Compare("items", id, live, true) then mismatched = mismatched + 1 end
        elseif Client:RequestItemData(id) then
            self.pending.items[id] = true
            requested = requested + 1
        else
            unknown = unknown + 1
        end
    end
    for _, node in ipairs(guide.nodes or {}) do self:CheckObjective(node, true) end
    local uncachedNPCs = 0
    for _, id in ipairs(ids.npcs) do
        local live = Client:GetNPCName(id)
        if live then
            if self:Compare("npcs", id, live, true) then mismatched = mismatched + 1 end
        else
            uncachedNPCs = uncachedNPCs + 1
        end
    end
    ns:Print(prefix .. string.format("Audited '%s': %d quests, %d items, %d NPCs. %d mismatched, %d requested from the server, %d unanswerable, %d NPCs not yet seen this session.",
        guide.meta and guide.meta.title or guide.id, #ids.quests, #ids.items, #ids.npcs, mismatched, requested, unknown, uncachedNPCs))
    if requested > 0 then ns:Print(prefix .. "Server answers follow as they arrive.") end
end

function GuideAudit:OnDataLoaded(kind, id, success)
    if type(id) ~= "number" or not self.pending[kind][id] then return end
    self.pending[kind][id] = nil
    local Client = ns.modules.Client
    local live
    if kind == "quests" then live = Client:GetQuestTitle(id) else live = Client:GetItemName(id) end
    if success == false or (kind == "items" and not live) then
        self:Report(string.format("%s %d '%s' does not exist on this client.", labels[kind], id, self:Authored(kind, id) or "?"), true)
    elseif live then
        self:Compare(kind, id, live, true)
    end
    if not next(self.pending.quests) and not next(self.pending.items) then
        ns:Print(prefix .. "Audit finished; every server answer is in.")
    end
end


-- One-line rendering of any value; tables show their keys so a nested path
-- can be dumped next. A stand-in for Blizzard's /dump, which not every client ships.
local function describe(value, depth)
    -- A secret value poisons everything it touches: tostring of one is a
    -- secret string, and concatenating that throws where the line is joined
    -- rather than where it was made. Nothing derived from one leaves here.
    local isSecret = rawget(_G, "issecretvalue")
    if type(isSecret) == "function" then
        local ok, secret = pcall(isSecret, value)
        if ok and secret then return "(secret " .. type(value) .. ")" end
    end
    local kind = type(value)
    if kind == "table" then
        local keys = {}
        for key in pairs(value) do table.insert(keys, tostring(key)) end
        table.sort(keys)
        if #keys == 0 then return "{} (empty table)" end
        if depth and depth > 0 then
            local lines = {}
            for _, key in ipairs(keys) do
                local raw
                for k, v in pairs(value) do if tostring(k) == key then raw = v end end
                table.insert(lines, "  " .. key .. " = " .. describe(raw, 0))
            end
            return "table with " .. #keys .. " keys:\n" .. table.concat(lines, "\n")
        end
        return "table {" .. table.concat(keys, ", ") .. "}"
    elseif kind == "function" then
        return "function"
    elseif kind == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

-- Resolves "A.b.c" against the globals, walking tables by string key.
local function resolveGlobal(path)
    local value = _G
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil, part end
        local ok, next = pcall(function() return value[part] end)
        if not ok then return nil, part end
        value = next
    end
    return value
end

function GuideAudit:Dump(path)
    if not path or path == "" then ns:Print(prefix .. "Usage: /nuuroad dump SECURE_ACTIONS.raidtarget"); return end
    local value, missing = resolveGlobal(path)
    if value == nil and missing then
        ns:Print(prefix .. path .. " = nil (stopped at '" .. missing .. "')")
        return
    end
    self:ShowText("Dump: " .. path, path .. " = " .. describe(value, 1))
end

-- Everything that decides whether this client lets the addon mark targets.
function GuideAudit:MarkingDiagnostics()
    local Client = ns.modules.Client
    local lines = {}
    local function line(label, value) table.insert(lines, label .. ": " .. describe(value, 0)) end
    local build = Client.build or {}
    line("client", (build.version or "?") .. " build " .. tostring(build.build or "?") .. " toc " .. tostring(build.toc or "?"))
    line("SetRaidTarget global", rawget(_G, "SetRaidTarget"))
    line("restricted API (issecretvalue)", rawget(_G, "issecretvalue") ~= nil)
    line("restricted API (C_SecretValues)", rawget(_G, "C_SecretValues") ~= nil)
    line("capability targetMarkers", Client:Has("targetMarkers"))
    line("client refused SetRaidTarget this session", Client.markingForbidden == true)
    line("CanMarkTargets()", Client:CanMarkTargets())
    line("InCombatLockdown()", Client:InCombatLockdown())
    line("markTargets setting", ns.modules.Config:Get("automation.markTargets"))
    line("NPCTracking:Enabled(markTargets)", ns.modules.NPCTracking and ns.modules.NPCTracking:Enabled("markTargets"))
    local actions = rawget(_G, "SECURE_ACTIONS")
    line("SECURE_ACTIONS", actions)
    if type(actions) == "table" then
        local found = {}
        for key, value in pairs(actions) do
            if tostring(key):lower():find("raid") or tostring(key):lower():find("mark") or tostring(key):lower():find("target") then
                table.insert(found, tostring(key) .. " = " .. describe(value, 0))
            end
        end
        table.sort(found)
        line("SECURE_ACTIONS entries mentioning raid/mark/target", #found > 0 and table.concat(found, "; ") or "none")
    end
    line("SecureActionButtonTemplate loaded", rawget(_G, "SecureActionButton_OnClick") ~= nil)
    line("SecureUnitButtonTemplate loaded", rawget(_G, "SecureUnitButton_OnClick") ~= nil)
    line("SetBindingClick", rawget(_G, "SetBindingClick"))
    line("/targetmarker slash", rawget(_G, "SLASH_TARGET_MARKER1"))
    line("capability secureMarking", Client:Has("secureMarking"))
    if ns.modules.TargetMarking then
        for _, entry in ipairs(ns.modules.TargetMarking:DiagnosticLines()) do table.insert(lines, entry) end
    end
    -- The step's creature set as the tracker and the strip see it: what each
    -- one is, the marker it was given, whether it is live, whether it is in
    -- view, what the client reads off it, and what we put on it. This is the
    -- line to read when every creature wears the same marker, when one
    -- appears twice, or when an icon will not stay put.
    local NPCTracking, Names = ns.modules.NPCTracking, ns.modules.Names
    local TargetMarking = ns.modules.TargetMarking
    if NPCTracking then
        local seen, unknown, visible = NPCTracking:MarkersInView()
        local worn, carried = NPCTracking:WornMarkers(), NPCTracking:CarriedMarkers()
        local strip = TargetMarking and TargetMarking.MarkersToDraw and TargetMarking:MarkersToDraw() or {}
        local ours = TargetMarking and TargetMarking.MarkedByUs and TargetMarking:MarkedByUs() or {}
        table.insert(lines, "step creatures (" .. #NPCTracking.order .. " in " .. #(NPCTracking.nodes or {}) .. " steps):")
        for index, id in ipairs(NPCTracking.order) do
            local target = NPCTracking.targets[id] or {}
            table.insert(lines, string.format("%2d  id %s  %s  kind=%s marker=%s live=%s inView=%s onUnit=%s hidden=%s worn=%s carries=%s strip=%s line=%s steps=%d",
                index, tostring(id), tostring(Names and Names:DescribeNPC(id)), tostring(target.kind), tostring(target.marker),
                tostring(NPCTracking:IsLive(id)), tostring(visible[id] == true), tostring(seen[id]),
                tostring(unknown[id] == true), tostring(worn[id]), tostring(carried[id] == true),
                tostring(strip[id]), tostring(ours[id]), #(target.nodes or {})))
        end
        for index, node in ipairs(NPCTracking.nodes or {}) do
            local kill, talk = ns.modules.Steps:NPCs(node)
            table.insert(lines, string.format("  step %s  %s  kill=[%s] talk=[%s]", tostring(node.index),
                ns.modules.Steps:Title(node), table.concat(kill, ","), table.concat(talk, ",")))
        end
    end
    local targetMarker, markerKnown = Client:GetRaidTargetIndex("target")
    if markerKnown then
        line("GetRaidTargetIndex(target)", targetMarker ~= nil and targetMarker or "none")
    else
        line("GetRaidTargetIndex(target)", "hidden by the client (secret value)")
    end
    -- The raw call, unwrapped. A marker the player put on by hand reads back
    -- as a secret number on this client while an absent one reads as plain
    -- nil, which is why removing a marker updates the strip and changing one
    -- does not: nil is readable and the number is not.
    local raw = rawget(_G, "GetRaidTargetIndex")
    if type(raw) == "function" then
        local ok, value = pcall(raw, "target")
        local isSecret = rawget(_G, "issecretvalue")
        line("raw GetRaidTargetIndex(target) call", ok and ("type " .. type(value)) or ("ERROR " .. tostring(value)))
        if ok then
            line("  issecretvalue of it", type(isSecret) == "function" and select(2, pcall(isSecret, value)) or "no issecretvalue")
            -- Any comparison against a secret value throws; whether it does
            -- is the only thing we can learn about the number itself.
            line("  comparing it to 0 throws", not pcall(function() return value ~= nil and value > 0 end))
        end
    end
    -- If this exists, a texture can be pointed at a marker the addon is not
    -- allowed to read: the icon is set from the index without our code ever
    -- comparing it. Worth knowing before assuming a hidden marker cannot be
    -- drawn at all.
    line("SetRaidTargetIconTexture", rawget(_G, "SetRaidTargetIconTexture"))
    line("TargetFrame", rawget(_G, "TargetFrame") ~= nil)
    line("C_NamePlate.GetNamePlateForUnit", C_NamePlate ~= nil and C_NamePlate.GetNamePlateForUnit ~= nil)
    line("marker drawn on the target's frame", Client:GetRaidTargetIconFromFrame("target"))
    line("  icon texture found in the frame", Client:GetRaidTargetIconTexture("target") ~= nil)
    -- Whether the icon can be copied onto one of our own textures without
    -- ever reading it. This is the last way to show a marker whose value the
    -- client guards, so it is the line that decides what the strip can do.
    local probe = GuideAudit.iconProbe
    if not probe and rawget(_G, "UIParent") and CreateFrame then
        local holder = CreateFrame("Frame", nil, rawget(_G, "UIParent"))
        holder:Hide()
        probe = holder:CreateTexture(nil, "ARTWORK")
        GuideAudit.iconProbe = probe
    end
    local copied = probe ~= nil and Client:CopyRaidIcon(probe, "target")
    line("  icon copies onto our own texture", copied)
    -- Whether it copied is not whether it drew. The file is set from a
    -- constant, so reading it back says the texture really has something to
    -- draw; only the cell within it stays unknowable.
    if copied then
        line("  file on our texture afterwards", select(1, pcall(function() return probe:GetTexture() end))
            and select(2, pcall(function() return probe:GetTexture() end)) or "unreadable")
        line("  our texture is shown", select(2, pcall(function() return probe:IsShown() end)))
    end
    -- When the icon is not found, this says what is actually in there, which
    -- is the only way to learn what the client calls it on this build.
    if rawget(_G, "TargetFrame") and not Client:GetRaidTargetIconTexture("target") then
        table.insert(lines, "textures under TargetFrame:")
        for _, entry in ipairs(Client:DescribeTextures(rawget(_G, "TargetFrame"))) do
            table.insert(lines, "  " .. entry)
        end
    end
    table.insert(lines, "markers readable on the units in view:")
    for _, unit in ipairs(ns.modules.NPCTracking and ns.modules.NPCTracking:UnitsInView() or {}) do
        if Client:UnitExists(unit) then
            local value, known = Client:GetRaidTargetIndex(unit)
            -- Both answers side by side: the number the client will or will
            -- not give, and the marker read off the frame that draws it.
            line("  " .. unit .. " (" .. tostring(Client:GetUnitCreatureID(unit)) .. ")",
                (known and (value ~= nil and value or "none") or "hidden")
                .. ", drawn on its frame: " .. tostring(Client:GetRaidTargetIconFromFrame(unit)))
        end
    end
    line("target creature ID", Client:GetUnitCreatureID("target"))
    return lines
end

-- What a "Mark all" press would actually run, block by block, with the
-- reason each of the step's creatures is in it or out of it. A block whose
-- "/targetexact" finds nobody leaves the target cleared and its "/tm" marks
-- nothing, which is why one press can mark one creature and leave the rest:
-- the client can only mark what it can target from where the player stands.
function GuideAudit:MarkAllDiagnostics()
    local TargetMarking, NPCTracking = ns.modules.TargetMarking, ns.modules.NPCTracking
    if not TargetMarking or not NPCTracking then return { "target marking is not loaded" } end
    local marked = TargetMarking:MarkersInView()
    local visible = NPCTracking:VisibleTargets()
    local body, reason, skipped = TargetMarking:MarkAllBody(1023, marked)
    local lines = {
        "Paste one block below into a macro and press it: that shows whether the client refuses the",
        "/targetexact, the /tm, or neither. A block whose /targetexact finds nobody marks nothing.",
        "",
    }
    for _, entry in ipairs(NPCTracking:Entries()) do
        local why = (entry.done and "left out: done")
            or (not entry.marker and "left out: no marker (the step is not live yet)")
            or (marked[entry.id] ~= nil and ("left out: already marked (" .. tostring(marked[entry.id]) .. ")"))
            or "in the press"
        table.insert(lines, string.format("%s (id %s): marker=%s inView=%s -> %s",
            tostring(entry.name), tostring(entry.id), tostring(entry.marker), tostring(visible[entry.id] == true), why))
    end
    table.insert(lines, "")
    table.insert(lines, "left out for length: " .. tostring(skipped) .. (reason and ("; " .. reason) or ""))
    table.insert(lines, "")
    table.insert(lines, body)
    return lines
end

local function slashCommand(text)
    local command = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if command == "audit" or command == "ids" then
        GuideAudit:AuditGuide()
    elseif command == "log" then
        GuideAudit:ShowLog()
    elseif command == "log clear" then
        GuideAudit:ClearFindings()
        ns:Print(prefix .. "Findings cleared.")
    elseif command == "db" or command == "saved" then
        GuideAudit:ShowSavedData()
    elseif command == "rec clear" then
        local cleared = ns.recorder:Clear()
        ns:Print(prefix .. "Session log cleared (" .. tostring(cleared) .. " records).")
    elseif command == "rec" or command == "record" then
        GuideAudit:ShowText("Session recording", table.concat(ns.recorder:DiagnosticLines(), "\n"))
    elseif command == "where" or command == "nav" then
        GuideAudit:ShowText("Navigation diagnostics", table.concat(ns.modules.Navigation:DiagnosticLines(), "\n"))
    elseif command == "way" or command:match("^way%s") then
        -- A waypoint for the arrow: `/nr way [mapID] <x> <y>`, on the current
        -- map unless a map ID comes first. `way` alone or `way clear` puts it away.
        local Navigation = ns.modules.Navigation
        local argument = command:match("^way%s+(.+)$")
        if not argument or argument == "clear" then
            local had = Navigation.waypoint
            Navigation:ClearWaypoint()
            ns:Print(had and "Waypoint cleared." or "Usage: /nr way [mapID] <x> <y>; /nr way clear puts it away.")
        else
            local ok, problem = Navigation:SetWaypointFromText(argument)
            if ok then
                local location = Navigation.waypoint.location
                local mapName = ns.modules.Client:GetMapName(location.mapID)
                ns:Print(Navigation.waypoint.title .. " on " .. tostring(mapName or ("map " .. location.mapID)) .. ".")
            else
                ns:Print(problem)
            end
        end
    elseif command:match("^markallkey") then
        if ns.modules.TargetMarking then
            local marking = ns.modules.TargetMarking
            marking:SetKey(((text or ""):gsub("^%s*[Mm][Aa][Rr][Kk][Aa][Ll][Ll][Kk][Ee][Yy]", "")), marking.allButtonName)
        end
    elseif command:match("^markkey") then
        if ns.modules.TargetMarking then ns.modules.TargetMarking:SetKey(((text or ""):gsub("^%s*[Mm][Aa][Rr][Kk][Kk][Ee][Yy]", ""))) end
    elseif command == "marks" or command == "mark" then
        GuideAudit:ShowText("Target marking diagnostics", table.concat(GuideAudit:MarkingDiagnostics(), "\n"))
    elseif command == "markall" then
        GuideAudit:ShowText("Mark all", table.concat(GuideAudit:MarkAllDiagnostics(), "\n"))
    elseif command:match("^poi") then
        -- The quest POI evidence. With no argument it reports the log the
        -- tracker has been filling as the player walks; `now` asks the client
        -- fresh about everything in the quest log. Read-only either way.
        local POILog = ns.modules.POILog
        local argument = command:match("^poi%s+(.+)$")
        if argument == "clear" then
            if POILog then POILog:Clear() end
            ns:Print(prefix .. "Quest POI log cleared.")
        elseif argument == "sweep" then
            local queued = POILog and POILog:StartSweep() or 0
            ns:Print(prefix .. "Reading the client's own POI data for " .. queued .. " maps; /nuuroad poi maps shows it.")
        elseif argument == "correct" or argument == "corrections" then
            -- Session-only coordinate corrections for packaged guides, from
            -- what the game confirmed. Off until asked for.
            local Corrections = ns.modules.GuideCorrections
            if argument == "correct" then
                local on = Corrections:SetApplying(not Corrections.applying)
                ns:Print(prefix .. "Applying guide coordinate corrections is now " .. (on and "ON" or "OFF")
                    .. " (this session only, packaged guides only).")
            end
            GuideAudit:ShowText("Guide corrections", table.concat(Corrections:ReportLines(), "\n"))
        elseif argument == "observed" or argument == "truth" then
            -- The third source: where the game said things happened. Neither
            -- the guide nor the client had a say in it.
            GuideAudit:ShowText("Observed positions", table.concat(POILog:ObservationLines(), "\n"))
        elseif argument == "quests" then
            GuideAudit:ShowText("Quest POI detail", table.concat(POILog:QuestDetailLines(), "\n"))
        elseif argument == "maps" or argument == "pois" then
            GuideAudit:ShowText("Client map data", table.concat(POILog:MapLines(), "\n"))
        elseif not POILog then
            ns:Print("The quest POI log is not loaded.")
        else
            GuideAudit:ShowText("Quest POI log", table.concat(POILog:ReportLines(), "\n"))
        end
    elseif command:match("^questtip") then
        -- What the client's own quest-link tooltip says about a quest: the
        -- place to look for a prerequisite the player is missing.
        local questID = tonumber(command:match("^questtip%s+(%d+)"))
        if not questID then
            ns:Print("Usage: /nuuroad questtip <questID>")
        else
            local Client = ns.modules.Client
            local lines, have = Client:GetQuestTooltipLines(questID)
            local out = { "Quest " .. questID .. " " .. tostring(ns.modules.Names:Quest(questID)) .. ": data " .. (have and "cached" or "not cached"),
                "in log: " .. tostring(Client:IsQuestInLog(questID)) .. ", turned in: " .. tostring(Client:IsQuestComplete(questID)),
                "tooltip lines: " .. #lines }
            for index, entry in ipairs(lines) do
                table.insert(out, string.format("%2d  %s%s", index, tostring(entry.left or ""), entry.right and ("  |  " .. tostring(entry.right)) or ""))
            end
            if not have then
                table.insert(out, Client:RequestQuestData(questID) and "Asked the server for the quest; run the command again in a moment." or "The client cannot request quest data.")
            end
            GuideAudit:ShowText("Quest tooltip " .. questID, table.concat(out, "\n"))
        end
    elseif command:match("^dump") then
        GuideAudit:Dump(((text or ""):gsub("^%s*[Dd][Uu][Mm][Pp]%s*", ""):gsub("%s+$", "")))
    elseif command == "traveltest" then
        local Panel = ns.modules.TravelTestPanel
        if Panel then Panel:Toggle() end
    elseif command == "debug" then
        local Config = ns.modules.Config
        Config:Set("debug", not Config:Get("debug"))
        -- The options window hears it through OnSettingChanged("debug").
        ns:Print("Debug log " .. (Config:Get("debug") and "on" or "off") .. ".")
    elseif command == "" then
        if ns.modules.MainWindow then ns.modules.MainWindow:Toggle() end
    else
        ns:Print("/nuuroad - toggle the window; /nuuroad audit - check the active guide's IDs; /nuuroad log - copyable list of every finding (log clear to empty it); /nuuroad db - saved-data state; /nuuroad where - copyable map/position diagnostics for the arrow; /nuuroad way [mapID] <x> <y> - point the arrow at a place until you arrive (way clear to put it away); /nuuroad markkey <KEY> - bind the key that marks the targeted step NPC (markkey none to unbind); /nuuroad markallkey <KEY> - bind the key that marks every step NPC in view; /nuuroad marks - target marking diagnostics; /nuuroad markall - what a Mark all press would run, block by block; /nuuroad dump <Global.path> - show a global value or table keys; /nuuroad questtip <questID> - copyable lines of the client's quest-link tooltip; /nuuroad poi - everything the POI log holds, in one report. The parts on their own: poi correct (apply this session's coordinate corrections), poi corrections, poi observed, poi quests, poi maps, poi sweep, poi clear; /nuuroad traveltest - the step-by-step in-game test of the travel planner, logged to the travel channel; /nuuroad debug - toggle the debug log.")
    end
end

function GuideAudit:Initialize()
    _G.SLASH_NUUROAD1 = "/nuuroad"
    _G.SLASH_NUUROAD2 = "/nr"
    -- Only add our key. Assigning the SlashCmdList global itself (even to its own
    -- value) taints it, and every slash command the client dispatches afterwards
    -- runs tainted, so protected calls such as the dangerous-scripts dialog fail.
    if _G.SlashCmdList then _G.SlashCmdList.NUUROAD = slashCommand end

    local frame = CreateFrame("Frame")
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
        "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
        "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "QUEST_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED",
        "HEARTHSTONE_BOUND", "TAXIMAP_OPENED",
    }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "QUEST_DATA_LOAD_RESULT" then
            self:OnDataLoaded("quests", ...)
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            self:OnDataLoaded("items", ...)
        elseif not self:Enabled() then
            return
        elseif event == "PLAYER_TARGET_CHANGED" then
            self:CheckUnit("target", "your target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            self:CheckUnit("mouseover", "the unit under your mouse")
        elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
            self:CheckQuestDialog()
        elseif event == "QUEST_ACCEPTED" then
            -- Classic passes (questLogIndex, questID); newer clients pass (questID).
            self:CheckQuestEvent(select(select("#", ...), ...))
        elseif event == "QUEST_TURNED_IN" then
            self:CheckQuestEvent((...))
        elseif event == "QUEST_LOG_UPDATE" then
            self:ScanQuestLog()
            local node = self:CurrentNode()
            if node then self:CheckObjective(node); self:CheckProgressPosition(node) end
        elseif event == "BAG_UPDATE_DELAYED" then
            self:ScanBags()
            local node = self:CurrentNode()
            if node then self:CheckProgressPosition(node) end
        elseif event == "HEARTHSTONE_BOUND" then
            self:CheckHearth()
        elseif event == "TAXIMAP_OPENED" then
            self:CheckFlightMaster()
        elseif event == "PLAYER_ENTERING_WORLD" then
            self:AuditCurrentNode()
            self:ScanQuestLog()
            self:ScanBags()
        end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= self.pollInterval then
            self.elapsed = 0
            self:AuditCurrentNode()
        end
    end)
    self.frame = frame
end

ns:RegisterModule("GuideAudit", GuideAudit)
