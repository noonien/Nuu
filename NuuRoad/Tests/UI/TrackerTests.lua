-- The tracker (UI/MainWindow.lua), built from NuuKit on the kit's stand-in
-- for the client (Tests/UI/Harness.lua): the empty tracker, a packaged guide
-- started and drawn, back, skip, the list, the scrubber, the jump box, the
-- menu and each of its entries, a craft step's Make button with and without
-- NuuProfessions' API, the settings it shows, the tabs of the guides open,
-- hiding and showing, the width, and the minimap button. Nothing may reach the error handler, and the kit's
-- reset audit must find every change marked.
local ctx = dofile("Tests/UI/Harness.lua")
local ns, check, settle, frames = ctx.ns, ctx.check, ctx.settle, ctx.frames
local MainWindow = ns.modules.MainWindow
local Progress, Repository, Config = ns.modules.Progress, ns.modules.GuideRepository, ns.modules.Config
ctx.noErrors("load")

-- The strips beside the tracker are the panels suite's: here they only hear
-- that the step changed (their secure slots, named for key bindings, are
-- made in that suite, not this one).
local stripRefreshes = { NPCPanel = 0, ItemPanel = 0, MaterialsPanel = 0 }
local stripRefresh = {}
for name in pairs(stripRefreshes) do
    local module = ns.modules[name]
    if module then
        stripRefresh[name] = rawget(module, "Refresh")
        module.Refresh = function() stripRefreshes[name] = stripRefreshes[name] + 1 end
    end
end

