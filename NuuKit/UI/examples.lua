-- How the UI kit should read from an addon: a sketch of the API in
-- docs/ui-kit/PLAN.md, written before any of it exists. Not in NuuKit.toc and
-- never loaded; every example is a function nothing calls, so the file only
-- has to parse. The names in it are the proposal to argue with.
--
-- The rules the examples follow:
--   one UI per addon, made once;
--   one call per widget, with the caption positional and everything else in
--   an options table;
--   a container makes widgets in itself and stacks them (col:Button(...));
--   the same callbacks everywhere: onClick(), onChange(value), onPick(item);
--   the kit reads no settings: the addon passes its own tables in.

local _, ns = ...

----------------------------------------------------------------------------
-- Setup: once, in the addon's Core.lua
----------------------------------------------------------------------------

local function Setup()
    -- `look` is the addon's own saved table, or nil for the defaults:
    -- { theme = "midnight", accent = nil, opacity = 1, textSize = "normal", reduceMotion = false }
    ns.UI = ns.Kit.NewUI(ns, NuuRoadDB.look)
end

----------------------------------------------------------------------------
-- A whole window
----------------------------------------------------------------------------

local function GuideBrowser(guides, startGuide)
    local UI = ns.UI

    -- Movable, clamped, closes on Escape. With `place` and `key` its position
    -- and size are kept in NuuRoadDB.windows.browser; the kit writes only
    -- there. Chrome (flat or art) comes from the look.
    local win = UI:Window({
        key = "browser",
        title = "Choose a guide",
        subtitle = "Level 8 Human Warrior",
        width = 520, height = 560,
        resizable = true, minWidth = 420, minHeight = 360,
        place = NuuRoadDB.windows,
    })

    local body = win:Column({ gap = 8, padding = 12 })

    local search = body:Search({ placeholder = "Search guides, zones, quests" })

    -- `draw` fills one row from one item; rows are made once and reused, so
    -- `make` (optional) builds what a row holds the first time.
    local list = body:List({
        grow = true,
        rowHeight = 30,
        search = search,  -- filters as the player types; arrow keys move the selection
        filter = function(guide, text) return guide.name:lower():find(text:lower(), 1, true) end,
        empty = "No guides match.",
        make = function(row)
            row.name = row:Text("", "body", { grow = true })
            row.levels = row:Text("", "number", { width = 44, justify = "right" })
        end,
        draw = function(row, guide)
            row.name:SetText(guide.name)
            row.levels:SetText(guide.min .. "-" .. guide.max)
            row.levels:SetColor(ns.LevelColor(guide.min))
            row:SetDisabled(not guide.forMe, "Horde only")
        end,
        onPick = function(guide) win.start:SetEnabled(guide.forMe) end,
        onActivate = startGuide,  -- double-click or Enter
    })

    local buttons = body:Row({ align = "right", gap = 8 })
    buttons:Button("Cancel", { onClick = function() win:Hide() end })
    win.start = buttons:Button("Start guide", {
        tone = "accent",
        onClick = function() startGuide(list:GetSelected()) end,
    })

    list:SetItems(guides)
    return win
end

----------------------------------------------------------------------------
-- The look
----------------------------------------------------------------------------

local function Looks(section)
    local UI = ns.UI

    -- The whole Appearance section of an options window: theme cards, accent
    -- swatches, class colour, chrome, opacity. It reports; the addon keeps.
    section:LookPicker(NuuRoadDB.look, function(look)
        NuuRoadDB.look = look
        UI:SetLook(look)  -- every widget this addon made repaints, open windows too
    end)

    -- A look can also be set in code, field by field.
    UI:SetLook({ theme = "slate", accent = "#6f9dff" })
    local look = UI:GetLook()

    -- The computed colours, for drawing the kit does not cover. `t.accent`,
    -- `t.muted`, `t.done` and the rest are { r, g, b } in 0..1.
    local t = UI.tokens

    -- Something the addon draws itself joins the repaint the same way: the
    -- painter runs now and again after every look change.
    local marker = section:GetFrame():CreateTexture(nil, "ARTWORK")
    UI:Paint(marker, function(tk) marker:SetColorTexture(tk.accent[1], tk.accent[2], tk.accent[3], 1) end)

    -- More themes, flat or with art. Every texture is optional; one that is
    -- missing or will not load is drawn flat from the colours.
    ns.Kit.UI.AddTheme("dusk", {
        name = "Dusk",
        window = "#141018", band = "#1a1520", hairline = "#2c2436",
        surface = "#18131d", raised = "#221b29", border = "#3e3350",
        text = "#ece6f2", muted = "#a497b3", accent = "#c08cff",
        art = {
            background = "dusk\\bg",      -- under Media\, tiled both ways
            frame = { file = "dusk\\frame", corner = 30 },
            band = "dusk\\band",
            plate = "dusk\\plate", platePrimary = "dusk\\plate_primary",
        },
    })
    return look, t
