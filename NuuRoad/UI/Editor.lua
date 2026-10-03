local _, ns = ...

-- The guide editor (docs/authoring.md): the whole guide as a step list on
-- the left, the selected step's form on the right, and the form's tabs in
-- the window's band: Step, Destination, Choices, Materials, Shown when and
-- Places (UI/PlacesPanel.lua). Coordinates are entered as map percentages,
-- the way guides and most coordinate sources print them, and stored
-- normalized.
--
-- Built from NuuKit's widgets. The
-- form is read back into the step all at once (ApplyFields) before anything
-- changes the guide or another step is shown, and drawn from the step all
-- at once (Render); the widgets stay put, only their text
-- and what is shown change. The window is made the first time it opens.
--
-- ApplyNPCs and ApplyGoal touch no frame: Tests/GuideEditingTests.lua runs
-- them outside the client.
local Editor = {}

local nodeKinds = {
    "action", "travel", "talk", "kill", "note", "choice", "end",
    "train", "skillTarget", "gather", "craft", "skillUp", "buy", "equip", "reputationTarget", "levelTarget", "cast",
}
-- The kinds whose goal is one named thing: what the four fields under the
-- type buttons ask for. A field with no label is hidden for that type.
local goalFields = {
    -- A profession by name, or class spells by ID ("100, 772"): the spells
    -- are done once the client knows them all, and the rank does not apply.
    train = { value = "Skill, or spell IDs", amount = "Rank (optional)", hint = "Mining, or 100, 772", amountHint = "75", label = "Train" },
    cast = { value = "Spell ID", amount = "Times (optional)", hint = "1259686", amountHint = "1", label = "Cast" },
    skillTarget = { value = "Skill", amount = "Rank", hint = "Mining", amountHint = "150", label = "Raise a skill" },
    craft = { value = "Item ID", amount = "Count", extra = "Profession (optional)", upto = "Or rank", hint = "2862", amountHint = "30", extraHint = "Blacksmithing", uptoHint = "100", label = "Craft" },
    skillUp = { value = "Item ID", amount = "Until rank", extra = "Profession", hint = "2862", amountHint = "100", extraHint = "Blacksmithing", label = "Craft for the skill" },
    gather = { value = "Item ID", amount = "Count", extra = "Profession (optional)", upto = "Or rank", hint = "2770", amountHint = "20", extraHint = "Mining", uptoHint = "Blacksmithing 100", label = "Gather" },
    buy = { value = "Item ID", amount = "Count", extra = "Profession (optional)", upto = "Or rank", hint = "2320", amountHint = "10", extraHint = "Blacksmithing", uptoHint = "100", label = "Buy" },
    equip = { value = "Item ID", hint = "7360", label = "Equip" },
    reputationTarget = { value = "Faction ID", amount = "Standing", hint = "576", amountHint = "Honored", label = "Reach a standing" },
    levelTarget = { value = "Level", amount = "XP into it (not with By step)", extra = "By step (optional)", hint = "14", amountHint = "10200", extraHint = "57", label = "Reach a level" },
}
local kindHints = {
    action = "Anything the player does by hand", travel = "Go somewhere; pairs with a destination", talk = "Speak with an NPC",
    kill = "Kill the creatures listed below; kills are counted from the combat log", note = "Information only",
    choice = "Branch: the player picks a route", ["end"] = "Closing text; the guide is complete",
    train = "Learn a skill, or its next rank, from a trainer; or class spells by ID",
    cast = "Cast a spell here; casts made while on the step are counted", skillTarget = "Raise a skill to a rank",
    craft = "Make a number of one item", skillUp = "Make one item over and over until a profession rank lands",
    gather = "Pick, mine, or skin a number of one item; the auction house is the other way to get it",
    buy = "Buy a number of one item from the vendor in the NPC field",
    equip = "Wear one item", reputationTarget = "Reach a standing with a faction",
    levelTarget = "Reach a level. With a step in By step, the turn-ins before that step count towards it, so the player grinds only what they will not bring",
}
local KIND_LABELS = { skillTarget = "Skill", reputationTarget = "Rep", skillUp = "Skill-up", levelTarget = "Level" }

-- The form's tabs, in the band, in order.
local TABS = {
    { key = "basic", caption = "Step" },
    { key = "navigation", caption = "Destination" },
    { key = "choices", caption = "Choices" },
    { key = "materials", caption = "Materials" },
    { key = "condition", caption = "Shown when" },
    { key = "places", caption = "Places" },
}

local WIDTH, HEIGHT, MIN_WIDTH, MIN_HEIGHT = 920, 640, 780, 480

local function Steps() return ns.modules.Steps end
local function Schema() return ns.modules.Schema end
local function Places() return ns.modules.PlacesPanel end

local function trim(text) return (tostring(text or ""):match("^%s*(.-)%s*$")) end

local function kindCaption(kind)
    kind = kind or "action"
    return KIND_LABELS[kind] or (kind:sub(1, 1):upper() .. kind:sub(2))
end

local function formatPercent(value)
    if type(value) ~= "number" then return "" end
    local text = string.format("%.2f", value * 100)
    return (text:gsub("%.?0+$", ""))
end

local function parsePercent(text)
    local value = tonumber(text)
    if not value then return nil end
    return value / 100
end

-- "3244, 3245 3246" -> { 3244, 3245, 3246 }
local function parseIDs(text)
    local ids = {}
    for token in tostring(text or ""):gmatch("%d+") do table.insert(ids, tonumber(token)) end
    return ids
end

local function joinIDs(ids)
    local parts = {}
    for _, id in ipairs(ids or {}) do table.insert(parts, tostring(id)) end
    return table.concat(parts, ", ")
end

