local _, ns = ...

local Kit = ns.Kit

-- Development only, never shipped: every kit widget in every state, for
-- checking the kit in the client. `/nuukit ui` opens it. It has its own UI
-- and keeps its look for the session only.

local gallery

local GUIDES = {
    { name = "Northshire Valley", min = 1, max = 6 },
    { name = "Elwynn Forest", min = 6, max = 10 },
    { name = "Westfall", min = 10, max = 15 },
    { name = "Loch Modan", min = 10, max = 15 },
    { name = "Darkshore", min = 12, max = 17 },
    { name = "The Barrens", min = 12, max = 20, horde = true },
    { name = "Redridge Mountains", min = 15, max = 20 },
    { name = "Wetlands", min = 20, max = 25 },
    { name = "Duskwood", min = 20, max = 25 },
    { name = "Ashenvale", min = 20, max = 25 },
    { name = "Hillsbrad Foothills", min = 24, max = 30 },
    { name = "Stranglethorn Vale", min = 30, max = 35 },
    { name = "Arathi Highlands", min = 30, max = 35 },
    { name = "Desolace", min = 32, max = 38 },
    { name = "Dustwallow Marsh", min = 35, max = 40 },
    { name = "Tanaris", min = 40, max = 45 },
}

local FOLDERS = {
    { caption = "Alliance", count = 24, open = true, children = {
        { caption = "Eastern Kingdoms", count = 16, open = true, children = {
            { caption = "Elwynn Forest", count = 2 },
            { caption = "Westfall", count = 3 },
            { caption = "Dun Morogh", count = 2, children = { { caption = "Coldridge Valley", count = 1 } } },
        } },
        { caption = "Kalimdor", count = 8, children = { { caption = "Darkshore", count = 4 } } },
    } },
    { caption = "Professions", count = 9, children = { { caption = "Tailoring", count = 3 } } },
    { caption = "Dungeons", count = 5, children = { { caption = "The Deadmines", count = 1 } } },
}

local function lookTab(page, ui)
    local area = page:ScrollArea({ grow = true, gap = 14, padding = 4 })
    area:Text("The look picker every options window uses. It keeps nothing; this gallery forgets on reload.", "label", { wrap = true })
    area:LookPicker(ui:GetLook(), function(look) ui:SetLook(look) end)
end