end

----------------------------------------------------------------------------
-- Layout and text
----------------------------------------------------------------------------

local function Layout(win)
    local body = win:Column({ gap = 10, padding = 16 })

    -- Text styles: title, window, heading, body, label, link, fine, number, key.
    -- Colours by token name.
    body:Text("Elwynn Forest", "title")
    body:Text("Levels 6-10, Alliance, 38 steps", "label")
    body:Text("From Northshire's gate to Goldshire and the farms around it.", "body", { wrap = true })
    body:Text("Guessed from vendor price", "fine", { color = "estimate" })

    -- Rows inside columns, fixed widths, a child that takes the spare room.
    -- A row's `align` packs it ("left", "center", "right"); its children are
    -- centred across it.
    local row = body:Row({ gap = 8 })
    row:Text("Route by", "label")
    row:Spacer()  -- pushes what follows to the right
    row:Select({ width = 150, options = { { value = "cheap", caption = "Cheapest" } }, value = "cheap" })

    body:Rule()  -- a hairline

    -- Anything custom: every widget is a plain frame, so SetPoint works.
    local badge = ns.UI:Tag(win, "3 guessed", { tone = "estimate" })
    badge:SetPoint("TOPRIGHT", win, "TOPRIGHT", -40, -12)
end

----------------------------------------------------------------------------
-- Sections and tabs
----------------------------------------------------------------------------

local function SectionsAndTabs(win)
    local body = win:Column({ padding = 16 })

    -- Tabs own their pages; a page is a column like any other.
    local tabs = body:Tabs({
        { key = "plan", caption = "Plan" },
        { key = "recipes", caption = "Recipes" },
        { key = "materials", caption = "Materials", badge = "3" },
        { key = "options", caption = "Options" },
    }, {
        grow = true,
        value = "plan",
        onChange = function(key) ns:Trace("planner", { event = "tab", tab = key }) end,
    })

    local plan = tabs:Page("plan")

    -- A section: a heading with a rule, a hint, actions at the right, and a
    -- body that folds. The section is itself a column.
    local route = plan:Section("Route", {
        hint = "9 legs to 225",
        foldable = true,
        open = true,
        onToggle = function(open) end,
    })
    route:Text("...", "body")

    -- The reset beside a changed setting: shown only while `stored` is true.
    local prices = plan:Section("Prices", { hint = "3 guessed", reset = {
        stored = true,
        default = "vendor prices",
        onReset = function() end,
    } })

    tabs:SetBadge("materials", nil)  -- clear the count
    tabs:Select("recipes")
    return prices
end

----------------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------------