-- "2840 x10 gather" (one per line) <-> the node's material list. An item ID
-- alone means one, gathered. A line the parser cannot read is reported and
-- the step's existing materials are kept rather than half-written.
local function parseMaterials(text)
    local list, bad = {}, nil
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            local itemID = tonumber(line:match("^(%d+)"))
            local count = tonumber(line:match("^%d+%s*[xX]?%s*(%d+)")) or 1
            local source = line:match("(%a+)%s*$")
            if source then source = source:lower() end
            if source == nil or source == "x" then source = "gather" end
            if not itemID or not Steps().materialSources[source] then
                bad = bad or line
            else
                table.insert(list, { itemID = itemID, count = count, source = source })
            end
        end
    end
    return list, bad
end

local function formatMaterials(needs)
    local lines = {}
    for _, material in ipairs(needs or {}) do
        table.insert(lines, material.itemID .. " x" .. material.count .. " " .. (material.source or "gather"))
    end
    return table.concat(lines, "\n")
end

-- The step and goal rules: no frames ------------------------------------------------------

-- A KILL step keeps its target list, count, and observed completion in step
-- with the NPC field; any other step only records the NPCs as references.
function Editor:ApplyNPCs(node, ids, count)
    if #ids > 0 then
        node.refs = node.refs or {}
        node.refs.npcs = ids
    elseif node.refs then
        node.refs.npcs = nil
        if next(node.refs) == nil then node.refs = nil end
    end
    if node.kind ~= "kill" or (node.auto and node.auto.verb == "objective") then
        if node.auto and node.auto.verb == "kill" then node.auto = nil; node.completion = { type = "manual" } end
        return
    end
    local wasGenerated = node.auto and node.auto.verb == "kill" and not node.customTitle
    node.auto = { verb = "kill", kill = ids, count = count }
    node.completion = { type = "observed", observed = { type = "kills", npcs = ids, count = count or 1 } }
    if wasGenerated or not node.customTitle then
        node.customTitle = nil
        node.title = #ids > 0 and Steps():Title(node, true) or (node.title or "Kill")
    end
end

-- The goal kinds keep their auto fields and observed completion in step with
-- the fields under the type buttons. A field left blank leaves the step with
-- no completion rule rather than a broken one, so it advances by hand.
local goalVerbs = { train = true, learn = true, cast = true, skill = true, craft = true, skillup = true, gather = true, buy = true, equip = true, reputation = true, level = true }

-- "100" (the profession beside it) or "Blacksmithing 100" (another one).
local function parseUpto(text, profession)
    local rank = tonumber(tostring(text or ""):match("(%d+)%s*$"))
    if not rank then return nil end
    local skill = tostring(text):match("^%s*(.-)%s*%d+%s*$")
    if skill == "" then skill = profession end
    if type(skill) ~= "string" or skill == "" then return nil end
    return { skill = skill, rank = rank }
end

function Editor:ApplyGoal(node, value, amount, extra, uptoText)
    local fields = goalFields[node.kind]
    if not fields then
        if node.auto and goalVerbs[node.auto.verb] then node.auto = nil; node.completion = { type = "manual" } end
        return
    end
    value, amount, extra = value or "", amount or "", extra or ""
    local wasGenerated = node.auto and goalVerbs[node.auto.verb] and not node.customTitle
    local number, amountNumber = tonumber(value), tonumber(amount)
    local auto, observed
    if node.kind == "train" and tostring(value):match("^[%d%s,]+$") and #parseIDs(value) > 0 then
        local spells = parseIDs(value)
        auto = { verb = "learn", spells = spells, trainer = node.refs and node.refs.npcs and node.refs.npcs[1] }
        observed = { type = "spell", ids = spells }
    elseif node.kind == "train" and value ~= "" then
        auto = { verb = "train", skill = value, rank = amountNumber }
        observed = { type = "skill", name = value, atLeast = amountNumber or 1 }
    elseif node.kind == "skillTarget" and value ~= "" and amountNumber then
        auto = { verb = "skill", skill = value, rank = amountNumber }
        observed = { type = "skill", name = value, atLeast = amountNumber }
    elseif node.kind == "craft" and number then
        auto = { verb = "craft", item = number, count = amountNumber, skill = extra ~= "" and extra or nil }
        observed = { type = "crafted", itemID = number, count = amountNumber or 1 }
    elseif node.kind == "skillUp" and number and amountNumber and extra ~= "" then
        auto = { verb = "skillup", item = number, skill = extra, rank = amountNumber }
        observed = { type = "skill", name = extra, atLeast = amountNumber }
    elseif node.kind == "gather" and number then
        auto = { verb = "gather", item = number, count = amountNumber, skill = extra ~= "" and extra or nil }
        observed = { type = "item", itemID = number, count = amountNumber or 1 }
    elseif node.kind == "buy" and number then
        auto = { verb = "buy", item = number, count = amountNumber, vendor = node.refs and node.refs.npcs and node.refs.npcs[1] }
        observed = { type = "item", itemID = number, count = amountNumber or 1 }
    elseif node.kind == "cast" and number then
        auto = { verb = "cast", spell = number, count = amountNumber }
        observed = { type = "cast", spellID = number, count = amountNumber or 1 }
    elseif node.kind == "equip" and number then
        auto = { verb = "equip", item = number }
        observed = { type = "equipped", itemID = number }
    elseif node.kind == "levelTarget" and number then
        -- `by` is a later step's number; the turn-ins before it count, and
        -- the level is the one needed there, so it takes no XP of its own.
        local by = tonumber(extra)
        local count = self.working and #self.working.nodes or 0
        if by and (by <= (node.index or 0) or by > count) then by = nil end
        local xp = not by and amountNumber or nil
        auto = { verb = "level", level = number, xp = xp, by = by }
        observed = { type = "level", atLeast = number, xp = xp, by = by }
    elseif node.kind == "reputationTarget" and number then
        local standing = ns.modules.Names:StandingValue(amount)
        if standing then
            auto = { verb = "reputation", faction = number, standing = standing }
            observed = { type = "reputation", factionID = number, standing = standing }
        end
    end
    -- The rank escape survives an edit even for the types whose form does not
    -- offer it, so a guide that authored one never loses it here.
    local escape = node.auto and node.auto.upto
    if fields.upto then escape = parseUpto(uptoText, extra) end
    if auto then
        if escape then
            auto.upto = escape
            observed = { type = "any", children = { observed, { type = "skill", name = escape.skill, atLeast = escape.rank } } }
        end
        node.auto, node.completion = auto, { type = "observed", observed = observed }
        if auto.item then
            node.refs = node.refs or {}
            node.refs.items = { auto.item }
        end
        if wasGenerated or not node.customTitle then
            node.customTitle = nil
            node.title = Steps():Title(node, true)
        end
    else
        node.auto, node.completion = nil, { type = "manual" }
        if node.title == nil or node.title == "" then node.title = fields.label end
    end
