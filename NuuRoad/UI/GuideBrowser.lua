local _, ns = ...

-- The guide browser: three panes, built to need less digging than a folder
-- menu usually does. Ported from OpenRoad's UI/GuideBrowser.lua onto NuuKit.
--
-- Left, the places to look: quick views that answer the usual question
-- without knowing where a guide is filed (right for my level, where I stand,
-- what I have going, what I wrote), then every guide under "All guides", in
-- the folder tree the guides' own category paths make, any depth. A folder
-- shows every guide beneath it, not only its own, so the tree narrows a list
-- rather than hiding one behind the next click. Middle, the guides, each with
-- its level range coloured against the character and the folders it sits
-- in. Right, the chosen guide: what it covers and who it is for, with Start.
-- A click only chooses; nothing switches guides until the player presses
-- Start, double-clicks, or presses Enter in the search.
--
-- The search box looks through every guide at once, word by word: name,
-- folders, tags, zones, quest titles, and a number as a level. It waits for
-- the typing to pause before it looks. Guides the character cannot run (a
-- guide's own `only`) are left out unless the player unticks the box that
-- says so, and a view that hid some says how many.
--
-- The tracker calls Refresh on each of its refreshes while this window is
-- open; the browser draws again only when something it shows has changed
-- (the guides, the running guide and its progress, the level, the map, the
-- debug setting), not on every call.
local Browser = { expanded = {}, forCharacter = true, nodes = {} }

local WIDTH, HEIGHT, MIN_WIDTH, MIN_HEIGHT = 880, 500, 700, 360
local TREE_WIDTH, DETAIL_WIDTH = 210, 280
local GUIDE_ROW = 40
local MAX_SECTIONS = 10
-- How long the search waits for the typing to pause, in seconds.
local SEARCH_DELAY = 0.25

local QUICK_VIEWS = {
    { key = "suggested", name = "Suggested",
        tip = "Guides for this character that cover your level and that you have not finished." },
    { key = "near", name = "Near me", tip = "Guides with a step on the map you are on." },
    { key = "progress", name = "In progress", tip = "The guide you are running, and any other you have made progress in this session." },
    { key = "mine", name = "My guides", tip = "Guides you wrote or copied from a packaged one." },
}

local function modules() return ns.modules end
local function plural(count, word) return count .. " " .. word .. (count == 1 and "" or "s") end
local function trim(text) return ((text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Text in a colour of the look ("warning", "muted", ...). Drawn again on a
-- new look (Build's OnLook).
local function paint(token, text)
    local ui = ns:GetUI()
    local color = ui.tokens[token] or ui.tokens.text
    return ns.Kit.UI.ColorCode(color) .. text .. "|r"
end

local function playerLevel()
    local Client = modules().Client
    local level = Client and Client.Read and rawget(_G, "UnitLevel") and Client:Read(UnitLevel, "player")
    return type(level) == "number" and level > 0 and level or nil
end

local function evaluate(condition)
    local Client = modules().Client
    if not Client or not Client.EvaluateCondition then return nil end
    return Client:EvaluateCondition(condition)
end

local function completedCount(guide)
    local Progress = modules().Progress
    return Progress:CompletedCount(Progress:PeekState(guide))
end

-- Progress is out of the steps this character can do; one for another race
-- or faction is not counted.
local function stepCount(guide)
    return #modules().Progress:CharacterSteps(guide)
end

local function activeGuide()
    local Progress = modules().Progress
    if not (Progress and Progress.store) then return nil end
    return Progress:GetActiveGuide()
end

local function isActive(guide)
    local active = activeGuide()
    return active ~= nil and active.id == guide.id
end

local function isPersonal(guide)
    local Repository = modules().GuideRepository
    return not Repository:IsBuiltIn(guide.id) and not Repository:IsSessionGuide(guide.id)
end

local function guideMaps(guide)
    local maps, list = {}, {}
    for _, node in ipairs(guide.nodes or {}) do
        local mapID = node.location and node.location.mapID
        if mapID and not maps[mapID] then maps[mapID] = true; table.insert(list, mapID) end
    end
    return maps, list
end

local function currentMap()
    local Client = modules().Client
    return Client and Client.GetCurrentMapID and Client:GetCurrentMapID() or nil
end

-- Zone names and quest titles join the search text. Built once per guide
-- table: an edited guide is a new table, so it is never stale.
local searchCache = setmetatable({}, { __mode = "k" })
local function searchText(guide)
    local cached = searchCache[guide]
    if cached then return cached end
    local Client, extra = modules().Client, {}
    local _, maps = guideMaps(guide)
    for _, mapID in ipairs(maps) do
        local name = Client and Client.GetMapName and Client:GetMapName(mapID)
        if type(name) == "string" then table.insert(extra, name) end
    end
    table.insert(extra, modules().QuestIndex:SearchText(guide))
    cached = modules().GuideCatalog:SearchText(guide, table.concat(extra, " "))
    searchCache[guide] = cached
    return cached
end

local function questCount(guide)
    local QuestIndex = modules().QuestIndex
    QuestIndex:Build()
    local count = 0
    for _ in pairs(QuestIndex.questsByGuide and QuestIndex.questsByGuide[guide.id] or {}) do count = count + 1 end
    return count
end

local function levelText(guide, level)
    local levels = guide.meta.levels
    if not levels then return nil end
    local text = "Lv " .. levels[1] .. "-" .. levels[2]
    local fit = modules().GuideCatalog:LevelFit(guide, level)
    if fit == "later" then return paint("warning", text) end
    if fit == "past" then return paint("muted", text) end
    return paint("text", text)
end

-- The search's pause ------------------------------------------------------------------

-- One small frame counts the pause while a search waits; hidden otherwise,
-- so it costs nothing between searches.
local function searchTick(frame, elapsed)
    Browser.searchWait = (Browser.searchWait or 0) - (elapsed or 0)
    if Browser.searchWait > 0 then return end
    frame:Hide()
    Browser.searchPending = nil
    Browser:Draw()
end

function Browser:SearchTyped()
    self.searchPending = true
    self.searchWait = SEARCH_DELAY
    local timer = self.searchTimer
    if not timer then
        if type(CreateFrame) ~= "function" then return self:Draw() end
        timer = CreateFrame("Frame")
        timer:SetScript("OnUpdate", searchTick)
        self.searchTimer = timer
    end
    timer:Show()
end

-- A search that waits no longer: drawn now (Enter, a click elsewhere, code).
function Browser:CancelSearchWait()
    self.searchPending = nil
    if self.searchTimer then self.searchTimer:Hide() end
end

-- What the kit's search-to-list link sends the text to (UI.LinkSearch): it
-- only starts the pause, and the list is filled when the pause ends.
local searchTarget = { SetFilter = function() Browser:SearchTyped() end }

-- The window ----------------------------------------------------------------------------

local function treePicked(node) Browser:ChooseView(node.value) end
local function treeToggled(node, open)
    local key = node.value and node.value:match("^folder:(.*)$")
    if key then Browser.expanded[key] = open or nil end
    if node.value == "all" then Browser.allClosed = not open or nil end
end
local function guidePicked(guide) Browser:Pick(guide) end
local function guideActivated(guide) Browser:Start(guide) end
local function guideTip(guide)
    if modules().GuideCatalog:ForCharacter(guide, evaluate) then return nil end
    return function(tooltip)
        tooltip:SetText(guide.meta.title or "Untitled guide", 1, 1, 1)
        local c = ns:GetUI().tokens.danger
        tooltip:AddLine("Written for another character: " .. modules().Steps:DescribeCondition(guide.condition), c[1], c[2], c[3], true)
    end
end

local function makeGuideRow(row)
    local lines = row:Column{ grow = true, gap = 3 }
    row.title = lines:Text{ "" }
    row.meta = lines:Text{ "", style = "fine" }
end

local function drawGuideRow(row, guide) Browser:DrawRow(row, guide) end

function Browser:Create()
    if self.win then return self.win end
    local ui = ns:GetUI()
    local places = ns.db and ns.db.windows
    if not places then
        places = {}
        if ns.db then ns.db.windows = places end
    end
    local win = ui:Window({
        key = "browser", title = "Guides", width = WIDTH, height = HEIGHT,
        resizable = true, minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT, place = places, hidden = true,
    })
    self.win, self.frame = win, win
    win:HookScript("OnShow", function() Browser:Refresh() end)
    win:HookScript("OnHide", function() Browser:CancelSearchWait() end)

    local body = win:Column{ gap = 8, padding = 12 }
    local bar = body:Row{ gap = 10 }
    self.search = bar:Search{ grow = true, valign = "center",
        placeholder = "Search: a name, zone, quest, or level, for example barrens 15" }
    self.forCharacterToggle = bar:Toggle{ "Only guides for this character", value = self.forCharacter,
        tooltip = "Leaves out guides written for another faction, race, or class. Untick it to see every guide.",
        onChange = function(on) Browser:SetForCharacter(on) end }
    bar:Button{ "New guide", onClick = function() Browser:NewGuide() end,
        tooltip = "Starts an empty guide of your own in the editor." }

    local panes = body:SplitPanes{
        { key = "places", width = TREE_WIDTH, min = 160, padding = 0 },
        { key = "guides", grow = true, min = 260, padding = 0, gap = 6 },
        { key = "details", width = DETAIL_WIDTH, min = 220, padding = 0, gap = 8 },
        grow = true, place = places, key = "browser.panes",
    }

    self.tree = panes.places:Tree{ grow = true, onPick = treePicked, onToggle = treeToggled }

    local head = panes.guides:Row{ gap = 8 }
    self.listHead = head:Text{ "", style = "heading", grow = true }
    self.listCount = head:Text{ "", style = "label", color = "muted" }
    self.list = panes.guides:List{
        grow = true, rowHeight = GUIDE_ROW,
        make = makeGuideRow, draw = drawGuideRow,
        onPick = guidePicked, onActivate = guideActivated, tooltip = guideTip,
    }
    -- The arrows in the search move through the guides and Enter starts the
    -- chosen one; the text itself goes to the search's pause.
    ns.Kit.UI.LinkSearch(self.search, self.list, searchTarget)

    local area = panes.details:ScrollArea{ grow = true }
    local detail = area:Column{ gap = 6, padding = 4 }
    self.detailTitle = detail:Text{ "", style = "title", wrap = true }
    self.detailPath = detail:Text{ "", style = "fine", color = "muted", wrap = true }
    self.detailBody = detail:Text{ "", wrap = true }
    local actions = panes.details:Row{ gap = 6 }
    self.startButton = actions:Button{ "Start", tone = "accent", width = 90,
        onClick = function() Browser:Start(Browser:SelectedGuide()) end }
    self.editButton = actions:Button{ "Edit", onClick = function() Browser:EditSelected() end }

    -- Tints in the rows and details are worked out when drawn.
    ui:OnLook(function() if win:IsShown() then Browser:Draw(true) end end)
    return win
end

-- Views ---------------------------------------------------------------------------------

-- The guides a view lists, from `pool`, before the character filter.
function Browser:ViewGuides(view, pool, tree, level)
    local Catalog, list = modules().GuideCatalog, {}
    if view:sub(1, 7) == "folder:" then
        return Catalog:Under(tree.byKey[view:sub(8)])
    end
    if view == "all" then
        for _, guide in ipairs(pool) do table.insert(list, guide) end
        return Catalog:Sort(list)
    end
    local mapID = view == "near" and currentMap()
    for _, guide in ipairs(pool) do
        local keep
        if view == "suggested" then
            keep = Catalog:LevelFit(guide, level) == "now" and completedCount(guide) < stepCount(guide)
        elseif view == "near" then
            keep = mapID and guideMaps(guide)[mapID]
        elseif view == "progress" then
            keep = isActive(guide) or completedCount(guide) > 0
        elseif view == "mine" then
            keep = isPersonal(guide)
        end
        if keep then table.insert(list, guide) end
    end
    return Catalog:Sort(list)
end

-- Splits `list` into what the character filter keeps and how many it hid.
-- `runnable`, when given, remembers each guide's answer for one drawing.
function Browser:ForCharacter(list, runnable)
    if not self.forCharacter then return list, 0 end
    local Catalog, kept = modules().GuideCatalog, {}
    for _, guide in ipairs(list) do
        local ok = runnable and runnable[guide]
        if ok == nil then
            ok = Catalog:ForCharacter(guide, evaluate)
            if runnable then runnable[guide] = ok end
        end
        if ok then table.insert(kept, guide) end
    end
    return kept, #list - #kept
end

function Browser:ViewTitle(view, tree, level)
    if view == "suggested" then return level and ("Suggested for level " .. level) or "Suggested" end
    if view == "near" then
        local Client = modules().Client
        local mapID = currentMap()
        local name = mapID and Client:GetMapName(mapID)
        return name and ("Near me: " .. name) or "Near me"
    end
    if view == "progress" then return "In progress" end
    if view == "mine" then return "My guides" end
    if view == "all" then return "All guides" end
    local folder = tree.byKey[view:sub(8)]
    return folder and modules().GuideCatalog:PathText(folder.path) or ""
end

local function emptyText(view, query, level)
    if query ~= "" then return "No guide matches \"" .. query .. "\"." end
    if view == "suggested" then
        return "No unfinished guide covers " .. (level and ("level " .. level) or "your level") .. " for this character. All guides lists every one."
    end
    if view == "near" then return "No guide has a step on the map you are on." end
    if view == "progress" then return "No guide has been started this session." end
    if view == "mine" then return "You have no guides of your own yet. New guide starts one, and Edit on any guide makes a copy you can change." end
    return "This folder is empty."
end

-- The first opening shows what suits the character, or the running guide's
-- folder when nothing does, with the running guide's folders unfolded.
function Browser:ChooseFirstView(pool, tree, level)
    local active = activeGuide()
    local Catalog = modules().GuideCatalog
    if active then
        local path = Catalog:Path(active)
        for depth = 1, #path do self.expanded[Catalog:Key(path, depth)] = true end
        self.selectedID = active.id
    end
    if #self:ForCharacter(self:ViewGuides("suggested", pool, tree, level)) > 0 then return "suggested" end
    if active then return "folder:" .. Catalog:Key(Catalog:Path(active)) end
    return "progress"
end

-- The tree -------------------------------------------------------------------------------

-- One node table per view for good, so the kit's tree keeps its selection
-- and its open folders across drawings.
function Browser:Node(value)
    local node = self.nodes[value]
    if not node then
        node = { value = value }
        self.nodes[value] = node
    end
    return node
end

-- The tree's nodes, and a line naming what they show: the tree is set again
-- only when that line changes (a set of nodes is the whole tree drawn again,
-- back at its top).
function Browser:TreeNodes(pool, tree, level, runnable)
    local nodes, parts = {}, {}
    for _, quick in ipairs(QUICK_VIEWS) do
        local node = self:Node(quick.key)
        node.caption = quick.name
        node.count = #self:ForCharacter(self:ViewGuides(quick.key, pool, tree, level), runnable)
        node.children = nil
        table.insert(nodes, node)
        table.insert(parts, quick.key .. "=" .. node.count)
    end
    local Catalog = modules().GuideCatalog
    local function walk(folder, into)
        local count = #self:ForCharacter(Catalog:Under(folder), runnable)
        if count == 0 then return end
        local node = self:Node("folder:" .. folder.key)
        node.caption, node.count = folder.name, count
        local children = {}
        for _, child in ipairs(folder.children) do walk(child, children) end
        node.children = #children > 0 and children or nil
        node.open = self.expanded[folder.key] == true
        table.insert(into, node)
        table.insert(parts, folder.key .. "=" .. count .. (node.children and "+" or ""))
    end
    local all = self:Node("all")
    all.caption = "All guides"
    all.count = #self:ForCharacter(pool, runnable)
    local folders = {}
    for _, folder in ipairs(tree.children) do walk(folder, folders) end
    all.children = #folders > 0 and folders or nil
    all.open = not self.allClosed
    table.insert(nodes, all)
    table.insert(parts, "all=" .. all.count)
    return nodes, table.concat(parts, ";")
end

-- The tree row that shows `view`, selected; none when it is folded away.
function Browser:SelectTreeView(view)
    local node = self.nodes[view]
    for _, entry in ipairs(self.tree:GetItems()) do
        if entry.node == node then
            self.tree:Select(entry)
            return
        end
    end
    self.tree:Select(nil)
end

-- A click in the tree: a new question, so it clears the search.
function Browser:ChooseView(view)
    if not view then return end
    self.view = view
    if trim(self.search:GetText()) ~= "" then self.search:SetText("") end
    self:CancelSearchWait()
    self:Draw()
end

function Browser:SetForCharacter(on)
    self.forCharacter = on and true or false
    self:Draw()
end

-- Drawing --------------------------------------------------------------------------------

-- What the window shows depends on, besides the search and the view: when
-- none of it moved, a refresh from the tracker draws nothing.
local function stateKey()
    local Repository, Config = modules().GuideRepository, modules().Config
    local active = activeGuide()
    local mapID = currentMap()
    return table.concat({
        tostring(Repository.version),
        active and active.id or "-",
        active and completedCount(active) or 0,
        tostring(playerLevel()),
        tostring(mapID),
        Config and Config:Get("debug") and "debug" or "",
    }, "|")
end

-- From outside (the tracker, a setting): draws again only if the guides,
-- the running guide, the level, the map or the debug setting changed.
function Browser:Refresh()
    if not (self.win and self.win:IsShown()) then return end
    if self.searchPending then return end
    if self.drawnKey == stateKey() then return end
    self:Draw()
end

function Browser:OnSettingChanged(path)
    if path == "debug" and self.win and self.win:IsShown() then self:Draw(true) end
end

-- Everything again: the tree (when its counts changed), the list, the
-- details. `force` sets the tree even when its counts did not change.
function Browser:Draw(force)
    if not self.win then return end
    self:CancelSearchWait()
    local Catalog, Repository, Config = modules().GuideCatalog, modules().GuideRepository, modules().Config
    local query = trim(self.search:GetText())
    local level = playerLevel()
    self.forCharacterToggle:SetValue(self.forCharacter)
    self.drawnKey = stateKey()

    -- Fixtures are regression aids: out of the way unless searched for or debugging.
    local debug = Config and Config:Get("debug")
    local pool = {}
    for _, guide in ipairs(Repository:List()) do
        if debug or query ~= "" or not Catalog:IsFixture(guide) then table.insert(pool, guide) end
    end
    local tree = Catalog:Tree(pool)
    self.view = self.view or self:ChooseFirstView(pool, tree, level)
    if self.view:sub(1, 7) == "folder:" and not tree.byKey[self.view:sub(8)] then self.view = "suggested" end

    local runnable = {}
    local nodes, treeLine = self:TreeNodes(pool, tree, level, runnable)
    if force or treeLine ~= self.treeLine then
        self.treeLine = treeLine
        self.tree:SetNodes(nodes)
    end
    self:SelectTreeView(query == "" and self.view or nil)

    local list, title, folderDepth
    if query ~= "" then
        list = {}
        for _, guide in ipairs(pool) do
            if Catalog:Matches(guide, query, searchText(guide)) then table.insert(list, guide) end
        end
        list = Catalog:Sort(list)
        title, folderDepth = "Matching \"" .. query .. "\"", 0
    else
        list = self:ViewGuides(self.view, pool, tree, level)
        title = self:ViewTitle(self.view, tree, level)
        local folder = self.view:sub(1, 7) == "folder:" and tree.byKey[self.view:sub(8)]
        folderDepth = folder and folder.depth or 0
    end
    local shown, hidden = self:ForCharacter(list, runnable)

    self.listHead:SetText(title)
    self.listCount:SetText(plural(#shown, "guide"))
    local selected
    for _, guide in ipairs(shown) do
        if guide.id == self.selectedID then selected = guide end
    end
    if not selected then
        selected = shown[1]
        self.selectedID = selected and selected.id or nil
    end
    self.drawLevel, self.drawDepth, self.drawRunnable = level, folderDepth, runnable
    -- The same question keeps the list where it was scrolled to.
    local question = (query ~= "" and ("?" .. query) or self.view) .. (self.forCharacter and "" or "*")
    local keep = question == self.question
    self.question = question
    self.list:SetItems(shown, keep)
    self.list:Select(selected)
    if selected and not keep then self.list:ScrollToItem(selected) end
    if #shown == 0 then
        local text, action = emptyText(self.view, query, level), nil
        if hidden > 0 then
            text = text .. " " .. plural(hidden, "guide") .. " here " .. (hidden == 1 and "is" or "are") .. " for another character."
            action = { caption = "Show guides for other characters (" .. hidden .. ")",
                onClick = function() Browser:SetForCharacter(false) end }
        elseif query ~= "" then
            action = { caption = "Clear search", onClick = function() Browser:ClearSearch() end }
        end
        self.list:SetState("empty", text, action and { action = action } or nil)
    elseif self.list:GetState() then
        self.list:SetState(nil)
    end
    self:DrawDetail(selected, level)
end

function Browser:ClearSearch()
    self.search:SetText("")
    self:Draw()
end

function Browser:DrawRow(row, guide)
    local Catalog = modules().GuideCatalog
    local runnable = self.drawRunnable and self.drawRunnable[guide]
    if runnable == nil then runnable = Catalog:ForCharacter(guide, evaluate) end
    local active = isActive(guide)
    row.title:SetText((active and "> " or "") .. (guide.meta.title or "Untitled guide"))
    row.title:SetColor(runnable and "text" or "muted")
    local parts = {}
    local levels = levelText(guide, self.drawLevel)
    if levels then table.insert(parts, levels) end
    -- The folders below the one shown; a guide filed right in it names none.
    local path = Catalog:Path(guide)
    local depth = self.drawDepth or 0
    if #path > depth then table.insert(parts, Catalog:PathText(path, depth + 1)) end
    if not runnable then table.insert(parts, paint("danger", "not for this character")) end
    local done, total = completedCount(guide), stepCount(guide)
    if active then table.insert(parts, paint("accent", "active " .. done .. "/" .. total))
    elseif total > 0 and done >= total then table.insert(parts, paint("done", "finished"))
    elseif done > 0 then table.insert(parts, done .. "/" .. total) end
    if isPersonal(guide) then table.insert(parts, "yours") end
    row.meta:SetText(table.concat(parts, "  |  "))
end

function Browser:DrawDetail(guide, level)
    local Catalog = modules().GuideCatalog
    if not guide then
        self.detailTitle:SetText("")
        self.detailPath:SetText("")
        self.detailBody:SetText(paint("muted", "Choose a guide to see what it covers."))
        self.startButton:Hide(); self.editButton:Hide()
        return
    end
    self.detailTitle:SetText(guide.meta.title or "Untitled guide")
    self.detailPath:SetText(Catalog:PathText(Catalog:Path(guide)))
    local lines = {}
    local levels = guide.meta.levels
    if levels then
        local fit = Catalog:LevelFit(guide, level)
        local say = fit == "now" and "your level" or fit == "later" and paint("warning", "above your level")
            or fit == "past" and paint("muted", "below your level") or nil
        table.insert(lines, "Levels " .. levels[1] .. "-" .. levels[2] .. (say and (" - " .. say) or ""))
    end
    if guide.condition then
        local who = modules().Steps:DescribeCondition(guide.condition)
        if not Catalog:ForCharacter(guide, evaluate) then who = who .. " - " .. paint("danger", "not this character") end
        table.insert(lines, "For: " .. who)
    end
    local sections = guide.sections or {}
    table.insert(lines, plural(#sections, "section") .. ", " .. plural(#(guide.nodes or {}), "step") .. ", " .. plural(questCount(guide), "quest"))
    local done = completedCount(guide)
    local active = isActive(guide)
    if active then
        table.insert(lines, paint("accent", "Running: " .. done .. " of " .. stepCount(guide) .. " steps done"))
    elseif done > 0 then
        table.insert(lines, done .. " of " .. stepCount(guide) .. " steps done this session")
    end
    if guide.meta.source then table.insert(lines, paint("muted", guide.meta.source)) end
    if #sections > 0 then
        table.insert(lines, "")
        table.insert(lines, paint("muted", "Sections"))
        for index = 1, math.min(#sections, MAX_SECTIONS) do table.insert(lines, sections[index].title or "") end
        if #sections > MAX_SECTIONS then table.insert(lines, paint("muted", "and " .. (#sections - MAX_SECTIONS) .. " more")) end
    end
    self.detailBody:SetText(table.concat(lines, "\n"))

    self.startButton:SetText(active and "Show" or (done > 0 and "Resume" or "Start"))
    self.startButton:SetTooltip(active and "This guide is running; show the tracker"
        or (done > 0 and "Go back to this guide where you left it" or nil))
    self.startButton:Show()
    self.editButton:SetTooltip(not isPersonal(guide) and "Opens a copy. The packaged guide is never changed." or nil)
    self.editButton:Show()
end

-- Actions --------------------------------------------------------------------------------

-- A click on a guide: chosen, its details shown. The list's own selection
-- moves; nothing else is drawn again.
function Browser:Pick(guide)
    if not guide then return end
    self.selectedID = guide.id
    self:DrawDetail(guide, playerLevel())
end

function Browser:SelectedGuide()
    return self.selectedID and modules().GuideRepository:Get(self.selectedID) or nil
end

function Browser:Start(guide)
    if not guide then return end
    if not isActive(guide) then modules().Progress:Select(guide) end
    if self.win then self.win:Hide() end
    local MainWindow = modules().MainWindow
    if MainWindow and MainWindow.Show then MainWindow:Show() end
end

function Browser:EditSelected()
    local guide = self:SelectedGuide()
    if not guide then return end
    local Editor = modules().Editor
    if not (Editor and Editor.OpenGuide) then return end
    self.win:Hide()
    Editor:OpenGuide(guide)
end

function Browser:NewGuide()
    local Editor = modules().Editor
    if not (Editor and Editor.OpenNew) then return end
    self.win:Hide()
    Editor:OpenNew()
end

function Browser:IsShown()
    return self.win ~= nil and self.win:IsShown() or false
end

function Browser:Show()
    local win = self:Create()
    self:Draw()
    win:Show()
end

function Browser:Hide()
    if self.win then self.win:Hide() end
end

function Browser:Toggle()
    local win = self:Create()
    if win:IsShown() then win:Hide() else self:Show() end
end

-- Opens the browser searched for a quest, so every guide that handles it is
-- the whole list. Used by the quest log button.
function Browser:ShowQuest(questID)
    local win = self:Create()
    local name = modules().Names:Quest(questID)
    self.search:SetText(name or ("quest:" .. tostring(questID)))
    self:Draw()
    win:Show()
end

ns:RegisterModule("GuideBrowser", Browser)