local function Buttons(row)
    -- tone: accent, neutral (default), success, danger, warning, quest, or any colour.
    -- style: solid (default for accent), soft, outline, ghost; neutral defaults to its plate.
    row:Button("Start guide", { tone = "accent" })
    row:Button("Skip step")
    row:Button("Turn in", { tone = "success", style = "soft" })
    row:Button("Buy anyway", { tone = "warning", style = "outline" })
    row:Button("Summon", { tone = "#f48cba", style = "ghost" })

    -- A disabled button still shows its tooltip, which says why.
    local save = row:Button("Save as guide", {
        tooltip = "Keeps this route as a guide you can edit.",
        onClick = function() end,
    })
    save:SetEnabled(false, "Plan a route first.")

    -- Toggles in a group read as selected, not pressed.
    local mode = row:Button("Only mine", { onClick = function(self) self:SetActive(not self:IsActive()) end })

    -- For what cannot be undone: two clicks, or a hold.
    row:ConfirmButton("Reset guide", { onConfirm = function() end })          -- "Click again to reset"
    row:Button("Abandon", { tone = "danger", hold = 1.2, onClick = function() end })

    -- No plate: an arrow or menu mark inside a bar.
    local skip = row:GlyphButton("next", { tooltip = "Skip this step" })     -- next, back, menu, close, plus, minus
    skip:Attract("breathe")  -- pulse, shimmer, flash, trail; nil stops; off under reduceMotion
    skip:Attract(nil)
    return mode
end

----------------------------------------------------------------------------
-- Fields
----------------------------------------------------------------------------

local function Fields(col, prices)
    -- Commits on Enter, Tab or a click elsewhere; Escape puts the old text back.
    -- Fields in a window join its Tab order in the order they were made.
    col:Input({
        label = "Guide name",
        value = "Tailoring 112-225",
        onCommit = function(text) end,
        validate = function(text) if text == "" then return "Give it a name." end end,
    })

    col:TextArea({
        label = "What happened?",
        height = 150,
        maxLetters = 2000,  -- shows the count
        placeholder = "Tell us what you saw.",
        onChange = function(text) end,
    })

    -- Money is copper in and out; the player types "1g 20s 5c" or a number.
    col:MoneyInput({
        label = "Buy price, Silk Cloth",
        value = prices.silk,        -- nil shows the guess as a placeholder
        guess = 4100,
        onChange = function(copper) prices.silk = copper end,
    })

    col:NumberInput({ label = "Target skill", value = 225, min = 113, max = 300, step = 1, onChange = function(n) end })

    col:Toggle("Sell back what I make", { value = true, onChange = function(on) end })

    col:Slider({ label = "Undercut", value = 5, min = 0, max = 20, step = 1, format = "%d%%", onChange = function(v) end })

    -- Marks a field wrong until the player types again.
    local level = col:Input({ label = "Level", width = 80 })
    level:SetInvalid("Use a number from 1 to 60.")

    -- The kit formats money the same everywhere: 96s, not 0g 96s.
    local text = ns.Kit.FormatMoney(9600)       -- "96s"
    local copper = ns.Kit.ParseMoney("1g 20s")  -- 12000, or nil for a typo
    return text, copper
end

----------------------------------------------------------------------------
-- Menus and selects
----------------------------------------------------------------------------

local function Menus(col, stepRow, waypoints)
    local UI = ns.UI

    -- A select. With `default`, a player-set value gets the accent edge and a
    -- reset beside it.
    col:Select({
        label = "Route by",
        value = NuuProfessionsDB.routeBy,
        default = "cheap",
        options = {
            { value = "cheap", caption = "Cheapest", desc = "Least gold spent, counting what you sell back." },
            { value = "few", caption = "Fewest crafts", desc = "Fewer clicks; may cost more." },
            { separator = true },
            { value = "bags", caption = "From my bags only", disabled = true, reason = "Needs a bank scan first." },
        },
        onChange = function(value) NuuProfessionsDB.routeBy = value end,
    })

    -- Long lists: type to filter.
    col:SearchSelect({ label = "Zone", options = ns.ZoneOptions(), value = 40, onChange = function(zone) end })

    -- Several at once.
    col:MultiSelect({
        label = "Sources",
        options = {
            { header = "Buy from" },
            { value = "vendor", caption = "Vendor" },
            { value = "ah", caption = "Auction house" },
            { header = "Make or gather" },
            { value = "craft", caption = "Craft" },
            { value = "farm", caption = "Farm", desc = "Counts your time as free" },
        },
        value = { vendor = true, ah = true, craft = true },
        onChange = function(set) end,
    })

    -- A right-click menu at the cursor, with a submenu, checks and radios.
    stepRow:OnRightClick(function()
        UI:OpenMenu({
            { header = "Step 12" },
            { caption = "Go to this step", key = "Click", onClick = function() end },
            { caption = "Mark done", key = "Shift-Click", onClick = function() end },
            { separator = true },
            { caption = "Set waypoint", items = waypoints },  -- a submenu
            { caption = "Show on map", check = true, value = true, onChange = function(on) end },
            { separator = true },
            { caption = "Reset guide...", tone = "danger", desc = "Asks again before it forgets." },
        }, { at = "cursor" })
    end)

    -- Radio groups: the same `group` on each entry.
    UI:OpenMenu({
        { header = "List shows" },
        { caption = "Next 10 steps", group = "list", value = "next" },
        { caption = "This section", group = "list", value = "section", checked = true },
        { caption = "Whole guide", group = "list", value = "all" },
    }, { anchor = stepRow, onChange = function(group, value) end })