end

-- The window -------------------------------------------------------------------------------

local function stepMake(row)
    row.title = row:Text{ "", grow = true }
end

local function stepDraw(row, item)
    local editor = Editor
    local node = editor.working and editor.working.nodes[item.index]
    if not node then row.title:SetText(""); return end
    local title = Steps():Title(node, true)
    if title == "" then title = "(untitled)" end
    local prefix = node.kind == "choice" and "Y " or (node.kind == "end" and ". " or "")
    if Schema():GroupAt(editor.working, item.index) then prefix = "[G] " .. prefix end
    row.title:SetText(prefix .. title)
end

local function stepPicked(item) Editor:SelectStep(item.index) end
local function tabPicked(key) Editor:SelectTab(key) end
local function kindPicked(kind) Editor:SetKind(kind) end
local function kindOtherClicked() Editor:RenderKind() end
local function addStep() Editor:AddStep() end
local function deleteStep() Editor:DeleteStep() end
local function stepUp() Editor:MoveStep(-1) end
local function stepDown() Editor:MoveStep(1) end
local function groupNext() Editor:EditGroup(false) end
local function ungroup() Editor:EditGroup(true) end
local function choicePaged(at) Editor:SelectChoice(at) end
local function choiceAdded() Editor:AddChoice() end
local function choiceRemoved() Editor:RemoveChoice() end
local function saveClicked() Editor:Save() end
local function previewClicked() Editor:SaveAndPreview() end
local function cancelClicked() Editor:Hide() end

local function materialsScopeToggled(on)
    local editor = Editor
    if not editor.working then return end
    editor.working.meta.materials = on and "section" or nil
    editor:SetStatus("The materials list now covers " .. (on and "one section at a time." or "the whole guide ahead."))
end

local function windowHidden()
    local ui = ns:GetUI()
    ui:HideTooltip()
    local panel = Places()
    if panel then panel:DrawMap() end
end

-- A muted paragraph: hints and notes, secondary to the fields.
local function note(col, text)
    return col:Text{ text or "", style = "fine", color = "muted", wrap = true }
end

function Editor:BuildStepPane(pane)
    local head = pane:Row{ gap = 6 }
    head:Text{ "Steps", style = "label" }
    head:Spacer{}
    self.stepCount = head:Text{ "", style = "fine", color = "muted" }
    self.stepList = pane:List{ grow = true, rowHeight = 22, numbers = true, numberWidth = 30,
        make = stepMake, draw = stepDraw, onPick = stepPicked, empty = "No steps." }
    local buttons = pane:Row{ gap = 4 }
    buttons:Button{ "Add step", tone = "accent", onClick = addStep, tooltip = "Insert a new step after the selected one" }
    buttons:Button{ "Delete", onClick = deleteStep, tooltip = "Remove the selected step. Choices that led to it are removed too." }
    buttons:Button{ "Up", onClick = stepUp, tooltip = "Move the selected step up" }
    buttons:Button{ "Down", onClick = stepDown, tooltip = "Move the selected step down" }
end

function Editor:BuildStepTab(page)
    local area = page:ScrollArea{ grow = true, gap = 10, padding = 2 }
    self.stepTitle = area:Input{ label = "What the player does", placeholder = "One line, for example: Accept The Disruption Ends" }
    self.stepBody = area:TextArea{ label = "Details (optional)", boxHeight = 60,
        placeholder = "Where to find it, what to watch out for, why it matters" }

    area:Text{ "Type", style = "label" }
    local options = {}
    for index, kind in ipairs(nodeKinds) do
        options[index] = { value = kind, caption = kindCaption(kind), tooltip = kindHints[kind] }
    end
    options.columns, options.gap, options.onChange = 6, 4, kindPicked
    self.kindChoices = area:Choices(options)
    -- A kind the editor does not list (for example a cloned acceptQuest step)
    -- is shown on its own button so it is visible and never silently replaced.
    local other = area:Row{ gap = 6 }
    self.kindOther = other:Button{ "", width = 120, onClick = kindOtherClicked,
        tooltip = "This step's type comes from the original guide and is kept as-is" }
    self.kindOtherRow = other
    self.kindHint = note(area)

    -- NPCs of the step: marked in the world when seen; for a KILL step, the
    -- creatures whose kills are counted.
    local npcs = area:Row{ gap = 8 }
    self.npcIDs = npcs:Input{ label = "NPC IDs (comma separated)", grow = true,
        placeholder = "3448 for a quest giver, 3244, 3245 for targets" }
    self.killCount = npcs:Input{ label = "Kill count", width = 90, placeholder = "1" }

    -- What a skill, craft, buy, equip, or reputation step is about. The
    -- fields are relabelled per type and hidden for the types without one.
    local goal = area:Row{ gap = 8 }
    self.goalRow = goal
    self.goalValue = goal:Input{ label = "Skill", width = 170, placeholder = "Mining" }
    self.goalAmount = goal:Input{ label = "Rank", width = 120, placeholder = "150" }
    self.goalExtra = goal:Input{ label = "Profession", width = 150, placeholder = "Blacksmithing" }
    -- The rank that makes a materials step moot: "100" for the profession
    -- beside it, or "Blacksmithing 100" for another one.
    self.goalUpto = goal:Input{ label = "Or rank", width = 130, placeholder = "100" }

    local group = area:Row{ gap = 6, valign = "center" }
    group:Button{ "Group + next", onClick = groupNext, tooltip = "Group this quest visit with the next visit or group" }
    group:Button{ "Ungroup", onClick = ungroup, tooltip = "Make every member of this group a standalone step" }
    self.groupLabel = group:Text{ "", style = "fine", color = "muted" }

    -- How the step is carried: alongside a later one, or along with the ones
    -- after it. Both keep the guide from stopping on the step itself.
    local carried = area:Row{ gap = 8 }
    self.carriedWith = carried:Input{ label = "Carried alongside (step label, or 'next')", width = 240, placeholder = "next" }
    self.watchIDs = carried:Input{ label = "Watch for (NPC ID)", width = 140, placeholder = "3056" }
    self.waitSeconds = carried:Input{ label = "Wait (seconds)", width = 110, placeholder = "8" }
    -- The item the player presses on this step, which is not always the item
    -- the step counts.
    local use = area:Row{ gap = 10, valign = "center" }
    self.useItems = use:Input{ label = "Item to use (item IDs)", width = 170, placeholder = "4702" }
    use:Text{ "Put it in the item panel beside the tracker so the player can press it. It gates and completes"
        .. " nothing, and NuuRoad never presses it.", style = "fine", color = "muted", wrap = true, grow = true }
    self.sticky = area:Toggle{ "Keep this step up alongside the ones after it",
        tooltip = "The guide does not stop on it. It stays on the card under the current step until you have done it." }
    self.carriedNote = note(area)
    return area
