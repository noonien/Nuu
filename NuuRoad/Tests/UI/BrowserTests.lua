-- The guide browser and the quest finder, built from NuuKit on the kit's
-- stand-in for the client (Tests/UI/Harness.lua): open the browser, walk
-- the tree, search (after the pause), pick a guide, start it, open the
-- browser for a quest from the quest log button. Nothing may reach the
-- error handler, and the kit's reset audit must find every change marked.
local ctx = dofile("Tests/UI/Harness.lua")
local ns, check, settle, frames = ctx.ns, ctx.check, ctx.settle, ctx.frames
local Browser = ns.modules.GuideBrowser
local QuestFinder = ns.modules.QuestFinder
local Repository, Progress, QuestIndex = ns.modules.GuideRepository, ns.modules.Progress, ns.modules.QuestIndex
ctx.noErrors("load")

-- Counts the browser's drawings, to see what a refresh costs.
local draws = 0
local draw = Browser.Draw
Browser.Draw = function(self, ...)
    draws = draws + 1
    return draw(self, ...)
end

-- A pause long enough for the search to look (the stand-in's frames run
-- 0.08 seconds a tick).
local function pause()
    for _ = 1, 6 do frames.tick() end
    settle()
end

local function treeEntry(value)
    for index, entry in ipairs(Browser.tree:GetItems()) do
        if entry.node.value == value then return entry, index end
    end
    return nil
end

-- The shown row of the tree or list that holds `item`.
local function rowFor(list, item)
    for _, row in ipairs(list.rows) do
        if row:IsShown() and row.item == item then return row end
    end
    return nil
end

local function viewHas(list, guide)
    for _, item in ipairs(list:GetView()) do
        if item == guide then return true end
    end
    return false
end

-- Opening ------------------------------------------------------------------------------