end

----------------------------------------------------------------------------
-- Trees, split panes, scroll areas
----------------------------------------------------------------------------

local function Panes(win, folders, onFolder)
    -- Panes side by side with drag bars between; widths go into `place`.
    local panes = win:SplitPanes({
        { key = "places", width = 270, min = 200 },
        { key = "list", grow = true, min = 280 },
        { key = "details", width = 380, min = 300 },
    }, { place = NuuRoadDB.windows, key = "browser.panes" })

    -- Nodes are { caption, count, children, open, value }; folders open and
    -- close themselves.
    panes.places:Tree({
        nodes = folders,
        grow = true,
        onPick = onFolder,
        onToggle = function(node, open) end,
    })

    -- Free-form content that scrolls, with the slim bar that hides when it fits.
    local area = panes.details:ScrollArea({ grow = true })
    local inside = area:Column({ gap = 10 })
    inside:Text("Elwynn Forest", "title")
    return panes
end

----------------------------------------------------------------------------
-- Progress, notices and states
----------------------------------------------------------------------------

local function Feedback(col, list, win)
    -- value / max, marks along it, tone for the fill.
    local skill = col:ProgressBar({
        label = "Tailoring", value = 112, max = 300,
        marks = { { at = 150, caption = "cap 150" }, { at = 225, caption = "target 225", tone = "warning" } },
    })
    skill:SetValue(113)

    col:ProgressBar({ label = "Silk Cloth gathered", value = 64, max = 88, tone = "warning" })
    local scan = col:ProgressBar({ label = "Reading the merchant's list", busy = true })  -- no end known
    scan:Hide()

    -- A notice in the flow of the window: info, warning, danger, success.
    col:Notice("3 prices are guesses, so the route may change once you set them.", {
        tone = "warning",
        action = { caption = "Set them", onClick = function() end },
        dismiss = true,
    })

    -- A list or any container can stand in a state instead of its content.
    list:SetState("loading", "Reading recipes from the Tailoring window")
    list:SetState("empty", "Open your Tailoring window once, so the planner can read what you know.")
    list:SetState("error", "4 recipes came back without reagents.", {
        action = { caption = "Read again", onClick = function() end },
    })
    list:SetState(nil)  -- back to the rows

    -- The strip at the foot of a window: what a change just did, with Undo.
    win:Status("Silk Cloth price set to 32s.", { undo = function() end })
end

----------------------------------------------------------------------------
-- In-play frames, slots, tooltips
----------------------------------------------------------------------------

local function InPlay()
    local UI = ns.UI

    -- Frames over the world: always flat and translucent, text shadowed,
    -- following the look's opacity. Same layout calls as a window.
    local tracker = UI:Panel({
        key = "tracker", inPlay = true,
        width = 360, resizable = "width",
        collapsible = true,  -- one line when collapsed
        place = NuuRoadDB.windows,
    })
    tracker:Column({ padding = 10 }):Text("Kill Kobold Vermin", "body")

    -- A strip of icon slots with a header plate the player drags.
    local strip = UI:StripPanel({ key = "items", title = "Items for this step", place = NuuRoadDB.windows })
    local slot = strip:Slot({
        item = 6948,       -- icon, quality edge and cooldown come from the item
        key = "C-5",       -- shortened to fit the corner
        count = 1,
        onClick = function() end,
    })
    slot:SetMissing(true)  -- not in the bags: dimmed, danger edge

    -- Any widget takes `tooltip` (a string, or a function that fills
    -- GameTooltip). For anything else:
    UI:Tooltip(slot, function(tip) tip:AddLine("Hearthstone") end, { links = { item = 6948 } })