end

function Editor:BuildDestinationTab(page)
    local area = page:ScrollArea{ grow = true, gap = 10, padding = 2 }
    area:Text{ "Destination (optional)", style = "label" }
    note(area, "Coordinates are map percentages, as shown by most coordinate addons and websites: 52.26, 31.93. Map ID 0"
        .. " means the player's current map. Leave everything blank for no destination.")
    local row = area:Row{ gap = 8 }
    self.mapID = row:Input{ label = "Map ID", width = 90, placeholder = "1413" }
    self.locationX = row:Input{ label = "X %", width = 90, placeholder = "52.26" }
    self.locationY = row:Input{ label = "Y %", width = 90, placeholder = "31.93" }
    self.radius = row:Input{ label = "Arrival radius %", width = 130, placeholder = "2 (default)" }
    self.locationNote = note(area)
    -- A step can stand on one of the guide's place points ("cave.chamber"),
    -- which fills the coordinates from it, or name the point its own
    -- coordinates are near, so the arrow knows which passage it is in.
    local points = area:Row{ gap = 8 }
    self.placePoint = points:Input{ label = "Or stand on a place point", width = 190, placeholder = "cave.chamber" }
    self.nearPoint = points:Input{ label = "Near a place point", width = 190, placeholder = "cave.chamber" }
    self.placeNote = note(area)
    return area
end

function Editor:BuildChoicesTab(page)
    local area = page:ScrollArea{ grow = true, gap = 10, padding = 2 }
    area:Text{ "Choices", style = "label" }
    note(area, "Each choice is a button in the tracker that jumps to the step number you enter. Adding a choice makes"
        .. " this a choice step.")
    local row = area:Row{ gap = 8 }
    self.choiceTitle = row:Input{ label = "Button text", grow = true, placeholder = "For example: Go to Ratchet first" }
    self.choiceTarget = row:Input{ label = "Jumps to step", width = 110, placeholder = "Step #" }
    self.choicePager = area:Pager{ caption = "Choice", count = 0, onChange = choicePaged, onAdd = choiceAdded,
        onDelete = choiceRemoved }
    return area
end

function Editor:BuildMaterialsTab(page)
    local area = page:ScrollArea{ grow = true, gap = 10, padding = 2 }
    area:Text{ "Materials this step needs", style = "label" }
    note(area, "One material per line: item ID, how many, and where it comes from - gather, vendor, ah, drop, or craft"
        .. " (gather if you leave it out). For example: 2840 x10 gather. Counts are for the whole step, not per item"
        .. " made. They add up into the materials list beside the tracker; nothing is bought, priced, or searched for you.")
    self.materials = area:TextArea{ boxHeight = 150, placeholder = "2840 x10 gather\n3466 x2 ah" }
    self.materialsNote = note(area)
    -- Guide-wide: the list covers the section the player is in, for a guide
    -- whose sections each start with their own shopping.
    self.materialsBySection = area:Toggle{ "The list shows only the current section (whole guide)",
        tooltip = "For a guide whose every section buys its own materials first. Off, the list adds up everything"
            .. " from here to the end of the guide.", onChange = materialsScopeToggled }
    return area
end

function Editor:BuildConditionTab(page)
    local area = page:ScrollArea{ grow = true, gap = 10, padding = 2 }
    area:Text{ "Who sees this step", style = "label" }
    note(area, "Leave this empty and every character sees the step. Otherwise name the conditions: a class, race, or"
        .. " faction (Warrior, Tauren, Horde), or a keyword - quest 858, season 2, level 10, skill Mining 75, item 2495"
        .. " x3, equipped 2495, spell 8017, gold 5000, zone 1412, profession Skinning, reputation 576 Honored, hardcore."
        .. " Write 'not' in front to turn one around. Terms joined by 'or' pass if any of them does; a bar between them"
        .. " means every part must pass, so 'not Warrior | not Druid' is neither of the two. 'now item 2495' is read as"
        .. " the guide arrives: without it the step is passed over, not waited on.")
    self.conditionText = area:Input{ placeholder = "Warrior or Shaman" }
    self.conditionLua = area:Input{ label = "Or a Lua expression, for what the keywords cannot say",
        placeholder = "level() >= 10 and itemCount(2495) == 0" }
    note(area, "One expression, not a script: no loops, no assignments, no globals. It reads the game through level(),"
        .. " class(), race(), faction(), questInLog(id), questFinished(id), questReady(id), itemCount(id), equipped(id),"
        .. " skill(name), standing(factionID), money(), zone(), season(), and api(name, ...) for a read this list has"
        .. " no helper for. Both fields apply together when both are filled. Prefer the keywords above: they show by"
        .. " name in the tracker and the audit, and this does not.")
    self.conditionNote = note(area)
    return area