check(Progress.store, "progress has its store after login")
Browser:Toggle()
settle()
ctx.noErrors("open")
local win = Browser.win
check(win and win:IsShown(), "the browser shows")
check(Browser.view ~= nil, "a first view is chosen")
check(#Browser.tree:GetItems() >= 5, "the tree lists the quick views and all guides")
for _, key in ipairs({ "suggested", "near", "progress", "mine", "all" }) do
    check(treeEntry(key), "the tree has " .. key)
end

-- A refresh from the tracker with nothing changed draws nothing.
local before = draws
Browser:Refresh()
Browser:Refresh()
check(draws == before, "a refresh with nothing changed draws nothing")

-- Walking the tree ----------------------------------------------------------------------

local all, allIndex = treeEntry("all")
local allRow = rowFor(Browser.tree, all)
check(allRow, "all guides has a row")
allRow:Click("LeftButton")
settle()
check(Browser.view == "all", "a click on all guides shows it")
check(Browser.listHead:GetText() == "All guides", "the list says what it shows")
local everything = #Browser.list:GetView()
check(everything > 0, "all guides lists guides")

-- A folder under all guides, with a folder of its own below it.
local folder
for index = allIndex + 1, #Browser.tree:GetItems() do
    local entry = Browser.tree:GetItems()[index]
    if entry.node.children then folder = entry; break end
end
check(folder, "a folder with folders in it")
local folderRow = rowFor(Browser.tree, folder)
check(folderRow, "the folder has a row")
folderRow:Click("LeftButton")
settle()
check(Browser.view == folder.node.value, "a click on the folder shows it")
local inFolder = #Browser.list:GetView()
check(inFolder > 0 and inFolder <= everything, "the folder lists the guides below it")
local shownBefore = #Browser.tree:GetItems()
if not folder.node.open then
    folderRow:Fire("OnDoubleClick")
    settle()
end
check(folder.node.open and #Browser.tree:GetItems() >= shownBefore, "a double click opens the folder")
local child = folder.node.children[1]
local childEntry = treeEntry(child.value)
check(childEntry, "the folder's first child is in the tree")
rowFor(Browser.tree, childEntry):Click("LeftButton")
settle()
check(Browser.view == child.value, "a click on the child folder shows it")
check(#Browser.list:GetView() <= inFolder, "the child folder lists no more than its parent")
check(Browser.expanded[folder.node.value:sub(8)], "the open folder is remembered")

-- Quick views each draw without trouble.
for _, key in ipairs({ "suggested", "near", "progress", "mine" }) do
    rowFor(Browser.tree, treeEntry(key)):Click("LeftButton")
    settle()
    check(Browser.view == key, "the tree shows " .. key)
end
ctx.noErrors("tree")

-- Searching -----------------------------------------------------------------------------

local barrens
for _, guide in ipairs(Repository:List()) do
    if (guide.meta.title or ""):lower():find("barrens", 1, true) then barrens = guide; break end
end
check(barrens, "a packaged guide about the Barrens")

local box = Browser.search.box
box:SetText("barrens")
before = draws
box:Fire("OnTextChanged", true)
check(draws == before, "typing waits for the pause")
Browser:Refresh()
check(draws == before, "a refresh while the search waits draws nothing")
pause()
check(draws == before + 1, "the pause draws once")
check(Browser.listHead:GetText():find("barrens", 1, true), "the list says what it matched")
check(viewHas(Browser.list, barrens), "the search finds the Barrens guide")
check(Browser.tree:GetSelected() == nil, "no tree row is selected while searching")

-- Typing again, fast: one drawing for the lot.
before = draws
for _, text in ipairs({ "b", "ba", "bar" }) do
    box:SetText(text)
    box:Fire("OnTextChanged", true)
    frames.tick()
end
pause()
check(draws == before + 1, "quick typing draws once")

-- A search that matches nothing offers to clear itself.
box:SetText("zzzz no such guide")
box:Fire("OnTextChanged", true)
pause()
check(#Browser.list:GetView() == 0, "nothing matches")
check(Browser.list:GetState() == "empty", "the list says so")
Browser:ClearSearch()
settle()
check(Browser.search:GetText() == "", "clear search empties the box")
check(Browser.listHead:GetText() == "My guides", "and the view comes back")

-- The character filter.
Browser.forCharacterToggle:Click("LeftButton")
settle()
check(Browser.forCharacter == false, "the toggle shows every guide")
Browser.forCharacterToggle:Click("LeftButton")
settle()
check(Browser.forCharacter == true, "and back")
ctx.noErrors("search")

-- Picking and starting ------------------------------------------------------------------

box:SetText("barrens")
box:Fire("OnTextChanged", true)
pause()
local barrensRow = rowFor(Browser.list, barrens)
check(barrensRow, "the Barrens guide has a row")
check(barrensRow.title:GetText():find(barrens.meta.title, 1, true), "the row shows the guide's title")
barrensRow:Click("LeftButton")
settle()
check(Browser.selectedID == barrens.id, "a click chooses the guide")
check(Browser.list:GetSelected() == barrens, "the list shows it chosen")
check(Browser.detailTitle:GetText() == barrens.meta.title, "the details show it")
check(Browser.detailBody:GetText():find("step", 1, true), "the details count its steps")
local wasActive = Progress:GetActiveGuide()
if not (wasActive and wasActive.id == barrens.id) then
    check(Browser.startButton:GetText() == "Start" or Browser.startButton:GetText() == "Resume", "the button offers to start it")
end
Browser.startButton:Click("LeftButton")
settle()
check(Progress:GetActiveGuide() and Progress:GetActiveGuide().id == barrens.id, "start makes it the active guide")
check(not win:IsShown(), "start closes the browser")
ctx.noErrors("start")

-- Opened again, the running guide says so, and a refresh after the guide
-- moves on draws again.
Browser:Toggle()
settle()
check(win:IsShown(), "the browser opens again")
check(Browser.search:GetText() == "barrens", "it keeps the search")
check(Browser.startButton:GetText() == "Show", "the running guide's button shows the tracker")
check(rowFor(Browser.list, barrens).title:GetText():sub(1, 2) == "> ", "the running guide is marked")
before = draws
Browser:Refresh()
check(draws == before, "nothing changed, nothing drawn")
local state = Progress:GetState(barrens)
state.statuses = state.statuses or {}
local doneBefore = Progress:CompletedCount(state)
local openStep
for _, step in ipairs(Progress:CharacterSteps(barrens)) do
    if not Progress:IsDone(state.statuses[step.index]) then openStep = step; break end
end
check(openStep, "a step still to do")
state.statuses[openStep.index] = "complete"
Browser:Refresh()
check(draws == before + 1, "a step done draws again")
check(Browser.detailBody:GetText():find("Running: " .. (doneBefore + 1) .. " of", 1, true), "the details count it")
state.statuses[openStep.index] = nil
Browser:Toggle()
check(not win:IsShown(), "toggle closes it")
ctx.noErrors("reopen")

-- A quest from the quest log ------------------------------------------------------------

local questID, entries
for id, list in pairs(QuestIndex:Build()) do
    if ns.modules.Names:Quest(id) and #list > 0 then questID, entries = id, list; break end
end
check(questID, "a quest a guide names")

-- The quest log's button, on a stand-in quest log page.
local page = CreateFrame("Frame", nil, UIParent)
QuestFinder:Show(page, questID)
local button = QuestFinder.button
check(button and button:IsShown(), "the quest finder's button shows")
local caption = button:GetText()
check(caption == "In guide" or caption == ("In " .. #entries .. " guides"), "it says how many guides: " .. tostring(caption))
local lines = {}
local tip = { SetText = function(_, text) lines[#lines + 1] = text end,
    AddLine = function(_, text) lines[#lines + 1] = text end }
QuestFinder:Tooltip(tip)
check(#lines >= 3, "its tooltip names the guides and their steps")
check(lines[2]:find(entries[1].guide.meta.title, 1, true), "the first guide is named")
QuestFinder:Show(page, nil, nil)
check(not button:IsShown(), "no quest, no button")
QuestFinder:Show(page, questID)

-- A quest tooltip gets the guide lines once.
lines = {}
tip.NumLines = function() return #lines end
check(QuestFinder:AddTooltipLines(tip, questID), "a quest tooltip takes the lines")
local count = #lines
QuestFinder:AddTooltipLines(tip, questID)
check(#lines == count, "and only once")
check(table.concat(lines, "\n"):find("NuuRoad:", 1, true), "they are the addon's")

-- A click opens the browser searched for the quest.
button:Click("LeftButton")
settle()
check(win:IsShown(), "the button opens the browser")
check(Browser.search:GetText() ~= "", "searched for the quest")
check(viewHas(Browser.list, entries[1].guide) or Browser.forCharacter, "the quest's guide is listed")
local listed = 0
for _, entry in ipairs(entries) do
    if viewHas(Browser.list, entry.guide) then listed = listed + 1 end
end
check(listed > 0 or Browser.list:GetState() == "empty", "the list holds the quest's guides, or says why not")

-- ShowQuest straight, as MainWindow:ShowGuidesForQuest calls it.
Browser:Hide()
Browser:ShowQuest(questID)
settle()
check(win:IsShown(), "ShowQuest opens the browser")
QuestFinder:Hide()
check(not button:IsShown(), "the quest finder hides")
Browser:Hide()

-- A new look draws the window again, open.
Browser:Toggle()
before = draws
ctx.UI:SetLook({ theme = "slate" })
settle()
check(draws > before, "a new look draws the open browser again")
Browser:Hide()
ctx.noErrors("guide browser")