-- Every text shown under `w` (a kit widget or holder), in order.
local function texts(w, out)
    out = out or {}
    if not w or not w:IsShown() then return out end
    if w.kitType == "Text" then out[#out + 1] = w:GetText() or "" end
    if (w.kitType == "Button" or w.kitType == "Link") and w.GetText then out[#out + 1] = w:GetText() or "" end
    local inner = w.kitInner or w
    for _, child in ipairs(inner.kitChildren or {}) do texts(child, out) end
    return out
end

local function has(list, pattern)
    for _, text in ipairs(list) do
        if string.find(text, pattern, 1, true) then return text end
    end
    return nil
end

-- The card's buttons, by caption.
local function buttons(w, out)
    out = out or {}
    if not w then return out end
    if w.kitType == "Button" and w:IsShown() then out[#out + 1] = w end
    local inner = w.kitInner or w
    for _, child in ipairs(inner.kitChildren or {}) do buttons(child, out) end
    return out
end

local function button(pattern)
    for _, b in ipairs(buttons(MainWindow.cardHolder)) do
        if string.find(b:GetText() or "", pattern, 1, true) then return b end
    end
    return nil
end

local function current()
    local guide = Progress:GetActiveGuide()
    local node = guide and Progress:GetCurrentNode(guide)
    return node and node.index or nil
end

-- A click the tracker takes: its own debounce reads a clock the stand-in
-- holds still, so each test click is a fresh one.
local function click(widget, mouse)
    MainWindow.lastAction = nil
    widget:Click(mouse)
    settle()
end

-- The menu's row whose entry has `caption`.
local function menuRow(menu, caption)
    for index = 1, menu.count or #menu.rows do
        local row = menu.rows[index]
        if row and row:IsShown() and row.item and row.item.caption and string.find(row.item.caption, caption, 1, true) then
            return row
        end
    end
    return nil
end

-- The guide's own menu, from a right-click on its name in the band.
local function openGuideMenu()
    ctx.UI:CloseMenu()
    MainWindow.frame.band:Fire("OnMouseUp", "RightButton")
    settle()
    local menu = ctx.UI.kitMenu
    check(menu and menu:IsShown(), "a right-click on the band opens the guide's menu")
    return menu
end

local function openMenu()
    ctx.UI:CloseMenu()
    click(MainWindow.menuButton)
    local menu = ctx.UI.kitMenu
    check(menu and menu:IsShown(), "the menu opens from its button")
    return menu
end

-- The empty tracker -------------------------------------------------------------------

local win = MainWindow.frame
check(win and win.kitIsWindow, "the tracker is a kit window")
check(win:IsShown(), "the tracker shows at login (tracker.shown)")
check(Progress:GetActiveGuide() == nil, "no guide yet")
check(has(texts(MainWindow.cardHolder), "Choose a guide to begin."), "the empty tracker asks for a guide")
check(not MainWindow.skip:IsShown() and not MainWindow.back:IsShown(), "no back or skip without a guide")
check(win.title:GetText() == "No guide selected", "the band says no guide")
check(not MainWindow.bar:IsShown(), "no progress bar without a guide")
do
    local Browser = ns.modules.GuideBrowser
    local browse = button("Browse guides")
    check(browse, "the empty tracker has a button for the guide browser")
    if Browser:IsShown() then Browser:Hide() end
    click(browse)
    check(Browser:IsShown(), "the button opens the guide browser")
    Browser:Hide()
end

-- A packaged guide ----------------------------------------------------------------------

local guide = Repository:Get("nuuroad:leveling:horde-mulgore-1-6")
check(guide, "the Mulgore 1-6 guide is packaged")
Progress:Select(guide)
MainWindow:Refresh()
settle()
ctx.noErrors("start a guide")
local first = current()
check(first, "the guide has a current step")
check(MainWindow.counter:GetText():find("^" .. first .. " / " .. #guide.nodes), "the counter shows the step")
check(MainWindow.skip:IsShown() and MainWindow.back:IsShown() and MainWindow.counter:IsShown(), "back, counter and skip show")
check(string.find(win.title:GetText() or "", guide.meta.title:sub(1, 6), 1, true), "the band names the guide")
local cardTexts = texts(MainWindow.cardHolder)
check(#cardTexts > 0, "the card has lines")
check(MainWindow.card ~= nil, "the step card is open")
check(win:GetHeight() >= 95, "the tracker is sized to its content")
check(MainWindow.list ~= nil and #MainWindow.list:GetItems() > 0, "the step list is filled")
check(MainWindow.list:GetSelected() == Progress:GetCurrentNode(guide), "the list's selection is the current step")
local total = #MainWindow:CharacterSteps(guide)
local _, maxValue = MainWindow.bar:GetRange()
check(MainWindow.bar:IsShown(), "a guide brings the bar back")
check(maxValue == total, "the bar spans the character's steps")

-- A refresh builds from the pools: no new frames once warm.
MainWindow:Refresh(); settle()
local before = #frames.objects
MainWindow:Refresh(); settle()
check(#frames.objects == before, "a refresh makes no new frames (" .. (#frames.objects - before) .. " made)")

-- The tooltips of the card's lines and of a list row draw.
for _, row in ipairs(MainWindow.list.rows) do
    if row:IsShown() and row.item then
        local filler = MainWindow:ListTooltip(row.item)
        filler(GameTooltip)
        break
    end
end
ctx.noErrors("tooltips")

for name, count in pairs(stripRefreshes) do
    if ns.modules[name] then check(count > 0, "a refresh tells the " .. name .. " (" .. count .. ")") end
end

-- Back and skip -------------------------------------------------------------------------

click(MainWindow.skip)
local afterSkip = current()
check(afterSkip and afterSkip > first, "skip moves forward (" .. tostring(first) .. " -> " .. tostring(afterSkip) .. ")")
check(MainWindow.counter:GetText():find("^" .. afterSkip .. " / "), "the counter follows skip")
click(MainWindow.skip)
local twice = current()
check(twice and twice > afterSkip, "skip again")
click(MainWindow.back)
check(current() < twice, "back moves back")
ctx.noErrors("back and skip")

-- Done on a step nothing in the game finishes.
for _ = 1, 20 do
    if button("Done - next step") or not current() then break end
    click(MainWindow.skip)
end
local done = button("Done - next step")
if done then
    local at = current()
    click(done)
    check(current() ~= at, "done moves the guide on")
end
check(done, "a step nothing in the game finishes has a Done button")
-- A purchase is finished by buying, so it has no Done button; its card
-- offers a skip instead, recorded as skipped.
do
    local buy
    for _, node in ipairs(guide.nodes) do
        if node.kind == "buy" and node.index > current() then buy = node break end
    end
    check(buy, "the Mulgore guide has a purchase to skip")
    if buy then
        Progress:GoTo(guide, buy.index)
        MainWindow:Refresh(); settle()
        local skipBuy = button("Skip - I do not need it")
        check(skipBuy and not button("Done - next step"), "a buy step offers skip, not done")
        -- Proven work past the purchase settles it, but the guide still sits
        -- on it, so the card keeps its skip.
        local GuideScan = ns.modules.GuideScan
        local settled = GuideScan.Settled
        GuideScan.Settled = function() return true end
        MainWindow:Refresh(); settle()
        check(button("Skip - I do not need it"), "a settled purchase still offers skip")
        GuideScan.Settled = settled
        MainWindow:Refresh(); settle()
        skipBuy = button("Skip - I do not need it")
        if skipBuy then
            click(skipBuy)
            check(current() ~= buy.index, "the card's skip moves the guide on")
            check(Progress:GetState(guide).statuses[buy.index] == "skipped", "the purchase is recorded as skipped")
        end
    end
end
-- Back near the start for what follows.
Progress:GoTo(guide, first)
Progress:Forward(guide)
Progress:Forward(guide)
MainWindow:Refresh(); settle()

-- The list ------------------------------------------------------------------------------

do
    local target
    for _, row in ipairs(MainWindow.list.rows) do
        if row:IsShown() and row.item and row.item.index < current() then target = row end
    end
    check(target, "the list shows a step before the current one")
    do
        local index = target.item.index
        click(target)
        check(current() == index, "a click on a list row moves the guide there")
        check(MainWindow.list:GetSelected() == Progress:GetCurrentNode(guide), "the selection follows")
    end
end
ctx.noErrors("list")

-- The scrubber ---------------------------------------------------------------------------

do
    -- On the bar, as the cursor would be: the stand-in's cursor stands 200
    -- units into the bar.
    local bar = MainWindow.bar
    local value = bar:ValueAt(200)
    local number, _, node = MainWindow:ScrubIndex(value)
    check(number and node, "the bar maps the cursor to a step")
    bar.scripts.OnMouseDown(bar, "LeftButton")
    bar.scripts.OnMouseUp(bar, "LeftButton")
    MainWindow:Refresh(); settle()
    check(current() == node.index, "scrubbing moves the guide to the step under the cursor")
    local filler = MainWindow:ScrubTooltip(value)
    check(type(filler) == "function" and MainWindow:ScrubTooltip(value) == filler, "one tooltip per step, kept")
    filler(GameTooltip)
    -- Hovering follows the cursor, the tooltip included.
    bar.scripts.OnEnter(bar)
    bar.scripts.OnLeave(bar)
end
ctx.noErrors("scrub")

-- The jump box --------------------------------------------------------------------------

do
    click(MainWindow.counter)
    check(MainWindow.jumpOpen and MainWindow.jump:IsShown(), "the counter opens the jump box")
    check(not MainWindow.counter:IsShown() and not MainWindow.back:IsShown(), "the box stands where the counter was")
    local box = MainWindow.jump.box
    box:SetText("3")
    box.scripts.OnEnterPressed(box)
    settle()
    local steps = MainWindow:CharacterSteps(guide)
    local expected
    for _, candidate in ipairs(steps) do
        if candidate.index >= 3 then expected = candidate.index; break end
    end
    check(current() == expected, "the jump box moves to step 3 (" .. tostring(current()) .. ")")
    check(not MainWindow.jumpOpen and not MainWindow.jump:IsShown(), "the box closes after a jump")
    check(MainWindow.counter:IsShown(), "the counter is back")
    -- Opened and left: it goes when it loses the keyboard.
    click(MainWindow.counter)
    check(MainWindow.jumpOpen, "the box opens again")
    MainWindow.jump:ClearFocus()
    frames.tick()
    check(not MainWindow.jumpOpen, "the box goes when it loses focus")
    -- A number out of range keeps the guide where it is.
    click(MainWindow.counter)
    local at = current()
    box:SetText("9999")
    box.scripts.OnEnterPressed(box)
    check(current() == at, "an out-of-range number moves nothing")
    MainWindow:HideJumpBox()
end
ctx.noErrors("jump box")

-- The refresh throttle -------------------------------------------------------------------

do
    local count = 0
    local refresh = MainWindow.Refresh
    MainWindow.Refresh = function(self) count = count + 1; return refresh(self) end
    for _ = 1, 5 do MainWindow:RequestRefresh() end
    frames.tick()
    check(count == 0, "a request waits for the throttle")
    for _ = 1, 3 do frames.tick() end
    check(count == 1, "five requests make one refresh (" .. count .. ")")
    MainWindow.Refresh = refresh
end

-- The menu ------------------------------------------------------------------------------

do
    local menu = openMenu()
    for _, caption in ipairs({ "Guides", "Authoring", "Report a bug", "Options" }) do
        check(menuRow(menu, caption), "the menu has " .. caption)
    end
    for _, caption in ipairs({ "Edit", "Reset progress", "Close" }) do
        check(not menuRow(menu, caption), "the menu leaves " .. caption .. " to the guide's menu")
    end
    click(MainWindow.menuButton)
    check(not menu:IsShown(), "a second click on the button closes it")

    -- Each entry, taken; the other modules may still be placeholders.
    for _, caption in ipairs({ "Guides", "Report a bug", "Options" }) do
        menu = openMenu()
        click(menuRow(menu, caption))
        check(not menu:IsShown(), caption .. " closes the menu")
        ctx.noErrors("menu: " .. caption)
    end
    local Browser = ns.modules.GuideBrowser
    if Browser and Browser.Hide then Browser:Hide() end
    local Options = ns.modules.Options
    if Options and Options.win and Options.win.Hide then Options.win:Hide() end

    -- The guide's own menu, under its name.
    menu = openGuideMenu()
    for _, caption in ipairs({ "Edit", "Reset progress", "Close" }) do
        check(menuRow(menu, caption), "the guide's menu has " .. caption)
    end
    local titled = false
    for index = 1, menu.count or #menu.rows do
        local row = menu.rows[index]
        local guide = Progress:GetActiveGuide()
        if row and row:IsShown() and row.item and row.item.header == (guide.meta and guide.meta.title or guide.id) then titled = true end
    end
    check(titled, "the guide's menu is headed by its name")
    click(menuRow(menu, "Edit"))
    check(not menu:IsShown(), "Edit closes the menu")
    ctx.noErrors("guide menu: Edit")
    if ns.modules.Editor and ns.modules.Editor.Hide then ns.modules.Editor:Hide() end

    -- The authoring submenu.
    for _, caption in ipairs({ "Session log", "Place recorder", "Diagnostics" }) do
        menu = openMenu()
        local row = menuRow(menu, "Authoring")
        row.scripts.OnEnter(row)
        local sub = menu.sub
        check(sub and sub:IsShown(), "Authoring opens its submenu")
        click(menuRow(sub, caption))
        ctx.noErrors("menu: " .. caption)
        ctx.UI:CloseMenu()
    end
    -- What the entries opened is put away, for the suites after this one.
    local modules = ns.modules
    if modules.RecordingPanel and modules.RecordingPanel.win and modules.RecordingPanel.win:IsShown() then modules.RecordingPanel:Hide() end
    if modules.PlaceRecorder and modules.PlaceRecorder.win and modules.PlaceRecorder.win:IsShown() then modules.PlaceRecorder:Toggle() end
    if modules.Options and modules.Options.diagnostics and modules.Options.diagnostics:IsShown() then modules.Options.diagnostics:Hide() end
    if modules.BugReportPanel and modules.BugReportPanel.Hide then modules.BugReportPanel:Hide() end
    if modules.Options and modules.Options.Hide then modules.Options:Hide() end

    -- Reset asks twice.
    click(MainWindow.skip)
    local moved = current()
    menu = openGuideMenu()
    local row = menuRow(menu, "Reset progress")
    click(row)
    check(menu:IsShown(), "the first click keeps the menu open")
    check(menuRow(menu, "Sure? Click again"), "and asks again")
    check(current() == moved, "nothing is reset yet")
    click(menuRow(menu, "Sure? Click again"))
    check(not menu:IsShown(), "the second click closes the menu")
    check(current() <= first, "the guide is back at its start (" .. tostring(current()) .. ")")
    -- The next opening is disarmed again.
    menu = openGuideMenu()
    check(menuRow(menu, "Reset progress"), "a new opening is not armed")
    ctx.UI:CloseMenu()

    -- The planner is NuuProfessions' own to open; the menu has no entry for it.
    _G.NuuProfessions = { API = { apiVersion = 1, Open = function() end } }
    menu = openMenu()
    check(not menuRow(menu, "Profession planner"), "no planner entry, even with NuuProfessions")
    ctx.UI:CloseMenu()
    _G.NuuProfessions = nil
end
ctx.noErrors("menu")

-- A craft step's Make button --------------------------------------------------------------

do
    local fixture = Repository:Get("nuuroad:fixture:professions")
    check(fixture, "the profession fixture is packaged")
    local craft, skillup
    for _, node in ipairs(fixture.nodes) do
        local auto = node.auto
        if auto and auto.verb == "craft" and not craft and not auto.upto then craft = node end
        if auto and auto.verb == "skillup" and not skillup then skillup = node end
    end
    check(craft and skillup, "the fixture has a craft and a skill-up step")

    -- Without NuuProfessions: one made per craft, no recipe to count by.
    local order = MainWindow:MakeOrder(craft)
    check(order and order.count == (craft.auto.count or 1), "a craft step makes what its count asks for")
    check(order.spell == nil and order.profession == craft.auto.skill, "without the planner, no spell")
    local up = MainWindow:MakeOrder(skillup)
    check(up and up.count == math.huge and up.untilSkill == skillup.auto.rank, "a skill-up makes until its skill")

    Progress:Select(fixture)
    Progress:GoTo(fixture, craft.index)
    MainWindow:Refresh(); settle()
    check(current() == craft.index, "the craft step is current")
    local make = MainWindow.makeState and button(craft.auto.skill)
    check(make, "the card has the Make button")
    check(MainWindow.makeState.mode == nil and not make:IsEnabled(), "with the profession closed the button says why")
    ctx.noErrors("craft step, no planner")

    -- With the planner's API: its recipe counts what a craft makes.
    local asked
    _G.NuuProfessions = { API = { apiVersion = 1,
        Recipe = function(profession, spell, item)
            asked = profession
            return { makes = item, made = { 2, 2 }, reagents = { { 2835, 1 } }, skills = { 1, 50, 60, 70 } }, 3116
        end,
        Skills = function() return nil end,
        CarriedCrafts = function() return nil end,
        Open = function() end,
    } }
    order = MainWindow:MakeOrder(craft)
    check(asked == craft.auto.skill, "the tracker asks the planner for the recipe")
    check(order.count == math.ceil((craft.auto.count or 1) / 2), "two made per craft halves the crafts (" .. order.count .. ")")
    check(order.spell == 3116, "the planner's spell is used")
    MainWindow:Refresh(); settle()
    check(button(craft.auto.skill), "the Make button shows with the planner")

    -- The window open on the recipe: the button makes a batch.
    local Client = ns.modules.Client
    local findCraft, craftCall, canOpen = Client.FindCraft, Client.Craft, Client.CanOpenProfession
    local made
    Client.FindCraft = function() return { available = 10, api = "trade" } end
    Client.Craft = function(_, profession, spell, item, count) made = count; return true end
    MainWindow:Refresh(); settle()
    make = button("Make ")
    check(make and make:IsEnabled(), "an open window makes a batch: " .. tostring(make and make:GetText()))
    click(make)
    check(made == order.count, "Make orders the step's crafts")
    -- Closed, but the tracker can open it.
    Client.FindCraft = function() return nil, "closed" end
    Client.CanOpenProfession = function() return true end
    local openedOn
    local openProfession = Client.OpenProfession
    Client.OpenProfession = function(_, profession) openedOn = profession end
    MainWindow:Refresh(); settle()
    make = button("Open " .. craft.auto.skill)
    check(make and make:IsEnabled(), "a closed window opens on the recipe")
    click(make)
    check(openedOn == craft.auto.skill, "the button opens the profession")
    Client.FindCraft, Client.Craft, Client.CanOpenProfession, Client.OpenProfession = findCraft, craftCall, canOpen, openProfession
    _G.NuuProfessions = nil
    MainWindow:Refresh(); settle()
end
ctx.noErrors("craft step")

-- Settings -------------------------------------------------------------------------------

do
    Progress:Select(guide)
    MainWindow:Refresh(); settle()
    Config:Set("stepList.rows", 3)
    settle()
    check(MainWindow.listRows == 3, "the list follows stepList.rows")
    Config:Set("stepList.rows", 0)
    settle()
    check(MainWindow.list == nil and not MainWindow.listHolder:IsShown(), "zero rows puts the list away")
    Config:Reset("stepList.rows")
    settle()
    check(MainWindow.list ~= nil, "the list comes back")
    Config:Set("tracker.scale", 1.2)
    Config:Reset("tracker.scale")
    Config:Set("tracker.markWaiting", true)
    for _ = 1, 4 do frames.tick() end
    Config:Reset("tracker.markWaiting")
    Config:SetRealmSetting("auctionHouse", true)
    Config:Reset("realm.auctionHouse")
    settle()
end
ctx.noErrors("settings")

-- Growing upward: the band at the foot, the parts above it in reverse, the
-- bottom edge held while the height changes.
do
    local frame, content = MainWindow.frame, MainWindow.content
    local function order()
        local at = {}
        for index, child in ipairs(content:GetChildren()) do at[child] = index end
        return at
    end
    Config:Set("tracker.upward", true)
    settle()
    check(frame:IsUpward(), "the setting turns the tracker upward")
    local at = order()
    check(at[MainWindow.listHolder] < at[MainWindow.cardHolder] and at[MainWindow.cardHolder] < at[MainWindow.stickyHolder]
        and at[MainWindow.stickyHolder] < at[MainWindow.bar] and at[MainWindow.bar] < at[MainWindow.tabRow],
        "upward, the list is on top and the tabs sit on the band")
    -- The stand-in does not resolve anchors: the points are what is checked.
    check(frame.band:GetPoint(1) == "BOTTOMLEFT", "the band is at the foot")
    check(frame:GetPoint(1) == "BOTTOMLEFT", "the tracker is held by its bottom edge")
    Config:Set("stepList.rows", 12)
    settle()
    check(frame:GetPoint(1) == "BOTTOMLEFT", "and still is after it grows")
    Config:Reset("stepList.rows")
    Config:Reset("tracker.upward")
    settle()
    check(not frame:IsUpward(), "reset, it grows down again")
    at = order()
    check(at[MainWindow.tabRow] < at[MainWindow.bar] and at[MainWindow.bar] < at[MainWindow.listHolder], "and the parts are back in order")
    check(frame.band:GetPoint(1) == "TOPLEFT" and frame:GetPoint(1) == "TOPLEFT", "the band is back on top")
end
ctx.noErrors("upward")

-- The tabs -------------------------------------------------------------------------------

do
    -- The craft fixture and the Mulgore guide are both open by now.
    local fixture = Repository:Get("nuuroad:fixture:professions")
    local row = MainWindow.tabRow
    local function strip() return row:IsShown() and row.kitChildren[1] or nil end
    Progress:Select(guide)
    MainWindow:Refresh(); settle()
    local tabs = strip()
    check(tabs and tabs.kitType == "Tabs", "two guides open show the strip")
    check(row.kitChildren[1] == tabs and MainWindow.content.kitChildren[1] == row, "the strip heads the tracker's body")
    check(tabs:GetValue() == guide.id and tabs.kitTabs[fixture.id] ~= nil, "a tab for each, the shown guide chosen")
    check(tabs.kitTabs[guide.id].label:GetText() == "Camp Narache", "the caption is the title: " .. tostring(tabs.kitTabs[guide.id].label:GetText()))
    check(tabs.kitTabs[guide.id].tooltip == guide.meta.title, "the tooltip names the whole guide")
    local fixtureTab = tabs.kitTabs[fixture.id]
    check(fixtureTab.divider and fixtureTab.divider:IsShown(), "a hairline divides the tabs")
    check(fixtureTab.closeButton:GetAlpha() == 0, "a tab's close mark waits for the pointer")
    fixtureTab:Fire("OnEnter")
    check(fixtureTab.closeButton:GetAlpha() == 1, "and shows under it")
    fixtureTab:Fire("OnLeave")
    -- A right-click on a tab not shown opens that guide's menu, and shows no other.
    click(fixtureTab, "RightButton")
    local sheet = ctx.UI.kitMenu
    check(sheet and sheet:IsShown() and sheet.rows[1].item.header == fixture.meta.title,
        "a right-click on a tab opens its guide's menu")
    check(Progress:GetActiveGuide() == guide, "and does not choose the tab")
    ctx.UI:CloseMenu()
    local at = current()
    click(tabs.kitTabs[fixture.id])
    check(Progress:GetActiveGuide() == fixture and strip():GetValue() == fixture.id, "a tab shows its guide, and the strip follows")
    check(string.find(win.title:GetText() or "", fixture.meta.title:sub(1, 6), 1, true), "the band names it")
    click(strip().kitTabs[guide.id])
    check(Progress:GetActiveGuide() == guide and current() == at, "back to the first guide, where it was")
    -- Switching tabs once warm makes no frames.
    local made = #frames.objects
    click(strip().kitTabs[fixture.id])
    click(strip().kitTabs[guide.id])
    check(#frames.objects == made, "a switch builds from the pools: " .. (#frames.objects - made) .. " new")
    ctx.noErrors("tabs")

    -- More guides than fit: the shown one keeps its tab, the rest go behind "+N".
    local extra = {}
    for _, id in ipairs({ "nuuroad:leveling:horde-tirisfal-1-6", "nuuroad:leveling:horde-barrens-13-21",
        "nuuroad:leveling:horde-mulgore-6-12" }) do
        local other = Repository:Get(id)
        check(other, id .. " is packaged")
        table.insert(extra, other)
        Progress:Select(other)
    end
    MainWindow:Refresh(); settle()
    local last = extra[#extra]
    tabs = strip()
    local more = row.kitChildren[2]
    check(#tabs.kitOrder == 3 and tabs:GetValue() == last.id, "three tabs fit, the shown guide's among them: " .. #tabs.kitOrder)
    check(more and more.kitType == "Link" and more:GetText() == "+2", "the rest behind +2")
    local right = tabs.kitPX + tabs.kitPW
    check(more.kitPX >= right and more.kitPX + more.kitPW <= win:GetWidth() - 10, "+2 fits at the end of the strip")
    for _, key in ipairs(tabs.kitOrder) do
        local tab = tabs.kitTabs[key]
        check(tab.kitPW <= 170 and tab.label:GetText():sub(-3) == "..." or #tab.label:GetText() < 20, "a tab cut to share the width")
    end
    click(more)
    local menu = ctx.UI.kitMenu
    check(menu and menu:IsShown() and menuRow(menu, extra[1].meta.title), "+2 lists the guides without a tab")
    click(menuRow(menu, extra[1].meta.title))
    check(Progress:GetActiveGuide() == extra[1] and strip().kitTabs[extra[1].id] ~= nil, "one picked there is shown, with a tab")
    ctx.noErrors("tabs: more")

    -- Shutting tabs: one not shown, then the shown one, then by the menu.
    for _, other in ipairs(extra) do
        if other ~= extra[1] then Progress:Close(other) end
    end
    Progress:Close(fixture)
    MainWindow:Refresh(); settle()
    check(#strip().kitOrder == 2 and not row.kitChildren[2], "two left, no +N")
    click(strip().kitTabs[guide.id].closeButton)
    check(Progress:GetActiveGuide() == extra[1] and not Progress:IsOpen(guide), "the mark shuts a tab not shown")
    check(not row:IsShown(), "one guide open has no strip")
    click(menuRow(openGuideMenu(), "Close"))
    check(Progress:GetActiveGuide() == nil and #Progress:OpenIDs() == 0, "the guide's menu shuts the last guide")
    check(has(texts(MainWindow.cardHolder), "Choose a guide to begin."), "and the tracker asks for one")
    ctx.UI:CloseMenu()
    MainWindow.frame.band:Fire("OnMouseUp", "RightButton")
    check(not (ctx.UI.kitMenu and ctx.UI.kitMenu:IsShown()), "with no guide the band opens no menu")
    Progress:Select(guide)
    MainWindow:Refresh(); settle()
    check(Progress:GetCurrentIndex(guide) == at and not row:IsShown(), "opened again where it was, alone")
end
ctx.noErrors("tabs")

-- The width ------------------------------------------------------------------------------

do
    local lineWidth = MainWindow.lineWidth
    win:SetWidth(520)
    for _ = 1, 4 do frames.tick() end
    settle()
    check(MainWindow.lineWidth > lineWidth, "a wider tracker lays its lines out wider")
    win:SetWidth(360)
    for _ = 1, 4 do frames.tick() end
    settle()
end
ctx.noErrors("width")

-- Hiding and showing ---------------------------------------------------------------------

click(MainWindow.close)
check(not win:IsShown(), "close hides the tracker")
check(Config:Get("tracker.shown") == false, "and remembers it")
MainWindow:Toggle()
settle()
check(win:IsShown() and Config:Get("tracker.shown") == true, "toggle shows it again")
ctx.noErrors("toggle")

-- The minimap button -----------------------------------------------------------------------

do
    if not rawget(_G, "Minimap") then
        local minimap = CreateFrame("Frame", nil, UIParent)
        minimap:SetSize(140, 140)
        minimap.GetCenter = function() return 170, 430 end
        _G.Minimap = minimap
    end
    local launcher = MainWindow:CreateLauncher()
    check(launcher, "the minimap button is made")
    Config:Set("minimap.angle", 90)
    local point = launcher:GetNumPoints() > 0 and { launcher:GetPoint(1) }
    check(point and math.abs(point[4]) < 0.01 and point[5] > 0, "the button stands at its angle")
    Config:Reset("minimap.angle")
    launcher.scripts.OnClick(launcher, "LeftButton")
    check(not win:IsShown(), "a left click hides the tracker")
    launcher.scripts.OnClick(launcher, "LeftButton")
    settle()
    check(win:IsShown(), "and shows it again")
    launcher.scripts.OnEnter(launcher)
    launcher.scripts.OnLeave(launcher)
end
ctx.noErrors("launcher")

-- Last: the guide cleared, the empty tracker again, then every card back to
-- the pools, so the audit sees the releases.
Progress:Deselect()
MainWindow:Refresh(); settle()
check(has(texts(MainWindow.cardHolder), "Choose a guide to begin."), "no guide again")
check(not MainWindow.bar:IsShown(), "and the bar goes with it")
MainWindow:BeginCards()
settle()
for name, refresh in pairs(stripRefresh) do ns.modules[name].Refresh = refresh end
-- Showing the tracker again stored that it is open; the suites after this
-- one start from nothing stored.
Config:Reset("tracker.shown")
ctx.noErrors("tracker")