end

function Editor:Build()
    if self.win then return end
    local ui = ns:GetUI()
    local db = ns.db
    local places = db and db.windows
    if not places then
        places = {}
        if db then db.windows = places end
    end
    local win = ui:Window({
        key = "editor", title = "Guide editor", width = WIDTH, height = HEIGHT,
        resizable = true, minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT, place = places,
        status = true, hidden = true,
    })
    win:HookScript("OnHide", windowHidden)
    self.win, self.frame = win, win

    -- The form's tabs in the band after the title, as a kit window's own
    -- tabs sit; their pages live in the form pane rather than the whole
    -- body, so the step list stays beside every tab.
    local header = win.header
    header:Spacer{ size = 24 }
    local entries = { value = "basic", onChange = tabPicked, rule = false }
    for index, tab in ipairs(TABS) do entries[index] = { key = tab.key, caption = tab.caption } end
    self.tabs = header:Tabs(entries)
    header:Spacer{}

    local panes = win:SplitPanes{
        { key = "steps", width = 270, min = 210 },
        { key = "form", grow = true, min = 460 },
        place = places, key = "editor.panes",
    }
    self:BuildStepPane(panes.steps)

    local form = panes.form
    local guideRow = form:Row{ gap = 8 }
    self.guideTitle = guideRow:Input{ label = "Guide title", grow = true, placeholder = "Name your guide" }
    -- Where the guide browser files it: folders split on "/", any depth.
    self.guideCategory = guideRow:Input{ label = "Folder", width = 210, placeholder = "Leveling/The Barrens",
        help = "Folders split on /, any depth" }
    form:Rule{}

    self.pages = {
        basic = self:BuildStepTab(form),
        navigation = self:BuildDestinationTab(form),
        choices = self:BuildChoicesTab(form),
        materials = self:BuildMaterialsTab(form),
        condition = self:BuildConditionTab(form),
    }
    local placesPage = form:Column{ grow = true, gap = 8 }
    self.pages.places = placesPage
    local panel = Places()
    if panel then
        panel:Build(self, placesPage)
    else
        note(placesPage, "The places tab is not available.")
    end

    local foot = form:Row{ gap = 6 }
    foot:Spacer{}
    foot:Button{ "Save", onClick = saveClicked, tooltip = "Validate and save this guide on this account" }
    foot:Button{ "Save and preview", tone = "accent", onClick = previewClicked,
        tooltip = "Validate, save, and follow this guide in the tracker" }
    foot:Button{ "Cancel", onClick = cancelClicked, tooltip = "Close without saving" }
    self:ShowPage(self.activeTab or "basic")
end

-- Status -----------------------------------------------------------------------------------

function Editor:SetStatus(text, isError)
    local win = self.win
    if not win then return end
    local opts = self.statusOpts or {}
    self.statusOpts = opts
    opts.tone = isError and "danger" or "text"
    win:Status(text ~= "" and text or nil, opts)
end

-- Tabs -------------------------------------------------------------------------------------

function Editor:ShowPage(tab)
    for key, page in pairs(self.pages or {}) do page:SetShown(key == tab) end
    if self.tabs and self.tabs:GetValue() ~= tab then self.tabs:SetValue(tab) end
end

function Editor:SelectTab(tab)
    self.activeTab = tab
    if not self.win then return end
    self:ShowPage(tab)
    if tab == "basic" and self.working then self:RenderKind() end
    if tab == "navigation" and self.working then self:RenderPlaceNote() end
    local panel = Places()
    if panel then
        if tab == "places" then panel:Render() else panel:DrawMap() end
    end
end

-- Kind -------------------------------------------------------------------------------------

function Editor:CurrentNode()
    return self.working and self.working.nodes[self.stepIndex]
end

function Editor:SetKind(kind)
    local node = self:CurrentNode()
    if not node then return end
    if Schema():GroupAt(self.working, self.stepIndex) and not Schema().groupKinds[kind] then
        self:SetStatus("Ungroup this step before changing its type.", true)
        self:RenderKind()
        return
    end
    -- The fields belong to the type that is on screen, so what the author
    -- typed is stored before the type changes under it.
    self:ApplyFields()
    node.kind = kind
    self:Render()
end

local function relabel(field, label, hint)
    field:SetLabel(label or "")
    field:SetPlaceholder(hint or "")
    field:SetShown(label ~= nil)
end

function Editor:RenderKind()
    local node = self:CurrentNode()
    if not node or not self.win then return end
    local listed = false
    for _, kind in ipairs(nodeKinds) do
        if node.kind == kind then listed = true end
    end
    self.kindChoices:SetValue(listed and node.kind or nil)
    self.kindOtherRow:SetShown(not listed)
    if not listed then
        self.kindOther:SetText(kindCaption(node.kind))
        self.kindOther:SetActive(true)
    end
    local fields = goalFields[node.kind]
    self.goalRow:SetShown(fields ~= nil)
    if fields then
        relabel(self.goalValue, fields.value, fields.hint)
        relabel(self.goalAmount, fields.amount, fields.amountHint)
        relabel(self.goalExtra, fields.extra, fields.extraHint)
        relabel(self.goalUpto, fields.upto, fields.uptoHint)
    end
    local hint = ""
    if fields then
        hint = "Completes when the game reports it done. The title is generated from these fields unless you change it."
    elseif node.kind == "kill" then
        hint = "Completes once the combat log shows the kill count reached. The title is generated from the NPC IDs and count unless you change it."
    elseif node.auto then
        hint = "This step's text is generated from quest and NPC IDs. Editing the title here overrides it."
    elseif node.completion and node.completion.type == "observed" then
        hint = "This step completes automatically when the game reports it done."
    end
    self.kindHint:SetText(hint)
    self.kindHint:SetShown(hint ~= "")
    self.killCount:SetShown(node.kind == "kill")