end

----------------------------------------------------------------------------
-- Tables, pagers, figures, settings, choices and cards
----------------------------------------------------------------------------

local function Tables(col, materials)
    -- A plan's numbers side by side: money in coins, `signed` toned by sign.
    local figures = col:Figures({
        { key = "cost", caption = "Cost", money = true },
        { key = "net", caption = "Net", money = true, signed = true, tooltip = "What the route costs less what it sells for." },
    })
    figures:Set("cost", 124000)
    figures:Set("net", -43000)

    -- Columns with heads, rows made once and reused, groups ({ caption, rows })
    -- that fold, a footer. A column shows item[key], or `text(item)`, or
    -- holds a widget: `make` builds it once per row, `draw` fills it.
    local materialsTable = col:Table({
        rows = 10, footer = true, grow = true,
        columns = {
            { key = "name", caption = "Material", grow = true },
            { key = "need", caption = "Need", width = 50, align = "right", number = true },
            { key = "price", caption = "Price used", width = 140, money = true, tooltip = "Yours, else the vendor's, else a guess.",
              make = function(ui, cell) return ui:MoneyInput(cell, { width = 100 }) end,
              draw = function(field, item) field:SetValue(item.price) end },
        },
        onPick = function(item) end,
    })
    materialsTable:SetItems(materials)  -- { { caption = "Cloth", rows = { ... } }, ... }
    materialsTable:SetFooter({ name = "9 materials", price = 182000 })

    -- Pages of a long list, or one record of several.
    col:Pager({ noun = "Recipes", total = 132, pageSize = 20, onChange = function(page) end })
    col:Pager({ caption = "Choice", count = 3, onAdd = function() end, onDelete = function(at) end })

    -- An options row: name and help on the left, the control made in it.
    local setting = col:Setting("Undercut", { help = "How far under the lowest auction you would sell.",
        onReset = function(row) row:SetChanged(false) end })
    setting:Slider({ min = 0, max = 20, value = 8, format = "%d%%", width = 200 })
    setting:SetChanged(true)

    -- Buttons in even columns, one picked.
    col:Choices({ "Go to", "Kill", "Collect", "Talk" }, { value = "Kill", columns = 4, onChange = function(kind) end })

    -- A bar over a range with coloured runs and marks; the axis is the
    -- addon's, lined up with bar:XOf(value). Step i of n is i - 1 to i.
    local steps = col:SegmentBar({ min = 0, max = 58,
        segments = { { from = 0, to = 13, tone = "success" }, { from = 13, to = 14, tone = "accent" } },
        marks = { { at = 13.5, kind = "pointer" } },
        tooltipFor = function(value) return "Step " .. (math.floor(value) + 1) end,
        scrub = true, onPick = function(value) end })
    steps:SetMarks({ { at = 20.5, kind = "pointer" } })

    -- A raised card with a rail, holding a column.
    local card = col:Card({ tone = "accent" })
    card:Text("Kobold Vermin", "heading")
    card:ProgressBar({ value = 6, max = 10 })
end

----------------------------------------------------------------------------
-- Keyboard
----------------------------------------------------------------------------

local function Keyboard(win, a, b, c)
    -- By default Tab moves through the window's text fields, and arrows move
    -- through a list while its search field has focus. A custom order:
    win:TabOrder({ a, b, c })

    -- Opt in to full keyboard control of buttons, toggles and tabs. The
    -- window holds the keyboard while shown, so game keybinds stop until it
    -- closes.
    win:TakeKeyboard(true)
end

-- Hands the examples back, so nothing in the file is unused.
return {
    Setup, GuideBrowser, Looks, Layout, SectionsAndTabs, Buttons,
    Fields, Menus, Panes, Feedback, InPlay, Keyboard, Tables,
}