local function controlsTab(page)
    local area = page:ScrollArea({ grow = true, gap = 14, padding = 4 })

    local buttons = area:Section("Buttons", { hint = "tones by styles" })
    for _, tone in ipairs({ "accent", "neutral", "success", "danger", "warning", "quest", "#f48cba" }) do
        local row = buttons:Row({ gap = 8 })
        row:Text(tone, "label", { width = 70 })
        for _, style in ipairs({ "solid", "soft", "outline", "ghost" }) do
            row:Button(style, { tone = tone ~= "neutral" and tone or nil, style = (tone == "neutral" and style == "solid") and "plate" or style })
        end
        row:Button("disabled", { tone = tone ~= "neutral" and tone or nil, disabled = "Nothing to do yet." })
    end
    local states = buttons:Row({ gap = 8 })
    local active = states:Button("Active", { active = true })
    active.kitClick = function(b) b:SetActive(not b:IsActive()) end
    states:ConfirmButton("Reset guide", { onConfirm = function() Kit.UI.gallery.win:Status("Guide reset.", { undo = function() end }) end })
    states:Button("Clear status", { style = "ghost", onClick = function() Kit.UI.gallery.win:Status(nil) end })
    states:Button("Hold to abandon", { tone = "danger", style = "outline", hold = 1.2,
        onClick = function() Kit.UI.gallery.win:Status("Abandoned.") end })
    states:Disclosure("Ways around", {})
    states:Link("Report a problem", { onClick = function() end })

    local glyphs = area:Section("Glyphs and attention")
    local row = glyphs:Row({ gap = 6 })
    for _, kind in ipairs({ "back", "next", "up", "down", "menu", "close", "plus", "minus" }) do
        row:GlyphButton(kind, { tooltip = kind })
    end
    local attract = glyphs:Row({ gap = 8 })
    for _, kind in ipairs({ "breathe", "pulse", "shimmer", "flash", "trail" }) do
        local target = attract:Button(kind, { tone = kind == "pulse" and "accent" or nil })
        target.kitClick = function(b) b:Attract(kind) end
    end
    attract:Button("Stop", { style = "ghost", onClick = function() if Kit.UI.gallery.win.kitAttracting then Kit.UI.gallery.win.kitAttracting:Attract(nil) end end })
    local together = glyphs:Row({ gap = 8 })
    for _, kinds in ipairs({ { "trail", "breathe" }, { "pulse", "shimmer" }, { "trail", "flash" } }) do
        local target = together:Button(table.concat(kinds, " + "))
        target.kitClick = function(b) b:Attract(kinds) end
    end

    local fields = area:Section("Fields")
    local line = fields:Row({ gap = 12 })
    line:Input({ label = "Guide name", width = 180, value = "Tailoring 112-225",
        validate = function(text) if text == "" then return "Give it a name." end end })
    line:Input({ label = "Level", width = 80, placeholder = "1 to 60", numeric = true })
    line:MoneyInput({ label = "Buy price, Silk Cloth", guess = 4100 })
    line:NumberInput({ label = "Target skill", value = 225, min = 113, max = 300 })
    local wrong = fields:Input({ label = "Shown invalid", width = 240, value = "32x" })
    wrong:SetInvalid(Kit.MoneyHint())
    fields:TextArea({ label = "What happened?", height = 80, maxLetters = 2000, placeholder = "Tell us what you saw." })
    local toggles = fields:Row({ gap = 18 })
    toggles:Toggle("Sell back what I make", { value = true })
    toggles:Toggle("Farm cloth myself")
    toggles:Toggle("Disabled", { disabled = true })
    fields:Slider({ label = "Undercut", value = 5, min = 0, max = 20, format = "%d%%", width = 260 })

    local menus = area:Section("Menus and selects")
    local selects = menus:Row({ gap = 12 })
    selects:Select({ label = "Route by", value = "few", default = "cheap", options = {
        { value = "cheap", caption = "Cheapest", desc = "Least gold spent, counting what you sell back." },
        { value = "few", caption = "Fewest crafts", desc = "Fewer clicks; may cost more." },
        { value = "farm", caption = "Least farming", desc = "Buy what you would otherwise gather." },
        { separator = true },
        { value = "bags", caption = "From my bags only", disabled = true, reason = "Needs a bank scan first." },
    } })
    local zones = {}
    for _, guide in ipairs(GUIDES) do zones[#zones + 1] = { value = guide.name, caption = guide.name } end
    selects:SearchSelect({ label = "Zone", value = "Westfall", options = zones })
    selects:MultiSelect({ label = "Sources", value = { vendor = true, ah = true }, options = {
        { header = "Buy from" }, { value = "vendor", caption = "Vendor" }, { value = "ah", caption = "Auction house" },
        { header = "Make or gather" }, { value = "craft", caption = "Craft" }, { value = "farm", caption = "Farm", desc = "Counts your time as free" },
    } })
    local menuButton = menus:Button("Right-click me, or click", { style = "outline" })
    local function openStepMenu(b, atCursor)
        b.ui:OpenMenu({
            { header = "Step 12" },
            { caption = "Go to this step", key = "Click" },
            { caption = "Mark done", key = "Shift-Click" },
            { separator = true },
            { caption = "Set waypoint", items = {
                { caption = "Kobold camp", desc = "Where most Vermin are" },
                { caption = "Nearest flight master", disabled = true, reason = "None in Northshire" },
            } },
            { caption = "Show on map", check = true, value = true },
            { header = "List shows" },
            { caption = "Next 10 steps", group = "list", value = "next" },
            { caption = "This section", group = "list", value = "section", checked = true },
            { separator = true },
            { caption = "Reset guide...", tone = "danger", desc = "Asks again before it forgets." },
        }, atCursor and { at = "cursor" } or { anchor = b })
    end
    menuButton.kitClick = function(b) openStepMenu(b, false) end
    menuButton:OnRightClick(function(b) openStepMenu(b, true) end)

    local text = area:Section("Text, tags and notices", { foldable = true })
    for _, style in ipairs({ "title", "window", "heading", "body", "label", "link", "fine", "number", "key" }) do
        text:Text(style .. ": Kill Kobold Vermin 6/10", style)
    end
    local tags = text:Row({ gap = 6 })
    tags:Tag("needs pattern", { tone = "#fa85c7" })
    tags:Tag("3 guessed", { tone = "estimate" })
    tags:Tag("done", { tone = "success" })
    text:Notice("Prices come from your last merchant and auction house visits.", { dismiss = true })
    text:Notice("3 prices are guesses, so the route may change once you set them.", { tone = "warning", action = { caption = "Set them" } })
    text:Notice("The Tailoring window closed before the scan finished.", { tone = "danger", action = { caption = "Scan again" } })
    text:Notice("Saved as the guide Tailoring 112-225.", { tone = "success" })
end

local function listsTab(page, ui)
    local panes = page:SplitPanes({
        { key = "places", width = 230, min = 160 },
        { key = "list", grow = true, min = 220 },
        { key = "details", width = 280, min = 200 },
    })
    panes.places:Tree({ nodes = FOLDERS, grow = true })
    local search = panes.list:Search({ placeholder = "Search guides" })
    local list = panes.list:List({
        grow = true, rowHeight = 26, search = search, empty = "No guides match.",
        make = function(row)
            row.name = row:Text("", "body", { grow = true })
            row.levels = row:Text("", "number", { width = 44, justify = "RIGHT" })
        end,
        draw = function(row, guide)
            row.name:SetText(guide.name)
            row.levels:SetText(guide.min .. "-" .. guide.max)
            row:SetDisabled(guide.horde, "Horde only")
        end,
        onPick = function(guide) Kit.UI.gallery.detail:SetText(guide.name) end,
        onActivate = function(guide) Kit.UI.gallery.win:Status("Started " .. guide.name .. ".") end,
    })
    list:SetItems(GUIDES)
    local states = panes.list:Row({ gap = 6 })
    states:Button("Loading", { style = "outline", onClick = function() list:SetState("loading", "Reading guides") end })
    states:Button("Error", { style = "outline", onClick = function()
        list:SetState("error", "4 guides failed to load.", { action = { caption = "Read again", onClick = function() list:SetState(nil) end } })
    end })
    states:Button("Back", { style = "ghost", onClick = function() list:SetState(nil) end })

    local area = panes.details:ScrollArea({ grow = true, gap = 10 })
    Kit.UI.gallery.detail = area:Text("Elwynn Forest", "title")
    area:Text("Levels 6-10, Alliance, 38 steps", "label")
    area:Text("From Northshire's gate to Goldshire and the farms around it: Fargodeep Mine, the Stonefield and Maclure feud, Jasperlode Mine, then on to Westfall.", "body", { wrap = true })
    area:ProgressBar({ label = "Your progress", value = 16, max = 38 })
    area:ProgressBar({ label = "Tailoring", value = 112, max = 300, marks = {
        { at = 150, caption = "cap 150" }, { at = 225, caption = "target 225", tone = "warning" } } })
    area:ProgressBar({ label = "Silk Cloth gathered", value = 64, max = 88, tone = "warning" })
    area:ProgressBar({ label = "Reading the merchant's list", busy = true })
    local buttons = area:Row({ gap = 8 })
    buttons:Button("Start guide", { tone = "accent", onClick = function() Kit.UI.gallery.win:Status("Started.", { undo = function() end }) end })
    buttons:Button("Open in editor")
end

local MATERIALS = {
    { caption = "Cloth", rows = {
        { name = "Linen Cloth", have = 40, need = 120, price = 10, get = "ah" },
        { name = "Wool Cloth", have = 12, need = 60, get = "ah", guess = 120 },
        { name = "Silk Cloth", have = 0, need = 80, price = 410, get = "farm" },
    } },
    { caption = "Thread and dye", open = false, rows = {
        { name = "Red Dye", have = 0, need = 10, price = 50, get = "vendor" },
        { name = "Gray Dye", have = 2, need = 12, price = 35, get = "vendor" },
    } },
    { caption = "From a vendor", rows = {
        { name = "Coarse Thread", have = 0, need = 40, price = 10, get = "vendor" },
        { name = "Fine Thread", have = 5, need = 35, price = 50, get = "vendor" },
    } },
}

local GET_IT = {
    { value = "ah", caption = "Buy on the AH" }, { value = "vendor", caption = "Vendor" },
    { value = "farm", caption = "Farm it myself" }, { value = "craft", caption = "Craft it" },
}

local function tablesTab(page, ui)
    local area = page:ScrollArea({ grow = true, gap = 14, padding = 4 })

    local plan = area:Section("Figures", { hint = "a plan in four numbers" })
    plan:Figures({
        { key = "cost", caption = "Cost", money = true, value = 124000 },
        { key = "sells", caption = "Sells", money = true, value = 81000, tone = "gain",
          tooltip = "What the crafts sell back for: 31 Gray Woolen Shirts to a vendor, the rest kept." },
        { key = "net", caption = "Net", money = true, signed = true, value = -43000 },
        { key = "crafts", caption = "Crafts", value = 186 },
    })

    local materials = area:Section("Table", { hint = "the planner's materials" })
    local search = materials:Search({ placeholder = "Search materials", width = 240 })
    local tableFrame = materials:Table({
        rows = 8, footer = true, search = search, empty = "No materials match.",
        columns = {
            { key = "name", caption = "Material", grow = true },
            { key = "have", caption = "Have", width = 50, align = "right", number = true },
            { key = "need", caption = "Need", width = 50, align = "right", number = true },
            { key = "price", caption = "Price used", width = 150, money = true,
              tooltip = "What each is costed at: your price if you typed one, else the vendor's, else a guess.",
              make = function(ui2, cell) return ui2:MoneyInput(cell, { width = 110 }) end,
              draw = function(field, item)
                  field:SetValue(item.price)
                  field:SetPlaceholder(item.guess and ("~" .. Kit.FormatMoney(item.guess) .. ", a guess") or "")
              end },
            { key = "get", caption = "Get it", width = 150,
              make = function(ui2, cell) return ui2:Select(cell, { width = 150, options = GET_IT }) end,
              draw = function(select, item) select:SetValue(item.get, true) end },
        },
        onPick = function(item) Kit.UI.gallery.win:Status("Picked " .. item.name .. ".") end,
    })
    tableFrame:SetItems(MATERIALS)
    tableFrame:SetFooter({ name = "9 materials", price = 182000 })

    local bars = area:Section("Segment bars", { hint = "the bar only: axes and captions are the addon's" })
    bars:Text("A guide's steps: done, skipped, where you are. Point for the step, click or drag to jump.", "label", { wrap = true })
    local STEPS = 58
    local stepBar
    local function stepSegments(current)
        return {
            { from = 0, to = 6, tone = "success" }, { from = 6, to = 8, tone = "#4a5566" },
            { from = 8, to = current - 1, tone = "success" }, { from = current - 1, to = current, tone = "accent" },
        }
    end
    stepBar = bars:SegmentBar({ min = 0, max = STEPS, height = 10,
        segments = stepSegments(14), marks = { { at = 13.5, kind = "pointer" } },
        tooltipFor = function(value) return "Step " .. math.min(STEPS, math.floor(value) + 1) .. ", click to jump there" end,
        scrub = true,
        onPick = function(value)
            local step = math.min(STEPS, math.floor(value) + 1)
            stepBar:SetSegments(stepSegments(math.max(9, step)))
            stepBar:SetMarks({ { at = step - 0.5, kind = "pointer" } })
            Kit.UI.gallery.win:Status("Jumped to step " .. step .. ".")
        end })

    bars:Text("A recipe's ranks, on one scale for every recipe: you at 132, the target at 150.", "label", { wrap = true })
    local function bands(orange, yellow, green, grey, stop)
        return {
            { from = orange, to = yellow, tone = "#cc855c" }, { from = yellow, to = green, tone = "#ccb861" },
            { from = green, to = grey, tone = "#70a870" }, { from = grey, to = stop, tone = "#4a5566" },
        }
    end
    local ranks = { { at = 132, tone = "text" }, { at = 150, tone = "accent" } }
    for _, recipe in ipairs({
        { "Gray Woolen Shirt", bands(100, 110, 125, 140, 170) },
        { "Bolt of Silk Cloth", bands(125, 135, 140, 145, 175) },
        { "Azure Silk Pants", bands(140, 150, 165, 180, 200) },
    }) do
        local line = bars:Row({ gap = 12 })
        line:Text(recipe[1], "body", { width = 150 })
        line:SegmentBar({ min = 100, max = 200, grow = true, segments = recipe[2], marks = ranks,
            tooltipFor = function(value) return "Rank " .. math.floor(value + 0.5) end })
    end
    local plan = bars:Row({ gap = 12 })
    plan:Text("The plan", "body", { width = 150 })
    plan:SegmentBar({ min = 100, max = 200, grow = true, height = 12, segments = {
        { from = 112, to = 125, tone = "accent", alpha = 0.6 }, { from = 125, to = 140, tone = "accent", alpha = 0.6 },
        { from = 140, to = 160, tone = "accent", style = "outline" },
    } })

    local pagers = area:Section("Pagers")
    local recipes = pagers:Pager({ noun = "Recipes", total = 132, pageSize = 20, at = 3, caption = "Page" })
    local choices = { "Kill the kobolds", "Go round the camp", "Skip it" }
    local choice
    choice = pagers:Pager({ caption = "Choice", count = #choices, at = 2,
        onAdd = function() choices[#choices + 1] = "New choice"; choice:SetCount(#choices); choice:SetAt(#choices) end,
        onDelete = function(at) table.remove(choices, at); choice:SetCount(#choices) end })
    pagers:Pager({ caption = "Step", count = 12, at = 4, words = true })

    local options = area:Section("Settings", { hint = "how routes are chosen",
        reset = { stored = true, default = "the kit's", onReset = function() Kit.UI.gallery.win:Status("All planning settings reset.") end } })
    local routeBy = options:Setting("Route by", { help = "What the planner keeps down: gold, clicks or farming." })
    routeBy:Select({ width = 200, value = "few", default = "cheap", options = {
        { value = "cheap", caption = "Cheapest" }, { value = "few", caption = "Fewest crafts" }, { value = "farm", caption = "Least farming" } } })
    local undercut = options:Setting("Undercut", { help = "How far under the lowest auction you would sell.",
        onReset = function(setting) setting:SetChanged(false) end })
    undercut:Slider({ value = 8, min = 0, max = 20, format = "%d%%", width = 200 })
    undercut:SetChanged(true)
    options:Setting("Count the bank", { help = "Take what is in the bank off what to buy." }):Toggle("On", { value = true })
    options:Setting("Goal", { help = "The rank to plan up to." }):NumberInput({ value = 150, min = 113, max = 300 })

    local kinds = area:Section("Choices", { hint = "the kind of a guide step" })
    kinds:Choices({ "Go to", "Kill", "Collect", "Talk", "Use", "Train", "Note" }, { value = "Kill", columns = 4 })

    local cards = area:Section("Cards")
    local row = cards:Row({ gap = 12, valign = "top" })
    local current = row:Card({ width = 320 })
    current:Text("Step 14, kill", "label")
    current:Text("Kobold Vermin", "heading")
    current:ProgressBar({ value = 6, max = 10, tone = "success" })
    current:Text("Most are at the kobold camp north of the abbey, past the lumber pile.", "label", { wrap = true })
    local actions = current:Row({ gap = 8 })
    actions:Button("Skip", { style = "outline" })
    actions:Button("Set waypoint", { style = "ghost" })
    local kept = row:Card({ width = 260, tone = "warning" })
    kept:Text("Kept on screen", "fine", { color = "warning" })
    kept:Text("Collect 8 Linen Cloth", "body")
    kept:Text("For the Gray Woolen Shirt quest, whenever it drops.", "label", { wrap = true })

    local lists = area:Section("List with a gutter and a value")
    local steps = lists:List({ rows = 4, numbers = function(step) return step.n end,
        value = function(step) return step.yards and (step.yards .. " yd") or "" end,
        make = function(r) r.caption = r:Text("", "body") end,
        draw = function(r, step) r.caption:SetText(step.text) end })
    steps:SetItems({
        { n = 12, text = "Talk to Deputy Willem" }, { n = 13, text = "Collect Milly's Harvest" },
        { n = 14, text = "Kill Kobold Vermin", yards = 120 }, { n = 15, text = "Turn in at the abbey", yards = 340 },
    })
end

local function inPlayTab(page, ui)
    page:Text("Frames over the world stay flat whatever the theme.", "label")
    local row = page:Row({ gap = 8 })
    row:Button("Tracker panel", { onClick = function()
        local g = Kit.UI.gallery
        if not g.panel then
            g.panel = ui:Panel({ key = "tracker", title = "Northshire Valley", width = 340, height = 180,
                resizable = "width", collapsible = true, point = { "RIGHT", UIParent, "RIGHT", -80, 0 } })
            local body = g.panel:Column({ padding = 10, gap = 4 })
            body:Text("Kill Kobold Vermin 6/10", "body", { color = "warning" })
            body:Text("Loot Tough Wolf Meat 8/8", "body", { color = "done" })
            body:Text("Turn in to Eagan Peltskinner", "body")
        end
        g.panel:Toggle()
    end })
    row:Button("Item strip", { onClick = function()
        local g = Kit.UI.gallery
        if not g.strip then
            g.strip = ui:StripPanel({ key = "items", title = "Items for this step", summary = "4" })
            g.strip:Slot({ item = 6948, key = "CTRL-5", quest = true })
            g.strip:Slot({ item = 2589, count = 14, key = "1" })
            g.strip:Slot({ item = 118, count = 3, key = "SHIFT-BUTTON4" })
            g.strip:Slot({ item = 2589, marker = 8 })
            local missing = g.strip:Slot({ item = 772, key = "2" })
            missing:SetMissing(true)
        end
        g.strip:SetShown(not g.strip:IsShown())
    end })
    row:Button("Full keyboard", { onClick = function()
        local win = Kit.UI.gallery.win
        win:TakeKeyboard(not win.kitKeyboard)
        win:Status(win.kitKeyboard and "The gallery holds the keyboard: Tab, Enter, arrows, Escape." or "Keyboard back to the game.")
    end })
end

local function open()
    Kit.UI.gallery = Kit.UI.gallery or {}
    local g = Kit.UI.gallery
    if g.win then g.win:Toggle(); return end
    local ui = Kit.NewUI({ name = "NuuKitGallery" }, g.look)
    g.ui = ui
    local win = ui:Window({ key = "gallery", title = "NuuKit gallery", subtitle = "every widget, every state",
        width = 900, height = 640, resizable = true, minWidth = 700, minHeight = 460,
        status = "What a change did shows here, with Undo." })
    g.win = win
    local tabs = win:Tabs({
        { key = "look", caption = "Look" },
        { key = "controls", caption = "Controls" },
        { key = "lists", caption = "Lists and panes" },
        { key = "tables", caption = "Tables and forms" },
        { key = "inplay", caption = "In play" },
    }, { pagePadding = 12 })
    lookTab(tabs:Page("look"), ui)
    controlsTab(tabs:Page("controls"))
    listsTab(tabs:Page("lists"), ui)
    tablesTab(tabs:Page("tables"), ui)
    inPlayTab(tabs:Page("inplay"), ui)
    win:Show()
end

if type(SlashCmdList) == "table" then
    SLASH_NUUKIT1 = "/nuukit"
    SlashCmdList.NUUKIT = function(message)
        if (message or ""):lower():match("^%s*ui") then open() else print("NuuKit: /nuukit ui opens the widget gallery.") end
    end
end