end

-- Reading the form back --------------------------------------------------------------------

function Editor:ApplyFields()
    local node = self:CurrentNode()
    if not node or not self.win then return end
    self.working.meta.title = self.guideTitle:GetText()
    local category = trim(self.guideCategory:GetText())
    self.working.meta.category = category ~= "" and category or "Personal"
    local title = self.stepTitle:GetText()
    -- A generated title stays generated until the author changes it; the IDs
    -- behind it (kill targets, tracked quests) are kept either way.
    if node.auto and title ~= Steps():Title(node, true) then node.customTitle = true end
    node.title = title
    node.body = self.stepBody:GetText()
    local count = tonumber(self.killCount:GetText())
    self:ApplyNPCs(node, parseIDs(self.npcIDs:GetText()), count and count >= 1 and math.floor(count) or nil)
    self:ApplyGoal(node, self.goalValue:GetText(), self.goalAmount:GetText(), self.goalExtra:GetText(), self.goalUpto:GetText())
    local mapID = tonumber(self.mapID:GetText())
    local x = parsePercent(self.locationX:GetText())
    local y = parsePercent(self.locationY:GetText())
    local radius = parsePercent(self.radius:GetText())
    local panel = Places()
    if panel then panel:ApplyFields() end
    local pointText = trim(self.placePoint:GetText())
    local nearText = trim(self.nearPoint:GetText())
    local standPlace, standPoint
    if pointText ~= "" then
        standPlace, standPoint = Steps().FindPlacePoint(self.working.places, pointText)
        if not standPlace then
            self:SetStatus("No place point '" .. pointText .. "'; write it as place.point, for example cave.chamber.", true)
            self.statusPinned = true
        end
    end
    if standPlace then
        -- The point is the place: its coordinates are the step's.
        mapID = standPoint.map or standPlace.map or mapID
        x, y = standPoint.at[1] / 100, standPoint.at[2] / 100
    end
    if mapID or x or y or radius then
        local location = node.location or {}
        location.mapID, location.x, location.y = mapID, x, y
        location.arrivalRadiusNormalized = radius
        location.point = standPlace and pointText or nil
        if nearText ~= "" and not Steps().FindPlacePoint(self.working.places, nearText) then
            self:SetStatus("No place point '" .. nearText .. "' to be near.", true)
            self.statusPinned = true
        else
            location.near = nearText ~= "" and nearText or nil
        end
        node.location = location
    else
        node.location = nil
    end
    node.watch = nil
    local watched = parseIDs(self.watchIDs:GetText())
    if #watched > 0 then
        node.watch = watched
        node.refs = node.refs or {}
        local npcs, seen = node.refs.npcs or {}, {}
        for _, id in ipairs(npcs) do seen[id] = true end
        for _, id in ipairs(watched) do if not seen[id] then table.insert(npcs, id) end end
        node.refs.npcs = npcs
    end
    node.use = nil
    local used = parseIDs(self.useItems:GetText())
    if #used > 0 then
        node.use = used
        node.refs = node.refs or {}
        local items, seenItem = node.refs.items or {}, {}
        for _, id in ipairs(items) do seenItem[id] = true end
        for _, id in ipairs(used) do if not seenItem[id] then seenItem[id] = true; table.insert(items, id) end end
        node.refs.items = items
    end
    local waitSeconds = tonumber(self.waitSeconds:GetText())
    node.wait = waitSeconds and waitSeconds > 0 and waitSeconds or nil
    node.sticky = self.sticky:GetValue() and true or nil
    -- The step this one is carried with, by label or by number. A target that
    -- does not resolve, or sits earlier, leaves the step as it was.
    local carriedText = self.carriedWith:GetText()
    if carriedText == nil or not carriedText:match("%S") then
        node.companionOf = nil
    else
        local target = tonumber(carriedText)
        if not target then
            for _, candidate in ipairs(self.working.nodes) do
                if candidate.label == carriedText then target = candidate.index end
            end
        end
        if target and self.working.nodes[target] and target > node.index then
            node.companionOf = target
        else
            self:SetStatus("No step after this one is called '" .. carriedText .. "'. The step keeps what it had.", true)
            self.statusPinned = true
        end
    end
    Steps():ApplyCarried(node)
    -- A condition that will not parse leaves the step with the one it had,
    -- rather than quietly dropping the gating and showing it to everyone.
    local readCondition, condition = pcall(Steps().ParseCondition, Steps(),
        self.conditionText:GetText(), self.conditionLua:GetText())
    if readCondition then
        node.condition = condition
    else
        self:SetStatus("Could not read that condition: " .. (tostring(condition):gsub("^.*NuuRoad: ", ""))
            .. ". The step keeps the condition it had.", true)
        self.statusPinned = true
    end
    local materials, badMaterial = parseMaterials(self.materials:GetText())
    if badMaterial then
        self:SetStatus("Could not read the material line '" .. badMaterial .. "'; the step keeps the materials it had.", true)
        self.statusPinned = true
    else
        node.needs = #materials > 0 and materials or nil
    end
    if node.choices and node.choices[self.choiceIndex] then
        local choice = node.choices[self.choiceIndex]
        choice.title = self.choiceTitle:GetText()
        local targetIndex = tonumber(self.choiceTarget:GetText())
        local target = targetIndex and self.working.nodes[targetIndex]
        choice["next"] = target and target.index or nil
    end
end

-- Drawing the form -------------------------------------------------------------------------

-- The guide's named points, under the place fields of the Destination tab;
-- drawn again when the tab shows, as the Places tab may have changed them.
function Editor:RenderPlaceNote()
    local named = {}
    for _, place in ipairs(self.working.places or {}) do
        for index, point in ipairs(place.points or {}) do
            if point.id then table.insert(named, place.place .. "." .. point.id)
            elseif point.label then table.insert(named, place.place .. "." .. index .. " (" .. point.label .. ")") end
        end
    end
    self.placeNote:SetText(#named > 0 and ("Points in this guide's places: " .. table.concat(named, ", ") .. ".")
        or "This guide has no places yet; the Places tab adds caves and tunnels.")
end

function Editor:RenderStepList()
    local nodes = self.working.nodes
    local items = self.stepItems or {}
    self.stepItems = items
    for index = 1, #nodes do
        local item = items[index] or {}
        item.index = index
        items[index] = item
    end
    for index = #items, #nodes + 1, -1 do items[index] = nil end
    self.stepList:SetItems(items, true)
    local selected = items[self.stepIndex]
    self.stepList:Select(selected)
    if selected then self.stepList:ScrollToItem(selected) end
    self.stepCount:SetText(#nodes .. (#nodes == 1 and " step" or " steps"))
end

-- Keeps the selected row inside the visible part of the list.
function Editor:ScrollToStep()
    local item = self.stepItems and self.stepItems[self.stepIndex]
    if item then self.stepList:ScrollToItem(item) end
end

function Editor:Render()
    local node = self:CurrentNode()
    if not node or not self.win then return end
    local Names = ns.modules.Names
    local group = Schema():GroupAt(self.working, self.stepIndex)
    self.groupLabel:SetText(group and ("Steps " .. group.first .. "-" .. group.last) or "Standalone")
    self.guideTitle:SetText(self.working.meta.title or "")
    self.guideCategory:SetText(self.working.meta.category or "")
    -- The title field edits the stored title; a note's display label is its body.
    self.stepTitle:SetText(node.kind == "note" and (node.title or "") or Steps():Title(node, true))
    self.stepBody:SetText(node.body or "")
    self.npcIDs:SetText(joinIDs(node.refs and node.refs.npcs))
    local killCount = node.auto and node.auto.verb == "kill" and node.auto.count
    self.killCount:SetText(killCount and tostring(killCount) or "")
    local auto = node.auto
    local goalValue, goalAmount, goalExtra = "", "", ""
    if auto and goalVerbs[auto.verb] then
        -- The craft verbs name an item and carry the profession separately;
        -- the skill verbs put the skill in the first field themselves.
        if auto.item then goalValue = tostring(auto.item); goalExtra = auto.skill or ""
        else goalValue = auto.skill or (auto.faction and tostring(auto.faction)) or "" end
        if auto.verb == "learn" then
            goalValue = joinIDs(auto.spells)
        elseif auto.verb == "cast" then
            goalValue, goalAmount = tostring(auto.spell), auto.count and tostring(auto.count) or ""
        elseif auto.verb == "level" then
            goalValue, goalAmount, goalExtra = tostring(auto.level), auto.xp and tostring(auto.xp) or "", auto.by and tostring(auto.by) or ""
        elseif auto.verb == "reputation" then goalAmount = Names:DescribeStanding(auto.standing)
        elseif auto.rank then goalAmount = tostring(auto.rank)
        elseif auto.count then goalAmount = tostring(auto.count) end
    end
    self.goalValue:SetText(goalValue)
    self.goalAmount:SetText(goalAmount)
    self.goalExtra:SetText(goalExtra)
    local escape = auto and auto.upto
    -- The profession is spelled out only when it differs from the one beside it.
    self.goalUpto:SetText(escape and ((escape.skill ~= goalExtra and (escape.skill .. " ") or "") .. escape.rank) or "")
    local location = node.location or {}
    self.mapID:SetText(location.mapID and tostring(location.mapID) or "")
    self.locationX:SetText(formatPercent(location.x))
    self.locationY:SetText(formatPercent(location.y))
    self.radius:SetText(formatPercent(location.arrivalRadiusNormalized))
    self.placePoint:SetText(location.point or "")
    self.nearPoint:SetText(location.near or "")
    self:RenderPlaceNote()
    local spots = location.spots and #location.spots or 0
    self.locationNote:SetText(spots > 0 and ("This step also has " .. spots .. " more points from the original guide,"
        .. " kept as they are; the arrow takes whichever is nearest.") or "")
    self.locationNote:SetShown(spots > 0)
    self.materials:SetText(formatMaterials(node.needs))
    self.materialsBySection:SetValue(self.working.meta.materials == "section")
    local needCount = node.needs and #node.needs or 0
    self.materialsNote:SetText(needCount == 0 and "This step asks for nothing. Materials from every step ahead add up into the list beside the tracker."
        or (needCount .. (needCount == 1 and " material" or " materials") .. " on this step, added to the list beside the tracker."))
    local carriedTarget = node.companionOf and self.working.nodes[node.companionOf]
    self.carriedWith:SetText(carriedTarget and (carriedTarget.label or tostring(node.companionOf)) or "")
    self.watchIDs:SetText(joinIDs(node.watch))
    self.useItems:SetText(joinIDs(node.use))
    self.waitSeconds:SetText(node.wait and tostring(node.wait) or "")
    self.sticky:SetValue(node.sticky and true or false)
    self.carriedNote:SetText(node.companionOf
        and ("Carried with step " .. node.companionOf .. ". The guide does not stop here; this step is done when that one is.")
        or (node.sticky and "Carried alongside the steps after it until it is done."
            or "A step of its own: the guide stops here."))
    self.conditionText:SetText(Steps():DescribeCondition(node.condition) or "")
    self.conditionLua:SetText(Steps():LuaCondition(node.condition) or "")
    self.conditionNote:SetText(node.condition
        and "This step is passed over for a character who does not meet it. A condition this client cannot judge counts as met, so a step is never hidden by a check that could not run."
        or "Every character sees this step.")
    local choiceCount = #(node.choices or {})
    self.choiceIndex = math.min(self.choiceIndex or 1, math.max(choiceCount, 1))
    local choice = node.choices and node.choices[self.choiceIndex]
    self.choiceTitle:SetText(choice and choice.title or "")
    local targetIndex = choice and choice["next"]
    self.choiceTarget:SetText(targetIndex and tostring(targetIndex) or "")
    self.choicePager:SetCount(choiceCount)
    self.choicePager:SetAt(self.choiceIndex)
    self.choiceTitle:SetEnabled(choice ~= nil)
    self.choiceTarget:SetEnabled(choice ~= nil)
    self:RenderStepList()
    if not self.statusPinned then
        self:SetStatus(self.isClone and "Editing a personal copy; the original guide is unchanged."
            or "Personal guide - saved on this account.")
    end
    self.statusPinned = false
    self:SelectTab(self.activeTab or "basic")
end

-- The player's actions ---------------------------------------------------------------------

function Editor:SelectStep(index)
    if not self.working or index < 1 or index > #self.working.nodes then return end
    self:ApplyFields()
    self.stepIndex = index
    self.choiceIndex = 1
    self:Render()
end

function Editor:AddStep()
    self:ApplyFields()
    self.stepIndex = ns.modules.GuideEditing:Insert(self.working, self.stepIndex)
    self.choiceIndex = 1
    self:Render()
end

function Editor:DeleteStep()
    self:ApplyFields()
    local ok, err = ns.modules.GuideEditing:Delete(self.working, self.stepIndex)
    if not ok then self:SetStatus(err, true); return end
    self.stepIndex = math.min(self.stepIndex, #self.working.nodes)
    self.choiceIndex = 1
    self:Render()
end

function Editor:MoveStep(direction)
    self:ApplyFields()
    local ok, err = ns.modules.GuideEditing:Move(self.working, self.stepIndex, direction)
    if not ok then self:SetStatus(err, true); return end
    self.stepIndex = self.stepIndex + direction
    self:Render()
end

function Editor:EditGroup(remove)
    self:ApplyFields()
    local Editing = ns.modules.GuideEditing
    local ok, err
    if remove then ok, err = Editing:Ungroup(self.working, self.stepIndex)
    else ok, err = Editing:GroupNext(self.working, self.stepIndex) end
    if not ok then self:SetStatus(err, true); return end
    self:Render()
end

function Editor:SelectChoice(index)
    local node = self:CurrentNode()
    if not node or not node.choices or index < 1 or index > #node.choices then return end
    self:ApplyFields()
    self.choiceIndex = index
    self:Render()
end

function Editor:AddChoice()
    self:ApplyFields()
    local node = self:CurrentNode()
    if not node then return end
    if Schema():GroupAt(self.working, self.stepIndex) then
        self:SetStatus("Ungroup this step before adding a choice.", true)
        return
    end
    local target = self.working.nodes[self.stepIndex + 1]
    if not target then
        self:SetStatus("Add another step first so the choice has somewhere to go.", true); self.statusPinned = true
        self:Render()
        return
    end
    node.choices = node.choices or {}
    table.insert(node.choices, { title = "New choice", ["next"] = target.index })
    node.kind = "choice"
    self.choiceIndex = #node.choices
    self:Render()
end

function Editor:RemoveChoice()
    self:ApplyFields()
    local node = self:CurrentNode()
    if not node or not node.choices or #node.choices == 0 then return end
    table.remove(node.choices, self.choiceIndex)
    if #node.choices == 0 then node.choices = nil end
    self.choiceIndex = math.max(1, self.choiceIndex - 1)
    self:Render()
end

function Editor:Save()
    self:ApplyFields()
    local title = self.working.meta.title or ""
    if #title == 0 or #title > 100 then
        self:SetStatus("Guide title must be between 1 and 100 characters.", true)
        return false
    end
    local valid, errors = ns.modules.GuideRepository:SaveUserGuide(self.working)
    if not valid then
        self:SetStatus("Cannot save: " .. (errors[1] or "invalid guide"), true)
        return false
    end
    ns.modules.Progress:Select(self.working)
    -- The tracker may already follow this very table: its places changed.
    local Route = ns.modules.TravelRoute
    if Route and Route.ForgetPlaces then Route:ForgetPlaces() end
    self.isClone = false
    self:SetStatus("Saved.")
    self:RenderStepList()
    return true
end

-- Save, and follow the guide in the tracker.
function Editor:SaveAndPreview()
    if not self:Save() then return false end
    self:Hide()
    local Main = ns.modules.MainWindow
    if Main and Main.Show then Main:Show() end
    return true
end

-- Opening ----------------------------------------------------------------------------------

function Editor:Show()
    self:Build()
    self.win:Show()
end

function Editor:Hide()
    if self.win then self.win:Hide() end
end

function Editor:IsShown()
    return self.win ~= nil and self.win:IsShown() or false
end

-- Shows the editor on what it had, or a new guide.
function Editor:Toggle()
    if self:IsShown() then return self:Hide() end
    if self.working then
        self:Show()
        self:Render()
    else
        self:OpenNew()
    end
end

function Editor:OpenNew()
    self:Build()
    local panel = Places()
    if panel then panel:Reset() end
    self.working = ns.modules.GuideRepository:CreateUserGuide()
    self.isClone = false
    self.stepIndex = 1
    self.choiceIndex = 1
    self.activeTab = "basic"
    self.win:Show()
    self:Render()
end

function Editor:OpenGuide(guide)
    if not guide then return self:OpenNew() end
    self:Build()
    local panel = Places()
    if panel then panel:Reset() end
    local Repository = ns.modules.GuideRepository
    if Repository.builtIns[guide.id] or Repository:IsSessionGuide(guide.id) then
        self.working = Repository:CloneToUserGuide(guide)
        self.isClone = true
    else
        self.working = Repository:CopyGuide(guide)
        self.isClone = false
    end
    Schema():IndexNodes(self.working)
    local state = ns.modules.Progress:PeekState(guide)
    self.stepIndex = state and state.currentStep or 1
    if self.stepIndex > #self.working.nodes then self.stepIndex = 1 end
    self.choiceIndex = 1
    self.activeTab = "basic"
    self.win:Show()
    self:Render()
end

ns:RegisterModule("Editor", Editor)
